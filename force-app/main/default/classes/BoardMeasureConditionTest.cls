/**
 * Entry-point seam for Measure conditions: the Chart and Metric query entry points with inserted Opportunities, Won
 * vs Closed side by side, conditions ANDed with the Filter context and Base filters, query grouping (observable via
 * `Limits.getQueries()`), the cursor tier, Bucket-field charts and Data providers.
 */
@IsTest
public class BoardMeasureConditionTest {
    private static final String PROVIDER = 'BoardMeasureConditionTest.CapturingProvider';
    private static List<BoardDataProviderRequest> received = new List<BoardDataProviderRequest>();

    /** Test provider: records each request and returns the standard leg's buckets. */
    public class CapturingProvider implements BoardDataProvider {
        public BoardDataProviderResult provide(BoardDataProviderRequest request) {
            received.add(request);
            BoardDataProviderResult result = new BoardDataProviderResult();
            result.includeStandardResult = true;
            return result;
        }
    }

    /**
     * MC Alpha: Won 100, Won 200, Lost 50, Open 1000. MC Beta: Won 300, Lost 70, Lost 30. MC Gamma: Open 500.
     */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = 'MC Alpha');
        Account beta = new Account(Name = 'MC Beta');
        Account gamma = new Account(Name = 'MC Gamma');
        insert new List<Account>{ alpha, beta, gamma };
        insert new List<Opportunity>{
            opportunity('MC 1', alpha.Id, 100, wonStage()),
            opportunity('MC 2', alpha.Id, 200, wonStage()),
            opportunity('MC 3', alpha.Id, 50, lostStage()),
            opportunity('MC 4', alpha.Id, 1000, openStage()),
            opportunity('MC 5', beta.Id, 300, wonStage()),
            opportunity('MC 6', beta.Id, 70, lostStage()),
            opportunity('MC 7', beta.Id, 30, lostStage()),
            opportunity('MC 8', gamma.Id, 500, openStage())
        };
    }

    @IsTest
    static void chartShowsWonAndClosedSideBySide() {
        BoardChartQuery.ChartResult result = query(
            chartRequest(
                new List<Object>{
                    withCondition(countMeasure(), won()),
                    withCondition(countMeasure(), closed()),
                    withCondition(measure('SUM', 'Amount'), won()),
                    measure('SUM', 'Amount')
                }
            )
        );

        Assert.areEqual('SINGLE', result.mode);
        List<String> labels = new List<String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            labels.add(category.label);
        }
        Assert.areEqual(new List<String>{ 'MC Alpha', 'MC Beta', 'MC Gamma' }, labels, 'By Won count, largest first');
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(2, values.get('MC Alpha|0'));
        Assert.areEqual(3, values.get('MC Alpha|1'));
        Assert.areEqual(300, values.get('MC Alpha|2'));
        Assert.areEqual(1350, values.get('MC Alpha|3'), 'No condition: every row');
        Assert.areEqual(1, values.get('MC Beta|0'));
        Assert.areEqual(3, values.get('MC Beta|1'));
        Assert.areEqual(300, values.get('MC Beta|2'));
        Assert.areEqual(0, values.get('MC Gamma|0'), 'No Won rows: a count of 0');
        Assert.areEqual(0, values.get('MC Gamma|1'));
        Assert.isNull(values.get('MC Gamma|2'), 'No Won rows: a blank sum');
        Assert.areEqual(500, values.get('MC Gamma|3'));
    }

    @IsTest
    static void measuresSharingAConditionRunAsOneQuery() {
        // Warm-up: describes and currency settings are read once per transaction.
        query(chartRequest(new List<Object>{ countMeasure() }));

        Integer before = Limits.getQueries();
        query(chartRequest(new List<Object>{ withCondition(countMeasure(), won()) }));
        Integer oneWonMeasure = Limits.getQueries() - before;

        before = Limits.getQueries();
        query(
            chartRequest(new List<Object>{ withCondition(countMeasure(), won()), withCondition(countMeasure(), won()) })
        );
        Integer twoWonMeasures = Limits.getQueries() - before;

        before = Limits.getQueries();
        query(
            chartRequest(
                new List<Object>{
                    withCondition(countMeasure(), won()),
                    withCondition(countMeasure(), closed()),
                    countMeasure()
                }
            )
        );
        Integer threeGroups = Limits.getQueries() - before;

        Assert.areEqual(oneWonMeasure, twoWonMeasures, 'Same source object and condition: one query');
        Assert.areEqual(oneWonMeasure + 2, threeGroups, 'One query per (source object, condition) group');
    }

    @IsTest
    static void conditionNarrowsTheFilterContextAndBaseFiltersNeverReplacesThem() {
        Map<String, Object> request = chartRequest(
            new List<Object>{ withCondition(countMeasure(), closed()), withCondition(measure('SUM', 'Amount'), won()) }
        );
        request.put(
            'filters',
            new List<Object>{
                new Map<String, Object>{
                    'filterId' => 'account',
                    'type' => 'LOOKUP',
                    'fieldPath' => 'AccountId',
                    'explicit' => true,
                    'operator' => 'IN',
                    'values' => new List<Object>{ accountId('MC Alpha') }
                }
            }
        );
        request.put('baseFilters', new List<Object>{ condition('Amount', 'GT', 60) });

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual(1, result.categories.size(), 'Filter context still applies');
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(2, values.get('MC Alpha|0'), 'Closed and Amount > 60: 100 and 200, not 50');
        Assert.areEqual(300, values.get('MC Alpha|1'));
        Assert.isTrue(result.appliedFilterIds.contains('account'));
    }

    @IsTest
    static void cursorTierEvaluatesEachMeasureConditionPerRecord() {
        List<Object> measures = new List<Object>{
            withCondition(countMeasure(), won()),
            withCondition(measure('SUM', 'Amount'), closed()),
            measure('AVG', 'Amount')
        };
        Map<String, Decimal> expected = valuesByLabel(query(chartRequest(measures)));

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 3;
        Map<String, Object> request = chartRequest(measures);
        BoardChartQuery.ChartResult result = query(request);
        Assert.areEqual('CURSOR', result.mode);
        while (!result.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.cursor);
            next.put('offset', result.nextOffset);
            next.put('partialState', result.partialState);
            result = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }
        Map<String, Decimal> merged = valuesByLabel(result);
        Assert.areEqual(expected.keySet(), merged.keySet());
        for (String key : expected.keySet()) {
            Decimal want = expected.get(key);
            Decimal got = merged.get(key);
            Assert.areEqual(
                want == null ? null : want.setScale(2),
                got == null ? null : got.setScale(2),
                'Cursor matches SOQL: ' + key
            );
        }
        Assert.areEqual(2, merged.get('MC Alpha|0'));
        Assert.areEqual(350, merged.get('MC Alpha|1'));
    }

    @IsTest
    static void cappedGroupsFallBackToTheCursorTier() {
        BoardQueryService.CHART_GROUP_LIMIT = 1;
        BoardChartQuery.ChartResult result = query(
            chartRequest(new List<Object>{ withCondition(countMeasure(), won()), countMeasure() })
        );

        Assert.areEqual('CURSOR', result.mode, 'A capped group query re-runs through cursor chunks');
        Assert.isTrue(result.isComplete);
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(2, values.get('MC Alpha|0'));
        Assert.areEqual(4, values.get('MC Alpha|1'));
        Assert.areEqual(0, values.get('MC Gamma|0'));
    }

    @IsTest
    static void bucketFieldChartAppliesMeasureConditionsPerBucket() {
        Map<String, Object> request = chartRequest(
            new List<Object>{ withCondition(countMeasure(), won()), countMeasure() }
        );
        request.put('groupByField', 'bucket:size');
        request.put(
            'bucketFields',
            new List<Object>{
                new Map<String, Object>{
                    'id' => 'size',
                    'label' => 'Size',
                    'rules' => new List<Object>{
                        new Map<String, Object>{ 'label' => 'Large', 'condition' => condition('Amount', 'GTE', 250) }
                    }
                }
            }
        );

        Map<String, Decimal> values = valuesByLabel(query(request));

        Assert.areEqual(1, values.get('Large|0'), 'Won and >= 250: 300');
        Assert.areEqual(3, values.get('Large|1'), '300, 500, 1000');
        Assert.areEqual(2, values.get('Other|0'), 'Won 100 and 200');
        Assert.areEqual(5, values.get('Other|1'));
    }

    @IsTest
    static void metricMeasuresEachAggregateTheirOwnCondition() {
        Map<String, Object> request = new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'measures' => new List<Object>{
                hidden(withCondition(countMeasure(), won())),
                withCondition(measure('SUM', 'Amount'), closed()),
                hidden(withCondition(measure('SUM', 'Amount'), won()))
            }
        };

        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(request));

        Assert.areEqual(1, result.visibleIndex);
        Assert.areEqual(750, (Decimal) result.value, 'Closed: 100 + 200 + 50 + 300 + 70 + 30');
        Assert.areEqual(3, Integer.valueOf(result.measures[0].value));
        Assert.areEqual(600, (Decimal) result.measures[2].value);
    }

    @IsTest
    static void childRelationshipConditionsAreAConfigError() {
        Map<String, Object> childCondition = new Map<String, Object>{
            'logic' => 'AND',
            'conditions' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'c1',
                    'fieldPath' => 'OpportunityLineItem(OpportunityId).Quantity',
                    'operator' => 'GT',
                    'value' => 1
                }
            }
        };
        try {
            query(chartRequest(new List<Object>{ withCondition(countMeasure(), childCondition) }));
            Assert.fail('Expected a config error');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), String.valueOf(payload));
        }
    }

    @IsTest
    static void dataProviderReceivesEachMeasureConditionAndItsStandardLegAppliesIt() {
        Map<String, Object> request = chartRequest(
            new List<Object>{ withCondition(countMeasure(), won()), measure('SUM', 'Amount') }
        );
        request.put('dataProvider', PROVIDER);

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual(1, received.size());
        BoardDataProviderRequest.Condition sent = received[0].measures[0].condition;
        Assert.isNotNull(sent, 'Measure condition passed to the provider');
        Assert.areEqual('AND', sent.logic);
        Assert.areEqual('IsWon', sent.children[0].path);
        Assert.areEqual('EQ', sent.children[0].operator);
        Assert.isNull(received[0].measures[1].condition);
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(2, values.get('MC Alpha|0'));
        Assert.areEqual(1350, values.get('MC Alpha|1'));
        Assert.areEqual(0, values.get('MC Gamma|0'));
    }

    @IsTest
    static void metricWithAMeasureConditionUsesTheCursorTier() {
        Map<String, Object> wonAmount = withCondition(measure('SUM', 'Amount'), won());
        Map<String, Object> request = new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'measures' => new List<Object>{ wonAmount }
        };
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 2;

        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(request));

        Assert.areEqual('CURSOR', result.mode);
        Map<String, Object> continuation = request.clone();
        continuation.remove('measures');
        continuation.putAll(wonAmount);
        Decimal sum = 0;
        BoardQueryService.AggregateChunk chunk = result.chunk;
        while (true) {
            sum += chunk.buckets[0].sum;
            if (chunk.isComplete) {
                break;
            }
            Map<String, Object> next = continuation.clone();
            next.put('cursor', chunk.cursor);
            next.put('offset', chunk.nextOffset);
            chunk = BoardQueryService.fetchAggregateChunk(JSON.serialize(next));
        }
        Assert.areEqual(600, sum, 'Won only: 100 + 200 + 300');
    }

    @IsTest
    static void dataProviderMetricWithAMeasureConditionUsesTheCursorTier() {
        Map<String, Object> wonAmount = withCondition(measure('SUM', 'Amount'), won());
        Map<String, Object> request = new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'measures' => new List<Object>{ wonAmount, hidden(countMeasure()) },
            'dataProvider' => PROVIDER
        };
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 3;

        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(request));

        Assert.areEqual('CURSOR', result.mode, 'Above the threshold: the cursor tier, not LIMIT_EXCEEDED');
        Assert.isFalse(result.isComplete);
        // The Metric widget's continuation: the request without `measures`, plus the visible Measure's fields.
        Map<String, Object> continuation = request.clone();
        continuation.remove('measures');
        continuation.putAll(wonAmount);
        Decimal sum = 0;
        Integer count = 0;
        BoardQueryService.AggregateChunk chunk = result.chunk;
        while (true) {
            for (BoardChartEngine.Partial bucket : chunk.buckets) {
                sum += bucket.sum;
                count += bucket.count;
            }
            if (chunk.isComplete) {
                break;
            }
            Map<String, Object> next = continuation.clone();
            next.put('cursor', chunk.cursor);
            next.put('offset', chunk.nextOffset);
            chunk = BoardQueryService.fetchAggregateChunk(JSON.serialize(next));
        }
        Assert.areEqual(600, sum, 'Won only, on every chunk: 100 + 200 + 300');
        Assert.areEqual(3, count);
        Assert.areEqual(1, received.size(), 'The provider runs once, on the first call');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    private static Map<String, Object> chartRequest(List<Object> measures) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => 'AccountId',
            'measures' => measures
        };
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        return new Map<String, Object>{ 'aggregateFunction' => aggregateFunction, 'valueFieldApiName' => valueField };
    }

    private static Map<String, Object> countMeasure() {
        return new Map<String, Object>{ 'aggregateFunction' => 'COUNT' };
    }

    private static Map<String, Object> withCondition(Map<String, Object> measure, Map<String, Object> condition) {
        measure.put('condition', condition);
        return measure;
    }

    private static Map<String, Object> hidden(Map<String, Object> measure) {
        measure.put('hidden', true);
        return measure;
    }

    private static Map<String, Object> won() {
        return tree(condition('IsWon', 'EQ', true));
    }

    private static Map<String, Object> closed() {
        return tree(condition('IsClosed', 'EQ', true));
    }

    private static Map<String, Object> tree(Map<String, Object> entry) {
        return new Map<String, Object>{ 'logic' => 'AND', 'conditions' => new List<Object>{ entry } };
    }

    private static Map<String, Object> condition(String fieldPath, String operator, Object value) {
        return new Map<String, Object>{
            'id' => 'mc-' + fieldPath,
            'fieldPath' => fieldPath,
            'operator' => operator,
            'value' => value
        };
    }

    private static BoardChartQuery.ChartResult query(Map<String, Object> request) {
        return BoardChartQuery.queryChart(JSON.serialize(request));
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

    private static String wonStage() {
        return [SELECT ApiName FROM OpportunityStage WHERE IsActive = TRUE AND IsClosed = TRUE AND IsWon = TRUE LIMIT 1]
        .ApiName;
    }

    private static String lostStage() {
        return [
            SELECT ApiName
            FROM OpportunityStage
            WHERE IsActive = TRUE AND IsClosed = TRUE AND IsWon = FALSE
            LIMIT 1
        ]
        .ApiName;
    }

    private static String openStage() {
        return [SELECT ApiName FROM OpportunityStage WHERE IsActive = TRUE AND IsClosed = FALSE LIMIT 1].ApiName;
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