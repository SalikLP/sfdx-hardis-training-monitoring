/**
 * Data provider seam for the virtual-row helpers (`BoardDataProviderRows`): a test provider builds virtual rows (path to
 * value) with the helpers and its buckets merge into the engine's under identical keys and labels; each helper's keys
 * and labels match the engine's for the same values, in the SOQL tier and the cursor tier.
 */
@IsTest
private class BoardDataProviderRowsTest {
    private static final String PROVIDER = 'BoardDataProviderRowsTest.VirtualRowProvider';
    private static final Date FEBRUARY = Date.newInstance(2026, 2, 15);
    private static final Date NOVEMBER = Date.newInstance(2026, 11, 3);

    /** The virtual rows `VirtualRowProvider` aggregates (path to value) and the requests it received. */
    private static List<Map<String, Object>> virtualRows = new List<Map<String, Object>>();
    private static List<BoardDataProviderRequest> received = new List<BoardDataProviderRequest>();

    /**
     * Test provider: keeps the virtual rows inside the Widget scope, keys each by the request's category field with
     * the helpers (Bucket field, date bucket or reference label), and returns one partial per Measure per bucket on
     * top of the standard result.
     */
    public class VirtualRowProvider implements BoardDataProvider {
        public BoardDataProviderResult provide(BoardDataProviderRequest request) {
            received.add(request);
            BoardDataProviderRows helpers = new BoardDataProviderRows(request);
            Map<String, BoardDataProviderResult.Bucket> buckets = new Map<String, BoardDataProviderResult.Bucket>();
            for (Map<String, Object> row : virtualRows) {
                if (!helpers.inScope(row)) {
                    continue;
                }
                List<String> key = keyOf(helpers, request, row);
                if (key == null) {
                    continue; // Excluded by the Bucket field's fallback.
                }
                BoardDataProviderResult.Bucket bucket = buckets.get(key[0]);
                if (bucket == null) {
                    bucket = new BoardDataProviderResult.Bucket(key[0], key[1], null, null);
                    for (BoardDataProviderRequest.Measure measure : request.measures) {
                        bucket.measures.add(new BoardDataProviderResult.Partial());
                    }
                    buckets.put(key[0], bucket);
                }
                for (BoardDataProviderRequest.Measure measure : request.measures) {
                    if (measure.condition != null && !BoardDataProviderRows.matches(measure.condition, row)) {
                        continue;
                    }
                    BoardDataProviderResult.Partial partial = bucket.measures[measure.index];
                    Object raw = measure.valueFieldApiName == null
                        ? 1
                        : BoardDataProviderRows.valueAt(row, measure.valueFieldApiName);
                    Decimal value = raw == null ? null : Decimal.valueOf(String.valueOf(raw));
                    if (value == null) {
                        continue;
                    }
                    partial.sum += measure.valueFieldApiName == null ? 0 : value;
                    partial.count++;
                    partial.min = partial.min == null || value < partial.min ? value : partial.min;
                    partial.max = partial.max == null || value > partial.max ? value : partial.max;
                }
            }
            BoardDataProviderResult result = new BoardDataProviderResult();
            result.includeStandardResult = true;
            result.buckets.addAll(buckets.values());
            return result;
        }

        private List<String> keyOf(
            BoardDataProviderRows helpers,
            BoardDataProviderRequest request,
            Map<String, Object> row
        ) {
            String field = request.groupByField;
            if (field.startsWith('bucket:')) {
                String label = helpers.bucketLabel(field, row);
                return label == null ? null : new List<String>{ label, label };
            }
            Object value = BoardDataProviderRows.valueAt(row, field);
            if (request.dateGranularity != null) {
                return new List<String>{
                    BoardDataProviderRows.dateBucketKey(value, request.dateGranularity),
                    BoardDataProviderRows.dateBucketLabel(value, request.dateGranularity)
                };
            }
            Id recordId = (Id) value;
            return new List<String>{
                String.valueOf(recordId),
                BoardDataProviderRows.referenceLabels(new Set<Id>{ recordId }).get(recordId)
            };
        }
    }

