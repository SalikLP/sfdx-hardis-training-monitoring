/**
 * Row grouping with Detail rows off: the Table as an aggregated table.
 *
 * Every Group row comes at once (no cursor paging, no infinite scroll), each with its record count, the Stacked
 * summaries of the columns that have summaries, and the values of fields constant per group (e.g. `Account.Industry`
 * when grouped by `AccountId`). Group fields are the ones Detail rows on takes (`BoardTableGroupLevel`): up to two
 * levels, lookups, picklists, text and dates bucketed by any granularity, direct or through a parent path. With two
 * levels each first-level Group row is followed by its second-level Group rows. Every column must have one meaning per
 * group: a non-date group field, a field through a lookup group field, or a numeric column with summaries.
 *
 * SOQL tier: one `GROUP BY` over every level returns the second-level groups (with mergeable `SUM`/`COUNT`/`MIN`/`MAX`
 * partials); a parent-path level is read in two slices (its "(Blank)" records, a missing parent included, told apart on
 * the relationship Id: a missing parent's fields are placeholder values in `WHERE` and `GROUP BY`). Above `MAX_GROUPS`
 * groups, or above the single-aggregate row threshold, the cursor tier (`BoardTableAggregateCursor`) reads the records
 * up to the cursor cap; above the cap the Table is blocked. Both tiers fold into `BoardTableAggregateEngine`, which rolls
 * second-level groups up into first-level groups and orders both levels: by value, by a field constant per group
 * (`orderBy`) or by a summary (`orderBySummary`), "(Blank)" last. A Row limit keeps the top N first-level groups.
 */
