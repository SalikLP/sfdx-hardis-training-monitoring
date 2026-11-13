/**
 * Entry-point tests for mixed-currency totals: every query path returns currency amounts in the corporate currency.
 * The single-call SOQL aggregate (corporate in multi-currency orgs) is the source of truth; the `Database.Cursor`
 * tier and ungrouped MIN/MAX must match it.
 *
 * Needs a multi-currency org with at least two active currencies; every test skips gracefully otherwise.
 * Data: two Accounts (corporate 1,000 revenue; other-currency 2,000 revenue) and five Opportunities in two stages,
 * amounts in both currencies.
 */
@IsTest
private class BoardQueryServiceCurrencyTest {
    private static final Decimal TOLERANCE = 0.01;

    @TestSetup
    static void setup() {
        String other = otherActiveIsoCode();
        if (other == null) {
            return;
        }
        String corporate = BoardCurrencyConverter.forRequest().getCorporateIsoCode();
        Account corporateAccount = (Account) withCurrency(
            new Account(Name = 'Currency Corporate', AnnualRevenue = 1000),
            corporate
        );
        Account otherAccount = (Account) withCurrency(
            new Account(Name = 'Currency Other', AnnualRevenue = 2000),
            other
        );
        insert new List<Account>{ corporateAccount, otherAccount };
        insert new List<Opportunity>{
            opportunity('Corporate 100', corporateAccount.Id, 100, 'Prospecting', corporate),
            opportunity('Corporate 300', corporateAccount.Id, 300, 'Qualification', corporate),
            opportunity('Other 7', otherAccount.Id, 7, 'Prospecting', other),
            opportunity('Other 50', otherAccount.Id, 50, 'Qualification', other),
            opportunity('Other 1000', otherAccount.Id, 1000, 'Qualification', other)
        };
    }

    @IsTest
    static void metricCursorSumAndAvgEqualTheSingleCallSoqlResult() {
        if (otherActiveIsoCode() == null) {
            return;
        }
        for (String valueField : new List<String>{ 'Amount', 'Account.AnnualRevenue' }) {
            Decimal singleSum = (Decimal) run(metricRequest('SUM', valueField)).value;
            Decimal singleAvg = (Decimal) run(metricRequest('AVG', valueField)).value;
            Assert.areEqual(soqlAggregate('SUM', valueField), singleSum, 'Single-call path is the SOQL aggregate');

            BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
            BoardQueryService.CURSOR_CHUNK_SIZE = 2;
            Map<String, Object> request = metricRequest('SUM', valueField);
            BoardQueryService.MetricResult first = run(request);
            Assert.areEqual('CURSOR', first.mode);
            BoardChartEngine.Partial merged = mergeMetricChunks(request, first.chunk);
            assertClose(singleSum, merged.sum, 'Cursor SUM of ' + valueField);
            assertClose(singleAvg, merged.sum / merged.count, 'Cursor AVG of ' + valueField);
            BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 49900;
        }
    }

    @IsTest
    static void metricMinAndMaxReturnCorporateValues() {
        if (otherActiveIsoCode() == null) {
            return;
        }
        for (String aggregateFunction : new List<String>{ 'MIN', 'MAX' }) {
            for (String valueField : new List<String>{ 'Amount', 'Account.AnnualRevenue' }) {
                assertClose(
                    soqlAggregate(aggregateFunction, valueField),
                    (Decimal) run(metricRequest(aggregateFunction, valueField)).value,
                    aggregateFunction + ' of ' + valueField
                );
            }
        }
    }

    @IsTest
    static void chartCursorCategoriesEqualSingleCallCategories() {
        if (otherActiveIsoCode() == null) {
            return;
        }
        for (String aggregateFunction : new List<String>{ 'SUM', 'MIN', 'MAX' }) {
            Map<String, Object> request = chartRequest(aggregateFunction, 'StageName');
            Map<String, Decimal> single = chartValues(BoardChartQuery.queryChart(JSON.serialize(request)));

            BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
            BoardQueryService.CURSOR_CHUNK_SIZE = 2;
            BoardChartQuery.ChartResult first = BoardChartQuery.queryChart(JSON.serialize(request));
            Assert.areEqual('CURSOR', first.mode);
            Map<String, Decimal> merged = chartValues(completeChart(request, first));
            Assert.areEqual(single.keySet(), merged.keySet(), aggregateFunction);
            for (String stage : single.keySet()) {
                assertClose(single.get(stage), merged.get(stage), aggregateFunction + ' ' + stage);
            }
            BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 49900;
        }
    }

