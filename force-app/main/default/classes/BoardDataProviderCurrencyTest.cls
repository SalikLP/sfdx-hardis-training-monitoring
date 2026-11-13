/**
 * Currency in Data provider amounts (currency/08): a test Data provider returns amounts in the corporate currency, and
 * the Metric and Chart entry points return them in the request's Display currency with its ISO code; counts never
 * convert. The provider request carries the Display currency and a corporate → Display currency helper.
 *
 * The per-currency tests need a multi-currency org with at least two active currencies, discovered at runtime; they
 * skip gracefully otherwise. The injected-rate test runs in any org. The provider replaces the standard query, so the
 * Widget shows only the provider's amounts: SUM 900, AVG 300, MIN 100, MAX 500 and COUNT 3 (corporate).
 */
@IsTest
public class BoardDataProviderCurrencyTest {
    private static final String PROVIDER = 'BoardDataProviderCurrencyTest.CorporateAmountsProvider';
    private static final Decimal TOLERANCE = 0.01;
    private static final Decimal CORPORATE_SUM = 900;
    private static final Decimal CORPORATE_AVG = 300;
    private static final Decimal CORPORATE_MIN = 100;
    private static final Decimal CORPORATE_MAX = 500;
    private static final Integer ROW_COUNT = 3;

    private static List<BoardDataProviderRequest> received = new List<BoardDataProviderRequest>();

    /** Test provider: one bucket per run, every amount Measure `{ sum 900, count 3, min 100, max 500 }` corporate. */
    public class CorporateAmountsProvider implements BoardDataProvider {
        public BoardDataProviderResult provide(BoardDataProviderRequest request) {
            received.add(request);
            BoardDataProviderResult result = new BoardDataProviderResult();
            BoardDataProviderResult.Bucket bucket = new BoardDataProviderResult.Bucket(
                request.groupByField == null ? null : 'estimates',
                request.groupByField == null ? null : 'Estimates',
                null,
                null
            );
            for (BoardDataProviderRequest.Measure measure : request.measures) {
                bucket.measures.add(
                    measure.aggregateFunction == 'COUNT'
                        ? new BoardDataProviderResult.Partial(0, ROW_COUNT, null, null)
                        : new BoardDataProviderResult.Partial(CORPORATE_SUM, ROW_COUNT, CORPORATE_MIN, CORPORATE_MAX)
                );
            }
            result.buckets.add(bucket);
            return result;
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Multi-currency org: every active currency as Display currency
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void chartProviderAmountsAreReturnedInEachDisplayCurrency() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String display : rates.keySet()) {
            Decimal rate = rates.get(display);
            BoardChartQuery.ChartResult chart = BoardChartQuery.queryChart(JSON.serialize(chartRequest(display)));

            Assert.areEqual(new List<String>{ display, display, display, display, null }, chart.currencyIsoCodes);
            Map<Integer, Decimal> values = valuesByMeasure(chart);
            assertClose(CORPORATE_SUM * rate, values.get(0), 'SUM in ' + display);
            assertClose(CORPORATE_AVG * rate, values.get(1), 'AVG in ' + display);
            assertClose(CORPORATE_MIN * rate, values.get(2), 'MIN in ' + display);
            assertClose(CORPORATE_MAX * rate, values.get(3), 'MAX in ' + display);
            assertClose(ROW_COUNT, values.get(4), 'COUNT never converts (' + display + ')');
        }
    }

