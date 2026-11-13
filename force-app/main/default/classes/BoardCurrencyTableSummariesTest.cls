/**
 * Entry-point tests for the Display currency in Table features (currency/09): Data bar scales and Total, Group and
 * Subtotal summaries over a currency column are computed from amounts converted record -> Display currency, so
 * summaries over records in different currencies are correct. Record counts and non-currency columns never convert.
 *
 * The per-currency tests need a multi-currency org with at least two active currencies, discovered at runtime (no
 * hard-coded ISO codes or rates); they skip gracefully otherwise. Expected values are worked out here from each stored
 * record: its own amount Ã· rate[record currency] Ã— rate[display currency], then summed, averaged or compared.
 * Data: six Opportunities in two groups (`NextStep` Group A / Group B), each group spread over the active currencies.
 */
@IsTest
private class BoardCurrencyTableSummariesTest {
    private static final Decimal TOLERANCE = 0.01;
    private static final String GROUP_A = 'Group A';
    private static final String GROUP_B = 'Group B';
    private static final List<Decimal> AMOUNTS = new List<Decimal>{ 100, 250, 1000, 40, 600, 75 };

    @TestSetup
    static void setup() {
        Map<String, Decimal> rates = activeRates();
        List<String> isoCodes = rates == null ? new List<String>{ null } : new List<String>(rates.keySet());
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < AMOUNTS.size(); i++) {
            Opportunity opportunity = new Opportunity(
                Name = 'Summary Currency ' + i,
                Amount = AMOUNTS[i],
                Probability = 10 + i,
                NextStep = i < 3 ? GROUP_A : GROUP_B,
                CloseDate = Date.today(),
                StageName = 'Prospecting'
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
    static void dataBarScaleSpansTheConvertedAmounts() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String display : rates.keySet()) {
            Map<String, Object> request = tableRequest(display);
            amountColumn(request).put('displayAs', 'dataBar');

            BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

            List<Decimal> converted = convertedAmounts(storedRecords(null), rates, display);
            Assert.areEqual('amount', result.barScales[0].columnId);
            assertClose(maxOf(converted), result.barScales[0].max, 'Bar max in ' + display);
            assertClose(minOf(converted), result.barScales[0].min, 'Bar min in ' + display);
        }
    }

