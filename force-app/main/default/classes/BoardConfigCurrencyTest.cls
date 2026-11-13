/**
 * Entry-point tests for the Config currency (currency/06): Admin-entered amounts are read in the request's
 * `configCurrency` (default: corporate). Base filter amounts on currency fields select records as ISO literals in the
 * Config currency; Metric thresholds come back converted Config → Display currency.
 *
 * The per-currency tests need a multi-currency org with at least two active currencies, discovered at runtime (no
 * hard-coded ISO codes or rates); they skip gracefully otherwise. The injected-rate tests run in any org.
 * Data: one Opportunity of Amount 100 per active currency (one without a currency in single-currency orgs).
 */
@IsTest
private class BoardConfigCurrencyTest {
    private static final Decimal TOLERANCE = 0.01;
    private static final Decimal RECORD_AMOUNT = 100;
    /** Between 100 of one currency and 100 of any other currency at a rate other than 1. */
    private static final Decimal BASE_FILTER_AMOUNT = 99.5;

    @TestSetup
    static void setup() {
        Map<String, Decimal> rates = activeRates();
        List<String> isoCodes = rates == null ? new List<String>{ null } : new List<String>(rates.keySet());
        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        List<Opportunity> opportunities = new List<Opportunity>();
        for (String isoCode : isoCodes) {
            Opportunity opportunity = new Opportunity(
                Name = 'Config ' + isoCode,
                Amount = RECORD_AMOUNT,
                CloseDate = Date.today(),
                StageName = stage
            );
            if (isoCode != null) {
                opportunity.put('CurrencyIsoCode', isoCode);
            }
            opportunities.add(opportunity);
        }
        insert opportunities;
    }

