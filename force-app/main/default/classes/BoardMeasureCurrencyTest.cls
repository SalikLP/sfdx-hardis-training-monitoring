/**
 * Currency in Measures (currency/07) through the Metric and Chart query entry points: currency Formula measures
 * (constants in the Config currency), Average per record and Cross-object measures of a currency field, Measure
 * condition amounts in the Config currency, Gauge amounts, and Share of total (never converted).
 *
 * The per-currency tests need a multi-currency org with at least two active currencies, discovered at runtime; they
 * skip otherwise. Expected values are computed here from each record's amount and currency and the active
 * `CurrencyType` rates. The injected-rate tests run in any org.
 * Data: six Opportunities on two Accounts and two stages, amounts spread over the active currencies.
 */
@IsTest
private class BoardMeasureCurrencyTest {
    private static final Decimal TOLERANCE = 0.01;
    private static final Decimal TARGET = 15000;
    private static final Decimal CONDITION_AMOUNT = 150;

    @TestSetup
    static void setup() {
        Map<String, Decimal> rates = activeRates();
        List<String> isoCodes = rates == null ? new List<String>{ null } : new List<String>(rates.keySet());
        Account north = new Account(Name = 'Measure Currency North');
        Account south = new Account(Name = 'Measure Currency South');
        insert new List<Account>{ north, south };
        List<Schema.PicklistEntry> stages = Opportunity.StageName.getDescribe().getPicklistValues();
        List<Decimal> amounts = new List<Decimal>{ 100, 300, 7, 160, 1000, 400 };
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < amounts.size(); i++) {
            Opportunity opportunity = new Opportunity(
                Name = 'Measure Currency ' + i,
                AccountId = Math.mod(i, 2) == 0 ? north.Id : south.Id,
                Amount = amounts[i],
                CloseDate = Date.today(),
                StageName = stages[Math.mod(i / 2, 2)].getValue()
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
    // Multi-currency org: every active currency as Display (and Config) currency
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void currencyFormulaMeasureIsInTheDisplayCurrencyWithItsTargetInTheConfigCurrency() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        Decimal corporateSum = corporateSum(null);
        for (String config : rates.keySet()) {
            for (String display : rates.keySet()) {
                BoardQueryService.MetricResult gap = BoardQueryService.queryMetric(
                    JSON.serialize(
                        metricRequest(
                            new List<Object>{ hidden(measure('SUM', 'Amount')), currencyFormula('A - ' + TARGET) },
                            display,
                            config
                        )
                    )
                );
                String label = display + ' (Config ' + config + ')';
                Decimal expected = (corporateSum - TARGET / rates.get(config)) * rates.get(display);
                assertClose(expected, toDecimal(gap.value), 'Gap to targetMeasure in ' + label);
                Assert.areEqual(
                    display,
                    gap.currencyIsoCode,
                    'A currency Formula measure carries the Display currency'
                );
                Assert.areEqual(Schema.DisplayType.CURRENCY.name(), gap.valueType);
            }
        }
    }

    @IsTest
    static void unflaggedFormulaMeasureIsNeverAnAmount() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        Decimal corporateSum = corporateSum(null);
        for (String display : rates.keySet()) {
            // Average deal size: SUM / COUNT, as shown, without a currency.
            BoardQueryService.MetricResult average = BoardQueryService.queryMetric(
                JSON.serialize(
                    metricRequest(
                        new List<Object>{
                            hidden(measure('SUM', 'Amount')),
                            hidden(measure('COUNT', null)),
                            new Map<String, Object>{ 'aggregateFunction' => 'FORMULA', 'formula' => 'A / B' }
                        },
                        display,
                        null
                    )
                )
            );
            assertClose(corporateSum * rates.get(display) / 6, toDecimal(average.value), 'A / B in ' + display);
            Assert.isNull(average.currencyIsoCode, 'An unflagged Formula measure is not converted');
        }
    }

