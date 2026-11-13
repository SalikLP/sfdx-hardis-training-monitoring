/**
 * User Mode runtime query service for Board data Widgets.
 *
 * Every request is a JSON document whose data scope (`objectApiName`, resolved Filter bindings in `filters`, and
 * Widget `baseFilters`) is compiled by the reusable `QueryScope` into a bind-safe `WHERE` clause. Queries, counts, and
 * cursors execute with `AccessLevel.USER_MODE` and `Security.stripInaccessible(AccessType.READABLE, ...)`. The one
 * statement without a bind map is the `SOSL` text search, whose `WHERE` scope inlines the typed bind values as
 * escaped literals (`searchLiteral`).
 *
 * Failures are thrown as `AuraHandledException`s whose message is a serialized `BoardErrorPayload`
 * (`{ category, message, filterId, fieldPath, retryable }`, see `BoardErrors`). Explicit bindings, base filters, and
 * value fields fail closed (`CONFIG_ERROR` / `ACCESS_ERROR`); convention bindings that cannot be resolved or are
 * ambiguous, and `TEXT` terms shorter than `minCharacters` (at least 2), are skipped and reported in
 * `ignoredFilterIds`.
 */
public with sharing class BoardQueryService {
    /** Max matching rows for a single-call SOQL aggregate (`SUM`, `AVG`, `COUNT_DISTINCT`). */
    @TestVisible
    private static Integer CURSOR_AGGREGATE_THRESHOLD = 49900;
    /**
     * Rows aggregated per `Database.Cursor` chunk call. Fetched rows count against the per-transaction query-row
     * limit, so each chunk is also capped by the remaining query-row budget (see `fetchChunk`).
     */
    @TestVisible
    private static Integer CURSOR_CHUNK_SIZE = 40000;
    /** Max rows per `Database.Cursor.fetch` call (platform cap: 2,000). */
    @TestVisible
    private static Integer CURSOR_FETCH_SIZE = 2000;
    /** Max matching rows for multi-call `Database.Cursor` chunked aggregation. */
    @TestVisible
    private static Integer CURSOR_MAX_ROWS = 200000;
    /**
     * Max group/series combinations returned by one Chart `GROUP BY` query. A capped result re-runs through the
     * `Database.Cursor` tier when it can (see `scanChart`).
     */
    @TestVisible
    private static Integer CHART_GROUP_LIMIT = 2000;

    private static final Integer MAX_PARENT_HOPS = 5;
    private static final Integer MAX_SEMI_JOINS = 2;
    /** Max `SELF` / `Child(ForeignKey)` targets of one `SOSL` text search (one `SOQL LIKE` query each). */
    private static final Integer MAX_SEARCH_TARGETS = 5;
    /** Server floor for `TEXT` terms (spec story 31); a filter's larger `minCharacters` raises it. */
    private static final Integer MIN_SEARCH_CHARACTERS = 2;
    /** Filter types resolved by the Step 2 `targetObjectApiName` convention. */
    private static final Set<String> STEP_TWO_TYPES = new Set<String>{ 'LOOKUP', 'USER', 'RECORD_CONTEXT' };

    private static final String MODE_SINGLE = 'SINGLE';
    private static final String MODE_CURSOR = 'CURSOR';
    private static final String IGNORE_BINDING = 'IGNORE';
    private static final String TOKEN_ME = 'ME';
    /** `USER` filter match mode that matches each picked user's Team (`BoardTeamResolver`). */
    private static final String MATCH_MODE_TEAM = 'usersAndTeam';
    /** Filter type of a number range (`BETWEEN` / `GTE` / `LTE` on a numeric field; currency: Display currency). */
    private static final String NUMBER_RANGE = 'NUMBER_RANGE';
    /** Filter type over a Bucket field's labels (`BoardBucketField.selection`). */
    private static final String BUCKET_FILTER = 'BUCKET';
    /** Where a Chart widget's Bucket field goes (`BucketChart`). */
    private static final String BUCKET_AS_CATEGORY = 'CATEGORY';
    private static final String BUCKET_AS_SERIES = 'SERIES';
    private static final String BUCKET_AS_PANEL = 'PANEL';

    private static final Set<String> AGGREGATE_FUNCTIONS = new Set<String>{
        'COUNT',
        'COUNT_DISTINCT',
        'SUM',
        'AVG',
        'MIN',
        'MAX',
        BoardAveragePerRecord.AGGREGATE_FUNCTION
    };
    private static final Set<String> DATE_GRANULARITIES = new Set<String>{
        'DAY',
        'CALENDAR_MONTH',
        'CALENDAR_QUARTER',
        'CALENDAR_YEAR',
        'FISCAL_QUARTER',
        'FISCAL_YEAR'
    };
    private static final Set<String> AUDIT_REFERENCE_FIELDS = new Set<String>{ 'createdbyid', 'lastmodifiedbyid' };
    private static final Set<Schema.DisplayType> DATE_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME
    };
    private static final Set<Schema.DisplayType> PICKLIST_FILTER_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.MULTIPICKLIST,
        Schema.DisplayType.STRING,
        Schema.DisplayType.BOOLEAN,
        Schema.DisplayType.COMBOBOX
    };
    private static final Set<Schema.DisplayType> TEXT_FILTER_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL,
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.COMBOBOX
    };
    private static final Set<Schema.DisplayType> ID_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.REFERENCE,
        Schema.DisplayType.ID
    };

    private static final Pattern SEMI_JOIN_PATTERN = Pattern.compile('^([A-Za-z0-9_]+)\\(([A-Za-z0-9_]+)\\)\\.(.+)$');
    /** `TEXT` `SOSL` child union target: `Child(ForeignKey)`. */
    private static final Pattern CHILD_TARGET_PATTERN = Pattern.compile('^([A-Za-z0-9_]+)\\(([A-Za-z0-9_]+)\\)$');
    private static final String SELF_TARGET = 'SELF';
    /** Max records one `SOSL` search returns across all `RETURNING` objects (platform cap). */
    @TestVisible
    private static Integer SEARCH_SOSL_LIMIT = 2000;
    /** Row cap of each synchronous `SOQL LIKE` leg of the hybrid search. */
    @TestVisible
    private static Integer SEARCH_LIKE_LIMIT = 500;
    /** Field types the hybrid search's `SOQL LIKE` leg scans (filterable, non-encrypted). */
    private static final Set<Schema.DisplayType> SEARCH_LIKE_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL
    };
    /** `SOSL` reserved characters escaped in the search term. */
    private static final Pattern SOSL_RESERVED_PATTERN = Pattern.compile('([?&|!{}\\[\\]()^~*:\\\\"\'+\\-])');
    /** A `QueryScope` bind reference (`:b0`, `:b12`) inside a compiled predicate. */
    private static final Pattern BIND_TOKEN_PATTERN = Pattern.compile(':(b\\d+)(?!\\d)');
    private static final Pattern ISO_DATE_PATTERN = Pattern.compile('^\\d{4}-\\d{2}-\\d{2}$');

    // Transaction-scoped describe caches (keys are lower-cased API names).
    private static final Map<String, Map<String, Schema.SObjectField>> RELATIONSHIP_INDEX_CACHE = new Map<String, Map<String, Schema.SObjectField>>();

    /**
     * Computes a Metric Widget aggregate.
     *
     * Request: `{ objectApiName, aggregateFunction, valueFieldApiName, filters[], baseFilters[], refreshToken }`.
     * - `COUNT` uses `Database.countQueryWithBinds`; ungrouped `MIN`/`MAX` use `ORDER BY field ASC/DESC LIMIT 1`.
     * - `SUM`, `AVG`, `COUNT_DISTINCT` run a single SOQL aggregate when the matching row count is
     *   `<= CURSOR_AGGREGATE_THRESHOLD`.
     * - `SUM`/`AVG` up to `CURSOR_MAX_ROWS` rows open a `Database.Cursor` and return the first chunk
     *   (`mode: 'CURSOR'`, `isComplete: false`); the caller continues with `fetchAggregateChunk`.
     * - Larger scopes (or `COUNT_DISTINCT` above the threshold, or non-selective queries) fail with `LIMIT_EXCEEDED`.
     * - Currency values are read in the corporate currency on every path (cursor rows and the MIN/MAX row are
     *   converted from each record's currency), then SUM/AVG/MIN/MAX of a currency field are returned in the
     *   request's `displayCurrency` with `currencyIsoCode` set (`BoardCurrencyConverter`).
     * - A `measures` list (Metric widget Measures list, see `BoardMetricQuery`) aggregates every Measure this way and
     *   returns the visible Measure's result plus one result per Measure in `measures`.
     */
    @AuraEnabled(cacheable=true)
    public static MetricResult queryMetric(String requestJson) {
        try {
            Map<String, Object> request = parseRequest(requestJson);
            if (BoardDataProviders.isNamed(request)) {
                return BoardCurrencyConverter.forRequest().toDisplay(BoardDataProviders.queryMetric(request), request);
            }
            QueryScope scope = new QueryScope(request);
            return BoardMetricQuery.run(scope, request);
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    /**
     * Fetches and aggregates the next `CURSOR_CHUNK_SIZE` rows of a cursor opened by a previous query call.
     *
     * Request: the original Metric request plus `{ cursor, offset }`. Each call returns only that chunk's partial
     * `{ sum, count, min, max }` bucket; the caller merges chunks until `isComplete`.
     */
    @AuraEnabled(cacheable=true)
    public static AggregateChunk fetchAggregateChunk(String requestJson) {
        try {
            Map<String, Object> request = parseRequest(requestJson);
            Schema.DescribeSObjectResult objectDescribe = BoardDescribe.requireReadableObject(
                getString(request, 'objectApiName')
            );
            if (BoardDataProviders.isNamed(request)) {
                return providerMetricChunk(request);
            }
            if (parseAggregateFunction(request) == BoardAveragePerRecord.AGGREGATE_FUNCTION) {
                return perRecordMetricChunk(objectDescribe, request);
            }
            ResolvedField valueField = resolveValueField(objectDescribe, getString(request, 'valueFieldApiName'));
            Integer offset = getInteger(request, 'offset');
            AggregateChunk chunk = fetchChunk(
                deserializeCursor(getString(request, 'cursor')),
                offset == null ? 0 : offset,
                valueField.path,
                currencyIsoPath(valueField)
            );
            // Converted to the Display currency like the first chunk.
            BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
            return converter.toDisplay(
                chunk,
                converter.isoCodeFor(parseAggregateFunction(request), valueField.type.name(), request)
            );
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Metric execution
    // ---------------------------------------------------------------------------------------------------------

    /** One Metric aggregate (`aggregateFunction`, `valueFieldApiName` of `request`) over a compiled scope. */
    public static MetricResult runMetric(QueryScope scope, Map<String, Object> request) {
        String aggregateFunction = parseAggregateFunction(request);
        MetricResult result = new MetricResult(aggregateFunction, scope);
        if (aggregateFunction == 'COUNT') {
            Integer totalRows = scope.countRows();
            result.value = totalRows;
            result.totalRows = totalRows;
            return result;
        }
        if (aggregateFunction == BoardAveragePerRecord.AGGREGATE_FUNCTION) {
            return runPerRecordMetric(scope, request, result);
        }

        ResolvedField valueField = resolveValueField(scope.objectDescribe, getString(request, 'valueFieldApiName'));
        requireAggregatable(aggregateFunction, valueField);
        result.valueType = valueField.type.name();

        String isoPath = currencyIsoPath(valueField);
        if (aggregateFunction == 'MIN' || aggregateFunction == 'MAX') {
            // ORDER BY a currency field sorts by corporate value; the winning row's own amount is then converted.
            String direction = aggregateFunction == 'MIN' ? ' ASC' : ' DESC';
            String soql = scope.buildSoql(
                valueField.path + (isoPath == null ? '' : ', ' + isoPath),
                new List<String>{ valueField.path + ' != null' },
                'ORDER BY ' + valueField.path + direction + ' LIMIT 1'
            );
            List<SObject> rows = scope.query(soql);
            result.value = rows.isEmpty() ? null : readCorporateValue(rows[0], valueField.path, isoPath);
            return result;
        }

        Integer totalRows = scope.countRows();
        result.totalRows = totalRows;
        if (totalRows <= CURSOR_AGGREGATE_THRESHOLD) {
            String soql = scope.buildSoql(aggregateFunction + '(' + valueField.path + ') v', null, '');
            List<SObject> rows = scope.query(soql);
            result.value = rows.isEmpty() ? null : ((AggregateResult) rows[0]).get('v');
            return result;
        }
        if (aggregateFunction == 'COUNT_DISTINCT' || totalRows > CURSOR_MAX_ROWS) {
            throw limitExceeded(totalRows);
        }

        String cursorSoql = scope.buildSoql(valueField.path + (isoPath == null ? '' : ', ' + isoPath), null, '');
        result.useCursor(openAggregateCursor(scope, cursorSoql, valueField.path, isoPath));
        return result;
    }

    private static String parseAggregateFunction(Map<String, Object> request) {
        String aggregateFunction = upper(getString(request, 'aggregateFunction'));
        if (!AGGREGATE_FUNCTIONS.contains(aggregateFunction)) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Unsupported aggregate function: ' + getString(request, 'aggregateFunction'),
                null,
                'aggregateFunction'
            );
        }
        return aggregateFunction;
    }

    // ---------------------------------------------------------------------------------------------------------
    // Average per record (`BoardAveragePerRecord`)
    // ---------------------------------------------------------------------------------------------------------

    /**
     * Metric Average per record: one `GROUP BY` per-record field query whose rows (one value per record) are averaged
     * in Apex; a scope beyond `CURSOR_AGGREGATE_THRESHOLD` rows, or more records than one query returns
     * (`CHART_GROUP_LIMIT`), opens a cursor ordered by the per-record field (chunks: `perRecordMetricChunk`).
     */
    private static MetricResult runPerRecordMetric(QueryScope scope, Map<String, Object> request, MetricResult result) {
        ChartMeasures measures = new ChartMeasures(scope.objectDescribe, new List<Object>{ request });
        result.valueType = measures.valueTypes[0];
        Integer totalRows = scope.countRows();
        result.totalRows = totalRows;
        if (totalRows <= CURSOR_AGGREGATE_THRESHOLD) {
            BoardChartEngine.Accumulator averages = new BoardChartEngine.Accumulator(1);
            if (!queryPerRecordGroup(scope, null, measures, new List<String>(), averages)) {
                result.value = averages.rows.isEmpty()
                    ? null
                    : averages.rows[0].value(0, BoardAveragePerRecord.AGGREGATE_FUNCTION);
                return result;
            }
        }
        if (totalRows > CURSOR_MAX_ROWS) {
            throw limitExceeded(totalRows);
        }
        Database.Cursor cursor = Database.getCursorWithBinds(
            scope.buildSoql(measures.cursorSelect(null), null, measures.cursorOrder()),
            scope.binds,
            AccessLevel.USER_MODE
        );
        result.useCursor(readPerRecordChunk(cursor, 0, measures));
        return result;
    }

    /**
     * Next cursor chunk of a Data provider Metric widget's standard leg (`fetchAggregateChunk`), in the Display
     * currency. That cursor reads the whole scope (`scanPartials`), so the chunk is read like the Chart cursor tier:
     * the request's Measure (its fields at the top level, as the Metric widget continues it) with its Measure condition
     * evaluated per record.
     */
    private static AggregateChunk providerMetricChunk(Map<String, Object> request) {
        Map<String, Object> measure = new Map<String, Object>();
        for (
            String key : new List<String>{ 'aggregateFunction', 'valueFieldApiName', 'perField', 'inner', 'condition' }
        ) {
            if (request.get(key) != null) {
                measure.put(key, request.get(key));
            }
        }
        // The Measure condition is compiled into a scope of its own, to evaluate it per record (as `scanChart`).
        QueryScope scope = new QueryScope(
            new Map<String, Object>{ 'objectApiName' => getString(request, 'objectApiName') }
        );
        ChartMeasures measures = new ChartMeasures(scope.objectDescribe, new List<Object>{ measure });
        measures.compileConditions(scope);
        BoardChartQuery.ChartResult result = new BoardChartQuery.ChartResult();
        result.accumulator = new BoardChartEngine.Accumulator(1);
        Integer offset = getInteger(request, 'offset');
        Integer start = offset == null ? 0 : Math.max(0, offset);
        scanChartChunk(deserializeCursor(getString(request, 'cursor')), start, null, measures, result);
        BoardChartEngine.Partial total = new BoardChartEngine.Partial();
        for (BoardChartEngine.GroupedRow row : result.accumulator.rows) {
            total.combine(row.partials[0]);
        }
        BoardChartEngine.Partial bucket = new BoardChartEngine.Partial();
        bucket.sum = total.sum;
        bucket.count = total.count;
        bucket.min = total.min;
        bucket.max = total.max;
        AggregateChunk chunk = new AggregateChunk();
        chunk.cursor = result.cursor;
        chunk.offset = start;
        chunk.nextOffset = result.nextOffset;
        chunk.totalRows = result.totalRows;
        chunk.isComplete = result.isComplete;
        chunk.buckets = new List<BoardChartEngine.Partial>{ bucket };
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        return converter.toDisplay(chunk, converter.isoCodeFor(measures.functions[0], measures.valueTypes[0], request));
    }

    /** Next Metric Average per record cursor chunk (`fetchAggregateChunk`), in the Display currency. */
    private static AggregateChunk perRecordMetricChunk(
        Schema.DescribeSObjectResult objectDescribe,
        Map<String, Object> request
    ) {
        ChartMeasures measures = new ChartMeasures(objectDescribe, new List<Object>{ request });
        AggregateChunk chunk = readPerRecordChunk(
            deserializeCursor(getString(request, 'cursor')),
            getInteger(request, 'offset'),
            measures
        );
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        return converter.toDisplay(
            chunk,
            converter.isoCodeFor(BoardAveragePerRecord.AGGREGATE_FUNCTION, measures.valueTypes[0], request)
        );
    }

    /**
     * One Metric Average per record cursor chunk as one bucket of record values (`sum` of them, `count` of records),
     * ending before the rows of its last record (see `BoardAveragePerRecord.completeRecords`).
     */
    private static AggregateChunk readPerRecordChunk(Database.Cursor cursor, Integer offset, ChartMeasures measures) {
        Integer start = Math.max(0, offset == null ? 0 : offset);
        CursorRows rows = readCursorRows(cursor, start);
        Integer readCount = measures.completeRecords(rows.records, rows.nextOffset >= rows.totalRows);
        BoardAveragePerRecord.RecordFold fold = new BoardAveragePerRecord.RecordFold(measures.inners);
        for (Integer i = 0; i < readCount; i++) {
            SObject record = rows.records[i];
            fold.add(null, null, null, null, measures.recordKey(record), measures.perRecordValues(record));
        }
        BoardChartEngine.Accumulator values = new BoardChartEngine.Accumulator(1);
        fold.putInto(values);
        BoardChartEngine.Partial bucket = new BoardChartEngine.Partial();
        if (!values.rows.isEmpty()) {
            BoardChartEngine.Partial partial = values.rows[0].partials[0];
            bucket.sum = partial.sum;
            bucket.count = partial.count;
            bucket.min = partial.min;
            bucket.max = partial.max;
        }
        AggregateChunk chunk = new AggregateChunk();
        chunk.cursor = JSON.serialize(cursor);
        chunk.offset = start;
        chunk.nextOffset = start + readCount;
        chunk.totalRows = rows.totalRows;
        chunk.isComplete = chunk.nextOffset >= rows.totalRows;
        chunk.buckets = new List<BoardChartEngine.Partial>{ bucket };
        return chunk;
    }

    /**
     * One Average per record query group (`groupMeasures` share one per-record field): `GROUP BY` category (+ series,
     * with a `grouping`) + per-record field, each row one record's value per Measure, added to `averages` (whose
     * partials then average them per category / series). Rows without a record are left out. True when the query
     * hit `CHART_GROUP_LIMIT`, so records may be missing.
     */
    private static Boolean queryPerRecordGroup(
        QueryScope scope,
        ChartGrouping grouping,
        ChartMeasures groupMeasures,
        List<String> predicates,
        BoardChartEngine.Accumulator averages
    ) {
        String perPath = groupMeasures.perRecordPath();
        List<String> allPredicates = new List<String>(predicates);
        allPredicates.add(perPath + ' != null');
        String selectClause = groupMeasures.aggregateSelect();
        String groupByClause = perPath;
        if (grouping != null) {
            selectClause = grouping.aggregateSelect() + ', ' + selectClause;
            groupByClause = grouping.groupByClause() + ', ' + perPath;
        }
        List<SObject> rows = scope.query(
            scope.buildSoql(selectClause, allPredicates, 'GROUP BY ' + groupByClause + ' LIMIT ' + CHART_GROUP_LIMIT)
        );
        List<String> none = new List<String>{ null, null };
        for (SObject row : rows) {
            AggregateResult aggregate = (AggregateResult) row;
            List<String> category = grouping == null ? none : grouping.groupBy.fromAggregate(aggregate);
            List<String> series = grouping == null ||
                grouping.stackBy == null
                ? none
                : grouping.stackBy.fromAggregate(aggregate);
            List<Object> values = new List<Object>();
            for (Integer i = 0; i < groupMeasures.size(); i++) {
                values.add(aggregate.get('v' + i));
            }
            List<String> panel = grouping == null ? none : grouping.panelOfAggregate(aggregate);
            averages.add(panel[0], panel[1], category[0], category[1], series[0], series[1], values);
        }
        return rows.size() >= CHART_GROUP_LIMIT;
    }

    /** Opens a User Mode `Database.Cursor` over `soql` and aggregates its first chunk. */
    private static AggregateChunk openAggregateCursor(QueryScope scope, String soql, String valuePath, String isoPath) {
        Database.Cursor cursor = Database.getCursorWithBinds(soql, scope.binds, AccessLevel.USER_MODE);
        return fetchChunk(cursor, 0, valuePath, isoPath);
    }

    /**
     * Aggregates one cursor chunk (`readCursorRows`) into one partial bucket. A non-null `isoPath` (currency value
     * fields in multi-currency orgs) converts each row to the corporate currency before it is added.
     */
    private static AggregateChunk fetchChunk(Database.Cursor cursor, Integer offset, String valuePath, String isoPath) {
        Integer start = Math.max(0, offset);
        CursorRows rows = readCursorRows(cursor, start);
        BoardChartEngine.Partial bucket = new BoardChartEngine.Partial();
        for (SObject row : rows.records) {
            bucket.add(readCorporateValue(row, valuePath, isoPath));
        }
        AggregateChunk chunk = new AggregateChunk();
        chunk.cursor = JSON.serialize(cursor);
        chunk.offset = start;
        chunk.nextOffset = rows.nextOffset;
        chunk.totalRows = rows.totalRows;
        chunk.isComplete = chunk.nextOffset >= rows.totalRows;
        chunk.buckets = new List<BoardChartEngine.Partial>{ bucket };
        return chunk;
    }

    private static List<SObject> fetchCursorRows(Database.Cursor cursor, Integer position, Integer count) {
        try {
            return cursor.fetch(position, count);
        } catch (System.TransientCursorException cursorError) {
            throw aggregationCursorExpired();
        } catch (System.FatalCursorException cursorError) {
            throw aggregationCursorExpired();
        }
    }

    private static Database.Cursor deserializeCursor(String cursorJson) {
        try {
            return (Database.Cursor) JSON.deserialize(cursorJson, Database.Cursor.class);
        } catch (Exception invalidCursor) {
            throw aggregationCursorExpired();
        }
    }

    private static BoardErrors.BoardException aggregationCursorExpired() {
        return BoardErrors.error(
            BoardErrors.QUERY_ERROR,
            'The aggregation cursor is no longer available. Retry to recalculate.',
            null,
            null,
            true
        );
    }

    private static ResolvedField resolveValueField(Schema.DescribeSObjectResult objectDescribe, String fieldApiName) {
        if (String.isBlank(fieldApiName)) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'A value field is required for this aggregate.',
                null,
                'valueFieldApiName'
            );
        }
        String fieldName = fieldApiName.trim();
        if (fieldName.contains('(')) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'The value field must be a field on ' +
                    objectDescribe.getName() +
                    ' or a parent path, not a child relationship: ' +
                    fieldName,
                null,
                fieldName
            );
        }
        // Direct field or 1–5 hop parent path (`Account.AnnualRevenue`); each hop is FLS-checked.
        return resolveFieldPath(objectDescribe, fieldName, null, fieldName);
    }

    private static void requireAggregatable(String aggregateFunction, ResolvedField valueField) {
        Boolean numeric = BoardDescribe.NUMERIC_TYPES.contains(valueField.type);
        Boolean supported =
            aggregateFunction == 'COUNT_DISTINCT' ||
            numeric ||
            ((aggregateFunction == 'MIN' || aggregateFunction == 'MAX') &&
            (DATE_TYPES.contains(valueField.type) || valueField.type == Schema.DisplayType.TIME));
        if (!supported) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                aggregateFunction + ' is not supported on ' + valueField.type.name() + ' field ' + valueField.path,
                null,
                valueField.path
            );
        }
    }

    /** `CurrencyIsoCode` path to select next to a currency value field in multi-currency orgs; otherwise null. */
    private static String currencyIsoPath(ResolvedField valueField) {
        return valueField == null ||
            valueField.type != Schema.DisplayType.CURRENCY
            ? null
            : BoardCurrencyConverter.forRequest().isoCodePath(valueField.path, valueField.type);
    }

    /** Value-field value of a queried row, converted from the record's currency to corporate when `isoPath` is set. */
    private static Object readCorporateValue(SObject row, String valuePath, String isoPath) {
        Object value = readPath(row, valuePath);
        if (isoPath == null || value == null) {
            return value;
        }
        return BoardCurrencyConverter.forRequest()
            .toCorporate(Decimal.valueOf(String.valueOf(value)), (String) readPath(row, isoPath));
    }

    private static BoardErrors.BoardException limitExceeded(Integer totalRows) {
        String spanned = totalRows == null ? 'too many' : totalRows.format();
        return BoardErrors.error(
            BoardErrors.LIMIT_EXCEEDED,
            'This view spans ' +
                spanned +
                ' records (beyond the limit for this calculation). Narrow the Date Range or add filters to view results.',
            null,
            null
        );
    }

    // ---------------------------------------------------------------------------------------------------------
    // Table entry points (execution lives in `BoardTableQuery`)
    // ---------------------------------------------------------------------------------------------------------

    /**
     * Opens a Table Widget `Database.PaginationCursor` and returns its first page.
     *
     * Request: `{ objectApiName, columns[], sortBy, sortDirection, pageSize, start, filters[],
     * baseFilters[], displayCurrency, refreshToken, widgetRefreshToken }`. Currency cells come back converted from
     * each record's currency to `displayCurrency`, and currency columns carry its `currencyIsoCode`. `columns[]` items are `TableColumnConfig` (`id`,
     * `fieldPath`, `linkToRecord`); paths are direct fields or 1-5 hop parent dot-paths and fail closed with
     * `ACCESS_ERROR` when unreadable. Ordering is `sortBy sortDirection NULLS LAST, Id ASC`. `start` (default 0)
     * lets the caller re-open an expired cursor and continue at the row it had reached. A request that still
     * carries `childRelationship` fails with `CONFIG_ERROR` (child rows were replaced by Row grouping).
     * With Row grouping (`groupBy`: up to two `{ fieldPath, sortDirection, dateGranularity, orderBy }`) records stream group-sorted and the result also
     * carries `groupField` and the first page's `groups` (see `BoardTableGrouping`); later pages come from
     * `fetchGroupedTablePage`.
     */
    @AuraEnabled(cacheable=true)
    public static TableResult queryTable(String requestJson) {
        try {
            Map<String, Object> request = parseRequest(requestJson);
            BoardTableQuery.rejectChildRelationship(request);
            QueryScope scope = new QueryScope(request);
            return BoardTableQuery.runTable(scope, request);
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    /**
     * Fetches the page at `start` from a cursor returned by `queryTable`, without recompiling the query.
     * An expired or invalid cursor fails with a retryable `QUERY_ERROR` whose `fieldPath` is `paginationCursor`.
     * Currency cells are converted to `displayCurrency` (the `queryTable` request's; blank = the viewer's currency).
     */
    @AuraEnabled(cacheable=true)
    public static TablePage fetchTablePage(
        String paginationCursor,
        Integer start,
        Integer pageSize,
        String displayCurrency
    ) {
        try {
            return BoardTableQuery.fetchPage(paginationCursor, start, pageSize, displayCurrency);
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    /**
     * Row grouping: fetches the page at `start` from a grouped Table's cursor (as `fetchTablePage`, page size from
     * the request) plus `groups`, the full-group record count of each group on the page. `requestJson` is the
     * `queryTable` request that opened the cursor (its scope and `groupBy` restrict the page-scoped `GROUP BY`).
     */
    @AuraEnabled(cacheable=true)
    public static TablePage fetchGroupedTablePage(String requestJson, String paginationCursor, Integer start) {
        try {
            Map<String, Object> request = parseRequest(requestJson);
            BoardTableQuery.rejectChildRelationship(request);
            QueryScope scope = new QueryScope(request);
            return BoardTableQuery.fetchGroupedPage(scope, request, paginationCursor, start);
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    /**
     * Detail rows off, cursor tier: the next chunk of a Table whose `queryTable` response carried an incomplete
     * `aggregateCursor`. Request: the `queryTable` request plus `{ cursor, offset, partialState }` from the previous
     * response. Only the final chunk carries the Group rows (see `BoardTableAggregateCursor`).
     */
    @AuraEnabled(cacheable=true)
    public static TableResult fetchTableAggregateChunk(String requestJson) {
        try {
            Map<String, Object> request = parseRequest(requestJson);
            if (getString(request, 'cursor') == null) {
                throw BoardErrors.error(
                    BoardErrors.QUERY_ERROR,
                    'The table calculation can no longer continue. Retry to recalculate.',
                    null,
                    null,
                    true
                );
            }
            BoardTableQuery.rejectChildRelationship(request);
            return BoardTableQuery.runTable(new QueryScope(request), request);
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Shared cursor tier (Table with Detail rows off: `BoardTableAggregateCursor`)
    // ---------------------------------------------------------------------------------------------------------

    /** Max matching rows for a single SOQL aggregate; above it aggregates read cursor chunks. */
    public static Integer cursorAggregateThreshold() {
        return CURSOR_AGGREGATE_THRESHOLD;
    }

    /** Max matching rows the cursor tier aggregates; above it the request is blocked. */
    public static Integer cursorMaxRows() {
        return CURSOR_MAX_ROWS;
    }

    /** Records the scope matches. */
    public static Integer countScopeRows(QueryScope scope) {
        return countScopeRows(scope, null);
    }

    /** A cursor serialized by a previous chunk call; an invalid one is the retryable expired-cursor error. */
    public static Database.Cursor restoreCursor(String cursorJson) {
        return deserializeCursor(cursorJson);
    }

    /**
     * The readable records of one cursor chunk at `offset`: up to `CURSOR_CHUNK_SIZE` rows in `CURSOR_FETCH_SIZE`
     * fetches, capped by the remaining query-row budget. Only cursor exceptions map to the retryable expired-cursor
     * error; anything else (fetch-size or bound errors) surfaces as a real failure. Every cursor tier reads through it.
     */
    public static CursorRows readCursorRows(Database.Cursor cursor, Integer offset) {
        Integer start = Math.max(0, offset == null ? 0 : offset);
        CursorRows chunk = new CursorRows();
        try {
            chunk.totalRows = cursor.getNumRecords();
        } catch (System.TransientCursorException cursorError) {
            throw aggregationCursorExpired();
        } catch (System.FatalCursorException cursorError) {
            throw aggregationCursorExpired();
        }
        Integer rowBudget = Limits.getLimitQueryRows() - Limits.getQueryRows();
        Integer fetchSize = Math.max(0, Math.min(Math.min(CURSOR_CHUNK_SIZE, rowBudget), chunk.totalRows - start));
        List<SObject> rows = new List<SObject>();
        for (Integer fetched = 0; fetched < fetchSize; fetched += CURSOR_FETCH_SIZE) {
            rows.addAll(fetchCursorRows(cursor, start + fetched, Math.min(CURSOR_FETCH_SIZE, fetchSize - fetched)));
        }
        chunk.records = Security.stripInaccessible(AccessType.READABLE, rows).getRecords();
        chunk.nextOffset = start + fetchSize;
        return chunk;
    }

    /** One cursor chunk: its readable records, the cursor's row count and the offset of the next chunk. */
    public class CursorRows {
        public List<SObject> records = new List<SObject>();
        public Integer totalRows;
        public Integer nextOffset;
    }

    private static Integer countScopeRows(QueryScope scope, List<String> extraPredicates) {
        return scope.countSoql(scope.buildSoql('COUNT()', extraPredicates, ''));
    }

    // ---------------------------------------------------------------------------------------------------------
    // Chart widget grouped scan (entry points in `BoardChartQuery`, shaping in `BoardChartEngine`)
    // ---------------------------------------------------------------------------------------------------------

    /**
     * Groups a Chart widget request (see `BoardChartQuery`) by its category field and optional series field
     * (`stackByField`) and aggregates every Measure per group into `result.accumulator`, unshaped. Two tiers:
     * one `GROUP BY` query with one column per Measure, or `Database.Cursor` chunks when a value Measure
     * spans more than `CURSOR_AGGREGATE_THRESHOLD` rows or the `GROUP BY` hits `CHART_GROUP_LIMIT` (never with a
     * `COUNT_DISTINCT` Measure, whose chunks cannot merge). A request carrying `cursor` continues that cursor at
     * `offset`, adding to the grouped rows of its `partialState`.
     *
     * Measure conditions (`measures[].condition`, see `BoardMeasureGroups`) narrow the scope per Measure: the SOQL tier
     * runs one `GROUP BY` query per Measure condition group and joins them on the category / series key; the cursor
     * tier reads the scope once and evaluates each Measure's condition per record.
     *
     * Average per record Measures (`BoardAveragePerRecord`) run their own query grouped by category / series + their
     * per-record field, averaged in Apex; their cursor is ordered by that field and each chunk ends at a record boundary.
     * Not available with a Bucket field.
     */
    public static BoardChartQuery.ChartResult scanChart(Map<String, Object> request) {
        String groupBucketId = BoardBucketField.referencedId(getString(request, 'groupByField'));
        String stackBucketId = BoardBucketField.referencedId(getString(request, 'stackByField'));
        String panelBucketId = BoardBucketField.referencedId(getString(request, 'panelField'));
        if (groupBucketId != null || stackBucketId != null || panelBucketId != null) {
            return scanBucketChart(request, groupBucketId, stackBucketId, panelBucketId);
        }
        String cursorJson = getString(request, 'cursor');
        QueryScope scope = cursorJson == null ? new QueryScope(request) : null;
        Schema.DescribeSObjectResult objectDescribe = scope == null
            ? BoardDescribe.requireReadableObject(getString(request, 'objectApiName'))
            : scope.objectDescribe;
        ChartGrouping grouping = new ChartGrouping(objectDescribe, request);
        ChartMeasures measures = new ChartMeasures(objectDescribe, getList(request, 'measures'));
        if (measures.size() > 1 && grouping.stackBy != null) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'A Chart widget shows several Measures or one Measure split by a series field, not both.',
                null,
                'stackByField'
            );
        }
        BoardChartQuery.ChartResult result = new BoardChartQuery.ChartResult();
        result.aggregateFunctions = measures.functions;
        result.valueTypes = measures.valueTypes;
        result.groupBy = grouping.groupBy.info();
        result.stackBy = grouping.stackBy == null ? null : grouping.stackBy.info();
        result.panelBy = grouping.panelBy == null ? null : grouping.panelBy.info();
        result.accumulator = new BoardChartEngine.Accumulator(measures.size());
        // A cursor chunk call compiles the Measure conditions into a scope of its own, to evaluate them per record.
        measures.compileConditions(
            scope != null
                ? scope
                : new QueryScope(new Map<String, Object>{ 'objectApiName' => objectDescribe.getName() })
        );
        if (scope == null) {
            result.accumulator.restore(getString(request, 'partialState'));
            Integer offset = getInteger(request, 'offset');
            scanChartChunk(deserializeCursor(cursorJson), offset == null ? 0 : offset, grouping, measures, result);
            return result;
        }
        result.appliedFilterIds = scope.appliedFilterIds;
        result.ignoredFilterIds = scope.ignoredFilterIds;

        List<String> extraPredicates = grouping.extraPredicates();
        String cursorSoql = scope.buildSoql(measures.cursorSelect(grouping), extraPredicates, measures.cursorOrder());
        if (measures.needsRowCount()) {
            result.totalRows = countScopeRows(scope, extraPredicates);
            if (result.totalRows > CURSOR_AGGREGATE_THRESHOLD) {
                if (measures.hasCountDistinct() || result.totalRows > CURSOR_MAX_ROWS) {
                    throw limitExceeded(result.totalRows);
                }
                openChartCursor(scope, cursorSoql, grouping, measures, result);
                return result;
            }
        }

        // One GROUP BY query per Measure condition group, joined on the category / series key.
        BoardMeasureGroups.MeasureJoin measureJoin = new BoardMeasureGroups.MeasureJoin(measures.functions);
        Boolean capped = false;
        for (Integer g = 0; g < measures.groups.groups.size(); g++) {
            BoardMeasureGroups.MeasureGroup measureGroup = measures.groups.groups[g];
            ChartMeasures groupMeasures = measures.subset(measureGroup.measureIndexes);
            if (measureGroup.perField != null) {
                capped = joinPerRecordGroup(scope, grouping, measures, g, extraPredicates, measureJoin) || capped;
                continue;
            }
            String soql = scope.buildSoql(
                grouping.aggregateSelect() + ', ' + groupMeasures.aggregateSelect(),
                measures.predicatesFor(g, extraPredicates),
                'GROUP BY ' +
                    grouping.groupByClause() +
                    ' ORDER BY ' +
                    groupMeasures.expressions[0] +
                    ' DESC NULLS LAST LIMIT ' +
                    CHART_GROUP_LIMIT
            );
            List<SObject> rows = scope.query(soql);
            for (SObject row : rows) {
                AggregateResult aggregate = (AggregateResult) row;
                List<String> category = grouping.groupBy.fromAggregate(aggregate);
                List<String> series = grouping.stackBy == null
                    ? new List<String>{ null, null }
                    : grouping.stackBy.fromAggregate(aggregate);
                List<Object> values = new List<Object>();
                for (Integer i = 0; i < groupMeasures.size(); i++) {
                    values.add(aggregate.get('v' + i));
                }
                List<String> panel = grouping.panelOfAggregate(aggregate);
                measureJoin.put(measureGroup, panel, category, series, values);
            }
            capped = capped || rows.size() >= CHART_GROUP_LIMIT;
        }
        measureJoin.putInto(result.accumulator);
        result.overallValues = referenceLineTotals(request, scope, extraPredicates, measures);
        result.panelQueryTotals = chartPanelTotals(request, scope, extraPredicates, measures, grouping.panelBy);
        Boolean mergeOther = !capped && !measures.hasCountDistinct() && needsMergedOther(request, measures, result);
        if (!capped && !mergeOther) {
            return result;
        }
        // Capped (smaller groups were dropped), or an "Other" that must merge partials: re-aggregate every group
        // through cursor chunks when possible.
        if (!measures.hasCountDistinct()) {
            if (result.totalRows == null) {
                result.totalRows = countScopeRows(scope, extraPredicates);
            }
            if (result.totalRows <= CURSOR_MAX_ROWS) {
                result.accumulator = new BoardChartEngine.Accumulator(measures.size());
                openChartCursor(scope, cursorSoql, grouping, measures, result);
                return result;
            }
        }
        if (mergeOther) {
            return result; // Too many rows to re-read: the final values stand and "Other" truncates.
        }
        result.hasMoreGroups = true;
        if (BoardChartQuery.usesShareOfTotal(request)) {
            result.grandTotals = chartGrandTotals(scope, extraPredicates, measures);
        }
        return result;
    }

    /**
     * True when the shaped chart needs an "Other" category or series for Measures that don't add up (AVG, MIN, MAX,
     * Average per record, or a Formula measure over any of them): only cursor partials merge into it
     * (`BoardChartEngine`), so the SOQL tier's final values re-run through the cursor tier. Never with a Panel field
     * (Panels sum their "Other") or on a date axis (always truncated).
     */
    private static Boolean needsMergedOther(
        Map<String, Object> request,
        ChartMeasures measures,
        BoardChartQuery.ChartResult result
    ) {
        if (result.panelBy != null) {
            return false;
        }
        Boolean additive = !BoardFormulaMeasures.hasFormulaMeasures(request);
        for (String aggregateFunction : measures.functions) {
            additive = additive && (aggregateFunction == 'COUNT' || aggregateFunction == 'SUM');
        }
        if (additive) {
            return false;
        }
        Boolean includeBlank = request.get('includeNullBucket') != false;
        Set<String> categoryValues = new Set<String>();
        Set<String> seriesValues = new Set<String>();
        for (BoardChartEngine.GroupedRow row : result.accumulator.rows) {
            if (row.categoryValue == null && !includeBlank) {
                continue;
            }
            categoryValues.add(row.categoryValue);
            seriesValues.add(row.seriesValue);
        }
        Boolean dateAxis = result.groupBy != null && result.groupBy.dateGranularity != null;
        Boolean otherCategory =
            'OTHER'.equalsIgnoreCase(getString(request, 'overflowMode')) &&
            !dateAxis &&
            categoryValues.size() > BoardChartQuery.maxCategories(request);
        Boolean otherSeries = result.stackBy != null && seriesValues.size() > BoardChartQuery.maxSeries(request);
        return otherCategory || otherSeries;
    }

    /** Reference line overall values: every Measure over the whole scope; null when no Measure is a Reference line. */
    private static List<Decimal> referenceLineTotals(
        Map<String, Object> request,
        QueryScope scope,
        List<String> predicates,
        ChartMeasures measures
    ) {
        return BoardChartQuery.usesReferenceLines(request) ? chartGrandTotals(scope, predicates, measures) : null;
    }

    /**
     * Panel totals (`BoardChartPanelTotals`): every Measure per Panel field value, in one query grouped by the Panel
     * field alone per Measure condition group, keyed by Panel key; null unless a Panel headline or Reference line
     * needs them.
     */
    private static Map<String, List<Decimal>> chartPanelTotals(
        Map<String, Object> request,
        QueryScope scope,
        List<String> extraPredicates,
        ChartMeasures measures,
        ChartDimension panelBy
    ) {
        if (panelBy == null || !BoardChartPanelTotals.isNeeded(request)) {
            return null;
        }
        Map<String, List<Decimal>> totals = new Map<String, List<Decimal>>();
        String panelSelect = String.join(panelBy.selectColumns(), ', ');
        String panelGroupBy = String.join(panelBy.expressions, ', ');
        for (Integer g = 0; g < measures.groups.groups.size(); g++) {
            BoardMeasureGroups.MeasureGroup measureGroup = measures.groups.groups[g];
            ChartMeasures groupMeasures = measures.subset(measureGroup.measureIndexes);
            List<String> predicates = measures.predicatesFor(g, extraPredicates);
            // Average per record: one row per Panel and record, averaged per Panel (records beyond the cap left out).
            String perPath = measureGroup.perField != null ? groupMeasures.perRecordPath() : null;
            if (perPath != null) {
                predicates = new List<String>(predicates);
                predicates.add(perPath + ' != null');
            }
            String soql = scope.buildSoql(
                panelSelect + ', ' + groupMeasures.aggregateSelect(),
                predicates,
                'GROUP BY ' + panelGroupBy + (perPath == null ? '' : ', ' + perPath) + ' LIMIT ' + CHART_GROUP_LIMIT
            );
            BoardChartEngine.Accumulator perPanel = new BoardChartEngine.Accumulator(groupMeasures.size());
            for (SObject row : scope.query(soql)) {
                AggregateResult aggregate = (AggregateResult) row;
                List<String> panel = panelBy.fromAggregate(aggregate);
                List<Object> values = new List<Object>();
                for (Integer i = 0; i < groupMeasures.size(); i++) {
                    values.add(aggregate.get('v' + i));
                }
                if (perPath != null) {
                    perPanel.add(panel[0], panel[1], null, null, null, null, values);
                } else {
                    perPanel.put(panel[0], panel[1], null, null, null, null, values);
                }
            }
            for (BoardChartEngine.GroupedRow row : perPanel.rows) {
                String panelKey = row.panelValue == null ? BoardChartEngine.BLANK_KEY : row.panelValue;
                List<Decimal> panelTotals = totals.get(panelKey);
                if (panelTotals == null) {
                    panelTotals = new List<Decimal>();
                    for (Integer i = 0; i < measures.size(); i++) {
                        panelTotals.add(null);
                    }
                    totals.put(panelKey, panelTotals);
                }
                for (Integer i = 0; i < groupMeasures.size(); i++) {
                    panelTotals[measureGroup.measureIndexes[i]] = row.value(i, groupMeasures.functions[i]);
                }
            }
        }
        return totals;
    }

    /**
     * SOQL tier of an Average per record group `groupIndex` of a Chart: its per-record query averaged per category /
     * series and put into `measureJoin`. True when the query was capped.
     */
    private static Boolean joinPerRecordGroup(
        QueryScope scope,
        ChartGrouping grouping,
        ChartMeasures measures,
        Integer groupIndex,
        List<String> extraPredicates,
        BoardMeasureGroups.MeasureJoin measureJoin
    ) {
        BoardMeasureGroups.MeasureGroup measureGroup = measures.groups.groups[groupIndex];
        ChartMeasures groupMeasures = measures.subset(measureGroup.measureIndexes);
        BoardChartEngine.Accumulator averages = new BoardChartEngine.Accumulator(groupMeasures.size());
        Boolean capped = queryPerRecordGroup(
            scope,
            grouping,
            groupMeasures,
            measures.predicatesFor(groupIndex, extraPredicates),
            averages
        );
        for (BoardChartEngine.GroupedRow row : averages.rows) {
            List<Object> values = new List<Object>();
            for (Integer i = 0; i < groupMeasures.size(); i++) {
                values.add(row.value(i, BoardAveragePerRecord.AGGREGATE_FUNCTION));
            }
            measureJoin.put(
                measureGroup,
                new List<String>{ row.panelValue, row.panelLabel },
                new List<String>{ row.categoryValue, row.categoryLabel },
                new List<String>{ row.seriesValue, row.seriesLabel },
                values
            );
        }
        return capped;
    }

    /**
     * Share of total denominators of a capped result: every Measure over the whole scope, in one ungrouped query per
     * Measure condition group.
     */
    /** The Panel field must differ from the Group by and series fields (a duplicate grouping fails in SOQL). */
    private static void requirePanelDistinct(String panelPath, String groupPath, String stackPath) {
        String panel = panelPath.deleteWhitespace().toLowerCase();
        Boolean isGroup = groupPath != null && panel == groupPath.deleteWhitespace().toLowerCase();
        Boolean isStack = stackPath != null && panel == stackPath.deleteWhitespace().toLowerCase();
        if (isGroup || isStack) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'The Panel field must differ from the Group by and Stack by fields.',
                null,
                'panelField'
            );
        }
    }

    private static List<Decimal> chartGrandTotals(
        QueryScope scope,
        List<String> extraPredicates,
        ChartMeasures measures
    ) {
        List<Decimal> totals = new List<Decimal>();
        for (Integer i = 0; i < measures.size(); i++) {
            totals.add(null);
        }
        for (Integer g = 0; g < measures.groups.groups.size(); g++) {
            BoardMeasureGroups.MeasureGroup measureGroup = measures.groups.groups[g];
            ChartMeasures groupMeasures = measures.subset(measureGroup.measureIndexes);
            if (measureGroup.perField != null) {
                // Average per record over the whole scope; blank when there are more records than one query returns.
                BoardChartEngine.Accumulator averages = new BoardChartEngine.Accumulator(groupMeasures.size());
                Boolean capped = queryPerRecordGroup(
                    scope,
                    null,
                    groupMeasures,
                    measures.predicatesFor(g, extraPredicates),
                    averages
                );
                for (Integer i = 0; i < groupMeasures.size() && !capped && !averages.rows.isEmpty(); i++) {
                    totals[measureGroup.measureIndexes[i]] = averages.rows[0]
                        .value(i, BoardAveragePerRecord.AGGREGATE_FUNCTION);
                }
                continue;
            }
            AggregateResult total = (AggregateResult) scope.query(
                scope.buildSoql(groupMeasures.aggregateSelect(), measures.predicatesFor(g, extraPredicates), '')
            )[0];
            for (Integer i = 0; i < groupMeasures.size(); i++) {
                Object value = total.get('v' + i);
                totals[measureGroup.measureIndexes[i]] = value == null ? null : Decimal.valueOf(String.valueOf(value));
            }
        }
        return totals;
    }

    /**
     * Standard leg of a Data provider Widget (`BoardDataProviders`): the request's rows grouped like `scanChart`
     * (one ungrouped row without a `groupByField`), each Measure as a mergeable `{ sum, count, min, max }` partial in
     * `result.accumulator`, from one SOQL query. With `runQuery` false only the header (groups, Measures, applied and
     * ignored filter ids) is returned. Scopes beyond `CURSOR_AGGREGATE_THRESHOLD` rows fail with `LIMIT_EXCEEDED`.
     */
    public static BoardChartQuery.ChartResult scanPartials(
        QueryScope scope,
        Map<String, Object> request,
        Boolean runQuery
    ) {
        return scanPartials(scope, request, runQuery, false);
    }

    /**
     * `scanPartials`, and with `allowCursor` a scope beyond `CURSOR_AGGREGATE_THRESHOLD` (up to `CURSOR_MAX_ROWS`)
     * opens a `Database.Cursor` and returns its first chunk (`mode: 'CURSOR'`), continued like `scanChart` (Chart
     * widget: `fetchChartChunk`) or `fetchAggregateChunk` (Metric widget, ungrouped).
     */
    public static BoardChartQuery.ChartResult scanPartials(
        QueryScope scope,
        Map<String, Object> request,
        Boolean runQuery,
        Boolean allowCursor
    ) {
        String groupBucketId = BoardBucketField.referencedId(getString(request, 'groupByField'));
        String stackBucketId = BoardBucketField.referencedId(getString(request, 'stackByField'));
        if (groupBucketId != null || stackBucketId != null) {
            if (new ChartMeasures(scope.objectDescribe, getList(request, 'measures')).hasCountDistinct()) {
                throw countDistinctUnmergeable();
            }
            return scanBucketPartials(scope, request, groupBucketId, stackBucketId, runQuery, allowCursor);
        }
        ChartGrouping grouping = String.isBlank(getString(request, 'groupByField'))
            ? null
            : new ChartGrouping(scope.objectDescribe, request);
        ChartMeasures measures = new ChartMeasures(scope.objectDescribe, getList(request, 'measures'));
        if (measures.size() > 1 && grouping != null && grouping.stackBy != null) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'A Chart widget shows several Measures or one Measure split by a series field, not both.',
                null,
                'stackByField'
            );
        }
        if (measures.hasCountDistinct()) {
            throw countDistinctUnmergeable();
        }
        measures.compileConditions(scope);
        BoardChartQuery.ChartResult result = new BoardChartQuery.ChartResult();
        result.aggregateFunctions = measures.functions;
        result.valueTypes = measures.valueTypes;
        result.groupBy = grouping == null ? null : grouping.groupBy.info();
        result.stackBy = grouping == null || grouping.stackBy == null ? null : grouping.stackBy.info();
        result.panelBy = grouping == null || grouping.panelBy == null ? null : grouping.panelBy.info();
        result.appliedFilterIds = new List<String>(scope.appliedFilterIds);
        result.ignoredFilterIds = new List<String>(scope.ignoredFilterIds);
        result.accumulator = new BoardChartEngine.Accumulator(measures.size());
        if (!runQuery) {
            return result;
        }
        List<String> extraPredicates = grouping == null ? new List<String>() : grouping.extraPredicates();
        result.totalRows = countScopeRows(scope, extraPredicates);
        if (result.totalRows > CURSOR_AGGREGATE_THRESHOLD) {
            // Metric chunk continuations evaluate the Measure condition per record too (`providerMetricChunk`).
            if (!allowCursor || result.totalRows > CURSOR_MAX_ROWS) {
                throw limitExceeded(result.totalRows);
            }
            openChartCursor(
                scope,
                scope.buildSoql(measures.cursorSelect(grouping), extraPredicates, measures.cursorOrder()),
                grouping,
                measures,
                result
            );
            return result;
        }
        String suffix = grouping == null ? '' : 'GROUP BY ' + grouping.groupByClause() + ' LIMIT ' + CHART_GROUP_LIMIT;
        List<String> none = new List<String>{ null, null };
        // One query per Measure condition group; partials merge on the category / series key.
        for (Integer g = 0; g < measures.groups.groups.size(); g++) {
            BoardMeasureGroups.MeasureGroup measureGroup = measures.groups.groups[g];
            ChartMeasures groupMeasures = measures.subset(measureGroup.measureIndexes);
            if (measureGroup.perField != null) {
                // Average per record: one value per record, merged as `{ sum, count }` of record values.
                BoardChartEngine.Accumulator averages = new BoardChartEngine.Accumulator(groupMeasures.size());
                Boolean perRecordCapped = queryPerRecordGroup(
                    scope,
                    grouping,
                    groupMeasures,
                    measures.predicatesFor(g, extraPredicates),
                    averages
                );
                for (BoardChartEngine.GroupedRow row : averages.rows) {
                    result.accumulator.addPartials(
                        row.panelValue,
                        row.panelLabel,
                        row.categoryValue,
                        row.categoryLabel,
                        row.seriesValue,
                        row.seriesLabel,
                        measureGroup.spread(row.partials, measures.size())
                    );
                }
                result.hasMoreGroups = result.hasMoreGroups || perRecordCapped;
                continue;
            }
            String selectClause = groupMeasures.partialSelect();
            if (grouping != null) {
                selectClause = grouping.aggregateSelect() + ', ' + selectClause;
            }
            List<SObject> rows = scope.query(
                scope.buildSoql(selectClause, measures.predicatesFor(g, extraPredicates), suffix)
            );
            for (SObject row : rows) {
                AggregateResult aggregate = (AggregateResult) row;
                List<String> category = grouping == null ? none : grouping.groupBy.fromAggregate(aggregate);
                List<String> series = grouping == null ||
                    grouping.stackBy == null
                    ? none
                    : grouping.stackBy.fromAggregate(aggregate);
                // A Cross-object measure's leg groups by its panel mapping too (Small multiples).
                List<String> panel = grouping == null ? none : grouping.panelOfAggregate(aggregate);
                result.accumulator.addPartials(
                    panel[0],
                    panel[1],
                    category[0],
                    category[1],
                    series[0],
                    series[1],
                    measureGroup.spread(groupMeasures.partials(aggregate), measures.size())
                );
            }
            result.hasMoreGroups = result.hasMoreGroups || (grouping != null && rows.size() >= CHART_GROUP_LIMIT);
        }
        return result;
    }

    private static BoardErrors.BoardException countDistinctUnmergeable() {
        return BoardErrors.error(
            BoardErrors.CONFIG_ERROR,
            'A Widget with a Data provider cannot show COUNT_DISTINCT Measures: their partial results cannot be merged.',
            null,
            'measures'
        );
    }

    private static void openChartCursor(
        QueryScope scope,
        String soql,
        ChartGrouping grouping,
        ChartMeasures measures,
        BoardChartQuery.ChartResult result
    ) {
        Database.Cursor cursor = Database.getCursorWithBinds(soql, scope.binds, AccessLevel.USER_MODE);
        scanChartChunk(cursor, 0, grouping, measures, result);
    }

    /** Adds one cursor chunk's records (`readCursorRows`) to `result.accumulator`. */
    private static void scanChartChunk(
        Database.Cursor cursor,
        Integer offset,
        ChartGrouping grouping,
        ChartMeasures measures,
        BoardChartQuery.ChartResult result
    ) {
        Integer start = Math.max(0, offset);
        CursorRows chunk = readCursorRows(cursor, start);
        Integer totalRows = chunk.totalRows;
        Integer fetchSize = chunk.nextOffset - start;
        List<String> none = new List<String>{ null, null };
        List<SObject> records = chunk.records;
        // Average per record: the chunk ends before its last record's rows, which the next chunk re-reads.
        Integer readCount = measures.completeRecords(records, chunk.nextOffset >= totalRows);
        BoardAveragePerRecord.RecordFold fold = new BoardAveragePerRecord.RecordFold(measures.inners);
        for (Integer r = 0; r < readCount; r++) {
            SObject row = records[r];
            // No grouping: the ungrouped standard leg of a Metric widget's Data provider.
            List<String> category = grouping == null ? none : grouping.groupBy.fromRecord(row);
            List<String> series = grouping == null ||
                grouping.stackBy == null
                ? new List<String>{ null, null }
                : grouping.stackBy.fromRecord(row);
            List<String> panel = grouping == null ? none : grouping.panelOfRecord(row);
            result.accumulator.add(
                panel[0],
                panel[1],
                category[0],
                category[1],
                series[0],
                series[1],
                measures.recordValues(row)
            );
            if (measures.hasPerRecord()) {
                fold.add(
                    panel[0],
                    panel[1],
                    category[0],
                    category[1],
                    series[0],
                    series[1],
                    measures.recordKey(row),
                    measures.perRecordValues(row)
                );
            }
        }
        fold.putInto(result.accumulator);
        Integer consumed = fetchSize - (records.size() - readCount);
        result.mode = MODE_CURSOR;
        result.cursor = JSON.serialize(cursor);
        result.totalRows = totalRows;
        result.processedRows = start + consumed;
        result.nextOffset = start + consumed;
        result.isComplete = result.nextOffset >= totalRows;
    }

    /**
     * A Chart widget grouped, split or paneled by a Bucket field (`bucket:<id>` in `groupByField`, `stackByField` or
     * `panelField`, defined in the request's Widget-level `bucketFields`, else its Board-level `boardBucketFields`;
     * see `BoardBucketField.find`). SOQL tier: one aggregate query
     * per bucket, `WHERE <scope> AND rule_i AND NOT(rule_1..i-1)`, grouped by the other dimensions when there are any,
     * so every aggregate is exact. Cursor tier (a value Measure over more than `CURSOR_AGGREGATE_THRESHOLD`, up to
     * `CURSOR_MAX_ROWS` rows): one `Database.Cursor` over the scope, each record labelled in memory by
     * `BoardBucketField.labelOf` (same buckets as the `SOQL` predicates), continued like `scanChart`. `COUNT_DISTINCT`
     * cannot merge across chunks, so it fails with `LIMIT_EXCEEDED` there (as without a Bucket field). A grouped
     * per-bucket query capped at `CHART_GROUP_LIMIT` re-runs through the cursor tier up to `CURSOR_MAX_ROWS` rows (as
     * `scanChart`); above that, or with `COUNT_DISTINCT`, the capped groups come back with `hasMoreGroups`.
     */
    private static BoardChartQuery.ChartResult scanBucketChart(
        Map<String, Object> request,
        String groupBucketId,
        String stackBucketId,
        String panelBucketId
    ) {
        String cursorJson = getString(request, 'cursor');
        // A chunk continuation reads its open cursor: the scope only compiles the Bucket rules, without the filters.
        QueryScope scope = new QueryScope(
            cursorJson == null ? request : new Map<String, Object>{ 'objectApiName' => request.get('objectApiName') }
        );
        BucketChart chart = new BucketChart(scope, request, groupBucketId, stackBucketId, panelBucketId);
        ChartMeasures measures = chart.measures;
        BoardBucketField bucketField = chart.bucketField;
        BoardChartQuery.ChartResult result = chart.result;
        BucketChunkScan chunkScan = chart.chunkScan;
        if (cursorJson != null) {
            result.accumulator.restore(getString(request, 'partialState'));
            Integer offset = getInteger(request, 'offset');
            chunkScan.scan(deserializeCursor(cursorJson), offset == null ? 0 : offset, result);
            return result;
        }
        result.appliedFilterIds = scope.appliedFilterIds;
        result.ignoredFilterIds = scope.ignoredFilterIds;

        List<String> extraPredicates = chart.extraPredicates();
        if (measures.needsRowCount()) {
            result.totalRows = countScopeRows(scope, extraPredicates);
            if (result.totalRows > CURSOR_AGGREGATE_THRESHOLD) {
                if (measures.hasCountDistinct() || result.totalRows > CURSOR_MAX_ROWS) {
                    throw limitExceeded(result.totalRows);
                }
                String soql = scope.buildSoql(chunkScan.selectClause(), extraPredicates, '');
                chunkScan.scan(Database.getCursorWithBinds(soql, scope.binds, AccessLevel.USER_MODE), 0, result);
                return result;
            }
        }
        String suffix = chart.groupBySuffix();
        Map<String, String> bucketPredicates = bucketField.predicates(scope);
        // One query per bucket and Measure condition group, joined on the Panel / category / series key.
        BoardMeasureGroups.MeasureJoin measureJoin = new BoardMeasureGroups.MeasureJoin(measures.functions);
        for (String bucketLabel : bucketField.labels()) {
            for (Integer g = 0; g < measures.groups.groups.size(); g++) {
                BoardMeasureGroups.MeasureGroup measureGroup = measures.groups.groups[g];
                ChartMeasures groupMeasures = measures.subset(measureGroup.measureIndexes);
                // A bucket without rows is skipped; a query without GROUP BY still returns one row, so count its rows.
                Integer countIndex = groupMeasures.functions.indexOf('COUNT');
                String rowCountAlias = countIndex >= 0 ? 'v' + countIndex : 'bn';
                String selectClause = groupMeasures.aggregateSelect() + (countIndex >= 0 ? '' : ', COUNT(Id) bn');
                if (chart.isGrouped()) {
                    selectClause = chart.selectColumns() + ', ' + selectClause;
                }
                List<String> predicates = measures.predicatesFor(g, extraPredicates);
                predicates.add(bucketPredicates.get(bucketLabel));
                List<SObject> rows = scope.query(scope.buildSoql(selectClause, predicates, suffix));
                if (chart.isGrouped() && rows.size() >= CHART_GROUP_LIMIT) {
                    result.hasMoreGroups = true;
                }
                for (SObject row : rows) {
                    AggregateResult aggregate = (AggregateResult) row;
                    if (Integer.valueOf(aggregate.get(rowCountAlias)) == 0) {
                        continue;
                    }
                    List<Object> values = new List<Object>();
                    for (Integer i = 0; i < groupMeasures.size(); i++) {
                        values.add(aggregate.get('v' + i));
                    }
                    List<List<String>> keys = chart.keysOfAggregate(aggregate, bucketLabel);
                    measureJoin.put(measureGroup, keys[0], keys[1], keys[2], values);
                }
            }
        }
        measureJoin.putInto(result.accumulator);
        Boolean mergeOther =
            !result.hasMoreGroups &&
            !measures.hasCountDistinct() &&
            needsMergedOther(request, measures, result);
        // Capped (smaller groups were dropped), or an "Other" that must merge partials: re-aggregate every group
        // through cursor chunks when possible.
        if ((result.hasMoreGroups || mergeOther) && !measures.hasCountDistinct()) {
            if (result.totalRows == null) {
                result.totalRows = countScopeRows(scope, extraPredicates);
            }
            if (result.totalRows <= CURSOR_MAX_ROWS) {
                result.hasMoreGroups = false;
                result.accumulator = new BoardChartEngine.Accumulator(measures.size());
                String soql = scope.buildSoql(chunkScan.selectClause(), extraPredicates, '');
                chunkScan.scan(Database.getCursorWithBinds(soql, scope.binds, AccessLevel.USER_MODE), 0, result);
                return result;
            }
        }
        // Share of total and Reference lines over every bucketed row (an excluded fallback stays out).
        List<String> bucketedPredicates = new List<String>(extraPredicates);
        bucketedPredicates.add('(' + String.join(bucketPredicates.values(), ') OR (') + ')');
        if (result.hasMoreGroups && BoardChartQuery.usesShareOfTotal(request)) {
            result.grandTotals = chartGrandTotals(scope, bucketedPredicates, measures);
        }
        result.overallValues = referenceLineTotals(request, scope, bucketedPredicates, measures);
        result.panelQueryTotals = chart.panel != null
            ? chartPanelTotals(request, scope, bucketedPredicates, measures, chart.panel)
            : bucketPanelTotals(request, scope, extraPredicates, bucketPredicates, chart);
        return result;
    }

    /**
     * Panel totals of a Bucket field Panel field (`BoardChartPanelTotals`): every Measure over each bucket's rows, in
     * one ungrouped query per bucket and Measure condition group, keyed by bucket label (the Panel key), so an AVG is
     * exact. Null unless the Bucket field is the Panel field and a Panel headline or Reference line needs them.
     */
    private static Map<String, List<Decimal>> bucketPanelTotals(
        Map<String, Object> request,
        QueryScope scope,
        List<String> extraPredicates,
        Map<String, String> bucketPredicates,
        BucketChart chart
    ) {
        if (chart.bucketRole != BUCKET_AS_PANEL || !BoardChartPanelTotals.isNeeded(request)) {
            return null;
        }
        ChartMeasures measures = chart.measures;
        Map<String, List<Decimal>> totals = new Map<String, List<Decimal>>();
        for (String bucketLabel : chart.bucketField.labels()) {
            for (Integer g = 0; g < measures.groups.groups.size(); g++) {
                BoardMeasureGroups.MeasureGroup measureGroup = measures.groups.groups[g];
                ChartMeasures groupMeasures = measures.subset(measureGroup.measureIndexes);
                List<String> predicates = measures.predicatesFor(g, extraPredicates);
                predicates.add(bucketPredicates.get(bucketLabel));
                // An ungrouped query returns one row even for an empty bucket, so count its rows.
                AggregateResult aggregate = (AggregateResult) scope.query(
                    scope.buildSoql(groupMeasures.aggregateSelect() + ', COUNT(Id) bn', predicates, '')
                )[0];
                if (Integer.valueOf(aggregate.get('bn')) == 0) {
                    continue;
                }
                List<Decimal> bucketTotals = totals.get(bucketLabel);
                if (bucketTotals == null) {
                    bucketTotals = new List<Decimal>();
                    for (Integer i = 0; i < measures.size(); i++) {
                        bucketTotals.add(null);
                    }
                    totals.put(bucketLabel, bucketTotals);
                }
                for (Integer i = 0; i < groupMeasures.size(); i++) {
                    Object value = aggregate.get('v' + i);
                    bucketTotals[measureGroup.measureIndexes[i]] = value == null
                        ? null
                        : Decimal.valueOf(String.valueOf(value));
                }
            }
        }
        return totals;
    }

    /**
     * The setup a Bucket field chart shares between the Widget query (`scanBucketChart`) and a Data provider's
     * standard leg (`scanBucketPartials`): where the Bucket field goes (category, series or Panel field), the plain
     * dimensions grouped next to it, the Measures, the Bucket field compiled into `scope`, the result header and the
     * cursor-tier scan. A chart uses one Bucket field.
     */
    private class BucketChart {
        /** `BUCKET_AS_CATEGORY`, `BUCKET_AS_SERIES` or `BUCKET_AS_PANEL`. */
        String bucketRole;
        /** The plain category, series and Panel fields; null in the Bucket field's role or when not set. */
        ChartDimension category;
        ChartDimension series;
        ChartDimension panel;
        /** The plain dimensions, in `GROUP BY` order. */
        List<ChartDimension> dimensions = new List<ChartDimension>();
        Boolean includeNullBucket;
        ChartMeasures measures;
        BoardBucketField bucketField;
        BoardChartQuery.ChartResult result;
        BucketChunkScan chunkScan;

        BucketChart(
            QueryScope scope,
            Map<String, Object> request,
            String groupBucketId,
            String stackBucketId,
            String panelBucketId
        ) {
            Integer bucketCount =
                (groupBucketId != null ? 1 : 0) +
                (stackBucketId != null ? 1 : 0) +
                (panelBucketId != null ? 1 : 0);
            if (bucketCount > 1) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'A Chart widget uses one Bucket field: as its category, series or Panel field.',
                    null,
                    panelBucketId != null ? 'panelField' : 'stackByField'
                );
            }
            String bucketId = panelBucketId;
            bucketRole = BUCKET_AS_PANEL;
            if (groupBucketId != null) {
                bucketId = groupBucketId;
                bucketRole = BUCKET_AS_CATEGORY;
            } else if (stackBucketId != null) {
                bucketId = stackBucketId;
                bucketRole = BUCKET_AS_SERIES;
            }
            includeNullBucket = request.get('includeNullBucket') != false;
            measures = new ChartMeasures(scope.objectDescribe, getList(request, 'measures'));
            if (measures.hasPerRecord()) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Average per record isn\'t available on a chart grouped or split by a Bucket field.',
                    null,
                    'measures'
                );
            }
            String groupPath = getString(request, 'groupByField');
            String stackPath = getString(request, 'stackByField');
            String panelPath = getString(request, 'panelField');
            if (bucketRole != BUCKET_AS_CATEGORY) {
                if (String.isBlank(groupPath)) {
                    throw BoardErrors.error(
                        BoardErrors.CONFIG_ERROR,
                        'A group-by field is required.',
                        null,
                        'groupByField'
                    );
                }
                category = new ChartDimension(
                    scope.objectDescribe,
                    groupPath,
                    getString(request, 'dateGranularity'),
                    'g0'
                );
                dimensions.add(category);
            }
            if (bucketRole != BUCKET_AS_SERIES && String.isNotBlank(stackPath)) {
                series = new ChartDimension(scope.objectDescribe, stackPath, null, 'g1');
                dimensions.add(series);
            }
            if (bucketRole != BUCKET_AS_PANEL && String.isNotBlank(panelPath)) {
                requirePanelDistinct(panelPath, groupPath, stackPath);
                panel = new ChartDimension(
                    scope.objectDescribe,
                    panelPath,
                    getString(request, 'panelDateGranularity'),
                    'g2'
                );
                dimensions.add(panel);
            }
            Boolean hasSeries = bucketRole == BUCKET_AS_SERIES || series != null;
            if (measures.size() > 1 && hasSeries) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'A Chart widget shows several Measures or one Measure split by a series field, not both.',
                    null,
                    'stackByField'
                );
            }
            bucketField = BoardBucketField.find(
                getList(request, 'bucketFields'),
                getList(request, 'boardBucketFields'),
                bucketId
            );
            scope.compileBucketRules(bucketField);
            // Before the cursor tier, which evaluates each Measure condition per record.
            measures.compileConditions(scope);

            result = new BoardChartQuery.ChartResult();
            result.aggregateFunctions = measures.functions;
            result.valueTypes = measures.valueTypes;
            ChartDimensionInfo bucketInfo = bucketDimensionInfo(bucketField);
            result.groupBy = bucketRole == BUCKET_AS_CATEGORY ? bucketInfo : category.info();
            result.stackBy = bucketRole == BUCKET_AS_SERIES ? bucketInfo : (series == null ? null : series.info());
            result.panelBy = bucketRole == BUCKET_AS_PANEL ? bucketInfo : (panel == null ? null : panel.info());
            result.accumulator = new BoardChartEngine.Accumulator(measures.size());
            chunkScan = new BucketChunkScan(scope, this);
        }

        /** Without include blank: no blank plain category or Panel field value (as `ChartGrouping`). */
        List<String> extraPredicates() {
            List<String> predicates = new List<String>();
            if (!includeNullBucket) {
                if (category != null) {
                    predicates.add(category.field.path + ' != null');
                }
                if (panel != null) {
                    predicates.add(panel.field.path + ' != null');
                }
            }
            return predicates;
        }

        /** Whether the per-bucket queries group by a plain dimension. */
        Boolean isGrouped() {
            return !dimensions.isEmpty();
        }

        /** `GROUP BY` of the per-bucket queries (capped at `CHART_GROUP_LIMIT`), or empty when ungrouped. */
        String groupBySuffix() {
            if (!isGrouped()) {
                return '';
            }
            List<String> expressions = new List<String>();
            for (ChartDimension dimension : dimensions) {
                expressions.addAll(dimension.expressions);
            }
            return 'GROUP BY ' + String.join(expressions, ', ') + ' LIMIT ' + CHART_GROUP_LIMIT;
        }

        /** The plain dimensions' aggregate SELECT columns. */
        String selectColumns() {
            List<String> columns = new List<String>();
            for (ChartDimension dimension : dimensions) {
                columns.addAll(dimension.selectColumns());
            }
            return String.join(columns, ', ');
        }

        /** Raw field paths of the plain dimensions (cursor tier). */
        List<String> rawPaths() {
            List<String> paths = new List<String>();
            for (ChartDimension dimension : dimensions) {
                paths.addAll(dimension.rawPaths());
            }
            return paths;
        }

        /** `[panel, category, series]` `[value, label]` keys of a grouped row of `bucketLabel`'s query. */
        List<List<String>> keysOfAggregate(AggregateResult aggregate, String bucketLabel) {
            return keysOf(
                bucketLabel,
                panel == null ? null : panel.fromAggregate(aggregate),
                category == null ? null : category.fromAggregate(aggregate),
                series == null ? null : series.fromAggregate(aggregate)
            );
        }

        /** `[panel, category, series]` `[value, label]` keys of a cursor record in `bucketLabel`. */
        List<List<String>> keysOfRecord(SObject record, String bucketLabel) {
            return keysOf(
                bucketLabel,
                panel == null ? null : panel.fromRecord(record),
                category == null ? null : category.fromRecord(record),
                series == null ? null : series.fromRecord(record)
            );
        }

        /** The bucket label in the Bucket field's role, the plain keys elsewhere (`[null, null]` when not set). */
        List<List<String>> keysOf(
            String bucketLabel,
            List<String> panelKey,
            List<String> categoryKey,
            List<String> seriesKey
        ) {
            List<String> bucketKey = new List<String>{ bucketLabel, bucketLabel };
            return new List<List<String>>{
                bucketRole == BUCKET_AS_PANEL ? bucketKey : orNone(panelKey),
                bucketRole == BUCKET_AS_CATEGORY ? bucketKey : orNone(categoryKey),
                bucketRole == BUCKET_AS_SERIES ? bucketKey : orNone(seriesKey)
            };
        }

        List<String> orNone(List<String> key) {
            return key == null ? new List<String>{ null, null } : key;
        }
    }

    /**
     * `scanPartials` for a Chart widget grouped or split by a Bucket field (a Data provider's standard leg): each
     * bucket's rows as mergeable `{ sum, count, min, max }` partials under the bucket label, the keys `scanBucketChart`
     * gives them. SOQL tier: one partial query per bucket and Measure condition group. Beyond
     * `CURSOR_AGGREGATE_THRESHOLD` rows: the cursor tier with `allowCursor` (continued by `scanBucketChart`), else
     * `LIMIT_EXCEEDED`.
     */
    private static BoardChartQuery.ChartResult scanBucketPartials(
        QueryScope scope,
        Map<String, Object> request,
        String groupBucketId,
        String stackBucketId,
        Boolean runQuery,
        Boolean allowCursor
    ) {
        BucketChart chart = new BucketChart(scope, request, groupBucketId, stackBucketId, null);
        BoardChartQuery.ChartResult result = chart.result;
        result.appliedFilterIds = new List<String>(scope.appliedFilterIds);
        result.ignoredFilterIds = new List<String>(scope.ignoredFilterIds);
        if (!runQuery) {
            return result;
        }
        List<String> extraPredicates = chart.extraPredicates();
        result.totalRows = countScopeRows(scope, extraPredicates);
        if (result.totalRows > CURSOR_AGGREGATE_THRESHOLD) {
            if (!allowCursor || result.totalRows > CURSOR_MAX_ROWS) {
                throw limitExceeded(result.totalRows);
            }
            String soql = scope.buildSoql(chart.chunkScan.selectClause(), extraPredicates, '');
            chart.chunkScan.scan(Database.getCursorWithBinds(soql, scope.binds, AccessLevel.USER_MODE), 0, result);
            return result;
        }
        String suffix = chart.groupBySuffix();
        Map<String, String> bucketPredicates = chart.bucketField.predicates(scope);
        ChartMeasures measures = chart.measures;
        for (String bucketLabel : chart.bucketField.labels()) {
            for (Integer g = 0; g < measures.groups.groups.size(); g++) {
                BoardMeasureGroups.MeasureGroup measureGroup = measures.groups.groups[g];
                ChartMeasures groupMeasures = measures.subset(measureGroup.measureIndexes);
                // A query without GROUP BY returns one row even for an empty bucket, so count the bucket's rows.
                String selectClause = groupMeasures.partialSelect() + ', COUNT(Id) bn';
                if (chart.isGrouped()) {
                    selectClause = chart.selectColumns() + ', ' + selectClause;
                }
                List<String> predicates = measures.predicatesFor(g, extraPredicates);
                predicates.add(bucketPredicates.get(bucketLabel));
                List<SObject> rows = scope.query(scope.buildSoql(selectClause, predicates, suffix));
                if (chart.isGrouped() && rows.size() >= CHART_GROUP_LIMIT) {
                    result.hasMoreGroups = true;
                }
                for (SObject row : rows) {
                    AggregateResult aggregate = (AggregateResult) row;
                    if (Integer.valueOf(aggregate.get('bn')) == 0) {
                        continue;
                    }
                    List<BoardChartEngine.Partial> partials = measureGroup.spread(
                        groupMeasures.partials(aggregate),
                        measures.size()
                    );
                    // A Data provider draws no Small multiples: its partials key on category and series only.
                    List<List<String>> keys = chart.keysOfAggregate(aggregate, bucketLabel);
                    result.accumulator.addPartials(keys[1][0], keys[1][1], keys[2][0], keys[2][1], partials);
                }
            }
        }
        return result;
    }

    /**
     * Cursor tier of a Bucket field chart: reads a chunk of records (fetched like `fetchChunk`), labels each with its
     * bucket in memory and adds it to `result.accumulator` under that bucket and the plain dimensions' keys. Rule
     * fields on currency amounts are read in the corporate currency, the amount `SOQL` compares a rule value with.
     */
    private class BucketChunkScan {
        BucketChart chart;
        BoardBucketField bucketField;
        ChartMeasures measures;
        List<String> rulePaths;
        Map<String, String> ruleIsoPaths = new Map<String, String>();

        BucketChunkScan(QueryScope scope, BucketChart chart) {
            this.chart = chart;
            this.bucketField = chart.bucketField;
            this.measures = chart.measures;
            rulePaths = bucketField.paths();
            for (String path : rulePaths) {
                String isoPath = currencyIsoPath(resolveFieldPath(scope.objectDescribe, path, null, path));
                if (isoPath != null) {
                    ruleIsoPaths.put(path, isoPath);
                }
            }
        }

        /** Cursor SELECT list: Measure value fields, the plain dimensions' fields and every rule field, once. */
        String selectClause() {
            List<String> paths = measures.cursorSelect(null).split(', ');
            paths.addAll(chart.rawPaths());
            paths.addAll(rulePaths);
            paths.addAll(ruleIsoPaths.values());
            List<String> columns = new List<String>();
            Set<String> seen = new Set<String>();
            for (String path : paths) {
                if (seen.add(path.toLowerCase())) {
                    columns.add(path);
                }
            }
            return String.join(columns, ', ');
        }

        void scan(Database.Cursor cursor, Integer offset, BoardChartQuery.ChartResult result) {
            CursorRows chunk = readCursorRows(cursor, offset);
            for (SObject record : chunk.records) {
                String bucketLabel = bucketOf(record);
                if (bucketLabel == null) {
                    continue; // Matches no rule and the fallback bucket is excluded.
                }
                List<List<String>> keys = chart.keysOfRecord(record, bucketLabel);
                result.accumulator.add(
                    keys[0][0],
                    keys[0][1],
                    keys[1][0],
                    keys[1][1],
                    keys[2][0],
                    keys[2][1],
                    measures.recordValues(record)
                );
            }
            result.mode = MODE_CURSOR;
            result.cursor = JSON.serialize(cursor);
            result.totalRows = chunk.totalRows;
            result.processedRows = chunk.nextOffset;
            result.nextOffset = chunk.nextOffset;
            result.isComplete = result.nextOffset >= chunk.totalRows;
        }

        String bucketOf(SObject record) {
            Map<String, Object> row = new Map<String, Object>();
            for (String path : rulePaths) {
                row.put(path, readCorporateValue(record, path, ruleIsoPaths.get(path)));
            }
            return bucketField.labelOf(row);
        }
    }

    /** A Bucket field as a chart dimension: `bucket:<id>`, type `BUCKET`, its bucket labels as the picklist order. */
    private static ChartDimensionInfo bucketDimensionInfo(BoardBucketField bucketField) {
        ChartDimensionInfo info = new ChartDimensionInfo();
        info.fieldPath = BoardBucketField.REFERENCE_PREFIX + bucketField.id;
        info.dataType = 'BUCKET';
        info.picklistOrder = bucketField.labels();
        return info;
    }

    /** A Chart widget's Measures (1–6): aggregate function, resolved value field, and their query columns. */
    private class ChartMeasures {
        List<String> functions = new List<String>();
        List<String> valueTypes = new List<String>();
        List<String> expressions = new List<String>();
        List<String> valuePaths = new List<String>();
        List<String> isoPaths = new List<String>();
        /** Per Measure: an Average per record Measure's per-record field path and inner mode; null for the others. */
        List<String> perPaths = new List<String>();
        List<String> inners = new List<String>();
        /** Measure condition groups (`compileConditions`); one query each. */
        BoardMeasureGroups groups;
        /** Parallel to `groups.groups`: the group's compiled Measure condition `SOQL`, or null without one. */
        List<String> groupPredicates = new List<String>();
        /** Per Measure: its compiled Measure condition, evaluated per record in the cursor tier (null without one). */
        List<BoardCondition.Node> conditionNodes = new List<BoardCondition.Node>();
        /** Field paths the Measure conditions read (cursor tier). */
        Set<String> conditionPaths = new Set<String>();
        /** `CurrencyIsoCode` path of each currency condition path, so the cursor tier compares corporate amounts. */
        Map<String, String> conditionIsoPaths = new Map<String, String>();
        List<Object> rawMeasures;

        /** A subset's Measures (see `subset`). */
        ChartMeasures() {
        }

        ChartMeasures(Schema.DescribeSObjectResult objectDescribe, List<Object> rawMeasures) {
            this.rawMeasures = rawMeasures;
            if (rawMeasures.isEmpty() || rawMeasures.size() > BoardChartQuery.MAX_MEASURES) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'A Chart widget needs 1 to ' + BoardChartQuery.MAX_MEASURES + ' Measures.',
                    null,
                    'measures'
                );
            }
            for (Object rawMeasure : rawMeasures) {
                Map<String, Object> measure = asMap(rawMeasure);
                String aggregateFunction = parseAggregateFunction(measure);
                functions.add(aggregateFunction);
                Boolean isPerRecord = aggregateFunction == BoardAveragePerRecord.AGGREGATE_FUNCTION;
                Integer index = functions.size() - 1;
                perPaths.add(isPerRecord ? resolvePerRecordField(objectDescribe, measure, index) : null);
                inners.add(isPerRecord ? BoardAveragePerRecord.innerOf(measure, index) : null);
                if (aggregateFunction == 'COUNT') {
                    valueTypes.add(null);
                    expressions.add('COUNT(Id)');
                    valuePaths.add(null);
                    isoPaths.add(null);
                    continue;
                }
                ResolvedField valueField = resolveValueField(objectDescribe, getString(measure, 'valueFieldApiName'));
                if (aggregateFunction != 'COUNT_DISTINCT' && !BoardDescribe.NUMERIC_TYPES.contains(valueField.type)) {
                    throw BoardErrors.error(
                        BoardErrors.CONFIG_ERROR,
                        aggregateFunction + ' Measures require a numeric value field: ' + valueField.path,
                        null,
                        valueField.path
                    );
                }
                valueTypes.add(valueField.type.name());
                // Average per record: the query column is one record's value (SUM or MAX of its rows).
                expressions.add(
                    isPerRecord
                        ? BoardAveragePerRecord.innerExpression(inners[index], valueField.path)
                        : aggregateFunction + '(' + valueField.path + ')'
                );
                valuePaths.add(valueField.path);
                isoPaths.add(currencyIsoPath(valueField));
            }
            Set<String> perRecordFields = new Set<String>();
            for (String perPath : perPaths) {
                if (perPath != null) {
                    perRecordFields.add(perPath.toLowerCase());
                }
            }
            if (perRecordFields.size() > 1) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Average per record Measures of one Widget must use the same per-record field.',
                    null,
                    'measures'
                );
            }
        }

        /** True when any Measure is an Average per record Measure. */
        Boolean hasPerRecord() {
            return perRecordPath() != null;
        }

        /** The Average per record Measures' per-record field path (one per Widget), or null. */
        String perRecordPath() {
            for (String perPath : perPaths) {
                if (perPath != null) {
                    return perPath;
                }
            }
            return null;
        }

        /** Cursor `ORDER BY`: by the per-record field, so each record's rows are contiguous; else none. */
        String cursorOrder() {
            return hasPerRecord() ? 'ORDER BY ' + perRecordPath() : '';
        }

        /** A cursor row's record (its per-record field value). */
        Object recordKey(SObject row) {
            return readPath(row, perRecordPath());
        }

        /** How many leading `records` of a cursor chunk to read now (all without Average per record Measures). */
        Integer completeRecords(List<SObject> records, Boolean isLastChunk) {
            if (!hasPerRecord()) {
                return records.size();
            }
            List<Object> recordKeys = new List<Object>();
            for (SObject record : records) {
                recordKeys.add(recordKey(record));
            }
            return BoardAveragePerRecord.completeRecords(recordKeys, isLastChunk);
        }

        /**
         * One cursor row's value per Average per record Measure (folded per record by `BoardAveragePerRecord`),
         * currency converted to corporate; null for the other Measures and outside a Measure's condition.
         */
        List<Object> perRecordValues(SObject row) {
            Map<String, Object> conditionValues = conditionValuesOf(row);
            List<Object> values = new List<Object>();
            for (Integer i = 0; i < functions.size(); i++) {
                BoardCondition.Node condition = conditionNodes.isEmpty() ? null : conditionNodes[i];
                Boolean included = perPaths[i] != null && (condition == null || condition.evaluate(conditionValues));
                values.add(included ? readCorporateValue(row, valuePaths[i], isoPaths[i]) : null);
            }
            return values;
        }

        private Map<String, Object> conditionValuesOf(SObject row) {
            Map<String, Object> values = new Map<String, Object>();
            for (String path : conditionPaths) {
                values.put(path, readCorporateValue(row, path, conditionIsoPaths.get(path)));
            }
            return values;
        }

        Integer size() {
            return functions.size();
        }

        /**
         * Groups the Measures by Measure condition and compiles each condition into `scope`'s binds (Widget object
         * and parent fields only, so the cursor tier can evaluate it per record).
         */
        void compileConditions(QueryScope scope) {
            groups = new BoardMeasureGroups(rawMeasures);
            for (Integer i = 0; i < functions.size(); i++) {
                conditionNodes.add(null);
            }
            for (BoardMeasureGroups.MeasureGroup measureGroup : groups.groups) {
                if (measureGroup.condition == null) {
                    groupPredicates.add(null);
                    continue;
                }
                CompiledCondition compiled = scope.compileMeasureCondition(measureGroup.condition);
                groupPredicates.add(compiled.soql);
                collectPaths(compiled.node, conditionPaths);
                for (Integer index : measureGroup.measureIndexes) {
                    conditionNodes[index] = compiled.node;
                }
            }
            for (String path : conditionPaths) {
                String isoPath = currencyIsoPath(resolveFieldPath(scope.objectDescribe, path, null, path));
                if (isoPath != null) {
                    conditionIsoPaths.put(path, isoPath);
                }
            }
        }

        /** `extraPredicates` plus group `groupIndex`'s Measure condition. */
        List<String> predicatesFor(Integer groupIndex, List<String> extraPredicates) {
            List<String> predicates = new List<String>(extraPredicates);
            if (groupPredicates[groupIndex] != null) {
                predicates.add(groupPredicates[groupIndex]);
            }
            return predicates;
        }

        /** The Measures at `indexes` (one Measure group), their query columns numbered from 0. */
        ChartMeasures subset(List<Integer> indexes) {
            ChartMeasures part = new ChartMeasures();
            for (Integer index : indexes) {
                part.functions.add(functions[index]);
                part.valueTypes.add(valueTypes[index]);
                part.expressions.add(expressions[index]);
                part.valuePaths.add(valuePaths[index]);
                part.isoPaths.add(isoPaths[index]);
                part.perPaths.add(perPaths[index]);
                part.inners.add(inners[index]);
            }
            return part;
        }

        Boolean needsRowCount() {
            for (String aggregateFunction : functions) {
                if (aggregateFunction != 'COUNT') {
                    return true;
                }
            }
            return false;
        }

        Boolean hasCountDistinct() {
            return functions.contains('COUNT_DISTINCT');
        }

        /** `COUNT(Id) v0, SUM(Amount) v1, ...` */
        String aggregateSelect() {
            List<String> columns = new List<String>();
            for (Integer i = 0; i < expressions.size(); i++) {
                columns.add(expressions[i] + ' v' + i);
            }
            return String.join(columns, ', ');
        }

        /** Partial columns per Measure `i`: `COUNT(Id) ci`, or `SUM(f) si, COUNT(f) ci, MIN(f) ni, MAX(f) xi`. */
        String partialSelect() {
            List<String> columns = new List<String>();
            for (Integer i = 0; i < functions.size(); i++) {
                if (valuePaths[i] == null) {
                    columns.add('COUNT(Id) c' + i);
                    continue;
                }
                String path = valuePaths[i];
                columns.add('SUM(' + path + ') s' + i);
                columns.add('COUNT(' + path + ') c' + i);
                columns.add('MIN(' + path + ') n' + i);
                columns.add('MAX(' + path + ') x' + i);
            }
            return String.join(columns, ', ');
        }

        /** One `partialSelect` row's partial per Measure (`COUNT` Measures: `sum == count ==` rows). */
        List<BoardChartEngine.Partial> partials(AggregateResult aggregate) {
            List<BoardChartEngine.Partial> result = new List<BoardChartEngine.Partial>();
            for (Integer i = 0; i < functions.size(); i++) {
                BoardChartEngine.Partial partial = new BoardChartEngine.Partial();
                Object rawCount = aggregate.get('c' + i);
                partial.count = rawCount == null ? 0 : Integer.valueOf(rawCount);
                if (valuePaths[i] == null) {
                    partial.sum = partial.count;
                } else {
                    Object rawSum = aggregate.get('s' + i);
                    Object rawMin = aggregate.get('n' + i);
                    Object rawMax = aggregate.get('x' + i);
                    partial.sum = rawSum == null ? 0 : Decimal.valueOf(String.valueOf(rawSum));
                    partial.min = rawMin == null ? null : Decimal.valueOf(String.valueOf(rawMin));
                    partial.max = rawMax == null ? null : Decimal.valueOf(String.valueOf(rawMax));
                }
                result.add(partial);
            }
            return result;
        }

        /** Plain cursor SELECT list: every value field, its `CurrencyIsoCode` path, and the dimension paths, once. */
        String cursorSelect(ChartGrouping grouping) {
            List<String> paths = new List<String>();
            for (Integer i = 0; i < valuePaths.size(); i++) {
                if (valuePaths[i] != null) {
                    paths.add(valuePaths[i]);
                }
                if (isoPaths[i] != null) {
                    paths.add(isoPaths[i]);
                }
            }
            if (grouping != null) {
                paths.addAll(grouping.rawSelect().split(', '));
            }
            if (hasPerRecord()) {
                paths.add(perRecordPath());
            }
            paths.addAll(conditionPaths);
            paths.addAll(conditionIsoPaths.values());
            if (paths.isEmpty()) {
                paths.add('Id');
            }
            List<String> columns = new List<String>();
            Set<String> seen = new Set<String>();
            for (String path : paths) {
                if (seen.add(path.toLowerCase())) {
                    columns.add(path);
                }
            }
            return String.join(columns, ', ');
        }

        /**
         * One record's value per Measure, currency converted to corporate; `COUNT` Measures count every record. A
         * record outside a Measure's condition adds nothing to that Measure (null).
         */
        List<Object> recordValues(SObject row) {
            Map<String, Object> conditionRow = new Map<String, Object>();
            for (String path : conditionPaths) {
                conditionRow.put(path, readCorporateValue(row, path, conditionIsoPaths.get(path)));
            }
            List<Object> values = new List<Object>();
            for (Integer i = 0; i < functions.size(); i++) {
                BoardCondition.Node condition = conditionNodes.isEmpty() ? null : conditionNodes[i];
                if (condition != null && !condition.evaluate(conditionRow)) {
                    values.add(null);
                } else if (perPaths[i] != null) {
                    values.add(null); // Average per record: folded per record (`perRecordValues`).
                } else if (functions[i] == 'COUNT') {
                    values.add(1);
                } else {
                    values.add(readCorporateValue(row, valuePaths[i], isoPaths[i]));
                }
            }
            return values;
        }
    }

    /** An Average per record Measure's per-record field: a lookup on the Widget object (or a parent path to one). */
    private static String resolvePerRecordField(
        Schema.DescribeSObjectResult objectDescribe,
        Map<String, Object> measure,
        Integer index
    ) {
        String path = BoardAveragePerRecord.requirePerField(measure, index);
        ResolvedField field = resolveFieldPath(objectDescribe, path, null, path);
        if (field.type != Schema.DisplayType.REFERENCE) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Measure ' +
                    (index + 1) +
                    ': the per-record field must be a lookup (e.g. OpportunityId), not ' +
                    path +
                    '.',
                null,
                path
            );
        }
        return field.path;
    }

    /** Adds the field path of every condition in `node`'s tree to `paths`. */
    private static void collectPaths(BoardCondition.Node node, Set<String> paths) {
        if (node instanceof BoardCondition.Predicate) {
            paths.add(((BoardCondition.Predicate) node).path);
            return;
        }
        for (BoardCondition.Node child : ((BoardCondition.Junction) node).children) {
            collectPaths(child, paths);
        }
    }

    /** Reads a direct field or parent dot-path value from a queried record (null when a parent is empty). */
    public static Object readPath(SObject row, String path) {
        List<String> segments = path.split('\\.');
        SObject current = row;
        try {
            for (Integer i = 0; i < segments.size() - 1 && current != null; i++) {
                current = current.getSObject(segments[i]);
            }
            return current == null ? null : current.get(segments[segments.size() - 1]);
        } catch (SObjectException notQueried) {
            return null;
        }
    }

    /** The Chart's primary group dimension plus optional stack dimension and Panel field (Small multiples). */
    private class ChartGrouping {
        ChartDimension groupBy;
        ChartDimension stackBy;
        /** Small multiples: the Panel field, one more grouping of the same query; null without one. */
        ChartDimension panelBy;
        Boolean includeNullBucket;

        ChartGrouping(Schema.DescribeSObjectResult objectDescribe, Map<String, Object> request) {
            String groupPath = getString(request, 'groupByField');
            if (String.isBlank(groupPath)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'A group-by field is required.',
                    null,
                    'groupByField'
                );
            }
            groupBy = new ChartDimension(objectDescribe, groupPath, getString(request, 'dateGranularity'), 'g0');
            String stackPath = getString(request, 'stackByField');
            if (String.isNotBlank(stackPath)) {
                stackBy = new ChartDimension(objectDescribe, stackPath, null, 'g1');
            }
            String panelPath = getString(request, 'panelField');
            if (String.isNotBlank(panelPath)) {
                requirePanelDistinct(panelPath, groupPath, stackPath);
                panelBy = new ChartDimension(
                    objectDescribe,
                    panelPath,
                    getString(request, 'panelDateGranularity'),
                    'g2'
                );
            }
            includeNullBucket = request.get('includeNullBucket') != false;
        }

        List<String> extraPredicates() {
            List<String> predicates = new List<String>();
            if (!includeNullBucket) {
                predicates.add(groupBy.field.path + ' != null');
                if (panelBy != null) {
                    predicates.add(panelBy.field.path + ' != null');
                }
            }
            return predicates;
        }

        String aggregateSelect() {
            List<String> columns = groupBy.selectColumns();
            if (stackBy != null) {
                columns.addAll(stackBy.selectColumns());
            }
            if (panelBy != null) {
                columns.addAll(panelBy.selectColumns());
            }
            return String.join(columns, ', ');
        }

        String groupByClause() {
            List<String> expressions = new List<String>(groupBy.expressions);
            if (stackBy != null) {
                expressions.addAll(stackBy.expressions);
            }
            if (panelBy != null) {
                expressions.addAll(panelBy.expressions);
            }
            return String.join(expressions, ', ');
        }

        /** The Panel `[value, label]` of a grouped row; `[null, null]` without a Panel field. */
        List<String> panelOfAggregate(AggregateResult aggregate) {
            return panelBy == null ? new List<String>{ null, null } : panelBy.fromAggregate(aggregate);
        }

        /** The Panel `[value, label]` of a cursor record; `[null, null]` without a Panel field. */
        List<String> panelOfRecord(SObject row) {
            return panelBy == null ? new List<String>{ null, null } : panelBy.fromRecord(row);
        }

        /**
         * Plain (non-aggregate) SELECT list for cursor rows: every raw dimension path (each selected once).
         */
        String rawSelect() {
            List<String> paths = new List<String>();
            paths.addAll(groupBy.rawPaths());
            if (stackBy != null) {
                paths.addAll(stackBy.rawPaths());
            }
            if (panelBy != null) {
                paths.addAll(panelBy.rawPaths());
            }
            List<String> columns = new List<String>();
            Set<String> seen = new Set<String>();
            for (String path : paths) {
                if (seen.add(path.toLowerCase())) {
                    columns.add(path);
                }
            }
            return String.join(columns, ', ');
        }
    }

    /**
     * One Chart dimension (`groupByField` or `stackByField`): a groupable direct field or 1-5 hop parent path,
     * a Reference field labelled by its target's name field, or a Date/DateTime field bucketed by granularity.
     * Buckets are `[value, label]` pairs: sortable keys (`2026-03`, `2026-Q1`, `FY2026-Q2`, record Ids, picklist API
     * values) and display labels (null for the null bucket).
     */
    private class ChartDimension {
        ResolvedField field;
        String alias;
        String granularity;
        Boolean isDateTime = false;
        String labelPath;
        Map<String, String> picklistLabels = new Map<String, String>();
        List<String> picklistOrder = new List<String>();
        List<String> expressions = new List<String>();
        List<String> aliases = new List<String>();

        ChartDimension(
            Schema.DescribeSObjectResult objectDescribe,
            String rawPath,
            String rawGranularity,
            String alias
        ) {
            String path = rawPath.deleteWhitespace();
            if (path.contains('(')) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Chart dimensions must be a field or parent field path: ' + rawPath,
                    null,
                    rawPath
                );
            }
            this.field = resolveFieldPath(objectDescribe, path, null, rawPath);
            if (field.describe.isCalculated() && !field.describe.isGroupable()) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    BoardBucketField.formulaGroupingMessage(rawPath),
                    null,
                    rawPath
                );
            }
            this.alias = alias;
            String requested = upper(rawGranularity);
            Boolean isDate = DATE_TYPES.contains(field.type);
            if (String.isNotBlank(requested) && !DATE_GRANULARITIES.contains(requested)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Unsupported date granularity: ' + rawGranularity,
                    null,
                    rawPath
                );
            }
            if (String.isNotBlank(requested) && !isDate) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Date granularity requires a Date or DateTime field: ' + rawPath,
                    null,
                    rawPath
                );
            }
            if (isDate) {
                granularity = String.isBlank(requested) ? 'DAY' : requested;
                isDateTime = field.type == Schema.DisplayType.DATETIME;
                addDateExpressions();
                return;
            }
            if (!field.describe.isGroupable()) {
                throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Field is not groupable: ' + rawPath, null, rawPath);
            }
            add(field.path, 'k');
            if (field.type == Schema.DisplayType.REFERENCE) {
                labelPath = nameFieldPath(field);
                if (labelPath != null) {
                    add(labelPath, 'l');
                }
            }
            if (field.type == Schema.DisplayType.PICKLIST) {
                for (Schema.PicklistEntry entry : field.describe.getPicklistValues()) {
                    if (entry.isActive()) {
                        picklistOrder.add(entry.getValue());
                        picklistLabels.put(entry.getValue(), entry.getLabel());
                    }
                }
            }
        }

        void add(String expression, String suffix) {
            expressions.add(expression);
            aliases.add(alias + suffix);
        }

        void addDateExpressions() {
            String source = isDateTime ? 'convertTimezone(' + field.path + ')' : field.path;
            switch on granularity {
                when 'DAY' {
                    add(isDateTime ? 'DAY_ONLY(' + source + ')' : field.path, 'k');
                }
                when 'CALENDAR_MONTH' {
                    add('CALENDAR_YEAR(' + source + ')', 'y');
                    add('CALENDAR_MONTH(' + source + ')', 'p');
                }
                when 'CALENDAR_QUARTER' {
                    add('CALENDAR_YEAR(' + source + ')', 'y');
                    add('CALENDAR_QUARTER(' + source + ')', 'p');
                }
                when 'CALENDAR_YEAR' {
                    add('CALENDAR_YEAR(' + source + ')', 'y');
                }
                when 'FISCAL_QUARTER' {
                    add('FISCAL_YEAR(' + source + ')', 'y');
                    add('FISCAL_QUARTER(' + source + ')', 'p');
                }
                when else {
                    add('FISCAL_YEAR(' + source + ')', 'y');
                }
            }
        }

        /** `Parent.NameField` path of a Reference field's target, or null when unreadable or too deep. */
        String nameFieldPath(ResolvedField reference) {
            List<String> segments = reference.path.split('\\.');
            String relationshipName = reference.describe.getRelationshipName();
            if (relationshipName == null || segments.size() > MAX_PARENT_HOPS) {
                return null;
            }
            Schema.DescribeSObjectResult target = BoardDescribe.describeObject(parentType(reference.describe));
            if (!BoardDescribe.isReadableObject(target)) {
                return null;
            }
            String nameField = BoardDescribe.readableNameField(target);
            if (nameField == null) {
                return null;
            }
            segments[segments.size() - 1] = relationshipName;
            return String.join(segments, '.') + '.' + nameField;
        }

        List<String> selectColumns() {
            List<String> columns = new List<String>();
            for (Integer i = 0; i < expressions.size(); i++) {
                columns.add(expressions[i] + ' ' + aliases[i]);
            }
            return columns;
        }

        List<String> rawPaths() {
            List<String> paths = new List<String>{ field.path };
            if (labelPath != null) {
                paths.add(labelPath);
            }
            return paths;
        }

        List<String> fromAggregate(AggregateResult aggregate) {
            if (granularity == null) {
                return pair(aggregate.get(alias + 'k'), labelPath == null ? null : aggregate.get(alias + 'l'));
            }
            if (granularity == 'DAY') {
                return dateBucket((Date) aggregate.get(alias + 'k'), null, null);
            }
            Integer period = aliases.size() > 1 ? (Integer) aggregate.get(alias + 'p') : null;
            return dateBucket(null, (Integer) aggregate.get(alias + 'y'), period);
        }

        List<String> fromRecord(SObject row) {
            Object raw = readPath(row, field.path);
            if (granularity == null) {
                return pair(raw, labelPath == null ? null : readPath(row, labelPath));
            }
            // A DateTime field buckets by its date in the user's time zone (`DAY_ONLY(convertTimezone())` in SOQL).
            Object day = isDateTime && raw != null ? (Object) ((Datetime) raw).date() : raw;
            return BoardDataProviderRows.dateBucket(day, granularity);
        }

        List<String> pair(Object raw, Object label) {
            if (raw == null) {
                return new List<String>{ null, null };
            }
            String value = raw instanceof Date ? String.valueOf((Date) raw) : String.valueOf(raw);
            if (labelPath != null) {
                return new List<String>{ value, label == null ? value : String.valueOf(label) };
            }
            String picklistLabel = picklistLabels.get(value);
            return new List<String>{ value, picklistLabel == null ? value : picklistLabel };
        }

        List<String> dateBucket(Date day, Integer year, Integer period) {
            return BoardDataProviderRows.periodBucket(granularity, day, year, period);
        }

        ChartDimensionInfo info() {
            ChartDimensionInfo info = new ChartDimensionInfo();
            info.fieldPath = field.path;
            info.labelFieldPath = labelPath;
            info.dataType = field.type.name();
            info.dateGranularity = granularity;
            info.picklistOrder = picklistOrder;
            return info;
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Query scope compiler (shared by every Widget query)
    // ---------------------------------------------------------------------------------------------------------

    /**
     * Runs a scope's single-statement queries and counts in place of `AccessLevel.USER_MODE` (`QueryScope.executor`).
     * Only deployed Apex sets one, e.g. the Quota provider reading in system mode for viewers granted it; config can't.
     * Cursors, text searches and label lookups stay USER_MODE.
     */
    public interface QueryExecutor {
        List<SObject> query(String soql, Map<String, Object> binds);
        Integer countQuery(String soql, Map<String, Object> binds);
    }

    /**
     * Compiles a Widget request's data scope (`objectApiName` + resolved Filter bindings + base filters) into a
     * bind-safe `WHERE` clause and executes User Mode queries, counts, and cursors against it.
     */
    public class QueryScope implements BoardCondition.Binder {
        public Schema.DescribeSObjectResult objectDescribe;
        public Map<String, Object> binds = new Map<String, Object>();
        List<String> appliedFilterIds = new List<String>();
        List<String> ignoredFilterIds = new List<String>();
        /**
         * The scope's condition tree: one node per applied Filter binding and Base filter (a child-path node's path is
         * relative to its child object; `SOSL` text searches are not part of it). `predicates` holds its compiled `SOQL`.
         */
        public BoardCondition.Junction conditions = BoardCondition.allOf(new List<BoardCondition.Node>());
        List<String> predicates = new List<String>();
        /** Parallel to `predicates`: true when the predicate only uses direct fields, so `SOSL` `WHERE` can apply it. */
        List<Boolean> searchSafe = new List<Boolean>();
        /** Bind names holding escaped `LIKE` patterns (their `\` sequences must survive inlining into `SOSL`). */
        Set<String> likeBindNames = new Set<String>();
        Integer semiJoinCount = 0;
        /** Runs the scope's queries and counts instead of USER_MODE when set (see `QueryExecutor`). */
        public QueryExecutor executor;
        /** The Widget request: `displayCurrency` types end-user amount ranges, `configCurrency` Base filter amounts. */
        Map<String, Object> request;

        public QueryScope(Map<String, Object> request) {
            this.request = request;
            objectDescribe = BoardDescribe.requireReadableObject(getString(request, 'objectApiName'));
            List<FilterBinding> searches = new List<FilterBinding>();
            for (Object rawFilter : getList(request, 'filters')) {
                FilterBinding filter = new FilterBinding(rawFilter);
                if (filter.operator == 'SOSL') {
                    searches.add(filter);
                } else {
                    addFilter(filter);
                }
            }
            for (Object rawBaseFilter : getList(request, 'baseFilters')) {
                addBaseFilter(new BaseFilter(rawBaseFilter));
            }
            // Text searches compile last so their capped search legs only return records inside the other filters.
            for (FilterBinding search : searches) {
                addFilter(search);
            }
        }

        /** A copy of `parent` narrowed by `narrowing` (a Measure condition); shares `parent`'s binds. */
        QueryScope(QueryScope parent, CompiledCondition narrowing) {
            objectDescribe = parent.objectDescribe;
            binds = parent.binds;
            appliedFilterIds = parent.appliedFilterIds;
            ignoredFilterIds = parent.ignoredFilterIds;
            conditions = BoardCondition.allOf(new List<BoardCondition.Node>(parent.conditions.children));
            conditions.children.add(narrowing.node);
            predicates = new List<String>(parent.predicates);
            searchSafe = new List<Boolean>(parent.searchSafe);
            likeBindNames = parent.likeBindNames;
            semiJoinCount = parent.semiJoinCount;
            executor = parent.executor;
            addCompiled(narrowing.soql, narrowing.isSearchSafe);
        }

        /**
         * This scope narrowed by a Measure condition (ANDed with the Filter context and Base filters); this scope
         * itself when the condition is blank.
         */
        public QueryScope withMeasureCondition(Object rawCondition) {
            if (BoardMeasureGroups.isBlank(rawCondition)) {
                return this;
            }
            return new QueryScope(this, compileMeasureCondition(rawCondition));
        }

        /** A Measure condition's condition tree, compiled into this scope's binds; null when blank. */
        public BoardCondition.Node measureConditionNode(Object rawCondition) {
            return BoardMeasureGroups.isBlank(rawCondition) ? null : compileMeasureCondition(rawCondition).node;
        }

        /**
         * A Measure condition (Base filter condition tree), compiled into this scope's binds. Like Bucket rules it can
         * only use the Widget's object and its parents, so a record's membership is computable from the record.
         */
        CompiledCondition compileMeasureCondition(Object rawCondition) {
            Integer semiJoinsBefore = semiJoinCount;
            CompiledCondition compiled = compileBaseFilterTree(new BaseFilter(rawCondition), false);
            if (semiJoinCount != semiJoinsBefore) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'A Measure condition can only use fields of the Widget\'s object and its parents.',
                    null,
                    'measures'
                );
            }
            return compiled;
        }

        public String buildSoql(String selectClause, List<String> extraPredicates, String suffix) {
            List<String> allPredicates = new List<String>(predicates);
            if (extraPredicates != null) {
                allPredicates.addAll(extraPredicates);
            }
            String soql = 'SELECT ' + selectClause + ' FROM ' + objectDescribe.getName();
            if (!allPredicates.isEmpty()) {
                soql += ' WHERE ' + conjunction(allPredicates);
            }
            return String.isBlank(suffix) ? soql : soql + ' ' + suffix;
        }

        /**
         * Narrows the scope with one more compiled `SOQL` predicate whose binds are already in `binds` (e.g. a Row
         * limit's top groups). Not applied to text-search legs, which compiled with the scope.
         */
        public void restrict(String predicate) {
            addCompiled(predicate, false);
        }

        String conjunction(List<String> clauses) {
            return '(' + String.join(clauses, ') AND (') + ')';
        }

        Integer countRows() {
            return countSoql(buildSoql('COUNT()', null, ''));
        }

        Integer countSoql(String soql) {
            return executor == null
                ? Database.countQueryWithBinds(soql, binds, AccessLevel.USER_MODE)
                : executor.countQuery(soql, binds);
        }

        List<SObject> query(String soql) {
            List<SObject> rows = executor == null
                ? Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)
                : executor.query(soql, binds);
            if (rows.isEmpty() || rows[0] instanceof AggregateResult) {
                return rows;
            }
            return Security.stripInaccessible(AccessType.READABLE, rows).getRecords();
        }

        String bind(Object value) {
            String name = 'b' + binds.size();
            binds.put(name, value);
            return ':' + name;
        }

        /** `BoardCondition.Binder`: condition values bind into this scope's bind map. */
        public String bind(Object value, Boolean isLikePattern) {
            if (value instanceof BoardCurrencyConverter.IsoAmount) {
                // A validated ISO currency literal: inlined, since a bound number is read in the corporate currency.
                return ((BoardCurrencyConverter.IsoAmount) value).toSoql();
            }
            return isLikePattern ? bindLike((String) value) : bind(value);
        }

        String bindLike(String pattern) {
            String token = bind(pattern);
            likeBindNames.add(token.substring(1));
            return token;
        }

        void addFilter(FilterBinding filter) {
            if (!filter.hasSelection()) {
                return;
            }
            String path = String.isBlank(filter.fieldPath) ? null : filter.fieldPath.trim();
            if (path != null && path.equalsIgnoreCase(IGNORE_BINDING)) {
                ignoredFilterIds.add(filter.filterId);
                return;
            }
            if (filter.type == BUCKET_FILTER) {
                addBucketFilter(filter);
                return;
            }
            if (filter.isTextSearch() && filter.text.trim().length() < filter.minimumCharacters()) {
                // Too short to search selectively: treated like an empty search box.
                ignoredFilterIds.add(filter.filterId);
                return;
            }
            if (filter.operator == 'SOSL') {
                addSearchFilter(filter, path);
                return;
            }
            if (path != null && path.contains(',')) {
                addTextFieldList(filter, path);
                return;
            }
            if (path == null && filter.explicit) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Filter binding has no field path.',
                    filter.filterId,
                    null
                );
            }
            if (path != null && !filter.explicit && !isUnambiguousConventionPath(filter, path)) {
                ignoredFilterIds.add(filter.filterId);
                return;
            }
            ResolvedField field;
            try {
                field = resolveBinding(path == null ? conventionPath(filter) : path, filter.filterId);
                if (field != null) {
                    requireFilterCompatible(filter, field);
                }
            } catch (BoardErrors.BoardException bindingError) {
                if (filter.explicit) {
                    throw bindingError;
                }
                field = null;
            }
            if (field == null) {
                ignoredFilterIds.add(filter.filterId);
                return;
            }
            // A Team condition reaches through `<relationship>.UserRoleId`, which `SOSL` `WHERE` can't apply.
            addPredicate(field, compileFilter(filter, field), filter.filterId, !filter.matchesTeams());
            appliedFilterIds.add(filter.filterId);
        }

        /**
         * A Bucket filter: the rows in the selected buckets of the Bucket field the Widget's Filter binding maps it to
         * (sent resolved in `bucketField`). Its rules compile against this Widget's object; when they don't fit it, a
         * convention binding is ignored and an explicit one is a config error.
         */
        void addBucketFilter(FilterBinding filter) {
            BoardBucketField bucketField;
            try {
                if (filter.bucketField == null) {
                    throw BoardErrors.error(
                        BoardErrors.CONFIG_ERROR,
                        'Bucket filter "' + filter.filterId + '" has no Bucket field.',
                        filter.filterId,
                        filter.fieldPath
                    );
                }
                bucketField = BoardBucketField.fromConfig(filter.bucketField);
                compileBucketRules(bucketField);
            } catch (BoardErrors.BoardException bindingError) {
                if (filter.explicit) {
                    throw bindingError;
                }
                ignoredFilterIds.add(filter.filterId);
                return;
            }
            BoardBucketField.Selection selection = bucketField.selection(
                filter.filterId,
                new Set<String>(filter.values)
            );
            conditions.children.add(selection);
            // Rule paths may reach parents, which `SOSL` `WHERE` can't apply.
            addCompiled(selection.toSoql(this), false);
            appliedFilterIds.add(filter.filterId);
        }

        /**
         * Compiles every rule condition of `bucketField` (Base filter condition shape) into its condition node and
         * `SOQL`, binding into this scope. Rules use the Widget's object and its parents only: a row's bucket must be
         * computable from the row itself.
         */
        public void compileBucketRules(BoardBucketField bucketField) {
            for (BoardBucketField.Rule rule : bucketField.rules) {
                Integer semiJoinsBefore = semiJoinCount;
                CompiledCondition compiled = compileBaseFilterTree(new BaseFilter(rule.rawCondition), false);
                if (semiJoinCount != semiJoinsBefore) {
                    throw BoardErrors.error(
                        BoardErrors.CONFIG_ERROR,
                        'Bucket rule "' + rule.label + '" can only use fields of the Widget\'s object and its parents.',
                        null,
                        BoardBucketField.REFERENCE_PREFIX + bucketField.id
                    );
                }
                rule.condition = compiled.node;
                rule.soql = compiled.soql;
            }
        }

        void addBaseFilter(BaseFilter condition) {
            CompiledCondition compiled = compileBaseFilterTree(condition, false);
            conditions.children.add(compiled.node);
            addCompiled(compiled.soql, compiled.isSearchSafe);
        }

        /**
         * A Base filter condition or AND / OR group, compiled to its condition node and `SOQL` (child paths wrapped in
         * semi-joins). `insideOr` marks conditions under an OR group, where `SOQL` allows no semi-join.
         */
        CompiledCondition compileBaseFilterTree(BaseFilter condition, Boolean insideOr) {
            if (condition.isGroup) {
                return compileBaseFilterGroup(condition, insideOr);
            }
            if (String.isBlank(condition.fieldPath)) {
                throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Base filter has no field path.', condition.id, null);
            }
            ResolvedField field = resolveBinding(condition.fieldPath.trim(), condition.id);
            if (insideOr && field.childObject != null) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Child relationship conditions cannot be combined with OR in base filters.',
                    condition.id,
                    field.bindingPath
                );
            }
            BoardCondition.Node node = compileBaseFilter(condition, field);
            return new CompiledCondition(
                node,
                wrapSemiJoin(field, node.toSoql(this), condition.id),
                isDirectField(field)
            );
        }

        CompiledCondition compileBaseFilterGroup(BaseFilter baseGroup, Boolean insideOr) {
            if (baseGroup.logic != 'AND' && baseGroup.logic != 'OR') {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Base filter group logic must be AND or OR.',
                    baseGroup.id,
                    null
                );
            }
            if (baseGroup.children.isEmpty()) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Base filter group has no conditions.',
                    baseGroup.id,
                    null
                );
            }
            Boolean isOr = baseGroup.logic == 'OR';
            List<BoardCondition.Node> nodes = new List<BoardCondition.Node>();
            List<String> clauses = new List<String>();
            Boolean isSearchSafe = true;
            for (BaseFilter child : baseGroup.children) {
                CompiledCondition compiled = compileBaseFilterTree(child, insideOr || isOr);
                nodes.add(compiled.node);
                clauses.add(compiled.soql);
                isSearchSafe &= compiled.isSearchSafe;
            }
            String soql = clauses.size() == 1
                ? clauses[0]
                : '(' + String.join(clauses, ') ' + baseGroup.logic + ' (') + ')';
            return new CompiledCondition(new BoardCondition.Junction(baseGroup.logic, nodes), soql, isSearchSafe);
        }

        void addPredicate(ResolvedField field, BoardCondition.Node condition, String filterId, Boolean isSearchSafe) {
            conditions.children.add(condition);
            addCompiled(wrapSemiJoin(field, condition.toSoql(this), filterId), isDirectField(field) && isSearchSafe);
        }

        void addCompiled(String predicate, Boolean isSearchSafe) {
            predicates.add(predicate);
            searchSafe.add(isSearchSafe);
        }

        Boolean isDirectField(ResolvedField field) {
            return field.childObject == null && !field.path.contains('.');
        }

        /** `predicate` as-is, or wrapped in `Id IN (SELECT fk FROM Child WHERE ...)` for a child path. */
        String wrapSemiJoin(ResolvedField field, String predicate, String filterId) {
            if (field.childObject == null) {
                return predicate;
            }
            semiJoinCount++;
            if (semiJoinCount > MAX_SEMI_JOINS) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'At most ' + MAX_SEMI_JOINS + ' child relationship bindings can apply to one widget.',
                    filterId,
                    field.bindingPath
                );
            }
            return 'Id IN (SELECT ' + field.foreignKey + ' FROM ' + field.childObject + ' WHERE ' + predicate + ')';
        }

        /** `CONTAINS` / `STARTS_WITH` across a comma-separated field list: one `OR` group of escaped `LIKE`s. */
        void addTextFieldList(FilterBinding filter, String path) {
            if (filter.operator != 'CONTAINS' && filter.operator != 'STARTS_WITH') {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Field lists require a CONTAINS or STARTS_WITH text filter.',
                    filter.filterId,
                    path
                );
            }
            List<String> clauses = new List<String>();
            List<BoardCondition.Node> alternatives = new List<BoardCondition.Node>();
            Boolean allDirect = true;
            for (String part : path.split(',')) {
                if (String.isBlank(part)) {
                    continue;
                }
                ResolvedField field = resolveBinding(part.trim(), filter.filterId);
                requireFilterCompatible(filter, field);
                BoardCondition.Node condition = compileFilter(filter, field);
                alternatives.add(condition);
                clauses.add('(' + wrapSemiJoin(field, condition.toSoql(this), filter.filterId) + ')');
                allDirect &= isDirectField(field);
            }
            conditions.children.add(BoardCondition.anyOf(alternatives));
            addCompiled(String.join(clauses, ' OR '), allDirect);
            appliedFilterIds.add(filter.filterId);
        }

        /**
         * `SOSL` text search compiled to `Id IN :matchedParentIds`: the single-transaction union of
         * `Search.query` (full-text indexes, incl. non-filterable Long Text Area fields) and a bounded `SOQL LIKE`
         * leg on filterable text fields (zero index lag). Targets are `SELF` and `Child(ForeignKey)` entries; by
         * convention `SELF`. Child matches keep their parent rows.
         * Both legs are restricted to the scope compiled so far (every other filter and base filter), so their row
         * caps never fill up with records the Widget would discard.
         */
        void addSearchFilter(FilterBinding filter, String path) {
            List<SearchTarget> targets = path == null
                ? conventionSearchTargets()
                : parseSearchTargets(filter.filterId, path);
            String term = filter.text.trim();
            Set<Id> parentIds = new Set<Id>();
            searchSosl(term, targets, parentIds);
            searchLike(term, targets, parentIds);
            addCompiled('Id IN ' + bind(new List<Id>(parentIds)), false);
            appliedFilterIds.add(filter.filterId);
        }

        List<SearchTarget> conventionSearchTargets() {
            return new List<SearchTarget>{ new SearchTarget(objectDescribe, null) };
        }

        List<SearchTarget> parseSearchTargets(String filterId, String path) {
            List<SearchTarget> targets = new List<SearchTarget>();
            Set<String> seen = new Set<String>();
            for (String part : path.split(',')) {
                String compact = part.deleteWhitespace();
                if (String.isBlank(compact)) {
                    continue;
                }
                SearchTarget target;
                if (compact.equalsIgnoreCase(SELF_TARGET)) {
                    target = new SearchTarget(objectDescribe, null);
                } else {
                    Matcher childTarget = CHILD_TARGET_PATTERN.matcher(compact);
                    if (!childTarget.matches()) {
                        throw BoardErrors.error(
                            BoardErrors.CONFIG_ERROR,
                            'SOSL search targets must be SELF or Child(ForeignKey): ' + part.trim(),
                            filterId,
                            path
                        );
                    }
                    target = childSearchTarget(childTarget.group(1), childTarget.group(2), filterId, path);
                }
                if (seen.add(target.describe.getName().toLowerCase())) {
                    targets.add(target);
                }
            }
            if (targets.isEmpty()) {
                throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'The SOSL search has no targets.', filterId, path);
            }
            if (targets.size() > MAX_SEARCH_TARGETS) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'A SOSL search can cover at most ' + MAX_SEARCH_TARGETS + ' objects.',
                    filterId,
                    path
                );
            }
            return targets;
        }

        SearchTarget childSearchTarget(String childObject, String foreignKey, String filterId, String bindingPath) {
            if (String.isBlank(childObject) || String.isBlank(foreignKey)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'A child search target needs an object and foreign key.',
                    filterId,
                    bindingPath
                );
            }
            ResolvedField fk = resolveSemiJoin(
                childObject.trim(),
                foreignKey.trim(),
                foreignKey.trim(),
                filterId,
                bindingPath
            );
            return new SearchTarget(
                BoardDescribe.describeObject(BoardDescribe.getGlobalDescribe().get(fk.childObject)),
                fk.foreignKey
            );
        }

        /**
         * Full-text leg, restricted to the scope compiled so far. A scope `SOSL` cannot evaluate falls back to
         * scoping `SELF` only, then to no scope (the Widget query still applies every filter); a term `SOSL` cannot
         * search (e.g. one character) leaves the `LIKE` leg to match.
         */
        void searchSosl(String term, List<SearchTarget> targets, Set<Id> parentIds) {
            String soslTerm = SOSL_RESERVED_PATTERN.matcher(term).replaceAll('\\\\$1') + '*';
            String scope = searchScope();
            List<List<SObject>> results = runSearch(soslTerm, targets, scope, true);
            if (results == null && scope != null && targets.size() > 1) {
                results = runSearch(soslTerm, targets, scope, false);
            }
            if (results == null && scope != null) {
                results = runSearch(soslTerm, targets, null, false);
            }
            if (results == null) {
                return;
            }
            for (Integer i = 0; i < targets.size(); i++) {
                collectMatches(targets[i], results[i], parentIds);
            }
        }

        /** One `Search.query`; null when the platform rejects the term or the `WHERE` scope. */
        List<List<SObject>> runSearch(
            String soslTerm,
            List<SearchTarget> targets,
            String scope,
            Boolean scopeChildren
        ) {
            Integer perObject = SEARCH_SOSL_LIMIT / targets.size();
            List<String> returning = new List<String>();
            for (SearchTarget target : targets) {
                String condition = '';
                if (scope != null && target.foreignKey == null) {
                    condition = ' WHERE ' + scope;
                } else if (scope != null && scopeChildren) {
                    condition = ' WHERE ' + parentRestriction(target, scope);
                }
                returning.add(
                    target.describe.getName() + '(' + target.selectList() + condition + ' LIMIT ' + perObject + ')'
                );
            }
            try {
                return Search.query(
                    'FIND :soslTerm IN ALL FIELDS RETURNING ' + String.join(returning, ', '),
                    AccessLevel.USER_MODE
                );
            } catch (SearchException unsearchable) {
                return null;
            } catch (QueryException unsupportedScope) {
                return null;
            }
        }

        /**
         * The search-safe predicates (direct fields only) with their binds inlined as literals, since `Search.query`
         * cannot take a bind map; null when none applies. Values are typed (coerced) binds: strings are quoted and
         * escaped, so no user text reaches the statement unescaped.
         */
        String searchScope() {
            List<String> clauses = new List<String>();
            for (Integer i = 0; i < predicates.size(); i++) {
                String inlined = searchSafe[i] ? inlineBinds(predicates[i]) : null;
                if (inlined != null) {
                    clauses.add(inlined);
                }
            }
            return clauses.isEmpty() ? null : conjunction(clauses);
        }

        /** `predicate` with each `:bN` replaced by its literal, or null when a value has no `SOSL` literal form. */
        String inlineBinds(String predicate) {
            Matcher token = BIND_TOKEN_PATTERN.matcher(predicate);
            List<String> parts = new List<String>();
            Integer last = 0;
            while (token.find()) {
                String name = token.group(1);
                String literal = searchLiteral(binds.get(name), likeBindNames.contains(name));
                if (literal == null) {
                    return null;
                }
                parts.add(predicate.substring(last, token.start()));
                parts.add(literal);
                last = token.end();
            }
            parts.add(predicate.substring(last));
            return String.join(parts, '');
        }

        /** `fk IN (SELECT Id FROM <Widget object> WHERE scope)` restricting a child target to in-scope parents. */
        String parentRestriction(SearchTarget target, String scope) {
            return target.foreignKey + ' IN (SELECT Id FROM ' + objectDescribe.getName() + ' WHERE ' + scope + ')';
        }

        /**
         * Synchronous `LIKE '%term%'` leg across each target's filterable text fields (`ORDER BY LastModifiedDate
         * DESC LIMIT 500`), ANDed with the scope compiled so far (child targets through a parent semi-join when the
         * scope has none of its own). A non-selective LDV query falls back to the `SOSL` leg.
         */
        void searchLike(String term, List<SearchTarget> targets, Set<Id> parentIds) {
            Map<String, Object> likeBinds = new Map<String, Object>(binds);
            likeBinds.put('likeTerm', '%' + BoardDescribe.escapeLike(term) + '%');
            String scope = predicates.isEmpty() ? null : conjunction(predicates);
            for (SearchTarget target : targets) {
                List<String> clauses = new List<String>();
                Map<String, Schema.SObjectField> fieldMap = target.describe.fields.getMap();
                for (Schema.SObjectField field : fieldMap.values()) {
                    Schema.DescribeFieldResult describe = field.getDescribe();
                    if (
                        SEARCH_LIKE_TYPES.contains(describe.getType()) &&
                        describe.isFilterable() &&
                        describe.isAccessible() &&
                        !describe.isEncrypted()
                    ) {
                        clauses.add(describe.getName() + ' LIKE :likeTerm');
                    }
                }
                if (clauses.isEmpty()) {
                    continue;
                }
                String condition = '(' + String.join(clauses, ' OR ') + ')';
                if (scope != null && target.foreignKey == null) {
                    condition += ' AND ' + scope;
                } else if (scope != null && semiJoinCount == 0) {
                    // SOQL cannot nest semi-joins, so a scope with child bindings leaves child legs unrestricted.
                    condition += ' AND ' + parentRestriction(target, scope);
                }
                String soql =
                    'SELECT ' +
                    target.selectList() +
                    ' FROM ' +
                    target.describe.getName() +
                    ' WHERE ' +
                    condition +
                    (fieldMap.containsKey('LastModifiedDate') ? ' ORDER BY LastModifiedDate DESC' : '') +
                    ' LIMIT ' +
                    SEARCH_LIKE_LIMIT;
                try {
                    collectMatches(target, Database.queryWithBinds(soql, likeBinds, AccessLevel.USER_MODE), parentIds);
                } catch (QueryException nonSelective) {
                    continue;
                }
            }
        }

        void collectMatches(SearchTarget target, List<SObject> records, Set<Id> parentIds) {
            Schema.SObjectType parentType = objectDescribe.getSObjectType();
            for (SObject record : records) {
                Id parentId = target.foreignKey == null ? record.Id : (Id) record.get(target.foreignKey);
                if (parentId == null || parentId.getSObjectType() != parentType) {
                    continue;
                }
                parentIds.add(parentId);
            }
        }

        /** Step 2 target object of a `LOOKUP`, `USER`, or Record context filter (Record context: from its Id). */
        String conventionTarget(FilterBinding filter) {
            if (!STEP_TWO_TYPES.contains(filter.type)) {
                return null;
            }
            String target = filter.targetObjectApiName;
            if (String.isBlank(target) && filter.type == 'USER') {
                target = 'User';
            }
            if (String.isBlank(target) && filter.type == 'RECORD_CONTEXT' && !filter.values.isEmpty()) {
                Id recordId = BoardDescribe.toId(filter.values[0]);
                target = recordId == null ? null : BoardDescribe.describeObject(recordId.getSObjectType()).getName();
            }
            return String.isBlank(target) ? null : target;
        }

        /**
         * Filterable, non-audit reference fields to `target`, regardless of the running user's FLS: ambiguity must
         * not depend on which candidates a user can read (spec story 37).
         */
        List<Schema.DescribeFieldResult> conventionCandidates(String target) {
            List<Schema.DescribeFieldResult> candidates = new List<Schema.DescribeFieldResult>();
            for (Schema.SObjectField field : objectDescribe.fields.getMap().values()) {
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                if (
                    fieldDescribe.getType() == Schema.DisplayType.REFERENCE &&
                    fieldDescribe.isFilterable() &&
                    !AUDIT_REFERENCE_FIELDS.contains(fieldDescribe.getName().toLowerCase()) &&
                    referencesObject(fieldDescribe, target)
                ) {
                    candidates.add(fieldDescribe);
                }
            }
            return candidates;
        }

        /**
         * Step 2 convention for `LOOKUP`, `USER`, and Record context filters without a field path: `Id` on the
         * target object, else the single candidate reference field when the running user can read it.
         */
        String conventionPath(FilterBinding filter) {
            String target = conventionTarget(filter);
            if (target == null) {
                return null;
            }
            if (target.equalsIgnoreCase(objectDescribe.getName())) {
                return 'Id';
            }
            List<Schema.DescribeFieldResult> candidates = conventionCandidates(target);
            return candidates.size() == 1 && candidates[0].isAccessible() ? candidates[0].getName() : null;
        }

        /**
         * Whether a Widget-resolved (non-explicit) path is a safe convention binding. Widgets resolve Step 2 over the
         * fields the user can read, so a Step 2 path (not `Id`, not the Step 1 `fieldApiName` hint, `OwnerId` for
         * `USER`) is re-checked against every candidate regardless of FLS.
         */
        Boolean isUnambiguousConventionPath(FilterBinding filter, String path) {
            if (!STEP_TWO_TYPES.contains(filter.type) || path.equalsIgnoreCase('Id')) {
                return true;
            }
            String stepOneField = String.isNotBlank(filter.fieldApiName)
                ? filter.fieldApiName.trim()
                : (filter.type == 'USER' ? 'OwnerId' : null);
            if (stepOneField != null && stepOneField.equalsIgnoreCase(path)) {
                return true;
            }
            String target = conventionTarget(filter);
            if (target == null) {
                return false;
            }
            List<Schema.DescribeFieldResult> candidates = conventionCandidates(target);
            return candidates.size() == 1 && candidates[0].getName().equalsIgnoreCase(path);
        }

        /** Resolves a direct field, 1-5 hop parent dot-path, or `Child(ForeignKey).Field` semi-join path. */
        ResolvedField resolveBinding(String path, String filterId) {
            if (path == null) {
                return null;
            }
            String compactPath = path.deleteWhitespace();
            Matcher semiJoin = SEMI_JOIN_PATTERN.matcher(compactPath);
            ResolvedField field;
            if (semiJoin.matches()) {
                field = resolveSemiJoin(semiJoin.group(1), semiJoin.group(2), semiJoin.group(3), filterId, path);
            } else {
                field = resolveFieldPath(objectDescribe, compactPath, filterId, path);
            }
            if (!field.describe.isFilterable()) {
                throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Field is not filterable: ' + path, filterId, path);
            }
            return field;
        }

        ResolvedField resolveSemiJoin(
            String childObjectName,
            String foreignKeyName,
            String childPath,
            String filterId,
            String bindingPath
        ) {
            Schema.SObjectType childType = BoardDescribe.getGlobalDescribe().get(childObjectName);
            if (childType == null) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Unknown child object: ' + childObjectName,
                    filterId,
                    bindingPath
                );
            }
            Schema.DescribeSObjectResult childDescribe = BoardDescribe.describeObject(childType);
            if (!BoardDescribe.isReadableObject(childDescribe)) {
                throw BoardErrors.error(
                    BoardErrors.ACCESS_ERROR,
                    'You do not have access to the object ' + childDescribe.getName(),
                    filterId,
                    bindingPath
                );
            }
            Schema.SObjectField foreignKey = childDescribe.fields.getMap().get(foreignKeyName);
            if (foreignKey == null) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Unknown field: ' + childDescribe.getName() + '.' + foreignKeyName,
                    filterId,
                    bindingPath
                );
            }
            Schema.DescribeFieldResult foreignKeyDescribe = BoardDescribe.requireReadableField(
                childDescribe.getName(),
                foreignKey.getDescribe(),
                filterId,
                bindingPath
            );
            if (
                foreignKeyDescribe.getType() != Schema.DisplayType.REFERENCE ||
                !foreignKeyDescribe.isFilterable() ||
                !referencesObject(foreignKeyDescribe, objectDescribe.getName())
            ) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    childDescribe.getName() +
                        '.' +
                        foreignKeyDescribe.getName() +
                        ' does not reference ' +
                        objectDescribe.getName(),
                    filterId,
                    bindingPath
                );
            }
            ResolvedField field = resolveFieldPath(childDescribe, childPath, filterId, bindingPath);
            field.childObject = childDescribe.getName();
            field.foreignKey = foreignKeyDescribe.getName();
            return field;
        }

        /** The condition a resolved Filter binding contributes (compiled to `SOQL` through this scope's binds). */
        BoardCondition.Node compileFilter(FilterBinding filter, ResolvedField field) {
            String path = field.path;
            String filterId = filter.filterId;
            switch on filter.operator {
                when 'IN' {
                    BoardCondition.Node users = compileIn(path, field, filter.effectiveValues(), false, filterId);
                    return filter.matchesTeams() ? compileTeam(users, filter, field) : users;
                }
                when 'EMPTY' {
                    return BoardCondition.field(filterId, path, 'EQ', new List<Object>{ null });
                }
                when 'FILLED' {
                    return BoardCondition.field(filterId, path, 'NEQ', new List<Object>{ null });
                }
                when 'LITERAL' {
                    return relativeDate(
                        filterId,
                        path,
                        requireRelativeDate(filter.literal, filterId, field.bindingPath)
                    );
                }
                when 'BETWEEN', 'GTE', 'LTE' {
                    List<BoardCondition.Node> range = new List<BoardCondition.Node>();
                    if (filter.operator != 'LTE' && String.isNotBlank(filter.fromValue)) {
                        range.add(
                            typed(filterId, path, 'GTE', rangeBound(filter.fromValue, field, false, filterId), field)
                        );
                    }
                    if (filter.operator != 'GTE' && String.isNotBlank(filter.toValue)) {
                        range.add(
                            typed(filterId, path, 'LTE', rangeBound(filter.toValue, field, true, filterId), field)
                        );
                    }
                    return BoardCondition.allOf(range);
                }
                when 'CONTAINS' {
                    return escapedLike(filterId, path, '%' + BoardDescribe.escapeLike(filter.text.trim()) + '%');
                }
                when else {
                    // STARTS_WITH (requireFilterCompatible rejects every other operator)
                    return escapedLike(filterId, path, BoardDescribe.escapeLike(filter.text.trim()) + '%');
                }
            }
        }

        /** A range bound: a date, a number, or (currency fields) an amount in the request's Display currency. */
        Object rangeBound(String value, ResolvedField field, Boolean endOfDay, String filterId) {
            if (!BoardDescribe.NUMERIC_TYPES.contains(field.type)) {
                return dateBound(value, field, endOfDay, filterId);
            }
            Decimal amount = (Decimal) coerce(value, field, filterId);
            if (field.type != Schema.DisplayType.CURRENCY) {
                return amount;
            }
            return BoardCurrencyConverter.forRequest().displayAmountBound(amount, request);
        }

        /**
         * Team condition of a `usersAndTeam` User filter: `<path> IN :userIds OR <path's relationship>.UserRoleId IN
         * :rolesBelow`, where `rolesBelow` are the roles strictly below the picked users' roles (role Ids stay in the
         * bind map, never in a result). Without roles below, only the picked users' own records match. Works on any
         * user-lookup path (custom lookups, parent paths, inside a child semi-join); a path whose `.UserRoleId`
         * would exceed the 5-hop limit is a config error regardless of the selection.
         */
        BoardCondition.Node compileTeam(BoardCondition.Node usersCondition, FilterBinding filter, ResolvedField field) {
            requireTeamHops(filter, field);
            Set<Id> userIds = new Set<Id>();
            for (String value : filter.effectiveValues()) {
                Id userId = BoardDescribe.toId(value);
                if (userId != null) {
                    userIds.add(userId);
                }
            }
            Set<Id> rolesBelow = BoardTeamResolver.rolesBelowUsers(userIds);
            String relationshipName = field.describe.getRelationshipName();
            if (rolesBelow.isEmpty() || relationshipName == null) {
                return usersCondition;
            }
            List<String> segments = field.path.split('\\.');
            segments[segments.size() - 1] = relationshipName;
            String rolePath = String.join(segments, '.') + '.UserRoleId';
            return BoardCondition.anyOf(
                new List<BoardCondition.Node>{
                    usersCondition,
                    BoardCondition.field(filter.filterId, rolePath, 'IN', new List<Id>(rolesBelow))
                }
            );
        }

        /** `<path>.UserRoleId` adds one relationship hop to the bound path; past `MAX_PARENT_HOPS` SOQL rejects it. */
        void requireTeamHops(FilterBinding filter, ResolvedField field) {
            Integer roleHops = field.path.split('\\.').size();
            if (roleHops > MAX_PARENT_HOPS) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Filter binding "' +
                        filter.filterId +
                        '": Include team needs ' +
                        field.bindingPath +
                        '.UserRoleId, which exceeds the ' +
                        MAX_PARENT_HOPS +
                        '-hop limit. Bind the filter to a shorter user-lookup path.',
                    filter.filterId,
                    field.bindingPath
                );
            }
        }

        /** The condition a Base filter contributes (compiled to `SOQL` through this scope's binds). */
        BoardCondition.Node compileBaseFilter(BaseFilter condition, ResolvedField field) {
            String path = field.path;
            String filterId = condition.id;
            switch on condition.operator {
                when 'IS_NULL' {
                    Boolean isNull = condition.value == null || String.valueOf(condition.value) != 'false';
                    return single(filterId, path, isNull ? 'EQ' : 'NEQ', null);
                }
                when 'EQ', 'NEQ', 'GT', 'GTE', 'LT', 'LTE' {
                    return inConfigCurrency(
                        compileComparison(path, condition.operator, condition.value, field, filterId),
                        field
                    );
                }
                when 'IN', 'NOT_IN' {
                    List<String> values = new List<String>();
                    if (condition.value instanceof List<Object>) {
                        for (Object item : (List<Object>) condition.value) {
                            values.add(item == null ? null : String.valueOf(item));
                        }
                    } else if (condition.value != null) {
                        values.add(String.valueOf(condition.value));
                    }
                    if (values.isEmpty()) {
                        throw BoardErrors.error(
                            BoardErrors.CONFIG_ERROR,
                            'Base filter requires at least one value.',
                            filterId,
                            field.bindingPath
                        );
                    }
                    return inConfigCurrency(
                        compileIn(path, field, values, condition.operator == 'NOT_IN', filterId),
                        field
                    );
                }
                when 'LIKE' {
                    if (!TEXT_FILTER_TYPES.contains(field.type) || condition.value == null) {
                        throw BoardErrors.error(
                            BoardErrors.CONFIG_ERROR,
                            'LIKE requires a text field and value.',
                            filterId,
                            field.bindingPath
                        );
                    }
                    String likePattern = String.valueOf(condition.value);
                    return single(
                        filterId,
                        path,
                        'LIKE',
                        likePattern.contains('%') ? likePattern : '%' + likePattern + '%'
                    );
                }
                when 'LITERAL' {
                    if (!DATE_TYPES.contains(field.type)) {
                        throw BoardErrors.error(
                            BoardErrors.CONFIG_ERROR,
                            'Relative date literals require a Date or DateTime field.',
                            filterId,
                            field.bindingPath
                        );
                    }
                    String literal = condition.value == null ? null : String.valueOf(condition.value);
                    return relativeDate(filterId, path, requireRelativeDate(literal, filterId, field.bindingPath));
                }
                when else {
                    throw BoardErrors.error(
                        BoardErrors.CONFIG_ERROR,
                        'Unsupported base filter operator: ' + condition.operator,
                        filterId,
                        field.bindingPath
                    );
                }
            }
        }

        /**
         * A Base filter amount on a currency field is written in the Config currency: it compiles to an ISO literal
         * (`Amount > EUR5000`), never a `HAVING`. An `IN` / `NOT_IN` list becomes one `=` per amount (ORed) / `!=` per
         * amount (ANDed), each an ISO literal; in memory each compares as its corporate amount. Single-currency orgs
         * and other fields: unchanged.
         */
        BoardCondition.Node inConfigCurrency(BoardCondition.Node node, ResolvedField field) {
            BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
            if (
                field.type != Schema.DisplayType.CURRENCY ||
                !converter.isMultiCurrency() ||
                !(node instanceof BoardCondition.Predicate)
            ) {
                return node;
            }
            BoardCondition.Predicate predicate = (BoardCondition.Predicate) node;
            if (predicate.operator == 'IN' || predicate.operator == 'NOT_IN') {
                Boolean negate = predicate.operator == 'NOT_IN';
                List<BoardCondition.Node> clauses = new List<BoardCondition.Node>();
                for (Object value : predicate.values) {
                    Object amount = value instanceof Decimal
                        ? converter.configAmountBound((Decimal) value, request)
                        : value;
                    clauses.add(single(predicate.filterId, predicate.path, negate ? 'NEQ' : 'EQ', amount));
                }
                return negate ? BoardCondition.allOf(clauses) : BoardCondition.anyOf(clauses);
            }
            if (!predicate.values.isEmpty() && predicate.values[0] instanceof Decimal) {
                predicate.values[0] = converter.configAmountBound((Decimal) predicate.values[0], request);
            }
            return predicate;
        }

        BoardCondition.Node compileComparison(
            String path,
            String operator,
            Object rawValue,
            ResolvedField field,
            String filterId
        ) {
            if (rawValue == null) {
                if (operator != 'EQ' && operator != 'NEQ') {
                    throw BoardErrors.error(
                        BoardErrors.CONFIG_ERROR,
                        operator + ' requires a value.',
                        filterId,
                        field.bindingPath
                    );
                }
                return single(filterId, path, operator, null);
            }
            String text = String.valueOf(rawValue);
            if (field.type == Schema.DisplayType.DATETIME && ISO_DATE_PATTERN.matcher(text).matches()) {
                // A whole user-time-zone day on a DateTime field.
                Object dayStart = dateBound(text, field, false, filterId);
                Object dayEnd = dateBound(text, field, true, filterId);
                switch on operator {
                    when 'EQ' {
                        return BoardCondition.allOf(
                            new List<BoardCondition.Node>{
                                single(filterId, path, 'GTE', dayStart),
                                single(filterId, path, 'LTE', dayEnd)
                            }
                        );
                    }
                    when 'NEQ' {
                        return BoardCondition.anyOf(
                            new List<BoardCondition.Node>{
                                single(filterId, path, 'LT', dayStart),
                                single(filterId, path, 'GT', dayEnd)
                            }
                        );
                    }
                    when 'GT' {
                        return single(filterId, path, 'GT', dayEnd);
                    }
                    when 'GTE' {
                        return single(filterId, path, 'GTE', dayStart);
                    }
                    when 'LT' {
                        return single(filterId, path, 'LT', dayStart);
                    }
                    when else {
                        return single(filterId, path, 'LTE', dayEnd);
                    }
                }
            }
            return typed(filterId, path, operator, coerce(rawValue, field, filterId), field);
        }

        BoardCondition.Node compileIn(
            String path,
            ResolvedField field,
            List<String> values,
            Boolean negate,
            String filterId
        ) {
            if (field.type == Schema.DisplayType.MULTIPICKLIST) {
                List<Object> tokens = new List<Object>();
                for (String value : values) {
                    tokens.add(value);
                }
                return BoardCondition.field(filterId, path, negate ? 'EXCLUDES' : 'INCLUDES', tokens);
            }
            if (field.type == Schema.DisplayType.BOOLEAN) {
                List<BoardCondition.Node> clauses = new List<BoardCondition.Node>();
                for (String value : values) {
                    clauses.add(single(filterId, path, negate ? 'NEQ' : 'EQ', coerce(value, field, filterId)));
                }
                return negate ? BoardCondition.allOf(clauses) : BoardCondition.anyOf(clauses);
            }
            Boolean isWholeNumberField = isWholeNumberType(field.type);
            List<Object> coerced = isWholeNumberField ? new List<Object>() : typedList(field.type);
            for (String value : values) {
                coerced.add(coerce(value, field, filterId));
            }
            String operator = negate ? 'NOT_IN' : 'IN';
            if (isWholeNumberField) {
                return BoardCondition.wholeNumberField(
                    filterId,
                    path,
                    operator,
                    coerced,
                    field.type == Schema.DisplayType.LONG
                );
            }
            return BoardCondition.field(filterId, path, operator, coerced);
        }

        BoardCondition.Predicate single(String filterId, String path, String operator, Object value) {
            return BoardCondition.field(filterId, path, operator, new List<Object>{ value });
        }

        /** `single`, or on an Integer / Long field its whole-number form (`BoardCondition.wholeNumberField`). */
        BoardCondition.Node typed(String filterId, String path, String operator, Object value, ResolvedField field) {
            if (!isWholeNumberType(field.type)) {
                return single(filterId, path, operator, value);
            }
            return BoardCondition.wholeNumberField(
                filterId,
                path,
                operator,
                new List<Object>{ value },
                field.type == Schema.DisplayType.LONG
            );
        }

        BoardCondition.Predicate relativeDate(String filterId, String path, String literal) {
            return single(filterId, path, 'RELATIVE_DATE', literal);
        }

        /** A `LIKE` on user text already escaped by `BoardDescribe.escapeLike`. */
        BoardCondition.Predicate escapedLike(String filterId, String path, String likePattern) {
            BoardCondition.Predicate condition = single(filterId, path, 'LIKE', likePattern);
            condition.escapedPattern = true;
            return condition;
        }
    }

    /**
     * `SOSL` `WHERE` literal of a typed bind value (or list of them), or null when it has none. Strings are quoted
     * with `\` and `'` escaped; escaped `LIKE` patterns (`isLikePattern`) already pair every `\`, so only `'` is
     * escaped to keep their `\%` / `\_` / `\\` sequences.
     */
    private static String searchLiteral(Object value, Boolean isLikePattern) {
        if (value == null) {
            return 'null';
        }
        if (value instanceof List<Object>) {
            List<String> items = new List<String>();
            for (Object item : (List<Object>) value) {
                String literal = item == null ? null : searchLiteral(item, isLikePattern);
                if (literal == null) {
                    return null;
                }
                items.add(literal);
            }
            return items.isEmpty() ? null : '(' + String.join(items, ', ') + ')';
        }
        if (value instanceof Id) {
            return '\'' + String.valueOf(value) + '\'';
        }
        if (value instanceof String) {
            String text = (String) value;
            if (!isLikePattern) {
                text = text.replace('\\', '\\\\');
            }
            return '\'' + text.replace('\'', '\\\'') + '\'';
        }
        if (value instanceof Boolean || value instanceof Integer || value instanceof Long) {
            return String.valueOf(value);
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).toPlainString();
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        }
        if (value instanceof Date) {
            return String.valueOf((Date) value);
        }
        return null;
    }

    /** One object a `SOSL` text search covers: the Widget object (`SELF`) or a child via its foreign key. */
    private class SearchTarget {
        Schema.DescribeSObjectResult describe;
        /** Child reference field pointing at the Widget object; null for `SELF`. */
        String foreignKey;

        SearchTarget(Schema.DescribeSObjectResult describe, String foreignKey) {
            this.describe = describe;
            this.foreignKey = foreignKey;
        }

        String selectList() {
            return foreignKey == null ? 'Id' : 'Id, ' + foreignKey;
        }
    }

    /** A Filter binding resolved by the Widget: one active filter plus the field path it binds to. */
    private class FilterBinding {
        String filterId;
        String type;
        String fieldPath;
        Boolean explicit;
        String operator;
        List<String> values = new List<String>();
        String token;
        String literal;
        String fromValue;
        String toValue;
        String text;
        String targetObjectApiName;
        /** The filter's Step 1 convention hint (Widgets resolve Step 1 against it). */
        String fieldApiName;
        /** `TEXT` `minCharacters` (null when not sent). */
        Integer minCharacters;
        /** `USER` match mode: `users` (default) or `usersAndTeam`. */
        String matchMode;
        /** `BUCKET`: the config of the Bucket field the Widget's Filter binding maps the filter to. */
        Object bucketField;

        FilterBinding(Object raw) {
            Map<String, Object> source = asMap(raw);
            filterId = getString(source, 'filterId');
            type = upper(getString(source, 'type'));
            fieldPath = getString(source, 'fieldPath');
            explicit = source.get('explicit') == true;
            operator = String.isBlank(getString(source, 'operator')) ? 'IN' : upper(getString(source, 'operator'));
            for (Object value : getList(source, 'values')) {
                if (value != null && String.isNotBlank(String.valueOf(value))) {
                    values.add(String.valueOf(value));
                }
            }
            token = upper(getString(source, 'token'));
            literal = getString(source, 'literal');
            fromValue = getString(source, 'from');
            toValue = getString(source, 'to');
            text = getString(source, 'text');
            targetObjectApiName = getString(source, 'targetObjectApiName');
            fieldApiName = getString(source, 'fieldApiName');
            matchMode = getString(source, 'matchMode');
            bucketField = source.get('bucketField');
            Object rawMinimum = source.get('minCharacters');
            if (rawMinimum instanceof Integer) {
                minCharacters = (Integer) rawMinimum;
            } else if (rawMinimum instanceof Decimal) {
                minCharacters = ((Decimal) rawMinimum).intValue();
            }
        }

        Boolean hasSelection() {
            switch on operator {
                when 'IN' {
                    return !values.isEmpty() || token == TOKEN_ME;
                }
                when 'LITERAL' {
                    return String.isNotBlank(literal);
                }
                when 'BETWEEN' {
                    return String.isNotBlank(fromValue) || String.isNotBlank(toValue);
                }
                when 'GTE' {
                    return String.isNotBlank(fromValue);
                }
                when 'LTE' {
                    return String.isNotBlank(toValue);
                }
                when 'CONTAINS', 'STARTS_WITH', 'SOSL' {
                    return String.isNotBlank(text);
                }
                when else {
                    return true;
                }
            }
        }

        Boolean isTextSearch() {
            return operator == 'CONTAINS' || operator == 'STARTS_WITH' || operator == 'SOSL';
        }

        /** Shortest term the server searches: `minCharacters`, never below `MIN_SEARCH_CHARACTERS`. */
        Integer minimumCharacters() {
            return minCharacters == null ? MIN_SEARCH_CHARACTERS : Math.max(MIN_SEARCH_CHARACTERS, minCharacters);
        }

        /** A `USER` filter in Team match mode: each picked user's Team instead of only the user. */
        Boolean matchesTeams() {
            return type == 'USER' && matchMode == MATCH_MODE_TEAM;
        }

        List<String> effectiveValues() {
            List<String> effective = new List<String>(values);
            if (token == TOKEN_ME) {
                effective.add(UserInfo.getUserId());
            }
            return effective;
        }
    }

    /**
     * A Widget's static base filter entry: a condition (`BaseFilterCondition`) or, when it has `conditions`, an AND /
     * OR group (`{ id, logic, conditions[] }`) of further entries.
     */
    private class BaseFilter {
        String id;
        String fieldPath;
        String operator;
        Object value;
        Boolean isGroup;
        String logic;
        List<BaseFilter> children = new List<BaseFilter>();

        BaseFilter(Object raw) {
            Map<String, Object> source = asMap(raw);
            id = getString(source, 'id');
            fieldPath = getString(source, 'fieldPath');
            operator = upper(getString(source, 'operator'));
            value = source.get('value');
            isGroup = source.containsKey('conditions');
            logic = upper(getString(source, 'logic'));
            for (Object child : getList(source, 'conditions')) {
                children.add(new BaseFilter(child));
            }
        }
    }

    /** A compiled condition: its node, its `SOQL` (semi-joins included), and whether `SOSL` `WHERE` can apply it. */
    private class CompiledCondition {
        BoardCondition.Node node;
        String soql;
        Boolean isSearchSafe;

        CompiledCondition(BoardCondition.Node node, String soql, Boolean isSearchSafe) {
            this.node = node;
            this.soql = soql;
            this.isSearchSafe = isSearchSafe;
        }
    }

    /** A field path resolved against describes with canonical API names. */
    public class ResolvedField {
        public String path;
        String bindingPath;
        public Schema.DescribeFieldResult describe;
        public Schema.DisplayType type;
        String childObject;
        String foreignKey;

        ResolvedField(String path, String bindingPath, Schema.DescribeFieldResult describe) {
            this.path = path;
            this.bindingPath = bindingPath;
            this.describe = describe;
            this.type = describe.getType();
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Field path resolution & type rules
    // ---------------------------------------------------------------------------------------------------------

    public static ResolvedField resolveFieldPath(
        Schema.DescribeSObjectResult rootDescribe,
        String path,
        String filterId,
        String bindingPath
    ) {
        List<String> segments = path.split('\\.', -1);
        if (segments.size() - 1 > MAX_PARENT_HOPS) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Field paths can traverse at most ' + MAX_PARENT_HOPS + ' parent relationships: ' + bindingPath,
                filterId,
                bindingPath
            );
        }
        Schema.DescribeSObjectResult current = rootDescribe;
        List<String> canonical = new List<String>();
        for (Integer i = 0; i < segments.size() - 1; i++) {
            Schema.SObjectField reference = relationshipIndex(current).get(segments[i].toLowerCase());
            if (reference == null) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Unknown relationship ' + segments[i] + ' on ' + current.getName(),
                    filterId,
                    bindingPath
                );
            }
            Schema.DescribeFieldResult referenceDescribe = BoardDescribe.requireReadableField(
                current.getName(),
                reference.getDescribe(),
                filterId,
                bindingPath
            );
            current = BoardDescribe.describeObject(parentType(referenceDescribe));
            if (!BoardDescribe.isReadableObject(current)) {
                throw BoardErrors.error(
                    BoardErrors.ACCESS_ERROR,
                    'You do not have access to the object ' + current.getName(),
                    filterId,
                    bindingPath
                );
            }
            canonical.add(referenceDescribe.getRelationshipName());
        }
        String leaf = segments[segments.size() - 1];
        Schema.SObjectField field = String.isBlank(leaf) ? null : current.fields.getMap().get(leaf);
        if (field == null) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Unknown field: ' + current.getName() + '.' + leaf,
                filterId,
                bindingPath
            );
        }
        Schema.DescribeFieldResult fieldDescribe = BoardDescribe.requireReadableField(
            current.getName(),
            field.getDescribe(),
            filterId,
            bindingPath
        );
        canonical.add(fieldDescribe.getName());
        return new ResolvedField(String.join(canonical, '.'), bindingPath, fieldDescribe);
    }

    /** Parent object of a reference hop; polymorphic lookups (e.g. `Owner`) prefer `User`. */
    public static Schema.SObjectType parentType(Schema.DescribeFieldResult referenceDescribe) {
        List<Schema.SObjectType> targets = referenceDescribe.getReferenceTo();
        for (Schema.SObjectType target : targets) {
            if (target == User.SObjectType) {
                return target;
            }
        }
        return targets[0];
    }

    public static Map<String, Schema.SObjectField> relationshipIndex(Schema.DescribeSObjectResult objectDescribe) {
        String cacheKey = objectDescribe.getName().toLowerCase();
        Map<String, Schema.SObjectField> index = RELATIONSHIP_INDEX_CACHE.get(cacheKey);
        if (index == null) {
            index = new Map<String, Schema.SObjectField>();
            for (Schema.SObjectField field : objectDescribe.fields.getMap().values()) {
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                if (
                    fieldDescribe.getType() == Schema.DisplayType.REFERENCE &&
                    fieldDescribe.getRelationshipName() != null
                ) {
                    index.put(fieldDescribe.getRelationshipName().toLowerCase(), field);
                }
            }
            RELATIONSHIP_INDEX_CACHE.put(cacheKey, index);
        }
        return index;
    }

    private static Boolean referencesObject(Schema.DescribeFieldResult fieldDescribe, String objectApiName) {
        for (Schema.SObjectType target : fieldDescribe.getReferenceTo()) {
            if (BoardDescribe.describeObject(target).getName().equalsIgnoreCase(objectApiName)) {
                return true;
            }
        }
        return false;
    }

    private static void requireFilterCompatible(FilterBinding filter, ResolvedField field) {
        Boolean compatible;
        switch on filter.operator {
            when 'IN' {
                if (filter.type == 'PICKLIST') {
                    compatible = PICKLIST_FILTER_TYPES.contains(field.type);
                } else {
                    String target = filter.type == 'USER' ? 'User' : filter.targetObjectApiName;
                    compatible =
                        field.type == Schema.DisplayType.ID ||
                        (field.type == Schema.DisplayType.REFERENCE &&
                        (String.isBlank(target) ||
                        referencesObject(field.describe, target) ||
                        (filter.type == 'USER' && referencesObject(field.describe, 'Group'))));
                }
            }
            when 'LITERAL' {
                compatible = DATE_TYPES.contains(field.type);
            }
            when 'BETWEEN', 'GTE', 'LTE' {
                compatible = filter.type == NUMBER_RANGE
                    ? BoardDescribe.NUMERIC_TYPES.contains(field.type)
                    : DATE_TYPES.contains(field.type);
            }
            when 'CONTAINS', 'STARTS_WITH' {
                compatible = TEXT_FILTER_TYPES.contains(field.type);
            }
            when 'EMPTY', 'FILLED' {
                // Any filterable field (resolveBinding already rejects non-filterable ones, e.g. Long Text Area).
                compatible = true;
            }
            when else {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Unsupported filter operator: ' + filter.operator,
                    filter.filterId,
                    field.bindingPath
                );
            }
        }
        if (!compatible) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'A ' + filter.type + ' filter cannot bind to ' + field.type.name() + ' field ' + field.bindingPath,
                filter.filterId,
                field.bindingPath
            );
        }
    }

    private static String requireRelativeDate(String literal, String filterId, String fieldPath) {
        String normalized = literal == null ? '' : literal.trim().toUpperCase();
        if (!BoardCondition.isRelativeDate(normalized)) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Invalid relative date literal: ' + literal,
                filterId,
                fieldPath
            );
        }
        return normalized;
    }

    /** ISO `YYYY-MM-DD` bound; on DateTime fields expands to the user-timezone day start or end. */
    private static Object dateBound(String isoDate, ResolvedField field, Boolean endOfDay, String filterId) {
        String value = isoDate.trim();
        if (!ISO_DATE_PATTERN.matcher(value).matches()) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Invalid date (expected YYYY-MM-DD): ' + value,
                filterId,
                field.bindingPath
            );
        }
        Date day;
        try {
            day = Date.valueOf(value);
        } catch (Exception invalidDate) {
            throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Invalid date: ' + value, filterId, field.bindingPath);
        }
        if (field.type != Schema.DisplayType.DATETIME) {
            return day;
        }
        return endOfDay
            ? Datetime.newInstance(day, Time.newInstance(23, 59, 59, 999))
            : Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0));
    }

    /** Bind list whose runtime element type matches the field, as SOQL `IN` binds require. */
    private static List<Object> typedList(Schema.DisplayType fieldType) {
        if (ID_TYPES.contains(fieldType)) {
            return new List<Id>();
        }
        if (BoardDescribe.NUMERIC_TYPES.contains(fieldType)) {
            return new List<Decimal>();
        }
        if (fieldType == Schema.DisplayType.DATE) {
            return new List<Date>();
        }
        if (fieldType == Schema.DisplayType.DATETIME) {
            return new List<Datetime>();
        }
        return new List<String>();
    }

    /** Integer and Long fields: `SOQL` rejects a Decimal bind on them (`BoardCondition.wholeNumberField`). */
    private static Boolean isWholeNumberType(Schema.DisplayType fieldType) {
        return fieldType == Schema.DisplayType.INTEGER || fieldType == Schema.DisplayType.LONG;
    }

    private static Object coerce(Object rawValue, ResolvedField field, String filterId) {
        if (rawValue == null) {
            return null;
        }
        String text = String.valueOf(rawValue).trim();
        try {
            if (field.type == Schema.DisplayType.BOOLEAN) {
                if (text != 'true' && text != 'false') {
                    throw new TypeException();
                }
                return Boolean.valueOf(text);
            }
            if (BoardDescribe.NUMERIC_TYPES.contains(field.type)) {
                return Decimal.valueOf(text);
            }
            if (field.type == Schema.DisplayType.DATE) {
                return Date.valueOf(text);
            }
            if (field.type == Schema.DisplayType.DATETIME) {
                return (Datetime) JSON.deserialize('"' + text + '"', Datetime.class);
            }
            if (ID_TYPES.contains(field.type)) {
                Id recordId = BoardDescribe.toId(text);
                if (recordId == null) {
                    throw new TypeException();
                }
                return recordId;
            }
        } catch (Exception invalidValue) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Invalid value "' + text + '" for ' + field.type.name() + ' field ' + field.bindingPath,
                filterId,
                field.bindingPath
            );
        }
        return String.valueOf(rawValue);
    }

    // ---------------------------------------------------------------------------------------------------------
    // Request parsing & errors
    // ---------------------------------------------------------------------------------------------------------

    /** The request JSON as a map; malformed JSON or a non-object is a CONFIG_ERROR. */
    public static Map<String, Object> parseRequest(String requestJson) {
        try {
            return asMap(JSON.deserializeUntyped(requestJson));
        } catch (Exception malformed) {
            throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Malformed widget query request.', null, null);
        }
    }

    public static Map<String, Object> asMap(Object raw) {
        if (!(raw instanceof Map<String, Object>)) {
            throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Malformed widget query request.', null, null);
        }
        return (Map<String, Object>) raw;
    }

    public static List<Object> getList(Map<String, Object> source, String key) {
        Object value = source.get(key);
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }

    public static String getString(Map<String, Object> source, String key) {
        Object value = source.get(key);
        return value == null ? null : String.valueOf(value);
    }

    public static Integer getInteger(Map<String, Object> source, String key) {
        Object value = source.get(key);
        return value == null ? null : Integer.valueOf(value);
    }

    /** A numeric value as a Decimal (null stays null); a non-number throws a `TypeException`. */
    public static Decimal toDecimal(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof Decimal) {
            return (Decimal) raw;
        }
        if (raw instanceof Integer) {
            return Decimal.valueOf((Integer) raw);
        }
        if (raw instanceof Long) {
            return Decimal.valueOf((Long) raw);
        }
        if (raw instanceof Double) {
            return Decimal.valueOf((Double) raw);
        }
        return Decimal.valueOf(String.valueOf(raw).trim());
    }

    /** `toDecimal`, but null for a non-number (e.g. a date MIN/MAX or text). */
    public static Decimal toDecimalOrNull(Object raw) {
        try {
            return toDecimal(raw);
        } catch (TypeException notNumeric) {
            return null;
        }
    }

    private static String upper(String value) {
        return value == null ? null : value.trim().toUpperCase();
    }

    // ---------------------------------------------------------------------------------------------------------
    // DTOs
    // ---------------------------------------------------------------------------------------------------------

    /** Fields of a Metric result: binding outcome, row count, and the cursor tier hand-off. */
    public virtual class AggregateQueryResult {
        @AuraEnabled
        public String aggregateFunction;
        /** `Schema.DisplayType` name of the value field (null for `COUNT`). */
        @AuraEnabled
        public String valueType;
        /** ISO code of a currency `value` (Display currency); null when the value is not an amount. */
        @AuraEnabled
        public String currencyIsoCode;
        /** Matching row count (null for `MIN`/`MAX`). */
        @AuraEnabled
        public Integer totalRows;
        /** `SINGLE` (one-call aggregate) or `CURSOR` (multi-call chunked aggregation). */
        @AuraEnabled
        public String mode = MODE_SINGLE;
        @AuraEnabled
        public Boolean isComplete = true;
        /** First cursor chunk when `mode == 'CURSOR'`. */
        @AuraEnabled
        public AggregateChunk chunk;
        @AuraEnabled
        public List<String> appliedFilterIds;
        @AuraEnabled
        public List<String> ignoredFilterIds;

        AggregateQueryResult(String aggregateFunction, QueryScope scope) {
            this.aggregateFunction = aggregateFunction;
            this.appliedFilterIds = scope.appliedFilterIds;
            this.ignoredFilterIds = scope.ignoredFilterIds;
        }

        AggregateQueryResult() {
        }

        void useCursor(AggregateChunk firstChunk) {
            mode = MODE_CURSOR;
            chunk = firstChunk;
            isComplete = firstChunk.isComplete;
        }
    }

    public class MetricResult extends AggregateQueryResult {
        /** Aggregate value (null when no rows match AVG/MIN/MAX, or while `mode == 'CURSOR'`). */
        @AuraEnabled
        public Object value;
        /** The request's `thresholdAmounts` (Config currency) in the Display currency; as entered for non-amounts. */
        @AuraEnabled
        public List<Decimal> thresholdAmounts;
        /** The request's `gaugeAmounts` (Gauge static minimum, maximum; Config currency) like `thresholdAmounts`. */
        @AuraEnabled
        public List<Decimal> gaugeAmounts;
        /** Measures list: one result per Measure (hidden included), in Measure order; null on each Measure's result. */
        @AuraEnabled
        public List<MetricResult> measures;
        /** Measures list: index in `measures` of the visible Measure, whose result this is. */
        @AuraEnabled
        public Integer visibleIndex;
        /** Measures list: one per Cross-object measure (`BoardCrossObjectMeasures`); null without any. */
        @AuraEnabled
        public List<BoardCrossObjectMeasures.Notice> crossObjectNotices;

        public MetricResult(String aggregateFunction, QueryScope scope) {
            super(aggregateFunction, scope);
        }

        /** An empty result, filled by `BoardMetricQuery` from the visible Measure's result. */
        public MetricResult() {
            super();
        }
    }

    public class AggregateChunk {
        /** Serialized `Database.Cursor` handle to pass back to `fetchAggregateChunk`. */
        @AuraEnabled
        public String cursor;
        @AuraEnabled
        public Integer offset;
        @AuraEnabled
        public Integer nextOffset;
        @AuraEnabled
        public Integer totalRows;
        @AuraEnabled
        public Boolean isComplete;
        /** Partial aggregates for this chunk only (one ungrouped bucket for Metric). */
        @AuraEnabled
        public List<BoardChartEngine.Partial> buckets;
    }

    public class ChartDimensionInfo {
        /** Canonical field path that was grouped. */
        @AuraEnabled
        public String fieldPath;
        /** Name field path used for Reference labels (e.g. `Account.Name`), else null. */
        @AuraEnabled
        public String labelFieldPath;
        @AuraEnabled
        public String dataType;
        /** Effective date bucket granularity for Date/DateTime fields (default `DAY`), else null. */
        @AuraEnabled
        public String dateGranularity;
        /** Active picklist values in describe order (for `PICKLIST_ORDER` sorting); empty for other types. */
        @AuraEnabled
        public List<String> picklistOrder;
    }

    /** A resolved Table column: canonical paths and describe facts the Table renders and sorts by. */
    public class TableColumn {
        @AuraEnabled
        public String id;
        /** Canonical field path (key into `TableRow.values`). */
        @AuraEnabled
        public String fieldPath;
        /** Default header label from describe (the Widget prefers an admin `label`). */
        @AuraEnabled
        public String label;
        /** `Schema.DisplayType` name of the leaf field. */
        @AuraEnabled
        public String dataType;
        @AuraEnabled
        public Boolean isSortable;
        @AuraEnabled
        public Boolean isNameField;
        /** Record ID path the cell links to (`Id`, `AccountId`, `Account.OwnerId`), or null for no link. */
        @AuraEnabled
        public String linkPath;
        /** Currency columns: the Display currency their cells are converted to; null for any other column. */
        @AuraEnabled
        public String currencyIsoCode;
        /** Paths fetched for this column instead of `fieldPath` and `linkPath` (a Bucket field column's rule fields). */
        public List<String> fetchPaths;

        /** An empty column, filled by its builder (see `BoardTableBucketColumns.column`). */
        public TableColumn() {
        }

        public TableColumn(Schema.DescribeSObjectResult objectDescribe, Map<String, Object> config) {
            id = getString(config, 'id');
            String rawPath = getString(config, 'fieldPath');
            if (String.isBlank(rawPath)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Table column ' + id + ' has no field path.',
                    null,
                    null
                );
            }
            ResolvedField field = BoardTableQuery.resolveTablePath(objectDescribe, rawPath);
            fieldPath = field.path;
            dataType = field.type.name();
            isSortable = field.describe.isSortable();
            isNameField = field.describe.isNameField();
            label = field.describe.getLabel();
            if (String.isBlank(id)) {
                id = fieldPath;
            }

            String linkMode = String.isBlank(getString(config, 'linkToRecord'))
                ? 'auto'
                : getString(config, 'linkToRecord').trim().toLowerCase();
            Boolean primaryName =
                isNameField || BoardTableQuery.PRIMARY_NAME_FIELDS.contains(field.describe.getName().toLowerCase());
            if (linkMode == 'always' || (linkMode == 'auto' && primaryName)) {
                linkPath = BoardTableQuery.recordIdPath(objectDescribe, fieldPath);
            }
        }
    }

    /** A Row action's resolved target: the record Id path fetched with each row (never shown as a column). */
    public class RowActionTarget {
        @AuraEnabled
        public String id;
        /** Key into `TableRow.values` holding the target record Id (`Id` = the row's own record). */
        @AuraEnabled
        public String targetPath;
        /** Object the target Id belongs to, or null when the lookup is polymorphic. */
        @AuraEnabled
        public String targetObjectApiName;
        /** Create actions: resolved paths of the row fields their default values map from (keys into `TableRow.values`). */
        @AuraEnabled
        public List<String> fieldPaths = new List<String>();
    }

    /** One Table record: `id` plus flattened `path -> value` for every selected column and link path. */
    public class TableRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Map<String, Object> values = new Map<String, Object>();

        public TableRow(SObject record) {
            id = record.Id;
            BoardTableQuery.flattenRecord(record, '', values);
        }
    }

    /** One `Database.PaginationCursor` page. */
    public virtual class TablePage {
        /** Serialized cursor handle to pass back to `fetchTablePage`. */
        @AuraEnabled
        public String paginationCursor;
        @AuraEnabled
        public List<TableRow> rows = new List<TableRow>();
        @AuraEnabled
        public Integer start;
        /** Cursor position of the next page (guarded against `getNextIndex()` wrapping to 0 at the end). */
        @AuraEnabled
        public Integer nextIndex;
        @AuraEnabled
        public Boolean hasMore;
        /** Rows the cursor spans (`getNumRecords()`, at most `BoardTableQuery.TABLE_MAX_ROWS`). */
        @AuraEnabled
        public Integer totalCount;
        /** Rows deleted since the cursor opened that this page skipped. */
        @AuraEnabled
        public Integer deletedRows;
        /** Row grouping: the groups of this page's rows in row order, with full-group counts; null when ungrouped. */
        @AuraEnabled
        public List<BoardTableEngine.TableGroup> groups;
    }

    /** Largest and smallest value of a Data bar column over the whole scope; null when no record has a value. */
    public class BarScale {
        @AuraEnabled
        public String columnId;
        @AuraEnabled
        public Decimal max;
        @AuraEnabled
        public Decimal min;
    }

    /** First Table page plus resolved columns, effective sort, and binding outcome. */
    public class TableResult extends TablePage {
        @AuraEnabled
        public List<TableColumn> columns = new List<TableColumn>();
        /** Canonical sort path (null for the default `Id ASC` order). */
        @AuraEnabled
        public String sortBy;
        @AuraEnabled
        public String sortDirection;
        /** Row limit applied to this Table; null when unlimited. `totalCount` is then the full matching count. */
        @AuraEnabled
        public Integer rowLimit;
        /**
         * Row limit of a grouped Table when it cut first-level groups (the "Top N groups" badge); null otherwise. `totalCount`
         * then counts the records of the shown groups.
         */
        @AuraEnabled
        public Integer groupLimit;
        /**
         * Total row: one entry per column with Stacked summaries (whole scope, or the shown rows under a Row limit);
         * null when the Total row is off or `totalRowUnavailable`.
         */
        @AuraEnabled
        public List<BoardTableEngine.ColumnTotal> totals;
        /** True when the scope spans too many records to total in one request; the Total row then shows why. */
        @AuraEnabled
        public Boolean totalRowUnavailable = false;
        /** Resolved Row action targets, in request order. */
        @AuraEnabled
        public List<RowActionTarget> rowActions = new List<RowActionTarget>();
        /** Data bar scale per Data bar column over the whole scope (matching records, ignoring paging and Row limit). */
        @AuraEnabled
        public List<BarScale> barScales = new List<BarScale>();
        /** Detail rows off: every Group row of the aggregated table, in order; null otherwise. */
        @AuraEnabled
        public List<BoardTableAggregate.GroupRow> aggregateGroups;
        /**
         * Detail rows off, cursor tier: where the chunked load stands (`fetchTableAggregateChunk` continues it until
         * `isComplete`); null in the SOQL tier.
         */
        @AuraEnabled
        public BoardTableAggregateCursor.Progress aggregateCursor;

        /** Row grouping: the resolved group field (null when ungrouped). */
        @AuraEnabled
        public BoardTableGrouping.GroupField groupField;
        @AuraEnabled
        public List<String> appliedFilterIds;
        @AuraEnabled
        public List<String> ignoredFilterIds;

        public TableResult(QueryScope scope) {
            appliedFilterIds = scope.appliedFilterIds;
            ignoredFilterIds = scope.ignoredFilterIds;
        }

        public void copyPage(TablePage page) {
            paginationCursor = page.paginationCursor;
            rows = page.rows;
            start = page.start;
            nextIndex = page.nextIndex;
            hasMore = page.hasMore;
            totalCount = page.totalCount;
            deletedRows = page.deletedRows;
        }
    }
}