    // ---------------------------------------------------------------------------------------------------------
    // Multi-currency org: every active currency as Config currency
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void baseFilterAmountsSelectRecordsInTheConfigCurrency() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        Set<Integer> distinctCounts = new Set<Integer>();
        for (String config : rates.keySet()) {
            Integer expected = 0;
            for (String recordIsoCode : rates.keySet()) {
                // 100 in the record's currency, converted to the Config currency.
                Decimal inConfig = RECORD_AMOUNT / rates.get(recordIsoCode) * rates.get(config);
                expected += inConfig > BASE_FILTER_AMOUNT ? 1 : 0;
            }
            distinctCounts.add(expected);
            Map<String, Object> request = countRequest(config);
            Assert.areEqual(
                expected,
                Integer.valueOf(BoardQueryService.queryMetric(JSON.serialize(request)).value),
                'Metric COUNT with Amount > ' + BASE_FILTER_AMOUNT + ' ' + config
            );
            Assert.areEqual(
                expected,
                chartTotal(config),
                'Chart COUNT with Amount > ' + BASE_FILTER_AMOUNT + ' ' + config
            );
        }
        Assert.isTrue(distinctCounts.size() > 1, 'The Config currency changes which records the amount selects');
    }

    /**
     * Bucket rules, Measure conditions and Table Bucket columns evaluate Config currency amounts in memory against
     * corporate row amounts: they must keep exactly the records the `SOQL` tier keeps.
     */
    @IsTest
    static void inMemoryConfigCurrencyConditionsMatchWhatSoqlMatches() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        List<SObject> records = Database.query('SELECT Id, Amount, CurrencyIsoCode FROM Opportunity');
        for (String config : rates.keySet()) {
            BoardQueryService.QueryScope scope = new BoardQueryService.QueryScope(countRequest(config));
            Set<Id> soqlIds = new Map<Id, SObject>(
                    Database.queryWithBinds(scope.buildSoql('Id', null, ''), scope.binds, AccessLevel.USER_MODE)
                )
                .keySet();
            Set<Id> inMemoryIds = new Set<Id>();
            for (SObject record : records) {
                Decimal corporate = converter.toCorporate(
                    (Decimal) record.get('Amount'),
                    (String) record.get('CurrencyIsoCode')
                );
                if (scope.conditions.evaluate(new Map<String, Object>{ 'Amount' => corporate })) {
                    inMemoryIds.add(record.Id);
                }
            }
            Assert.isFalse(soqlIds.isEmpty(), 'Some record matches in ' + config);
            Assert.areEqual(
                soqlIds,
                inMemoryIds,
                'In memory = SOQL with Amount > ' + BASE_FILTER_AMOUNT + ' ' + config
            );
        }
    }

    /** `IN` / `NOT_IN` amounts are in the Config currency too, in `SOQL` and in memory alike. */
    @IsTest
    static void inListAmountsAreReadInTheConfigCurrency() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        List<SObject> records = Database.query('SELECT Id, Amount, CurrencyIsoCode FROM Opportunity');
        for (String config : rates.keySet()) {
            for (String operator : new List<String>{ 'IN', 'NOT_IN' }) {
                Map<String, Object> request = countRequest(config);
                request.put(
                    'baseFilters',
                    new List<Object>{
                        new Map<String, Object>{
                            'id' => 'listed',
                            'fieldPath' => 'Amount',
                            'operator' => operator,
                            'value' => new List<Object>{ RECORD_AMOUNT }
                        }
                    }
                );
                BoardQueryService.QueryScope scope = new BoardQueryService.QueryScope(request);
                Set<Id> soqlIds = new Map<Id, SObject>(
                        Database.queryWithBinds(scope.buildSoql('Id', null, ''), scope.binds, AccessLevel.USER_MODE)
                    )
                    .keySet();
                Set<Id> expectedIds = new Set<Id>();
                Set<Id> inMemoryIds = new Set<Id>();
                for (SObject record : records) {
                    Boolean inConfig = record.get('CurrencyIsoCode') == config;
                    if (inConfig == (operator == 'IN')) {
                        expectedIds.add(record.Id);
                    }
                    Decimal corporate = converter.toCorporate(
                        (Decimal) record.get('Amount'),
                        (String) record.get('CurrencyIsoCode')
                    );
                    if (scope.conditions.evaluate(new Map<String, Object>{ 'Amount' => corporate })) {
                        inMemoryIds.add(record.Id);
                    }
                }
                Assert.areEqual(expectedIds, soqlIds, operator + ' 100 ' + config + ': only 100 ' + config + ' is 100');
                Assert.areEqual(soqlIds, inMemoryIds, 'In memory = SOQL for ' + operator + ' in ' + config);
            }
        }
    }

    @IsTest
    static void corporateIsTheConfigCurrencyWhenNoneIsSent() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        String corporate = BoardCurrencyConverter.forRequest().getCorporateIsoCode();
        Assert.areEqual(
            BoardQueryService.queryMetric(JSON.serialize(countRequest(corporate))).value,
            BoardQueryService.queryMetric(JSON.serialize(countRequest(null))).value
        );
    }

    @IsTest
    static void metricThresholdsAreConvertedFromTheConfigToTheDisplayCurrency() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String config : rates.keySet()) {
            for (String display : rates.keySet()) {
                Map<String, Object> request = thresholdRequest('SUM', config, display);
                BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(request));
                String label = '15,000 ' + config + ' in ' + display;
                Assert.areEqual(2, result.thresholdAmounts.size(), label);
                assertClose(15000 / rates.get(config) * rates.get(display), result.thresholdAmounts[0], label);
                Assert.isNull(result.thresholdAmounts[1], 'A rule without an amount stays empty');
            }
        }
    }

    @IsTest
    static void countThresholdsAreNeverConverted() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String config : rates.keySet()) {
            BoardQueryService.MetricResult result = BoardQueryService.queryMetric(
                JSON.serialize(thresholdRequest('COUNT', config, config))
            );
            Assert.areEqual(15000, result.thresholdAmounts[0].intValue(), 'COUNT thresholds are not amounts');
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Any org: injected rates (single-call paths without currency Base filters) and the single-currency no-op
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void injectedRatesConvertMetricThresholds() {
        BoardCurrencyConverter.requestConverter = BoardCurrencyConverter.fromRates(
            new List<BoardCurrencyConverter.Rate>{
                new BoardCurrencyConverter.Rate('XXA', 1, true),
                new BoardCurrencyConverter.Rate('XXB', 4, false),
                new BoardCurrencyConverter.Rate('XXC', 2, false)
            }
        );
        // 15,000 XXC ÷ 2 × 4 = 30,000 XXB.
        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(
            JSON.serialize(thresholdRequest('SUM', 'XXC', 'XXB'))
        );
        assertClose(30000, result.thresholdAmounts[0], 'Threshold in the Display currency');
        Assert.isNull(result.thresholdAmounts[1]);
    }

    @IsTest
    static void unknownConfigCurrencyFailsWithQueryError() {
        BoardCurrencyConverter.requestConverter = BoardCurrencyConverter.fromRates(
            new List<BoardCurrencyConverter.Rate>{ new BoardCurrencyConverter.Rate('XXA', 1, true) }
        );
        try {
            BoardQueryService.queryMetric(JSON.serialize(countRequest('XYZ')));
            Assert.fail('Expected an unknown currency error');
        } catch (AuraHandledException error) {
            Assert.isTrue(error.getMessage().contains('Unknown currency: XYZ'), error.getMessage());
        }
    }

    @IsTest
    static void singleCurrencyOrgsBindPlainAmountsAndKeepThresholds() {
        BoardCurrencyConverter.requestConverter = BoardCurrencyConverter.singleCurrency();
        Map<String, Decimal> rates = activeRates();
        Integer expected = [SELECT COUNT() FROM Opportunity];
        if (rates != null) {
            // A plain amount is compared with each record's amount in the corporate currency.
            expected = 0;
            for (Decimal rate : rates.values()) {
                expected += RECORD_AMOUNT / rate > BASE_FILTER_AMOUNT ? 1 : 0;
            }
        }
        Assert.areEqual(
            expected,
            Integer.valueOf(BoardQueryService.queryMetric(JSON.serialize(countRequest('XYZ'))).value),
            'The Config currency is ignored in single-currency orgs'
        );

        BoardQueryService.MetricResult sum = BoardQueryService.queryMetric(
            JSON.serialize(thresholdRequest('SUM', 'XYZ', 'XYZ'))
        );
        Assert.areEqual(15000, sum.thresholdAmounts[0].intValue(), 'Thresholds as entered');
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

    private static List<Object> amountBaseFilter() {
        return new List<Object>{
            new Map<String, Object>{
                'id' => 'big',
                'fieldPath' => 'Amount',
                'operator' => 'GT',
                'value' => BASE_FILTER_AMOUNT
            }
        };
    }

    /** COUNT of Opportunities with `Amount > 99.5` in `config`. */
    private static Map<String, Object> countRequest(String config) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'aggregateFunction' => 'COUNT',
            'filters' => new List<Object>(),
            'baseFilters' => amountBaseFilter(),
            'configCurrency' => config
        };
    }

    /** Total COUNT across the stages of a Chart with the same Base filter (a grouped query: never a HAVING). */
    private static Integer chartTotal(String config) {
        Map<String, Object> request = new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => 'StageName',
            'measures' => new List<Object>{ new Map<String, Object>{ 'aggregateFunction' => 'COUNT' } },
            'baseFilters' => amountBaseFilter(),
            'configCurrency' => config
        };
        Decimal total = 0;
        for (BoardChartEngine.ChartPoint point : BoardChartQuery.queryChart(JSON.serialize(request)).points) {
            total += point.value;
        }
        return total.intValue();
    }

    /** Metric with thresholds 15,000 and (no amount) in `config`, shown in `display`. */
    private static Map<String, Object> thresholdRequest(String aggregateFunction, String config, String display) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'aggregateFunction' => aggregateFunction,
            'valueFieldApiName' => aggregateFunction == 'COUNT' ? null : 'Amount',
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'displayCurrency' => display,
            'configCurrency' => config,
            'thresholdAmounts' => new List<Object>{ 15000, null }
        };
    }

    private static void assertClose(Decimal expected, Decimal actual, String message) {
        Assert.isNotNull(actual, message);
        Assert.isTrue(Math.abs(expected - actual) <= TOLERANCE, message + ': expected ' + expected + ', got ' + actual);
    }
}