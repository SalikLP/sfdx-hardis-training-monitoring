/**
 * Engine helpers for Data providers that build virtual rows (a map of field path to value): each helper gives a row
 * the engine's own keys and labels, so the provider's partial buckets merge with the standard query's under the same
 * keys (see `BoardDataProviderResult.Bucket`).
 *
 * - `bucketLabel`: the Bucket field bucket of a row (the bucket's key and label alike; null when the fallback
 *   excludes the row).
 * - `dateBucketKey` / `dateBucketLabel`: the date bucket of a Date or Datetime at a date granularity (Datetimes in the
 *   user's time zone, fiscal periods from the org's fiscal year settings).
 * - `referenceLabels`: record Id to the label the engine shows for it (the target's name field, else the Id).
 * - `matches` / `inScope`: a condition, or the request's whole Widget scope, against a row with `SOQL` semantics.
 *
 * Paths match row keys case-insensitively; a missing path reads as null. Amounts in a row are corporate currency.
 */
global inherited sharing class BoardDataProviderRows {
    private static final Set<String> DATE_GRANULARITIES = new Set<String>{
        'DAY',
        'CALENDAR_MONTH',
        'CALENDAR_QUARTER',
        'CALENDAR_YEAR',
        'FISCAL_QUARTER',
        'FISCAL_YEAR'
    };
    private static Organization fiscalSettings;

    private BoardDataProviderRequest request;
    /** Compiled lazily, once, for the request's Bucket fields. */
    private BoardQueryService.QueryScope scope;
    private Map<String, BoardBucketField> bucketFields = new Map<String, BoardBucketField>();

    /** Helpers for the request a provider received (its Widget scope and Bucket fields). */
    global BoardDataProviderRows(BoardDataProviderRequest request) {
        this.request = request == null ? new BoardDataProviderRequest() : request;
    }

    // ---------------------------------------------------------------------------------------------------------
    // Bucket fields and scope
    // ---------------------------------------------------------------------------------------------------------

    /**
     * The bucket of `row` in the request's Bucket field `bucketField` (the Widget's own, else the Board's; `bucket:<id>`, e.g. the request's
     * `groupByField`, or the bare id): the first matching rule's label, else the fallback label, or null when the
     * fallback excludes the row. The engine keys and labels a bucket by this label.
     */
    global String bucketLabel(String bucketField, Map<String, Object> row) {
        String id = BoardBucketField.referencedId(bucketField);
        if (id == null && bucketField != null) {
            id = bucketField.trim();
        }
        BoardBucketField compiled = bucketFields.get(id);
        if (compiled == null) {
            compiled = BoardBucketField.find(
                BoardQueryService.getList(request.query, 'bucketFields'),
                BoardQueryService.getList(request.query, 'boardBucketFields'),
                id
            );
            if (scope == null) {
                scope = new BoardQueryService.QueryScope(request.query);
            }
            scope.compileBucketRules(compiled);
            bucketFields.put(id, compiled);
        }
        return compiled.labelOf(normalize(row, compiled.paths()));
    }

    /** Whether `row` is inside the request's scope: every Board filter, Base filter and Record context condition. */
    global Boolean inScope(Map<String, Object> row) {
        List<BoardDataProviderRequest.Condition> conditions = new List<BoardDataProviderRequest.Condition>();
        conditions.addAll(request.filters);
        conditions.addAll(request.baseFilters);
        conditions.addAll(request.recordContext);
        for (BoardDataProviderRequest.Condition condition : conditions) {
            if (!matches(condition, row)) {
                return false;
            }
        }
        return true;
    }

    /**
     * Whether `row` satisfies `condition` (null matches every row) with `SOQL` semantics: case-insensitive text,
     * nulls only match `= null` / `!= value` / `NOT IN` / `EXCLUDES`, relative dates in the user's time zone.
     */
    global static Boolean matches(BoardDataProviderRequest.Condition condition, Map<String, Object> row) {
        if (condition == null) {
            return true;
        }
        List<String> paths = new List<String>();
        BoardCondition.Node node = toNode(condition, paths);
        return node.evaluate(normalize(row, paths));
    }

    /** The value of `path` in `row`, matching keys case-insensitively like `SOQL` paths (null when absent). */
    global static Object valueAt(Map<String, Object> row, String path) {
        if (row == null || path == null) {
            return null;
        }
        if (row.containsKey(path)) {
            return row.get(path);
        }
        for (String key : row.keySet()) {
            if (key != null && key.equalsIgnoreCase(path)) {
                return row.get(key);
            }
        }
        return null;
    }

    // ---------------------------------------------------------------------------------------------------------
    // Date buckets
    // ---------------------------------------------------------------------------------------------------------

    /**
     * The engine's date bucket key of `value` (Date or Datetime) at `granularity` (`DAY` when blank, `CALENDAR_MONTH`,
     * `CALENDAR_QUARTER`, `CALENDAR_YEAR`, `FISCAL_QUARTER`, `FISCAL_YEAR`): e.g. `2026-03-14`, `2026-03`, `2026-Q1`,
     * `2026`, `FY2026-Q2`, `FY2026`; null for an empty value ("(Blank)").
     */
    global static String dateBucketKey(Object value, String granularity) {
        return dateBucket(value, granularity)[0];
    }

    /** The engine's date bucket label of `value` at `granularity` (e.g. `Mar 2026`, `Q1 2026`); null when empty. */
    global static String dateBucketLabel(Object value, String granularity) {
        return dateBucket(value, granularity)[1];
    }

    /** `[key, label]` of the date bucket of `value` (Date, or Datetime in the user's time zone) at `granularity`. */
    public static List<String> dateBucket(Object value, String granularity) {
        String unit = String.isBlank(granularity) ? 'DAY' : granularity.trim().toUpperCase();
        if (!DATE_GRANULARITIES.contains(unit)) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Unsupported date granularity: ' + granularity,
                null,
                null
            );
        }
        if (value == null) {
            return new List<String>{ null, null };
        }
        if (!(value instanceof Date) && !(value instanceof Datetime)) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Date bucketing needs a Date or Datetime value, not: ' + value,
                null,
                null
            );
        }
        // `instanceof` doesn't tell Date and Datetime apart reliably; their JSON does (only a Datetime has a time part).
        Date day = JSON.serialize(value).contains('T') ? ((Datetime) value).date() : (Date) value;
        switch on unit {
            when 'DAY' {
                return periodBucket(unit, day, null, null);
            }
            when 'CALENDAR_MONTH' {
                return periodBucket(unit, null, day.year(), day.month());
            }
            when 'CALENDAR_QUARTER' {
                return periodBucket(unit, null, day.year(), (day.month() - 1) / 3 + 1);
            }
            when 'CALENDAR_YEAR' {
                return periodBucket(unit, null, day.year(), null);
            }
            when else {
                Organization settings = getFiscalSettings();
                Integer startMonth = settings.FiscalYearStartMonth == null ? 1 : settings.FiscalYearStartMonth;
                Integer startYear = day.month() >= startMonth ? day.year() : day.year() - 1;
                Integer fiscalYear = startMonth == 1 || settings.UsesStartDateAsFiscalYearName
                    ? startYear
                    : startYear + 1;
                Integer fiscalQuarter = Math.mod(day.month() - startMonth + 12, 12) / 3 + 1;
                return periodBucket(unit, null, fiscalYear, unit == 'FISCAL_QUARTER' ? fiscalQuarter : null);
            }
        }
    }

    /**
     * `[key, label]` of a date bucket at `granularity` (upper case) from a `day` (`DAY`) or a `year` and `period`
     * (month or quarter), as the `SOQL` date functions return them; `[null, null]` when empty.
     */
    public static List<String> periodBucket(String granularity, Date day, Integer year, Integer period) {
        if (granularity == 'DAY') {
            return day == null ? new List<String>{ null, null } : new List<String>{ String.valueOf(day), day.format() };
        }
        if (year == null) {
            return new List<String>{ null, null };
        }
        String yearText = String.valueOf(year);
        switch on granularity {
            when 'CALENDAR_MONTH' {
                return new List<String>{
                    yearText +
                    '-' +
                    String.valueOf(period).leftPad(2, '0'),
                    Datetime.newInstance(year, period, 1).format('MMM yyyy')
                };
            }
            when 'CALENDAR_QUARTER' {
                return new List<String>{ yearText + '-Q' + period, 'Q' + period + ' ' + yearText };
            }
            when 'CALENDAR_YEAR' {
                return new List<String>{ yearText, yearText };
            }
            when 'FISCAL_QUARTER' {
                return new List<String>{ 'FY' + yearText + '-Q' + period, 'Q' + period + ' FY' + yearText };
            }
            when else {
                return new List<String>{ 'FY' + yearText, 'FY' + yearText };
            }
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Reference labels
    // ---------------------------------------------------------------------------------------------------------

    /**
     * Record Id to the label the engine shows for it as a category or series value: the record's name field, else
     * (no access, no name, no record) the Id itself. Null ids are skipped; one query per object.
     */
    global static Map<Id, String> referenceLabels(Set<Id> recordIds) {
        Map<Id, String> labels = new Map<Id, String>();
        Map<Schema.SObjectType, Set<Id>> idsByType = new Map<Schema.SObjectType, Set<Id>>();
        for (Id recordId : recordIds == null ? new Set<Id>() : recordIds) {
            if (recordId == null) {
                continue;
            }
            labels.put(recordId, String.valueOf(recordId));
            Schema.SObjectType objectType = recordId.getSObjectType();
            if (!idsByType.containsKey(objectType)) {
                idsByType.put(objectType, new Set<Id>());
            }
            idsByType.get(objectType).add(recordId);
        }
        for (Schema.SObjectType objectType : idsByType.keySet()) {
            Schema.DescribeSObjectResult target = objectType.getDescribe();
            String nameField = target.isAccessible() ? BoardDescribe.readableNameField(target) : null;
            if (nameField == null) {
                continue;
            }
            Set<Id> ids = idsByType.get(objectType);
            List<SObject> records = Database.queryWithBinds(
                'SELECT Id, ' + nameField + ' FROM ' + target.getName() + ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            );
            for (SObject record : records) {
                Object name = record.get(nameField);
                if (name != null) {
                    labels.put(record.Id, String.valueOf(name));
                }
            }
        }
        return labels;
    }

    // ---------------------------------------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------------------------------------

    private static BoardCondition.Node toNode(BoardDataProviderRequest.Condition condition, List<String> paths) {
        if (condition.isGroup()) {
            List<BoardCondition.Node> children = new List<BoardCondition.Node>();
            for (BoardDataProviderRequest.Condition child : condition.children) {
                if (child != null) {
                    children.add(toNode(child, paths));
                }
            }
            return condition.logic.equalsIgnoreCase('OR')
                ? BoardCondition.anyOf(children)
                : BoardCondition.allOf(children);
        }
        paths.add(condition.path);
        return BoardCondition.field(
            condition.filterId,
            condition.path,
            condition.operator == null ? null : condition.operator.toUpperCase(),
            condition.values
        );
    }

    /** `row` re-keyed by the exact `paths` a condition reads (row keys match case-insensitively). */
    private static Map<String, Object> normalize(Map<String, Object> row, List<String> paths) {
        Map<String, Object> normalized = new Map<String, Object>();
        for (String path : paths) {
            normalized.put(path, valueAt(row, path));
        }
        return normalized;
    }

    /** Org fiscal year settings, used to bucket dates exactly like `SOQL` `FISCAL_*` date functions. */
    private static Organization getFiscalSettings() {
        if (fiscalSettings == null) {
            fiscalSettings = [
                SELECT FiscalYearStartMonth, UsesStartDateAsFiscalYearName
                FROM Organization
                WITH USER_MODE
                LIMIT 1
            ];
        }
        return fiscalSettings;
    }
}