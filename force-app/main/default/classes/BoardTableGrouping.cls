/**
 * Row grouping of a Table with Detail rows on: up to two group fields (`BoardTableGroupLevel`: lookup, picklist, text
 * or date; direct or a 1-5 hop parent path).
 *
 * Records stream through the Table's pagination cursor ordered by the group fields (blanks last) and then the
 * within-group sort, so each group's records are contiguous. Every page also runs one `GROUP BY` over both group
 * fields, restricted to that page's first-level groups, so each Group row (first and second level) carries its
 * full-group record count even when the group spans pages. Lookups group by record Id (same-named records stay
 * separate) and are labelled by the record name. Dates are bucketed by the Chart widget's granularities
 * (`CALENDAR_MONTH` etc.); each row carries its bucket key under the level's `keyPath`. Groups are ordered by their
 * value, or by a field constant per group reached through a lookup group field (`orderBy`, e.g. `Opportunity.Amount`).
 */
public with sharing class BoardTableGrouping {
    private static final Integer MAX_LEVELS = 2;
    /** Prefix of the bind names of a Row limit's top-group restriction (kept apart from the page-scoped binds). */
    private static final String TOP_BIND_PREFIX = 'top_';

    /** Resolved first group field returned to the Widget (the second, if any, as its `secondLevel`). */
    public GroupField resolvedField;
    private List<BoardTableGroupLevel> levels = new List<BoardTableGroupLevel>();
    /** Summarized columns whose Stacked summaries each Group row carries (see `BoardTableGroupSummaries`). */
    public List<BoardTableEngine.SummarySpec> summarySpecs = new List<BoardTableEngine.SummarySpec>();

    /** The request's Row grouping, or null for an ungrouped Table. */
    public static BoardTableGrouping fromRequest(
        Schema.DescribeSObjectResult objectDescribe,
        Map<String, Object> request
    ) {
        List<Object> groupBy = BoardQueryService.getList(request, 'groupBy');
        if (groupBy.isEmpty()) {
            return null;
        }
        if (groupBy.size() > MAX_LEVELS) {
            throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'A Table groups by up to two fields.', null, 'groupBy');
        }
        return new BoardTableGrouping(objectDescribe, groupBy);
    }

    private BoardTableGrouping(Schema.DescribeSObjectResult objectDescribe, List<Object> groupBy) {
        for (Integer index = 0; index < groupBy.size(); index++) {
            levels.add(new BoardTableGroupLevel(objectDescribe, BoardQueryService.asMap(groupBy[index]), index + 1));
        }
        resolvedField = levels[0].field;
        if (levels.size() > 1) {
            if (levels[1].field.fieldPath.equalsIgnoreCase(levels[0].field.fieldPath)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Group by two different fields.',
                    null,
                    levels[1].field.fieldPath
                );
            }
            resolvedField.secondLevel = levels[1].field;
        }
    }

    /** The group fields, first level first (one or two). */
    public List<BoardTableGroupLevel> groupLevels() {
        return levels;
    }

    /** `selectList` plus each group field and its label path, case-insensitively deduped. */
    public String extendSelect(String selectList) {
        Set<String> selected = new Set<String>();
        for (String path : selectList.split(',')) {
            selected.add(path.trim().toLowerCase());
        }
        List<String> extra = new List<String>();
        for (BoardTableGroupLevel level : levels) {
            for (String path : new List<String>{ level.field.fieldPath, level.field.labelPath }) {
                if (path != null && selected.add(path.toLowerCase())) {
                    extra.add(path);
                }
            }
        }
        return extra.isEmpty() ? selectList : selectList + ', ' + String.join(extra, ', ');
    }

    /**
     * `ORDER BY` body: each group level in turn (its order field if any, a lookup's record name, then the group
     * field, so same-named records stay apart), blanks last, then the within-group sort (`withinGroupClause`, which
     * already ends with an `Id` tie-breaker). Exception: with a parent-path group field, records whose parent is
     * missing sort where the platform's placeholder value for that field falls (SOQL can't order by the relationship
     * being null), so their "(Blank)" group is not reliably last; the server and the Widget still show one "(Blank)"
     * group per level, gathering its records under its first Group row.
     */
    public String orderClause(String withinSortBy, String withinGroupClause) {
        List<String> parts = new List<String>();
        Set<String> orderedPaths = new Set<String>();
        for (BoardTableGroupLevel level : levels) {
            for (String path : level.orderPaths()) {
                if (orderedPaths.add(path.toLowerCase())) {
                    parts.add(path + ' ' + level.field.sortDirection + ' NULLS LAST');
                }
            }
        }
        // Sorting within groups by a group path itself adds nothing: keep only the Id tie-breaker.
        Boolean sortsByGroupPath = withinSortBy != null && orderedPaths.contains(withinSortBy.toLowerCase());
        parts.add(sortsByGroupPath ? 'Id ASC' : withinGroupClause);
        return String.join(parts, ', ');
    }

    /**
     * The groups of one page's rows in row order (each first-level group followed by its second-level groups), each
     * with its full-group record count (one `GROUP BY`). Date levels also write each row's bucket key under `keyPath`.
     */
    public List<BoardTableEngine.TableGroup> pageGroups(
        BoardQueryService.QueryScope scope,
        List<BoardQueryService.TableRow> rows
    ) {
        List<Map<String, Object>> values = new List<Map<String, Object>>();
        for (BoardQueryService.TableRow row : rows) {
            values.add(row.values);
            for (BoardTableGroupLevel level : levels) {
                level.keyRow(row.values);
            }
        }
        BoardTableGroupLevel first = levels[0];
        List<BoardTableEngine.TableGroup> firstGroups = BoardTableEngine.groupsInRowOrder(
            values,
            first.field.keyPath,
            first.field.labelPath
        );
        if (firstGroups.isEmpty()) {
            return firstGroups;
        }
        GroupCounts counts = countGroups(scope, firstGroups, values);
        List<BoardTableEngine.TableGroup> groups = new List<BoardTableEngine.TableGroup>();
        Map<String, List<Map<String, Object>>> rowsByFirstKey = new Map<String, List<Map<String, Object>>>();
        if (levels.size() > 1) {
            for (Map<String, Object> row : values) {
                String key = blankSafe(row.get(first.field.keyPath));
                if (!rowsByFirstKey.containsKey(key)) {
                    rowsByFirstKey.put(key, new List<Map<String, Object>>());
                }
                rowsByFirstKey.get(key).add(row);
            }
        }
        for (BoardTableEngine.TableGroup firstGroup : firstGroups) {
            first.decorate(firstGroup, counts.firstLevel.get(first.countKey(firstGroup.key)));
            firstGroup.summaries = counts.firstLevelSummaries.forKey(first.countKey(firstGroup.key));
            groups.add(firstGroup);
            if (levels.size() == 1) {
                continue;
            }
            BoardTableGroupLevel second = levels[1];
            Map<String, Integer> subCounts = counts.secondLevel.get(first.countKey(firstGroup.key));
            for (
                BoardTableEngine.TableGroup subgroup : BoardTableEngine.groupsInRowOrder(
                    rowsByFirstKey.get(blankSafe(firstGroup.key)),
                    second.field.keyPath,
                    second.field.labelPath
                )
            ) {
                subgroup.level = 2;
                subgroup.parentKey = firstGroup.key;
                second.decorate(subgroup, subCounts == null ? null : subCounts.get(second.countKey(subgroup.key)));
                subgroup.summaries = counts.secondLevelSummaries.forKey(
                    subgroupKey(first.countKey(firstGroup.key), second.countKey(subgroup.key))
                );
                groups.add(subgroup);
            }
        }
        return groups;
    }

    private static String blankSafe(Object key) {
        return key == null ? '' : String.valueOf(key);
    }

    /**
     * Record counts over the whole scope, restricted to `firstGroups`' keys: per first-level group, and per
     * second-level group within it (a `GROUP BY` over both levels; a first-level count sums its subgroups). A
     * parent-path level is counted in two slices, so records whose parent is missing land in "(Blank)": the platform
     * gives a missing parent's fields placeholder values in `WHERE` and `GROUP BY` (not null), so they are told apart
     * on the relationship itself (`Account.Id = null`).
     */
    private GroupCounts countGroups(
        BoardQueryService.QueryScope scope,
        List<BoardTableEngine.TableGroup> firstGroups,
        List<Map<String, Object>> values
    ) {
        Map<String, Object> binds = new Map<String, Object>(scope.binds);
        String restriction = levels[0].pageRestriction(firstGroups, binds);
        GroupCounts counts = new GroupCounts(summarySpecs);
        List<List<Boolean>> slices = new List<List<Boolean>>{ new List<Boolean>() };
        for (Integer i = 0; i < levels.size(); i++) {
            BoardTableGroupLevel level = levels[i];
            // A first-level blank is only in the restriction when on the page; a second-level blank may be anywhere
            // in the page's first-level groups (also on other pages), and they count toward them.
            Boolean countsBlank = level.isParentPath() && (i > 0 || level.hasBlankRow(values));
            List<List<Boolean>> extended = new List<List<Boolean>>();
            for (List<Boolean> slice : slices) {
                extended.add(withBlank(slice, false));
                if (countsBlank) {
                    extended.add(withBlank(slice, true));
                }
            }
            slices = extended;
        }
        for (List<Boolean> blanks : slices) {
            countSlice(scope, restriction, binds, counts, blanks);
        }
        return counts;
    }

    private static List<Boolean> withBlank(List<Boolean> slice, Boolean blank) {
        List<Boolean> extended = new List<Boolean>(slice);
        extended.add(blank);
        return extended;
    }

    /**
     * Counts (and summaries) of one slice: a level flagged in `blanks` is restricted to its "(Blank)" records and not
     * grouped; an unflagged parent-path level is restricted to records with a parent and a value.
     */
    private void countSlice(
        BoardQueryService.QueryScope scope,
        String restriction,
        Map<String, Object> binds,
        GroupCounts counts,
        List<Boolean> blanks
    ) {
        List<String> selectColumns = new List<String>();
        List<String> groupExpressions = new List<String>();
        List<String> predicates = new List<String>{ restriction };
        for (Integer i = 0; i < levels.size(); i++) {
            BoardTableGroupLevel level = levels[i];
            if (blanks[i]) {
                predicates.add(level.blankPredicate());
                continue;
            }
            if (level.isParentPath()) {
                predicates.add(level.valuePredicate());
            }
            selectColumns.addAll(level.selectColumns());
            groupExpressions.addAll(level.expressions);
        }
        selectColumns.add('COUNT(Id) recordCount');
        String soql = scope.buildSoql(
            String.join(selectColumns, ', ') + counts.firstLevelSummaries.aggregateSelect(),
            predicates,
            groupExpressions.isEmpty() ? '' : 'GROUP BY ' + String.join(groupExpressions, ', ')
        );
        for (SObject result : Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
            AggregateResult aggregate = (AggregateResult) result;
            Integer recordCount = (Integer) aggregate.get('recordCount');
            if (recordCount == null || recordCount == 0) {
                continue;
            }
            String firstKey = blanks[0] ? '' : levels[0].countKey(levels[0].keyOf(aggregate));
            Integer previous = counts.firstLevel.containsKey(firstKey) ? counts.firstLevel.get(firstKey) : 0;
            counts.firstLevel.put(firstKey, previous + recordCount);
            String secondKey = null;
            if (levels.size() > 1) {
                if (!counts.secondLevel.containsKey(firstKey)) {
                    counts.secondLevel.put(firstKey, new Map<String, Integer>());
                }
                Map<String, Integer> subCounts = counts.secondLevel.get(firstKey);
                secondKey = blanks[1] ? '' : levels[1].countKey(levels[1].keyOf(aggregate));
                Integer subPrevious = subCounts.containsKey(secondKey) ? subCounts.get(secondKey) : 0;
                subCounts.put(secondKey, subPrevious + recordCount);
            }
            counts.addSummaries(firstKey, secondKey, aggregate);
        }
    }

    /**
     * Row limit (Detail rows on): the first `groupLimit` first-level groups in the group order (one `GROUP BY`, blanks
     * last), as a `WHERE` predicate restricting the record stream to them (an IN-list of keys; dates the range of their
     * buckets, which are contiguous in the group order; blanks by `= null`), its binds added to `scope.binds`. Null
     * when the scope has no more groups than `groupLimit` (nothing to cut).
     */
    public String topGroupsRestriction(BoardQueryService.QueryScope scope, Integer groupLimit) {
        BoardTableGroupLevel first = levels[0];
        List<String> groupExpressions = new List<String>(first.expressions);
        List<String> orderParts = new List<String>();
        String direction = ' ' + first.field.sortDirection + ' NULLS LAST';
        if (first.granularity != null) {
            // Buckets never overlap, so the earliest date of each bucket orders them as the stream does.
            orderParts.add('MIN(' + first.field.fieldPath + ')' + direction);
        } else {
            for (String path : new List<String>{ first.field.orderBy, first.field.labelPath }) {
                if (path != null) {
                    orderParts.add(constantPerGroupExpression(scope, path, groupExpressions) + direction);
                }
            }
            orderParts.add(first.field.fieldPath + direction);
        }
        // A parent path's "(Blank)" group (missing parents included) can't be grouped reliably: rank the groups with a
        // value, the blank one coming last as in the group order.
        Boolean parentPath = first.isParentPath();
        String soql = scope.buildSoql(
            String.join(first.selectColumns(), ', '),
            parentPath ? new List<String>{ first.valuePredicate() } : null,
            'GROUP BY ' +
                String.join(groupExpressions, ', ') +
                ' ORDER BY ' +
                String.join(orderParts, ', ') +
                ' LIMIT ' +
                (groupLimit + 1)
        );
        List<SObject> results = Database.queryWithBinds(soql, scope.binds, AccessLevel.USER_MODE);
        Boolean blankCut =
            parentPath &&
            results.size() == groupLimit &&
            Database.countQueryWithBinds(
                scope.buildSoql('COUNT()', new List<String>{ first.blankPredicate() }, 'LIMIT 1'),
                scope.binds,
                AccessLevel.USER_MODE
            ) > 0;
        if (results.size() < groupLimit || (results.size() == groupLimit && !blankCut)) {
            return null;
        }
        List<BoardTableEngine.TableGroup> topGroups = new List<BoardTableEngine.TableGroup>();
        for (Integer i = 0; i < groupLimit; i++) {
            BoardTableEngine.TableGroup topGroup = new BoardTableEngine.TableGroup();
            topGroup.key = first.keyOf((AggregateResult) results[i]);
            topGroups.add(topGroup);
        }
        Map<String, Object> restrictionBinds = new Map<String, Object>();
        String predicate = first.pageRestriction(topGroups, restrictionBinds);
        // Page-scoped counts reuse these bind names on the narrowed scope, so the top-group binds get their own.
        for (String bindName : restrictionBinds.keySet()) {
            predicate = predicate.replace(':' + bindName, ':' + TOP_BIND_PREFIX + bindName);
            scope.binds.put(TOP_BIND_PREFIX + bindName, restrictionBinds.get(bindName));
        }
        return predicate;
    }

    /**
     * Aggregate expression of a field constant per first-level group (its order field or a lookup's record name):
     * the path itself, added to `groupExpressions`, when groupable (it never splits a group), else `MAX(path)`.
     */
    private static String constantPerGroupExpression(
        BoardQueryService.QueryScope scope,
        String path,
        List<String> groupExpressions
    ) {
        BoardQueryService.ResolvedField field = BoardTableQuery.resolveTablePath(scope.objectDescribe, path);
        if (field.describe.isGroupable()) {
            groupExpressions.add(field.path);
            return field.path;
        }
        return 'MAX(' + field.path + ')';
    }

    /**
     * Full-group counts by count key: first-level groups, and second-level groups per first-level count key; plus
     * each group's whole-group Stacked summaries per level (a first-level group merges its subgroups' rows).
     */
    private class GroupCounts {
        Map<String, Integer> firstLevel = new Map<String, Integer>();
        Map<String, Map<String, Integer>> secondLevel = new Map<String, Map<String, Integer>>();
        BoardTableGroupSummaries firstLevelSummaries;
        BoardTableGroupSummaries secondLevelSummaries;

        GroupCounts(List<BoardTableEngine.SummarySpec> summarySpecs) {
            firstLevelSummaries = new BoardTableGroupSummaries(summarySpecs);
            secondLevelSummaries = new BoardTableGroupSummaries(summarySpecs);
        }

        /** Merges one `GROUP BY` row into its first-level group's and (with two levels) its subgroup's summaries. */
        void addSummaries(String firstKey, String secondKey, AggregateResult aggregate) {
            firstLevelSummaries.add(firstKey, aggregate);
            if (secondKey != null) {
                secondLevelSummaries.add(subgroupKey(firstKey, secondKey), aggregate);
            }
        }
    }

    /** Summary key of a subgroup: its first-level and second-level count keys. */
    private static String subgroupKey(String firstKey, String secondKey) {
        return firstKey + '|' + secondKey;
    }

    /** A group field as the Widget renders it: group column header and Group row labels and links. */
    public class GroupField {
        /** Canonical group field path. */
        @AuraEnabled
        public String fieldPath;
        /** Key into `TableRow.values` holding each row's group key: `fieldPath`, or a date level's bucket key. */
        @AuraEnabled
        public String keyPath;
        /** Path of a lookup's record name in `TableRow.values` (e.g. `Opportunity.Name`), else null. */
        @AuraEnabled
        public String labelPath;
        @AuraEnabled
        public String label;
        /** `Schema.DisplayType` name of the group field. */
        @AuraEnabled
        public String dataType;
        /** Group order: `ASC` or `DESC` (blanks always last). */
        @AuraEnabled
        public String sortDirection;
        /** Date bucket granularity (`DAY`, `CALENDAR_MONTH`, ...) of a date group field, else null. */
        @AuraEnabled
        public String dateGranularity;
        /** Field constant per group the groups are ordered by (e.g. `Opportunity.Amount`), else null (by value). */
        @AuraEnabled
        public String orderBy;
        /** The second group field, nested under this one; null with one group field. */
        @AuraEnabled
        public GroupField secondLevel;
    }
}