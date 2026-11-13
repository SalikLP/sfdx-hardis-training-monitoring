/**
 * Entry-point seam for Panel totals (Small multiples): the Chart query entry point with inserted Opportunities returns
 * each Panel's total per Measure for the Panel headline and per-panel Reference lines. A Panel total covers every row
 * of its Panel (whatever max categories cut), respects the Measure's own Measure condition, and a Formula measure is
 * computed on Panel totals.
 */
@IsTest
private class BoardChartQueryPanelTotalsTest {
    /**
     * Opportunities by Type (Panel field) and Stage (category): type 1: stage 1 100, stage 2 50 (sum 150, avg 75);
     * type 2: stage 1 30, stage 1 10 (sum 40, avg 20); no type: stage 1 10.
     */
    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Board Panel Totals Account');
        insert account;
        insert new List<Opportunity>{
            opportunity('Totals Opp 1', account.Id, 100, stageValue(0), typeValue(0)),
            opportunity('Totals Opp 2', account.Id, 50, stageValue(1), typeValue(0)),
            opportunity('Totals Opp 3', account.Id, 30, stageValue(0), typeValue(1)),
            opportunity('Totals Opp 4', account.Id, 10, stageValue(0), typeValue(1)),
            opportunity('Totals Opp 5', account.Id, 10, stageValue(0), null)
        };
    }

    @IsTest
    static void panelHeadlineIsEachPanelsTotalOfEveryMeasure() {
        Map<String, Object> request = panelRequest(
            new List<Object>{ measure('SUM', 'Amount'), hidden(measure('AVG', 'Amount')) }
        );
        request.put('panelHeadlineMeasure', 1);

        BoardChartQuery.ChartResult result = query(request);

        Map<String, List<Decimal>> totals = totals(result);
        Assert.areEqual(3, result.panelTotals.size(), 'One total per Panel');
        Assert.areEqual(result.panels[0].key, result.panelTotals[0].panelKey, 'In Panel order');
        Assert.areEqual(150, totals.get(typeValue(0))[0]);
        Assert.areEqual(75, totals.get(typeValue(0))[1].setScale(2), 'AVG over the Panel rows, not summed');
        Assert.areEqual(40, totals.get(typeValue(1))[0]);
        Assert.areEqual(20, totals.get(typeValue(1))[1].setScale(2));
        Assert.areEqual(10, totals.get(BoardChartEngine.BLANK_KEY)[1].setScale(2));
    }

    @IsTest
    static void panelHeadlineRespectsItsOwnMeasureCondition() {
        Map<String, Object> firstStage = new Map<String, Object>{
            'logic' => 'AND',
            'conditions' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'mc-stage',
                    'fieldPath' => 'StageName',
                    'operator' => 'EQ',
                    'value' => stageValue(0)
                }
            }
        };
        Map<String, Object> headline = hidden(measure('COUNT', null));
        headline.put('condition', firstStage);
        Map<String, Object> request = panelRequest(new List<Object>{ measure('SUM', 'Amount'), headline });
        request.put('panelHeadlineMeasure', 1);

        Map<String, List<Decimal>> totals = totals(query(request));

        Assert.areEqual(150, totals.get(typeValue(0))[0], 'The chart Measure counts every stage');
        Assert.areEqual(1, totals.get(typeValue(0))[1], 'The headline counts only its condition');
        Assert.areEqual(2, totals.get(typeValue(1))[1]);
    }

    @IsTest
    static void formulaMeasureIsComputedOnPanelTotals() {
        Map<String, Object> request = panelRequest(
            new List<Object>{
                hidden(measure('SUM', 'Amount')),
                hidden(measure('COUNT', null)),
                hidden(new Map<String, Object>{ 'aggregateFunction' => 'FORMULA', 'formula' => 'A / B' })
            }
        );
        request.put('panelHeadlineMeasure', 2);

        Map<String, List<Decimal>> totals = totals(query(request));

        Assert.areEqual(75, totals.get(typeValue(0))[2].setScale(2), '150 / 2, not a sum of per-category ratios');
        Assert.areEqual(20, totals.get(typeValue(1))[2].setScale(2), '40 / 2');
    }

    @IsTest
    static void referenceLinesGetEachPanelsValue() {
        Map<String, Object> line = measure('AVG', 'Amount');
        line.put('render', BoardChartQuery.REFERENCE_LINE_RENDER);
        Map<String, Object> request = panelRequest(new List<Object>{ measure('SUM', 'Amount'), line });
        request.put('includeNullBucket', false);

        BoardChartQuery.ChartResult result = query(request);

        Map<String, List<Decimal>> totals = totals(result);
        Assert.areEqual(2, result.panelTotals.size(), 'No (Blank) panel without include blank');
        Assert.areEqual(75, totals.get(typeValue(0))[1].setScale(2));
        Assert.areEqual(20, totals.get(typeValue(1))[1].setScale(2));
    }

    @IsTest
    static void cursorTierPanelTotalsMatchSoql() {
        Map<String, Object> request = panelRequest(
            new List<Object>{ measure('SUM', 'Amount'), hidden(measure('AVG', 'Amount')) }
        );
        request.put('panelHeadlineMeasure', 1);
        Map<String, List<Decimal>> expected = totals(query(request));

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 2;
        BoardChartQuery.ChartResult result = query(request);
        Assert.areEqual('CURSOR', result.mode);
        while (!result.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.cursor);
            next.put('offset', result.nextOffset);
            next.put('partialState', result.partialState);
            result = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }

        Map<String, List<Decimal>> merged = totals(result);
        Assert.areEqual(expected.keySet(), merged.keySet());
        for (String key : expected.keySet()) {
            for (Integer i = 0; i < 2; i++) {
                Assert.areEqual(expected.get(key)[i].setScale(2), merged.get(key)[i].setScale(2), key + ' ' + i);
            }
        }
    }

    @IsTest
    static void noPanelTotalsWithoutAHeadlineOrReferenceLine() {
        Assert.isNull(query(panelRequest(new List<Object>{ measure('SUM', 'Amount') })).panelTotals);

        Map<String, Object> noPanels = panelRequest(new List<Object>{ measure('SUM', 'Amount') });
        noPanels.remove('panelField');
        noPanels.put('panelHeadlineMeasure', 0);
        Assert.isNull(query(noPanels).panelTotals, 'Only Small multiples have Panel totals');
    }

    private static Map<String, Object> panelRequest(List<Object> measures) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => 'StageName',
            'panelField' => 'Type',
            'measures' => measures,
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>()
        };
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        Map<String, Object> result = new Map<String, Object>{ 'aggregateFunction' => aggregateFunction };
        if (valueField != null) {
            result.put('valueFieldApiName', valueField);
        }
        return result;
    }

    private static Map<String, Object> hidden(Map<String, Object> measure) {
        measure.put('hidden', true);
        return measure;
    }

    private static BoardChartQuery.ChartResult query(Map<String, Object> request) {
        return BoardChartQuery.queryChart(JSON.serialize(request));
    }

    /** Panel totals keyed by Panel key. */
    private static Map<String, List<Decimal>> totals(BoardChartQuery.ChartResult result) {
        Assert.isNotNull(result.panelTotals, 'Panel totals returned');
        Map<String, List<Decimal>> totals = new Map<String, List<Decimal>>();
        for (BoardChartPanelTotals.PanelTotal total : result.panelTotals) {
            totals.put(total.panelKey, total.values);
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