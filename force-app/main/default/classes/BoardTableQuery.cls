/**
 * Table Widget query execution (`Database.PaginationCursor` infinite scroll).
 *
 * Opens the first page, fetches later pages from the pagination cursor, and resolves Table columns and sorting. The
 * `@AuraEnabled` entry points (`queryTable`, `fetchTablePage`) stay on `BoardQueryService`, which parses the request,
 * compiles its data scope (Filter bindings, base filters, text search) with the shared `QueryScope`, and converts
 * failures with `BoardErrors`. Summary computation over in-memory rows lives in `BoardTableEngine`.
 */
public with sharing class BoardTableQuery {
    /** Max rows a Table `Database.PaginationCursor` spans (platform pagination cursor limit). */
    @TestVisible
    private static Integer TABLE_MAX_ROWS = 100000;
    private static final Integer TABLE_DEFAULT_PAGE_SIZE = 25;
    private static final Integer TABLE_MIN_PAGE_SIZE = 10;
    private static final Integer TABLE_MAX_PAGE_SIZE = 100;
    /** `fieldPath` of the retryable `QUERY_ERROR` raised for an expired/invalid cursor; the Table re-opens it. */
    private static final String PAGINATION_CURSOR_PATH = 'paginationCursor';
    /** Leaf fields linked by `linkToRecord: 'auto'` in addition to describe name fields. */
    public static final Set<String> PRIMARY_NAME_FIELDS = new Set<String>{ 'name', 'casenumber', 'subject' };
    /** Column types (`Schema.DisplayType` names) a Total row can summarize. */
    private static final Set<String> SUMMARIZABLE_TYPES = new Set<String>{
        'CURRENCY',
        'DOUBLE',
        'INTEGER',
        'LONG',
        'PERCENT'
    };
    /** Most records a whole-scope Total row aggregates in one request (aggregated rows count as query rows). */
    @TestVisible
    private static Integer TOTALS_MAX_ROWS = 50000;

    /**
     * Page at `start` of a cursor returned by `queryTable` (see `BoardQueryService.fetchTablePage`), currency cells in
     * `displayCurrency`.
     */
    public static BoardQueryService.TablePage fetchPage(
        String paginationCursor,
        Integer start,
        Integer pageSize,
        String displayCurrency
    ) {
        String isoCode = displayIsoCode(new Map<String, Object>{ 'displayCurrency' => displayCurrency });
        return fetchPage(paginationCursor, start, pageSize, new CellCurrency(isoCode, null));
    }

    private static BoardQueryService.TablePage fetchPage(
        String paginationCursor,
        Integer start,
        Integer pageSize,
        CellCurrency cells
    ) {
        return fetchTableRows(
            deserializePaginationCursor(paginationCursor),
            paginationCursor,
            start == null ? 0 : Math.max(0, start),
            clampPageSize(pageSize),
            cells
        );
    }

    /** Child rows were removed from the Table: a saved `childRelationship` is a config error, not migrated. */
    public static void rejectChildRelationship(Map<String, Object> request) {
        if (request.get('childRelationship') != null) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Child rows were replaced by Row grouping: use the child object as source and group by the parent.',
                null,
                'childRelationship'
            );
        }
    }

    public static BoardQueryService.TableResult runTable(
        BoardQueryService.QueryScope scope,
        Map<String, Object> request
    ) {
        BoardQueryService.TableResult result = new BoardQueryService.TableResult(scope);
        result.columns = resolveTableColumns(
            scope.objectDescribe,
            BoardQueryService.getList(request, 'columns'),
            'columns'
        );
        BoardCurrencyConverter.forRequest().stampTableColumns(result.columns, request);
        CellCurrency cells = new CellCurrency(displayIsoCode(request), result.columns);
        BoardTableBucketColumns bucketColumns = BoardTableBucketColumns.resolve(scope, request, result.columns);
        result.rowActions = resolveRowActionTargets(
            scope.objectDescribe,
            BoardQueryService.getList(request, 'rowActions')
        );
        TableOrder order = new TableOrder(
            scope.objectDescribe,
            BoardQueryService.getString(request, 'sortBy'),
            BoardQueryService.getString(request, 'sortDirection')
        );
        result.sortBy = order.sortBy;
        result.sortDirection = order.sortDirection;
        List<BoardQueryService.TableColumn> barColumns = dataBarColumns(
            result.columns,
            BoardQueryService.getList(request, 'columns')
        );

        if (BoardTableBucketGroup.isRequested(request)) {
            return BoardTableCurrency.groupRowsToDisplay(
                BoardTableBucketGroup.run(scope, request, result, totalRowSpecs(request, result.columns))
            );
        }
        BoardTableGrouping grouping = BoardTableGrouping.fromRequest(scope.objectDescribe, request);

        List<BoardTableEngine.SummarySpec> totalSpecs = totalRowSpecs(request, result.columns);

        if (grouping != null && BoardTableAggregate.isRequested(request)) {
            return withGroupBarScales(
                BoardTableCurrency.groupRowsToDisplay(
                    BoardTableAggregate.run(scope, request, result, grouping, totalSpecs)
                ),
                barColumns
            );
        }
        result.barScales = BoardTableCurrency.recordBarScales(scope, barColumns);
        if (grouping != null) {
            BoardTableAggregate.rejectSummaryOrder(request);
            // A grouped Table's Row limit counts first-level groups: the stream below covers only the top N.
            result.groupLimit = BoardTableRowLimit.limitToTopGroups(scope, grouping, request);
        }
        Integer rowLimit = grouping != null
            ? null
            : BoardTableEngine.resolveRowLimit(request.get('rowLimit'), order.sortBy);
        if (rowLimit != null) {
            result.copyPage(limitedPage(scope, result, order, rowLimit, cells));
            bucketColumns.labelRows(result.rows);
            result.rowLimit = rowLimit;
            if (totalSpecs != null) {
                result.totals = BoardTableEngine.totalsOverRows(rowValues(result.rows), totalSpecs);
            }
            return result;
        }

        String selectList = tableSelectList(result.columns, result.rowActions);
        String orderClause = order.clause;
        if (grouping != null) {
            selectList = grouping.extendSelect(selectList);
            orderClause = grouping.orderClause(order.sortBy, order.clause);
        }
        String soql = scope.buildSoql(selectList, null, 'ORDER BY ' + orderClause + ' LIMIT ' + TABLE_MAX_ROWS);
        Database.PaginationCursor cursor = Database.getPaginationCursorWithBinds(
            soql,
            scope.binds,
            AccessLevel.USER_MODE
        );
        Integer start = BoardQueryService.getInteger(request, 'start');
        result.copyPage(
            fetchTableRows(
                cursor,
                JSON.serialize(cursor),
                start == null ? 0 : Math.max(0, start),
                clampPageSize(BoardQueryService.getInteger(request, 'pageSize')),
                cells
            )
        );
        bucketColumns.labelRows(result.rows);
        if (grouping != null) {
            grouping.summarySpecs = columnSummarySpecs(request, result.columns);
            result.groupField = grouping.resolvedField;
            result.groups = BoardTableCurrency.groupsToDisplay(grouping.pageGroups(scope, result.rows), result.columns);
        }
        // A cursor re-opened mid-scroll (`start` > 0) keeps the Total row the Widget already has.
        if (totalSpecs != null && result.start == 0) {
            applyScopeTotals(scope, result, totalSpecs);
        }
        return result;
    }

    // ---- Total row ---------------------------------------------------------------------------------------------

    /** Total row specs: null when the Total row is off, else the column summary specs. */
    private static List<BoardTableEngine.SummarySpec> totalRowSpecs(
        Map<String, Object> request,
        List<BoardQueryService.TableColumn> columns
    ) {
        Object showTotalRow = request.get('showTotalRow');
        if (!(showTotalRow instanceof Boolean) || !((Boolean) showTotalRow)) {
            return null;
        }
        return columnSummarySpecs(request, columns);
    }

    /**
     * One spec per column with Stacked summaries (in column order), shared by Group, Subtotal and Total rows.
     * Summaries on a non-numeric column are a config error.
     */
    public static List<BoardTableEngine.SummarySpec> columnSummarySpecs(
        Map<String, Object> request,
        List<BoardQueryService.TableColumn> columns
    ) {
        List<Object> rawColumns = BoardQueryService.getList(request, 'columns');
        List<BoardTableEngine.SummarySpec> specs = new List<BoardTableEngine.SummarySpec>();
        for (Integer i = 0; i < columns.size(); i++) {
            BoardQueryService.TableColumn column = columns[i];
            List<String> functions = BoardTableEngine.resolveSummaryFunctions(
                BoardQueryService.asMap(rawColumns[i]).get('summaries'),
                column.id
            );
            if (functions.isEmpty()) {
                continue;
            }
            if (!SUMMARIZABLE_TYPES.contains(column.dataType)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Summaries need a number, currency or percent column: ' + column.id,
                    null,
                    'columns'
                );
            }
            specs.add(new BoardTableEngine.SummarySpec(column.id, column.fieldPath, functions));
        }
        return specs;
    }

    /**
     * Whole-scope Total row from one aggregate query, unless the scope spans more records than this request may
     * aggregate: then the Total row is flagged unavailable rather than failing the Table.
     */
    public static void applyScopeTotals(
        BoardQueryService.QueryScope scope,
        BoardQueryService.TableResult result,
        List<BoardTableEngine.SummarySpec> specs
    ) {
        Integer rowBudget = Math.min(TOTALS_MAX_ROWS, Limits.getLimitQueryRows() - Limits.getQueryRows());
        if (result.totalCount != null && result.totalCount > rowBudget) {
            result.totalRowUnavailable = true;
            return;
        }
        // SOQL totals are corporate; currency columns' summaries are returned in the Display currency, their MIN/MAX
        // from the extreme record converted record -> Display.
        result.totals = BoardTableCurrency.scopeExtremesToDisplay(
            scope,
            BoardCurrencyConverter.forRequest().totalsToDisplay(scopeTotals(scope, specs), result.columns),
            specs,
            result.columns
        );
    }

    /** `SELECT SUM(Amount) t0_0, AVG(Amount) t0_1, ... FROM <scope>`: every column's summaries in one query. */
    private static List<BoardTableEngine.ColumnTotal> scopeTotals(
        BoardQueryService.QueryScope scope,
        List<BoardTableEngine.SummarySpec> specs
    ) {
        List<BoardTableEngine.ColumnTotal> totals = new List<BoardTableEngine.ColumnTotal>();
        List<String> aggregates = new List<String>();
        for (Integer c = 0; c < specs.size(); c++) {
            for (Integer f = 0; f < specs[c].functions.size(); f++) {
                aggregates.add(specs[c].functions[f] + '(' + specs[c].fieldPath + ') ' + totalAlias(c, f));
            }
        }
        if (aggregates.isEmpty()) {
            return totals;
        }
        AggregateResult aggregate = (AggregateResult) Database.queryWithBinds(
            scope.buildSoql(String.join(aggregates, ', '), null, ''),
            scope.binds,
            AccessLevel.USER_MODE
        )[0];
        for (Integer c = 0; c < specs.size(); c++) {
            BoardTableEngine.ColumnTotal total = new BoardTableEngine.ColumnTotal(specs[c].columnId);
            for (Integer f = 0; f < specs[c].functions.size(); f++) {
                total.add(specs[c].functions[f], aggregate.get(totalAlias(c, f)));
            }
            totals.add(total);
        }
        return totals;
    }

    private static String totalAlias(Integer columnIndex, Integer functionIndex) {
        return 't' + columnIndex + '_' + functionIndex;
    }

    private static List<Map<String, Object>> rowValues(List<BoardQueryService.TableRow> rows) {
        List<Map<String, Object>> values = new List<Map<String, Object>>();
        for (BoardQueryService.TableRow row : rows) {
            values.add(row.values);
        }
        return values;
    }

    /**
     * Page at `start` of a grouped Table's cursor, with the full-group counts of the groups on that page (the
     * request's scope and `groupBy` are recompiled for the page-scoped `GROUP BY`).
     */
    public static BoardQueryService.TablePage fetchGroupedPage(
        BoardQueryService.QueryScope scope,
        Map<String, Object> request,
        String paginationCursor,
        Integer start
    ) {
        BoardTableGrouping grouping = BoardTableGrouping.fromRequest(scope.objectDescribe, request);
        List<BoardQueryService.TableColumn> columns = resolveTableColumns(
            scope.objectDescribe,
            BoardQueryService.getList(request, 'columns'),
            'columns'
        );
        BoardCurrencyConverter.forRequest().stampTableColumns(columns, request);
        BoardQueryService.TablePage page = fetchPage(
            paginationCursor,
            start,
            BoardQueryService.getInteger(request, 'pageSize'),
            new CellCurrency(displayIsoCode(request), columns)
        );
        BoardTableBucketColumns.resolve(scope, request, columns).labelRows(page.rows);
        if (grouping != null) {
            grouping.summarySpecs = columnSummarySpecs(request, columns);
            page.groups = BoardTableCurrency.groupsToDisplay(grouping.pageGroups(scope, page.rows), columns);
        }
        return page;
    }

    /**
     * Row limit (ungrouped): the first `rowLimit` records in the configured sort as one page with no cursor (no
     * infinite scroll), plus the full matching count for the "Top N of total" badge.
     */
    private static BoardQueryService.TablePage limitedPage(
        BoardQueryService.QueryScope scope,
        BoardQueryService.TableResult result,
        TableOrder order,
        Integer rowLimit,
        CellCurrency cells
    ) {
        String selectList = tableSelectList(result.columns, result.rowActions);
        List<SObject> records = Database.queryWithBinds(
            scope.buildSoql(selectList, null, 'ORDER BY ' + order.clause + ' LIMIT ' + rowLimit),
            scope.binds,
            AccessLevel.USER_MODE
        );
        BoardQueryService.TablePage page = new BoardQueryService.TablePage();
        page.rows.addAll(tableRows(records, cells));
        page.start = 0;
        page.nextIndex = records.size();
        page.hasMore = false;
        page.deletedRows = 0;
        page.totalCount = Database.countQueryWithBinds(
            scope.buildSoql('COUNT()', null, ''),
            scope.binds,
            AccessLevel.USER_MODE
        );
        return page;
    }

    /**
     * The columns configured `displayAs: 'dataBar'`, in column order; a Data bar on a non-numeric column is a config
     * error. `columns` are the resolved columns, in the same order as `rawColumns`.
     */
    private static List<BoardQueryService.TableColumn> dataBarColumns(
        List<BoardQueryService.TableColumn> columns,
        List<Object> rawColumns
    ) {
        List<BoardQueryService.TableColumn> barColumns = new List<BoardQueryService.TableColumn>();
        for (Integer i = 0; i < columns.size(); i++) {
            String displayAs = BoardQueryService.getString(BoardQueryService.asMap(rawColumns[i]), 'displayAs');
            if ('dataBar'.equalsIgnoreCase(displayAs)) {
                if (!BoardTableEngine.isDataBarType(columns[i].dataType)) {
                    throw BoardErrors.error(
                        BoardErrors.CONFIG_ERROR,
                        'A Data bar needs a number, currency or percent column: ' + columns[i].fieldPath,
                        null,
                        columns[i].fieldPath
                    );
                }
                barColumns.add(columns[i]);
            }
        }
        return barColumns;
    }

    /**
     * Detail rows off: Data bars sit on Group rows, so they are scaled over the Group rows (see
     * `BoardTableGroupBarScales`), not the records. An incomplete cursor-tier chunk has no Group rows yet.
     */
    private static BoardQueryService.TableResult withGroupBarScales(
        BoardQueryService.TableResult result,
        List<BoardQueryService.TableColumn> barColumns
    ) {
        result.barScales = BoardTableGroupBarScales.overGroups(barColumns, result.aggregateGroups);
        return result;
    }

    private static List<BoardQueryService.TableColumn> resolveTableColumns(
        Schema.DescribeSObjectResult objectDescribe,
        List<Object> rawColumns,
        String configPath
    ) {
        List<BoardQueryService.TableColumn> columns = new List<BoardQueryService.TableColumn>();
        for (Object rawColumn : rawColumns) {
            Map<String, Object> config = BoardQueryService.asMap(rawColumn);
            columns.add(
                BoardTableBucketColumns.isBucketColumn(config)
                    ? BoardTableBucketColumns.column(config)
                    : new BoardQueryService.TableColumn(objectDescribe, config)
            );
        }
        if (columns.isEmpty()) {
            throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'A table needs at least one column.', null, configPath);
        }
        return columns;
    }

    /**
     * Validates each Row action's `target` (blank or `Id` = the row's record, else a reference field path such as
     * `AccountId` or `Account.OwnerId`) and resolves the object the target Id points to (null when polymorphic).
     */
    private static List<BoardQueryService.RowActionTarget> resolveRowActionTargets(
        Schema.DescribeSObjectResult objectDescribe,
        List<Object> rawActions
    ) {
        List<BoardQueryService.RowActionTarget> targets = new List<BoardQueryService.RowActionTarget>();
        for (Object rawAction : rawActions) {
            Map<String, Object> action = BoardQueryService.asMap(rawAction);
            String rawTarget = BoardQueryService.getString(action, 'target');
            BoardQueryService.RowActionTarget target = new BoardQueryService.RowActionTarget();
            target.id = BoardQueryService.getString(action, 'id');
            String actionType = BoardQueryService.getString(action, 'type');
            if ('create'.equalsIgnoreCase(actionType)) {
                resolveCreateAction(objectDescribe, action, target);
            } else if ('flow'.equalsIgnoreCase(actionType)) {
                resolveFlowAction(objectDescribe, action, target);
            } else if (String.isBlank(rawTarget) || rawTarget.trim().equalsIgnoreCase('Id')) {
                target.targetPath = 'Id';
                target.targetObjectApiName = objectDescribe.getName();
            } else {
                BoardQueryService.ResolvedField field = resolveTablePath(objectDescribe, rawTarget);
                if (field.type != Schema.DisplayType.REFERENCE) {
                    throw BoardErrors.error(
                        BoardErrors.CONFIG_ERROR,
                        'A Row action target must be a lookup field: ' + rawTarget,
                        null,
                        rawTarget
                    );
                }
                target.targetPath = field.path;
                List<Schema.SObjectType> referenceTo = field.describe.getReferenceTo();
                target.targetObjectApiName = referenceTo.size() == 1 ? referenceTo[0].getDescribe().getName() : null;
            }
            targets.add(target);
        }
        return targets;
    }

    /**
     * A Create action targets the row's own record (`Id`), reports the object to create (checked to exist) and
     * resolves the row fields its default values map from (`fields`) so they are fetched with each row.
     */
    private static void resolveCreateAction(
        Schema.DescribeSObjectResult objectDescribe,
        Map<String, Object> action,
        BoardQueryService.RowActionTarget target
    ) {
        String objectApiName = BoardQueryService.getString(action, 'object');
        Schema.SObjectType createType = String.isBlank(objectApiName)
            ? null
            : BoardDescribe.getGlobalDescribe().get(objectApiName.trim());
        if (createType == null) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'A Create row action needs an object: ' + objectApiName,
                null,
                objectApiName
            );
        }
        target.targetPath = 'Id';
        target.targetObjectApiName = createType.getDescribe().getName();
        addMappedFieldPaths(objectDescribe, action, target);
    }

    /**
     * A Screen Flow action runs on the row's own record (`Id`) and resolves the row fields its input variables map
     * from (`fields`) so they are fetched with each row.
     */
    private static void resolveFlowAction(
        Schema.DescribeSObjectResult objectDescribe,
        Map<String, Object> action,
        BoardQueryService.RowActionTarget target
    ) {
        target.targetPath = 'Id';
        target.targetObjectApiName = objectDescribe.getName();
        addMappedFieldPaths(objectDescribe, action, target);
    }

    private static void addMappedFieldPaths(
        Schema.DescribeSObjectResult objectDescribe,
        Map<String, Object> action,
        BoardQueryService.RowActionTarget target
    ) {
        for (Object rawField : BoardQueryService.getList(action, 'fields')) {
            target.fieldPaths.add(resolveTablePath(objectDescribe, String.valueOf(rawField)).path);
        }
    }

    /**
     * `Id` plus each column's `fieldPath` and `linkPath` (and a currency column's `CurrencyIsoCode`, for conversion)
     * and each Row action's target, case-insensitively deduped.
     */
    private static String tableSelectList(
        List<BoardQueryService.TableColumn> columns,
        List<BoardQueryService.RowActionTarget> rowActions
    ) {
        List<String> selectPaths = new List<String>{ 'Id' };
        Set<String> selected = new Set<String>{ 'id' };
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        for (BoardQueryService.TableColumn column : columns) {
            List<String> columnPaths = column.fetchPaths != null
                ? column.fetchPaths
                : new List<String>{ column.fieldPath, column.linkPath, converter.tableIsoCodePath(column) };
            for (String path : columnPaths) {
                if (path != null && selected.add(path.toLowerCase())) {
                    selectPaths.add(path);
                }
            }
        }
        for (BoardQueryService.RowActionTarget rowAction : rowActions) {
            List<String> actionPaths = new List<String>{ rowAction.targetPath };
            actionPaths.addAll(rowAction.fieldPaths);
            for (String actionPath : actionPaths) {
                if (selected.add(actionPath.toLowerCase())) {
                    selectPaths.add(actionPath);
                }
            }
        }
        return String.join(selectPaths, ', ');
    }

    /** Fetches one page with the prototype-verified final-page `fetchSize` clamp and `getNextIndex()` wrap guard. */
    private static BoardQueryService.TablePage fetchTableRows(
        Database.PaginationCursor paginationCursor,
        String cursorJson,
        Integer start,
        Integer pageSize,
        CellCurrency cells
    ) {
        BoardQueryService.TablePage page = new BoardQueryService.TablePage();
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
        } catch (System.TransientCursorException cursorError) {
            throw paginationCursorExpired();
        } catch (System.FatalCursorException cursorError) {
            throw paginationCursorExpired();
        }
        if (start > totalRecords) {
            // A cursor that cannot reach rows the caller already read is no longer the one it opened.
            throw paginationCursorExpired();
        }
        page.rows.addAll(tableRows(records, cells));
        page.paginationCursor = cursorJson;
        page.start = start;
        page.nextIndex = nextIndex;
        page.totalCount = totalRecords;
        page.deletedRows = deletedRows;
        page.hasMore = nextIndex < totalRecords && !records.isEmpty();
        return page;
    }

    /** Readable rows of `records`, currency cells converted from each record's currency to the Display currency. */
    private static List<BoardQueryService.TableRow> tableRows(List<SObject> records, CellCurrency cells) {
        List<BoardQueryService.TableRow> rows = new List<BoardQueryService.TableRow>();
        if (records.isEmpty()) {
            return rows;
        }
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        for (SObject record : Security.stripInaccessible(AccessType.READABLE, records).getRecords()) {
            rows.add(
                converter.rowToDisplay(
                    new BoardQueryService.TableRow(record),
                    record,
                    cells.displayIsoCode,
                    cells.paths
                )
            );
        }
        return rows;
    }

    /**
     * The Display currency of a page's currency cells and which cells convert: the currency columns' `fieldPath`s
     * (lower case), so fields fetched only for Bucket field rules or Row actions keep the record's own amount. Null
     * paths (a plain later page, which has no Bucket field columns) convert every fetched currency field.
     */
    private class CellCurrency {
        public String displayIsoCode;
        public Set<String> paths;

        CellCurrency(String displayIsoCode, List<BoardQueryService.TableColumn> columns) {
            this.displayIsoCode = displayIsoCode;
            if (columns != null) {
                paths = new Set<String>();
                for (BoardQueryService.TableColumn column : columns) {
                    if (column.currencyIsoCode != null) {
                        paths.add(column.fieldPath.toLowerCase());
                    }
                }
            }
        }
    }

    /** The request's Display currency (validated; default: the viewer's currency). */
    private static String displayIsoCode(Map<String, Object> request) {
        return BoardCurrencyConverter.forRequest().displayIsoCode(request);
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
    public static BoardQueryService.ResolvedField resolveTablePath(
        Schema.DescribeSObjectResult objectDescribe,
        String path
    ) {
        String compactPath = path.deleteWhitespace();
        if (compactPath.contains('(')) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Table columns support direct fields and parent paths only: ' + path,
                null,
                path
            );
        }
        return BoardQueryService.resolveFieldPath(objectDescribe, compactPath, null, path);
    }

    /** Record ID path a column links to: `Id` for direct fields, the last hop's reference field for parent paths. */
    public static String recordIdPath(Schema.DescribeSObjectResult rootDescribe, String canonicalPath) {
        List<String> segments = canonicalPath.split('\\.');
        if (segments.size() == 1) {
            return 'Id';
        }
        Schema.DescribeSObjectResult current = rootDescribe;
        Schema.DescribeFieldResult reference;
        for (Integer i = 0; i < segments.size() - 1; i++) {
            reference = BoardQueryService.relationshipIndex(current).get(segments[i].toLowerCase()).getDescribe();
            current = BoardDescribe.describeObject(BoardQueryService.parentType(reference));
        }
        segments[segments.size() - 2] = reference.getName();
        segments.remove(segments.size() - 1);
        return String.join(segments, '.');
    }

    /** Flattens a queried record into `path -> value` (e.g. `Account.Owner.Name`). */
    public static void flattenRecord(SObject record, String prefix, Map<String, Object> values) {
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
            if (BoardBucketField.referencedId(rawSortBy) != null) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'A Bucket field column is not sortable: ' + rawSortBy,
                    null,
                    rawSortBy
                );
            }
            BoardQueryService.ResolvedField sortField = resolveTablePath(objectDescribe, rawSortBy);
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
}