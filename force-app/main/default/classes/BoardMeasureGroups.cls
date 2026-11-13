/**
 * Measure query grouping and the Measure join: pure, in memory (no SOQL, no describes).
 *
 * A Widget's Measures are grouped by the rows they aggregate: Measures with the same Measure condition (a Base filter
 * condition tree, `{ logic, conditions[] }`) share one group, so each group runs as one query over the Widget's scope
 * narrowed by that condition. `MeasureJoin` merges every group's grouped values back into one row per category /
 * series key, one value per Measure in Measure order.
 */
public inherited sharing class BoardMeasureGroups {
    /** Groups in order of their first Measure. */
    public List<MeasureGroup> groups = new List<MeasureGroup>();

    /** Groups `rawMeasures` (Measure config maps, each with an optional `condition`). */
    public BoardMeasureGroups(List<Object> rawMeasures) {
        Map<String, MeasureGroup> byKey = new Map<String, MeasureGroup>();
        for (Integer i = 0; i < rawMeasures.size(); i++) {
            Object condition = conditionOf(rawMeasures[i]);
            // Average per record Measures query per record of their per-record field: a group of their own.
            String key = groupKey(condition) + BoardAveragePerRecord.groupKeySuffix(rawMeasures[i]);
            MeasureGroup measureGroup = byKey.get(key);
            if (measureGroup == null) {
                measureGroup = new MeasureGroup(condition);
                if (BoardAveragePerRecord.isPerRecord(rawMeasures[i])) {
                    measureGroup.perField = BoardAveragePerRecord.perFieldOf(rawMeasures[i]);
                }
                byKey.put(key, measureGroup);
                groups.add(measureGroup);
            }
            measureGroup.measureIndexes.add(i);
        }
    }

    /** True when at least one Measure has a Measure condition. */
    public Boolean hasConditions() {
        for (MeasureGroup measureGroup : groups) {
            if (measureGroup.condition != null) {
                return true;
            }
        }
        return false;
    }

    /** A Measure's condition, or null when it has none (or a blank one). */
    public static Object conditionOf(Object rawMeasure) {
        if (!(rawMeasure instanceof Map<String, Object>)) {
            return null;
        }
        Object condition = ((Map<String, Object>) rawMeasure).get('condition');
        return isBlank(condition) ? null : condition;
    }

    /** The grouping key of a Measure condition: Measures with equal keys run as one query. */
    public static String groupKey(Object condition) {
        return condition == null ? '' : JSON.serialize(condition);
    }

    /** A missing condition, an empty map, or a group with no conditions. */
    public static Boolean isBlank(Object condition) {
        if (condition == null) {
            return true;
        }
        if (!(condition instanceof Map<String, Object>)) {
            return false;
        }
        Map<String, Object> source = (Map<String, Object>) condition;
        if (source.isEmpty()) {
            return true;
        }
        if (source.containsKey('conditions') && !source.containsKey('fieldPath')) {
            Object children = source.get('conditions');
            return children == null || (children instanceof List<Object> && ((List<Object>) children).isEmpty());
        }
        return false;
    }

    /** Measures that aggregate the same rows: their condition (null for none) and their positions in the Widget. */
    public class MeasureGroup {
        public Object condition;
        public List<Integer> measureIndexes = new List<Integer>();
        /** Average per record group: the per-record field its query groups by; null for plain Measures. */
        public String perField;

        public MeasureGroup(Object condition) {
            this.condition = condition;
        }

        /**
         * This group's partials (one per group Measure) placed at their Measure positions among `measureCount`
         * Measures; the other positions get empty partials.
         */
        public List<BoardChartEngine.Partial> spread(
            List<BoardChartEngine.Partial> groupPartials,
            Integer measureCount
        ) {
            List<BoardChartEngine.Partial> result = new List<BoardChartEngine.Partial>();
            for (Integer i = 0; i < measureCount; i++) {
                result.add(new BoardChartEngine.Partial());
            }
            for (Integer i = 0; i < measureIndexes.size(); i++) {
                result[measureIndexes[i]] = groupPartials[i];
            }
            return result;
        }
    }

    /**
     * Joins the grouped values of every group's query on the Panel / category / series key (first-seen order). A key
     * a group never returned keeps a blank value for that group's Measures, or 0 for a `COUNT` Measure.
     */
    public class MeasureJoin {
        private List<String> aggregateFunctions;
        private List<BoardChartEngine.GroupedRow> joined = new List<BoardChartEngine.GroupedRow>();
        private Map<String, BoardChartEngine.GroupedRow> index = new Map<String, BoardChartEngine.GroupedRow>();

        /** `aggregateFunctions`: one per Measure of the Widget, in Measure order. */
        public MeasureJoin(List<String> aggregateFunctions) {
            this.aggregateFunctions = aggregateFunctions;
        }

        /** One grouped row of `measureGroup`'s query: its values in the group's Measure order. */
        public void put(
            MeasureGroup measureGroup,
            String categoryValue,
            String categoryLabel,
            String seriesValue,
            String seriesLabel,
            List<Object> groupValues
        ) {
            put(
                measureGroup,
                new List<String>{ null, null },
                new List<String>{ categoryValue, categoryLabel },
                new List<String>{ seriesValue, seriesLabel },
                groupValues
            );
        }

        /**
         * One grouped row of `measureGroup`'s query in a Panel (Small multiples): `[value, label]` pairs of the Panel,
         * category and series.
         */
        public void put(
            MeasureGroup measureGroup,
            List<String> panel,
            List<String> category,
            List<String> series,
            List<Object> groupValues
        ) {
            String key = JSON.serialize(new List<String>{ panel[0], category[0], series[0] });
            BoardChartEngine.GroupedRow row = index.get(key);
            if (row == null) {
                row = new BoardChartEngine.GroupedRow(category[0], category[1], series[0], series[1]);
                row.panelValue = panel[0];
                row.panelLabel = panel[1];
                row.values = new List<Decimal>();
                Decimal zero = 0;
                for (String aggregateFunction : aggregateFunctions) {
                    row.values.add(aggregateFunction == 'COUNT' ? zero : null);
                }
                joined.add(row);
                index.put(key, row);
            }
            for (Integer i = 0; i < measureGroup.measureIndexes.size(); i++) {
                row.values[measureGroup.measureIndexes[i]] = BoardQueryService.toDecimal(groupValues[i]);
            }
        }

        /** The joined rows, one value per Measure. */
        public List<BoardChartEngine.GroupedRow> rows() {
            return joined;
        }

        /** Puts every joined row into `accumulator` (SOQL tier: final values). */
        public void putInto(BoardChartEngine.Accumulator accumulator) {
            for (BoardChartEngine.GroupedRow row : joined) {
                List<Object> values = new List<Object>();
                for (Decimal value : row.values) {
                    values.add(value);
                }
                accumulator.put(
                    row.panelValue,
                    row.panelLabel,
                    row.categoryValue,
                    row.categoryLabel,
                    row.seriesValue,
                    row.seriesLabel,
                    values
                );
            }
        }
    }
}