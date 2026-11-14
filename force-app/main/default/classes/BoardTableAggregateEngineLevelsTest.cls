/**
 * Engine-unit seam of a Table with Detail rows off grouped by two fields: rows (cursor tier) or pre-aggregated
 * second-level groups (SOQL tier) fold into first-level groups, each with its second-level groups nested beneath,
 * counts and Stacked summaries rolled up, both levels ordered (blanks last at each level).
 */
@IsTest
private class BoardTableAggregateEngineLevelsTest {
    private static final String KEY = 'AccountId';
    private static final String LABEL = 'Account.Name';
    private static final String FAMILY = 'Family';
    private static final String AMOUNT = 'Amount';

    /** Grouped by Account (ordered by name), then by Family; Amount summed and maxed. */
    private static BoardTableAggregateEngine.Plan plan() {
        BoardTableAggregateEngine.Plan plan = new BoardTableAggregateEngine.Plan();
        plan.keyPath = KEY;
        plan.valuePaths = new List<String>{ LABEL };
        plan.specs = new List<BoardTableEngine.SummarySpec>{
            new BoardTableEngine.SummarySpec('amount', AMOUNT, new List<String>{ 'SUM', 'MAX' })
        };
        plan.orderPath = LABEL;
        BoardTableAggregateEngine.Plan second = new BoardTableAggregateEngine.Plan();
        second.keyPath = FAMILY;
        second.specs = plan.specs;
        plan.secondLevel = second;
        return plan;
    }

    private static Map<String, Object> row(String rowKey, String rowLabel, String rowFamily, Decimal rowAmount) {
        return new Map<String, Object>{ KEY => rowKey, LABEL => rowLabel, FAMILY => rowFamily, AMOUNT => rowAmount };
    }

