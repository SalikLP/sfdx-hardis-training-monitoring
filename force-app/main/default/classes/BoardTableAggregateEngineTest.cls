/**
 * Engine-unit seam of a Table with Detail rows off in the cursor tier: group accumulation, summary computation and
 * group ordering over in-memory rows (no SOQL, no records), matching what the SOQL tier's `GROUP BY` returns.
 */
@IsTest
private class BoardTableAggregateEngineTest {
    private static final String KEY = 'AccountId';
    private static final String LABEL = 'Account.Name';
    private static final String REVENUE = 'Account.AnnualRevenue';
    private static final String AMOUNT = 'Amount';

    /** Grouped by Account; label and revenue reached through the lookup; Amount summed and maxed. */
    private static BoardTableAggregateEngine.Plan plan() {
        BoardTableAggregateEngine.Plan plan = new BoardTableAggregateEngine.Plan();
        plan.keyPath = KEY;
        plan.valuePaths = new List<String>{ LABEL, REVENUE };
        plan.specs = new List<BoardTableEngine.SummarySpec>{
            new BoardTableEngine.SummarySpec('amount', AMOUNT, new List<String>{ 'SUM', 'MAX' })
        };
        plan.orderPath = LABEL;
        return plan;
    }

    private static Map<String, Object> row(String rowKey, String rowLabel, Decimal rowRevenue, Decimal rowAmount) {
        return new Map<String, Object>{ KEY => rowKey, LABEL => rowLabel, REVENUE => rowRevenue, AMOUNT => rowAmount };
    }

    /** Alpha (10, 20, 30), Beta (5), Gamma (100, blank), two rows without a key (7, 8). */
    private static List<Map<String, Object>> rows() {
        return new List<Map<String, Object>>{
            row('001A', 'Alpha', 100, 10),
            row('001G', 'Gamma', 500, 100),
            row(null, null, null, 7),
            row('001B', 'Beta', 900, 5),
            row('001A', 'Alpha', 100, 20),
            row('', null, null, 8),
            row('001G', 'Gamma', 500, null),
            row('001A', 'Alpha', 100, 30)
        };
    }

    private static List<BoardTableAggregateEngine.AggregatedGroup> aggregate(
        BoardTableAggregateEngine.Plan plan,
        List<Map<String, Object>> rows
    ) {
        BoardTableAggregateEngine.Accumulator accumulator = new BoardTableAggregateEngine.Accumulator(plan);
        for (Map<String, Object> row : rows) {
            accumulator.add(row);
        }
        return BoardTableAggregateEngine.orderGroups(accumulator.groups(), plan);
    }

    @IsTest
    static void rowsFoldIntoGroupsWithCountsSummariesAndValuesConstantPerGroup() {
        List<BoardTableAggregateEngine.AggregatedGroup> groups = aggregate(plan(), rows());

        Assert.areEqual(new List<String>{ '001A', '001B', '001G', null }, keys(groups), 'By label, "(Blank)" last');
        BoardTableAggregateEngine.AggregatedGroup alpha = groups[0];
        Assert.areEqual(3, alpha.count);
        Assert.areEqual('Alpha', alpha.values.get(LABEL));
        assertNumber(100, alpha.values.get(REVENUE));
        Assert.areEqual('001A', alpha.values.get(KEY));
        List<BoardTableEngine.ColumnTotal> alphaSummaries = BoardTableAggregateEngine.summaries(alpha, plan().specs);
        Assert.areEqual('amount', alphaSummaries[0].columnId);
        Assert.areEqual('SUM', alphaSummaries[0].summaries[0].summaryFunction);
        assertNumber(60, alphaSummaries[0].summaries[0].value);
        assertNumber(30, alphaSummaries[0].summaries[1].value);

        BoardTableAggregateEngine.AggregatedGroup gamma = groups[2];
        Assert.areEqual(2, gamma.count, 'A blank cell still counts its record');
        assertNumber(100, BoardTableAggregateEngine.summaries(gamma, plan().specs)[0].summaries[0].value);

        BoardTableAggregateEngine.AggregatedGroup blank = groups[3];
        Assert.isNull(blank.key, 'Null and empty keys form one "(Blank)" group');
        Assert.areEqual(2, blank.count);
        assertNumber(15, BoardTableAggregateEngine.summaries(blank, plan().specs)[0].summaries[0].value);
    }

