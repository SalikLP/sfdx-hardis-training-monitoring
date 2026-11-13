/**
 * Amount range filters in the Display currency (currency/05): an end-user range on a currency field ("over 5,000")
 * means 5,000 in the request's `displayCurrency`, emitted as a validated ISO literal (`Amount >= EUR5000`), never as
 * a currency `HAVING`. Single-currency orgs keep bare numbers.
 *
 * The per-currency tests need a multi-currency org with at least two active currencies, discovered at runtime (no
 * hard-coded ISO codes or rates); they skip gracefully otherwise. Expected counts come from the inserted amounts and
 * the spec's conversion (`amount ÷ rate[record] × rate[display]`). The injected-rate tests run in any org.
 * Data: per active currency (or once, in a single-currency org), an Account and two Opportunities in that currency
 * with amounts 1,000 and 10; Probability 100, so Expected Revenue (a calculated currency field) equals Amount.
 */
@IsTest
private class BoardCurrencyRangeFilterTest {
    private static final List<Decimal> AMOUNTS = new List<Decimal>{ 1000, 10 };

    @TestSetup
    static void setup() {
        Map<String, Decimal> rates = activeRates();
        List<String> isoCodes = rates == null ? new List<String>{ null } : new List<String>(rates.keySet());
        Map<String, Account> accounts = new Map<String, Account>();
        for (String isoCode : isoCodes) {
            Account account = new Account(Name = 'Range ' + isoCode, AnnualRevenue = AMOUNTS[0]);
            if (isoCode != null) {
                account.put('CurrencyIsoCode', isoCode);
            }
            accounts.put(isoCode, account);
        }
        insert accounts.values();
        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        List<Opportunity> opportunities = new List<Opportunity>();
        for (String isoCode : isoCodes) {
            for (Decimal amount : AMOUNTS) {
                Opportunity opportunity = new Opportunity(
                    Name = 'Range ' + isoCode + ' ' + amount,
                    AccountId = accounts.get(isoCode).Id,
                    Amount = amount,
                    Probability = 100,
                    CloseDate = Date.today(),
                    StageName = stage
                );
                if (isoCode != null) {
                    opportunity.put('CurrencyIsoCode', isoCode);
                }
                opportunities.add(opportunity);
            }
        }
        insert opportunities;
    }

    // ---------------------------------------------------------------------------------------------------------
    // Converter: the range bound of an end-user amount
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void amountRangeBoundsAreIsoLiteralsInTheDisplayCurrency() {
        BoardCurrencyConverter rates = injected();

        Object bound = rates.displayAmountBound(5000, new Map<String, Object>{ 'displayCurrency' => ' xxb ' });
        Assert.isInstanceOfType(bound, BoardCurrencyConverter.IsoAmount.class);
        Assert.areEqual('XXB5000', ((BoardCurrencyConverter.IsoAmount) bound).toSoql());

        Object decimals = rates.displayAmountBound(1234.50, new Map<String, Object>{ 'displayCurrency' => 'XXA' });
        Assert.areEqual('XXA1234.50', ((BoardCurrencyConverter.IsoAmount) decimals).toSoql());
    }

    @IsTest
    static void inactiveOrUnknownDisplayCurrenciesNeverReachSoql() {
        for (String display : new List<String>{ 'XXC', 'XYZ', 'XXA5 OR Amount' }) {
            try {
                injected().displayAmountBound(5000, new Map<String, Object>{ 'displayCurrency' => display });
                Assert.fail('Expected a currency error for ' + display);
            } catch (BoardErrors.BoardException error) {
                Assert.areEqual(BoardErrors.QUERY_ERROR, error.category, display);
            }
        }
    }

    @IsTest
    static void singleCurrencyAmountRangeBoundsAreBareNumbers() {
        Decimal amount = 5000;
        Assert.areEqual(
            amount,
            BoardCurrencyConverter.singleCurrency()
                .displayAmountBound(amount, new Map<String, Object>{ 'displayCurrency' => 'EUR' })
        );
    }