    /**
     * Opportunities: Rows Opp 1 (100, Web, February) and 2 (200, November) on Rows Alpha in the first stage; Rows Opp
     * 3 (350, November) on Rows Beta in the second stage.
     */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = 'Rows Alpha');
        Account beta = new Account(Name = 'Rows Beta');
        insert new List<Account>{ alpha, beta };
        Opportunity web = opportunity('Rows Opp 1', alpha.Id, 100, firstStage(), FEBRUARY);
        web.LeadSource = 'Web';
        insert new List<Opportunity>{
            web,
            opportunity('Rows Opp 2', alpha.Id, 200, firstStage(), NOVEMBER),
            opportunity('Rows Opp 3', beta.Id, 350, secondStage(), NOVEMBER)
        };
    }

    // ---------------------------------------------------------------------------------------------------------
    // Provider merges under the engine's keys
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void providerBucketsOfVirtualRowsMergeIntoTheEnginesBucketFieldBuckets() {
        virtualRows.add(new Map<String, Object>{ 'Amount' => 500 }); // Large
        virtualRows.add(new Map<String, Object>{ 'amount' => 160 }); // Medium: paths match case-insensitively
        virtualRows.add(new Map<String, Object>{ 'Amount' => 20, 'LeadSource' => 'web' }); // Web: text ignores case
        Map<String, Object> request = chartRequest('bucket:dealSize');
        Map<String, String> standardKeys = keyLabels(query(chartRequest('bucket:dealSize')).categories);

        BoardChartQuery.ChartResult result = query(withProvider(request));

        Assert.areEqual(1, received.size());
        Assert.areEqual(
            standardKeys.keySet(),
            keyLabels(result.categories).keySet(),
            'Provider buckets land in the engine buckets: ' + JSON.serialize(result.categories)
        );
        Assert.areEqual(standardKeys, keyLabels(result.categories), 'Same labels');
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(850, values.get('Large|0'), '350 + 500');
        Assert.areEqual(2, values.get('Large|1'));
        Assert.areEqual(360, values.get('Medium|0'), '200 + 160');
        Assert.areEqual(120, values.get('Web|0'), '100 + 20');
    }

    @IsTest
    static void bucketFieldProviderMergesTheSameInTheCursorTier() {
        virtualRows.add(new Map<String, Object>{ 'Amount' => 500 });
        virtualRows.add(new Map<String, Object>{ 'Amount' => 160 });
        BoardChartQuery.ChartResult soql = query(withProvider(chartRequest('bucket:dealSize')));

        BoardChartQuery.ChartResult cursor = queryInCursorTier(withProvider(chartRequest('bucket:dealSize')));

        Assert.areEqual(2, received.size(), 'Once per run');
        Assert.areEqual(keyLabels(soql.categories), keyLabels(cursor.categories));
        Map<String, Decimal> expected = valuesByLabel(soql);
        Map<String, Decimal> merged = valuesByLabel(cursor);
        Assert.areEqual(expected.keySet(), merged.keySet());
        for (String key : expected.keySet()) {
            Assert.areEqual(expected.get(key).setScale(2), merged.get(key).setScale(2), 'Cursor matches SOQL: ' + key);
        }
        Assert.areEqual(850, merged.get('Large|0'), '350 + 500');
    }

    @IsTest
    static void excludedFallbackLeavesTheVirtualRowOut() {
        BoardDataProviderRequest request = providerRequest(chartRequest('bucket:dealSize'));
        Map<String, Object> excluded = (Map<String, Object>) ((List<Object>) request.query.get('bucketFields'))[0];
        excluded.put('fallback', new Map<String, Object>{ 'exclude' => true });

        BoardDataProviderRows helpers = new BoardDataProviderRows(request);

        Assert.areEqual('Large', helpers.bucketLabel('dealSize', new Map<String, Object>{ 'Amount' => 300 }));
        Assert.isNull(helpers.bucketLabel('bucket:dealSize', new Map<String, Object>{ 'Amount' => 10 }));
        Assert.isNull(helpers.bucketLabel('dealSize', new Map<String, Object>{ 'Amount' => null }), 'Null: no rule');
    }

    @IsTest
    static void providerDateBucketsMergeIntoTheEnginesDateBuckets() {
        virtualRows.add(new Map<String, Object>{ 'CloseDate' => Date.newInstance(2026, 2, 1), 'Amount' => 5 });
        virtualRows.add(new Map<String, Object>{ 'CloseDate' => Date.newInstance(2026, 11, 30), 'Amount' => 7 });
        Map<String, Object> request = chartRequest('CloseDate');
        request.put('dateGranularity', 'CALENDAR_MONTH');
        Map<String, String> standardKeys = keyLabels(query(request).categories);

        BoardChartQuery.ChartResult result = query(withProvider(request));

        Assert.areEqual(standardKeys, keyLabels(result.categories), 'Same month buckets: ' + standardKeys);
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(105, values.get(standardKeys.get('2026-02') + '|0'));
        Assert.areEqual(557, values.get(standardKeys.get('2026-11') + '|0'));
    }

    @IsTest
    static void providerReferenceBucketsMergeIntoTheEnginesRecordBuckets() {
        virtualRows.add(new Map<String, Object>{ 'AccountId' => accountId('Rows Beta'), 'Amount' => 50 });
        Map<String, String> standardKeys = keyLabels(query(chartRequest('AccountId')).categories);

        BoardChartQuery.ChartResult result = query(withProvider(chartRequest('AccountId')));

        Assert.areEqual(standardKeys, keyLabels(result.categories));
        Assert.areEqual(400, valuesByLabel(result).get('Rows Beta|0'), '350 + 50');
    }

    @IsTest
    static void virtualRowsOutsideTheWidgetScopeOrMeasureConditionAreLeftOut() {
        virtualRows.add(new Map<String, Object>{ 'AccountId' => accountId('Rows Alpha'), 'Amount' => 1000 });
        virtualRows.add(new Map<String, Object>{ 'AccountId' => accountId('Rows Beta'), 'Amount' => 1 });
        Map<String, Object> request = chartRequest('AccountId');
        Map<String, Object> amountMeasure = measure('SUM', 'Amount');
        amountMeasure.put('condition', condition('Amount', 'LT', 500));
        request.put('measures', new List<Object>{ amountMeasure, countMeasure() });
        request.put(
            'baseFilters',
            new List<Object>{
                new Map<String, Object>{
                    'id' => 'betaOnly',
                    'fieldPath' => 'AccountId',
                    'operator' => 'EQ',
                    'value' => accountId('Rows Beta')
                }
            }
        );

        BoardChartQuery.ChartResult result = query(withProvider(request));

        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(1, result.categories.size(), 'The Alpha row is outside the Base filter');
        Assert.areEqual(351, values.get('Rows Beta|0'));
        Assert.areEqual(2, values.get('Rows Beta|1'));
    }

    // ---------------------------------------------------------------------------------------------------------
    // Keys and labels match the engine (SOQL and cursor tier)
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void dateBucketKeysAndLabelsMatchTheEngineForEveryGranularityInBothTiers() {
        for (
            String granularity : new List<String>{
                'DAY',
                'CALENDAR_MONTH',
                'CALENDAR_QUARTER',
                'CALENDAR_YEAR',
                'FISCAL_QUARTER',
                'FISCAL_YEAR'
            }
        ) {
            Map<String, Object> request = chartRequest('CloseDate');
            request.put('dateGranularity', granularity);
            Map<String, String> expected = new Map<String, String>();
            for (Date day : new List<Date>{ FEBRUARY, NOVEMBER }) {
                expected.put(
                    BoardDataProviderRows.dateBucketKey(day, granularity),
                    BoardDataProviderRows.dateBucketLabel(day, granularity)
                );
            }
            Assert.areEqual(expected, keyLabels(query(request).categories), 'SOQL tier, ' + granularity);
            Assert.areEqual(expected, keyLabels(queryInCursorTier(request).categories), 'Cursor tier, ' + granularity);
        }
    }

    @IsTest
    static void datetimeBucketsUseTheUsersTimeZoneLikeTheEngine() {
        Datetime created = [SELECT CreatedDate FROM Opportunity WHERE Name = 'Rows Opp 1'].CreatedDate;
        Map<String, Object> request = chartRequest('CreatedDate');
        request.put('dateGranularity', 'DAY');

        Map<String, String> expected = new Map<String, String>{
            BoardDataProviderRows.dateBucketKey(created, 'DAY') => BoardDataProviderRows.dateBucketLabel(created, 'DAY')
        };

        Assert.areEqual(String.valueOf(created.date()), BoardDataProviderRows.dateBucketKey(created, null));
        Assert.areEqual(expected, keyLabels(query(request).categories), 'SOQL tier');
        Assert.areEqual(expected, keyLabels(queryInCursorTier(request).categories), 'Cursor tier');
    }

    @IsTest
    static void emptyOrUnsupportedDateValues() {
        Assert.isNull(BoardDataProviderRows.dateBucketKey(null, 'CALENDAR_MONTH'), 'Null lands in (Blank)');
        Assert.isNull(BoardDataProviderRows.dateBucketLabel(null, 'CALENDAR_MONTH'));
        Assert.areEqual('2026-Q1', BoardDataProviderRows.dateBucketKey(FEBRUARY, 'calendar_quarter'));
        try {
            BoardDataProviderRows.dateBucketKey(FEBRUARY, 'WEEK');
            Assert.fail('Unsupported granularity');
        } catch (BoardErrors.BoardException expected) {
            Assert.areEqual(BoardErrors.CONFIG_ERROR, expected.category);
            Assert.isTrue(expected.getMessage().contains('WEEK'));
        }
        try {
            BoardDataProviderRows.dateBucketKey('2026-02-15', 'DAY');
            Assert.fail('Not a Date or Datetime');
        } catch (BoardErrors.BoardException expected) {
            Assert.areEqual(BoardErrors.CONFIG_ERROR, expected.category);
            Assert.isTrue(expected.getMessage().contains('Date'));
        }
    }

    @IsTest
    static void referenceLabelsMatchTheEngineInBothTiers() {
        Map<String, String> expected = new Map<String, String>();
        Set<Id> accountIds = new Set<Id>{ accountId('Rows Alpha'), accountId('Rows Beta'), null };
        Map<Id, String> labels = BoardDataProviderRows.referenceLabels(accountIds);
        for (Id recordId : labels.keySet()) {
            expected.put(String.valueOf(recordId), labels.get(recordId));
        }

        Assert.areEqual(2, labels.size(), 'Null ids are skipped');
        Assert.areEqual('Rows Alpha', labels.get(accountId('Rows Alpha')));
        Assert.areEqual(expected, keyLabels(query(chartRequest('AccountId')).categories), 'SOQL tier');
        Assert.areEqual(expected, keyLabels(queryInCursorTier(chartRequest('AccountId')).categories), 'Cursor tier');
    }

    @IsTest
    static void referenceLabelOfAnUnreadableRecordIsItsId() {
        Account gone = new Account(Name = 'Rows Gone');
        insert gone;
        delete gone;

        Map<Id, String> labels = BoardDataProviderRows.referenceLabels(new Set<Id>{ gone.Id });

        Assert.areEqual(String.valueOf(gone.Id), labels.get(gone.Id), 'Like the engine: no name, the value');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Condition evaluation with SOQL null semantics
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void conditionsEvaluateAgainstAVirtualRowWithSoqlNullSemantics() {
        BoardDataProviderRequest.Condition notHundred = predicate('Amount', 'NEQ', 100);
        BoardDataProviderRequest.Condition overHundred = predicate('Amount', 'GT', 100);
        BoardDataProviderRequest.Condition anyOf = new BoardDataProviderRequest.Condition();
        anyOf.logic = 'OR';
        anyOf.children.add(overHundred);
        anyOf.children.add(predicate('StageName', 'IN', 'Closed Won'));
        Map<String, Object> empty = new Map<String, Object>{ 'Amount' => null };

        Assert.isTrue(BoardDataProviderRows.matches(notHundred, empty), '!= value keeps empty fields');
        Assert.isFalse(BoardDataProviderRows.matches(overHundred, empty), 'Ordering against null never matches');
        Assert.isFalse(BoardDataProviderRows.matches(overHundred, new Map<String, Object>()), 'Missing path is null');
        Assert.isTrue(BoardDataProviderRows.matches(overHundred, new Map<String, Object>{ 'AMOUNT' => 101 }));
        Assert.isTrue(BoardDataProviderRows.matches(anyOf, new Map<String, Object>{ 'stagename' => 'closed won' }));
        Assert.isFalse(BoardDataProviderRows.matches(anyOf, empty));
        Assert.isTrue(BoardDataProviderRows.matches(null, empty), 'No condition matches every row');
    }

    @IsTest
    static void inScopeAppliesFiltersBaseFiltersAndRecordContextOfTheRequest() {
        Map<String, Object> request = chartRequest('AccountId');
        request.put(
            'filters',
            new List<Object>{
                new Map<String, Object>{
                    'filterId' => 'stage',
                    'type' => 'PICKLIST',
                    'fieldPath' => 'StageName',
                    'explicit' => true,
                    'operator' => 'IN',
                    'values' => new List<Object>{ firstStage() }
                }
            }
        );
        BoardDataProviderRows helpers = new BoardDataProviderRows(providerRequest(request));

        Assert.isTrue(helpers.inScope(new Map<String, Object>{ 'StageName' => firstStage() }));
        Assert.isFalse(helpers.inScope(new Map<String, Object>{ 'StageName' => secondStage() }));
        Assert.isFalse(helpers.inScope(new Map<String, Object>()), 'IN never matches null');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** The request a provider receives for `request` (captured from a run of the test provider). */
    private static BoardDataProviderRequest providerRequest(Map<String, Object> request) {
        query(withProvider(request));
        return received[received.size() - 1];
    }

    private static BoardDataProviderRequest.Condition predicate(String path, String operator, Object value) {
        BoardDataProviderRequest.Condition condition = new BoardDataProviderRequest.Condition();
        condition.path = path;
        condition.operator = operator;
        condition.values.add(value);
        return condition;
    }

    private static Map<String, Object> withProvider(Map<String, Object> request) {
        Map<String, Object> named = request.clone();
        named.put('dataProvider', PROVIDER);
        return named;
    }

    /** Large (Amount >= 300), Medium (Amount >= 150), Web (Lead source Web); the rest falls in Other. */
    private static List<Object> dealSize() {
        return new List<Object>{
            new Map<String, Object>{
                'id' => 'dealSize',
                'label' => 'Deal size',
                'rules' => new List<Object>{
                    rule('Large', condition('Amount', 'GTE', 300)),
                    rule('Medium', condition('Amount', 'GTE', 150)),
                    rule('Web', condition('LeadSource', 'EQ', 'Web'))
                }
            }
        };
    }

    private static Map<String, Object> rule(String label, Map<String, Object> condition) {
        return new Map<String, Object>{ 'label' => label, 'condition' => condition };
    }

    /** A one-condition AND group, as the condition editor saves it. */
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

    private static Map<String, Object> chartRequest(String groupByField) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => groupByField,
            'bucketFields' => dealSize(),
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

    /** `request` forced through the cursor tier (one row per chunk), read to its last chunk. */
    private static BoardChartQuery.ChartResult queryInCursorTier(Map<String, Object> request) {
        Integer threshold = BoardQueryService.CURSOR_AGGREGATE_THRESHOLD;
        Integer chunkSize = BoardQueryService.CURSOR_CHUNK_SIZE;
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 1;
        BoardChartQuery.ChartResult result = query(request);
        Assert.areEqual('CURSOR', result.mode);
        while (!result.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.cursor);
            next.put('offset', result.nextOffset);
            next.put('partialState', result.partialState);
            result = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = threshold;
        BoardQueryService.CURSOR_CHUNK_SIZE = chunkSize;
        return result;
    }

    /** Category stored values to labels. */
    private static Map<String, String> keyLabels(List<BoardChartEngine.ChartKey> keys) {
        Map<String, String> labels = new Map<String, String>();
        for (BoardChartEngine.ChartKey key : keys) {
            labels.put(key.value, key.label);
        }
        return labels;
    }

    /** Point values keyed `categoryLabel|measureIndex`. */
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

    private static Opportunity opportunity(String name, Id accountId, Decimal amount, String stage, Date closeDate) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            Amount = amount,
            CloseDate = closeDate,
            StageName = stage
        );
    }
}