    @IsTest
    static void totalRowSummariesAreOverTheConvertedAmounts() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String display : rates.keySet()) {
            Map<String, Object> request = tableRequest(display);
            request.put('showTotalRow', true);
            amountColumn(request).put('summaries', new List<Object>{ 'SUM', 'AVG', 'MIN', 'MAX' });

            BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

            Assert.areEqual('amount', result.totals[0].columnId);
            assertSummaries(
                convertedAmounts(storedRecords(null), rates, display),
                result.totals[0],
                'Total ' + display
            );
        }
    }

    @IsTest
    static void groupAndSubtotalSummariesAreOverTheConvertedAmounts() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String display : rates.keySet()) {
            Map<String, Object> request = tableRequest(display);
            request.put('pageSize', 10);
            request.put('showSubtotals', true);
            request.put(
                'groupBy',
                new List<Object>{
                    new Map<String, Object>{ 'fieldPath' => 'NextStep' },
                    new Map<String, Object>{ 'fieldPath' => 'Name' }
                }
            );
            amountColumn(request).put('summaries', new List<Object>{ 'SUM', 'AVG', 'MIN', 'MAX' });
            probabilityColumn(request).put('summaries', new List<Object>{ 'SUM' });

            BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

            Integer firstLevelGroups = 0;
            for (BoardTableEngine.TableGroup tableGroup : result.groups) {
                List<Opportunity> members = tableGroup.level == 2
                    ? storedRecordsNamed(tableGroup.key)
                    : storedRecords(tableGroup.key);
                firstLevelGroups += tableGroup.level == 2 ? 0 : 1;
                Assert.areEqual(members.size(), tableGroup.count, 'Counts never convert');
                assertSummaries(
                    convertedAmounts(members, rates, display),
                    tableGroup.summaries[0],
                    tableGroup.key + ' in ' + display
                );
                assertClose(
                    sumOf(probabilities(members)),
                    tableGroup.summaries[1].summaries[0].value,
                    'Probability is not an amount'
                );
            }
            Assert.areEqual(2, firstLevelGroups, 'Group A and Group B');

            // A later grouped page carries the same converted Group summaries.
            BoardQueryService.TablePage again = BoardQueryService.fetchGroupedTablePage(
                JSON.serialize(request),
                result.paginationCursor,
                0
            );
            assertSummaries(
                convertedAmounts(storedRecords(again.groups[0].key), rates, display),
                again.groups[0].summaries[0],
                'Later page ' + display
            );
        }
    }

    @IsTest
    static void aggregatedTableGroupRowsTotalAndBarsAreOverTheConvertedAmounts() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        for (String display : rates.keySet()) {
            assertAggregatedTableConverted(
                BoardQueryService.queryTable(JSON.serialize(aggregateRequest(display))),
                rates,
                display
            );
        }
    }

    @IsTest
    static void aggregatedTableCursorTierIsOverTheConvertedAmounts() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        BoardTableAggregate.MAX_GROUPS = 1;
        for (String display : rates.keySet()) {
            BoardQueryService.TableResult result = BoardQueryService.queryTable(
                JSON.serialize(aggregateRequest(display))
            );
            Assert.isNotNull(result.aggregateCursor, 'More groups than the SOQL tier holds: cursor tier');
            Assert.isTrue(result.aggregateCursor.isComplete, 'Six records fit in one chunk');
            assertAggregatedTableConverted(result, rates, display);
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Any org
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void singleCurrencyConverterLeavesSummariesAndBarsAsStored() {
        BoardCurrencyConverter.requestConverter = BoardCurrencyConverter.singleCurrency();
        List<Decimal> stored = AMOUNTS.clone();

        Map<String, Object> request = tableRequest(null);
        request.put('showTotalRow', true);
        amountColumn(request).put('displayAs', 'dataBar');
        amountColumn(request).put('summaries', new List<Object>{ 'SUM', 'AVG', 'MIN', 'MAX' });
        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));
        BoardQueryService.TableResult aggregated = BoardQueryService.queryTable(JSON.serialize(aggregateRequest(null)));

        Assert.areEqual(2, aggregated.aggregateGroups.size());
        Assert.areEqual(AMOUNTS.size(), aggregated.totalCount, 'Counts never convert');
        if (UserInfo.isMultiCurrencyOrganization()) {
            // SOQL still aggregates the stored amounts in the corporate currency here: only the shape is checked.
            Assert.isNotNull(result.barScales[0].max);
            Assert.areEqual(4, result.totals[0].summaries.size());
            return;
        }
        assertClose(maxOf(stored), result.barScales[0].max, 'Bar max');
        assertClose(minOf(stored), result.barScales[0].min, 'Bar min');
        assertSummaries(stored, result.totals[0], 'Total row');
        assertSummaries(stored, aggregated.totals[0], 'Aggregated Total row');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** Group rows per `NextStep`, the Total row and the Data bar scale over the Group rows' first summary (SUM). */
    private static void assertAggregatedTableConverted(
        BoardQueryService.TableResult result,
        Map<String, Decimal> rates,
        String display
    ) {
        Assert.areEqual(2, result.aggregateGroups.size(), 'Group A and Group B');
        Decimal largestGroupSum;
        for (BoardTableAggregate.GroupRow groupRow : result.aggregateGroups) {
            List<Opportunity> members = storedRecords(groupRow.key);
            Assert.areEqual(members.size(), groupRow.count, 'Counts never convert');
            List<Decimal> converted = convertedAmounts(members, rates, display);
            assertSummaries(converted, groupRow.summaries[0], groupRow.key + ' in ' + display);
            largestGroupSum = largestGroupSum == null ? sumOf(converted) : Math.max(largestGroupSum, sumOf(converted));
        }
        assertSummaries(convertedAmounts(storedRecords(null), rates, display), result.totals[0], 'Total ' + display);
        assertClose(largestGroupSum, result.barScales[0].max, 'Bar max over Group rows in ' + display);
    }

    /** The column total's SUM, AVG, MIN and MAX (in the order requested) match `amounts`. */
    private static void assertSummaries(List<Decimal> amounts, BoardTableEngine.ColumnTotal total, String message) {
        Map<String, Decimal> expected = new Map<String, Decimal>{
            'SUM' => sumOf(amounts),
            'AVG' => sumOf(amounts).divide(amounts.size(), 10),
            'MIN' => minOf(amounts),
            'MAX' => maxOf(amounts)
        };
        Assert.areEqual(4, total.summaries.size(), message);
        for (BoardTableEngine.SummaryValue summary : total.summaries) {
            assertClose(expected.get(summary.summaryFunction), summary.value, message + ' ' + summary.summaryFunction);
        }
    }

    private static List<Decimal> convertedAmounts(
        List<Opportunity> records,
        Map<String, Decimal> rates,
        String display
    ) {
        List<Decimal> converted = new List<Decimal>();
        for (Opportunity record : records) {
            String recordIso = (String) record.get('CurrencyIsoCode');
            converted.add((record.Amount * rates.get(display)).divide(rates.get(recordIso), 10));
        }
        return converted;
    }

    private static List<Decimal> probabilities(List<Opportunity> records) {
        List<Decimal> values = new List<Decimal>();
        for (Opportunity record : records) {
            values.add(record.Probability);
        }
        return values;
    }

    private static Decimal sumOf(List<Decimal> values) {
        Decimal sum = 0;
        for (Decimal value : values) {
            sum += value;
        }
        return sum;
    }

    private static Decimal maxOf(List<Decimal> values) {
        Decimal largest;
        for (Decimal value : values) {
            largest = largest == null ? value : Math.max(largest, value);
        }
        return largest;
    }

    private static Decimal minOf(List<Decimal> values) {
        Decimal smallest;
        for (Decimal value : values) {
            smallest = smallest == null ? value : Math.min(smallest, value);
        }
        return smallest;
    }

    /** Every stored Opportunity, or those whose `NextStep` is `nextStep`. */
    private static List<Opportunity> storedRecords(String nextStep) {
        String isoField = UserInfo.isMultiCurrencyOrganization() ? ', CurrencyIsoCode' : '';
        String condition = nextStep == null ? '' : ' WHERE NextStep = :nextStep';
        return (List<Opportunity>) Database.query(
            'SELECT Id, Name, Amount, Probability' + isoField + ' FROM Opportunity' + condition
        );
    }

    private static List<Opportunity> storedRecordsNamed(String name) {
        String isoField = UserInfo.isMultiCurrencyOrganization() ? ', CurrencyIsoCode' : '';
        return (List<Opportunity>) Database.query(
            'SELECT Id, Name, Amount, Probability' + isoField + ' FROM Opportunity WHERE Name = :name'
        );
    }

    /** Active ISO code â†’ conversion rate (corporate = 1), or null when fewer than two currencies are active. */
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

    /** Name, Amount (currency) and Probability (percent) columns. */
    private static Map<String, Object> tableRequest(String display) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => new List<Object>{
                new Map<String, Object>{ 'id' => 'name', 'fieldPath' => 'Name' },
                new Map<String, Object>{ 'id' => 'amount', 'fieldPath' => 'Amount' },
                new Map<String, Object>{ 'id' => 'probability', 'fieldPath' => 'Probability' }
            },
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'displayCurrency' => display
        };
    }

    /** Opportunities grouped by `NextStep` with Detail rows off: Amount summaries shown as a Data bar, Total row on. */
    private static Map<String, Object> aggregateRequest(String display) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'amount',
                    'fieldPath' => 'Amount',
                    'displayAs' => 'dataBar',
                    'summaries' => new List<Object>{ 'SUM', 'AVG', 'MIN', 'MAX' }
                }
            },
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'pageSize' => 10,
            'detailRows' => false,
            'showTotalRow' => true,
            'groupBy' => new List<Object>{ new Map<String, Object>{ 'fieldPath' => 'NextStep' } },
            'displayCurrency' => display
        };
    }

    private static Map<String, Object> amountColumn(Map<String, Object> request) {
        return (Map<String, Object>) ((List<Object>) request.get('columns'))[1];
    }

    private static Map<String, Object> probabilityColumn(Map<String, Object> request) {
        return (Map<String, Object>) ((List<Object>) request.get('columns'))[2];
    }

    private static void assertClose(Decimal expected, Decimal actual, String message) {
        Assert.isNotNull(actual, message);
        Assert.isTrue(Math.abs(expected - actual) <= TOLERANCE, message + ': expected ' + expected + ', got ' + actual);
    }
}