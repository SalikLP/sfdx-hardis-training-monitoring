/**
 * Entry-point tests for the Display currency on the Table widget (currency/03): currency cells come back converted
 * record -> Display currency on the first page, later pages, grouped pages and Row limit pages; currency columns carry
 * the Display currency ISO code; the whole-scope Total row is converted; non-currency number cells never convert.
 *
 * The per-currency tests need a multi-currency org with at least two active currencies, discovered at runtime (no
 * hard-coded ISO codes or rates); they skip gracefully otherwise. Expected cell values are each record's own amount
 * ÷ rate[record currency] × rate[display currency].
 * Data: four Opportunities, amounts spread over the active currencies, each with a Probability (not converted).
 */
@IsTest
private class BoardCurrencyTableTest {
    private static final Decimal TOLERANCE = 0.01;
    private static final Integer RECORD_COUNT = 4;

    @TestSetup
    static void setup() {
        Map<String, Decimal> rates = activeRates();
        List<String> isoCodes = rates == null ? new List<String>{ null } : new List<String>(rates.keySet());
        Account account = new Account(Name = 'Table Currency');
        insert account;
        List<Decimal> amounts = new List<Decimal>{ 100, 250, 1000, 40 };
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < RECORD_COUNT; i++) {
            Opportunity opportunity = new Opportunity(
                Name = 'Table Currency ' + i,
                AccountId = account.Id,
                Amount = amounts[i],
                Probability = 10 + i,
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
    static void firstAndLaterPagesConvertCurrencyCellsPerRecord() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        Map<Id, Opportunity> records = storedRecords();
        for (String display : rates.keySet()) {
            BoardQueryService.TableResult first = BoardQueryService.queryTable(JSON.serialize(tableRequest(display)));

            Assert.areEqual(display, first.columns[1].currencyIsoCode, 'Currency column carries the Display currency');
            Assert.isNull(first.columns[2].currencyIsoCode, 'Percent column carries no ISO code');
            assertRowsConverted(first.rows, records, rates, display);

            // A later page read from the same cursor (the minimum page size covers every record, so read from 0).
            BoardQueryService.TablePage page = BoardQueryService.fetchTablePage(first.paginationCursor, 0, 10, display);
            assertRowsConverted(page.rows, records, rates, display);
        }
    }

    @IsTest
    static void rowLimitAndGroupedPagesConvertCurrencyCells() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        Map<Id, Opportunity> records = storedRecords();
        for (String display : rates.keySet()) {
            Map<String, Object> limited = tableRequest(display);
            limited.put('sortBy', 'Name');
            limited.put('rowLimit', RECORD_COUNT);
            assertRowsConverted(BoardQueryService.queryTable(JSON.serialize(limited)).rows, records, rates, display);

            Map<String, Object> grouped = tableRequest(display);
            grouped.put('pageSize', 10);
            grouped.put('groupBy', new List<Object>{ new Map<String, Object>{ 'fieldPath' => 'StageName' } });
            BoardQueryService.TableResult first = BoardQueryService.queryTable(JSON.serialize(grouped));
            assertRowsConverted(first.rows, records, rates, display);
            BoardQueryService.TablePage again = BoardQueryService.fetchGroupedTablePage(
                JSON.serialize(grouped),
                first.paginationCursor,
                0
            );
            assertRowsConverted(again.rows, records, rates, display);
        }
    }

    @IsTest
    static void totalRowOverACurrencyColumnIsInTheDisplayCurrency() {
        Map<String, Decimal> rates = activeRates();
        if (rates == null) {
            return;
        }
        Decimal corporateSum = (Decimal) [SELECT SUM(Amount) v FROM Opportunity][0].get('v');
        for (String display : rates.keySet()) {
            Map<String, Object> request = tableRequest(display);
            request.put('showTotalRow', true);
            List<Object> columns = (List<Object>) request.get('columns');
            ((Map<String, Object>) columns[1]).put('summaries', new List<Object>{ 'SUM' });

            BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

            Assert.areEqual('amount', result.totals[0].columnId);
            assertClose(
                corporateSum * rates.get(display),
                result.totals[0].summaries[0].value,
                'Total SUM in ' + display
            );
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Any org
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void singleCurrencyConverterReturnsCellsUnconvertedInTheOrgCurrency() {
        BoardCurrencyConverter.requestConverter = BoardCurrencyConverter.singleCurrency();
        Map<Id, Opportunity> records = storedRecords();

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(tableRequest(null)));

        Assert.areEqual(UserInfo.getDefaultCurrency(), result.columns[1].currencyIsoCode);
        Assert.areEqual(RECORD_COUNT, result.rows.size());
        for (BoardQueryService.TableRow row : result.rows) {
            Opportunity stored = records.get(row.id);
            Assert.areEqual(stored.Amount, (Decimal) row.values.get('Amount'));
            Assert.areEqual(stored.Probability, (Decimal) row.values.get('Probability'));
        }
        BoardQueryService.TablePage page = BoardQueryService.fetchTablePage(result.paginationCursor, 0, 10, null);
        Assert.areEqual(RECORD_COUNT, page.rows.size());
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** Every cell's Amount equals its record's amount converted to `display`; Probability is never converted. */
    private static void assertRowsConverted(
        List<BoardQueryService.TableRow> rows,
        Map<Id, Opportunity> records,
        Map<String, Decimal> rates,
        String display
    ) {
        Assert.areEqual(RECORD_COUNT, rows.size(), 'Every record in ' + display);
        for (BoardQueryService.TableRow row : rows) {
            Opportunity stored = records.get(row.id);
            String recordIso = (String) stored.get('CurrencyIsoCode');
            Decimal expected = stored.Amount / rates.get(recordIso) * rates.get(display);
            assertClose(expected, (Decimal) row.values.get('Amount'), recordIso + ' -> ' + display);
            Assert.areEqual(stored.Probability, (Decimal) row.values.get('Probability'), 'Probability unchanged');
        }
    }

    private static Map<Id, Opportunity> storedRecords() {
        String isoField = UserInfo.isMultiCurrencyOrganization() ? ', CurrencyIsoCode' : '';
        return new Map<Id, Opportunity>(
            (List<Opportunity>) Database.query('SELECT Id, Amount, Probability' + isoField + ' FROM Opportunity')
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

    private static void assertClose(Decimal expected, Decimal actual, String message) {
        Assert.isNotNull(actual, message);
        Assert.isTrue(Math.abs(expected - actual) <= TOLERANCE, message + ': expected ' + expected + ', got ' + actual);
    }
}