    @IsTest
    static void textKeysGroupCaseInsensitivelyLikeSoql() {
        BoardTableAggregateEngine.Plan plan = plan();
        plan.orderPath = null;
        List<BoardTableAggregateEngine.AggregatedGroup> groups = aggregate(
            plan,
            new List<Map<String, Object>>{ row('north', null, null, 1), row('North', null, null, 2) }
        );

        Assert.areEqual(1, groups.size());
        Assert.areEqual('north', groups[0].key, 'The first spelling seen names the group');
        Assert.areEqual(2, groups[0].count);
    }

    @IsTest
    static void groupsOrderBySummaryDescendingWithBlankLast() {
        BoardTableAggregateEngine.Plan plan = plan();
        plan.orderPath = null;
        plan.orderSpecIndex = 0;
        plan.orderFunction = 'SUM';
        plan.direction = 'DESC';

        Assert.areEqual(new List<String>{ '001G', '001A', '001B', null }, keys(aggregate(plan, rows())));

        plan.direction = 'ASC';
        Assert.areEqual(new List<String>{ '001B', '001A', '001G', null }, keys(aggregate(plan, rows())));
    }

    @IsTest
    static void groupsWithoutTheSummaryValueSortLastInEitherDirection() {
        BoardTableAggregateEngine.Plan plan = plan();
        plan.orderPath = null;
        plan.orderSpecIndex = 0;
        plan.orderFunction = 'MAX';
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            row('001A', 'Alpha', 1, null),
            row('001B', 'Beta', 1, 5),
            row('001C', 'Gamma', 1, 9)
        };

