/**
 * Row grouping with Detail rows off: the Table as an aggregated table.
 *
 * One `GROUP BY` over the Table's scope returns every Group row at once (no cursor, no infinite scroll), each with its
 * record count, the Stacked summaries of the columns that have summaries, and the values of fields reached through a
 * lookup group field (constant per group, e.g. `Account.Industry` when grouped by `AccountId`). Every column must have
 * one meaning per group: the group field, a field through the group lookup, or a numeric column with summaries.
 * Groups are ordered by value, by a field constant per group (`orderBy`) or by a summary (`orderBySummary`), with
 * "(Blank)" last. Above `MAX_GROUPS` groups, or above the single-aggregate row threshold, the Table falls back to the
 * cursor tier (`BoardTableAggregateCursor`, `BoardTableAggregateEngine`) up to the cursor cap; above the cap it is
 * blocked.
 */
public with sharing class BoardTableAggregate {
    /** Most Group rows the SOQL tier returns (an aggregate query cannot page past 2,000 rows). */
    @TestVisible
    private static Integer MAX_GROUPS = 2000;
    private static final String KEY_ALIAS = 'groupKey';
    private static final String COUNT_ALIAS = 'recordCount';

    private BoardQueryService.QueryScope scope;
    private BoardTableGrouping.GroupField groupField;
    private Boolean isLookup;
    /** Lower-cased path prefix of fields reached through the lookup group field (e.g. `account.`), else null. */
    private String relationshipPrefix;
    private Map<String, String> picklistLabels = new Map<String, String>();
    private List<String> selectParts = new List<String>();
    private List<String> groupByPaths = new List<String>();
    /** Lower-cased path -> SOQL expression of a field constant per group (the grouped path, or `MAX(path)`). */
    private Map<String, String> expressionByPath = new Map<String, String>();
    /** Canonical path -> alias of a field constant per group in the aggregate result. */
    private Map<String, String> aliasByPath = new Map<String, String>();
    private List<BoardTableEngine.SummarySpec> specs = new List<BoardTableEngine.SummarySpec>();
    /** Row limit: the top N Group rows to keep (see `BoardTableRowLimit`); null when unlimited. */
    private Integer groupLimit;
    /** True when the scope had more groups than `groupLimit`, so the Group rows are the top N only. */
    private Boolean cutByGroupLimit = false;
    /**
     * SOQL tier: each Group row's mergeable `{ sum, count, min, max }` per summarized column, so the Total row is
     * merged from the Group rows (as the cursor tier does) instead of reading the scope again.
     */
    private List<BoardTableAggregateEngine.AggregatedGroup> groupPartials = new List<BoardTableAggregateEngine.AggregatedGroup>();
    /** Cursor tier: the same grouping, values, summaries and order, applied in memory. */
    private BoardTableAggregateEngine.Plan plan = new BoardTableAggregateEngine.Plan();
    /** Cursor tier: every field the aggregate reads, by canonical path. */
    private Map<String, BoardQueryService.ResolvedField> readFields = new Map<String, BoardQueryService.ResolvedField>();

    /** True when the request turns Detail rows off (`detailRows: false`). */
    public static Boolean isRequested(Map<String, Object> request) {
        Object detailRows = request.get('detailRows');
        return detailRows instanceof Boolean && !((Boolean) detailRows);
    }

    /** Ordering groups by a summary needs Detail rows off (summaries are only per group there). */
    public static void rejectSummaryOrder(Map<String, Object> request) {
        if (groupEntry(request).get('orderBySummary') != null) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Ordering groups by a summary needs Detail rows off.',
                null,
                'groupBy'
            );
        }
    }

    /**
     * Fills `result` (columns, Row actions and Data bar scales already resolved) with every Group row, the record
     * count and, when `totalSpecs` is set, the grand-total Total row.
     */
    public static BoardQueryService.TableResult run(
        BoardQueryService.QueryScope scope,
        Map<String, Object> request,
        BoardQueryService.TableResult result,
        BoardTableGrouping grouping,
        List<BoardTableEngine.SummarySpec> totalSpecs
    ) {
        BoardTableAggregate aggregate = new BoardTableAggregate(scope, grouping);
        aggregate.addColumns(result.columns, BoardTableQuery.columnSummarySpecs(request, result.columns));
        String orderClause = aggregate.orderClause(groupEntry(request), result);
        result.groupField = grouping.resolvedField;
        aggregate.groupLimit = BoardTableRowLimit.resolveGroupLimit(request.get('rowLimit'), false);
        result.rows = new List<BoardQueryService.TableRow>();
        result.start = 0;
        result.hasMore = false;
        result.deletedRows = 0;
        if (BoardTableAggregateCursor.isContinuation(request)) {
            return aggregate.runCursorTier(request, result, totalSpecs);
        }
        Integer scopeRows = BoardTableAggregateCursor.countWithinCap(scope);
        result.aggregateGroups = BoardTableAggregateCursor.exceedsSingleAggregate(scopeRows)
            ? null
            : aggregate.queryGroups(orderClause);
        if (result.aggregateGroups == null) {
            return aggregate.runCursorTier(request, result, totalSpecs);
        }
        result.totalCount = 0;
        for (GroupRow groupRow : result.aggregateGroups) {
            result.totalCount += groupRow.count;
        }
        result.nextIndex = result.totalCount;
        if (aggregate.cutByGroupLimit) {
            result.groupLimit = aggregate.groupLimit;
            BoardTableRowLimit.restrictToGroupRows(
                scope,
                aggregate.groupField.fieldPath,
                aggregate.isLookup,
                result.aggregateGroups
            );
        }
        if (totalSpecs != null) {
            // Merged from the Group rows shown (corporate), like the cursor tier: no second read of the scope.
            result.totals = BoardCurrencyConverter.forRequest()
                .totalsToDisplay(
                    BoardTableAggregateEngine.grandTotals(aggregate.groupPartials, aggregate.specs),
                    result.columns
                );
        }
        return result;
    }

    private static Map<String, Object> groupEntry(Map<String, Object> request) {
        List<Object> groupBy = BoardQueryService.getList(request, 'groupBy');
        return groupBy.isEmpty() ? new Map<String, Object>() : BoardQueryService.asMap(groupBy[0]);
    }

    private BoardTableAggregate(BoardQueryService.QueryScope scope, BoardTableGrouping grouping) {
        this.scope = scope;
        groupField = grouping.resolvedField;
        if (groupField.secondLevel != null || groupField.dateGranularity != null) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'With Detail rows off a Table groups by one lookup, picklist or text field.',
                null,
                'groupBy'
            );
        }
        BoardQueryService.ResolvedField resolved = BoardTableQuery.resolveTablePath(
            scope.objectDescribe,
            groupField.fieldPath
        );
        isLookup = resolved.type == Schema.DisplayType.REFERENCE;
        String relationshipName = resolved.describe.getRelationshipName();
        if (isLookup && relationshipName != null) {
            List<String> segments = resolved.path.split('\\.');
            segments[segments.size() - 1] = relationshipName;
            relationshipPrefix = String.join(segments, '.').toLowerCase() + '.';
        }
        if (resolved.type == Schema.DisplayType.PICKLIST || resolved.type == Schema.DisplayType.COMBOBOX) {
            for (Schema.PicklistEntry picklistEntry : resolved.describe.getPicklistValues()) {
                picklistLabels.put(picklistEntry.getValue(), picklistEntry.getLabel());
            }
        }
        groupByPaths.add(groupField.fieldPath);
        expressionByPath.put(groupField.fieldPath.toLowerCase(), groupField.fieldPath);
        plan.keyPath = groupField.fieldPath;
        plan.specs = specs;
        plan.direction = groupField.sortDirection;
        trackReadField(resolved);
        selectParts.add(groupField.fieldPath + ' ' + KEY_ALIAS);
        selectParts.add('COUNT(Id) ' + COUNT_ALIAS);
        if (groupField.labelPath != null) {
            addConstantField(BoardTableQuery.resolveTablePath(scope.objectDescribe, groupField.labelPath));
        }
    }

    /** True for the group field itself and for fields reached through the lookup group field. */
    private Boolean isConstantPerGroup(String path) {
        String lowerPath = path.toLowerCase();
        return lowerPath == groupField.fieldPath.toLowerCase() ||
            (relationshipPrefix != null && lowerPath.startsWith(relationshipPrefix));
    }

    /**
     * Selects a field constant per group: grouped when groupable (adding it to `GROUP BY` never splits a group),
     * else as `MAX(path)` (every record of the group has the same value).
     */
    private void addConstantField(BoardQueryService.ResolvedField field) {
        String lowerPath = field.path.toLowerCase();
        if (expressionByPath.containsKey(lowerPath)) {
            return;
        }
        String alias = 'f' + aliasByPath.size();
        String expression;
        if (field.describe.isGroupable()) {
            groupByPaths.add(field.path);
            expression = field.path;
        } else if (field.describe.isAggregatable()) {
            expression = 'MAX(' + field.path + ')';
        } else {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'This field cannot be shown on Group rows with Detail rows off: ' + field.path,
                null,
                'columns'
            );
        }
        selectParts.add(expression + ' ' + alias);
        expressionByPath.put(lowerPath, expression);
        aliasByPath.put(field.path, alias);
        plan.valuePaths.add(field.path);
        trackReadField(field);
    }

    /** Cursor tier: reads `field` from each record; picklists order by their definition order, as in SOQL. */
    private void trackReadField(BoardQueryService.ResolvedField field) {
        readFields.put(field.path, field);
        if (field.type == Schema.DisplayType.PICKLIST || field.type == Schema.DisplayType.COMBOBOX) {
            List<String> ranked = new List<String>();
            for (Schema.PicklistEntry picklistEntry : field.describe.getPicklistValues()) {
                ranked.add(picklistEntry.getValue());
            }
            plan.rankedValues.put(field.path.toLowerCase(), ranked);
        }
    }

    /**
     * Each column is the group field, a field through the lookup group field, or a numeric column with summaries;
     * anything else has no single value per group and is a config error.
     */
    private void addColumns(
        List<BoardQueryService.TableColumn> columns,
        List<BoardTableEngine.SummarySpec> summarySpecs
    ) {
        Set<String> summarized = new Set<String>();
        for (BoardTableEngine.SummarySpec spec : summarySpecs) {
            for (Integer f = 0; f < spec.functions.size(); f++) {
                selectParts.add(spec.functions[f] + '(' + spec.fieldPath + ') ' + summaryAlias(specs.size(), f));
            }
            // Mergeable partials of the column (Total row from the Group rows).
            String partialAlias = 'p' + specs.size();
            selectParts.add('SUM(' + spec.fieldPath + ') ' + partialAlias + 's');
            selectParts.add('COUNT(' + spec.fieldPath + ') ' + partialAlias + 'c');
            selectParts.add('MIN(' + spec.fieldPath + ') ' + partialAlias + 'n');
            selectParts.add('MAX(' + spec.fieldPath + ') ' + partialAlias + 'x');
            specs.add(spec);
            summarized.add(spec.columnId);
            trackReadField(BoardTableQuery.resolveTablePath(scope.objectDescribe, spec.fieldPath));
        }
        for (BoardQueryService.TableColumn column : columns) {
            if (summarized.contains(column.id)) {
                continue;
            }
            if (!isConstantPerGroup(column.fieldPath)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'With Detail rows off a column shows the group field, a field through the group lookup, ' +
                        'or summaries: ' +
                        column.fieldPath,
                    null,
                    'columns'
                );
            }
            addConstantField(BoardTableQuery.resolveTablePath(scope.objectDescribe, column.fieldPath));
            if (column.linkPath != null && isConstantPerGroup(column.linkPath)) {
                addConstantField(BoardTableQuery.resolveTablePath(scope.objectDescribe, column.linkPath));
            }
        }
    }

    /**
     * `ORDER BY` body: by a summary, by a field constant per group, or by value (a lookup by its record name), then
     * the group key so ties keep a stable order. Sets the result's sort to the ordering column, if any.
     */
    private String orderClause(Map<String, Object> entry, BoardQueryService.TableResult result) {
        String direction = groupField.sortDirection;
        List<String> parts = new List<String>();
        result.sortBy = null;
        Object rawSummaryOrder = entry.get('orderBySummary');
        String orderByPath = BoardQueryService.getString(entry, 'orderBy');
        if (rawSummaryOrder != null) {
            BoardTableEngine.SummarySpec spec = plan.orderBySummary(rawSummaryOrder);
            parts.add(plan.orderFunction + '(' + spec.fieldPath + ') ' + direction + ' NULLS LAST');
            result.sortBy = spec.fieldPath;
        } else if (String.isNotBlank(orderByPath)) {
            BoardQueryService.ResolvedField field = BoardTableQuery.resolveTablePath(scope.objectDescribe, orderByPath);
            if (!isConstantPerGroup(field.path)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Groups can be ordered by a field through the group lookup only: ' + orderByPath,
                    null,
                    'groupBy'
                );
            }
            if (!field.path.equalsIgnoreCase(groupField.fieldPath)) {
                addConstantField(field);
                parts.add(expressionByPath.get(field.path.toLowerCase()) + ' ' + direction + ' NULLS LAST');
                result.sortBy = field.path;
                plan.orderPath = field.path;
            }
        }
        if (parts.isEmpty() && groupField.labelPath != null) {
            parts.add(expressionByPath.get(groupField.labelPath.toLowerCase()) + ' ' + direction + ' NULLS LAST');
            plan.orderPath = groupField.labelPath;
        }
        parts.add(groupField.fieldPath + ' ' + direction + ' NULLS LAST');
        result.sortDirection = result.sortBy == null ? null : direction;
        return String.join(parts, ', ');
    }

    /** Every Group row in order, "(Blank)" moved last; null when there are more than `MAX_GROUPS` groups. */
    private List<GroupRow> queryGroups(String orderClause) {
        String soql = scope.buildSoql(
            String.join(selectParts, ', '),
            null,
            'GROUP BY ' +
                String.join(groupByPaths, ', ') +
                ' ORDER BY ' +
                orderClause +
                ' LIMIT ' +
                ((groupLimit == null ? MAX_GROUPS : groupLimit) + 1)
        );
        List<SObject> results = Database.queryWithBinds(soql, scope.binds, AccessLevel.USER_MODE);
        if (groupLimit != null && results.size() > groupLimit) {
            cutByGroupLimit = true;
            results.remove(results.size() - 1);
        }
        if (results.size() > MAX_GROUPS) {
            return null;
        }
        List<GroupRow> groupRows = new List<GroupRow>();
        GroupRow blank;
        for (SObject result : results) {
            GroupRow groupRow = toGroupRow((AggregateResult) result);
            if (groupRow.key == null) {
                blank = groupRow;
            } else {
                groupRows.add(groupRow);
            }
        }
        if (blank != null) {
            groupRows.add(blank);
        }
        return groupRows;
    }

    private GroupRow toGroupRow(AggregateResult aggregate) {
        GroupRow groupRow = new GroupRow();
        Object rawKey = aggregate.get(KEY_ALIAS);
        groupRow.key = rawKey == null || String.isBlank(String.valueOf(rawKey)) ? null : String.valueOf(rawKey);
        groupRow.count = (Integer) aggregate.get(COUNT_ALIAS);
        groupRow.values.put(groupField.fieldPath, rawKey);
        for (String path : aliasByPath.keySet()) {
            groupRow.values.put(path, aggregate.get(aliasByPath.get(path)));
        }
        labelGroupRow(groupRow);
        BoardTableAggregateEngine.AggregatedGroup partials = new BoardTableAggregateEngine.AggregatedGroup();
        for (Integer c = 0; c < specs.size(); c++) {
            BoardTableEngine.ColumnTotal summaries = new BoardTableEngine.ColumnTotal(specs[c].columnId);
            for (Integer f = 0; f < specs[c].functions.size(); f++) {
                summaries.add(specs[c].functions[f], aggregate.get(summaryAlias(c, f)));
            }
            groupRow.summaries.add(summaries);
            BoardTableEngine.Summary partial = new BoardTableEngine.Summary();
            partial.addAggregate(
                aggregate.get('p' + c + 's'),
                aggregate.get('p' + c + 'c'),
                aggregate.get('p' + c + 'n'),
                aggregate.get('p' + c + 'x')
            );
            partials.summaries.add(partial);
        }
        groupPartials.add(partials);
        return groupRow;
    }

    /** Label, picklist label and lookup link of a Group row from its key and values. */
    private void labelGroupRow(GroupRow groupRow) {
        if (groupRow.key != null) {
            Object rawLabel = groupField.labelPath == null ? null : groupRow.values.get(groupField.labelPath);
            groupRow.label = rawLabel == null ? groupRow.key : String.valueOf(rawLabel);
            if (picklistLabels.containsKey(groupRow.key)) {
                groupRow.label = picklistLabels.get(groupRow.key);
            }
            if (isLookup) {
                groupRow.recordId = groupRow.key;
            }
        }
    }

    // ---- Cursor tier ---------------------------------------------------------------------------------------

    /**
     * Reads the next cursor chunk into the running groups (restored from the request's `partialState`). An incomplete
     * load returns only its progress and running state; the final chunk returns every Group row in order (the top N
     * under a Row limit) and, when `totalSpecs` is set, the Total row merged from the Group rows shown.
     */
    private BoardQueryService.TableResult runCursorTier(
        Map<String, Object> request,
        BoardQueryService.TableResult result,
        List<BoardTableEngine.SummarySpec> totalSpecs
    ) {
        Map<String, String> isoPathByPath = new Map<String, String>();
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        for (BoardQueryService.ResolvedField field : readFields.values()) {
            isoPathByPath.put(field.path, converter.isoCodePath(field.path, field.type));
        }
        BoardTableAggregateCursor.Chunk chunk = BoardTableAggregateCursor.read(scope, request, isoPathByPath);
        BoardTableAggregateEngine.Accumulator accumulator = new BoardTableAggregateEngine.Accumulator(plan)
            .restore(BoardQueryService.getString(request, 'partialState'));
        for (Map<String, Object> row : chunk.rows) {
            accumulator.add(row);
        }
        result.aggregateCursor = chunk.progress;
        result.totalCount = chunk.progress.totalRows;
        result.nextIndex = result.totalCount;
        result.aggregateGroups = new List<GroupRow>();
        if (!chunk.progress.isComplete) {
            chunk.progress.partialState = accumulator.state();
            return result;
        }
        List<BoardTableAggregateEngine.AggregatedGroup> ordered = BoardTableAggregateEngine.orderGroups(
            accumulator.groups(),
            plan
        );
        if (groupLimit != null && ordered.size() > groupLimit) {
            ordered = BoardTableAggregateEngine.topGroups(ordered, groupLimit);
            result.groupLimit = groupLimit;
            result.totalCount = 0;
            for (BoardTableAggregateEngine.AggregatedGroup aggregatedGroup : ordered) {
                result.totalCount += aggregatedGroup.count;
            }
            result.nextIndex = result.totalCount;
        }
        for (BoardTableAggregateEngine.AggregatedGroup aggregatedGroup : ordered) {
            result.aggregateGroups.add(toGroupRow(aggregatedGroup));
        }
        if (totalSpecs != null) {
            // Cursor-tier totals are corporate; currency columns' summaries are returned in the Display currency.
            result.totals = BoardCurrencyConverter.forRequest()
                .totalsToDisplay(BoardTableAggregateEngine.grandTotals(ordered, specs), result.columns);
        }
        return result;
    }

    private GroupRow toGroupRow(BoardTableAggregateEngine.AggregatedGroup aggregatedGroup) {
        GroupRow groupRow = new GroupRow();
        groupRow.key = aggregatedGroup.key;
        groupRow.count = aggregatedGroup.count;
        groupRow.values = aggregatedGroup.values;
        labelGroupRow(groupRow);
        groupRow.summaries = BoardTableAggregateEngine.summaries(aggregatedGroup, specs);
        return groupRow;
    }

    private static String summaryAlias(Integer specIndex, Integer functionIndex) {
        return 's' + specIndex + '_' + functionIndex;
    }

    /** One Group row of an aggregated table (Detail rows off). */
    public class GroupRow {
        /** Group value (record Id for lookups, API value for picklists); null for the "(Blank)" group. */
        @AuraEnabled
        public String key;
        /** Display value (lookup record name, picklist label); null for the "(Blank)" group. */
        @AuraEnabled
        public String label;
        /** Record the Group row links to (lookup groups only). */
        @AuraEnabled
        public String recordId;
        /** Records in the group. */
        @AuraEnabled
        public Integer count;
        /** Group field and fields reached through the lookup group field, by canonical path. */
        @AuraEnabled
        public Map<String, Object> values = new Map<String, Object>();
        /** Stacked summaries of each column with summaries, in column order. */
        @AuraEnabled
        public List<BoardTableEngine.ColumnTotal> summaries = new List<BoardTableEngine.ColumnTotal>();
    }
}