    /** Alpha: Hardware 10, 20, Software 30, no family 4; Beta: Software 5; no Account: Hardware 7, 8. */
    private static List<Map<String, Object>> rows() {
        return new List<Map<String, Object>>{
            row('001A', 'Alpha', 'Software', 30),
            row(null, null, 'Hardware', 7),
            row('001B', 'Beta', 'Software', 5),
            row('001A', 'Alpha', 'Hardware', 10),
            row('001A', 'Alpha', null, 4),
            row('001A', 'Alpha', 'hardware', 20),
            row(null, null, 'Hardware', 8)
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
    static void rowsFoldIntoFirstLevelGroupsWithTheirSecondLevelGroupsNested() {
        List<BoardTableAggregateEngine.AggregatedGroup> groups = aggregate(plan(), rows());

        Assert.areEqual(new List<String>{ '001A', '001B', null }, keys(groups), 'By label, "(Blank)" last');
        BoardTableAggregateEngine.AggregatedGroup alpha = groups[0];
        Assert.areEqual(4, alpha.count, 'A first-level count sums its subgroups');
        Assert.areEqual('Alpha', alpha.values.get(LABEL));
        assertSummaries(alpha, 64, 30);
        Assert.areEqual(
            new List<String>{ 'Hardware', 'Software', null },
            keys(alpha.subgroups),
            'Subgroups by value, case folded like GROUP BY, "(Blank)" last'
        );
        Assert.areEqual(2, alpha.subgroups[0].count);
        assertSummaries(alpha.subgroups[0], 30, 20);
        Assert.areEqual('001A', alpha.subgroups[0].parentKey);
        Assert.areEqual(1, alpha.subgroups[2].count);

        BoardTableAggregateEngine.AggregatedGroup blank = groups[2];
        Assert.areEqual(2, blank.count);
        Assert.areEqual(new List<String>{ 'Hardware' }, keys(blank.subgroups));
        Assert.isNull(blank.subgroups[0].parentKey);
        assertSummaries(blank, 15, 8);

        List<BoardTableEngine.ColumnTotal> totals = BoardTableAggregateEngine.grandTotals(groups, plan().specs);
        assertNumber(84, totals[0].summaries[0].value);
    }

    @IsTest
    static void firstLevelGroupsOrderByTheirRolledUpSummary() {
        BoardTableAggregateEngine.Plan plan = plan();
        plan.orderPath = null;
        plan.orderSpecIndex = 0;
        plan.orderFunction = 'SUM';
        plan.direction = 'DESC';
        plan.secondLevel.direction = 'DESC';

        List<BoardTableAggregateEngine.AggregatedGroup> groups = aggregate(plan, rows());

        Assert.areEqual(new List<String>{ '001A', '001B', null }, keys(groups), 'Sum desc: 64, 5, "(Blank)" last');
        Assert.areEqual(new List<String>{ 'Software', 'Hardware', null }, keys(groups[0].subgroups));
        Assert.areEqual(
            new List<String>{ '001A' },
            keys(BoardTableAggregateEngine.topGroups(groups, 1)),
            'A Row limit counts first-level groups'
        );
    }

    @IsTest
    static void runningStateKeepsBothLevelsFromOneChunkToTheNext() {
        List<Map<String, Object>> rows = rows();
        BoardTableAggregateEngine.Accumulator first = new BoardTableAggregateEngine.Accumulator(plan());
        for (Integer i = 0; i < 3; i++) {
            first.add(rows[i]);
        }
        BoardTableAggregateEngine.Accumulator second = new BoardTableAggregateEngine.Accumulator(plan())
            .restore(first.state());
        for (Integer i = 3; i < rows.size(); i++) {
            second.add(rows[i]);
        }

        List<BoardTableAggregateEngine.AggregatedGroup> chunked = BoardTableAggregateEngine.orderGroups(
            second.groups(),
            plan()
        );
        List<BoardTableAggregateEngine.AggregatedGroup> whole = aggregate(plan(), rows);
        Assert.areEqual(keys(whole), keys(chunked));
        for (Integer g = 0; g < whole.size(); g++) {
            Assert.areEqual(keys(whole[g].subgroups), keys(chunked[g].subgroups));
            Assert.areEqual(whole[g].count, chunked[g].count);
            Assert.areEqual(
                JSON.serialize(BoardTableAggregateEngine.summaries(whole[g], plan().specs)),
                JSON.serialize(BoardTableAggregateEngine.summaries(chunked[g], plan().specs))
            );
        }
    }

    @IsTest
    static void preAggregatedSecondLevelGroupsMergeLikeRows() {
        BoardTableAggregateEngine.Accumulator accumulator = new BoardTableAggregateEngine.Accumulator(plan());
        accumulator.addGroup(leaf('001A', 'Hardware', 2, 30, 20));
        accumulator.addGroup(leaf('001A', 'HARDWARE', 1, 5, 5));
        accumulator.addGroup(leaf('001A', null, 1, 4, 4));

        List<BoardTableAggregateEngine.AggregatedGroup> groups = BoardTableAggregateEngine.orderGroups(
            accumulator.groups(),
            plan()
        );

        Assert.areEqual(1, groups.size());
        Assert.areEqual(4, groups[0].count);
        assertSummaries(groups[0], 39, 20);
        Assert.areEqual(new List<String>{ 'Hardware', null }, keys(groups[0].subgroups));
        Assert.areEqual(3, groups[0].subgroups[0].count, 'Same key ignoring case: one group');
        assertSummaries(groups[0].subgroups[0], 35, 20);
    }

    @IsTest
    static void oneLevelPlansKeepFlatGroups() {
        BoardTableAggregateEngine.Plan plan = plan();
        plan.secondLevel = null;

        List<BoardTableAggregateEngine.AggregatedGroup> groups = aggregate(plan, rows());

        Assert.areEqual(new List<String>{ '001A', '001B', null }, keys(groups));
        Assert.isTrue(groups[0].subgroups.isEmpty());
    }

    /** A second-level group as one `GROUP BY` row returns it: key, parent key, count and the Amount partials. */
    private static BoardTableAggregateEngine.AggregatedGroup leaf(
        String parentKey,
        String groupKey,
        Integer count,
        Decimal sum,
        Decimal max
    ) {
        BoardTableAggregateEngine.AggregatedGroup chunk = new BoardTableAggregateEngine.AggregatedGroup();
        chunk.parentKey = parentKey;
        chunk.key = groupKey;
        chunk.count = count;
        chunk.values = new Map<String, Object>{ KEY => parentKey, LABEL => 'Alpha', FAMILY => groupKey };
        BoardTableEngine.Summary partial = new BoardTableEngine.Summary();
        partial.addAggregate(sum, count, max, max);
        chunk.summaries.add(partial);
        return chunk;
    }

    private static void assertSummaries(
        BoardTableAggregateEngine.AggregatedGroup aggregatedGroup,
        Decimal sum,
        Decimal max
    ) {
        List<BoardTableEngine.ColumnTotal> summaries = BoardTableAggregateEngine.summaries(
            aggregatedGroup,
            plan().specs
        );
        assertNumber(sum, summaries[0].summaries[0].value);
        assertNumber(max, summaries[0].summaries[1].value);
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