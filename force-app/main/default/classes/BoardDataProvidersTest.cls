/**
 * Data provider seam: a test provider class implementing the global `BoardDataProvider` interface, named in Chart and
 * Metric widget requests and asserted at the query entry points.
 */
@IsTest
public class BoardDataProvidersTest {
    private static final String PROVIDER = 'BoardDataProvidersTest.ScriptedProvider';

    /** What `ScriptedProvider` returns next, the requests it received, and whether it reuses the standard query. */
    private static BoardDataProviderResult scripted;
    private static List<BoardDataProviderRequest> received = new List<BoardDataProviderRequest>();
    private static Boolean useStandardQueryHelper = false;

    /** Test provider: records each request and returns the scripted result (plus the standard leg via the helper). */
    public class ScriptedProvider implements BoardDataProvider {
        public BoardDataProviderResult provide(BoardDataProviderRequest request) {
            received.add(request);
            BoardDataProviderResult result = scripted == null ? new BoardDataProviderResult() : scripted;
            if (useStandardQueryHelper) {
                result.buckets.addAll(request.runStandardQuery());
            }
            return result;
        }
    }

    /** A class an Admin might name by mistake: it doesn't implement the interface. */
    public class NotAProvider {
    }

    /**
     * Opportunities: Board Alpha 100 & 200 (first stage), Board Beta 300 (first stage) & 50 (second stage).
     */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = 'Board Alpha');
        Account beta = new Account(Name = 'Board Beta');
        insert new List<Account>{ alpha, beta };
        insert new List<Opportunity>{
            opportunity('Board Opp 1', alpha.Id, 100, firstStage()),
            opportunity('Board Opp 2', alpha.Id, 200, firstStage()),
            opportunity('Board Opp 3', beta.Id, 300, firstStage()),
            opportunity('Board Opp 4', beta.Id, 50, secondStage())
        };
    }

    @IsTest
    static void providerReceivesTheStructuredRequestWithFilterIdsAndPaths() {
        Id alphaId = accountId('Board Alpha');
        Map<String, Object> request = chartRequest(
            new List<Object>{ measure('SUM', 'Amount'), measure('AVG', 'Amount'), countMeasure() }
        );
        request.put(
            'filters',
            new List<Object>{
                filter('stage', 'PICKLIST', 'StageName', new List<Object>{ firstStage() }),
                filter('region', 'PICKLIST', 'IGNORE', new List<Object>{ 'EMEA' }),
                filter('$recordContext', 'RECORD_CONTEXT', 'AccountId', new List<Object>{ alphaId })
            }
        );
        request.put(
            'baseFilters',
            new List<Object>{
                new Map<String, Object>{
                    'id' => 'hasAmount',
                    'fieldPath' => 'Amount',
                    'operator' => 'IS_NULL',
                    'value' => false
                }
            }
        );

        BoardChartQuery.ChartResult result = queryChart(request);

        Assert.areEqual(1, received.size(), 'The provider is called once per run');
        BoardDataProviderRequest sent = received[0];
        Assert.areEqual('chart', sent.widgetType);
        Assert.areEqual('Opportunity', sent.objectApiName);
        Assert.areEqual('AccountId', sent.groupByField);
        Assert.isNull(sent.seriesField);

        Assert.areEqual(1, sent.filters.size(), 'Only applied Board filters; Record context is separate');
        BoardDataProviderRequest.Condition stage = sent.filters[0];
        Assert.areEqual('stage', stage.filterId);
        Assert.areEqual('StageName', stage.path);
        Assert.areEqual('IN', stage.operator);
        Assert.areEqual(1, stage.values.size());
        Assert.areEqual(firstStage(), String.valueOf(stage.values[0]));

        Assert.areEqual(1, sent.recordContext.size());
        Assert.areEqual('$recordContext', sent.recordContext[0].filterId);
        Assert.areEqual('AccountId', sent.recordContext[0].path);
        Assert.areEqual(alphaId, (Id) sent.recordContext[0].values[0]);

        Assert.areEqual(1, sent.baseFilters.size());
        Assert.areEqual('hasAmount', sent.baseFilters[0].filterId);
        Assert.areEqual('Amount', sent.baseFilters[0].path);
        Assert.areEqual('NEQ', sent.baseFilters[0].operator);
        Assert.isNull(sent.baseFilters[0].values[0]);

        Assert.areEqual(3, sent.measures.size());
        Assert.areEqual('AVG', sent.measures[1].aggregateFunction);
        Assert.areEqual('Amount', sent.measures[1].valueFieldApiName);
        Assert.areEqual(1, sent.measures[1].index);
        Assert.isNull(sent.measures[1].condition, 'No Measure condition configured');
        Assert.areEqual('COUNT', sent.measures[2].aggregateFunction);

        Assert.areEqual(0, result.categories.size(), 'The provider replaced the standard query and returned nothing');
        Assert.isTrue(result.ignoredFilterIds.contains('region'));
        Assert.isTrue(result.appliedFilterIds.contains('stage'));
    }

    @IsTest
    static void partialBucketsMergeWithTheStandardLegForSumCountAndAvg() {
        scripted = new BoardDataProviderResult();
        scripted.includeStandardResult = true;
        // One more Alpha row of 400, and a category only the provider knows.
        scripted.buckets.add(bucket(accountId('Board Alpha'), 'Alpha from provider', 400, 1, 3));
        scripted.buckets.add(bucket('estimates', 'Estimates', 1000, 1, 3));

        BoardChartQuery.ChartResult result = queryChart(
            chartRequest(new List<Object>{ measure('SUM', 'Amount'), measure('AVG', 'Amount'), countMeasure() })
        );

        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(3, result.categories.size());
        Assert.areEqual(700, values.get('Board Alpha|0'), '100 + 200 + 400');
        Assert.areEqual(233.33, values.get('Board Alpha|1').setScale(2), 'AVG over both legs: 700 / 3');
        Assert.areEqual(3, values.get('Board Alpha|2'));
        Assert.areEqual(350, values.get('Board Beta|0'));
        Assert.areEqual(175, values.get('Board Beta|1').setScale(0));
        Assert.areEqual(2, values.get('Board Beta|2'));
        Assert.areEqual(1000, values.get('Estimates|0'));
        Assert.areEqual(1000, values.get('Estimates|1').setScale(0));
        Assert.areEqual(1, values.get('Estimates|2'));
        Assert.areEqual('Estimates', result.categories[0].label, 'Shaped like any chart: largest first');
    }

    @IsTest
    static void metricWidgetMergesProviderPartialsWithTheStandardLeg() {
        scripted = new BoardDataProviderResult();
        scripted.includeStandardResult = true;
        scripted.buckets.add(bucket(null, null, 1000, 1, 1));

        Map<String, Object> request = metricRequest('AVG');
        BoardQueryService.MetricResult average = BoardQueryService.queryMetric(JSON.serialize(request));
        Assert.areEqual(330, ((Decimal) average.value).setScale(0), '(650 + 1000) / (4 + 1)');
        Assert.areEqual('AVG', average.aggregateFunction);
        Assert.areEqual('CURRENCY', average.valueType);
        Assert.areEqual('metric', received[0].widgetType);
        Assert.isNull(received[0].groupByField);
        Assert.areEqual('Amount', received[0].measures[0].valueFieldApiName);

        BoardQueryService.MetricResult total = BoardQueryService.queryMetric(JSON.serialize(metricRequest('SUM')));
        Assert.areEqual(1650, (Decimal) total.value);
    }

    @IsTest
    static void chartProviderIsCalledOnceAcrossAForcedCursorRunAndMatchesTheSoqlTier() {
        scripted = new BoardDataProviderResult();
        scripted.includeStandardResult = true;
        // Same label as the standard leg: a group's label comes from whichever leg reads it first.
        scripted.buckets.add(bucket(accountId('Board Alpha'), 'Board Alpha', 400, 1, 3));
        scripted.buckets.add(bucket('estimates', 'Estimates', 1000, 1, 3));
        List<Object> measures = new List<Object>{ measure('SUM', 'Amount'), measure('AVG', 'Amount'), countMeasure() };
        Map<String, Decimal> expected = valuesByLabel(queryChart(chartRequest(measures)));
        received.clear();

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 1;
        Map<String, Object> request = chartRequest(measures);
        BoardChartQuery.ChartResult result = queryChart(request);
        Assert.areEqual('CURSOR', result.mode, 'The standard leg runs in the cursor tier');
        Assert.isFalse(result.isComplete);
        Assert.areEqual(1, received.size(), 'The first chunk call invokes the provider');
        Assert.isTrue(
            valuesByLabel(result).containsKey('Estimates|0'),
            'The provider buckets come back with the first chunk'
        );

        Integer calls = 1;
        while (!result.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.cursor);
            next.put('offset', result.nextOffset);
            next.put('partialState', result.partialState);
            result = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
            calls++;
        }
        Assert.areEqual(4, calls, 'One row per chunk');
        Assert.areEqual(1, received.size(), 'Continuation chunks never invoke the provider');
        Map<String, Decimal> merged = valuesByLabel(result);
        Assert.areEqual(expected.keySet(), merged.keySet());
        for (String key : expected.keySet()) {
            Assert.areEqual(expected.get(key).setScale(2), merged.get(key).setScale(2), 'Cursor matches SOQL: ' + key);
        }
    }

    @IsTest
    static void metricProviderIsCalledOnceAcrossAForcedCursorRunAndMergesLikeTheSoqlTier() {
        scripted = new BoardDataProviderResult();
        scripted.includeStandardResult = true;
        scripted.buckets.add(bucket(null, null, 1000, 1, 1));
        Map<String, Object> request = metricRequest('AVG');

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.MetricResult oneChunk = BoardQueryService.queryMetric(JSON.serialize(request));
        Assert.areEqual(330, ((Decimal) oneChunk.value).setScale(0), 'A scope read in one chunk is complete at once');
        Assert.isTrue(oneChunk.isComplete);
        received.clear();

        BoardQueryService.CURSOR_CHUNK_SIZE = 1;
        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(request));
        Assert.areEqual('CURSOR', result.mode);
        Assert.isFalse(result.isComplete);
        Assert.areEqual(1, received.size(), 'The first chunk call invokes the provider');

        // The Metric widget's client merge: add every chunk's buckets until complete.
        Decimal sum = 0;
        Integer count = 0;
        Decimal max;
        BoardQueryService.AggregateChunk chunk = result.chunk;
        Integer calls = 1;
        while (true) {
            for (BoardChartEngine.Partial entry : chunk.buckets) {
                sum += entry.sum;
                count += entry.count;
                max = entry.max != null && (max == null || entry.max > max) ? entry.max : max;
            }
            if (chunk.isComplete) {
                break;
            }
            Map<String, Object> next = request.clone();
            next.put('cursor', chunk.cursor);
            next.put('offset', chunk.nextOffset);
            chunk = BoardQueryService.fetchAggregateChunk(JSON.serialize(next));
            calls++;
        }
        Assert.areEqual(4, calls, 'One row per chunk');
        Assert.areEqual(1, received.size(), 'Continuation chunks never invoke the provider');
        Assert.areEqual(330, (sum / count).setScale(0), '(650 + 1000) / (4 + 1), as in the SOQL tier');
        Assert.areEqual(1000, max);
    }

    @IsTest
    static void standardLegBeyondTheCursorTierAndTheHelperBeyondTheThresholdAreLimitExceeded() {
        scripted = new BoardDataProviderResult();
        scripted.includeStandardResult = true;
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_MAX_ROWS = 3;
        Assert.areEqual('LIMIT_EXCEEDED', expectChartCategory(chartRequest(new List<Object>{ countMeasure() })));

        BoardQueryService.CURSOR_MAX_ROWS = 200000;
        scripted = new BoardDataProviderResult();
        useStandardQueryHelper = true;
        Assert.areEqual(
            'LIMIT_EXCEEDED',
            expectChartCategory(chartRequest(new List<Object>{ countMeasure() })),
            'The helper has no cursor tier: it returns complete buckets only'
        );
    }

    @IsTest
    static void engineHelperRunsTheStandardQueryForARequest() {
        List<Object> measures = new List<Object>{ measure('SUM', 'Amount'), measure('AVG', 'Amount'), countMeasure() };
        Map<String, Object> plain = chartRequest(measures);
        plain.remove('dataProvider');
        Map<String, Decimal> expected = valuesByLabel(queryChart(plain));

        useStandardQueryHelper = true;
        Map<String, Decimal> viaHelper = valuesByLabel(queryChart(chartRequest(measures)));

        Assert.areEqual(expected.keySet(), viaHelper.keySet());
        for (String key : expected.keySet()) {
            Assert.areEqual(expected.get(key).setScale(2), viaHelper.get(key).setScale(2), key);
        }

        BoardQueryService.MetricResult metric = BoardQueryService.queryMetric(JSON.serialize(metricRequest('SUM')));
        Assert.areEqual(650, (Decimal) metric.value, 'The helper serves Metric widgets too');
    }

    @IsTest
    static void providerAppliedAndIgnoredFilterIdsSurfaceOnTheWidget() {
        scripted = new BoardDataProviderResult();
        scripted.ignoredFilterIds.add('stage');
        scripted.appliedFilterIds.add('region');
        Map<String, Object> request = chartRequest(new List<Object>{ countMeasure() });
        request.put(
            'filters',
            new List<Object>{
                filter('stage', 'PICKLIST', 'StageName', new List<Object>{ firstStage() }),
                filter('region', 'PICKLIST', 'IGNORE', new List<Object>{ 'EMEA' })
            }
        );

        BoardChartQuery.ChartResult result = queryChart(request);

        Assert.areEqual(new List<String>{ 'region' }, result.appliedFilterIds);
        Assert.areEqual(new List<String>{ 'stage' }, result.ignoredFilterIds);
    }

    @IsTest
    static void missingOrNonImplementingProviderClassIsAConfigError() {
        Map<String, Object> missing = chartRequest(new List<Object>{ countMeasure() });
        missing.put('dataProvider', 'NoSuchBoardDataProviderClass');
        Map<String, Object> error = expectChartError(missing);
        Assert.areEqual('dataProvider', error.get('fieldPath'));
        Assert.isTrue(String.valueOf(error.get('message')).contains('NoSuchBoardDataProviderClass'));

        Map<String, Object> wrongType = chartRequest(new List<Object>{ countMeasure() });
        wrongType.put('dataProvider', 'BoardDataProvidersTest.NotAProvider');
        error = expectChartError(wrongType);
        Assert.areEqual('dataProvider', error.get('fieldPath'));
        Assert.isTrue(String.valueOf(error.get('message')).contains('BoardDataProvider'));

        Map<String, Object> metric = metricRequest('SUM');
        metric.put('dataProvider', 'NoSuchBoardDataProviderClass');
        try {
            BoardQueryService.queryMetric(JSON.serialize(metric));
            Assert.fail('Expected a config error');
        } catch (AuraHandledException failure) {
            Assert.areEqual('CONFIG_ERROR', payload(failure).get('category'));
        }
    }

    @IsTest
    static void measureRejectionAndUnmergeableResultsAreConfigErrors() {
        scripted = new BoardDataProviderResult();
        scripted.rejectMeasure(1, 'Estimates have no product count.');
        Map<String, Object> error = expectChartError(
            chartRequest(new List<Object>{ measure('SUM', 'Amount'), countMeasure() })
        );
        Assert.areEqual('measures', error.get('fieldPath'));
        Assert.isTrue(String.valueOf(error.get('message')).contains('Estimates have no product count.'));

        scripted = new BoardDataProviderResult();
        scripted.buckets.add(bucket('estimates', 'Estimates', 1000, 1, 3));
        error = expectChartError(chartRequest(new List<Object>{ measure('SUM', 'Amount') }));
        Assert.areEqual('measures', error.get('fieldPath'), 'A bucket must carry one partial per Measure');

        received.clear();
        error = expectChartError(chartRequest(new List<Object>{ measure('COUNT_DISTINCT', 'Name') }));
        Assert.areEqual('measures', error.get('fieldPath'), 'COUNT_DISTINCT partials cannot merge');
        Assert.areEqual(0, received.size(), 'The provider is not called for an unmergeable Measure');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    private static Map<String, Object> chartRequest(List<Object> measures) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => 'AccountId',
            'measures' => measures,
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'dataProvider' => PROVIDER
        };
    }

    private static Map<String, Object> metricRequest(String aggregateFunction) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'aggregateFunction' => aggregateFunction,
            'valueFieldApiName' => 'Amount',
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'dataProvider' => PROVIDER
        };
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        return new Map<String, Object>{ 'aggregateFunction' => aggregateFunction, 'valueFieldApiName' => valueField };
    }

    private static Map<String, Object> countMeasure() {
        return new Map<String, Object>{ 'aggregateFunction' => 'COUNT' };
    }

    private static Map<String, Object> filter(String filterId, String type, String fieldPath, List<Object> values) {
        return new Map<String, Object>{
            'filterId' => filterId,
            'type' => type,
            'fieldPath' => fieldPath,
            'explicit' => true,
            'operator' => 'IN',
            'values' => values
        };
    }

    /**
     * One provider bucket with `measureCount` partials, each of `count` rows adding up to `sum` (COUNT reads `count`).
     */
    private static BoardDataProviderResult.Bucket bucket(
        String value,
        String label,
        Decimal sum,
        Integer count,
        Integer measureCount
    ) {
        BoardDataProviderResult.Bucket entry = new BoardDataProviderResult.Bucket(value, label, null, null);
        for (Integer i = 0; i < measureCount; i++) {
            entry.measures.add(new BoardDataProviderResult.Partial(sum, count, sum, sum));
        }
        return entry;
    }

    private static BoardChartQuery.ChartResult queryChart(Map<String, Object> request) {
        return BoardChartQuery.queryChart(JSON.serialize(request));
    }

    private static Map<String, Object> expectChartError(Map<String, Object> request) {
        try {
            queryChart(request);
        } catch (AuraHandledException failure) {
            Map<String, Object> error = payload(failure);
            Assert.areEqual('CONFIG_ERROR', error.get('category'), String.valueOf(error));
            return error;
        }
        Assert.fail('Expected a config error for ' + JSON.serialize(request));
        return null;
    }

    private static String expectChartCategory(Map<String, Object> request) {
        try {
            queryChart(request);
        } catch (AuraHandledException failure) {
            return String.valueOf(payload(failure).get('category'));
        }
        Assert.fail('Expected an error for ' + JSON.serialize(request));
        return null;
    }

    private static Map<String, Object> payload(AuraHandledException failure) {
        return (Map<String, Object>) JSON.deserializeUntyped(failure.getMessage());
    }

    /** Point values keyed `categoryLabel|measureIndex` (single-series charts). */
    private static Map<String, Decimal> valuesByLabel(BoardChartQuery.ChartResult result) {
        Map<String, String> labels = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            labels.put(category.key, category.label);
        }
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(labels.get(point.categoryKey) + '|' + point.measureIndex, point.value);
        }
        return values;
    }

    private static Id accountId(String name) {
        return [SELECT Id FROM Account WHERE Name = :name LIMIT 1].Id;
    }

    private static String firstStage() {
        return Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
    }

    private static String secondStage() {
        return Opportunity.StageName.getDescribe().getPicklistValues()[1].getValue();
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