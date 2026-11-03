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
    /** Rows fetched per `Database.Cursor` chunk call. */
    @TestVisible
    private static Integer CURSOR_CHUNK_SIZE = 40000;
    /** Max matching rows for multi-call `Database.Cursor` chunked aggregation. */
    @TestVisible
    private static Integer CURSOR_MAX_ROWS = 200000;
    /**
     * Max group/stack combinations returned by one Bar Chart `GROUP BY` query (largest values first). A capped
     * result re-runs through the `Database.Cursor` tier when it can (see `runBar`).
     */
    @TestVisible
    private static Integer BAR_GROUP_LIMIT = 2000;

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

    private static final Set<String> AGGREGATE_FUNCTIONS = new Set<String>{
        'COUNT',
        'COUNT_DISTINCT',
        'SUM',
        'AVG',
        'MIN',
        'MAX'
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
    private static final Map<String, String> COMPARISON_SYMBOLS = new Map<String, String>{
        'EQ' => '=',
        'NEQ' => '!=',
        'GT' => '>',
        'GTE' => '>=',
        'LT' => '<',
        'LTE' => '<='
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
    private static final Pattern RELATIVE_DATE_PATTERN = Pattern.compile(
        '^(YESTERDAY|TODAY|TOMORROW|(LAST|THIS|NEXT)_(WEEK|MONTH|QUARTER|YEAR|FISCAL_QUARTER|FISCAL_YEAR)' +
            '|(LAST|NEXT)_90_DAYS|(LAST|NEXT)_N_(DAYS|WEEKS|MONTHS|QUARTERS|YEARS|FISCAL_QUARTERS|FISCAL_YEARS):\\d{1,4}' +
            '|N_(DAYS|WEEKS|MONTHS|QUARTERS|YEARS|FISCAL_QUARTERS|FISCAL_YEARS)_AGO:\\d{1,4})$'
    );

    // Transaction-scoped describe caches (keys are lower-cased API names).
    private static final Map<String, Map<String, Schema.SObjectField>> RELATIONSHIP_INDEX_CACHE = new Map<String, Map<String, Schema.SObjectField>>();
    private static Organization fiscalSettings;

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
     */
    @AuraEnabled(cacheable=true)
    public static MetricResult queryMetric(String requestJson) {
        try {
            Map<String, Object> request = parseRequest(requestJson);
            QueryScope scope = new QueryScope(request);
            return runMetric(scope, request);
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    /**
     * Computes Bar Chart buckets grouped by `groupByField` and an optional `stackByField`.
     *
     * Request: `{ objectApiName, groupByField, dateGranularity, stackByField, includeNullBucket, aggregateFunction,
     * valueFieldApiName, filters[], baseFilters[], refreshToken }`.
     * - Reference group fields also group by the target's name field (`AccountId` → `Account.Name`) for labels.
     * - Date/DateTime group fields bucket by `dateGranularity` (default `DAY`) via SOQL date functions in the user's
     *   time zone.
     * - `COUNT` always runs one `GROUP BY` query; `SUM`, `AVG`, `MIN`, `MAX`, `COUNT_DISTINCT` do so when the matching
     *   row count is `<= CURSOR_AGGREGATE_THRESHOLD`. `SUM`/`AVG`/`MIN`/`MAX` up to `CURSOR_MAX_ROWS` rows switch to
     *   `Database.Cursor` chunks (`mode: 'CURSOR'`) whose grouped partial buckets the caller merges via
     *   `fetchAggregateChunk`; larger scopes fail with `LIMIT_EXCEEDED`.
     * - A `GROUP BY` result capped at `BAR_GROUP_LIMIT` combinations re-runs through the cursor tier (`COUNT` buckets
     *   then carry `sum == count ==` matching rows) when the scope spans `<= CURSOR_MAX_ROWS` rows; otherwise (and
     *   always for `COUNT_DISTINCT`) the capped buckets are returned with `hasMoreGroups: true`.
     * Sorting, `maxBars`, and series/bar overflow are applied by the caller over the returned buckets.
     */
    @AuraEnabled(cacheable=true)
    public static BarResult queryBar(String requestJson) {
        try {
            Map<String, Object> request = parseRequest(requestJson);
            QueryScope scope = new QueryScope(request);
            return runBar(scope, request);
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    /**
     * Fetches and aggregates the next `CURSOR_CHUNK_SIZE` rows of a cursor opened by a previous query call.
     *
     * Request: the original query request plus `{ cursor, offset }`. Each call returns only that chunk's partial
     * `{ sum, count, min, max }` buckets (one per group/stack combination for Bar requests, which carry a
     * `groupByField`; `COUNT` buckets add 1 per row); the caller merges chunks until `isComplete`.
     */
    @AuraEnabled(cacheable=true)
    public static AggregateChunk fetchAggregateChunk(String requestJson) {
        try {
            Map<String, Object> request = parseRequest(requestJson);
            Schema.DescribeSObjectResult objectDescribe = BoardDescribe.requireReadableObject(
                getString(request, 'objectApiName')
            );
            // Grouped COUNT cursors (Bar fallback) count rows; every other aggregate reads its value field.
            String valuePath = parseAggregateFunction(request) == 'COUNT'
                ? null
                : resolveValueField(objectDescribe, getString(request, 'valueFieldApiName')).path;
            BarGrouping grouping = String.isBlank(getString(request, 'groupByField'))
                ? null
                : new BarGrouping(objectDescribe, request);
            Integer offset = getInteger(request, 'offset');
            return fetchChunk(
                deserializeCursor(getString(request, 'cursor')),
                offset == null ? 0 : offset,
                valuePath,
                grouping
            );
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Metric execution
    // ---------------------------------------------------------------------------------------------------------

    private static MetricResult runMetric(QueryScope scope, Map<String, Object> request) {
        String aggregateFunction = parseAggregateFunction(request);
        MetricResult result = new MetricResult(aggregateFunction, scope);
        if (aggregateFunction == 'COUNT') {
            Integer totalRows = scope.countRows();
            result.value = totalRows;
            result.totalRows = totalRows;
            return result;
        }

        ResolvedField valueField = resolveValueField(scope.objectDescribe, getString(request, 'valueFieldApiName'));
        requireAggregatable(aggregateFunction, valueField);
        result.valueType = valueField.type.name();

        if (aggregateFunction == 'MIN' || aggregateFunction == 'MAX') {
            String direction = aggregateFunction == 'MIN' ? ' ASC' : ' DESC';
            String soql = scope.buildSoql(
                valueField.path,
                new List<String>{ valueField.path + ' != null' },
                'ORDER BY ' + valueField.path + direction + ' LIMIT 1'
            );
            List<SObject> rows = scope.query(soql);
            result.value = rows.isEmpty() ? null : readValue(rows[0], valueField.path);
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

        result.useCursor(openAggregateCursor(scope, scope.buildSoql(valueField.path, null, ''), valueField.path, null));
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

    /** Opens a User Mode `Database.Cursor` over `soql` and aggregates its first chunk. */
    private static AggregateChunk openAggregateCursor(
        QueryScope scope,
        String soql,
        String valuePath,
        BarGrouping grouping
    ) {
        Database.Cursor cursor = Database.getCursorWithBinds(soql, scope.binds, AccessLevel.USER_MODE);
        return fetchChunk(cursor, 0, valuePath, grouping);
    }

    /**
     * Aggregates one cursor chunk into partial buckets: one ungrouped bucket, or one per Bar group/stack pair. A null
     * `valuePath` counts rows (each row adds 1). Only cursor access maps to the retryable expired-cursor error.
     */
    private static AggregateChunk fetchChunk(
        Database.Cursor cursor,
        Integer offset,
        String valuePath,
        BarGrouping grouping
    ) {
        Integer start = Math.max(0, offset);
        Integer totalRows;
        Integer fetchSize;
        List<SObject> rows = new List<SObject>();
        try {
            totalRows = cursor.getNumRecords();
            fetchSize = Math.max(0, Math.min(CURSOR_CHUNK_SIZE, totalRows - start));
            if (fetchSize > 0) {
                rows = cursor.fetch(start, fetchSize);
            }
        } catch (Exception cursorError) {
            throw aggregationCursorExpired();
        }
        Map<String, AggregateBucket> buckets = new Map<String, AggregateBucket>();
        if (grouping == null) {
            buckets.put('', new AggregateBucket());
        }
        for (SObject row : Security.stripInaccessible(AccessType.READABLE, rows).getRecords()) {
            AggregateBucket bucket = grouping == null ? buckets.get('') : grouping.bucketFor(row, buckets);
            bucket.add(valuePath == null ? 1 : readValue(row, valuePath));
        }
        AggregateChunk chunk = new AggregateChunk();
        chunk.cursor = JSON.serialize(cursor);
        chunk.offset = start;
        chunk.nextOffset = start + fetchSize;
        chunk.totalRows = totalRows;
        chunk.isComplete = chunk.nextOffset >= totalRows;
        chunk.buckets = buckets.values();
        return chunk;
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

    /** Value-field value of a queried row; parent paths traverse the queried relationships. */
    private static Object readValue(SObject row, String path) {
        return readPath(row, path);
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
    // Table execution (`Database.PaginationCursor` infinite scroll)
    // ---------------------------------------------------------------------------------------------------------

    /** Max rows a Table `Database.PaginationCursor` spans (platform pagination cursor limit). */
    @TestVisible
    private static Integer TABLE_MAX_ROWS = 100000;
    private static final Integer TABLE_DEFAULT_PAGE_SIZE = 25;
    private static final Integer TABLE_MIN_PAGE_SIZE = 10;
    private static final Integer TABLE_MAX_PAGE_SIZE = 100;
    /** `fieldPath` of the retryable `QUERY_ERROR` raised for an expired/invalid cursor; the Table re-opens it. */
    private static final String PAGINATION_CURSOR_PATH = 'paginationCursor';
    /** Leaf fields linked by `linkToRecord: 'auto'` in addition to describe name fields. */
    private static final Set<String> PRIMARY_NAME_FIELDS = new Set<String>{ 'name', 'casenumber', 'subject' };
    private static final Integer CHILD_DEFAULT_LIMIT = 10;
    private static final Integer CHILD_MAX_LIMIT = 50;
    /** Row cap of the page-scoped child count query (`FeedItem` disallows `COUNT(Id)` + `GROUP BY`). */
    @TestVisible
    private static Integer CHILD_COUNT_QUERY_LIMIT = 2001;
    /** Count queries per page: each saturated query re-queries only the parents it did not reach. */
    @TestVisible
    private static Integer CHILD_COUNT_MAX_QUERIES = 3;

    /**
     * Opens a Table Widget `Database.PaginationCursor` and returns its first page.
     *
     * Request: `{ objectApiName, columns[], sortBy, sortDirection, pageSize, start, childRelationship, filters[],
     * baseFilters[], refreshToken, widgetRefreshToken }`. `columns[]` items are `TableColumnConfig` (`id`,
     * `fieldPath`, `linkToRecord`); paths are direct fields or 1-5 hop parent dot-paths and fail closed with
     * `ACCESS_ERROR` when unreadable. Ordering is `sortBy sortDirection NULLS LAST, Id ASC`. `start` (default 0)
     * lets the caller re-open an expired cursor and continue at the row it had reached. An optional
     * `childRelationship` adds page-scoped `childCount`s to each row (no child subqueries in the page SOQL).
     */
    @AuraEnabled(cacheable=true)
    public static TableResult queryTable(String requestJson) {
        try {
            Map<String, Object> request = parseRequest(requestJson);
            QueryScope scope = new QueryScope(request);
            return runTable(scope, request);
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    /**
     * Fetches the page at `start` from a cursor returned by `queryTable`, without recompiling the query.
     * An expired or invalid cursor fails with a retryable `QUERY_ERROR` whose `fieldPath` is `paginationCursor`.
     * `childConfig` is the Table's serialized `childRelationship` (blank for none) and adds page-scoped child counts.
     */
    @AuraEnabled(cacheable=true)
    public static TablePage fetchTablePage(
        String paginationCursor,
        Integer start,
        Integer pageSize,
        String childConfig
    ) {
        try {
            ChildRelationship child = String.isBlank(childConfig)
                ? null
                : new ChildRelationship(parseRequest(childConfig));
            return fetchTableRows(
                deserializePaginationCursor(paginationCursor),
                paginationCursor,
                start == null ? 0 : Math.max(0, start),
                clampPageSize(pageSize),
                child
            );
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    /**
     * Lazily fetches one parent row's child records for an expanded Table row.
     *
     * `childConfig` is the Table's serialized `childRelationship` (`childObjectApiName`, `foreignKeyField`,
     * `columns[]`, `sortBy`, `sortDirection`, `limit` 1..50 default 10; extra keys such as `refreshToken` only
     * vary the cache key). Runs in User Mode with `Security.stripInaccessible`; unreadable child columns fail
     * closed with `ACCESS_ERROR`.
     */
    @AuraEnabled(cacheable=true)
    public static ChildRowsResult queryChildRows(String childConfig, String parentId) {
        try {
            ChildRelationship child = new ChildRelationship(parseRequest(childConfig));
            Id parentRecordId = BoardDescribe.toId(parentId);
            if (parentRecordId == null) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'A valid parent record Id is required.',
                    null,
                    'parentId'
                );
            }
            return child.queryRows(parentRecordId);
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    private static TableResult runTable(QueryScope scope, Map<String, Object> request) {
        TableResult result = new TableResult(scope);
        result.columns = resolveTableColumns(scope.objectDescribe, getList(request, 'columns'), 'columns');
        TableOrder order = new TableOrder(
            scope.objectDescribe,
            getString(request, 'sortBy'),
            getString(request, 'sortDirection')
        );
        result.sortBy = order.sortBy;
        result.sortDirection = order.sortDirection;
        Object rawChild = request.get('childRelationship');
        ChildRelationship child = rawChild == null ? null : new ChildRelationship(asMap(rawChild));
        if (child != null) {
            child.matchedChildIds.addAll(scope.searchChildIds);
        }
        result.searchChildIds = new List<Id>(scope.searchChildIds);

        String soql = scope.buildSoql(
            tableSelectList(result.columns),
            null,
            'ORDER BY ' + order.clause + ' LIMIT ' + TABLE_MAX_ROWS
        );
        Database.PaginationCursor cursor = Database.getPaginationCursorWithBinds(
            soql,
            scope.binds,
            AccessLevel.USER_MODE
        );
        Integer start = getInteger(request, 'start');
        result.copyPage(
            fetchTableRows(
                cursor,
                JSON.serialize(cursor),
                start == null ? 0 : Math.max(0, start),
                clampPageSize(getInteger(request, 'pageSize')),
                child
            )
        );
        return result;
    }

    private static List<TableColumn> resolveTableColumns(
        Schema.DescribeSObjectResult objectDescribe,
        List<Object> rawColumns,
        String configPath
    ) {
        List<TableColumn> columns = new List<TableColumn>();
        for (Object rawColumn : rawColumns) {
            columns.add(new TableColumn(objectDescribe, asMap(rawColumn)));
        }
        if (columns.isEmpty()) {
            throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'A table needs at least one column.', null, configPath);
        }
        return columns;
    }

    /** `Id` plus each column's `fieldPath` and `linkPath`, case-insensitively deduped. */
    private static String tableSelectList(List<TableColumn> columns) {
        List<String> selectPaths = new List<String>{ 'Id' };
        Set<String> selected = new Set<String>{ 'id' };
        for (TableColumn column : columns) {
            for (String path : new List<String>{ column.fieldPath, column.linkPath }) {
                if (path != null && selected.add(path.toLowerCase())) {
                    selectPaths.add(path);
                }
            }
        }
        return String.join(selectPaths, ', ');
    }

    /** Fetches one page with the prototype-verified final-page `fetchSize` clamp and `getNextIndex()` wrap guard. */
    private static TablePage fetchTableRows(
        Database.PaginationCursor paginationCursor,
        String cursorJson,
        Integer start,
        Integer pageSize,
        ChildRelationship child
    ) {
        TablePage page = new TablePage();
        Integer totalRecords;
        List<SObject> records = new List<SObject>();
        Integer nextIndex = start;
        Integer deletedRows = 0;
        try {
            totalRecords = paginationCursor.getNumRecords();
            Integer fetchSize = Math.max(0, Math.min(pageSize, totalRecords - start));
            if (fetchSize > 0) {
                Database.CursorFetchResult fetchResult = paginationCursor.fetchPage(start, fetchSize);
                records = fetchResult.getRecords();
                deletedRows = fetchResult.getNumDeletedRecords();
                Integer rawNext = fetchResult.getNextIndex();
                nextIndex = (rawNext > start) ? rawNext : (start + records.size() + deletedRows);
            }
        } catch (Exception cursorError) {
            throw paginationCursorExpired();
        }
        if (start > totalRecords) {
            // A cursor that cannot reach rows the caller already read is no longer the one it opened.
            throw paginationCursorExpired();
        }
        if (!records.isEmpty()) {
            for (SObject record : Security.stripInaccessible(AccessType.READABLE, records).getRecords()) {
                page.rows.add(new TableRow(record));
            }
        }
        if (child != null) {
            child.applyCounts(page.rows);
            child.applySearchMatches(page.rows);
        }
        page.paginationCursor = cursorJson;
        page.start = start;
        page.nextIndex = nextIndex;
        page.totalCount = totalRecords;
        page.deletedRows = deletedRows;
        page.hasMore = nextIndex < totalRecords && !records.isEmpty();
        return page;
    }

    private static Database.PaginationCursor deserializePaginationCursor(String cursorJson) {
        if (String.isBlank(cursorJson)) {
            throw paginationCursorExpired();
        }
        try {
            return (Database.PaginationCursor) JSON.deserialize(cursorJson, Database.PaginationCursor.class);
        } catch (Exception invalidCursor) {
            throw paginationCursorExpired();
        }
    }

    private static BoardErrors.BoardException paginationCursorExpired() {
        return BoardErrors.error(
            BoardErrors.QUERY_ERROR,
            'The table cursor is no longer available. Reload the table to continue.',
            null,
            PAGINATION_CURSOR_PATH,
            true
        );
    }

    private static Integer clampPageSize(Integer pageSize) {
        if (pageSize == null) {
            return TABLE_DEFAULT_PAGE_SIZE;
        }
        return Math.max(TABLE_MIN_PAGE_SIZE, Math.min(TABLE_MAX_PAGE_SIZE, pageSize));
    }

    /** Direct field or 1-5 hop parent dot-path (no semi-joins) for Table columns and sorting. */
    private static ResolvedField resolveTablePath(Schema.DescribeSObjectResult objectDescribe, String path) {
        String compactPath = path.deleteWhitespace();
        if (compactPath.contains('(')) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Table columns support direct fields and parent paths only: ' + path,
                null,
                path
            );
        }
        return resolveFieldPath(objectDescribe, compactPath, null, path);
    }

    /** Record ID path a column links to: `Id` for direct fields, the last hop's reference field for parent paths. */
    private static String recordIdPath(Schema.DescribeSObjectResult rootDescribe, String canonicalPath) {
        List<String> segments = canonicalPath.split('\\.');
        if (segments.size() == 1) {
            return 'Id';
        }
        Schema.DescribeSObjectResult current = rootDescribe;
        Schema.DescribeFieldResult reference;
        for (Integer i = 0; i < segments.size() - 1; i++) {
            reference = relationshipIndex(current).get(segments[i].toLowerCase()).getDescribe();
            current = BoardDescribe.describeObject(parentType(reference));
        }
        segments[segments.size() - 2] = reference.getName();
        segments.remove(segments.size() - 1);
        return String.join(segments, '.');
    }

    /** Flattens a queried record into `path -> value` (e.g. `Account.Owner.Name`). */
    private static void flattenRecord(SObject record, String prefix, Map<String, Object> values) {
        Map<String, Object> populated = record.getPopulatedFieldsAsMap();
        for (String key : populated.keySet()) {
            Object value = populated.get(key);
            if (value instanceof SObject) {
                flattenRecord((SObject) value, prefix + key + '.', values);
            } else if (!(value instanceof List<SObject>)) {
                values.put(prefix + key, value);
            }
        }
    }

    /** Validated Table sort: canonical `sortBy`/`sortDirection` and the `ORDER BY` clause with an `Id` tie-breaker. */
    private class TableOrder {
        String sortBy;
        String sortDirection;
        String clause = 'Id ASC';

        TableOrder(Schema.DescribeSObjectResult objectDescribe, String rawSortBy, String rawDirection) {
            if (String.isBlank(rawSortBy)) {
                return;
            }
            ResolvedField sortField = resolveTablePath(objectDescribe, rawSortBy);
            if (!sortField.describe.isSortable()) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Field is not sortable: ' + rawSortBy,
                    null,
                    rawSortBy
                );
            }
            sortBy = sortField.path;
            sortDirection = 'DESC'.equalsIgnoreCase(rawDirection) ? 'DESC' : 'ASC';
            clause = sortBy.equalsIgnoreCase('Id')
                ? 'Id ' + sortDirection
                : sortBy + ' ' + sortDirection + ' NULLS LAST, Id ASC';
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Table child relationship (page-scoped counts + lazy child rows)
    // ---------------------------------------------------------------------------------------------------------

    /**
     * A Table `childRelationship`: the child object and the reference field pointing at the parent row.
     * Counts and child rows run in User Mode; the foreign key must reference the parent rows' object.
     */
    private class ChildRelationship {
        Map<String, Object> config;
        Schema.DescribeSObjectResult childDescribe;
        String foreignKeyField;
        Schema.DescribeFieldResult foreignKeyDescribe;
        Integer rowLimit;
        /** Child records matched by the Table's text search; matching parents on a page are auto-expanded. */
        Set<Id> matchedChildIds = new Set<Id>();

        ChildRelationship(Map<String, Object> config) {
            this.config = config;
            String childObjectApiName = getString(config, 'childObjectApiName');
            if (String.isBlank(childObjectApiName)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'The child relationship needs a child object.',
                    null,
                    'childRelationship.childObjectApiName'
                );
            }
            childDescribe = BoardDescribe.requireReadableObject(childObjectApiName);
            String rawForeignKey = getString(config, 'foreignKeyField');
            Schema.SObjectField field = String.isBlank(rawForeignKey)
                ? null
                : childDescribe.fields.getMap().get(rawForeignKey.trim());
            foreignKeyDescribe = field == null ? null : field.getDescribe();
            if (foreignKeyDescribe == null || foreignKeyDescribe.getType() != Schema.DisplayType.REFERENCE) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Unknown child foreign key: ' + childDescribe.getName() + '.' + rawForeignKey,
                    null,
                    'childRelationship.foreignKeyField'
                );
            }
            BoardDescribe.requireReadableField(
                childDescribe.getName(),
                foreignKeyDescribe,
                null,
                'childRelationship.foreignKeyField'
            );
            foreignKeyField = foreignKeyDescribe.getName();
            Integer requestedLimit = getInteger(config, 'limit');
            rowLimit = requestedLimit == null
                ? CHILD_DEFAULT_LIMIT
                : Math.max(1, Math.min(CHILD_MAX_LIMIT, requestedLimit));
            for (Object rawId : getList(config, 'matchedChildIds')) {
                Id childId = BoardDescribe.toId(rawId == null ? null : String.valueOf(rawId));
                if (childId != null) {
                    matchedChildIds.add(childId);
                }
            }
        }

        /** Ids of the page `rows` after checking the foreign key references their object. */
        List<Id> parentIdsOf(List<TableRow> rows) {
            List<Id> parentIds = new List<Id>();
            for (TableRow row : rows) {
                parentIds.add(row.id);
            }
            requireParentObject(parentIds[0]);
            return parentIds;
        }

        void requireParentObject(Id parentId) {
            String parentObject = parentId.getSObjectType().getDescribe().getName();
            if (!referencesObject(foreignKeyDescribe, parentObject)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    childDescribe.getName() + '.' + foreignKeyField + ' does not reference ' + parentObject,
                    null,
                    'childRelationship.foreignKeyField'
                );
            }
        }

        /**
         * Sets `childCount` (capped at the row limit) and `childCountCapped` on every row with
         * `SELECT Id, <fk> ... WHERE <fk> IN :parentIds LIMIT 2001` queries. A saturated query may omit parents
         * entirely, so it marks the parents it saw as capped (their counts may be partial) and re-queries only the
         * unseen ones, up to `CHILD_COUNT_MAX_QUERIES`. Parents still unresolved get an unknown count
         * (`childCount` null, `childCountCapped` true) and stay expandable.
         */
        void applyCounts(List<TableRow> rows) {
            if (rows.isEmpty()) {
                return;
            }
            Set<Id> unresolved = new Set<Id>(parentIdsOf(rows));
            Map<Id, Integer> counts = new Map<Id, Integer>();
            Set<Id> partial = new Set<Id>();
            Boolean saturated = true;
            for (
                Integer attempt = 0; attempt < CHILD_COUNT_MAX_QUERIES && saturated && !unresolved.isEmpty(); attempt++
            ) {
                List<SObject> children = Database.queryWithBinds(
                    'SELECT Id, ' +
                        foreignKeyField +
                        ' FROM ' +
                        childDescribe.getName() +
                        ' WHERE ' +
                        foreignKeyField +
                        ' IN :parentIds LIMIT ' +
                        CHILD_COUNT_QUERY_LIMIT,
                    new Map<String, Object>{ 'parentIds' => unresolved },
                    AccessLevel.USER_MODE
                );
                saturated = children.size() >= CHILD_COUNT_QUERY_LIMIT;
                for (SObject childRecord : children) {
                    Id parentId = (Id) childRecord.get(foreignKeyField);
                    Integer current = counts.get(parentId);
                    counts.put(parentId, current == null ? 1 : current + 1);
                }
                if (saturated) {
                    partial.addAll(counts.keySet());
                }
                unresolved.removeAll(counts.keySet());
            }
            for (TableRow row : rows) {
                if (saturated && unresolved.contains(row.id)) {
                    row.childCount = null;
                    row.childCountCapped = true;
                    continue;
                }
                Integer count = counts.containsKey(row.id) ? counts.get(row.id) : 0;
                row.childCount = Math.min(count, rowLimit);
                row.childCountCapped = count > rowLimit || partial.contains(row.id);
            }
        }

        List<TableColumn> resolveColumns() {
            return resolveTableColumns(childDescribe, getList(config, 'columns'), 'childRelationship.columns');
        }

        TableOrder resolveOrder() {
            return new TableOrder(childDescribe, getString(config, 'sortBy'), getString(config, 'sortDirection'));
        }

        ChildRowsResult newResult(Id parentId, List<TableColumn> columns, TableOrder order) {
            ChildRowsResult result = new ChildRowsResult();
            result.parentId = parentId;
            result.columns = columns;
            result.sortBy = order.sortBy;
            result.sortDirection = order.sortDirection;
            result.hasMore = false;
            return result;
        }

        /**
         * Batch-fetches, in one query, the search-matched child rows of every page row that has any, attaching
         * them as `children` (up to the row limit) and marking those rows `autoExpanded`.
         */
        void applySearchMatches(List<TableRow> rows) {
            if (rows.isEmpty() || matchedChildIds.isEmpty()) {
                return;
            }
            List<Id> parentIds = parentIdsOf(rows);
            List<TableColumn> columns = resolveColumns();
            TableOrder order = resolveOrder();
            String selectList = tableSelectList(columns);
            if (!(', ' + selectList.toLowerCase() + ',').contains(', ' + foreignKeyField.toLowerCase() + ',')) {
                selectList += ', ' + foreignKeyField;
            }
            List<SObject> records = Database.queryWithBinds(
                'SELECT ' +
                    selectList +
                    ' FROM ' +
                    childDescribe.getName() +
                    ' WHERE Id IN :matchedChildIds AND ' +
                    foreignKeyField +
                    ' IN :parentIds ORDER BY ' +
                    order.clause +
                    ' LIMIT ' +
                    CHILD_COUNT_QUERY_LIMIT,
                new Map<String, Object>{ 'matchedChildIds' => matchedChildIds, 'parentIds' => parentIds },
                AccessLevel.USER_MODE
            );
            Map<Id, ChildRowsResult> byParent = new Map<Id, ChildRowsResult>();
            for (SObject record : Security.stripInaccessible(AccessType.READABLE, records).getRecords()) {
                Id parentId = (Id) record.get(foreignKeyField);
                ChildRowsResult result = byParent.get(parentId);
                if (result == null) {
                    result = newResult(parentId, columns, order);
                    byParent.put(parentId, result);
                }
                if (result.rows.size() < rowLimit) {
                    result.rows.add(new TableRow(record));
                } else {
                    result.hasMore = true;
                }
            }
            for (TableRow row : rows) {
                ChildRowsResult result = byParent.get(row.id);
                if (result != null) {
                    row.autoExpanded = true;
                    row.children = result;
                }
            }
        }

        /** Up to `limit` child rows of one parent, ordered by the configured sort with an `Id` tie-breaker. */
        ChildRowsResult queryRows(Id parentId) {
            requireParentObject(parentId);
            TableOrder order = resolveOrder();
            ChildRowsResult result = newResult(parentId, resolveColumns(), order);
            List<SObject> records = Database.queryWithBinds(
                'SELECT ' +
                    tableSelectList(result.columns) +
                    ' FROM ' +
                    childDescribe.getName() +
                    ' WHERE ' +
                    foreignKeyField +
                    ' = :parentId ORDER BY ' +
                    order.clause +
                    ' LIMIT ' +
                    (rowLimit + 1),
                new Map<String, Object>{ 'parentId' => parentId },
                AccessLevel.USER_MODE
            );
            result.hasMore = records.size() > rowLimit;
            Integer index = 0;
            for (SObject record : Security.stripInaccessible(AccessType.READABLE, records).getRecords()) {
                if (index++ < rowLimit) {
                    result.rows.add(new TableRow(record));
                }
            }
            return result;
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Bar Chart execution
    // ---------------------------------------------------------------------------------------------------------

    private static BarResult runBar(QueryScope scope, Map<String, Object> request) {
        String aggregateFunction = parseAggregateFunction(request);
        BarGrouping grouping = new BarGrouping(scope.objectDescribe, request);
        BarResult result = new BarResult(aggregateFunction, scope, grouping);
        String measure = 'COUNT(Id)';
        ResolvedField valueField;
        if (aggregateFunction != 'COUNT') {
            valueField = resolveValueField(scope.objectDescribe, getString(request, 'valueFieldApiName'));
            if (aggregateFunction != 'COUNT_DISTINCT' && !BoardDescribe.NUMERIC_TYPES.contains(valueField.type)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    aggregateFunction + ' bars require a numeric value field: ' + valueField.path,
                    null,
                    valueField.path
                );
            }
            measure = aggregateFunction + '(' + valueField.path + ')';
            result.valueType = valueField.type.name();
        }
        List<String> extraPredicates = grouping.extraPredicates();
        String valuePath = valueField == null ? null : valueField.path;
        String cursorSoql = scope.buildSoql(grouping.cursorSelect(valuePath), extraPredicates, '');

        if (aggregateFunction != 'COUNT') {
            result.totalRows = countBarRows(scope, extraPredicates);
            if (result.totalRows > CURSOR_AGGREGATE_THRESHOLD) {
                if (aggregateFunction == 'COUNT_DISTINCT' || result.totalRows > CURSOR_MAX_ROWS) {
                    throw limitExceeded(result.totalRows);
                }
                result.useCursor(openAggregateCursor(scope, cursorSoql, valuePath, grouping));
                return result;
            }
        }

        String soql = scope.buildSoql(
            grouping.aggregateSelect() + ', ' + measure + ' v',
            extraPredicates,
            'GROUP BY ' +
                grouping.groupByClause() +
                ' ORDER BY ' +
                measure +
                ' DESC NULLS LAST LIMIT ' +
                BAR_GROUP_LIMIT
        );
        for (SObject row : scope.query(soql)) {
            AggregateResult aggregate = (AggregateResult) row;
            result.buckets.add(grouping.toBucket(aggregate, aggregate.get('v')));
        }
        if (result.buckets.size() < BAR_GROUP_LIMIT) {
            return result;
        }
        // Capped: smaller groups were dropped. Re-aggregate every group through cursor chunks when possible
        // (COUNT_DISTINCT cannot be merged across chunks).
        if (aggregateFunction != 'COUNT_DISTINCT') {
            if (result.totalRows == null) {
                result.totalRows = countBarRows(scope, extraPredicates);
            }
            if (result.totalRows <= CURSOR_MAX_ROWS) {
                result.buckets = new List<BarBucket>();
                result.useCursor(openAggregateCursor(scope, cursorSoql, valuePath, grouping));
                return result;
            }
        }
        result.hasMoreGroups = true;
        return result;
    }

    private static Integer countBarRows(QueryScope scope, List<String> extraPredicates) {
        return Database.countQueryWithBinds(
            scope.buildSoql('COUNT()', extraPredicates, ''),
            scope.binds,
            AccessLevel.USER_MODE
        );
    }

    /** Reads a direct field or parent dot-path value from a queried record (null when a parent is empty). */
    private static Object readPath(SObject row, String path) {
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

    /** Org fiscal year settings, used to bucket cursor rows exactly like SOQL `FISCAL_*` date functions. */
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

    /** The Bar Chart's primary group dimension plus optional stack dimension. */
    private class BarGrouping {
        BarDimension groupBy;
        BarDimension stackBy;
        Boolean includeNullBucket;

        BarGrouping(Schema.DescribeSObjectResult objectDescribe, Map<String, Object> request) {
            String groupPath = getString(request, 'groupByField');
            if (String.isBlank(groupPath)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'A group-by field is required.',
                    null,
                    'groupByField'
                );
            }
            groupBy = new BarDimension(objectDescribe, groupPath, getString(request, 'dateGranularity'), 'g0');
            String stackPath = getString(request, 'stackByField');
            if (String.isNotBlank(stackPath)) {
                stackBy = new BarDimension(objectDescribe, stackPath, null, 'g1');
            }
            includeNullBucket = request.get('includeNullBucket') != false;
        }

        List<String> extraPredicates() {
            return includeNullBucket ? new List<String>() : new List<String>{ groupBy.field.path + ' != null' };
        }

        String aggregateSelect() {
            List<String> columns = groupBy.selectColumns();
            if (stackBy != null) {
                columns.addAll(stackBy.selectColumns());
            }
            return String.join(columns, ', ');
        }

        String groupByClause() {
            List<String> expressions = new List<String>(groupBy.expressions);
            if (stackBy != null) {
                expressions.addAll(stackBy.expressions);
            }
            return String.join(expressions, ', ');
        }

        /** Plain (non-aggregate) SELECT list for cursor rows: value field (none for `COUNT`) plus every raw dimension path. */
        String cursorSelect(String valuePath) {
            List<String> paths = new List<String>();
            if (valuePath != null) {
                paths.add(valuePath);
            }
            paths.addAll(groupBy.rawPaths());
            if (stackBy != null) {
                paths.addAll(stackBy.rawPaths());
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

        BarBucket toBucket(AggregateResult aggregate, Object value) {
            BarBucket bucket = new BarBucket();
            List<String> groupKey = groupBy.fromAggregate(aggregate);
            bucket.groupValue = groupKey[0];
            bucket.groupLabel = groupKey[1];
            if (stackBy != null) {
                List<String> stackKey = stackBy.fromAggregate(aggregate);
                bucket.stackValue = stackKey[0];
                bucket.stackLabel = stackKey[1];
            }
            bucket.value = value;
            return bucket;
        }

        AggregateBucket bucketFor(SObject row, Map<String, AggregateBucket> buckets) {
            List<String> groupKey = groupBy.fromRecord(row);
            List<String> stackKey = stackBy == null ? null : stackBy.fromRecord(row);
            List<Object> values = new List<Object>{ groupKey[0] };
            if (stackKey != null) {
                values.add(stackKey[0]);
            }
            String mapKey = JSON.serialize(values);
            AggregateBucket bucket = buckets.get(mapKey);
            if (bucket == null) {
                bucket = new AggregateBucket();
                bucket.groupValues = values;
                bucket.groupLabels.add(groupKey[1]);
                if (stackKey != null) {
                    bucket.groupLabels.add(stackKey[1]);
                }
                buckets.put(mapKey, bucket);
            }
            return bucket;
        }
    }

    /**
     * One Bar Chart dimension (`groupByField` or `stackByField`): a groupable direct field or 1-5 hop parent path,
     * a Reference field labelled by its target's name field, or a Date/DateTime field bucketed by granularity.
     * Buckets are `[value, label]` pairs: sortable keys (`2026-03`, `2026-Q1`, `FY2026-Q2`, record Ids, picklist API
     * values) and display labels (null for the null bucket).
     */
    private class BarDimension {
        ResolvedField field;
        String alias;
        String granularity;
        Boolean isDateTime = false;
        String labelPath;
        Map<String, String> picklistLabels = new Map<String, String>();
        List<String> picklistOrder = new List<String>();
        List<String> expressions = new List<String>();
        List<String> aliases = new List<String>();

        BarDimension(Schema.DescribeSObjectResult objectDescribe, String rawPath, String rawGranularity, String alias) {
            String path = rawPath.deleteWhitespace();
            if (path.contains('(')) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Bar dimensions must be a field or parent field path: ' + rawPath,
                    null,
                    rawPath
                );
            }
            this.field = resolveFieldPath(objectDescribe, path, null, rawPath);
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
            for (Schema.SObjectField candidate : target.fields.getMap().values()) {
                Schema.DescribeFieldResult candidateDescribe = candidate.getDescribe();
                if (candidateDescribe.isNameField() && candidateDescribe.isAccessible()) {
                    segments[segments.size() - 1] = relationshipName;
                    return String.join(segments, '.') + '.' + candidateDescribe.getName();
                }
            }
            return null;
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
            if (raw == null) {
                return new List<String>{ null, null };
            }
            Date day = isDateTime ? ((Datetime) raw).date() : (Date) raw;
            switch on granularity {
                when 'DAY' {
                    return dateBucket(day, null, null);
                }
                when 'CALENDAR_MONTH' {
                    return dateBucket(null, day.year(), day.month());
                }
                when 'CALENDAR_QUARTER' {
                    return dateBucket(null, day.year(), (day.month() - 1) / 3 + 1);
                }
                when 'CALENDAR_YEAR' {
                    return dateBucket(null, day.year(), null);
                }
                when else {
                    Organization settings = getFiscalSettings();
                    Integer startMonth = settings.FiscalYearStartMonth == null ? 1 : settings.FiscalYearStartMonth;
                    Integer startYear = day.month() >= startMonth ? day.year() : day.year() - 1;
                    Integer fiscalYear = startMonth == 1 || settings.UsesStartDateAsFiscalYearName
                        ? startYear
                        : startYear + 1;
                    Integer fiscalQuarter = Math.mod(day.month() - startMonth + 12, 12) / 3 + 1;
                    return dateBucket(null, fiscalYear, granularity == 'FISCAL_QUARTER' ? fiscalQuarter : null);
                }
            }
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
            if (granularity == 'DAY') {
                return day == null
                    ? new List<String>{ null, null }
                    : new List<String>{ String.valueOf(day), day.format() };
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

        BarDimensionInfo info() {
            BarDimensionInfo info = new BarDimensionInfo();
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
     * Compiles a Widget request's data scope (`objectApiName` + resolved Filter bindings + base filters) into a
     * bind-safe `WHERE` clause and executes User Mode queries, counts, and cursors against it.
     */
    private class QueryScope {
        Schema.DescribeSObjectResult objectDescribe;
        Map<String, Object> binds = new Map<String, Object>();
        List<String> appliedFilterIds = new List<String>();
        List<String> ignoredFilterIds = new List<String>();
        List<String> predicates = new List<String>();
        /** Parallel to `predicates`: true when the predicate only uses direct fields, so `SOSL` `WHERE` can apply it. */
        List<Boolean> searchSafe = new List<Boolean>();
        /** Bind names holding escaped `LIKE` patterns (their `\` sequences must survive inlining into `SOSL`). */
        Set<String> likeBindNames = new Set<String>();
        Integer semiJoinCount = 0;
        /** Table `childRelationship` config (`childObjectApiName`, `foreignKeyField`) that convention `SOSL` unions. */
        Map<String, Object> childRelationship;
        /** Records of the Table's `childRelationship` matched by a `SOSL` text search. */
        Set<Id> searchChildIds = new Set<Id>();

        QueryScope(Map<String, Object> request) {
            objectDescribe = BoardDescribe.requireReadableObject(getString(request, 'objectApiName'));
            Object rawChild = request.get('childRelationship');
            childRelationship = rawChild instanceof Map<String, Object> ? (Map<String, Object>) rawChild : null;
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

        String buildSoql(String selectClause, List<String> extraPredicates, String suffix) {
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

        String conjunction(List<String> clauses) {
            return '(' + String.join(clauses, ') AND (') + ')';
        }

        Integer countRows() {
            return Database.countQueryWithBinds(buildSoql('COUNT()', null, ''), binds, AccessLevel.USER_MODE);
        }

        List<SObject> query(String soql) {
            List<SObject> rows = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
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
            addPredicate(field, compileFilter(filter, field), filter.filterId);
            appliedFilterIds.add(filter.filterId);
        }

        void addBaseFilter(BaseFilter condition) {
            if (String.isBlank(condition.fieldPath)) {
                throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Base filter has no field path.', condition.id, null);
            }
            ResolvedField field = resolveBinding(condition.fieldPath.trim(), condition.id);
            addPredicate(field, compileBaseFilter(condition, field), condition.id);
        }

        void addPredicate(ResolvedField field, String predicate, String filterId) {
            addCompiled(wrapSemiJoin(field, predicate, filterId), isDirectField(field));
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
            Boolean allDirect = true;
            for (String part : path.split(',')) {
                if (String.isBlank(part)) {
                    continue;
                }
                ResolvedField field = resolveBinding(part.trim(), filter.filterId);
                requireFilterCompatible(filter, field);
                clauses.add('(' + wrapSemiJoin(field, compileFilter(filter, field), filter.filterId) + ')');
                allDirect &= isDirectField(field);
            }
            addCompiled(String.join(clauses, ' OR '), allDirect);
            appliedFilterIds.add(filter.filterId);
        }

        /**
         * `SOSL` text search compiled to `Id IN :matchedParentIds`: the single-transaction union of
         * `Search.query` (full-text indexes, incl. non-filterable Long Text Area fields) and a bounded `SOQL LIKE`
         * leg on filterable text fields (zero index lag). Targets are `SELF` and `Child(ForeignKey)` entries; by
         * convention `SELF` plus the Table's `childRelationship`. Child matches keep their parent rows.
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
            List<SearchTarget> targets = new List<SearchTarget>{ new SearchTarget(objectDescribe, null) };
            if (childRelationship != null) {
                try {
                    targets.add(
                        childSearchTarget(
                            getString(childRelationship, 'childObjectApiName'),
                            getString(childRelationship, 'foreignKeyField'),
                            null,
                            'childRelationship'
                        )
                    );
                } catch (BoardErrors.BoardException invalidChild) {
                    // The Table reports an invalid childRelationship itself; search the parent only.
                    return targets;
                }
            }
            return targets;
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
            SearchTarget target = new SearchTarget(
                BoardDescribe.describeObject(BoardDescribe.getGlobalDescribe().get(fk.childObject)),
                fk.foreignKey
            );
            target.isTableChild =
                childRelationship != null &&
                fk.childObject.equalsIgnoreCase(getString(childRelationship, 'childObjectApiName')) &&
                fk.foreignKey.equalsIgnoreCase(getString(childRelationship, 'foreignKeyField'));
            return target;
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
                if (target.isTableChild) {
                    searchChildIds.add(record.Id);
                }
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

        String compileFilter(FilterBinding filter, ResolvedField field) {
            String path = field.path;
            switch on filter.operator {
                when 'IN' {
                    return compileIn(path, field, filter.effectiveValues(), false, filter.filterId);
                }
                when 'LITERAL' {
                    return path + ' = ' + requireRelativeDate(filter.literal, filter.filterId, field.bindingPath);
                }
                when 'BETWEEN', 'GTE', 'LTE' {
                    List<String> range = new List<String>();
                    if (filter.operator != 'LTE' && String.isNotBlank(filter.fromValue)) {
                        range.add(path + ' >= ' + bind(dateBound(filter.fromValue, field, false, filter.filterId)));
                    }
                    if (filter.operator != 'GTE' && String.isNotBlank(filter.toValue)) {
                        range.add(path + ' <= ' + bind(dateBound(filter.toValue, field, true, filter.filterId)));
                    }
                    return String.join(range, ' AND ');
                }
                when 'CONTAINS' {
                    return path + ' LIKE ' + bindLike('%' + BoardDescribe.escapeLike(filter.text.trim()) + '%');
                }
                when else {
                    // STARTS_WITH (requireFilterCompatible rejects every other operator)
                    return path + ' LIKE ' + bindLike(BoardDescribe.escapeLike(filter.text.trim()) + '%');
                }
            }
        }

        String compileBaseFilter(BaseFilter condition, ResolvedField field) {
            String path = field.path;
            String filterId = condition.id;
            switch on condition.operator {
                when 'IS_NULL' {
                    Boolean isNull = condition.value == null || String.valueOf(condition.value) != 'false';
                    return path + (isNull ? ' = null' : ' != null');
                }
                when 'EQ', 'NEQ', 'GT', 'GTE', 'LT', 'LTE' {
                    return compileComparison(path, condition.operator, condition.value, field, filterId);
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
                    return compileIn(path, field, values, condition.operator == 'NOT_IN', filterId);
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
                    return path + ' LIKE ' + bind(likePattern.contains('%') ? likePattern : '%' + likePattern + '%');
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
                    return path + ' = ' + requireRelativeDate(literal, filterId, field.bindingPath);
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

        String compileComparison(String path, String operator, Object rawValue, ResolvedField field, String filterId) {
            String symbol = COMPARISON_SYMBOLS.get(operator);
            if (rawValue == null) {
                if (operator != 'EQ' && operator != 'NEQ') {
                    throw BoardErrors.error(
                        BoardErrors.CONFIG_ERROR,
                        operator + ' requires a value.',
                        filterId,
                        field.bindingPath
                    );
                }
                return path + ' ' + symbol + ' null';
            }
            String text = String.valueOf(rawValue);
            if (field.type == Schema.DisplayType.DATETIME && ISO_DATE_PATTERN.matcher(text).matches()) {
                String dayStart = bind(dateBound(text, field, false, filterId));
                String dayEnd = bind(dateBound(text, field, true, filterId));
                switch on operator {
                    when 'EQ' {
                        return path + ' >= ' + dayStart + ' AND ' + path + ' <= ' + dayEnd;
                    }
                    when 'NEQ' {
                        return path + ' < ' + dayStart + ' OR ' + path + ' > ' + dayEnd;
                    }
                    when 'GT' {
                        return path + ' > ' + dayEnd;
                    }
                    when 'GTE' {
                        return path + ' >= ' + dayStart;
                    }
                    when 'LT' {
                        return path + ' < ' + dayStart;
                    }
                    when else {
                        return path + ' <= ' + dayEnd;
                    }
                }
            }
            return path + ' ' + symbol + ' ' + bind(coerce(rawValue, field, filterId));
        }

        String compileIn(String path, ResolvedField field, List<String> values, Boolean negate, String filterId) {
            if (field.type == Schema.DisplayType.MULTIPICKLIST) {
                List<String> tokens = new List<String>();
                for (String value : values) {
                    tokens.add(bind(value == null ? '' : value));
                }
                return path + (negate ? ' EXCLUDES (' : ' INCLUDES (') + String.join(tokens, ', ') + ')';
            }
            if (field.type == Schema.DisplayType.BOOLEAN) {
                List<String> clauses = new List<String>();
                for (String value : values) {
                    clauses.add(path + (negate ? ' != ' : ' = ') + bind(coerce(value, field, filterId)));
                }
                return String.join(clauses, negate ? ' AND ' : ' OR ');
            }
            List<Object> coerced = typedList(field.type);
            for (String value : values) {
                coerced.add(coerce(value, field, filterId));
            }
            return path + (negate ? ' NOT IN ' : ' IN ') + bind(coerced);
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
        /** True when this child is the Table's `childRelationship` (its matches auto-expand parent rows). */
        Boolean isTableChild = false;

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

        List<String> effectiveValues() {
            List<String> effective = new List<String>(values);
            if (token == TOKEN_ME) {
                effective.add(UserInfo.getUserId());
            }
            return effective;
        }
    }

    /** A Widget's static base filter condition (`BaseFilterCondition`). */
    private class BaseFilter {
        String id;
        String fieldPath;
        String operator;
        Object value;

        BaseFilter(Object raw) {
            Map<String, Object> source = asMap(raw);
            id = getString(source, 'id');
            fieldPath = getString(source, 'fieldPath');
            operator = upper(getString(source, 'operator'));
            value = source.get('value');
        }
    }

    /** A field path resolved against describes with canonical API names. */
    private class ResolvedField {
        String path;
        String bindingPath;
        Schema.DescribeFieldResult describe;
        Schema.DisplayType type;
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

    private static ResolvedField resolveFieldPath(
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
    private static Schema.SObjectType parentType(Schema.DescribeFieldResult referenceDescribe) {
        List<Schema.SObjectType> targets = referenceDescribe.getReferenceTo();
        for (Schema.SObjectType target : targets) {
            if (target == User.SObjectType) {
                return target;
            }
        }
        return targets[0];
    }

    private static Map<String, Schema.SObjectField> relationshipIndex(Schema.DescribeSObjectResult objectDescribe) {
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
            when 'LITERAL', 'BETWEEN', 'GTE', 'LTE' {
                compatible = DATE_TYPES.contains(field.type);
            }
            when 'CONTAINS', 'STARTS_WITH' {
                compatible = TEXT_FILTER_TYPES.contains(field.type);
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
        if (!RELATIVE_DATE_PATTERN.matcher(normalized).matches()) {
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

    private static Map<String, Object> parseRequest(String requestJson) {
        try {
            return asMap(JSON.deserializeUntyped(requestJson));
        } catch (Exception malformed) {
            throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Malformed widget query request.', null, null);
        }
    }

    private static Map<String, Object> asMap(Object raw) {
        if (!(raw instanceof Map<String, Object>)) {
            throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Malformed widget query request.', null, null);
        }
        return (Map<String, Object>) raw;
    }

    private static List<Object> getList(Map<String, Object> source, String key) {
        Object value = source.get(key);
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }

    private static String getString(Map<String, Object> source, String key) {
        Object value = source.get(key);
        return value == null ? null : String.valueOf(value);
    }

    private static Integer getInteger(Map<String, Object> source, String key) {
        Object value = source.get(key);
        return value == null ? null : Integer.valueOf(value);
    }

    private static String upper(String value) {
        return value == null ? null : value.trim().toUpperCase();
    }

    // ---------------------------------------------------------------------------------------------------------
    // DTOs
    // ---------------------------------------------------------------------------------------------------------

    /** Fields shared by Metric and Bar results: binding outcome, row count, and the cursor tier hand-off. */
    public virtual class AggregateQueryResult {
        @AuraEnabled
        public String aggregateFunction;
        /** `Schema.DisplayType` name of the value field (null for `COUNT`). */
        @AuraEnabled
        public String valueType;
        /** Matching row count (Metric: null for `MIN`/`MAX`; Bar: null for a single-call `COUNT`). */
        @AuraEnabled
        public Integer totalRows;
        /** `SINGLE` (one-call aggregate) or `CURSOR` (multi-call chunked aggregation). */
        @AuraEnabled
        public String mode = MODE_SINGLE;
        @AuraEnabled
        public Boolean isComplete = true;
        /** First cursor chunk when `mode == 'CURSOR'` (Bar buckets carry `groupValues`/`groupLabels`). */
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

        MetricResult(String aggregateFunction, QueryScope scope) {
            super(aggregateFunction, scope);
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
        public List<AggregateBucket> buckets;
    }

    public class AggregateBucket {
        /** Group-by values identifying the bucket (empty for ungrouped aggregates; Bar: `[groupValue, stackValue?]`). */
        @AuraEnabled
        public List<Object> groupValues = new List<Object>();
        /** Display labels parallel to `groupValues` (Bar only; null for the null bucket). */
        @AuraEnabled
        public List<String> groupLabels = new List<String>();
        @AuraEnabled
        public Decimal sum = 0;
        /** Number of non-null values. */
        @AuraEnabled
        public Integer count = 0;
        @AuraEnabled
        public Decimal min;
        @AuraEnabled
        public Decimal max;

        void add(Object rawValue) {
            if (rawValue == null) {
                return;
            }
            Decimal value = Decimal.valueOf(String.valueOf(rawValue));
            sum += value;
            count++;
            min = min == null || value < min ? value : min;
            max = max == null || value > max ? value : max;
        }
    }

    public class BarResult extends AggregateQueryResult {
        /** One entry per group/stack combination when `mode == 'SINGLE'` (largest values first). */
        @AuraEnabled
        public List<BarBucket> buckets = new List<BarBucket>();
        /**
         * True when the `GROUP BY` query returned `BAR_GROUP_LIMIT` combinations, dropped smaller ones, and the
         * cursor tier could not re-aggregate them (`COUNT_DISTINCT`, or more than `CURSOR_MAX_ROWS` rows).
         */
        @AuraEnabled
        public Boolean hasMoreGroups = false;
        @AuraEnabled
        public BarDimensionInfo groupBy;
        @AuraEnabled
        public BarDimensionInfo stackBy;

        BarResult(String aggregateFunction, QueryScope scope, BarGrouping grouping) {
            super(aggregateFunction, scope);
            this.groupBy = grouping.groupBy.info();
            this.stackBy = grouping.stackBy == null ? null : grouping.stackBy.info();
        }
    }

    public class BarBucket {
        /** Sortable group key (record Id, picklist API value, `2026-03`, `2026-Q1`, `FY2026`...); null bucket = null. */
        @AuraEnabled
        public String groupValue;
        /** Display label (reference name, translated picklist label, formatted date bucket); null bucket = null. */
        @AuraEnabled
        public String groupLabel;
        @AuraEnabled
        public String stackValue;
        @AuraEnabled
        public String stackLabel;
        @AuraEnabled
        public Object value;
    }

    public class BarDimensionInfo {
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

        TableColumn(Schema.DescribeSObjectResult objectDescribe, Map<String, Object> config) {
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
            ResolvedField field = resolveTablePath(objectDescribe, rawPath);
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
            Boolean primaryName = isNameField || PRIMARY_NAME_FIELDS.contains(field.describe.getName().toLowerCase());
            if (linkMode == 'always' || (linkMode == 'auto' && primaryName)) {
                linkPath = recordIdPath(objectDescribe, fieldPath);
            }
        }
    }

    /** One Table record: `id` plus flattened `path -> value` for every selected column and link path. */
    public class TableRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Map<String, Object> values = new Map<String, Object>();
        /**
         * Child records (capped at the child row limit); null when the Table has no `childRelationship`, or when
         * the count is unknown (`childCountCapped` true: too many children on the page to count them all).
         */
        @AuraEnabled
        public Integer childCount;
        /** True when the parent has more children than `childCount` shows (the badge renders `N+`). */
        @AuraEnabled
        public Boolean childCountCapped;
        /** True when the row matched the text search via a child record and `children` holds the matches. */
        @AuraEnabled
        public Boolean autoExpanded;
        /** Search-matched child rows (batch-fetched with the page); null unless `autoExpanded`. */
        @AuraEnabled
        public ChildRowsResult children;

        TableRow(SObject record) {
            id = record.Id;
            flattenRecord(record, '', values);
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
        /** Rows the cursor spans (`getNumRecords()`, at most `TABLE_MAX_ROWS`). */
        @AuraEnabled
        public Integer totalCount;
        /** Rows deleted since the cursor opened that this page skipped. */
        @AuraEnabled
        public Integer deletedRows;
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
        @AuraEnabled
        public List<String> appliedFilterIds;
        @AuraEnabled
        public List<String> ignoredFilterIds;
        /**
         * Child records matched by a `SOSL` text search on the Table's `childRelationship`; pass them back as
         * `childConfig.matchedChildIds` to `fetchTablePage` so later pages auto-expand too.
         */
        @AuraEnabled
        public List<Id> searchChildIds = new List<Id>();

        TableResult(QueryScope scope) {
            appliedFilterIds = scope.appliedFilterIds;
            ignoredFilterIds = scope.ignoredFilterIds;
        }

        void copyPage(TablePage page) {
            paginationCursor = page.paginationCursor;
            rows = page.rows;
            start = page.start;
            nextIndex = page.nextIndex;
            hasMore = page.hasMore;
            totalCount = page.totalCount;
            deletedRows = page.deletedRows;
        }
    }

    /** One expanded parent row's child sub-table. */
    public class ChildRowsResult {
        @AuraEnabled
        public Id parentId;
        @AuraEnabled
        public List<TableColumn> columns = new List<TableColumn>();
        @AuraEnabled
        public List<TableRow> rows = new List<TableRow>();
        /** Canonical child sort path (null for the default `Id ASC` order). */
        @AuraEnabled
        public String sortBy;
        @AuraEnabled
        public String sortDirection;
        /** True when the parent has more children than the configured `limit`. */
        @AuraEnabled
        public Boolean hasMore;
    }
}