    @IsTest
    static void chartConstantCurrencyFormulaIsConvertedFromTheConfigCurrency() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String config : rates.keySet()) {
            for (String display : rates.keySet()) {
                Map<String, Object> targetMeasure = currencyFormula(String.valueOf(TARGET));
                targetMeasure.put('render', BoardChartQuery.REFERENCE_LINE_RENDER);
                Map<String, Object> request = chartRequest(
                    new List<Object>{
                        measure('SUM', 'Amount'),
                        currencyFormula(String.valueOf(TARGET)),
                        targetMeasure
                    },
                    display
                );
                request.put('configCurrency', config);
                BoardChartQuery.ChartResult result = BoardChartQuery.queryChart(JSON.serialize(request));
                String label = display + ' (Config ' + config + ')';
                Decimal expected = TARGET / rates.get(config) * rates.get(display);
                Assert.areEqual(display, result.currencyIsoCodes[1], 'Formula ISO code in ' + label);
                for (BoardChartEngine.ChartPoint point : result.points) {
                    if (point.measureIndex == 1) {
                        assertClose(expected, point.value, 'Target per category in ' + label);
                    }
                }
                assertClose(expected, result.overallValues[2], 'Target Reference line in ' + label);
            }
        }
    }

    @IsTest
    static void averagePerRecordOfAnAmountIsConverted() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        // One SUM per Account (corporate), averaged.
        Map<Id, Decimal> perAccount = new Map<Id, Decimal>();
        for (SObject record : records()) {
            Id accountId = (Id) record.get('AccountId');
            Decimal previous = perAccount.containsKey(accountId) ? perAccount.get(accountId) : 0;
            perAccount.put(accountId, previous + corporate(record, rates));
        }
        Decimal corporateAverage = 0;
        for (Decimal value : perAccount.values()) {
            corporateAverage += value;
        }
        corporateAverage = corporateAverage / perAccount.size();
        for (String display : rates.keySet()) {
            Map<String, Object> perRecord = measure('AVG_PER', 'Amount');
            perRecord.put('perField', 'AccountId');
            perRecord.put('inner', 'SUM');
            BoardQueryService.MetricResult result = BoardQueryService.queryMetric(
                JSON.serialize(metricRequest(new List<Object>{ perRecord }, display, null))
            );
            assertClose(corporateAverage * rates.get(display), toDecimal(result.value), 'AVG_PER in ' + display);
            Assert.areEqual(display, result.currencyIsoCode);
        }
    }

    @IsTest
    static void crossObjectMeasureOfAnAmountIsConverted() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        Decimal corporateSum = corporateSum(null);
        for (String display : rates.keySet()) {
            Map<String, Object> pipeline = measure('SUM', 'Amount');
            pipeline.put('sourceObject', 'Opportunity');
            pipeline.put('categoryMapping', 'AccountId');
            Map<String, Object> request = metricRequest(
                new List<Object>{ hidden(measure('COUNT', null)), pipeline },
                display,
                null
            );
            request.put('objectApiName', 'Account');
            BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(request));
            assertClose(corporateSum * rates.get(display), toDecimal(result.value), 'Cross-object SUM in ' + display);
            Assert.areEqual(display, result.currencyIsoCode);
        }
    }

    @IsTest
    static void measureConditionAmountsAreReadInTheConfigCurrency() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        Set<Decimal> distinctTotals = new Set<Decimal>();
        for (String config : rates.keySet()) {
            Decimal corporateTotal = corporateSum(config);
            distinctTotals.add(corporateTotal);
            for (String display : rates.keySet()) {
                Map<String, Object> big = measure('SUM', 'Amount');
                big.put('condition', amountAbove(CONDITION_AMOUNT));
                Map<String, Object> request = metricRequest(new List<Object>{ big }, display, config);
                String label = display + ' (Config ' + config + ')';
                BoardQueryService.MetricResult metric = BoardQueryService.queryMetric(JSON.serialize(request));
                assertClose(
                    corporateTotal * rates.get(display),
                    toDecimal(metric.value),
                    'Metric with Amount > ' + label
                );

                Map<String, Object> chart = chartRequest(new List<Object>{ big }, display);
                chart.put('configCurrency', config);
                Decimal chartTotal = 0;
                for (BoardChartEngine.ChartPoint point : BoardChartQuery.queryChart(JSON.serialize(chart)).points) {
                    chartTotal += point.value == null ? 0 : point.value;
                }
                assertClose(corporateTotal * rates.get(display), chartTotal, 'Chart with Amount > ' + label);
            }
        }
        Assert.isTrue(distinctTotals.size() > 1, 'The Config currency changes which records the condition keeps');
    }

    @IsTest
    static void gaugeAmountsAreConvertedFromTheConfigCurrency() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String config : rates.keySet()) {
            for (String display : rates.keySet()) {
                Map<String, Object> request = metricRequest(
                    new List<Object>{ measure('SUM', 'Amount') },
                    display,
                    config
                );
                request.put('gaugeAmounts', new List<Object>{ 0, TARGET });
                request.put('thresholdAmounts', new List<Object>{ 5000 });
                BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(request));
                Decimal rate = rates.get(display) / rates.get(config);
                assertClose(0, result.gaugeAmounts[0], 'Gauge minimum');
                assertClose(TARGET * rate, result.gaugeAmounts[1], 'Gauge maximum in ' + display);
                assertClose(5000 * rate, result.thresholdAmounts[0], 'Gauge band in ' + display);

                request.put('measures', new List<Object>{ measure('COUNT', null) });
                BoardQueryService.MetricResult count = BoardQueryService.queryMetric(JSON.serialize(request));
                assertClose(TARGET, count.gaugeAmounts[1], 'A count Gauge keeps its amounts');
            }
        }
    }

    @IsTest
    static void shareOfTotalIsNeverConverted() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        Map<String, Decimal> first;
        for (String display : rates.keySet()) {
            Map<String, Object> share = measure('SUM', 'Amount');
            share.put('showAs', 'percentOfTotal');
            BoardChartQuery.ChartResult result = BoardChartQuery.queryChart(
                JSON.serialize(chartRequest(new List<Object>{ share }, display))
            );
            Assert.isNull(result.currencyIsoCodes[0], 'A Share of total carries no currency');
            Map<String, Decimal> values = new Map<String, Decimal>();
            Decimal total = 0;
            for (BoardChartEngine.ChartPoint point : result.points) {
                values.put(point.categoryKey, point.value);
                total += point.value;
            }
            assertClose(1, total, 'Shares add up to 1 in ' + display);
            if (first == null) {
                first = values;
            }
            for (String key : first.keySet()) {
                assertClose(first.get(key), values.get(key), 'Same share in every Display currency: ' + key);
            }
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Any org: injected rates (XXA corporate, XXB at 0.9) and single-currency orgs
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void injectedRatesConvertCurrencyFormulaConstants() {
        injectRates();
        BoardQueryService.MetricResult metric = BoardQueryService.queryMetric(
            JSON.serialize(metricRequest(new List<Object>{ currencyFormula('15000') }, 'XXB', 'XXA'))
        );
        assertClose(13500, toDecimal(metric.value), 'Metric 15,000 XXA targetMeasure in XXB');
        Assert.areEqual('XXB', metric.currencyIsoCode);

        BoardChartQuery.ChartResult chart = BoardChartQuery.queryChart(
            JSON.serialize(
                new Map<String, Object>{
                    'objectApiName' => 'Opportunity',
                    'groupByField' => 'StageName',
                    'measures' => new List<Object>{ currencyFormula('15000') },
                    'displayCurrency' => 'XXA',
                    'configCurrency' => 'XXB'
                }
            )
        );
        Assert.areEqual('XXA', chart.currencyIsoCodes[0]);
        Assert.isFalse(chart.points.isEmpty());
        for (BoardChartEngine.ChartPoint point : chart.points) {
            assertClose(16666.67, point.value, 'Chart 15,000 XXB targetMeasure in XXA');
        }
    }

    @IsTest
    static void injectedRatesEvaluateACursorFinishedCurrencyFormula() {
        injectRates();
        // Inputs finished by the client in the Display currency XXB: A = 900 XXB (1,000 XXA), B = a count of 4.
        Map<String, Object> request = metricRequest(
            new List<Object>{
                hidden(measure('SUM', 'Amount')),
                hidden(measure('COUNT', null)),
                currencyFormula('A / B + 100')
            },
            'XXB',
            'XXA'
        );
        request.put('values', new List<Object>{ 900, 4, null });
        request.put('currencyIsoCodes', new List<Object>{ 'XXB', null, null });
        assertClose(315, BoardFormulaMeasures.evaluateMetric(JSON.serialize(request)), '(1,000 / 4 + 100) XXA in XXB');
    }

    @IsTest
    static void singleCurrencyOrgsEvaluateCurrencyFormulasAsEntered() {
        BoardCurrencyConverter.requestConverter = BoardCurrencyConverter.singleCurrency();
        BoardQueryService.MetricResult metric = BoardQueryService.queryMetric(
            JSON.serialize(metricRequest(new List<Object>{ currencyFormula('15000') }, 'XYZ', 'XYZ'))
        );
        assertClose(15000, toDecimal(metric.value), 'Constant as entered');
        Assert.areEqual(UserInfo.getDefaultCurrency(), metric.currencyIsoCode, 'The org currency');
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

    private static void injectRates() {
        BoardCurrencyConverter.requestConverter = BoardCurrencyConverter.fromRates(
            new List<BoardCurrencyConverter.Rate>{
                new BoardCurrencyConverter.Rate('XXA', 1, true),
                new BoardCurrencyConverter.Rate('XXB', 0.9, false)
            }
        );
    }

    private static List<SObject> records() {
        return Database.query('SELECT Id, AccountId, Amount, CurrencyIsoCode FROM Opportunity');
    }

    private static Decimal corporate(SObject record, Map<String, Decimal> rates) {
        return (Decimal) record.get('Amount') / rates.get((String) record.get('CurrencyIsoCode'));
    }

    /**
     * Corporate SUM of the test amounts; with `config`, only those above `CONDITION_AMOUNT` in that currency (the
     * Measure condition).
     */
    private static Decimal corporateSum(String config) {
        Map<String, Decimal> rates = activeRates();
        Decimal total = 0;
        for (SObject record : records()) {
            Decimal amount = corporate(record, rates);
            if (config == null || amount * rates.get(config) > CONDITION_AMOUNT) {
                total += amount;
            }
        }
        return total;
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        return new Map<String, Object>{ 'aggregateFunction' => aggregateFunction, 'valueFieldApiName' => valueField };
    }

    private static Map<String, Object> hidden(Map<String, Object> measure) {
        measure.put('hidden', true);
        return measure;
    }

    private static Map<String, Object> currencyFormula(String formula) {
        return new Map<String, Object>{ 'aggregateFunction' => 'FORMULA', 'formula' => formula, 'isCurrency' => true };
    }

    /** Measure condition `Amount > amount` (Config currency). */
    private static Map<String, Object> amountAbove(Decimal amount) {
        return new Map<String, Object>{
            'logic' => 'AND',
            'conditions' => new List<Object>{
                new Map<String, Object>{ 'id' => 'mc1', 'fieldPath' => 'Amount', 'operator' => 'GT', 'value' => amount }
            }
        };
    }

    private static Map<String, Object> metricRequest(List<Object> measures, String display, String config) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'measures' => measures,
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'displayCurrency' => display,
            'configCurrency' => config
        };
    }

    private static Map<String, Object> chartRequest(List<Object> measures, String display) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => 'StageName',
            'measures' => measures,
            'displayCurrency' => display
        };
    }

    private static Decimal toDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }

    private static void assertClose(Decimal expected, Decimal actual, String message) {
        Assert.isNotNull(actual, message);
        Assert.isTrue(Math.abs(expected - actual) <= TOLERANCE, message + ': expected ' + expected + ', got ' + actual);
    }
}