/**
 * Row grouping of a Table with Detail rows on: up to two group fields (lookup, picklist, text or date; direct or a
 * 1-5 hop parent path).
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
    /** Non-date field types a Table can group by (Detail rows on). */
    private static final Set<Schema.DisplayType> GROUP_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.REFERENCE,
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.COMBOBOX,
        Schema.DisplayType.STRING,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL
    };
    private static final Set<Schema.DisplayType> DATE_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME
    };
    /** Date granularities shared with the Chart widget. */
    private static final Set<String> DATE_GRANULARITIES = new Set<String>{
        'DAY',
        'CALENDAR_MONTH',
        'CALENDAR_QUARTER',
        'CALENDAR_YEAR',
        'FISCAL_QUARTER',
        'FISCAL_YEAR'
    };
    private static final Integer MAX_LEVELS = 2;
    private static final String GROUP_KEYS_BIND = 'tableGroupKeys';
    private static final String GROUP_FROM_BIND = 'tableGroupFrom';
    private static final String GROUP_TO_BIND = 'tableGroupTo';
    /** Prefix of the bind names of a Row limit's top-group restriction (kept apart from the page-scoped binds). */
    private static final String TOP_BIND_PREFIX = 'top_';
    private static Organization fiscalSettings;

    /** Resolved first group field returned to the Widget (the second, if any, as its `secondLevel`). */
    public GroupField resolvedField;
    private List<GroupLevel> levels = new List<GroupLevel>();
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
            levels.add(new GroupLevel(objectDescribe, BoardQueryService.asMap(groupBy[index]), index + 1));
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

    /** `Relationship.NameField` of a lookup's target (e.g. `Opportunity.Name`), or null when unreadable. */
    private static String nameFieldPath(BoardQueryService.ResolvedField reference) {
        String relationshipPath = relationshipPath(reference);
        if (relationshipPath == null) {
            return null;
        }
        Schema.DescribeSObjectResult target = BoardDescribe.describeObject(
            BoardQueryService.parentType(reference.describe)
        );
        if (!BoardDescribe.isReadableObject(target)) {
            return null;
        }
        String nameField = BoardDescribe.readableNameField(target);
        return nameField == null ? null : relationshipPath + '.' + nameField;
    }

    /** Relationship path of a lookup (`OpportunityId` -> `Opportunity`, `Account.ParentId` -> `Account.Parent`). */
    private static String relationshipPath(BoardQueryService.ResolvedField reference) {
        String relationshipName = reference.describe.getRelationshipName();
        if (relationshipName == null) {
            return null;
        }
        List<String> segments = reference.path.split('\\.');
        segments[segments.size() - 1] = relationshipName;
        return String.join(segments, '.');
    }

    /** `selectList` plus each group field and its label path, case-insensitively deduped. */
    public String extendSelect(String selectList) {
        Set<String> selected = new Set<String>();
        for (String path : selectList.split(',')) {
            selected.add(path.trim().toLowerCase());
        }
        List<String> extra = new List<String>();
        for (GroupLevel level : levels) {
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
        for (GroupLevel level : levels) {
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
            for (GroupLevel level : levels) {
                level.keyRow(row.values);
            }
        }
        GroupLevel first = levels[0];
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
            GroupLevel second = levels[1];
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
            GroupLevel level = levels[i];
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
            GroupLevel level = levels[i];
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
        GroupLevel first = levels[0];
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

    private static Organization getFiscalSettings() {
        if (fiscalSettings == null) {
            fiscalSettings = [
                SELECT FiscalYearStartMonth, UsesStartDateAsFiscalYearName
                FROM Organization
                LIMIT 1
            ];
        }
        return fiscalSettings;
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

    /** One group field: its resolved path, group order, and (for dates) bucketing. */
    private class GroupLevel {
        GroupField field = new GroupField();
        Boolean isLookup = false;
        Boolean isDateTime = false;
        /** Date bucket granularity; null for non-date levels. */
        String granularity;
        String alias;
        Map<String, String> picklistLabels = new Map<String, String>();
        /** Date bucket labels by bucket key, collected as rows are keyed. */
        Map<String, String> bucketLabels = new Map<String, String>();
        /** `GROUP BY` expressions and their aliases. */
        List<String> expressions = new List<String>();
        List<String> aliases = new List<String>();

        GroupLevel(Schema.DescribeSObjectResult objectDescribe, Map<String, Object> entry, Integer level) {
            String rawPath = BoardQueryService.getString(entry, 'fieldPath');
            if (String.isBlank(rawPath)) {
                throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Choose a group field.', null, 'groupBy');
            }
            BoardQueryService.ResolvedField resolved = BoardTableQuery.resolveTablePath(objectDescribe, rawPath);
            alias = 'g' + level;
            field.fieldPath = resolved.path;
            field.keyPath = resolved.path;
            field.label = resolved.describe.getLabel();
            field.dataType = resolved.type.name();
            field.sortDirection = 'DESC'.equalsIgnoreCase(BoardQueryService.getString(entry, 'sortDirection'))
                ? 'DESC'
                : 'ASC';
            resolveGranularity(resolved, rawPath, BoardQueryService.getString(entry, 'dateGranularity'), level);
            if (granularity == null) {
                if (!GROUP_TYPES.contains(resolved.type) || !resolved.describe.isGroupable()) {
                    throw BoardErrors.error(
                        BoardErrors.CONFIG_ERROR,
                        'A Table can group by a lookup, picklist, text or date field: ' + rawPath,
                        null,
                        rawPath
                    );
                }
                expressions.add(resolved.path);
                aliases.add(alias + 'k');
            }
            isLookup = resolved.type == Schema.DisplayType.REFERENCE;
            if (isLookup) {
                field.labelPath = nameFieldPath(resolved);
            }
            if (resolved.type == Schema.DisplayType.PICKLIST || resolved.type == Schema.DisplayType.COMBOBOX) {
                for (Schema.PicklistEntry picklistEntry : resolved.describe.getPicklistValues()) {
                    picklistLabels.put(picklistEntry.getValue(), picklistEntry.getLabel());
                }
            }
            resolveOrderBy(objectDescribe, resolved, BoardQueryService.getString(entry, 'orderBy'));
        }

        void resolveGranularity(
            BoardQueryService.ResolvedField resolved,
            String rawPath,
            String rawGranularity,
            Integer level
        ) {
            String requested = String.isBlank(rawGranularity) ? null : rawGranularity.trim().toUpperCase();
            Boolean isDate = DATE_TYPES.contains(resolved.type);
            if (requested != null && !DATE_GRANULARITIES.contains(requested)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Unsupported date granularity: ' + rawGranularity,
                    null,
                    rawPath
                );
            }
            if (requested != null && !isDate) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Date granularity requires a Date or DateTime field: ' + rawPath,
                    null,
                    rawPath
                );
            }
            if (!isDate) {
                return;
            }
            granularity = requested == null ? 'DAY' : requested;
            isDateTime = resolved.type == Schema.DisplayType.DATETIME;
            field.dateGranularity = granularity;
            field.keyPath = 'groupKey' + level;
            String source = isDateTime ? 'convertTimezone(' + resolved.path + ')' : resolved.path;
            switch on granularity {
                when 'DAY' {
                    addExpression(isDateTime ? 'DAY_ONLY(' + source + ')' : resolved.path, 'k');
                }
                when 'CALENDAR_MONTH' {
                    addExpression('CALENDAR_YEAR(' + source + ')', 'y');
                    addExpression('CALENDAR_MONTH(' + source + ')', 'p');
                }
                when 'CALENDAR_QUARTER' {
                    addExpression('CALENDAR_YEAR(' + source + ')', 'y');
                    addExpression('CALENDAR_QUARTER(' + source + ')', 'p');
                }
                when 'CALENDAR_YEAR' {
                    addExpression('CALENDAR_YEAR(' + source + ')', 'y');
                }
                when 'FISCAL_QUARTER' {
                    addExpression('FISCAL_YEAR(' + source + ')', 'y');
                    addExpression('FISCAL_QUARTER(' + source + ')', 'p');
                }
                when else {
                    addExpression('FISCAL_YEAR(' + source + ')', 'y');
                }
            }
        }

        void addExpression(String expression, String suffix) {
            expressions.add(expression);
            aliases.add(alias + suffix);
        }

        /** Group order by a field constant per group: a field of the lookup group field's record. */
        void resolveOrderBy(
            Schema.DescribeSObjectResult objectDescribe,
            BoardQueryService.ResolvedField resolved,
            String rawOrderBy
        ) {
            if (String.isBlank(rawOrderBy)) {
                return;
            }
            String prefix = isLookup ? relationshipPath(resolved) : null;
            BoardQueryService.ResolvedField orderField = BoardTableQuery.resolveTablePath(objectDescribe, rawOrderBy);
            if (prefix == null || !orderField.path.startsWithIgnoreCase(prefix + '.')) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Order groups by a field of the lookup group field\'s record (e.g. Opportunity.Amount): ' +
                    rawOrderBy,
                    null,
                    rawOrderBy
                );
            }
            if (!orderField.describe.isSortable()) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Field is not sortable: ' + rawOrderBy,
                    null,
                    rawOrderBy
                );
            }
            field.orderBy = orderField.path;
        }

        /** `ORDER BY` paths of this level: order field, lookup record name, group field (dates by their raw value). */
        List<String> orderPaths() {
            List<String> paths = new List<String>();
            for (String path : new List<String>{ field.orderBy, field.labelPath, field.fieldPath }) {
                if (path != null) {
                    paths.add(path);
                }
            }
            return paths;
        }

        /**
         * A parent path (e.g. `Account.CreatedDate`). For a record whose parent is missing the platform evaluates the
         * parent's fields to placeholder values in `WHERE`, `GROUP BY` and `ORDER BY` (a date, not null), though the
         * selected value is null; such records are told apart on the relationship Id at each hop.
         */
        Boolean isParentPath() {
            return field.fieldPath.contains('.');
        }

        /** `Id` path of each relationship hop (`Account.Owner.Name` -> `Account.Id`, `Account.Owner.Id`). */
        List<String> parentIdPaths() {
            List<String> segments = field.fieldPath.split('\\.');
            List<String> paths = new List<String>();
            for (Integer hop = 1; hop < segments.size(); hop++) {
                List<String> relationship = new List<String>();
                for (Integer i = 0; i < hop; i++) {
                    relationship.add(segments[i]);
                }
                paths.add(String.join(relationship, '.') + '.Id');
            }
            return paths;
        }

        /** Records of this level's "(Blank)" group: a missing parent at any hop, or no value. */
        String blankPredicate() {
            List<String> predicates = new List<String>();
            for (String idPath : parentIdPaths()) {
                predicates.add(idPath + ' = null');
            }
            predicates.add(field.fieldPath + ' = null');
            return '(' + String.join(predicates, ' OR ') + ')';
        }

        /** Records of this level's non-blank groups: every parent present, and a value. */
        String valuePredicate() {
            List<String> predicates = new List<String>();
            for (String idPath : parentIdPaths()) {
                predicates.add(idPath + ' != null');
            }
            predicates.add(field.fieldPath + ' != null');
            return '(' + String.join(predicates, ' AND ') + ')';
        }

        /** Whether a loaded row falls in this level's "(Blank)" group. */
        Boolean hasBlankRow(List<Map<String, Object>> rows) {
            for (Map<String, Object> row : rows) {
                Object key = row.get(field.keyPath);
                if (key == null || String.isBlank(String.valueOf(key))) {
                    return true;
                }
            }
            return false;
        }

        List<String> selectColumns() {
            List<String> columns = new List<String>();
            for (Integer i = 0; i < expressions.size(); i++) {
                columns.add(expressions[i] + ' ' + aliases[i]);
            }
            return columns;
        }

        /** Writes a date row's bucket key under `keyPath` (other levels key rows by the group field itself). */
        void keyRow(Map<String, Object> row) {
            if (granularity == null) {
                return;
            }
            Date day = dayOf(row.get(field.fieldPath));
            if (day == null) {
                row.put(field.keyPath, null);
                return;
            }
            List<String> bucket = bucketOf(day);
            bucketLabels.put(bucket[0], bucket[1]);
            row.put(field.keyPath, bucket[0]);
        }

        /** Local calendar date of a Date or DateTime value (DateTimes in the user's time zone, as `convertTimezone`). */
        Date dayOf(Object raw) {
            if (raw == null) {
                return null;
            }
            return isDateTime ? ((Datetime) raw).date() : (Date) raw;
        }

        /** Group key of an aggregate row (as `keyRow` writes it for a record); null for blanks. */
        String keyOf(AggregateResult aggregate) {
            if (granularity == null) {
                Object raw = aggregate.get(alias + 'k');
                return raw == null ? null : String.valueOf(raw);
            }
            if (granularity == 'DAY') {
                Date day = (Date) aggregate.get(alias + 'k');
                return day == null ? null : String.valueOf(day);
            }
            Integer year = (Integer) aggregate.get(alias + 'y');
            Integer period = aliases.size() > 1 ? (Integer) aggregate.get(alias + 'p') : null;
            return year == null ? null : bucketKey(year, period);
        }

        /** Count key: text groups match case-insensitively, as `GROUP BY` folds case; blanks under `''`. */
        String countKey(String key) {
            if (String.isBlank(key)) {
                return '';
            }
            return isLookup || granularity != null ? key : key.toLowerCase();
        }

        /** Sets a group's full-group count, lookup link and display label (picklist label, date bucket label). */
        void decorate(BoardTableEngine.TableGroup tableGroup, Integer count) {
            tableGroup.count = count == null ? 0 : count;
            if (tableGroup.key == null) {
                return;
            }
            if (isLookup) {
                tableGroup.recordId = tableGroup.key;
            }
            if (picklistLabels.containsKey(tableGroup.key)) {
                tableGroup.label = picklistLabels.get(tableGroup.key);
            }
            if (bucketLabels.containsKey(tableGroup.key)) {
                tableGroup.label = bucketLabels.get(tableGroup.key);
            }
        }

        /**
         * `WHERE` predicate limiting the count query to the page's groups of this (first) level: their keys, or for
         * dates the range from the first to the last bucket on the page (the page's buckets are contiguous).
         */
        String pageRestriction(List<BoardTableEngine.TableGroup> groups, Map<String, Object> binds) {
            List<String> predicates = new List<String>();
            Boolean hasBlank = false;
            List<Object> keys = isLookup ? (List<Object>) new List<Id>() : (List<Object>) new List<String>();
            Date firstDay;
            Date lastDay;
            for (BoardTableEngine.TableGroup tableGroup : groups) {
                if (tableGroup.key == null) {
                    hasBlank = true;
                } else if (granularity != null) {
                    Date day = bucketStart(tableGroup.key);
                    firstDay = firstDay == null || day < firstDay ? day : firstDay;
                    lastDay = lastDay == null || day > lastDay ? day : lastDay;
                } else {
                    keys.add(isLookup ? (Object) Id.valueOf(tableGroup.key) : (Object) tableGroup.key);
                }
            }
            if (!keys.isEmpty()) {
                binds.put(GROUP_KEYS_BIND, keys);
                predicates.add(withValue(field.fieldPath + ' IN :' + GROUP_KEYS_BIND));
            }
            if (firstDay != null) {
                Date endDay = nextBucketStart(lastDay);
                binds.put(GROUP_FROM_BIND, isDateTime ? (Object) localMidnight(firstDay) : (Object) firstDay);
                binds.put(GROUP_TO_BIND, isDateTime ? (Object) localMidnight(endDay) : (Object) endDay);
                predicates.add(
                    withValue(
                        '(' +
                            field.fieldPath +
                            ' >= :' +
                            GROUP_FROM_BIND +
                            ' AND ' +
                            field.fieldPath +
                            ' < :' +
                            GROUP_TO_BIND +
                            ')'
                    )
                );
            }
            if (hasBlank) {
                predicates.add(isParentPath() ? blankPredicate() : field.fieldPath + ' = null');
            }
            return String.join(predicates, ' OR ');
        }

        /** A key predicate of a parent path also requires the parent (a missing one's placeholder could match). */
        String withValue(String keyPredicate) {
            return isParentPath() ? '(' + keyPredicate + ' AND ' + valuePredicate() + ')' : keyPredicate;
        }

        Datetime localMidnight(Date day) {
            return Datetime.newInstance(day, Time.newInstance(0, 0, 0, 0));
        }

        // ---- Date buckets (keys and labels as the Chart widget's: `2026-03`, `2026-Q1`, `FY2026-Q2`) ----------------

        /** `[key, label]` of the bucket holding `day`. */
        List<String> bucketOf(Date day) {
            if (granularity == 'DAY') {
                return new List<String>{ String.valueOf(day), day.format() };
            }
            Integer period;
            Integer year = day.year();
            switch on granularity {
                when 'CALENDAR_MONTH' {
                    period = day.month();
                }
                when 'CALENDAR_QUARTER' {
                    period = (day.month() - 1) / 3 + 1;
                }
                when 'CALENDAR_YEAR' {
                    period = null;
                }
                when else {
                    year = fiscalYearName(day);
                    period = granularity == 'FISCAL_QUARTER' ? fiscalQuarterIndex(day) + 1 : null;
                }
            }
            return new List<String>{ bucketKey(year, period), bucketLabel(year, period) };
        }

        String bucketKey(Integer year, Integer period) {
            String yearText = String.valueOf(year);
            switch on granularity {
                when 'CALENDAR_MONTH' {
                    return yearText + '-' + String.valueOf(period).leftPad(2, '0');
                }
                when 'CALENDAR_QUARTER' {
                    return yearText + '-Q' + period;
                }
                when 'CALENDAR_YEAR' {
                    return yearText;
                }
                when 'FISCAL_QUARTER' {
                    return 'FY' + yearText + '-Q' + period;
                }
                when else {
                    return 'FY' + yearText;
                }
            }
        }

        String bucketLabel(Integer year, Integer period) {
            String yearText = String.valueOf(year);
            switch on granularity {
                when 'CALENDAR_MONTH' {
                    return Datetime.newInstance(year, period, 1).format('MMM yyyy');
                }
                when 'CALENDAR_QUARTER' {
                    return 'Q' + period + ' ' + yearText;
                }
                when 'CALENDAR_YEAR' {
                    return yearText;
                }
                when 'FISCAL_QUARTER' {
                    return 'Q' + period + ' FY' + yearText;
                }
                when else {
                    return 'FY' + yearText;
                }
            }
        }

        /** First day of the bucket a bucket key names (inverse of `bucketKey`). */
        Date bucketStart(String key) {
            if (granularity == 'DAY') {
                return Date.valueOf(key);
            }
            String body = key.removeStart('FY');
            Integer year = Integer.valueOf(body.left(4));
            String periodText = body.length() > 4 ? body.substring(5).removeStart('Q') : null;
            Integer period = periodText == null ? null : Integer.valueOf(periodText);
            switch on granularity {
                when 'CALENDAR_MONTH' {
                    return Date.newInstance(year, period, 1);
                }
                when 'CALENDAR_QUARTER' {
                    return Date.newInstance(year, (period - 1) * 3 + 1, 1);
                }
                when 'CALENDAR_YEAR' {
                    return Date.newInstance(year, 1, 1);
                }
                when else {
                    Date fiscalStart = fiscalYearStartFor(year);
                    return period == null ? fiscalStart : fiscalStart.addMonths((period - 1) * 3);
                }
            }
        }

        /** First day of the bucket after the one starting `start`. */
        Date nextBucketStart(Date start) {
            switch on granularity {
                when 'DAY' {
                    return start.addDays(1);
                }
                when 'CALENDAR_MONTH' {
                    return start.addMonths(1);
                }
                when 'CALENDAR_QUARTER', 'FISCAL_QUARTER' {
                    return start.addMonths(3);
                }
                when else {
                    return start.addMonths(12);
                }
            }
        }

        Integer fiscalStartMonth() {
            Organization settings = getFiscalSettings();
            return settings.FiscalYearStartMonth == null ? 1 : settings.FiscalYearStartMonth;
        }

        /** Whether a fiscal year is named by the calendar year it ends in (the default when it starts after January). */
        Boolean namedByEndYear() {
            return fiscalStartMonth() != 1 && !getFiscalSettings().UsesStartDateAsFiscalYearName;
        }

        Integer fiscalYearName(Date day) {
            Integer startYear = day.month() >= fiscalStartMonth() ? day.year() : day.year() - 1;
            return namedByEndYear() ? startYear + 1 : startYear;
        }

        Integer fiscalQuarterIndex(Date day) {
            return Math.mod(day.month() - fiscalStartMonth() + 12, 12) / 3;
        }

        /** First day of the fiscal year named `fiscalYear`. */
        Date fiscalYearStartFor(Integer fiscalYear) {
            Integer startYear = namedByEndYear() ? fiscalYear - 1 : fiscalYear;
            return Date.newInstance(startYear, fiscalStartMonth(), 1);
        }
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