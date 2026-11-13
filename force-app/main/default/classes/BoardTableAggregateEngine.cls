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
            Object rawKey = row.get(plan.keyPath);
            String key = rawKey == null || String.isBlank(String.valueOf(rawKey)) ? null : String.valueOf(rawKey);
            AggregatedGroup aggregatedGroup = byFoldedKey.get(foldKey(key));
            if (aggregatedGroup == null) {
                aggregatedGroup = newGroup(key);
                aggregatedGroup.values.put(plan.keyPath, rawKey);
                track(aggregatedGroup);
            }
            aggregatedGroup.count++;
            for (String path : plan.valuePaths) {
                Object value = row.get(path);
                if (value != null && aggregatedGroup.values.get(path) == null) {
                    aggregatedGroup.values.put(path, value);
                }
            }
            for (Integer c = 0; c < plan.specs.size(); c++) {
                aggregatedGroup.summaries[c].add(row.get(plan.specs[c].fieldPath));
            }
        }

        /** Every group so far, unordered. */
        public List<AggregatedGroup> groups() {
            return tracked;
        }

        /** Compact running state: `[[key, count, values, [[sum, count, min, max], ...]], ...]`. */
        public String state() {
            List<Object> encoded = new List<Object>();
            for (AggregatedGroup aggregatedGroup : tracked) {
                List<Object> summaries = new List<Object>();
                for (BoardTableEngine.Summary summary : aggregatedGroup.summaries) {
                    summaries.add(new List<Object>{ summary.sum, summary.count, summary.min, summary.max });
                }
                encoded.add(
                    new List<Object>{ aggregatedGroup.key, aggregatedGroup.count, aggregatedGroup.values, summaries }
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
            for (String path : plan.valuePaths) {
                aggregatedGroup.values.put(path, null);
            }
            for (Integer c = 0; c < plan.specs.size(); c++) {
                aggregatedGroup.summaries.add(new BoardTableEngine.Summary());
            }
            return aggregatedGroup;
        }

        private void track(AggregatedGroup aggregatedGroup) {
            tracked.add(aggregatedGroup);
            byFoldedKey.put(foldKey(aggregatedGroup.key), aggregatedGroup);
        }
    }

    private static String foldKey(String key) {
        return key == null ? '' : key.toLowerCase();
    }

    /** The groups in the SOQL tier's order, "(Blank)" last. */
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