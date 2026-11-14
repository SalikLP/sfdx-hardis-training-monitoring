/**
 * Pure in-memory engine of a Table with Detail rows off in the cursor tier: no SOQL, no describes.
 *
 * Rows (flattened `path -> value` maps, amounts already in the corporate currency) fold into one group per key, the
 * way the SOQL tier's `GROUP BY` folds them: text keys ignore case, null and empty keys form the "(Blank)" group.
 * Each group keeps its record count, the values constant per group (`Plan.valuePaths`, first non-blank value seen)
 * and one mergeable `BoardTableEngine.Summary` per summarized column. `state()` / `restore()` carry the running groups
 * from one cursor chunk call to the next. `orderGroups` then orders them like the SOQL tier's `ORDER BY`: by a summary,
 * by a value constant per group, or by the key (picklists in definition order), text ignoring case, blanks last in
 * either direction, ties by key, and the "(Blank)" group last.
 *
 * With a second group field (`Plan.secondLevel`) the running groups are second-level groups (each with its first-level
 * `parentKey`); `groups()` rolls them up into first-level groups, each with its second-level groups as `subgroups`
 * (counts summed, summaries merged), and `orderGroups` orders both levels. The SOQL tier feeds the same accumulator
 * with its `GROUP BY` rows (`addGroup`), so both tiers share the roll-up and the order.
 */