        Assert.areEqual(new List<String>{ '001B', '001C', '001A' }, keys(aggregate(plan, rows)));
        plan.direction = 'DESC';
        Assert.areEqual(new List<String>{ '001C', '001B', '001A' }, keys(aggregate(plan, rows)));
    }

    @IsTest
    static void groupsOrderByANumberConstantPerGroupThenByKey() {
        BoardTableAggregateEngine.Plan plan = plan();
        plan.orderPath = REVENUE;
        plan.direction = 'DESC';
        List<Map<String, Object>> rows = rows();
        rows.add(row('001Z', 'Zeta', 900, 1));
        rows.add(row('001Y', 'Ypsilon', null, 1));

        Assert.areEqual(
            new List<String>{ '001Z', '001B', '001G', '001A', '001Y', null },
            keys(aggregate(plan, rows)),
            'Revenue desc, ties by key desc, blank revenue after values, "(Blank)" group last'
        );
    }

    @IsTest
    static void textOrdersIgnoreCase() {
        BoardTableAggregateEngine.Plan plan = plan();
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            row('001A', 'beta', 1, 1),
            row('001B', 'Alpha', 1, 1),
            row('001C', 'Charlie', 1, 1)
        };

        Assert.areEqual(new List<String>{ '001B', '001A', '001C' }, keys(aggregate(plan, rows)));
    }

    @IsTest
    static void picklistValuesOrderByTheirDefinitionOrder() {
        BoardTableAggregateEngine.Plan plan = new BoardTableAggregateEngine.Plan();
        plan.keyPath = 'StageName';
        plan.rankedValues.put('stagename', new List<String>{ 'Prospecting', 'Qualification', 'Closed Won' });
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'StageName' => 'Closed Won' },
            new Map<String, Object>{ 'StageName' => 'Prospecting' },
            new Map<String, Object>{ 'StageName' => 'Legacy' },
            new Map<String, Object>{ 'StageName' => 'Qualification' }
        };

        Assert.areEqual(
            new List<String>{ 'Prospecting', 'Qualification', 'Closed Won', 'Legacy' },
            keys(aggregate(plan, rows)),
            'Definition order; values outside it follow'
        );
        plan.direction = 'DESC';
        Assert.areEqual(
            new List<String>{ 'Legacy', 'Closed Won', 'Qualification', 'Prospecting' },
            keys(aggregate(plan, rows))
        );
    }

    @IsTest
    static void runningStateCarriesGroupsFromOneChunkToTheNext() {
        List<Map<String, Object>> rows = rows();
        BoardTableAggregateEngine.Accumulator first = new BoardTableAggregateEngine.Accumulator(plan());
        for (Integer i = 0; i < 4; i++) {
            first.add(rows[i]);
        }
        BoardTableAggregateEngine.Accumulator second = new BoardTableAggregateEngine.Accumulator(plan())
            .restore(first.state());
        for (Integer i = 4; i < rows.size(); i++) {
            second.add(rows[i]);
        }

        List<BoardTableAggregateEngine.AggregatedGroup> chunked = BoardTableAggregateEngine.orderGroups(
            second.groups(),
            plan()
        );
        List<BoardTableAggregateEngine.AggregatedGroup> whole = aggregate(plan(), rows);
        Assert.areEqual(keys(whole), keys(chunked));
        for (Integer g = 0; g < whole.size(); g++) {
            Assert.areEqual(whole[g].count, chunked[g].count);
            Assert.areEqual(
                JSON.serialize(BoardTableAggregateEngine.summaries(whole[g], plan().specs)),
                JSON.serialize(BoardTableAggregateEngine.summaries(chunked[g], plan().specs))
            );
        }
        Assert.areEqual('Alpha', chunked[0].values.get(LABEL));
    }

    @IsTest
    static void aMalformedRunningStateIsARetryableError() {
        try {
            new BoardTableAggregateEngine.Accumulator(plan()).restore('{not json');
            Assert.fail('Expected a retryable error');
        } catch (BoardErrors.BoardException expected) {
            Assert.areEqual(BoardErrors.QUERY_ERROR, expected.category);
            Assert.isTrue(expected.retryable);
        }
    }

    @IsTest
    static void aRowLimitKeepsTheTopGroupsInGroupOrder() {
        BoardTableAggregateEngine.Plan plan = plan();
        plan.orderPath = null;
        plan.orderSpecIndex = 0;
        plan.orderFunction = 'SUM';
        plan.direction = 'DESC';
        List<BoardTableAggregateEngine.AggregatedGroup> ordered = aggregate(plan, rows());

        Assert.areEqual(new List<String>{ '001G', '001A' }, keys(BoardTableAggregateEngine.topGroups(ordered, 2)));
        Assert.areEqual(4, BoardTableAggregateEngine.topGroups(ordered, 10).size(), 'Fewer groups than the limit');
    }

    @IsTest
    static void grandTotalsMergeEveryGroup() {
        List<BoardTableEngine.ColumnTotal> totals = BoardTableAggregateEngine.grandTotals(
            aggregate(plan(), rows()),
            plan().specs
        );

        Assert.areEqual(1, totals.size());
        Assert.areEqual('amount', totals[0].columnId);
        assertNumber(180, totals[0].summaries[0].value);
        assertNumber(100, totals[0].summaries[1].value);
    }

    private static List<String> keys(List<BoardTableAggregateEngine.AggregatedGroup> groups) {
        List<String> keys = new List<String>();
        for (BoardTableAggregateEngine.AggregatedGroup aggregatedGroup : groups) {
            keys.add(aggregatedGroup.key);
        }
        return keys;
    }

    private static void assertNumber(Decimal expected, Object actual) {
        Decimal value = BoardQueryService.toDecimal(actual);
        Assert.isTrue(value != null && value == expected, 'Expected ' + expected + ', got ' + actual);
    }
}