    @IsTest
    static void metricProviderAmountsAreReturnedInEachDisplayCurrencyAndCountsAreNot() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String display : rates.keySet()) {
            BoardQueryService.MetricResult sum = metric('SUM', display);
            Assert.areEqual(display, sum.currencyIsoCode);
            assertClose(CORPORATE_SUM * rates.get(display), (Decimal) sum.value, 'Metric SUM in ' + display);

            BoardQueryService.MetricResult count = metric('COUNT', display);
            Assert.isNull(count.currencyIsoCode, 'A count carries no currency');
            assertClose(ROW_COUNT, Decimal.valueOf(String.valueOf(count.value)), 'Metric COUNT never converts');
        }
    }

    @IsTest
    static void providerRequestCarriesTheDisplayCurrencyAndConvertsCorporateAmounts() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String display : rates.keySet()) {
            received.clear();
            BoardChartQuery.queryChart(JSON.serialize(chartRequest(display)));

            BoardDataProviderRequest sent = received[0];
            Assert.areEqual(display, sent.displayCurrency);
            assertClose(CORPORATE_SUM * rates.get(display), sent.toDisplayCurrency(CORPORATE_SUM), display);
            Assert.isNull(sent.toDisplayCurrency(null));
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Any org: injected rates and the single-currency no-op
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void injectedRatesConvertProviderAmountsButNotCounts() {
        BoardCurrencyConverter.requestConverter = BoardCurrencyConverter.fromRates(
            new List<BoardCurrencyConverter.Rate>{
                new BoardCurrencyConverter.Rate('XXA', 1, true),
                new BoardCurrencyConverter.Rate('XXB', 4, false)
            }
        );

        BoardChartQuery.ChartResult chart = BoardChartQuery.queryChart(JSON.serialize(chartRequest('XXB')));
        Assert.areEqual(new List<String>{ 'XXB', 'XXB', 'XXB', 'XXB', null }, chart.currencyIsoCodes);
        Map<Integer, Decimal> values = valuesByMeasure(chart);
        assertClose(3600, values.get(0), 'SUM 900 × 4');
        assertClose(1200, values.get(1), 'AVG 300 × 4');
        assertClose(400, values.get(2), 'MIN 100 × 4');
        assertClose(2000, values.get(3), 'MAX 500 × 4');
        assertClose(3, values.get(4), 'COUNT never converts');
        Assert.areEqual('XXB', received[0].displayCurrency);
        assertClose(40, received[0].toDisplayCurrency(10), 'Provider helper: 10 corporate × 4');

        BoardQueryService.MetricResult sum = metric('SUM', 'XXB');
        Assert.areEqual('XXB', sum.currencyIsoCode);
        assertClose(3600, (Decimal) sum.value, 'Metric SUM 900 × 4');
        BoardQueryService.MetricResult count = metric('COUNT', 'XXB');
        Assert.isNull(count.currencyIsoCode);
        assertClose(3, Decimal.valueOf(String.valueOf(count.value)), 'Metric COUNT never converts');
    }

    @IsTest
    static void singleCurrencyConverterLeavesProviderAmountsInTheOrgCurrency() {
        BoardCurrencyConverter.requestConverter = BoardCurrencyConverter.singleCurrency();

        BoardQueryService.MetricResult sum = metric('SUM', 'XXB');

        Assert.areEqual(UserInfo.getDefaultCurrency(), sum.currencyIsoCode, 'Formatted in the org currency');
        assertClose(CORPORATE_SUM, (Decimal) sum.value, 'Unconverted SUM');
        Assert.areEqual(UserInfo.getDefaultCurrency(), received[0].displayCurrency);
        Assert.areEqual(CORPORATE_SUM, received[0].toDisplayCurrency(CORPORATE_SUM), 'Helper is a no-op');
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

    /** SUM, AVG, MIN, MAX of Amount and COUNT, grouped by stage, from the provider. */
    private static Map<String, Object> chartRequest(String display) {
        List<Object> measures = new List<Object>();
        for (String aggregateFunction : new List<String>{ 'SUM', 'AVG', 'MIN', 'MAX' }) {
            measures.add(
                new Map<String, Object>{ 'aggregateFunction' => aggregateFunction, 'valueFieldApiName' => 'Amount' }
            );
        }
        measures.add(new Map<String, Object>{ 'aggregateFunction' => 'COUNT' });
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => 'StageName',
            'measures' => measures,
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'displayCurrency' => display,
            'dataProvider' => PROVIDER
        };
    }

    private static BoardQueryService.MetricResult metric(String aggregateFunction, String display) {
        Map<String, Object> request = new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'aggregateFunction' => aggregateFunction,
            'valueFieldApiName' => aggregateFunction == 'COUNT' ? null : 'Amount',
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'displayCurrency' => display,
            'dataProvider' => PROVIDER
        };
        return BoardQueryService.queryMetric(JSON.serialize(request));
    }

    /** Point values by Measure index (the provider returns one category). */
    private static Map<Integer, Decimal> valuesByMeasure(BoardChartQuery.ChartResult chart) {
        Map<Integer, Decimal> values = new Map<Integer, Decimal>();
        for (BoardChartEngine.ChartPoint point : chart.points) {
            values.put(point.measureIndex, point.value);
        }
        return values;
    }

    private static void assertClose(Decimal expected, Decimal actual, String message) {
        Assert.isNotNull(actual, message);
        Assert.isTrue(Math.abs(expected - actual) <= TOLERANCE, message + ': expected ' + expected + ', got ' + actual);
    }
}