public with sharing class BoardTableAggregateEngine {
    /** What to group by, carry, summarize and order by. */
    public class Plan {
        /** Group field path; its value is the group key. */
        public String keyPath;
        /** Paths of values constant per group (lookup label, fields reached through the lookup group field). */
        public List<String> valuePaths = new List<String>();
        /** Summarized columns, in column order. */
        public List<BoardTableEngine.SummarySpec> specs = new List<BoardTableEngine.SummarySpec>();
        /** `ASC` or `DESC`. */
        public String direction = 'ASC';
        /** Order by this value constant per group (then by key); null orders by key or by a summary. */
        public String orderPath;
        /** Order by summary `orderFunction` of `specs[orderSpecIndex]` (then by key). */
        public Integer orderSpecIndex;
        public String orderFunction;
        /** Lower-cased path -> picklist values in definition order (the order SOQL sorts picklists in). */
        public Map<String, List<String>> rankedValues = new Map<String, List<String>>();
        /** The second group field's plan (key, values constant per second-level group, order); null for one level. */
        public Plan secondLevel;

        /**
         * Orders the groups by the summary `rawSummaryOrder` names (`{ columnId, summaryFunction }`) and returns its
         * spec; a summary the Table doesn't show is a CONFIG_ERROR.
         */
        public BoardTableEngine.SummarySpec orderBySummary(Object rawSummaryOrder) {
            Map<String, Object> summaryOrder = BoardQueryService.asMap(rawSummaryOrder);
            String columnId = BoardQueryService.getString(summaryOrder, 'columnId');
            Object rawFunction = summaryOrder.get('summaryFunction');
            String summaryFunction = rawFunction == null ? null : String.valueOf(rawFunction).trim().toUpperCase();
            for (Integer c = 0; c < specs.size(); c++) {
                if (specs[c].columnId == columnId && specs[c].functions.contains(summaryFunction)) {
                    orderSpecIndex = c;
                    orderFunction = summaryFunction;
                    return specs[c];
                }
            }
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Groups are ordered by a summary the Table does not show: ' + summaryFunction + ' of ' + columnId,
                null,
                'groupBy'
            );
        }
    }

    /** One group: key (null for "(Blank)"), record count, values constant per group, running summaries. */
    public class AggregatedGroup {
        public String key;
        /** Second-level groups: the key of the first-level group they are nested under. */
        public String parentKey;
        /** First-level groups of a two-level plan: their second-level groups (in order after `orderGroups`). */
        public List<AggregatedGroup> subgroups = new List<AggregatedGroup>();
        public Integer count = 0;
        public Map<String, Object> values = new Map<String, Object>();
        /** One per `Plan.specs` entry. */
        public List<BoardTableEngine.Summary> summaries = new List<BoardTableEngine.Summary>();
    }

    /** Running groups of one cursor-tier load. */
    public class Accumulator {
        private final Plan plan;
        private final List<AggregatedGroup> tracked = new List<AggregatedGroup>();
        /** Lower-cased key (`''` for "(Blank)") -> group. */
        private final Map<String, AggregatedGroup> byFoldedKey = new Map<String, AggregatedGroup>();

        public Accumulator(Plan plan) {
            this.plan = plan;
        }

        /** Adds one record's flattened values. */
        public void add(Map<String, Object> row) {
            Object rawKey = row.get(leafPlan().keyPath);
            String key = keyOf(rawKey);
            String parentKey = plan.secondLevel == null ? null : keyOf(row.get(plan.keyPath));
            AggregatedGroup aggregatedGroup = byFoldedKey.get(leafKey(parentKey, key));
            if (aggregatedGroup == null) {
                aggregatedGroup = newGroup(key);
                aggregatedGroup.parentKey = parentKey;
                aggregatedGroup.values.put(leafPlan().keyPath, rawKey);
                if (plan.secondLevel != null) {
                    aggregatedGroup.values.put(plan.keyPath, row.get(plan.keyPath));
                }
                track(aggregatedGroup);
            }
            aggregatedGroup.count++;
            for (String path : leafValuePaths()) {
                Object value = row.get(path);
                if (value != null && aggregatedGroup.values.get(path) == null) {
                    aggregatedGroup.values.put(path, value);
                }
            }
            for (Integer c = 0; c < plan.specs.size(); c++) {
                aggregatedGroup.summaries[c].add(row.get(plan.specs[c].fieldPath));
            }
        }

        /**
         * Merges one pre-aggregated group (a SOQL-tier `GROUP BY` row: key, `parentKey` with two levels, count,
         * values and one mergeable summary per spec) into the running groups.
         */
        public void addGroup(AggregatedGroup chunk) {
            AggregatedGroup aggregatedGroup = byFoldedKey.get(leafKey(chunk.parentKey, chunk.key));
            if (aggregatedGroup == null) {
                aggregatedGroup = newGroup(chunk.key);
                aggregatedGroup.parentKey = chunk.parentKey;
                track(aggregatedGroup);
            }
            aggregatedGroup.count += chunk.count;
            for (String path : chunk.values.keySet()) {
                if (aggregatedGroup.values.get(path) == null) {
                    aggregatedGroup.values.put(path, chunk.values.get(path));
                }
            }
            mergeSummaries(aggregatedGroup, chunk);
        }

        /**
         * Every group so far, unordered: with one level the running groups; with two the first-level groups rolled up
         * from them, each with its second-level groups as `subgroups`.
         */
        public List<AggregatedGroup> groups() {
            if (plan.secondLevel == null) {
                return tracked;
            }
            List<AggregatedGroup> firstLevel = new List<AggregatedGroup>();
            Map<String, AggregatedGroup> byParent = new Map<String, AggregatedGroup>();
            for (AggregatedGroup leaf : tracked) {
                AggregatedGroup parent = byParent.get(foldKey(leaf.parentKey));
                if (parent == null) {
                    parent = new AggregatedGroup();
                    parent.key = leaf.parentKey;
                    parent.values.put(plan.keyPath, leaf.values.get(plan.keyPath));
                    for (String path : plan.valuePaths) {
                        parent.values.put(path, null);
                    }
                    for (Integer c = 0; c < plan.specs.size(); c++) {
                        parent.summaries.add(new BoardTableEngine.Summary());
                    }
                    byParent.put(foldKey(leaf.parentKey), parent);
                    firstLevel.add(parent);
                }
                parent.count += leaf.count;
                for (String path : plan.valuePaths) {
                    if (parent.values.get(path) == null) {
                        parent.values.put(path, leaf.values.get(path));
                    }
                }
                mergeSummaries(parent, leaf);
                parent.subgroups.add(leaf);
            }
            return firstLevel;
        }

        /** Merges `chunk`'s summaries into `target`'s. */
        private void mergeSummaries(AggregatedGroup target, AggregatedGroup chunk) {
            for (Integer c = 0; c < plan.specs.size(); c++) {
                BoardTableEngine.Summary part = chunk.summaries[c];
                target.summaries[c].addAggregate(part.sum, part.count, part.min, part.max);
            }
        }

        /** The plan of the running groups: the second level's with two levels. */
        private Plan leafPlan() {
            return plan.secondLevel == null ? plan : plan.secondLevel;
        }

        /** Values each running group keeps: both levels' with two levels. */
        private List<String> leafValuePaths() {
            if (plan.secondLevel == null) {
                return plan.valuePaths;
            }
            List<String> paths = new List<String>(plan.valuePaths);
            paths.addAll(plan.secondLevel.valuePaths);
            return paths;
        }

        /** Folded running-group key: the key, prefixed by the (length-prefixed) parent key with two levels. */
        private String leafKey(String parentKey, String key) {
            if (plan.secondLevel == null) {
                return foldKey(key);
            }
            String parent = foldKey(parentKey);
            return parent.length() + ':' + parent + foldKey(key);
        }

        /** Compact running state: `[[key, count, values, [[sum, count, min, max], ...], parentKey], ...]`. */
        public String state() {
            List<Object> encoded = new List<Object>();
            for (AggregatedGroup aggregatedGroup : tracked) {
                List<Object> summaries = new List<Object>();
                for (BoardTableEngine.Summary summary : aggregatedGroup.summaries) {
                    summaries.add(new List<Object>{ summary.sum, summary.count, summary.min, summary.max });
                }
                encoded.add(
                    new List<Object>{
                        aggregatedGroup.key,
                        aggregatedGroup.count,
                        aggregatedGroup.values,
                        summaries,
                        aggregatedGroup.parentKey
                    }
                );
            }
            return JSON.serialize(encoded);
        }

        /** Re-loads the groups of a previous `state()`; a malformed state fails as a retryable error. */
        public Accumulator restore(String state) {
            if (String.isBlank(state)) {
                return this;
            }
            try {
                for (Object rawGroup : (List<Object>) JSON.deserializeUntyped(state)) {
                    List<Object> encoded = (List<Object>) rawGroup;
                    AggregatedGroup aggregatedGroup = newGroup((String) encoded[0]);
                    aggregatedGroup.parentKey = encoded.size() > 4 ? (String) encoded[4] : null;
                    aggregatedGroup.count = BoardQueryService.toDecimal(encoded[1]).intValue();
                    aggregatedGroup.values = (Map<String, Object>) encoded[2];
                    List<Object> summaries = (List<Object>) encoded[3];
                    for (Integer c = 0; c < plan.specs.size(); c++) {
                        List<Object> parts = (List<Object>) summaries[c];
                        BoardTableEngine.Summary summary = aggregatedGroup.summaries[c];
                        summary.sum = BoardQueryService.toDecimal(parts[0]);
                        summary.count = BoardQueryService.toDecimal(parts[1]).intValue();
                        summary.min = BoardQueryService.toDecimal(parts[2]);
                        summary.max = BoardQueryService.toDecimal(parts[3]);
                    }
                    track(aggregatedGroup);
                }
            } catch (Exception malformed) {
                throw BoardErrors.error(
                    BoardErrors.QUERY_ERROR,
                    'The table calculation can no longer continue. Retry to recalculate.',
                    null,
                    null,
                    true
                );
            }
            return this;
        }

        private AggregatedGroup newGroup(String key) {
            AggregatedGroup aggregatedGroup = new AggregatedGroup();
            aggregatedGroup.key = key;
            for (String path : leafValuePaths()) {
                aggregatedGroup.values.put(path, null);
            }
            for (Integer c = 0; c < plan.specs.size(); c++) {
                aggregatedGroup.summaries.add(new BoardTableEngine.Summary());
            }
            return aggregatedGroup;
        }

        private void track(AggregatedGroup aggregatedGroup) {
            tracked.add(aggregatedGroup);
            byFoldedKey.put(leafKey(aggregatedGroup.parentKey, aggregatedGroup.key), aggregatedGroup);
        }
    }

    /** A group key: null for null and blank values (the "(Blank)" group). */
    private static String keyOf(Object rawKey) {
        return rawKey == null || String.isBlank(String.valueOf(rawKey)) ? null : String.valueOf(rawKey);
    }

    private static String foldKey(String key) {
        return key == null ? '' : key.toLowerCase();
    }

    /** The groups in the SOQL tier's order, "(Blank)" last; with two levels each group's subgroups too. */
    public static List<AggregatedGroup> orderGroups(List<AggregatedGroup> groups, Plan plan) {
        List<AggregatedGroup> ordered = new List<AggregatedGroup>();
        AggregatedGroup blank;
        for (AggregatedGroup aggregatedGroup : groups) {
            if (aggregatedGroup.key == null) {
                blank = aggregatedGroup;
            } else {
                ordered.add(aggregatedGroup);
            }
        }
        ordered.sort(new GroupOrder(plan));
        if (blank != null) {
            ordered.add(blank);
        }
        if (plan.secondLevel != null) {
            for (AggregatedGroup aggregatedGroup : ordered) {
                aggregatedGroup.subgroups = orderGroups(aggregatedGroup.subgroups, plan.secondLevel);
            }
        }
        return ordered;
    }

    /** Row limit: the first `limitCount` groups of an ordered list (like `LIMIT` after the SOQL tier's `ORDER BY`). */
    public static List<AggregatedGroup> topGroups(List<AggregatedGroup> ordered, Integer limitCount) {
        List<AggregatedGroup> top = new List<AggregatedGroup>();
        for (Integer g = 0; g < ordered.size() && g < limitCount; g++) {
            top.add(ordered[g]);
        }
        return top;
    }

    /** A group's Stacked summaries, one `ColumnTotal` per spec, its summaries in the spec's order. */
    public static List<BoardTableEngine.ColumnTotal> summaries(
        AggregatedGroup aggregatedGroup,
        List<BoardTableEngine.SummarySpec> specs
    ) {
        return columnTotals(aggregatedGroup.summaries, specs);
    }

    /** Total row over every group: each column's group summaries merged. */
    public static List<BoardTableEngine.ColumnTotal> grandTotals(
        List<AggregatedGroup> groups,
        List<BoardTableEngine.SummarySpec> specs
    ) {
        List<BoardTableEngine.Summary> merged = new List<BoardTableEngine.Summary>();
        for (Integer c = 0; c < specs.size(); c++) {
            BoardTableEngine.Summary total = new BoardTableEngine.Summary();
            for (AggregatedGroup aggregatedGroup : groups) {
                BoardTableEngine.Summary part = aggregatedGroup.summaries[c];
                total.addAggregate(part.sum, part.count, part.min, part.max);
            }
            merged.add(total);
        }
        return columnTotals(merged, specs);
    }

    private static List<BoardTableEngine.ColumnTotal> columnTotals(
        List<BoardTableEngine.Summary> summaries,
        List<BoardTableEngine.SummarySpec> specs
    ) {
        List<BoardTableEngine.ColumnTotal> totals = new List<BoardTableEngine.ColumnTotal>();
        for (Integer c = 0; c < specs.size(); c++) {
            BoardTableEngine.ColumnTotal total = new BoardTableEngine.ColumnTotal(specs[c].columnId);
            for (String summaryFunction : specs[c].functions) {
                total.add(summaryFunction, summaries[c].value(summaryFunction));
            }
            totals.add(total);
        }
        return totals;
    }

    /** `ORDER BY <summary | constant value | key> <direction> NULLS LAST, <key> <direction>` over keyed groups. */
    private class GroupOrder implements Comparator<AggregatedGroup> {
        private final Plan plan;
        private final Integer factor;

        GroupOrder(Plan plan) {
            this.plan = plan;
            this.factor = 'DESC'.equalsIgnoreCase(plan.direction) ? -1 : 1;
        }

        public Integer compare(AggregatedGroup left, AggregatedGroup right) {
            Integer order = 0;
            if (plan.orderSpecIndex != null) {
                order = compareNullsLast(
                    left.summaries[plan.orderSpecIndex].value(plan.orderFunction),
                    right.summaries[plan.orderSpecIndex].value(plan.orderFunction),
                    null
                );
            } else if (plan.orderPath != null) {
                order = compareNullsLast(
                    left.values.get(plan.orderPath),
                    right.values.get(plan.orderPath),
                    plan.rankedValues.get(plan.orderPath.toLowerCase())
                );
            }
            if (order == 0) {
                order = compareNullsLast(
                    left.values.get(plan.keyPath),
                    right.values.get(plan.keyPath),
                    plan.rankedValues.get(plan.keyPath.toLowerCase())
                );
            }
            return order;
        }

        /** Blank values last in either direction; others compared, then flipped for `DESC`. */
        private Integer compareNullsLast(Object left, Object right, List<String> ranks) {
            Boolean leftBlank = isBlank(left);
            Boolean rightBlank = isBlank(right);
            if (leftBlank || rightBlank) {
                return leftBlank == rightBlank ? 0 : (leftBlank ? 1 : -1);
            }
            return factor * compareValues(left, right, ranks);
        }
    }

    private static Boolean isBlank(Object value) {
        return value == null || (value instanceof String && String.isBlank((String) value));
    }

    /** Picklist rank first (ranked before unranked), then numbers numerically, then text ignoring case. */
    private static Integer compareValues(Object left, Object right, List<String> ranks) {
        if (ranks != null) {
            Integer leftRank = ranks.indexOf(String.valueOf(left));
            Integer rightRank = ranks.indexOf(String.valueOf(right));
            if (leftRank >= 0 || rightRank >= 0) {
                if (leftRank < 0) {
                    return 1;
                }
                if (rightRank < 0) {
                    return -1;
                }
                return leftRank - rightRank;
            }
        }
        if (isNumber(left) && isNumber(right)) {
            Decimal leftNumber = BoardQueryService.toDecimal(left);
            Decimal rightNumber = BoardQueryService.toDecimal(right);
            return leftNumber == rightNumber ? 0 : (leftNumber < rightNumber ? -1 : 1);
        }
        String leftText = String.valueOf(left);
        String rightText = String.valueOf(right);
        Integer folded = leftText.toLowerCase().compareTo(rightText.toLowerCase());
        return folded != 0 ? folded : leftText.compareTo(rightText);
    }

    private static Boolean isNumber(Object value) {
        return value instanceof Decimal || value instanceof Integer || value instanceof Long || value instanceof Double;
    }
}