    // ---------------------------------------------------------------------------------------------------------
    // Entry point: Metric counts under a range filter
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void aRangeInEachDisplayCurrencySelectsTheRightRecords() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        Boolean expectedRevenueFilterable = Opportunity.ExpectedRevenue.getDescribe().isFilterable();
        for (String display : rates.keySet()) {
            Integer atLeast = expectedCount(rates, display, 1000, null);
            Integer atMost = expectedCount(rates, display, null, 999.99);
            Integer between = expectedCount(rates, display, 5, 999.99);
            String label = ' in ' + display;
            Assert.areEqual(atLeast, countWith(display, range('Amount', 'GTE', '1000', null)), 'Amount >=' + label);
            Assert.areEqual(atMost, countWith(display, range('Amount', 'LTE', null, '999.99')), 'Amount <=' + label);
            Assert.areEqual(
                between,
                countWith(display, range('Amount', 'BETWEEN', '5', '999.99')),
                'Amount between' + label
            );
            // Each Account's 1,000 Annual Revenue is in its currency and shared by its two Opportunities.
            Integer accountsAtLeast = expectedCount(rates, display, new List<Decimal>{ 1000, 1000 }, 1000, null);
            Assert.areEqual(
                accountsAtLeast,
                countWith(display, range('Account.AnnualRevenue', 'GTE', '1000', null)),
                'Path field' + label
            );
            if (expectedRevenueFilterable) {
                Assert.areEqual(
                    atLeast,
                    countWith(display, range('ExpectedRevenue', 'GTE', '1000', null)),
                    'Calculated currency field' + label
                );
            }
        }
    }

    @IsTest
    static void singleCurrencyOrgRangesCompareBareNumbers() {
        if (UserInfo.isMultiCurrencyOrganization()) {
            return;
        }
        Assert.areEqual(1, countWith('EUR', range('Amount', 'GTE', '1000', null)));
        Assert.areEqual(1, countWith(null, range('Amount', 'BETWEEN', '5', '999.99')));
    }

    @IsTest
    static void anInactiveDisplayCurrencyFailsBeforeTheQueryRuns() {
        BoardCurrencyConverter.requestConverter = injected();
        Map<String, Object> request = metricRequest('XXC', range('Amount', 'GTE', '1000', null));
        try {
            BoardQueryService.queryMetric(JSON.serialize(request));
            Assert.fail('Expected a currency error');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual(BoardErrors.QUERY_ERROR, payload.get('category'), String.valueOf(payload));
        }
    }

    @IsTest
    static void dateRangeFiltersStillSkipNumberFieldsByConvention() {
        Map<String, Object> dates = range('Amount', 'GTE', '2026-01-01', null);
        dates.put('type', 'DATE_RANGE');
        dates.put('explicit', false);
        Integer total = [SELECT COUNT() FROM Opportunity];
        Assert.areEqual(total, countWith(null, dates), 'Incompatible convention binding is skipped');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** Corporate XXA, active XXB at 2, inactive XXC at 3. */
    private static BoardCurrencyConverter injected() {
        return BoardCurrencyConverter.fromRates(
            new List<BoardCurrencyConverter.Rate>{
                new BoardCurrencyConverter.Rate('XXA', 1, true),
                new BoardCurrencyConverter.Rate('XXB', 2, false),
                new BoardCurrencyConverter.Rate('XXC', 3, false, false)
            }
        );
    }

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

    /** Test Opportunities whose Amount, converted to `display`, lies in `[low, high]` (null bound: open). */
    private static Integer expectedCount(Map<String, Decimal> rates, String display, Decimal low, Decimal high) {
        return expectedCount(rates, display, AMOUNTS, low, high);
    }

    /** Per currency, the `amounts` (one per test Opportunity) whose value converted to `display` is in range. */
    private static Integer expectedCount(
        Map<String, Decimal> rates,
        String display,
        List<Decimal> amounts,
        Decimal low,
        Decimal high
    ) {
        Integer count = 0;
        for (String isoCode : rates.keySet()) {
            for (Decimal amount : amounts) {
                Decimal shown = isoCode == display ? amount : amount / rates.get(isoCode) * rates.get(display);
                if ((low == null || shown >= low) && (high == null || shown <= high)) {
                    count++;
                }
            }
        }
        return count;
    }

    private static Map<String, Object> range(String fieldPath, String operator, String fromValue, String toValue) {
        return new Map<String, Object>{
            'filterId' => 'amount',
            'type' => 'NUMBER_RANGE',
            'fieldPath' => fieldPath,
            'explicit' => true,
            'operator' => operator,
            'values' => new List<Object>(),
            'from' => fromValue,
            'to' => toValue
        };
    }

    private static Map<String, Object> metricRequest(String display, Map<String, Object> filter) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'aggregateFunction' => 'COUNT',
            'filters' => new List<Object>{ filter },
            'baseFilters' => new List<Object>(),
            'displayCurrency' => display
        };
    }

    private static Integer countWith(String display, Map<String, Object> filter) {
        return Integer.valueOf(BoardQueryService.queryMetric(JSON.serialize(metricRequest(display, filter))).value);
    }
}