    @IsTest
    static void chartGroupedByCurrencyIsoCodeSelectsItOnce() {
        if (otherActiveIsoCode() == null) {
            return;
        }
        Map<String, Object> request = chartRequest('SUM', 'CurrencyIsoCode');
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
        BoardQueryService.CURSOR_CHUNK_SIZE = 10;
        BoardChartQuery.ChartResult result = BoardChartQuery.queryChart(JSON.serialize(request));
        Assert.areEqual('CURSOR', result.mode);
        Assert.isTrue(result.isComplete);
        Map<String, Decimal> values = chartValues(result);
        Assert.areEqual(2, values.size(), 'One category per record currency');
        Decimal total = 0;
        for (Decimal value : values.values()) {
            total += value;
        }
        assertClose(soqlAggregate('SUM', 'Amount'), total, 'Converted total across currency categories');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** A non-corporate active currency, or null when the org cannot run these tests. */
    private static String otherActiveIsoCode() {
        if (!UserInfo.isMultiCurrencyOrganization()) {
            return null;
        }
        List<SObject> rows = Database.query(
            'SELECT IsoCode FROM CurrencyType WHERE IsActive = true AND IsCorporate = false ORDER BY IsoCode LIMIT 1'
        );
        return rows.isEmpty() ? null : (String) rows[0].get('IsoCode');
    }

    private static SObject withCurrency(SObject record, String isoCode) {
        record.put('CurrencyIsoCode', isoCode);
        return record;
    }

    private static Opportunity opportunity(String name, Id accountId, Decimal amount, String stage, String isoCode) {
        return (Opportunity) withCurrency(
            new Opportunity(
                Name = name,
                AccountId = accountId,
                Amount = amount,
                CloseDate = Date.today(),
                StageName = stage
            ),
            isoCode
        );
    }

    /** The single-call SOQL aggregate over every test Opportunity (corporate currency in multi-currency orgs). */
    private static Decimal soqlAggregate(String aggregateFunction, String valueField) {
        List<AggregateResult> rows = Database.query(
            'SELECT ' + aggregateFunction + '(' + valueField + ') v FROM Opportunity'
        );
        return (Decimal) rows[0].get('v');
    }

    private static Map<String, Object> metricRequest(String aggregateFunction, String valueField) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'aggregateFunction' => aggregateFunction,
            'valueFieldApiName' => valueField,
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            // Compared with corporate SOQL aggregates: show them in the corporate currency.
            'displayCurrency' => BoardCurrencyConverter.forRequest().getCorporateIsoCode(),
            'refreshToken' => 0
        };
    }

    private static BoardQueryService.MetricResult run(Map<String, Object> request) {
        return BoardQueryService.queryMetric(JSON.serialize(request));
    }

    /** Merges every Metric cursor chunk's partial bucket. */
    private static BoardChartEngine.Partial mergeMetricChunks(
        Map<String, Object> request,
        BoardQueryService.AggregateChunk first
    ) {
        BoardChartEngine.Partial total;
        BoardQueryService.AggregateChunk chunk = first;
        Boolean complete = false;
        while (!complete) {
            for (BoardChartEngine.Partial bucket : chunk.buckets) {
                if (total == null) {
                    total = bucket;
                    continue;
                }
                total.sum += bucket.sum;
                total.count += bucket.count;
                total.min = total.min == null || (bucket.min != null && bucket.min < total.min)
                    ? bucket.min
                    : total.min;
                total.max = total.max == null || (bucket.max != null && bucket.max > total.max)
                    ? bucket.max
                    : total.max;
            }
            complete = chunk.isComplete;
            if (!complete) {
                Map<String, Object> next = request.clone();
                next.put('cursor', chunk.cursor);
                next.put('offset', chunk.nextOffset);
                chunk = BoardQueryService.fetchAggregateChunk(JSON.serialize(next));
            }
        }
        return total;
    }

    /** A one-Measure Chart widget request on Amount, in the corporate currency. */
    private static Map<String, Object> chartRequest(String aggregateFunction, String groupByField) {
        Map<String, Object> request = metricRequest(aggregateFunction, 'Amount');
        request.remove('aggregateFunction');
        request.remove('valueFieldApiName');
        request.put(
            'measures',
            new List<Object>{
                new Map<String, Object>{ 'aggregateFunction' => aggregateFunction, 'valueFieldApiName' => 'Amount' }
            }
        );
        request.put('groupByField', groupByField);
        return request;
    }

    /** Follows a Chart cursor until `isComplete`. */
    private static BoardChartQuery.ChartResult completeChart(
        Map<String, Object> request,
        BoardChartQuery.ChartResult first
    ) {
        BoardChartQuery.ChartResult result = first;
        while (!result.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.cursor);
            next.put('offset', result.nextOffset);
            next.put('partialState', result.partialState);
            result = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }
        return result;
    }

    /** Category label -> value of the only Measure. */
    private static Map<String, Decimal> chartValues(BoardChartQuery.ChartResult result) {
        Map<String, String> labels = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            labels.put(category.key, category.label);
        }
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(labels.get(point.categoryKey), point.value);
        }
        return values;
    }

    private static void assertClose(Decimal expected, Decimal actual, String message) {
        Assert.isNotNull(actual, message);
        Assert.isTrue(Math.abs(expected - actual) <= TOLERANCE, message + ': expected ' + expected + ', got ' + actual);
    }
}