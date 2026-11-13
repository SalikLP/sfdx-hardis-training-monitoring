/**
 * Converts currency amounts between ISO codes with the org's static `CurrencyType` rates.
 *
 * - One step: `amount ÷ rate[from] × rate[to]` (the corporate currency has rate 1), kept at `CONVERSION_SCALE`
 *   decimal places (half-even) so per-row conversions can be summed without drifting. No `convertCurrency()`: it
 *   only targets the running user's personal currency.
 * - Rates are read once per request (`forRequest`) in User Mode. Dated exchange rates are not used. Inactive
 *   currencies keep converting (records can still carry them); an unknown ISO code fails with `QUERY_ERROR`.
 * - Single-currency orgs: a no-op (`isMultiCurrency() == false`). `CurrencyType` and `CurrencyIsoCode` exist only
 *   in multi-currency orgs, so they are referenced dynamically.
 * - Display currency: every query request carries `displayCurrency` (default: the viewer's currency). Aggregates come
 *   back from SOQL (and from the cursor tier, via `toCorporate`) in the corporate currency; the `toDisplay` overloads
 *   convert SUM/AVG/MIN/MAX of currency fields to the Display currency and stamp its ISO code on the result. Counts,
 *   percentages and other values never convert and carry no ISO code. Single-currency orgs: the org currency.
 * - Table: currency columns carry the Display currency (`stampTableColumns`); each row's currency cells are converted
 *   from the record's own `CurrencyIsoCode` (`rowToDisplay`) and the whole-scope Total row from corporate.
 * - Config currency: the request's `configCurrency` (default: corporate), the currency Admin-entered amounts are
 *   written in. Base filter amounts on currency fields compile to ISO literals in it (`configAmountBound`); Metric
 *   thresholds (`thresholdAmounts`) come back converted to the Display currency (`configToDisplay`).
 * - Amount range filters: end-user bounds on currency fields are typed in the Display currency and emitted as
 *   validated ISO literals (`displayAmountBound`), never as a currency `HAVING`.
 */