public with sharing class BoardTableAggregate {
    /** Most groups the SOQL tier returns (an aggregate query cannot page past 2,000 rows). */
    @TestVisible
    private static Integer MAX_GROUPS = 2000;
    private static final String COUNT_ALIAS = 'recordCount';

    private BoardQueryService.QueryScope scope;
    private List<BoardTableGroupLevel> levels;
    /** Per level: fields constant per group of that level (canonical path -> resolved field). */
    private List<Map<String, BoardQueryService.ResolvedField>> constantsByLevel = new List<Map<String, BoardQueryService.ResolvedField>>();
    /** Canonical path -> alias of a field constant per group in the aggregate result. */
    private Map<String, String> aliasByPath = new Map<String, String>();
    /** Lower-cased path -> SOQL expression of a field constant per group (the grouped path, or `MAX(path)`). */
    private Map<String, String> expressionByPath = new Map<String, String>();
    private List<BoardTableEngine.SummarySpec> specs = new List<BoardTableEngine.SummarySpec>();
    /** Row limit: the top N first-level groups to keep (see `BoardTableRowLimit`); null when unlimited. */
    private Integer groupLimit;
    /** Grouping, values, summaries and order of both tiers; `plan.secondLevel` with two group fields. */
    private BoardTableAggregateEngine.Plan plan = new BoardTableAggregateEngine.Plan();
    private List<BoardTableAggregateEngine.Plan> levelPlans = new List<BoardTableAggregateEngine.Plan>();
    /** Cursor tier: every field the aggregate reads, by canonical path. */
    private Map<String, BoardQueryService.ResolvedField> readFields = new Map<String, BoardQueryService.ResolvedField>();

    /** True when the request turns Detail rows off (`detailRows: false`). */
    public static Boolean isRequested(Map<String, Object> request) {
        Object detailRows = request.get('detailRows');
        return detailRows instanceof Boolean && !((Boolean) detailRows);
    }

    /** Ordering groups by a summary needs Detail rows off (summaries are only per group there). */
    public static void rejectSummaryOrder(Map<String, Object> request) {
        for (Object entry : BoardQueryService.getList(request, 'groupBy')) {
            if (BoardQueryService.asMap(entry).get('orderBySummary') != null) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Ordering groups by a summary needs Detail rows off.',
                    null,
                    'groupBy'
                );
            }
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
        aggregate.resolveOrder(BoardQueryService.getList(request, 'groupBy'), result);
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
        List<BoardTableAggregateEngine.AggregatedGroup> leaves = BoardTableAggregateCursor.exceedsSingleAggregate(
                scopeRows
            )
            ? null
            : aggregate.queryGroups();
        if (leaves == null) {
            return aggregate.runCursorTier(request, result, totalSpecs);
        }
        BoardTableAggregateEngine.Accumulator accumulator = new BoardTableAggregateEngine.Accumulator(aggregate.plan);
        for (BoardTableAggregateEngine.AggregatedGroup leaf : leaves) {
            accumulator.addGroup(leaf);
        }
        return aggregate.finish(result, accumulator.groups(), totalSpecs);
    }

    private BoardTableAggregate(BoardQueryService.QueryScope scope, BoardTableGrouping grouping) {
        this.scope = scope;
        levels = grouping.groupLevels();
        levelPlans.add(plan);
        if (levels.size() > 1) {
            plan.secondLevel = new BoardTableAggregateEngine.Plan();
            plan.secondLevel.rankedValues = plan.rankedValues;
            levelPlans.add(plan.secondLevel);
        }
        for (Integer i = 0; i < levels.size(); i++) {
            BoardTableGroupLevel level = levels[i];
            BoardTableAggregateEngine.Plan levelPlan = levelPlans[i];
            levelPlan.keyPath = level.field.keyPath;
            levelPlan.specs = specs;
            levelPlan.direction = level.field.sortDirection;
            constantsByLevel.add(new Map<String, BoardQueryService.ResolvedField>());
            trackReadField(resolve(level.field.fieldPath));
        }
        for (BoardTableGroupLevel level : levels) {
            for (String path : new List<String>{ level.field.labelPath, level.field.orderBy }) {
                if (path != null) {
                    addConstantField(resolve(path));
                }
            }
        }
    }

    private BoardQueryService.ResolvedField resolve(String path) {
        return BoardTableQuery.resolveTablePath(scope.objectDescribe, path);
    }

    /** Index of the first level with one value of `path` per group, or -1 when none has. */
    private Integer ownerLevel(String path) {
        for (Integer i = 0; i < levels.size(); i++) {
            if (levels[i].isConstantPerGroup(path)) {
                return i;
            }
        }
        return -1;
    }

    /** True for a (non-date) group field itself: its value is the group key, carried already. */
    private Boolean isGroupKey(String path) {
        for (BoardTableGroupLevel level : levels) {
            if (level.granularity == null && level.field.fieldPath.equalsIgnoreCase(path)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Carries a field constant per group of its level: in SOQL grouped when groupable (adding it to `GROUP BY` never
     * splits a group), else as `MAX(path)` (every record of the group has the same value).
     */
    private void addConstantField(BoardQueryService.ResolvedField field) {
        String lowerPath = field.path.toLowerCase();
        if (expressionByPath.containsKey(lowerPath) || isGroupKey(field.path)) {
            return;
        }
        Integer owner = ownerLevel(field.path);
        String expression;
        if (field.describe.isGroupable()) {
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
        expressionByPath.put(lowerPath, expression);
        aliasByPath.put(field.path, 'f' + aliasByPath.size());
        constantsByLevel[owner].put(field.path, field);
        levelPlans[owner].valuePaths.add(field.path);
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
     * Each column is a group field, a field through a lookup group field, or a numeric column with summaries;
     * anything else has no single value per group and is a config error.
     */
    private void addColumns(
        List<BoardQueryService.TableColumn> columns,
        List<BoardTableEngine.SummarySpec> summarySpecs
    ) {
        Set<String> summarized = new Set<String>();
        for (BoardTableEngine.SummarySpec spec : summarySpecs) {
            specs.add(spec);
            summarized.add(spec.columnId);
            trackReadField(resolve(spec.fieldPath));
        }
        for (BoardQueryService.TableColumn column : columns) {
            if (summarized.contains(column.id)) {
                continue;
            }
            if (!isGroupKey(column.fieldPath) && ownerLevel(column.fieldPath) < 0) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'With Detail rows off a column shows the group field, a field through the group lookup, ' +
                        'or summaries: ' +
                        column.fieldPath,
                    null,
                    'columns'
                );
            }
            addConstantField(resolve(column.fieldPath));
            if (column.linkPath != null && (isGroupKey(column.linkPath) || ownerLevel(column.linkPath) >= 0)) {
                addConstantField(resolve(column.linkPath));
            }
        }
    }

    /**
     * Group order of each level: by a summary (`orderBySummary`), by its order field, by a lookup's record name, else
     * by value. The first level's ordering column, if any, shows as the result's sort.
     */
    private void resolveOrder(List<Object> groupBy, BoardQueryService.TableResult result) {
        result.sortBy = null;
        result.sortDirection = null;
        for (Integer i = 0; i < levels.size(); i++) {
            BoardTableGroupLevel level = levels[i];
            BoardTableAggregateEngine.Plan levelPlan = levelPlans[i];
            Object rawSummaryOrder = i < groupBy.size()
                ? BoardQueryService.asMap(groupBy[i]).get('orderBySummary')
                : null;
            String sortBy = null;
            if (rawSummaryOrder != null) {
                sortBy = levelPlan.orderBySummary(rawSummaryOrder).fieldPath;
            } else if (level.field.orderBy != null) {
                levelPlan.orderPath = level.field.orderBy;
                sortBy = level.field.orderBy;
            } else if (level.field.labelPath != null) {
                levelPlan.orderPath = level.field.labelPath;
            }
            if (i == 0 && sortBy != null) {
                result.sortBy = sortBy;
                result.sortDirection = level.field.sortDirection;
            }
        }
    }

    // ---- SOQL tier -----------------------------------------------------------------------------------------------

    /**
     * Every second-level group (first-level with one group field) with its partials, unordered; null when there are
     * more than `MAX_GROUPS`. A parent-path level is read as two slices: records with a parent and a value, grouped,
     * and its "(Blank)" records, not grouped.
     */
    private List<BoardTableAggregateEngine.AggregatedGroup> queryGroups() {
        List<List<Boolean>> slices = new List<List<Boolean>>{ new List<Boolean>() };
        for (BoardTableGroupLevel level : levels) {
            List<List<Boolean>> extended = new List<List<Boolean>>();
            for (List<Boolean> slice : slices) {
                extended.add(withBlank(slice, false));
                if (level.isParentPath()) {
                    extended.add(withBlank(slice, true));
                }
            }
            slices = extended;
        }
        // One group field read in one slice: the top N groups come straight from `ORDER BY ... LIMIT N + 1`.
        Boolean limitedInSoql = groupLimit != null && slices.size() == 1 && levels.size() == 1;
        List<BoardTableAggregateEngine.AggregatedGroup> leaves = new List<BoardTableAggregateEngine.AggregatedGroup>();
        for (List<Boolean> blanks : slices) {
            for (SObject row : querySlice(blanks, limitedInSoql)) {
                AggregateResult aggregate = (AggregateResult) row;
                Integer recordCount = (Integer) aggregate.get(COUNT_ALIAS);
                if (recordCount != null && recordCount > 0) {
                    leaves.add(toLeaf(aggregate, blanks, recordCount));
                }
            }
            if (!limitedInSoql && leaves.size() > MAX_GROUPS) {
                return null;
            }
        }
        return leaves;
    }

    private static List<Boolean> withBlank(List<Boolean> slice, Boolean blank) {
        List<Boolean> extended = new List<Boolean>(slice);
        extended.add(blank);
        return extended;
    }

    /** One slice's `GROUP BY`: a level flagged in `blanks` is restricted to its "(Blank)" records and not grouped. */
    private List<SObject> querySlice(List<Boolean> blanks, Boolean limitedInSoql) {
        List<String> selectParts = new List<String>();
        List<String> groupByParts = new List<String>();
        List<String> predicates = new List<String>();
        for (Integer i = 0; i < levels.size(); i++) {
            BoardTableGroupLevel level = levels[i];
            if (blanks[i]) {
                predicates.add(level.blankPredicate());
                continue;
            }
            if (level.isParentPath()) {
                predicates.add(level.valuePredicate());
            }
            selectParts.addAll(level.selectColumns());
            groupByParts.addAll(level.expressions);
            for (String path : constantsByLevel[i].keySet()) {
                String expression = expressionByPath.get(path.toLowerCase());
                if (expression == path) {
                    groupByParts.add(path);
                }
                selectParts.add(expression + ' ' + aliasByPath.get(path));
            }
        }
        selectParts.add('COUNT(Id) ' + COUNT_ALIAS);
        for (Integer c = 0; c < specs.size(); c++) {
            String fieldPath = specs[c].fieldPath;
            selectParts.add('SUM(' + fieldPath + ') p' + c + 's');
            selectParts.add('COUNT(' + fieldPath + ') p' + c + 'c');
            selectParts.add('MIN(' + fieldPath + ') p' + c + 'n');
            selectParts.add('MAX(' + fieldPath + ') p' + c + 'x');
        }
        String suffix = '';
        if (!groupByParts.isEmpty()) {
            suffix = 'GROUP BY ' + String.join(groupByParts, ', ');
            suffix += limitedInSoql
                ? ' ORDER BY ' + limitedOrderClause() + ' LIMIT ' + (groupLimit + 1)
                : ' LIMIT ' + (MAX_GROUPS + 1);
        }
        return Database.queryWithBinds(
            scope.buildSoql(String.join(selectParts, ', '), predicates, suffix),
            scope.binds,
            AccessLevel.USER_MODE
        );
    }

    /**
     * `ORDER BY` body of one group field's top N: its summary, order field or record name, then its value (dates by
     * the earliest date of each bucket: buckets never overlap), blanks last. The engine re-applies the same order.
     */
    private String limitedOrderClause() {
        BoardTableGroupLevel level = levels[0];
        String direction = ' ' + level.field.sortDirection + ' NULLS LAST';
        List<String> parts = new List<String>();
        if (plan.orderSpecIndex != null) {
            parts.add(plan.orderFunction + '(' + specs[plan.orderSpecIndex].fieldPath + ')' + direction);
        } else if (plan.orderPath != null) {
            parts.add(expressionByPath.get(plan.orderPath.toLowerCase()) + direction);
        }
        parts.add(
            (level.granularity == null ? level.field.fieldPath : 'MIN(' + level.field.fieldPath + ')') + direction
        );
        return String.join(parts, ', ');
    }

    /** One `GROUP BY` row as a group: keys per level (null in a "(Blank)" slice), values, count, partials. */
    private BoardTableAggregateEngine.AggregatedGroup toLeaf(
        AggregateResult aggregate,
        List<Boolean> blanks,
        Integer recordCount
    ) {
        BoardTableAggregateEngine.AggregatedGroup leaf = new BoardTableAggregateEngine.AggregatedGroup();
        leaf.count = recordCount;
        for (Integer i = 0; i < levels.size(); i++) {
            BoardTableGroupLevel level = levels[i];
            String key = blanks[i] ? null : level.keyOf(aggregate);
            leaf.values.put(level.field.keyPath, blanks[i] ? null : level.rawKeyOf(aggregate));
            for (String path : constantsByLevel[i].keySet()) {
                leaf.values.put(path, blanks[i] ? null : aggregate.get(aliasByPath.get(path)));
            }
            key = String.isBlank(key) ? null : key;
            if (i == levels.size() - 1) {
                leaf.key = key;
            } else {
                leaf.parentKey = key;
            }
        }
        for (Integer c = 0; c < specs.size(); c++) {
            BoardTableEngine.Summary partial = new BoardTableEngine.Summary();
            partial.addAggregate(
                aggregate.get('p' + c + 's'),
                aggregate.get('p' + c + 'c'),
                aggregate.get('p' + c + 'n'),
                aggregate.get('p' + c + 'x')
            );
            leaf.summaries.add(partial);
        }
        return leaf;
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
            for (BoardTableGroupLevel level : levels) {
                level.keyRow(row);
            }
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
        return finish(result, accumulator.groups(), totalSpecs);
    }

    // ---- Both tiers --------------------------------------------------------------------------------------------

    /**
     * Orders the groups (both levels), keeps the top N first-level groups under a Row limit, and fills the Group rows
     * (each first-level one followed by its second-level ones), the record count and the Total row merged from them.
     */
    private BoardQueryService.TableResult finish(
        BoardQueryService.TableResult result,
        List<BoardTableAggregateEngine.AggregatedGroup> groups,
        List<BoardTableEngine.SummarySpec> totalSpecs
    ) {
        List<BoardTableAggregateEngine.AggregatedGroup> ordered = BoardTableAggregateEngine.orderGroups(groups, plan);
        Boolean cut = groupLimit != null && ordered.size() > groupLimit;
        if (cut) {
            ordered = BoardTableAggregateEngine.topGroups(ordered, groupLimit);
            result.groupLimit = groupLimit;
        }
        result.aggregateGroups = new List<GroupRow>();
        result.totalCount = 0;
        for (BoardTableAggregateEngine.AggregatedGroup aggregatedGroup : ordered) {
            result.totalCount += aggregatedGroup.count;
            result.aggregateGroups.add(toGroupRow(aggregatedGroup, 0, null));
            for (BoardTableAggregateEngine.AggregatedGroup subgroup : aggregatedGroup.subgroups) {
                result.aggregateGroups.add(toGroupRow(subgroup, 1, aggregatedGroup.key));
            }
        }
        result.nextIndex = result.totalCount;
        if (cut && levels.size() == 1 && levels[0].granularity == null) {
            BoardTableRowLimit.restrictToGroupRows(
                scope,
                levels[0].field.fieldPath,
                levels[0].isLookup,
                result.aggregateGroups
            );
        }
        if (totalSpecs != null) {
            // Merged from the Group rows shown (corporate): no second read of the scope.
            result.totals = BoardCurrencyConverter.forRequest()
                .totalsToDisplay(BoardTableAggregateEngine.grandTotals(ordered, specs), result.columns);
        }
        return result;
    }

    /** Group row of a group at `levelIndex` (0 or 1): label, lookup link, values and Stacked summaries. */
    private GroupRow toGroupRow(
        BoardTableAggregateEngine.AggregatedGroup aggregatedGroup,
        Integer levelIndex,
        String parentKey
    ) {
        BoardTableGroupLevel level = levels[levelIndex];
        GroupRow groupRow = new GroupRow();
        groupRow.level = levelIndex + 1;
        groupRow.parentKey = parentKey;
        groupRow.key = aggregatedGroup.key;
        groupRow.count = aggregatedGroup.count;
        groupRow.values = aggregatedGroup.values;
        if (groupRow.key != null) {
            Object recordName = level.field.labelPath == null ? null : groupRow.values.get(level.field.labelPath);
            groupRow.label = level.labelOf(groupRow.key, recordName);
            if (level.isLookup) {
                groupRow.recordId = groupRow.key;
            }
        }
        groupRow.summaries = BoardTableAggregateEngine.summaries(aggregatedGroup, specs);
        return groupRow;
    }

    /** One Group row of an aggregated table (Detail rows off). */
    public class GroupRow {
        /** Row grouping level: 1 for the first group field, 2 for groups nested under a first-level Group row. */
        @AuraEnabled
        public Integer level = 1;
        /** Second-level Group rows: the `key` of the first-level Group row they are nested under. */
        @AuraEnabled
        public String parentKey;
        /** Group value (record Id for lookups, API value for picklists, bucket key for dates); null for "(Blank)". */
        @AuraEnabled
        public String key;
        /** Display value (lookup record name, picklist label, date bucket label); null for the "(Blank)" group. */
        @AuraEnabled
        public String label;
        /** Record the Group row links to (lookup groups only). */
        @AuraEnabled
        public String recordId;
        /** Records in the group. */
        @AuraEnabled
        public Integer count;
        /** Group key (under the level's `keyPath`) and fields constant per group, by canonical path. */
        @AuraEnabled
        public Map<String, Object> values = new Map<String, Object>();
        /** Stacked summaries of each column with summaries, in column order. */
        @AuraEnabled
        public List<BoardTableEngine.ColumnTotal> summaries = new List<BoardTableEngine.ColumnTotal>();
    }
}