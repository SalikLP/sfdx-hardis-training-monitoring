@IsTest
private class BoardChartQueryPanelTest {
    /**
     * Opportunities by Type (Panel field) and Stage (category): type 1 / stage 1 100, type 1 / stage 2 50,
     * type 2 / stage 1 30, no type / stage 1 10.
     */
    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Board Panel Account');
        insert account;
        insert new List<Opportunity>{
            opportunity('Panel Opp 1', account.Id, 100, stageValue(0), typeValue(0)),
            opportunity('Panel Opp 2', account.Id, 50, stageValue(1), typeValue(0)),
            opportunity('Panel Opp 3', account.Id, 30, stageValue(0), typeValue(1)),
            opportunity('Panel Opp 4', account.Id, 10, stageValue(0), null)
        };
    }

    @IsTest
    static void panelFieldGroupsOnePanelPerValueInPicklistOrder() {
        BoardChartQuery.ChartResult result = query(panelRequest());

        Assert.isNotNull(result.panelBy);
        Assert.areEqual('Type', result.panelBy.fieldPath);
        Assert.areEqual(3, result.panels.size());
        Assert.areEqual(typeValue(0), result.panels[0].value, 'Picklist order');
        Assert.areEqual(typeLabel(0), result.panels[0].label, 'Titled with the picklist label');
        Assert.areEqual(typeValue(1), result.panels[1].value);
        Assert.isTrue(result.panels[2].isBlank, '(Blank) panel last, include blank on');
        Assert.areEqual(2, result.categories.size(), 'Every panel shares the same categories');
        Assert.areEqual(stageValue(0), result.categories[0].value, 'Stage 1 (140) before stage 2 (50)');
        Map<String, Decimal> values = values(result);
        Assert.areEqual(100, values.get(typeValue(0) + '|' + stageValue(0)));
        Assert.areEqual(50, values.get(typeValue(0) + '|' + stageValue(1)));
        Assert.areEqual(30, values.get(typeValue(1) + '|' + stageValue(0)));
        Assert.isFalse(values.containsKey(typeValue(1) + '|' + stageValue(1)), 'A gap, no point');
        Assert.areEqual(10, values.get(BoardChartEngine.BLANK_KEY + '|' + stageValue(0)));
        Assert.isFalse(result.cutPanels);

        Map<String, Object> noBlank = panelRequest();
        noBlank.put('includeNullBucket', false);
        Assert.areEqual(2, query(noBlank).panels.size(), 'No (Blank) panel without include blank');
    }

    @IsTest
    static void panelsBeyondMaxPanelsAreCutWithANotice() {
        Map<String, Object> request = panelRequest();
        request.put('maxPanels', 2);
        request.put('panelSort', 'VALUE_ASC');

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual(2, result.panels.size());
        Assert.isTrue(result.cutPanels);
        Assert.areEqual(1, result.hiddenPanels);
        Assert.isTrue(result.panels[0].isBlank, 'Smallest total first: (Blank) 10');
        Assert.areEqual(typeValue(1), result.panels[1].value, 'Then type 2 (30); type 1 (150) cut');
        for (BoardChartEngine.ChartPoint point : result.points) {
            Assert.areNotEqual(typeValue(0), point.panelKey, 'No points of a cut panel');
        }
    }

    @IsTest
    static void cursorTierGroupsByPanelAcrossChunks() {
        Map<String, Decimal> expected = values(query(panelRequest()));

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 2;
        Map<String, Object> request = panelRequest();
        BoardChartQuery.ChartResult result = query(request);
        Assert.areEqual('CURSOR', result.mode);
        while (!result.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.cursor);
            next.put('offset', result.nextOffset);
            next.put('partialState', result.partialState);
            result = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }

        Assert.areEqual(3, result.panels.size());
        Map<String, Decimal> merged = values(result);
        Assert.areEqual(expected.keySet(), merged.keySet());
        for (String key : expected.keySet()) {
            Assert.areEqual(expected.get(key).setScale(2), merged.get(key).setScale(2), 'Cursor matches SOQL: ' + key);
        }
    }

    @IsTest
    static void datePanelFieldTakesAGranularity() {
        Map<String, Object> request = panelRequest();
        request.put('panelField', 'CloseDate');
        request.put('panelDateGranularity', 'CALENDAR_YEAR');

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual(1, result.panels.size());
        Assert.areEqual(String.valueOf(Date.today().year()), result.panels[0].label);
        Assert.areEqual('CALENDAR_YEAR', result.panelBy.dateGranularity);
    }

    @IsTest
    static void panelFieldMustDifferFromTheOtherGroupings() {
        Map<String, Object> sameAsGroup = panelRequest();
        sameAsGroup.put('panelField', 'StageName');
        Assert.areEqual('panelField', expectError(sameAsGroup).get('fieldPath'));

        Map<String, Object> sameAsSeries = panelRequest();
        sameAsSeries.put('stackByField', 'Type');
        Assert.areEqual('panelField', expectError(sameAsSeries).get('fieldPath'));
    }

    private static Map<String, Object> panelRequest() {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => 'StageName',
            'panelField' => 'Type',
            'measures' => new List<Object>{
                new Map<String, Object>{ 'aggregateFunction' => 'SUM', 'valueFieldApiName' => 'Amount' }
            },
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>()
        };
    }

    private static BoardChartQuery.ChartResult query(Map<String, Object> request) {
        return BoardChartQuery.queryChart(JSON.serialize(request));
    }

    /** Point values keyed `panelKey|categoryKey` (one Measure, no series field). */
    private static Map<String, Decimal> values(BoardChartQuery.ChartResult result) {
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(point.panelKey + '|' + point.categoryKey, point.value);
        }
        return values;
    }

    private static Map<String, Object> expectError(Map<String, Object> request) {
        try {
            query(request);
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), String.valueOf(payload));
            return payload;
        }
        Assert.fail('Expected CONFIG_ERROR for ' + JSON.serialize(request));
        return null;
    }

    private static String stageValue(Integer index) {
        return Opportunity.StageName.getDescribe().getPicklistValues()[index].getValue();
    }

    private static String typeValue(Integer index) {
        return activeTypes()[index].getValue();
    }

    private static String typeLabel(Integer index) {
        return activeTypes()[index].getLabel();
    }

    private static List<Schema.PicklistEntry> activeTypes() {
        List<Schema.PicklistEntry> active = new List<Schema.PicklistEntry>();
        for (Schema.PicklistEntry entry : Opportunity.Type.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                active.add(entry);
            }
        }
        return active;
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