public with sharing class BoardCurrencyConverter {
    @TestVisible
    private static final Integer CONVERSION_SCALE = 10;
    private static final String ISO_CODE_FIELD = 'CurrencyIsoCode';
    private static final String DISPLAY_CURRENCY_KEY = 'displayCurrency';
    private static final String CONFIG_CURRENCY_KEY = 'configCurrency';
    private static final String THRESHOLD_AMOUNTS_KEY = 'thresholdAmounts';
    private static final String GAUGE_AMOUNTS_KEY = 'gaugeAmounts';
    /** Shape of an ISO code that may be inlined into `SOQL` as a currency literal. */
    private static final Pattern ISO_CODE_PATTERN = Pattern.compile('^[A-Z]{3}$');
    /** Aggregates whose result is an amount in the value field's currency (a currency Formula measure: `CURRENCY`). */
    private static final Set<String> CONVERTED_AGGREGATES = new Set<String>{
        'SUM',
        'AVG',
        'MIN',
        'MAX',
        BoardAveragePerRecord.AGGREGATE_FUNCTION,
        BoardFormulaMeasures.FORMULA
    };
    @TestVisible
    private static BoardCurrencyConverter requestConverter;

    private final Boolean multiCurrency;
    private final String corporateIsoCode;
    /** Upper-case ISO code → conversion rate against the corporate currency. */
    private final Map<String, Decimal> ratesByIsoCode = new Map<String, Decimal>();
    /** Upper-case ISO codes of the active currencies. */
    private final Set<String> activeIsoCodes = new Set<String>();

    /** One `CurrencyType` rate: units of `isoCode` per one unit of the corporate currency. */
    public class Rate {
        public String isoCode;
        public Decimal conversionRate;
        public Boolean isCorporate;
        /** Only active currencies can be a Display currency in an ISO literal; inactive ones still convert. */
        public Boolean isActive = true;

        public Rate(String isoCode, Decimal conversionRate, Boolean isCorporate) {
            this.isoCode = isoCode;
            this.conversionRate = conversionRate;
            this.isCorporate = isCorporate == true;
        }

        public Rate(String isoCode, Decimal conversionRate, Boolean isCorporate, Boolean isActive) {
            this(isoCode, conversionRate, isCorporate);
            this.isActive = isActive != false;
        }
    }

    /**
     * An amount as a `SOQL` ISO currency literal (`EUR5000`): `SOQL` compares it with each record's amount in that
     * record's currency. Its ISO code is checked against the active currencies before it is built, so it can be inlined.
     * In memory (Bucket rules, Measure conditions) it compares as `corporateAmount`, so rows must hold corporate amounts.
     */
    public class IsoAmount implements BoardCondition.InMemoryOperand {
        public final String isoCode;
        public final Decimal amount;
        /** `amount` in the corporate currency. */
        public final Decimal corporateAmount;

        private IsoAmount(String isoCode, Decimal amount, Decimal corporateAmount) {
            this.isoCode = isoCode;
            this.amount = amount;
            this.corporateAmount = corporateAmount;
        }

        public Object inMemoryValue() {
            return corporateAmount;
        }

        public String toSoql() {
            return isoCode + amount.toPlainString();
        }
    }

    /** What a Config editor needs to offer currencies: hidden entirely in single-currency orgs. */
    public class CurrencyOptions {
        @AuraEnabled
        public Boolean multiCurrency = false;
        @AuraEnabled
        public String corporateIsoCode;
        /** Active ISO codes, sorted. */
        @AuraEnabled
        public List<String> isoCodes = new List<String>();
    }

    /** The org's currency setup for the Config currency setting (and its single-currency hiding). */
    @AuraEnabled(cacheable=true)
    public static CurrencyOptions getCurrencyOptions() {
        try {
            BoardCurrencyConverter converter = forRequest();
            CurrencyOptions options = new CurrencyOptions();
            options.multiCurrency = converter.isMultiCurrency();
            options.corporateIsoCode = converter.getCorporateIsoCode();
            if (options.multiCurrency) {
                for (
                    SObject row : Database.query(
                        'SELECT IsoCode FROM CurrencyType WHERE IsActive = true ORDER BY IsoCode',
                        AccessLevel.USER_MODE
                    )
                ) {
                    options.isoCodes.add((String) row.get('IsoCode'));
                }
            }
            return options;
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    private BoardCurrencyConverter(Boolean multiCurrency, List<Rate> rates) {
        this.multiCurrency = multiCurrency;
        String corporate;
        for (Rate rate : rates) {
            if (String.isBlank(rate.isoCode) || rate.conversionRate == null || rate.conversionRate == 0) {
                continue;
            }
            ratesByIsoCode.put(rate.isoCode.toUpperCase(), rate.conversionRate);
            if (rate.isActive) {
                activeIsoCodes.add(rate.isoCode.toUpperCase());
            }
            if (rate.isCorporate) {
                corporate = rate.isoCode.toUpperCase();
            }
        }
        this.corporateIsoCode = corporate;
    }

    /** The converter for this request: the org's `CurrencyType` rates, read once and cached for the transaction. */
    public static BoardCurrencyConverter forRequest() {
        if (requestConverter == null) {
            requestConverter = UserInfo.isMultiCurrencyOrganization() ? fromRates(loadOrgRates()) : singleCurrency();
        }
        return requestConverter;
    }

    /** A multi-currency converter over an in-memory rate table (one entry flagged corporate). */
    @TestVisible
    private static BoardCurrencyConverter fromRates(List<Rate> rates) {
        return new BoardCurrencyConverter(true, rates);
    }

    /** The no-op converter of a single-currency org. */
    @TestVisible
    private static BoardCurrencyConverter singleCurrency() {
        return new BoardCurrencyConverter(false, new List<Rate>());
    }

    private static List<Rate> loadOrgRates() {
        List<Rate> rates = new List<Rate>();
        for (
            SObject row : Database.query(
                'SELECT IsoCode, ConversionRate, IsCorporate, IsActive FROM CurrencyType',
                AccessLevel.USER_MODE
            )
        ) {
            rates.add(
                new Rate(
                    (String) row.get('IsoCode'),
                    (Decimal) row.get('ConversionRate'),
                    (Boolean) row.get('IsCorporate'),
                    (Boolean) row.get('IsActive')
                )
            );
        }
        return rates;
    }

    public Boolean isMultiCurrency() {
        return multiCurrency;
    }

    /** The org's corporate ISO code (null in single-currency orgs). */
    public String getCorporateIsoCode() {
        return corporateIsoCode;
    }

    /**
     * `CurrencyIsoCode` path of the record that owns a currency value at `valuePath` (`Amount` → `CurrencyIsoCode`,
     * `Account.AnnualRevenue` → `Account.CurrencyIsoCode`). Null when nothing converts: single-currency orgs, no value
     * field, or a non-currency value.
     */
    public String isoCodePath(String valuePath, Schema.DisplayType valueType) {
        if (!multiCurrency || String.isBlank(valuePath) || valueType != Schema.DisplayType.CURRENCY) {
            return null;
        }
        Integer lastDot = valuePath.lastIndexOf('.');
        return lastDot < 0 ? ISO_CODE_FIELD : valuePath.substring(0, lastDot + 1) + ISO_CODE_FIELD;
    }

    /** Converts a record amount in `recordIsoCode` to the corporate currency. */
    public Decimal toCorporate(Decimal amount, String recordIsoCode) {
        return convert(amount, recordIsoCode, corporateIsoCode);
    }

    /** Converts `amount` from one ISO code to another in one step: `amount ÷ rate[from] × rate[to]`. */
    public Decimal convert(Decimal amount, String fromIsoCode, String toIsoCode) {
        if (!multiCurrency || amount == null) {
            return amount;
        }
        Decimal fromRate = rateOf(fromIsoCode);
        Decimal toRate = rateOf(toIsoCode);
        if (fromIsoCode.equalsIgnoreCase(toIsoCode)) {
            return amount;
        }
        return (amount * toRate).divide(fromRate, CONVERSION_SCALE, System.RoundingMode.HALF_EVEN);
    }

    /**
     * The request's Display currency (`displayCurrency`, default: the viewer's currency), validated against the
     * org's currencies. Single-currency orgs: always the org currency.
     */
    public String displayIsoCode(Map<String, Object> request) {
        if (!multiCurrency) {
            return UserInfo.getDefaultCurrency();
        }
        Object requested = request == null ? null : request.get(DISPLAY_CURRENCY_KEY);
        String isoCode = requested == null || String.isBlank(String.valueOf(requested))
            ? UserInfo.getDefaultCurrency()
            : String.valueOf(requested).trim().toUpperCase();
        rateOf(isoCode);
        return isoCode;
    }

    /**
     * The request's Config currency (`configCurrency`, default: the corporate currency), validated against the org's
     * currencies. Single-currency orgs: null (amounts are plain numbers in the org currency).
     */
    public String configIsoCode(Map<String, Object> request) {
        if (!multiCurrency) {
            return null;
        }
        Object requested = request == null ? null : request.get(CONFIG_CURRENCY_KEY);
        String isoCode = requested == null || String.isBlank(String.valueOf(requested))
            ? corporateIsoCode
            : String.valueOf(requested).trim().toUpperCase();
        rateOf(isoCode);
        return isoCode;
    }

    /**
     * The Admin amounts under `key` in the request (written in its Config currency) converted to `displayIsoCode`, one
     * per entry; null entries (and non-numbers) stay null. A null `displayIsoCode` (the value they compare with is not
     * an amount) or a single-currency org returns them as entered. Null when the request has no such list.
     */
    public List<Decimal> configToDisplay(Map<String, Object> request, String key, String displayIsoCode) {
        Object raw = request == null ? null : request.get(key);
        if (!(raw instanceof List<Object>)) {
            return null;
        }
        Boolean converts = multiCurrency && displayIsoCode != null;
        String fromIsoCode = converts ? configIsoCode(request) : null;
        List<Decimal> amounts = new List<Decimal>();
        for (Object item : (List<Object>) raw) {
            Decimal amount = BoardQueryService.toDecimalOrNull(item);
            amounts.add(converts && amount != null ? convert(amount, fromIsoCode, displayIsoCode) : amount);
        }
        return amounts;
    }

    /**
     * Bound of an end-user amount range on a currency field, typed in the request's Display currency: an `IsoAmount`
     * (`EUR5000`) in multi-currency orgs, so `SOQL` converts it per record; the bare number in single-currency orgs.
     * The Display currency must be an active currency. Never used in `HAVING` (an ISO literal there throws, and a bare
     * number there is corporate).
     */
    public Object displayAmountBound(Decimal amount, Map<String, Object> request) {
        if (!multiCurrency || amount == null) {
            return amount;
        }
        return validatedIsoAmount(displayIsoCode(request), amount);
    }

    /**
     * Amount of a Base filter on a currency field, written in the request's Config currency: an `IsoAmount`
     * (`EUR5000`) in multi-currency orgs, so `SOQL` converts it per record; the bare number in single-currency orgs.
     * The Config currency must be an active currency. Never used in `HAVING`.
     */
    public Object configAmountBound(Decimal amount, Map<String, Object> request) {
        if (!multiCurrency || amount == null) {
            return amount;
        }
        return validatedIsoAmount(configIsoCode(request), amount);
    }

    private IsoAmount validatedIsoAmount(String isoCode, Decimal amount) {
        if (!activeIsoCodes.contains(isoCode) || !ISO_CODE_PATTERN.matcher(isoCode).matches()) {
            throw BoardErrors.error(BoardErrors.QUERY_ERROR, 'Inactive currency: ' + isoCode, null, null);
        }
        return new IsoAmount(isoCode, amount, convert(amount, isoCode, corporateIsoCode));
    }

    /**
     * ISO code of an aggregate's value: the request's Display currency for SUM/AVG/MIN/MAX of a currency field
     * (`valueType` is a `Schema.DisplayType` name); null for anything that is not an amount (counts, percentages).
     */
    public String isoCodeFor(String aggregateFunction, String valueType, Map<String, Object> request) {
        Boolean amount =
            valueType == Schema.DisplayType.CURRENCY.name() &&
            aggregateFunction != null &&
            CONVERTED_AGGREGATES.contains(aggregateFunction.trim().toUpperCase());
        return amount ? displayIsoCode(request) : null;
    }

    /** Converts a corporate amount to `displayIsoCode`; unchanged when the ISO code is null (not an amount). */
    public Object fromCorporate(Object amount, String displayIsoCode) {
        if (!multiCurrency || amount == null || displayIsoCode == null) {
            return amount;
        }
        return convert(Decimal.valueOf(String.valueOf(amount)), corporateIsoCode, displayIsoCode);
    }

    /**
     * Metric result: converts the value (or the first cursor chunk), stamps `currencyIsoCode`, and returns the request's
     * Admin amounts (Config currency) in the Display currency when the value is an amount (`configAmountsToDisplay`).
     */
    public BoardQueryService.MetricResult toDisplay(
        BoardQueryService.MetricResult result,
        Map<String, Object> request
    ) {
        result.currencyIsoCode = isoCodeFor(result.aggregateFunction, result.valueType, request);
        result.value = fromCorporate(result.value, result.currencyIsoCode);
        toDisplay(result.chunk, result.currencyIsoCode);
        return configAmountsToDisplay(result, request);
    }

    /**
     * The request's Metric Admin amounts, written in the Config currency, in the result's currency (`currencyIsoCode`;
     * as entered when null): `thresholdAmounts` (Thresholds, absolute Gauge bands) and `gaugeAmounts` (the Gauge's
     * static minimum and maximum).
     */
    public BoardQueryService.MetricResult configAmountsToDisplay(
        BoardQueryService.MetricResult result,
        Map<String, Object> request
    ) {
        result.thresholdAmounts = configToDisplay(request, THRESHOLD_AMOUNTS_KEY, result.currencyIsoCode);
        result.gaugeAmounts = configToDisplay(request, GAUGE_AMOUNTS_KEY, result.currencyIsoCode);
        return result;
    }

    /**
     * Cursor chunk: converts each bucket's `sum`, `min` and `max` to `displayIsoCode` (counts stay), so the client's
     * merged SUM, AVG (`sum ÷ count`), MIN and MAX are in the Display currency. Null ISO code: unchanged.
     */
    public BoardQueryService.AggregateChunk toDisplay(BoardQueryService.AggregateChunk chunk, String displayIsoCode) {
        if (chunk == null || chunk.buckets == null || displayIsoCode == null) {
            return chunk;
        }
        for (BoardChartEngine.Partial bucket : chunk.buckets) {
            bucket.sum = (Decimal) fromCorporate(bucket.sum, displayIsoCode);
            bucket.min = (Decimal) fromCorporate(bucket.min, displayIsoCode);
            bucket.max = (Decimal) fromCorporate(bucket.max, displayIsoCode);
        }
        return chunk;
    }

    /** Shaped chart: stamps `currencyIsoCodes` (one per Measure) and converts the points of currency Measures. */
    public BoardChartQuery.ChartResult toDisplay(BoardChartQuery.ChartResult result, Map<String, Object> request) {
        result.currencyIsoCodes = new List<String>();
        for (Integer i = 0; i < result.aggregateFunctions.size(); i++) {
            String valueType = i < result.valueTypes.size() ? result.valueTypes[i] : null;
            result.currencyIsoCodes.add(isoCodeFor(result.aggregateFunctions[i], valueType, request));
        }
        for (BoardChartEngine.ChartPoint point : result.points) {
            Integer index = point.measureIndex;
            String isoCode = index == null ||
                index >= result.currencyIsoCodes.size()
                ? null
                : result.currencyIsoCodes[index];
            point.value = (Decimal) fromCorporate(point.value, isoCode);
        }
        return result;
    }

    /** Table columns: stamps the request's Display currency on every currency column (`currencyIsoCode`). */
    public List<BoardQueryService.TableColumn> stampTableColumns(
        List<BoardQueryService.TableColumn> columns,
        Map<String, Object> request
    ) {
        for (BoardQueryService.TableColumn column : columns) {
            column.currencyIsoCode = column.dataType == Schema.DisplayType.CURRENCY.name()
                ? displayIsoCode(request)
                : null;
        }
        return columns;
    }

    /** `CurrencyIsoCode` path to select with a Table column so its cells can convert; null when nothing converts. */
    public String tableIsoCodePath(BoardQueryService.TableColumn column) {
        return column.dataType == Schema.DisplayType.CURRENCY.name()
            ? isoCodePath(column.fieldPath, Schema.DisplayType.CURRENCY)
            : null;
    }

    /**
     * Table row: converts every currency field of the queried `record` (and of its parent records) from that
     * record's own `CurrencyIsoCode` to `displayIsoCode`, in the row's flattened `values`. Only the lower-case
     * `paths` convert (null: every currency field). A record whose `CurrencyIsoCode` was not selected is left alone.
     * Single-currency orgs: unchanged.
     */
    public BoardQueryService.TableRow rowToDisplay(
        BoardQueryService.TableRow row,
        SObject record,
        String displayIsoCode,
        Set<String> paths
    ) {
        if (multiCurrency && displayIsoCode != null) {
            recordToDisplay(record, '', row.values, new CellTarget(displayIsoCode, paths));
        }
        return row;
    }

    /** Where `recordToDisplay` converts to, and which flattened paths it may convert (null: all). */
    private class CellTarget {
        public final String displayIsoCode;
        public final Set<String> paths;

        CellTarget(String displayIsoCode, Set<String> paths) {
            this.displayIsoCode = displayIsoCode;
            this.paths = paths;
        }
    }

    /**
     * Whole-scope Total row: SOQL summaries come back in the corporate currency; those of a currency column (one
     * with a `currencyIsoCode`) are converted to it.
     */
    public List<BoardTableEngine.ColumnTotal> totalsToDisplay(
        List<BoardTableEngine.ColumnTotal> totals,
        List<BoardQueryService.TableColumn> columns
    ) {
        if (totals == null) {
            return totals;
        }
        Map<String, String> isoCodeByColumnId = new Map<String, String>();
        for (BoardQueryService.TableColumn column : columns) {
            isoCodeByColumnId.put(column.id, column.currencyIsoCode);
        }
        for (BoardTableEngine.ColumnTotal total : totals) {
            String isoCode = isoCodeByColumnId.get(total.columnId);
            for (BoardTableEngine.SummaryValue summary : total.summaries) {
                summary.value = (Decimal) fromCorporate(summary.value, isoCode);
            }
        }
        return totals;
    }

    private void recordToDisplay(SObject record, String prefix, Map<String, Object> values, CellTarget target) {
        Map<String, Object> populated = record.getPopulatedFieldsAsMap();
        String recordIsoCode;
        for (String key : populated.keySet()) {
            if (key.equalsIgnoreCase(ISO_CODE_FIELD)) {
                recordIsoCode = (String) populated.get(key);
            }
        }
        for (String key : populated.keySet()) {
            Object value = populated.get(key);
            if (value instanceof SObject) {
                recordToDisplay((SObject) value, prefix + key + '.', values, target);
            } else if (
                recordIsoCode != null &&
                value instanceof Decimal &&
                (target.paths == null || target.paths.contains((prefix + key).toLowerCase())) &&
                isCurrencyField(record.getSObjectType(), key)
            ) {
                values.put(prefix + key, convert((Decimal) value, recordIsoCode, target.displayIsoCode));
            }
        }
    }

    /** Field type lookups, cached per request (`Object.field` lower case → is a currency field). */
    private final Map<String, Boolean> currencyFieldCache = new Map<String, Boolean>();

    private Boolean isCurrencyField(Schema.SObjectType objectType, String fieldName) {
        String cacheKey = (String.valueOf(objectType) + '.' + fieldName).toLowerCase();
        Boolean cached = currencyFieldCache.get(cacheKey);
        if (cached == null) {
            Schema.SObjectField field = objectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields.getMap()
                .get(fieldName);
            cached = field != null && field.getDescribe().getType() == Schema.DisplayType.CURRENCY;
            currencyFieldCache.put(cacheKey, cached);
        }
        return cached;
    }

    private Decimal rateOf(String isoCode) {
        Decimal rate = String.isBlank(isoCode) ? null : ratesByIsoCode.get(isoCode.toUpperCase());
        if (rate == null) {
            throw BoardErrors.error(
                BoardErrors.QUERY_ERROR,
                'Unknown currency: ' + (String.isBlank(isoCode) ? '(none)' : isoCode),
                null,
                null
            );
        }
        return rate;
    }
}