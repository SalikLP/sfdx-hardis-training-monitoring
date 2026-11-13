/**
 * Entry-point tests for the Display currency (currency/02): Metric and Chart results come back in the request's
 * `displayCurrency` with its ISO code, on the single-call and cursor paths; counts never convert.
 *
 * The per-currency tests need a multi-currency org with at least two active currencies, discovered at runtime (no
 * hard-coded ISO codes or rates); they skip gracefully otherwise. Expected values are the corporate SOQL aggregate
 * times the display currency's `CurrencyType.ConversionRate`. The injected-rate tests run in any org.
 * Data: five Opportunities in two stages, amounts spread over the active currencies.
 */
@IsTest
private class BoardCurrencyDisplayTest {
    private static final Decimal TOLERANCE = 0.01;

    @TestSetup
    static void setup() {
        Map<String, Decimal> rates = activeRates();
        List<String> isoCodes = rates == null ? new List<String>{ null } : new List<String>(rates.keySet());
        Account account = new Account(Name = 'Display Currency');
        insert account;
        List<Schema.PicklistEntry> stages = Opportunity.StageName.getDescribe().getPicklistValues();
        List<Decimal> amounts = new List<Decimal>{ 100, 300, 7, 50, 1000 };
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < amounts.size(); i++) {
            Opportunity opportunity = new Opportunity(
                Name = 'Display ' + i,
                AccountId = account.Id,
                Amount = amounts[i],
                CloseDate = Date.today(),
                StageName = stages[Math.mod(i, 2)].getValue()
            );
            String isoCode = isoCodes[Math.mod(i, isoCodes.size())];
            if (isoCode != null) {
                opportunity.put('CurrencyIsoCode', isoCode);
            }
            opportunities.add(opportunity);
        }
        insert opportunities;
    }

    // ---------------------------------------------------------------------------------------------------------
    // Multi-currency org: every active currency as Display currency
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void metricAmountsAreReturnedInEachDisplayCurrency() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String display : rates.keySet()) {
            for (String aggregateFunction : new List<String>{ 'SUM', 'AVG', 'MIN', 'MAX' }) {
                BoardQueryService.MetricResult result = metric(aggregateFunction, display);
                String label = aggregateFunction + ' in ' + display;
                Assert.areEqual(display, result.currencyIsoCode, label);
                assertClose(soqlAggregate(aggregateFunction) * rates.get(display), (Decimal) result.value, label);
            }
        }
    }

    @IsTest
    static void metricCursorTotalsEqualTheSingleCallTotalsInEachDisplayCurrency() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String display : rates.keySet()) {
            Decimal singleSum = (Decimal) metric('SUM', display).value;
            BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
            BoardQueryService.CURSOR_CHUNK_SIZE = 2;
            Map<String, Object> request = metricRequest('SUM', display);
            BoardQueryService.MetricResult first = BoardQueryService.queryMetric(JSON.serialize(request));
            Assert.areEqual('CURSOR', first.mode);
            Assert.areEqual(display, first.currencyIsoCode);
            Decimal sum = 0;
            Integer count = 0;
            Decimal min;
            BoardQueryService.AggregateChunk chunk = first.chunk;
            while (true) {
                for (BoardChartEngine.Partial bucket : chunk.buckets) {
                    sum += bucket.sum;
                    count += bucket.count;
                    min = min == null || (bucket.min != null && bucket.min < min) ? bucket.min : min;
                }
                if (chunk.isComplete) {
                    break;
                }
                Map<String, Object> next = request.clone();
                next.put('cursor', chunk.cursor);
                next.put('offset', chunk.nextOffset);
                chunk = BoardQueryService.fetchAggregateChunk(JSON.serialize(next));
            }
            assertClose(singleSum, sum, 'Cursor SUM in ' + display);
            Assert.areEqual(5, count, 'Counts never convert');
            assertClose(soqlAggregate('MIN') * rates.get(display), min, 'Cursor MIN in ' + display);
            BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 49900;
        }
    }

    @IsTest
    static void countsAreNeverConvertedAndCarryNoCurrency() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String display : rates.keySet()) {
            BoardQueryService.MetricResult count = metric('COUNT', display);
            Assert.areEqual(5, count.value);
            Assert.isNull(count.currencyIsoCode);
            BoardQueryService.MetricResult distinct = metric('COUNT_DISTINCT', display);
            Assert.areEqual(5, Integer.valueOf(distinct.value));
            Assert.isNull(distinct.currencyIsoCode);
        }
    }

    @IsTest
    static void chartAmountMeasuresAreReturnedInEachDisplayCurrencyOnBothTiers() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        String corporate = BoardCurrencyConverter.forRequest().getCorporateIsoCode();
        Map<String, Decimal> corporateValues = pointValues(BoardChartQuery.queryChart(chartJson(corporate, null)));
        for (String display : rates.keySet()) {
            BoardChartQuery.ChartResult single = BoardChartQuery.queryChart(chartJson(display, null));
            Assert.areEqual(new List<String>{ display, null }, single.currencyIsoCodes);
            assertConverted(corporateValues, pointValues(single), rates.get(display), 'Single call in ' + display);

            BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
            BoardQueryService.CURSOR_CHUNK_SIZE = 2;
            BoardChartQuery.ChartResult result = BoardChartQuery.queryChart(chartJson(display, null));
            Assert.areEqual('CURSOR', result.mode);
            while (!result.isComplete) {
                result = BoardChartQuery.fetchChartChunk(chartJson(display, result));
            }
            Assert.areEqual(new List<String>{ display, null }, result.currencyIsoCodes);
            assertConverted(corporateValues, pointValues(result), rates.get(display), 'Cursor tier in ' + display);
            BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 49900;
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Any org: injected rates through the entry points (single-call paths only: no record currencies are read)
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void injectedRatesConvertMetricAndChartAmountsButNotCounts() {
        BoardCurrencyConverter.requestConverter = BoardCurrencyConverter.fromRates(
            new List<BoardCurrencyConverter.Rate>{
                new BoardCurrencyConverter.Rate('XXA', 1, true),
                new BoardCurrencyConverter.Rate('XXB', 4, false)
            }
        );
        Decimal corporateSum = soqlAggregate('SUM');

        BoardQueryService.MetricResult sum = metric('SUM', 'XXB');
        Assert.areEqual('XXB', sum.currencyIsoCode);
        assertClose(corporateSum * 4, (Decimal) sum.value, 'Metric SUM');
        BoardQueryService.MetricResult count = metric('COUNT', 'XXB');
        Assert.areEqual(5, count.value);
        Assert.isNull(count.currencyIsoCode);

        BoardChartQuery.ChartResult chart = BoardChartQuery.queryChart(chartJson('XXB', null));
        Assert.areEqual(new List<String>{ 'XXB', null }, chart.currencyIsoCodes);
        Decimal chartSum = 0;
        Decimal chartCount = 0;
        for (BoardChartEngine.ChartPoint point : chart.points) {
            if (point.measureIndex == 0) {
                chartSum += point.value;
            } else {
                chartCount += point.value;
            }
        }
        assertClose(corporateSum * 4, chartSum, 'Chart SUM');
        assertClose(5, chartCount, 'Chart COUNT');
    }

    @IsTest
    static void singleCurrencyConverterReturnsOrgCurrencyAmountsUnconverted() {
        BoardCurrencyConverter.requestConverter = BoardCurrencyConverter.singleCurrency();

        BoardQueryService.MetricResult sum = metric('SUM', 'EUR');

        Assert.areEqual(UserInfo.getDefaultCurrency(), sum.currencyIsoCode, 'Formatted in the org currency');
        assertClose(soqlAggregate('SUM'), (Decimal) sum.value, 'Unconverted SUM');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** Active ISO code → conversion rate (corporate = 1), or null when fewer than two currencies are active. */
    private static Map<String, Decimal> activeRates() {
        if (!UserInfo.isMultiCurrencyOrganization()) {
            return null;
        }
        Map<String, Decimal> rates = new Map<String, Decimal>();
        for (
            SObject row : Database.query(
                'SELECT IsoCode, ConversionRate FROM CurrencyType WHERE IsActive = true ORDER BY IsoCode'
            )
        ) {
            rates.put((String) row.get('IsoCode'), (Decimal) row.get('ConversionRate'));
        }
        return rates.size() < 2 ? null : rates;
    }

    /** The single-call SOQL aggregate over every test Opportunity (corporate currency in multi-currency orgs). */
    private static Decimal soqlAggregate(String aggregateFunction) {
        List<AggregateResult> rows = Database.query('SELECT ' + aggregateFunction + '(Amount) v FROM Opportunity');
        return (Decimal) rows[0].get('v');
    }

    private static Map<String, Object> metricRequest(String aggregateFunction, String display) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'aggregateFunction' => aggregateFunction,
            'valueFieldApiName' => aggregateFunction == 'COUNT' ? null : 'Amount',
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'displayCurrency' => display
        };
    }

    private static BoardQueryService.MetricResult metric(String aggregateFunction, String display) {
        return BoardQueryService.queryMetric(JSON.serialize(metricRequest(aggregateFunction, display)));
    }

    /** SUM of Amount and COUNT by stage; with `previous`, the next cursor chunk request. */
    private static String chartJson(String display, BoardChartQuery.ChartResult previous) {
        Map<String, Object> request = new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => 'StageName',
            'measures' => new List<Object>{
                new Map<String, Object>{ 'aggregateFunction' => 'SUM', 'valueFieldApiName' => 'Amount' },
                new Map<String, Object>{ 'aggregateFunction' => 'COUNT' }
            },
            'displayCurrency' => display
        };
        if (previous != null) {
            request.put('cursor', previous.cursor);
            request.put('offset', previous.nextOffset);
            request.put('partialState', previous.partialState);
        }
        return JSON.serialize(request);
    }

    /** Point values keyed `categoryKey|measureIndex`. */
    private static Map<String, Decimal> pointValues(BoardChartQuery.ChartResult result) {
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(point.categoryKey + '|' + point.measureIndex, point.value);
        }
        return values;
    }

    /** Measure 0 (SUM of Amount) is the corporate value times `rate`; measure 1 (COUNT) is unchanged. */
    private static void assertConverted(
        Map<String, Decimal> corporate,
        Map<String, Decimal> actual,
        Decimal rate,
        String message
    ) {
        Assert.areEqual(corporate.keySet(), actual.keySet(), message);
        for (String key : corporate.keySet()) {
            Decimal expected = key.endsWith('|0') ? corporate.get(key) * rate : corporate.get(key);
            assertClose(expected, actual.get(key), message + ' ' + key);
        }
    }

    private static void assertClose(Decimal expected, Decimal actual, String message) {
        Assert.isNotNull(actual, message);
        Assert.isTrue(Math.abs(expected - actual) <= TOLERANCE, message + ': expected ' + expected + ', got ' + actual);
    }
}