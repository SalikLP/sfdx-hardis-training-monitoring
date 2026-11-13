/**
 * Data provider seam of a Cross-object measure: a test provider class named in a Cross-object measure's
 * `dataProvider`, asserted at the Chart and Metric query entry points. Also Small multiples on a Widget-level Data
 * provider (the Panel field is one more grouping of the provider's buckets). Contract stands in for a target object.
 */
@IsTest
public class BoardCrossObjectProviderTest {
    private static final String PROVIDER = 'BoardCrossObjectProviderTest.TargetProvider';
    private static final String TARGETS = 'Contract';

    /** What `TargetProvider` returns next, and the requests it received. */
    private static BoardDataProviderResult scripted;
    private static List<BoardDataProviderRequest> received = new List<BoardDataProviderRequest>();

    /** Test provider: records each request and returns the scripted result (the same one on every call). */
    public class TargetProvider implements BoardDataProvider {
        public BoardDataProviderResult provide(BoardDataProviderRequest request) {
            received.add(request);
            return scripted == null ? new BoardDataProviderResult() : scripted;
        }
    }

    /**
     * Accounts: Alpha (Banking), Beta (Energy), Gamma (Retail). Opportunities: Alpha 100 and 200, Beta 300.
     * No Contracts: every target comes from the provider.
     */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = 'Provider Alpha', Industry = 'Banking');
        Account beta = new Account(Name = 'Provider Beta', Industry = 'Energy');
        Account gamma = new Account(Name = 'Provider Gamma', Industry = 'Retail');
        insert new List<Account>{ alpha, beta, gamma };
        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        insert new List<Opportunity>{
            opportunity('Provider Opp 1', alpha.Id, 100, stage),
            opportunity('Provider Opp 2', alpha.Id, 200, stage),
            opportunity('Provider Opp 3', beta.Id, 300, stage)
        };
    }

    @IsTest
    static void chartMeasureFromAProviderJoinsUnderTheChartKeys() {
        Id alphaId = accountId('Provider Alpha');
        Id gammaId = accountId('Provider Gamma');
        scripted = new BoardDataProviderResult();
        scripted.buckets.add(bucket(null, alphaId, 'Provider Alpha', 40, 2));
        scripted.buckets.add(bucket(null, gammaId, 'Provider Gamma', 7, 1));
        scripted.ignoredFilterIds.add('owner');
        Map<String, Object> target = providerMeasure('SUM', 'ContractTerm');
        target.put('filterBindings', new Map<String, Object>{ 'closeDate' => 'StartDate' });
        Map<String, Object> request = chartRequest(new List<Object>{ measure('SUM', 'Amount'), target });
        Map<String, Object> closeDate = filter('closeDate', 'DATE_RANGE', 'CloseDate', 'CloseDate', 'BETWEEN');
        closeDate.put('from', String.valueOf(Date.today().addDays(-1)));
        closeDate.put('to', String.valueOf(Date.today()));
        Map<String, Object> owner = filter('owner', 'USER', 'OwnerId', null, 'IN');
        owner.put('values', new List<Object>{ UserInfo.getUserId() });
        request.put('filters', new List<Object>{ closeDate, owner });

        BoardChartQuery.ChartResult result = queryChart(request);

        Assert.areEqual(1, received.size(), 'The provider is called once, for that one Measure');
        BoardDataProviderRequest sent = received[0];
        Assert.areEqual(TARGETS, sent.objectApiName);
        Assert.areEqual('AccountId', sent.groupByField, 'The category mapping');
        Assert.areEqual(1, sent.measures.size());
        Assert.areEqual('SUM', sent.measures[0].aggregateFunction);
        Assert.areEqual('ContractTerm', sent.measures[0].valueFieldApiName);
        Map<String, String> pathsByFilter = new Map<String, String>();
        for (BoardDataProviderRequest.Condition condition : sent.filters) {
            pathsByFilter.put(condition.filterId, firstPath(condition));
        }
        Assert.areEqual('StartDate', pathsByFilter.get('closeDate'), 'After the Measure\'s own Filter bindings');
        Assert.areEqual('OwnerId', pathsByFilter.get('owner'), 'Bound by convention');

        Assert.areEqual(new List<String>{ 'SUM', 'SUM' }, result.aggregateFunctions);
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(300, values.get('Provider Alpha|0'));
        Assert.areEqual(40, values.get('Provider Alpha|1'), 'Joined on the category value');
        Assert.areEqual(300, values.get('Provider Beta|0'));
        Assert.isNull(values.get('Provider Beta|1'));
        Assert.areEqual(7, values.get('Provider Gamma|1'), 'A category only the provider has still shows');
        BoardCrossObjectMeasures.Notice notice = result.crossObjectNotices[0];
        Assert.areEqual(1, notice.measureIndex);
        Assert.isFalse(notice.isBlank);
        Assert.areEqual(new List<String>{ 'owner' }, notice.ignoredFilterIds, 'The provider ignored it');
        Assert.areEqual(new List<String>{ 'closeDate' }, notice.appliedFilterIds);
    }

    @IsTest
    static void eachProviderMeasureGetsARequestOfItsOwn() {
        scripted = new BoardDataProviderResult();
        scripted.buckets.add(bucket(null, accountId('Provider Alpha'), 'Provider Alpha', 40, 2));

        BoardChartQuery.ChartResult result = queryChart(
            chartRequest(
                new List<Object>{
                    measure('SUM', 'Amount'),
                    providerMeasure('SUM', 'ContractTerm'),
                    providerMeasure('MAX', 'ContractTerm')
                }
            )
        );

        Assert.areEqual(2, received.size(), 'One request per Cross-object measure with a Data provider');
        Assert.areEqual('SUM', received[0].measures[0].aggregateFunction);
        Assert.areEqual('MAX', received[1].measures[0].aggregateFunction);
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(40, values.get('Provider Alpha|1'));
        Assert.areEqual(40, values.get('Provider Alpha|2'));
    }

    @IsTest
    static void smallMultiplesJoinProviderBucketsOnPanelAndCategory() {
        scripted = new BoardDataProviderResult();
        scripted.buckets.add(bucket('Banking', accountId('Provider Alpha'), 'Provider Alpha', 40, 2));
        scripted.buckets.add(bucket('Retail', accountId('Provider Gamma'), 'Provider Gamma', 7, 1));
        Map<String, Object> target = providerMeasure('SUM', 'ContractTerm');
        target.put('panelMapping', 'Account.Industry');
        Map<String, Object> request = chartRequest(new List<Object>{ measure('SUM', 'Amount'), target });
        request.put('panelField', 'Account.Industry');

        Map<String, Decimal> values = valuesByPanel(queryChart(request));

        Assert.areEqual('Account.Industry', received[0].panelField, 'The panel mapping is one more grouping');
        Assert.areEqual(300, values.get('Banking|Provider Alpha|0'));
        Assert.areEqual(40, values.get('Banking|Provider Alpha|1'));
        Assert.areEqual(7, values.get('Retail|Provider Gamma|1'), 'A Panel only the provider has still shows');
    }

    @IsTest
    static void metricMeasureFromAProviderTotalsItsBuckets() {
        scripted = new BoardDataProviderResult();
        scripted.buckets.add(bucket(null, null, null, 42, 3));
        Map<String, Object> pipeline = measure('SUM', 'Amount');
        pipeline.put('hidden', true);
        Map<String, Object> target = providerMeasure('SUM', 'ContractTerm');
        target.put('hidden', true);

        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(
            JSON.serialize(
                new Map<String, Object>{
                    'objectApiName' => 'Opportunity',
                    'measures' => new List<Object>{
                        pipeline,
                        target,
                        new Map<String, Object>{ 'aggregateFunction' => 'FORMULA', 'formula' => 'A - B' }
                    }
                }
            )
        );

        Assert.areEqual(1, received.size());
        Assert.areEqual('metric', received[0].widgetType);
        Assert.isNull(received[0].groupByField);
        Assert.areEqual(42, toDecimal(result.measures[1].value));
        Assert.areEqual(558, toDecimal(result.value), '600 pipeline - 42 targets');
    }

    @IsTest
    static void providerMeasureRejectionAndBucketFieldCategoryAreConfigErrors() {
        scripted = new BoardDataProviderResult();
        scripted.rejectMeasure(0, 'No targets for this aggregate.');
        String message = messageOf(
            chartRequest(new List<Object>{ measure('SUM', 'Amount'), providerMeasure('MIN', 'ContractTerm') })
        );
        Assert.isTrue(message.contains('No targets for this aggregate.'), message);
        Assert.isTrue(message.contains('Measure 2'), 'Named by its place in the Widget: ' + message);

        Map<String, Object> bucketCategory = chartRequest(new List<Object>{ providerMeasure('SUM', 'ContractTerm') });
        bucketCategory.put('groupByField', 'bucket:dealSize');
        message = messageOf(bucketCategory);
        Assert.isTrue(message.contains('Bucket field') && message.contains('Data provider'), message);
    }

    @IsTest
    static void smallMultiplesWorkWithAWidgetLevelProvider() {
        scripted = new BoardDataProviderResult();
        scripted.includeStandardResult = true;
        scripted.buckets.add(bucket('Retail', accountId('Provider Gamma'), 'Provider Gamma', 7, 1));
        Map<String, Object> request = chartRequest(new List<Object>{ measure('SUM', 'Amount') });
        request.put('dataProvider', PROVIDER);
        request.put('panelField', 'Account.Industry');

        Map<String, Decimal> values = valuesByPanel(queryChart(request));

        Assert.areEqual(1, received.size());
        Assert.areEqual('Account.Industry', received[0].panelField);
        Assert.areEqual(300, values.get('Banking|Provider Alpha|0'), 'The standard leg, by Panel');
        Assert.areEqual(300, values.get('Energy|Provider Beta|0'));
        Assert.areEqual(7, values.get('Retail|Provider Gamma|0'), 'The provider\'s bucket in its own Panel');
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

    private static Map<String, Object> providerMeasure(String aggregateFunction, String valueField) {
        Map<String, Object> cross = measure(aggregateFunction, valueField);
        cross.put('sourceObject', TARGETS);
        cross.put('categoryMapping', 'AccountId');
        cross.put('dataProvider', PROVIDER);
        return cross;
    }

    private static Map<String, Object> filter(
        String filterId,
        String type,
        String fieldPath,
        String fieldApiName,
        String operator
    ) {
        return new Map<String, Object>{
            'filterId' => filterId,
            'type' => type,
            'fieldPath' => fieldPath,
            'fieldApiName' => fieldApiName,
            'explicit' => false,
            'operator' => operator,
            'values' => new List<Object>()
        };
    }

    /** One provider bucket with one partial of `count` rows adding up to `sum`. */
    private static BoardDataProviderResult.Bucket bucket(
        String panelValue,
        String categoryValue,
        String categoryLabel,
        Decimal sum,
        Integer count
    ) {
        BoardDataProviderResult.Bucket entry = new BoardDataProviderResult.Bucket(
            categoryValue,
            categoryLabel,
            null,
            null
        );
        entry.panelValue = panelValue;
        entry.panelLabel = panelValue;
        entry.measures.add(new BoardDataProviderResult.Partial(sum, count, sum, sum));
        return entry;
    }

    private static BoardChartQuery.ChartResult queryChart(Map<String, Object> request) {
        return BoardChartQuery.queryChart(JSON.serialize(request));
    }

    private static String messageOf(Map<String, Object> request) {
        try {
            queryChart(request);
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), String.valueOf(payload));
            return String.valueOf(payload.get('message'));
        }
        Assert.fail('Expected a CONFIG_ERROR for ' + JSON.serialize(request));
        return null;
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

    /** Point values keyed `panelLabel|categoryLabel|measureIndex` (Small multiples). */
    private static Map<String, Decimal> valuesByPanel(BoardChartQuery.ChartResult result) {
        Map<String, String> panelLabels = new Map<String, String>();
        for (BoardChartEngine.ChartKey panel : result.panels) {
            panelLabels.put(panel.key, panel.label);
        }
        Map<String, String> categoryLabels = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            categoryLabels.put(category.key, category.label);
        }
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(
                panelLabels.get(point.panelKey) +
                    '|' +
                    categoryLabels.get(point.categoryKey) +
                    '|' +
                    point.measureIndex,
                point.value
            );
        }
        return values;
    }

    /** A condition's path, or its first child's (a date range compiles to an AND group on one path). */
    private static String firstPath(BoardDataProviderRequest.Condition condition) {
        if (!condition.isGroup()) {
            return condition.path;
        }
        return condition.children.isEmpty() ? null : firstPath(condition.children[0]);
    }

    private static Decimal toDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }

    private static Id accountId(String name) {
        return [SELECT Id FROM Account WHERE Name = :name LIMIT 1].Id;
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