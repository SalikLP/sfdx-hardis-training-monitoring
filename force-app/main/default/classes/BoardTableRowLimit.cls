/**
 * Row limit on a grouped Table: the limit counts first-level groups ("Top 10 groups") in the group order, so it needs
 * no default sort.
 *
 * Detail rows on (max `MAX_GROUPS_WITH_DETAIL_ROWS`): a top-N group query first, then the Table's scope is narrowed to
 * those groups (an IN-list of keys), so the record stream, the page-scoped group counts and the Total row all cover
 * only them. Detail rows off (max `MAX_GROUPS_WITHOUT_DETAIL_ROWS`): the aggregate returns the top N Group rows and the
 * scope is narrowed to them for the Total row. Either way totals are computed after the limit.
 */
public with sharing class BoardTableRowLimit {
    /** Most first-level groups a Row limit keeps with Detail rows on (the record stream is filtered by an IN-list). */
    public static final Integer MAX_GROUPS_WITH_DETAIL_ROWS = 200;
    /** Most Group rows a Row limit keeps with Detail rows off (an aggregate query returns at most 2,000 rows). */
    public static final Integer MAX_GROUPS_WITHOUT_DETAIL_ROWS = 2000;
    private static final String TOP_GROUP_KEYS_BIND = 'tableTopGroupKeys';

    /**
     * Validated Row limit of a grouped Table: null when unset, else a whole number from 1 to 200 (Detail rows on) or
     * 2,000 (Detail rows off).
     */
    public static Integer resolveGroupLimit(Object rawLimit, Boolean detailRows) {
        if (rawLimit == null || (rawLimit instanceof String && String.isBlank((String) rawLimit))) {
            return null;
        }
        Integer max = detailRows ? MAX_GROUPS_WITH_DETAIL_ROWS : MAX_GROUPS_WITHOUT_DETAIL_ROWS;
        Decimal parsed;
        try {
            parsed = BoardQueryService.toDecimal(rawLimit);
        } catch (Exception notANumber) {
            parsed = null;
        }
        if (parsed == null || parsed != parsed.setScale(0) || parsed < 1 || parsed > max) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                detailRows
                    ? 'With Detail rows on, Row limit must be a whole number from 1 to 200 groups.'
                    : 'Row limit must be a whole number from 1 to 2,000.',
                null,
                'rowLimit'
            );
        }
        return parsed.intValue();
    }

    /**
     * Detail rows on: narrows `scope` to the request's top N first-level groups. Returns the Row limit when it cut
     * groups (the badge then reads "Top N groups"), else null (every group fits, the scope is left as is).
     */
    public static Integer limitToTopGroups(
        BoardQueryService.QueryScope scope,
        BoardTableGrouping grouping,
        Map<String, Object> request
    ) {
        Integer groupLimit = resolveGroupLimit(request.get('rowLimit'), true);
        if (groupLimit == null) {
            return null;
        }
        String restriction = grouping.topGroupsRestriction(scope, groupLimit);
        if (restriction == null) {
            return null;
        }
        scope.restrict(restriction);
        return groupLimit;
    }

    /**
     * Detail rows off: narrows `scope` to the shown Group rows (their keys; the "(Blank)" group by `= null`), so the
     * Total row covers only them.
     */
    public static void restrictToGroupRows(
        BoardQueryService.QueryScope scope,
        String groupFieldPath,
        Boolean isLookup,
        List<BoardTableAggregate.GroupRow> groupRows
    ) {
        List<Object> keys = isLookup ? (List<Object>) new List<Id>() : (List<Object>) new List<String>();
        Boolean hasBlank = false;
        for (BoardTableAggregate.GroupRow groupRow : groupRows) {
            if (groupRow.key == null) {
                hasBlank = true;
            } else {
                keys.add(isLookup ? (Object) Id.valueOf(groupRow.key) : (Object) groupRow.key);
            }
        }
        List<String> predicates = new List<String>();
        if (!keys.isEmpty()) {
            scope.binds.put(TOP_GROUP_KEYS_BIND, keys);
            predicates.add(groupFieldPath + ' IN :' + TOP_GROUP_KEYS_BIND);
        }
        if (hasBlank) {
            predicates.add(groupFieldPath + ' = null');
        }
        if (!predicates.isEmpty()) {
            scope.restrict(String.join(predicates, ' OR '));
        }
    }
}