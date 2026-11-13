/**
 * Entry-point seam for the Table Total row: `queryTable` with `showTotalRow` and per-column Stacked summaries,
 * over the whole scope or only the rows shown under a Row limit.
 */
@IsTest
private class BoardQueryServiceTableTotalsTest {
    /** Opportunities with Amount 100, 200, ... 1,200 plus one with no Amount. */
    private static final Integer AMOUNT_COUNT = 12;

    @TestSetup
    static void setup() {
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 1; i <= AMOUNT_COUNT; i++) {
            opportunities.add(opportunity('Board Total ' + String.valueOf(i).leftPad(2, '0'), i * 100));
        }
        opportunities.add(opportunity('Board Total blank', null));
        insert opportunities;
    }

    private static Opportunity opportunity(String name, Decimal amount) {
        return new Opportunity(Name = name, StageName = 'Prospecting', CloseDate = Date.today(), Amount = amount);
    }

    @IsTest
    static void totalRowSummarizesAllMatchingRecordsNotJustTheFirstPage() {
        Map<String, Object> request = totalsRequest(new List<Object>{ 'SUM', 'AVG', 'MIN', 'MAX' });
        request.put('pageSize', 10);

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        Assert.areEqual(10, result.rows.size(), 'First page only');
        Assert.areEqual(1, result.totals.size(), 'Columns without summaries get no total');
        BoardTableEngine.ColumnTotal amount = result.totals[0];
        Assert.areEqual('amount', amount.columnId);
        assertSummaries(
            amount,
            new List<String>{ 'SUM', 'AVG', 'MIN', 'MAX' },
            new List<Decimal>{ 7800, 650, 100, 1200 }
        );
        Assert.isFalse(result.totalRowUnavailable);
    }

    @IsTest
    static void totalRowHonoursFilters() {
        Map<String, Object> request = totalsRequest(new List<Object>{ 'SUM' });
        request.put(
            'baseFilters',
            new List<Object>{
                new Map<String, Object>{ 'id' => 'big', 'fieldPath' => 'Amount', 'operator' => 'GTE', 'value' => 1000 }
            }
        );

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        assertSummaries(result.totals[0], new List<String>{ 'SUM' }, new List<Decimal>{ 3300 });
    }

    @IsTest
    static void totalRowUnderARowLimitSummarizesOnlyTheShownRows() {
        Map<String, Object> request = totalsRequest(new List<Object>{ 'MAX', 'SUM', 'AVG', 'MIN' });
        request.put('sortBy', 'Amount');
        request.put('sortDirection', 'DESC');
        request.put('rowLimit', 3);

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        Assert.areEqual(3, result.rows.size());
        Assert.areEqual(AMOUNT_COUNT + 1, result.totalCount, 'Badge still counts every match');
        assertSummaries(
            result.totals[0],
            new List<String>{ 'MAX', 'SUM', 'AVG', 'MIN' },
            new List<Decimal>{ 1200, 3300, 1100, 1000 }
        );
    }

    @IsTest
    static void totalRowOffReturnsNoTotals() {
        Map<String, Object> request = totalsRequest(new List<Object>{ 'SUM' });
        request.remove('showTotalRow');

        Assert.isNull(BoardQueryService.queryTable(JSON.serialize(request)).totals);
    }

    @IsTest
    static void summariesOnANonNumericOrUnknownColumnFailClosed() {
        Map<String, Object> request = totalsRequest(new List<Object>{ 'SUM' });
        ((Map<String, Object>) ((List<Object>) request.get('columns'))[0]).put('summaries', new List<Object>{ 'SUM' });
        Assert.areEqual('columns', expectConfigError(request).get('fieldPath'));

        Map<String, Object> countRequest = totalsRequest(new List<Object>{ 'COUNT' });
        Assert.areEqual('columns', expectConfigError(countRequest).get('fieldPath'));
    }

    @IsTest
    static void totalRowBeyondTheRowBudgetIsUnavailableInsteadOfFailing() {
        BoardTableQuery.TOTALS_MAX_ROWS = 5;

        BoardQueryService.TableResult result = BoardQueryService.queryTable(
            JSON.serialize(totalsRequest(new List<Object>{ 'SUM' }))
        );

        Assert.isNull(result.totals);
        Assert.isTrue(result.totalRowUnavailable, 'The Widget says why the Total row is blank');
        Assert.isFalse(result.rows.isEmpty(), 'Rows still load');
    }

    private static Map<String, Object> totalsRequest(List<Object> amountSummaries) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => new List<Object>{
                new Map<String, Object>{ 'id' => 'name', 'fieldPath' => 'Name' },
                new Map<String, Object>{ 'id' => 'amount', 'fieldPath' => 'Amount', 'summaries' => amountSummaries }
            },
            'showTotalRow' => true,
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'refreshToken' => 0
        };
    }

    private static void assertSummaries(
        BoardTableEngine.ColumnTotal total,
        List<String> expectedFunctions,
        List<Decimal> expectedValues
    ) {
        Assert.areEqual(expectedFunctions.size(), total.summaries.size(), 'Stacked summaries');
        for (Integer i = 0; i < expectedFunctions.size(); i++) {
            BoardTableEngine.SummaryValue summary = total.summaries[i];
            Assert.areEqual(expectedFunctions[i], summary.summaryFunction, 'Configured order');
            Assert.isTrue(
                summary.value != null && summary.value == expectedValues[i],
                summary.summaryFunction + ': expected ' + expectedValues[i] + ', got ' + summary.value
            );
        }
    }

    private static Map<String, Object> expectConfigError(Map<String, Object> request) {
        try {
            BoardQueryService.queryTable(JSON.serialize(request));
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), String.valueOf(payload));
            return payload;
        }
        Assert.fail('Expected CONFIG_ERROR for ' + JSON.serialize(request));
        return null;
    }
}