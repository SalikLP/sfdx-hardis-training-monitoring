/**
 * Entry-point seam for Bucket fields in Small multiples on the Chart query: a Bucket field as the Panel field (one
 * Panel per bucket, in bucket order, the fallback Panel per the fallback setting), and a Bucket field as the category
 * or series of a chart with a plain Panel field; SOQL and cursor tiers give the same Panels and points.
 */
@IsTest
private class BoardChartQueryBucketPanelTest {
    /**
     * Opportunities: Panel Bucket Opp 1 (100) and 2 (200) on Account Alpha in the first stage; Opp 3 (350) and 4 (no
     * Amount) on Account Beta in the second stage. Deal size buckets: Small (< 150) Opp 1, Big (>= 150) Opps 2 and 3,
     * fallback Other Opp 4.
     */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = 'Panel Bucket Alpha');
        Account beta = new Account(Name = 'Panel Bucket Beta');
        insert new List<Account>{ alpha, beta };
        insert new List<Opportunity>{
            opportunity('Panel Bucket Opp 1', alpha.Id, 100, stageValue(0)),
            opportunity('Panel Bucket Opp 2', alpha.Id, 200, stageValue(0)),
            opportunity('Panel Bucket Opp 3', beta.Id, 350, stageValue(1)),
            opportunity('Panel Bucket Opp 4', beta.Id, null, stageValue(1))
        };
    }

    @IsTest
    static void bucketPanelFieldDrawsOnePanelPerBucketInBucketOrder() {
        BoardChartQuery.ChartResult result = query(bucketPanelRequest(null));

        Assert.areEqual('SINGLE', result.mode);
        Assert.areEqual('bucket:dealSize', result.panelBy.fieldPath);
        Assert.areEqual('BUCKET', result.panelBy.dataType);
        Assert.areEqual('StageName', result.groupBy.fieldPath);
        Assert.areEqual(
            new List<String>{ 'Small', 'Big', 'Other' },
            panelLabels(result),
            'Rule order, the fallback Panel last (not alphabetical)'
        );
        Assert.isFalse(result.cutPanels);
        Map<String, Decimal> points = pointsByLabels(result);
        Assert.areEqual(100, points.get('Small|' + stageValue(0) + '||0'));
        Assert.areEqual(1, points.get('Small|' + stageValue(0) + '||1'));
        Assert.areEqual(200, points.get('Big|' + stageValue(0) + '||0'));
        Assert.areEqual(350, points.get('Big|' + stageValue(1) + '||0'));
        Assert.areEqual(1, points.get('Other|' + stageValue(1) + '||1'), 'Opp 4 matches no rule: the fallback Panel');
        Assert.isFalse(points.containsKey('Small|' + stageValue(1) + '||1'), 'A gap, no point');
    }

    @IsTest
    static void excludedFallbackHasNoPanel() {
        BoardChartQuery.ChartResult result = query(
            bucketPanelRequest(new Map<String, Object>{ 'label' => 'Rest', 'exclude' => true })
        );

        Assert.areEqual(new List<String>{ 'Small', 'Big' }, panelLabels(result));
        for (BoardChartEngine.ChartPoint point : result.points) {
            Assert.areNotEqual('Rest', point.panelKey, 'Excluded rows are left out');
        }
    }

    @IsTest
    static void renamedFallbackPanelTakesItsLabel() {
        BoardChartQuery.ChartResult result = query(
            bucketPanelRequest(new Map<String, Object>{ 'label' => 'Unsized', 'exclude' => false })
        );

        Assert.areEqual(new List<String>{ 'Small', 'Big', 'Unsized' }, panelLabels(result));
    }

    @IsTest
    static void bucketPanelsFollowMaxPanelsAndValueSort() {
        Map<String, Object> request = bucketPanelRequest(null);
        request.put('maxPanels', 2);
        request.put('panelSort', 'VALUE_DESC');

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual(new List<String>{ 'Big', 'Small' }, panelLabels(result), 'Big 550, Small 100; Other 0 cut');
        Assert.isTrue(result.cutPanels);
        Assert.areEqual(1, result.hiddenPanels);
    }

    @IsTest
    static void bucketPanelLeavesOutBlankCategoriesWithoutIncludeBlank() {
        Map<String, Object> request = bucketPanelRequest(null);
        request.put('groupByField', 'NextStep');
        request.put('includeNullBucket', false);

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual(0, result.panels.size(), 'Every Next step is blank: no rows, no Panels');
    }

    @IsTest
    static void bucketCategoryWithAPlainPanelField() {
        Map<String, Object> request = chartRequest('bucket:dealSize', dealSize(null));
        request.put('panelField', 'AccountId');

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual('bucket:dealSize', result.groupBy.fieldPath);
        Assert.areEqual('AccountId', result.panelBy.fieldPath);
        Assert.areEqual(new List<String>{ 'Panel Bucket Alpha', 'Panel Bucket Beta' }, panelLabels(result));
        Map<String, Decimal> points = pointsByLabels(result);
        Assert.areEqual(100, points.get('Panel Bucket Alpha|Small||0'));
        Assert.areEqual(200, points.get('Panel Bucket Alpha|Big||0'));
        Assert.areEqual(350, points.get('Panel Bucket Beta|Big||0'));
        Assert.areEqual(1, points.get('Panel Bucket Beta|Other||1'));
        Assert.isFalse(points.containsKey('Panel Bucket Alpha|Other||1'));
    }

    @IsTest
    static void bucketSeriesWithAPlainPanelField() {
        Map<String, Object> request = chartRequest('StageName', dealSize(null));
        request.put('stackByField', 'bucket:dealSize');
        request.put('panelField', 'AccountId');
        request.put('measures', new List<Object>{ countMeasure() });

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual('bucket:dealSize', result.stackBy.fieldPath);
        Assert.areEqual(2, result.panels.size());
        Map<String, Decimal> points = pointsByLabels(result);
        Assert.areEqual(1, points.get('Panel Bucket Alpha|' + stageValue(0) + '|Small|0'));
        Assert.areEqual(1, points.get('Panel Bucket Alpha|' + stageValue(0) + '|Big|0'));
        Assert.areEqual(1, points.get('Panel Bucket Beta|' + stageValue(1) + '|Big|0'));
        Assert.areEqual(1, points.get('Panel Bucket Beta|' + stageValue(1) + '|Other|0'));
        Assert.areEqual(4, points.size(), String.valueOf(points));
    }

    @IsTest
    static void cursorTierGivesTheSamePanelsAsTheSoqlTier() {
        // Bucket as the Panel field, a plain category.
        assertParity(bucketPanelRequest(null));

        // Bucket as the Panel field with an excluded fallback and a plain series field.
        Map<String, Object> withSeries = bucketPanelRequest(
            new Map<String, Object>{ 'label' => 'Rest', 'exclude' => true }
        );
        withSeries.put('stackByField', 'AccountId');
        withSeries.put('measures', new List<Object>{ measure('SUM', 'Amount') });
        assertParity(withSeries);

        // Bucket as the category of a plain Panel field.
        Map<String, Object> category = chartRequest('bucket:dealSize', dealSize(null));
        category.put('panelField', 'AccountId');
        assertParity(category);

        // Bucket as the series of a plain Panel field.
        Map<String, Object> series = chartRequest('StageName', dealSize(null));
        series.put('stackByField', 'bucket:dealSize');
        series.put('panelField', 'AccountId');
        series.put('measures', new List<Object>{ measure('SUM', 'Amount') });
        assertParity(series);
    }

    @IsTest
    static void bucketPanelTotalsCoverEachBucketIncludingAverages() {
        Map<String, Object> request = bucketPanelRequest(null);
        request.put('measures', new List<Object>{ measure('SUM', 'Amount'), hidden(measure('AVG', 'Amount')) });
        request.put('panelHeadlineMeasure', 1);

        Map<String, List<Decimal>> totals = panelTotals(query(request));

        Assert.areEqual(new Set<String>{ 'Small', 'Big', 'Other' }, totals.keySet());
        Assert.areEqual(100, totals.get('Small')[0]);
        Assert.areEqual(100, totals.get('Small')[1].setScale(2));
        Assert.areEqual(550, totals.get('Big')[0]);
        Assert.areEqual(275, totals.get('Big')[1].setScale(2), 'AVG over the bucket rows, not blank or summed');
        Assert.isNull(totals.get('Other')[1], 'Opp 4 has no Amount');

        Map<String, Object> excluded = bucketPanelRequest(
            new Map<String, Object>{ 'label' => 'Rest', 'exclude' => true }
        );
        excluded.put('measures', request.get('measures'));
        excluded.put('panelHeadlineMeasure', 1);
        Assert.areEqual(new Set<String>{ 'Small', 'Big' }, panelTotals(query(excluded)).keySet());
    }

    @IsTest
    static void plainPanelTotalsOfABucketCategoryCoverOnlyBucketedRows() {
        Map<String, Object> line = measure('AVG', 'Amount');
        line.put('render', BoardChartQuery.REFERENCE_LINE_RENDER);
        Map<String, Object> request = chartRequest('bucket:dealSize', dealSize(null));
        request.put('panelField', 'AccountId');
        request.put('measures', new List<Object>{ countMeasure(), line });

        Map<String, List<Decimal>> totals = panelTotalsByLabel(query(request));

        Assert.areEqual(2, totals.get('Panel Bucket Alpha')[0]);
        Assert.areEqual(150, totals.get('Panel Bucket Alpha')[1].setScale(2));
        Assert.areEqual(2, totals.get('Panel Bucket Beta')[0], 'Opp 4 in the fallback bucket');
        Assert.areEqual(350, totals.get('Panel Bucket Beta')[1].setScale(2));

        request.put('bucketFields', dealSize(new Map<String, Object>{ 'label' => 'Rest', 'exclude' => true }));
        Assert.areEqual(1, panelTotalsByLabel(query(request)).get('Panel Bucket Beta')[0], 'Excluded rows stay out');
    }

    @IsTest
    static void cursorTierPanelTotalsMatchSoqlWithBucketFields() {
        Map<String, Object> bucketPanel = bucketPanelRequest(null);
        bucketPanel.put('measures', new List<Object>{ measure('SUM', 'Amount'), hidden(measure('AVG', 'Amount')) });
        bucketPanel.put('panelHeadlineMeasure', 1);
        assertTotalsParity(bucketPanel);

        Map<String, Object> bucketCategory = chartRequest(
            'bucket:dealSize',
            dealSize(new Map<String, Object>{ 'label' => 'Rest', 'exclude' => true })
        );
        bucketCategory.put('panelField', 'AccountId');
        bucketCategory.put('measures', new List<Object>{ measure('SUM', 'Amount'), hidden(measure('AVG', 'Amount')) });
        bucketCategory.put('panelHeadlineMeasure', 1);
        assertTotalsParity(bucketCategory);
    }

    @IsTest
    static void rejectsASecondBucketFieldOrAnUnknownOne() {
        Map<String, Object> twoBuckets = bucketPanelRequest(null);
        twoBuckets.put('groupByField', 'bucket:dealSize');
        Assert.areEqual('panelField', expectError(twoBuckets).get('fieldPath'));

        Map<String, Object> bucketSeries = bucketPanelRequest(null);
        bucketSeries.put('stackByField', 'bucket:dealSize');
        Assert.areEqual('panelField', expectError(bucketSeries).get('fieldPath'));

        Map<String, Object> unknown = bucketPanelRequest(null);
        unknown.put('panelField', 'bucket:missing');
        Assert.areEqual('bucket:missing', expectError(unknown).get('fieldPath'));

        Map<String, Object> noCategory = bucketPanelRequest(null);
        noCategory.remove('groupByField');
        Assert.areEqual('groupByField', expectError(noCategory).get('fieldPath'));

        Map<String, Object> samePanel = chartRequest('bucket:dealSize', dealSize(null));
        samePanel.put('stackByField', 'AccountId');
        samePanel.put('panelField', 'AccountId');
        samePanel.put('measures', new List<Object>{ countMeasure() });
        Assert.areEqual('panelField', expectError(samePanel).get('fieldPath'));
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** Opportunities by stage in one Panel per deal size bucket; SUM of Amount and COUNT. */
    private static Map<String, Object> bucketPanelRequest(Map<String, Object> fallback) {
        Map<String, Object> request = chartRequest('StageName', dealSize(fallback));
        request.put('panelField', 'bucket:dealSize');
        return request;
    }

    /** Small (Amount < 150), Big (Amount >= 150); rows without an Amount fall back. */
    private static List<Object> dealSize(Map<String, Object> fallback) {
        Map<String, Object> config = new Map<String, Object>{
            'id' => 'dealSize',
            'label' => 'Deal size',
            'rules' => new List<Object>{
                rule('Small', condition('Amount', 'LT', 150)),
                rule('Big', condition('Amount', 'GTE', 150))
            }
        };
        if (fallback != null) {
            config.put('fallback', fallback);
        }
        return new List<Object>{ config };
    }

    private static Map<String, Object> rule(String label, Map<String, Object> condition) {
        return new Map<String, Object>{ 'label' => label, 'condition' => condition };
    }

    private static Map<String, Object> condition(String fieldPath, String operator, Object value) {
        return new Map<String, Object>{
            'logic' => 'AND',
            'conditions' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'c1',
                    'fieldPath' => fieldPath,
                    'operator' => operator,
                    'value' => value
                }
            }
        };
    }

    private static Map<String, Object> chartRequest(String groupByField, List<Object> bucketFields) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => groupByField,
            'bucketFields' => bucketFields,
            'baseFilters' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'bf1',
                    'fieldPath' => 'Name',
                    'operator' => 'LIKE',
                    'value' => 'Panel Bucket'
                }
            },
            'measures' => new List<Object>{ measure('SUM', 'Amount'), countMeasure() }
        };
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        return new Map<String, Object>{ 'aggregateFunction' => aggregateFunction, 'valueFieldApiName' => valueField };
    }

    private static Map<String, Object> countMeasure() {
        return new Map<String, Object>{ 'aggregateFunction' => 'COUNT' };
    }

    private static BoardChartQuery.ChartResult query(Map<String, Object> request) {
        return BoardChartQuery.queryChart(JSON.serialize(request));
    }

    /**
     * Runs `request` once through SOQL and once forced through the cursor tier (one row per chunk) and asserts the
     * same Panels, categories, series and point values.
     */
    private static void assertParity(Map<String, Object> request) {
        BoardChartQuery.ChartResult soql = query(request);
        Assert.areEqual('SINGLE', soql.mode);

        Integer threshold = BoardQueryService.CURSOR_AGGREGATE_THRESHOLD;
        Integer chunkSize = BoardQueryService.CURSOR_CHUNK_SIZE;
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 1;
        BoardChartQuery.ChartResult cursor = query(request);
        Assert.areEqual('CURSOR', cursor.mode);
        while (!cursor.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', cursor.cursor);
            next.put('offset', cursor.nextOffset);
            next.put('partialState', cursor.partialState);
            cursor = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = threshold;
        BoardQueryService.CURSOR_CHUNK_SIZE = chunkSize;

        Assert.areEqual(panelLabels(soql), panelLabels(cursor), 'Same Panels in the same order');
        Assert.areEqual(keyLabels(soql.categories), keyLabels(cursor.categories), 'Same categories');
        Assert.areEqual(keyLabels(soql.series), keyLabels(cursor.series), 'Same series');
        Assert.areEqual(
            pointsByLabels(soql),
            pointsByLabels(cursor),
            'Cursor tier matches SOQL for ' + JSON.serialize(request)
        );
    }

    private static Map<String, Object> hidden(Map<String, Object> measure) {
        measure.put('hidden', true);
        return measure;
    }

    /** Panel totals keyed by Panel key. */
    private static Map<String, List<Decimal>> panelTotals(BoardChartQuery.ChartResult result) {
        Assert.isNotNull(result.panelTotals, 'Panel totals returned');
        Map<String, List<Decimal>> totals = new Map<String, List<Decimal>>();
        for (BoardChartPanelTotals.PanelTotal total : result.panelTotals) {
            totals.put(total.panelKey, total.values);
        }
        return totals;
    }

    /** Panel totals keyed by Panel label. */
    private static Map<String, List<Decimal>> panelTotalsByLabel(BoardChartQuery.ChartResult result) {
        Map<String, String> labels = new Map<String, String>();
        for (BoardChartEngine.ChartKey panel : result.panels) {
            labels.put(panel.key, panel.label);
        }
        Map<String, List<Decimal>> byKey = panelTotals(result);
        Map<String, List<Decimal>> byLabel = new Map<String, List<Decimal>>();
        for (String key : byKey.keySet()) {
            byLabel.put(labels.get(key), byKey.get(key));
        }
        return byLabel;
    }

    /** Panel totals (2 decimals) of `request` in SOQL equal those of the cursor tier, one row per chunk. */
    private static void assertTotalsParity(Map<String, Object> request) {
        BoardChartQuery.ChartResult soql = query(request);
        Assert.areEqual('SINGLE', soql.mode);
        Integer threshold = BoardQueryService.CURSOR_AGGREGATE_THRESHOLD;
        Integer chunkSize = BoardQueryService.CURSOR_CHUNK_SIZE;
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 1;
        BoardChartQuery.ChartResult cursor = query(request);
        Assert.areEqual('CURSOR', cursor.mode);
        while (!cursor.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', cursor.cursor);
            next.put('offset', cursor.nextOffset);
            next.put('partialState', cursor.partialState);
            cursor = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = threshold;
        BoardQueryService.CURSOR_CHUNK_SIZE = chunkSize;

        Map<String, List<Decimal>> expected = panelTotals(soql);
        Map<String, List<Decimal>> merged = panelTotals(cursor);
        Assert.areEqual(expected.keySet(), merged.keySet(), 'Same Panels with totals');
        for (String key : expected.keySet()) {
            for (Integer i = 0; i < expected.get(key).size(); i++) {
                Decimal want = expected.get(key)[i];
                Decimal got = merged.get(key)[i];
                Assert.areEqual(
                    want == null ? null : want.setScale(2),
                    got == null ? null : got.setScale(2),
                    key + ' Measure ' + i
                );
            }
        }
    }

    private static List<String> panelLabels(BoardChartQuery.ChartResult result) {
        List<String> labels = new List<String>();
        for (BoardChartEngine.ChartKey panel : result.panels) {
            labels.add(panel.label);
        }
        return labels;
    }

    private static List<String> keyLabels(List<BoardChartEngine.ChartKey> keys) {
        List<String> labels = new List<String>();
        for (BoardChartEngine.ChartKey key : keys) {
            labels.add(key.key + '=' + key.label);
        }
        return labels;
    }

    /**
     * Point values (2 decimals) keyed `panelLabel|categoryLabel|seriesLabel|measureIndex`; a stage category by its
     * value, no series as an empty label.
     */
    private static Map<String, Decimal> pointsByLabels(BoardChartQuery.ChartResult result) {
        Map<String, String> labels = new Map<String, String>();
        for (BoardChartEngine.ChartKey panel : result.panels) {
            labels.put('p' + panel.key, panel.label);
        }
        for (BoardChartEngine.ChartKey category : result.categories) {
            labels.put('c' + category.key, result.groupBy.fieldPath == 'StageName' ? category.key : category.label);
        }
        for (BoardChartEngine.ChartKey series : result.series) {
            labels.put('s' + series.key, series.label);
        }
        Map<String, Decimal> points = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            String seriesLabel = point.seriesKey == BoardChartEngine.VALUE_KEY ? '' : labels.get('s' + point.seriesKey);
            points.put(
                labels.get('p' + point.panelKey) +
                    '|' +
                    labels.get('c' + point.categoryKey) +
                    '|' +
                    seriesLabel +
                    '|' +
                    point.measureIndex,
                point.value == null ? null : point.value.setScale(2)
            );
        }
        return points;
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

    private static Opportunity opportunity(String name, Id accountId, Decimal amount, String stage) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            Amount = amount,
            CloseDate = Date.today(),
            StageName = stage
        );
    }
}