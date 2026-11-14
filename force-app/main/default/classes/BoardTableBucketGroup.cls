/**
 * Row grouping by a Bucket field (`groupBy: [{ fieldPath: 'bucket:<id>' }]`, see `BoardBucketField`): with Detail rows
 * off only, an aggregated table with one Group row per bucket (one level: a second group field is a config error, as
 * the per-bucket rule predicates would have to be crossed with it). Detail rows on, an order field
 * and any column other than the Bucket field itself or a column with summaries are config errors.
 *
 * Like the Chart widget grouped by a Bucket field: in the SOQL tier one aggregate per bucket,
 * `WHERE <scope> AND rule_i AND NOT(rule_1..i-1)` (`BoardBucketField.predicates`); above the single-aggregate row
 * threshold the cursor tier (`BoardTableAggregateCursor`) labels each record in memory (`BoardBucketField.labelOf`)
 * and folds it with `BoardTableAggregateEngine`. Both tiers order the Group rows with the engine: rule order (then the
 * fallback bucket), reversed for `DESC`, or by a summary (`orderBySummary`); a Row limit keeps the top N. Buckets
 * without records have no Group row; rows the fallback excludes are left out (also from the count and Total row).
 */
public with sharing class BoardTableBucketGroup {
    /** `GroupField.dataType` of a Bucket field group (as the Chart widget's Bucket dimension). */
    public static final String GROUP_DATA_TYPE = 'BUCKET';
    private static final String COUNT_ALIAS = 'recordCount';

    private final BoardQueryService.QueryScope scope;
    private final BoardBucketField bucketField;
    /** `bucket:<id>`: the group key path, and the Bucket column's `fieldPath`. */
    private final String keyPath;
    private final List<BoardTableEngine.SummarySpec> specs;
    private final BoardTableAggregateEngine.Plan plan = new BoardTableAggregateEngine.Plan();
    /** Cursor tier: every field read per record (summarized fields and rule fields), by the path it is keyed under. */
    private final Map<String, BoardQueryService.ResolvedField> readFields = new Map<String, BoardQueryService.ResolvedField>();
    private Integer groupLimit;

    /** True when any group field of the request is a Bucket field. */
    public static Boolean isRequested(Map<String, Object> request) {
        for (Object entry : BoardQueryService.getList(request, 'groupBy')) {
            if (BoardBucketField.referencedId(groupPath(entry)) != null) {
                return true;
            }
        }
        return false;
    }

    /**
     * Fills `result` (columns, Row actions and Data bar scales already resolved) with one Group row per bucket, the
     * record count and, when `totalSpecs` is set, the Total row over the Group rows shown.
     */
    public static BoardQueryService.TableResult run(
        BoardQueryService.QueryScope scope,
        Map<String, Object> request,
        BoardQueryService.TableResult result,
        List<BoardTableEngine.SummarySpec> totalSpecs
    ) {
        if (!BoardTableAggregate.isRequested(request)) {
            throw configError('A Table can group by a Bucket field with Detail rows off only.');
        }
        List<Object> groupBy = BoardQueryService.getList(request, 'groupBy');
        if (groupBy.size() > 1) {
            throw configError('A Table grouped by a Bucket field has no second group field.');
        }
        Map<String, Object> entry = BoardQueryService.asMap(groupBy[0]);
        if (String.isNotBlank(BoardQueryService.getString(entry, 'orderBy'))) {
            throw configError('Groups of a Bucket field are ordered by rule order or by a summary.');
        }
        BoardTableBucketGroup bucketGroup = new BoardTableBucketGroup(scope, request, entry, result);
        result.rows = new List<BoardQueryService.TableRow>();
        result.start = 0;
        result.hasMore = false;
        result.deletedRows = 0;
        if (BoardTableAggregateCursor.isContinuation(request)) {
            return bucketGroup.runCursorTier(request, result, totalSpecs);
        }
        Integer scopeRows = BoardTableAggregateCursor.countWithinCap(scope);
        if (BoardTableAggregateCursor.exceedsSingleAggregate(scopeRows)) {
            return bucketGroup.runCursorTier(request, result, totalSpecs);
        }
        return bucketGroup.finish(result, bucketGroup.queryBuckets(), totalSpecs);
    }

    private BoardTableBucketGroup(
        BoardQueryService.QueryScope scope,
        Map<String, Object> request,
        Map<String, Object> entry,
        BoardQueryService.TableResult result
    ) {
        this.scope = scope;
        bucketField = BoardBucketField.find(
            BoardQueryService.getList(request, 'bucketFields'),
            BoardQueryService.getList(request, 'boardBucketFields'),
            BoardBucketField.referencedId(groupPath(entry))
        );
        scope.compileBucketRules(bucketField);
        keyPath = BoardBucketField.REFERENCE_PREFIX + bucketField.id;
        specs = BoardTableQuery.columnSummarySpecs(request, result.columns);
        rejectOtherColumns(result.columns);
        String direction = 'DESC'.equalsIgnoreCase(BoardQueryService.getString(entry, 'sortDirection'))
            ? 'DESC'
            : 'ASC';
        plan.keyPath = keyPath;
        plan.specs = specs;
        plan.direction = direction;
        plan.rankedValues.put(keyPath.toLowerCase(), bucketField.labels());
        result.sortBy = null;
        orderBySummary(entry.get('orderBySummary'), result);
        result.sortDirection = result.sortBy == null ? null : direction;
        result.groupField = groupField(direction);
        groupLimit = BoardTableRowLimit.resolveGroupLimit(request.get('rowLimit'), false);
        for (BoardTableEngine.SummarySpec spec : specs) {
            readFields.put(spec.fieldPath, BoardTableQuery.resolveTablePath(scope.objectDescribe, spec.fieldPath));
        }
        for (String path : bucketField.paths()) {
            readFields.put(path, BoardTableQuery.resolveTablePath(scope.objectDescribe, path));
        }
    }

    private static String groupPath(Object entry) {
        return entry instanceof Map<String, Object>
            ? BoardQueryService.getString((Map<String, Object>) entry, 'fieldPath')
            : null;
    }

    private BoardTableGrouping.GroupField groupField(String direction) {
        BoardTableGrouping.GroupField field = new BoardTableGrouping.GroupField();
        field.fieldPath = keyPath;
        field.keyPath = keyPath;
        field.label = String.isBlank(bucketField.label) ? bucketField.id : bucketField.label;
        field.dataType = GROUP_DATA_TYPE;
        field.sortDirection = direction;
        return field;
    }

    /** Each column is the Bucket field itself (its label per Group row) or a column with summaries. */
    private void rejectOtherColumns(List<BoardQueryService.TableColumn> columns) {
        Set<String> summarized = new Set<String>();
        for (BoardTableEngine.SummarySpec spec : specs) {
            summarized.add(spec.columnId);
        }
        for (BoardQueryService.TableColumn column : columns) {
            if (!summarized.contains(column.id) && !keyPath.equalsIgnoreCase(column.fieldPath)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Grouped by a Bucket field, a column shows the Bucket field or summaries: ' + column.fieldPath,
                    null,
                    'columns'
                );
            }
        }
    }

    /** Orders the Group rows by a summary the Table shows (`{ columnId, summaryFunction }`), if requested. */
    private void orderBySummary(Object rawSummaryOrder, BoardQueryService.TableResult result) {
        if (rawSummaryOrder == null) {
            return;
        }
        result.sortBy = plan.orderBySummary(rawSummaryOrder).fieldPath;
    }

    // ---- SOQL tier -----------------------------------------------------------------------------------------

    /** One aggregate per bucket (sum, count, min and max of each summarized field); empty buckets are skipped. */
    private List<BoardTableAggregateEngine.AggregatedGroup> queryBuckets() {
        List<String> selectParts = new List<String>{ 'COUNT(Id) ' + COUNT_ALIAS };
        for (Integer c = 0; c < specs.size(); c++) {
            String path = specs[c].fieldPath;
            selectParts.add('SUM(' + path + ') s' + c);
            selectParts.add('COUNT(' + path + ') n' + c);
            selectParts.add('MIN(' + path + ') l' + c);
            selectParts.add('MAX(' + path + ') h' + c);
        }
        String selectClause = String.join(selectParts, ', ');
        Map<String, String> bucketPredicates = bucketField.predicates(scope);
        List<BoardTableAggregateEngine.AggregatedGroup> groups = new List<BoardTableAggregateEngine.AggregatedGroup>();
        for (String bucketLabel : bucketField.labels()) {
            String soql = scope.buildSoql(selectClause, new List<String>{ bucketPredicates.get(bucketLabel) }, '');
            List<SObject> rows = Database.queryWithBinds(soql, scope.binds, AccessLevel.USER_MODE);
            AggregateResult aggregate = (AggregateResult) rows[0];
            Integer count = Integer.valueOf(aggregate.get(COUNT_ALIAS));
            if (count == null || count == 0) {
                continue;
            }
            BoardTableAggregateEngine.AggregatedGroup bucketGroup = new BoardTableAggregateEngine.AggregatedGroup();
            bucketGroup.key = bucketLabel;
            bucketGroup.count = count;
            bucketGroup.values.put(keyPath, bucketLabel);
            for (Integer c = 0; c < specs.size(); c++) {
                BoardTableEngine.Summary summary = new BoardTableEngine.Summary();
                summary.addAggregate(
                    aggregate.get('s' + c),
                    aggregate.get('n' + c),
                    aggregate.get('l' + c),
                    aggregate.get('h' + c)
                );
                bucketGroup.summaries.add(summary);
            }
            groups.add(bucketGroup);
        }
        return groups;
    }

    // ---- Cursor tier ---------------------------------------------------------------------------------------

    /**
     * Reads the next cursor chunk, labels each record with its bucket and folds it into the running groups (restored
     * from the request's `partialState`). An incomplete load returns only its progress and running state.
     */
    private BoardQueryService.TableResult runCursorTier(
        Map<String, Object> request,
        BoardQueryService.TableResult result,
        List<BoardTableEngine.SummarySpec> totalSpecs
    ) {
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        Map<String, String> isoPathByPath = new Map<String, String>();
        for (String path : readFields.keySet()) {
            BoardQueryService.ResolvedField field = readFields.get(path);
            isoPathByPath.put(path, converter.isoCodePath(field.path, field.type));
        }
        BoardTableAggregateCursor.Chunk chunk = BoardTableAggregateCursor.read(scope, request, isoPathByPath);
        BoardTableAggregateEngine.Accumulator accumulator = new BoardTableAggregateEngine.Accumulator(plan)
            .restore(BoardQueryService.getString(request, 'partialState'));
        for (Map<String, Object> row : chunk.rows) {
            String bucketLabel = bucketField.labelOf(row);
            if (bucketLabel == null) {
                continue; // Matches no rule and the fallback bucket is excluded.
            }
            row.put(keyPath, bucketLabel);
            accumulator.add(row);
        }
        result.aggregateCursor = chunk.progress;
        if (!chunk.progress.isComplete) {
            chunk.progress.partialState = accumulator.state();
            result.totalCount = chunk.progress.totalRows;
            result.nextIndex = result.totalCount;
            result.aggregateGroups = new List<BoardTableAggregate.GroupRow>();
            return result;
        }
        return finish(result, accumulator.groups(), totalSpecs);
    }

    // ---- Both tiers ----------------------------------------------------------------------------------------

    /** Orders the groups, keeps the top N under a Row limit, and sets the Group rows, count and Total row. */
    private BoardQueryService.TableResult finish(
        BoardQueryService.TableResult result,
        List<BoardTableAggregateEngine.AggregatedGroup> groups,
        List<BoardTableEngine.SummarySpec> totalSpecs
    ) {
        List<BoardTableAggregateEngine.AggregatedGroup> ordered = BoardTableAggregateEngine.orderGroups(groups, plan);
        if (groupLimit != null && ordered.size() > groupLimit) {
            ordered = BoardTableAggregateEngine.topGroups(ordered, groupLimit);
            result.groupLimit = groupLimit;
        }
        result.totalCount = 0;
        result.aggregateGroups = new List<BoardTableAggregate.GroupRow>();
        for (BoardTableAggregateEngine.AggregatedGroup bucketGroup : ordered) {
            result.totalCount += bucketGroup.count;
            result.aggregateGroups.add(toGroupRow(bucketGroup));
        }
        result.nextIndex = result.totalCount;
        if (totalSpecs != null) {
            // Totals over the Group rows are corporate; currency columns' summaries are returned in the Display currency.
            result.totals = BoardCurrencyConverter.forRequest()
                .totalsToDisplay(BoardTableAggregateEngine.grandTotals(ordered, specs), result.columns);
        }
        return result;
    }

    private BoardTableAggregate.GroupRow toGroupRow(BoardTableAggregateEngine.AggregatedGroup bucketGroup) {
        BoardTableAggregate.GroupRow groupRow = new BoardTableAggregate.GroupRow();
        groupRow.key = bucketGroup.key;
        groupRow.label = bucketGroup.key;
        groupRow.count = bucketGroup.count;
        groupRow.values = new Map<String, Object>{ keyPath => bucketGroup.key };
        groupRow.summaries = BoardTableAggregateEngine.summaries(bucketGroup, specs);
        return groupRow;
    }

    private static BoardErrors.BoardException configError(String message) {
        return BoardErrors.error(BoardErrors.CONFIG_ERROR, message, null, 'groupBy');
    }
}