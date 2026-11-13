/**
 * Engine-unit seam: summary computation over in-memory Table rows (no SOQL, no records).
 */
@IsTest
private class BoardTableEngineTest {
    private static Map<String, Object> row(Object amount) {
        return new Map<String, Object>{ 'Amount' => amount };
    }

    @IsTest
    static void summarizesSumAverageMinAndMaxIgnoringBlanks() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            row(10),
            row(null),
            row(-4.5),
            row(30.5),
            new Map<String, Object>()
        };

        BoardTableEngine.Summary summary = BoardTableEngine.summarize(rows, 'Amount');

        assertNumber(36, summary.value('SUM'), 'Sum adds the non-blank values');
        assertNumber(12, summary.value('AVG'), 'Average divides by the non-blank count');
        assertNumber(-4.5, summary.value('MIN'), 'Min is the smallest value');
        assertNumber(30.5, summary.value('MAX'), 'Max is the largest value');
        Assert.areEqual(3, summary.count, 'Blank cells are not counted');
    }

    /** Numeric comparison that ignores Decimal scale (`12` vs `12.0`). */
    private static void assertNumber(Decimal expected, Decimal actual, String message) {
        Assert.isTrue(actual != null && actual == expected, message + ': expected ' + expected + ', got ' + actual);
    }

    @IsTest
    static void dataBarsApplyToNumberCurrencyAndPercentFieldsOnly() {
        for (
            Schema.DisplayType numeric : new List<Schema.DisplayType>{
                Schema.DisplayType.INTEGER,
                Schema.DisplayType.LONG,
                Schema.DisplayType.DOUBLE,
                Schema.DisplayType.CURRENCY,
                Schema.DisplayType.PERCENT
            }
        ) {
            Assert.isTrue(BoardTableEngine.isDataBarType(numeric.name()), numeric + ' can be a Data bar');
        }
        for (
            Schema.DisplayType other : new List<Schema.DisplayType>{
                Schema.DisplayType.STRING,
                Schema.DisplayType.DATE,
                Schema.DisplayType.BOOLEAN,
                Schema.DisplayType.REFERENCE
            }
        ) {
            Assert.isFalse(BoardTableEngine.isDataBarType(other.name()), other + ' cannot be a Data bar');
        }
    }

    @IsTest
    static void preAggregatedChunksMergeIntoOneSummary() {
        BoardTableEngine.Summary summary = new BoardTableEngine.Summary();
        summary.addAggregate(30, 2, 10, 20);
        summary.addAggregate(null, 0, null, null);
        summary.addAggregate(-6, 2, -8, 2);

        assertNumber(24, summary.value('SUM'), 'Chunk sums add up');
        assertNumber(6, summary.value('AVG'), 'Average divides by the merged non-blank count');
        assertNumber(-8, summary.value('MIN'), 'Smallest chunk min');
        assertNumber(20, summary.value('MAX'), 'Largest chunk max');
        Assert.areEqual(4, summary.count, 'A chunk without values adds nothing');
    }

    @IsTest
    static void summaryOfNoValuesIsBlank() {
        BoardTableEngine.Summary summary = BoardTableEngine.summarize(
            new List<Map<String, Object>>{ row(null) },
            'Amount'
        );

        for (String summaryFunction : new List<String>{ 'SUM', 'AVG', 'MIN', 'MAX' }) {
            Assert.isNull(summary.value(summaryFunction), summaryFunction + ' of no values is blank');
        }
    }

    @IsTest
    static void rowLimitIsBlankOrAWholeNumberFrom1To2000() {
        Assert.isNull(BoardTableEngine.resolveRowLimit(null, null), 'No limit needs no sort');
        Assert.areEqual(10, BoardTableEngine.resolveRowLimit(10, 'Amount'));
        Assert.areEqual(2000, BoardTableEngine.resolveRowLimit('2000', 'Amount'), 'Numeric strings parse');
        Assert.areEqual(1, BoardTableEngine.resolveRowLimit(1, 'Amount'));
    }

    @IsTest
    static void rowLimitOutOfRangeOrWithoutSortIsAConfigError() {
        for (Object invalid : new List<Object>{ 0, -3, 2001, 'ten', 1.5 }) {
            assertRowLimitError(invalid, 'Amount');
        }
        assertRowLimitError(10, null);
        assertRowLimitError(10, ' ');
    }

    private static void assertRowLimitError(Object rowLimit, String sortBy) {
        try {
            BoardTableEngine.resolveRowLimit(rowLimit, sortBy);
            Assert.fail('Expected a config error for ' + rowLimit + ' / ' + sortBy);
        } catch (BoardErrors.BoardException expected) {
            Assert.isTrue(expected.getMessage().contains('Row limit'), expected.getMessage());
        }
    }

    @IsTest
    static void rejectsUnknownSummaryFunction() {
        try {
            BoardTableEngine.summarize(new List<Map<String, Object>>(), 'Amount').value('COUNT');
            Assert.fail('COUNT is not a Table summary');
        } catch (BoardErrors.BoardException expected) {
            Assert.isTrue(expected.getMessage().contains('COUNT'), 'Names the rejected function');
        }
    }

    @IsTest
    static void totalsStackEachColumnsSummariesInTheConfiguredOrder() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Amount' => 100, 'Quantity' => 2 },
            new Map<String, Object>{ 'Amount' => 300, 'Quantity' => null },
            new Map<String, Object>{ 'Amount' => 50.5, 'Quantity' => 4 }
        };
        List<BoardTableEngine.SummarySpec> specs = new List<BoardTableEngine.SummarySpec>{
            new BoardTableEngine.SummarySpec('amount', 'Amount', new List<String>{ 'MAX', 'SUM', 'AVG' }),
            new BoardTableEngine.SummarySpec('qty', 'Quantity', new List<String>{ 'MIN' })
        };

        List<BoardTableEngine.ColumnTotal> totals = BoardTableEngine.totalsOverRows(rows, specs);

        Assert.areEqual(2, totals.size(), 'One total per summarized column');
        Assert.areEqual('amount', totals[0].columnId);
        Assert.areEqual(3, totals[0].summaries.size(), 'Stacked summaries');
        Assert.areEqual('MAX', totals[0].summaries[0].summaryFunction, 'Configured order is kept');
        assertNumber(300, totals[0].summaries[0].value, 'Max');
        Assert.areEqual('SUM', totals[0].summaries[1].summaryFunction);
        assertNumber(450.5, totals[0].summaries[1].value, 'Sum');
        assertNumber(150.17, totals[0].summaries[2].value.setScale(2), 'Average');
        Assert.areEqual('qty', totals[1].columnId);
        assertNumber(2, totals[1].summaries[0].value, 'Min skips the blank');
    }

    @IsTest
    static void summaryListIsAnOrderedSetOfUpToFourFunctions() {
        Assert.isTrue(BoardTableEngine.resolveSummaryFunctions(null, 'amount').isEmpty(), 'No summaries');
        Assert.areEqual(
            new List<String>{ 'AVG', 'SUM', 'MIN', 'MAX' },
            BoardTableEngine.resolveSummaryFunctions(new List<Object>{ 'avg', 'Sum', ' MIN ', 'MAX' }, 'amount'),
            'Normalized, in order'
        );
        for (
            Object invalid : new List<Object>{
                new List<Object>{ 'COUNT' },
                new List<Object>{ 'SUM', 'SUM' },
                new List<Object>{ 'SUM', 'AVG', 'MIN', 'MAX', 'SUM' },
                'SUM'
            }
        ) {
            try {
                BoardTableEngine.resolveSummaryFunctions(invalid, 'amount');
                Assert.fail('Expected a config error for ' + invalid);
            } catch (BoardErrors.BoardException expected) {
                Assert.isTrue(expected.getMessage().contains('amount'), 'Names the column: ' + expected.getMessage());
            }
        }
    }

    /** A well-formed, never-inserted Opportunity Id (the engine needs no records). */
    private static Id fakeOpportunityId(Integer index) {
        return Id.valueOf(
            Opportunity.SObjectType.getDescribe().getKeyPrefix() + String.valueOf(index).leftPad(12, '0')
        );
    }

    private static Map<String, Object> line(Object opportunityId, String opportunityName) {
        return new Map<String, Object>{ 'OpportunityId' => opportunityId, 'Opportunity.Name' => opportunityName };
    }

    @IsTest
    static void groupsOfAPageFollowTheRowOrderWithOneGroupPerKey() {
        Id twinA = fakeOpportunityId(1);
        Id twinB = fakeOpportunityId(2);
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            line(twinA, 'Twin'),
            line(twinA, 'Twin'),
            line(twinB, 'Twin'),
            line(null, null),
            line(null, null)
        };

        List<BoardTableEngine.TableGroup> groups = BoardTableEngine.groupsInRowOrder(
            rows,
            'OpportunityId',
            'Opportunity.Name'
        );

        Assert.areEqual(3, groups.size(), 'Same-named records are separate groups; blanks are one group');
        Assert.areEqual(String.valueOf(twinA), groups[0].key, 'Keyed by record Id');
        Assert.areEqual('Twin', groups[0].label, 'Labelled by the record name');
        Assert.areEqual(String.valueOf(twinB), groups[1].key);
        Assert.areEqual('Twin', groups[1].label);
        Assert.isNull(groups[2].key, 'The blank group has no key');
        Assert.isNull(groups[2].label, 'The blank group has no label');
    }

    @IsTest
    static void groupLabelIsTheKeyWithoutALabelPath() {
        List<BoardTableEngine.TableGroup> groups = BoardTableEngine.groupsInRowOrder(
            new List<Map<String, Object>>{ new Map<String, Object>{ 'StageName' => 'Prospecting' } },
            'StageName',
            null
        );

        Assert.areEqual(1, groups.size());
        Assert.areEqual('Prospecting', groups[0].key);
        Assert.areEqual('Prospecting', groups[0].label);
    }
}