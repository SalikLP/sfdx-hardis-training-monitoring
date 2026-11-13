/**
 * Entry-point seam for grouped Chart requests over the 2,000-combination `GROUP BY` cap (board-loading stories 21–22):
 * Panel × category × series combinations over the cap and within `CURSOR_MAX_ROWS` re-run through the cursor tier and
 * come back complete, with max categories, the series cap and the Panel cut applied to the full aggregate; above
 * `CURSOR_MAX_ROWS` the capped groups come back with the "may miss groups" notice (`hasMoreGroups`). Thresholds are
 * lowered so a few records reach every band; the uncapped SOQL tier is the oracle.
 */
@IsTest
private class BoardChartQueryGroupCapTest {
    private static final Integer CAP = 2;

    /**
     * Opportunities (Type = Panel field, Stage = category, Account = series):
     * Cap Opp 1 type 1 / stage 1 / Alpha 100; Cap Opp 2 type 1 / stage 2 / Beta 50; Cap Opp 3 type 2 / stage 1 /
     * Alpha 30; Cap Opp 4 type 2 / stage 2 / Beta 20; Cap Opp 5 type 3 / stage 1 / Alpha 5.
     */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = 'Cap Alpha');
        Account beta = new Account(Name = 'Cap Beta');
        insert new List<Account>{ alpha, beta };
        insert new List<Opportunity>{
            opportunity('Cap Opp 1', alpha.Id, 100, stageValue(0), typeValue(0)),
            opportunity('Cap Opp 2', beta.Id, 50, stageValue(1), typeValue(0)),
            opportunity('Cap Opp 3', alpha.Id, 30, stageValue(0), typeValue(1)),
            opportunity('Cap Opp 4', beta.Id, 20, stageValue(1), typeValue(1)),
            opportunity('Cap Opp 5', alpha.Id, 5, stageValue(0), typeValue(2))
        };
    }

    @IsTest
    static void panelCombinationsOverTheCapAreCompleteThroughTheCursorTier() {
        Map<String, Object> request = panelRequest();
        request.put('stackByField', 'AccountId');
        BoardChartQuery.ChartResult expected = query(request);
        Assert.areEqual('SINGLE', expected.mode);
        Assert.areEqual(5, expected.points.size(), 'Five Panel × category × series groups');

        BoardQueryService.CHART_GROUP_LIMIT = CAP;
        BoardQueryService.CURSOR_CHUNK_SIZE = 2;
        BoardChartQuery.ChartResult capped = runToEnd(request);

        Assert.areEqual('CURSOR', capped.mode, 'Capped GROUP BY re-runs through the cursor tier');
        Assert.isTrue(capped.isComplete);
        Assert.isFalse(capped.hasMoreGroups, 'Every group is complete: no notice');
        Assert.areEqual(5, capped.totalRows);
        assertSameChart(expected, capped);
        Decimal smallest = 0;
        for (BoardChartEngine.ChartPoint point : capped.points) {
            if (point.panelKey == typeValue(2)) {
                smallest += point.value;
            }
        }
        Assert.areEqual(5, smallest, 'The smallest group (Opp 5) is not dropped');
    }

    @IsTest
    static void topNAndPanelCutRunOnTheFullAggregate() {
        // Category = Opportunity name: 5 groups. Max 3 categories + Other, max 2 Panels by total (type 1 150, type 2
        // 50; type 3 5 cut). The capped SOQL query alone would only hold Opp 1 and Opp 2 (both type 1).
        Map<String, Object> request = panelRequest();
        request.put('groupByField', 'Name');
        request.put('maxCategories', 3);
        request.put('overflowMode', 'OTHER');
        request.put('maxPanels', 2);
        request.put('panelSort', 'VALUE_DESC');
        BoardChartQuery.ChartResult expected = query(request);

        BoardQueryService.CHART_GROUP_LIMIT = CAP;
        BoardChartQuery.ChartResult capped = runToEnd(request);

        Assert.areEqual('CURSOR', capped.mode);
        Assert.isFalse(capped.hasMoreGroups);
        Assert.areEqual(new List<String>{ typeValue(0), typeValue(1) }, keyValues(capped.panels), 'Largest first');
        Assert.isTrue(capped.cutPanels, '12-panel style cut with a notice, after full aggregation');
        Assert.areEqual(1, capped.hiddenPanels);
        Assert.isTrue(capped.truncatedCategories, 'max categories + Other across every Panel');
        assertSameChart(expected, capped);
    }

    @IsTest
    static void seriesCapRunsOnTheFullAggregate() {
        Map<String, Object> request = panelRequest();
        request.put('stackByField', 'Name');
        request.put('maxSeries', 2);
        request.put('measures', new List<Object>{ new Map<String, Object>{ 'aggregateFunction' => 'COUNT' } });
        BoardChartQuery.ChartResult expected = query(request);
        Assert.isTrue(expected.truncatedSeries);

        BoardQueryService.CHART_GROUP_LIMIT = CAP;
        BoardChartQuery.ChartResult capped = runToEnd(request);

        Assert.areEqual('CURSOR', capped.mode);
        Assert.isTrue(capped.truncatedSeries);
        assertSameChart(expected, capped);
    }

    @IsTest
    static void overMaxCursorRowsKeepsCappedGroupsWithTheMissingGroupsNotice() {
        BoardQueryService.CHART_GROUP_LIMIT = CAP;
        BoardQueryService.CURSOR_MAX_ROWS = 4;

        BoardChartQuery.ChartResult capped = query(panelRequest());

        Assert.areEqual('SINGLE', capped.mode, 'Above the cursor-tier row cap: no cursor fallback');
        Assert.isTrue(capped.hasMoreGroups, '"May miss groups" notice');
        Assert.areEqual(CAP, capped.points.size(), 'Only the largest groups came back');
    }

    @IsTest
    static void categoryBySeriesWithoutPanelsStillCompletes() {
        // Regression: category × series over the cap (a stand-in for 200 categories × 12 series) without panels.
        Map<String, Object> request = panelRequest();
        request.remove('panelField');
        request.put('stackByField', 'AccountId');
        BoardChartQuery.ChartResult expected = query(request);

        BoardQueryService.CHART_GROUP_LIMIT = CAP;
        BoardQueryService.CURSOR_CHUNK_SIZE = 2;
        BoardChartQuery.ChartResult capped = runToEnd(request);

        Assert.areEqual('CURSOR', capped.mode);
        Assert.isTrue(capped.isComplete);
        Assert.isFalse(capped.hasMoreGroups);
        Assert.areEqual(0, capped.panels.size());
        assertSameChart(expected, capped);
    }

    @IsTest
    static void bucketPanelCombinationsOverTheCapAreCompleteThroughTheCursorTier() {
        // Bucket Panel field: Small (< 40) Opps 3, 4, 5; Big (>= 40) Opps 1, 2. Each bucket's query groups by stage.
        Map<String, Object> request = panelRequest();
        request.put('panelField', 'bucket:dealSize');
        request.put('bucketFields', dealSize());
        request.put('panelHeadlineMeasure', 0);
        BoardChartQuery.ChartResult expected = query(request);
        Assert.areEqual('SINGLE', expected.mode);

        BoardQueryService.CHART_GROUP_LIMIT = CAP;
        BoardQueryService.CURSOR_CHUNK_SIZE = 2;
        BoardChartQuery.ChartResult capped = runToEnd(request);

        Assert.areEqual('CURSOR', capped.mode, 'A capped bucket query re-runs through the cursor tier');
        Assert.isFalse(capped.hasMoreGroups);
        Assert.areEqual(new List<String>{ 'Small', 'Big' }, keyValues(capped.panels));
        assertSameChart(expected, capped);
        Assert.areEqual(totals(expected), totals(capped), 'Panel totals over every row');

        BoardQueryService.CURSOR_MAX_ROWS = 4;
        BoardChartQuery.ChartResult overMax = query(request);
        Assert.areEqual('SINGLE', overMax.mode);
        Assert.isTrue(overMax.hasMoreGroups, '"May miss groups" notice above the cursor-tier row cap');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** SUM of Amount by stage, one Panel per Type. */
    private static Map<String, Object> panelRequest() {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => 'StageName',
            'panelField' => 'Type',
            'maxPanels' => 12,
            'measures' => new List<Object>{
                new Map<String, Object>{ 'aggregateFunction' => 'SUM', 'valueFieldApiName' => 'Amount' }
            },
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>()
        };
    }

    private static List<Object> dealSize() {
        return new List<Object>{
            new Map<String, Object>{
                'id' => 'dealSize',
                'label' => 'Deal size',
                'rules' => new List<Object>{ rule('Small', 'LT', 40), rule('Big', 'GTE', 40) }
            }
        };
    }

    private static Map<String, Object> rule(String label, String operator, Decimal amount) {
        return new Map<String, Object>{
            'label' => label,
            'condition' => new Map<String, Object>{
                'logic' => 'AND',
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'c1',
                        'fieldPath' => 'Amount',
                        'operator' => operator,
                        'value' => amount
                    }
                }
            }
        };
    }

    private static BoardChartQuery.ChartResult query(Map<String, Object> request) {
        return BoardChartQuery.queryChart(JSON.serialize(request));
    }

    /** First call plus every `fetchChartChunk` until complete. */
    private static BoardChartQuery.ChartResult runToEnd(Map<String, Object> request) {
        BoardChartQuery.ChartResult result = query(request);
        while (!result.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.cursor);
            next.put('offset', result.nextOffset);
            next.put('partialState', result.partialState);
            result = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }
        return result;
    }

    private static void assertSameChart(BoardChartQuery.ChartResult expected, BoardChartQuery.ChartResult actual) {
        Assert.areEqual(keyValues(expected.panels), keyValues(actual.panels), 'Same Panels in the same order');
        Assert.areEqual(expected.cutPanels, actual.cutPanels);
        Assert.areEqual(expected.hiddenPanels, actual.hiddenPanels);
        Assert.areEqual(keyValues(expected.categories), keyValues(actual.categories), 'Same categories');
        Assert.areEqual(expected.truncatedCategories, actual.truncatedCategories);
        Assert.areEqual(expected.hiddenCategories, actual.hiddenCategories);
        Assert.areEqual(keyValues(expected.series), keyValues(actual.series), 'Same series');
        Assert.areEqual(expected.truncatedSeries, actual.truncatedSeries);
        Assert.areEqual(values(expected), values(actual), 'Same points');
    }

    private static List<String> keyValues(List<BoardChartEngine.ChartKey> keys) {
        List<String> result = new List<String>();
        for (BoardChartEngine.ChartKey key : keys) {
            result.add(key.key);
        }
        return result;
    }

    /** Point values (2 decimals) keyed `panelKey|categoryKey|seriesKey|measureIndex`. */
    private static Map<String, Decimal> values(BoardChartQuery.ChartResult result) {
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(
                point.panelKey + '|' + point.categoryKey + '|' + point.seriesKey + '|' + point.measureIndex,
                point.value == null ? null : point.value.setScale(2)
            );
        }
        return values;
    }

    private static Map<String, List<Decimal>> totals(BoardChartQuery.ChartResult result) {
        Map<String, List<Decimal>> totals = new Map<String, List<Decimal>>();
        for (BoardChartPanelTotals.PanelTotal total : result.panelTotals) {
            List<Decimal> scaled = new List<Decimal>();
            for (Decimal value : total.values) {
                scaled.add(value == null ? null : value.setScale(2));
            }
            totals.put(total.panelKey, scaled);
        }
        return totals;
    }

    private static String stageValue(Integer index) {
        return Opportunity.StageName.getDescribe().getPicklistValues()[index].getValue();
    }

    private static String typeValue(Integer index) {
        List<Schema.PicklistEntry> active = new List<Schema.PicklistEntry>();
        for (Schema.PicklistEntry entry : Opportunity.Type.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                active.add(entry);
            }
        }
        return active[index].getValue();
    }

    private static Opportunity opportunity(
        String name,
        Id accountId,
        Decimal amount,
        String stageName,
        String typeName
    ) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            Amount = amount,
            CloseDate = Date.today(),
            StageName = stageName,
            Type = typeName
        );
    }
}