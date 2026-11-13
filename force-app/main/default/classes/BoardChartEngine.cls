/**
 * Pure in-memory Chart widget engine: no SOQL, no describes.
 *
 * Fed with grouped rows (one per category / series pair, each holding one value per Measure) from either query tier,
 * it merges cursor-chunk partials (`Accumulator`), then sorts the categories, applies max categories +
 * "Other" or truncation, caps the series the same way, and returns the shaped chart (`shape`). The client draws the
 * shape as is and never re-aggregates.
 */
public with sharing class BoardChartEngine {
    /** Key of the "(Blank)" category or series (null field value). */
    public static final String BLANK_KEY = '__blank__';
    /** Key of the rolled-up "Other" category or series. */
    public static final String OTHER_KEY = '__other__';
    /** Series key of a chart without a series field (one series per Measure). */
    public static final String VALUE_KEY = '__value__';
    /** Colour key prefix of a Measure in a chart without a series field (`measure:0`, `measure:1`...). */
    public static final String MEASURE_COLOUR_PREFIX = 'measure:';
    public static final String BLANK_LABEL = '(Blank)';
    public static final String OTHER_LABEL = 'Other';
    /** Share of total (`showAs` of a Measure): its plain value, or a fraction of the grand or category total. */
    public static final String SHOW_AS_VALUE = 'value';
    public static final String SHOW_AS_PERCENT_OF_TOTAL = 'percentOfTotal';
    public static final String SHOW_AS_PERCENT_OF_CATEGORY = 'percentOfCategory';

    /** Aggregates whose values add up, so they can be summed into "Other". */
    private static final Set<String> ROLLUP_FUNCTIONS = new Set<String>{ 'COUNT', 'SUM' };
    private static final Set<String> SORTS = new Set<String>{
        'VALUE_DESC',
        'VALUE_ASC',
        'LABEL_ASC',
        'LABEL_DESC',
        'PICKLIST_ORDER',
        'CHRONOLOGICAL_ASC',
        'CHRONOLOGICAL_DESC'
    };

    // ---------------------------------------------------------------------------------------------------------
    // Grouped rows and cursor accumulation
    // ---------------------------------------------------------------------------------------------------------

    /**
     * One grouped row: a category / series pair and its value per Measure. Rows from a SOQL `GROUP BY` carry final
     * `values`; rows accumulated from cursor chunks carry running `partials` instead.
     */
    public class GroupedRow {
        public String categoryValue;
        public String categoryLabel;
        public String seriesValue;
        public String seriesLabel;
        /** Small multiples: the Panel field value and label of this row (null without a Panel field, or blank). */
        public String panelValue;
        public String panelLabel;
        public List<Decimal> values;
        public List<Partial> partials;
        /**
         * Rows whose `values` are computed (Formula measures): the queried Measures' partials they came from, so an
         * "Other" category or series can merge them (`Settings.otherValues`); null otherwise.
         */
        public List<Partial> otherInputs;

        /** For JSON deserialization of a cursor `state()`. */
        public GroupedRow() {
            this(null, null, null, null);
        }

        public GroupedRow(String categoryValue, String categoryLabel, String seriesValue, String seriesLabel) {
            this.categoryValue = categoryValue;
            this.categoryLabel = categoryLabel;
            this.seriesValue = seriesValue;
            this.seriesLabel = seriesLabel;
        }

        /** Final value of Measure `index` aggregated with `aggregateFunction` (null when no row had a value). */
        public Decimal value(Integer index, String aggregateFunction) {
            if (partials != null) {
                return partials[index].value(aggregateFunction);
            }
            return values == null || index >= values.size() ? null : values[index];
        }
    }

    /** Running `{ sum, count, min, max }` of one Measure in one grouped row; mergeable chunk by chunk. */
    public class Partial {
        @AuraEnabled
        public Decimal sum = 0;
        /** Number of non-null values. */
        @AuraEnabled
        public Integer count = 0;
        @AuraEnabled
        public Decimal min;
        @AuraEnabled
        public Decimal max;

        public void add(Object rawValue) {
            Decimal value = BoardQueryService.toDecimal(rawValue);
            if (value == null) {
                return;
            }
            sum += value;
            count++;
            min = (min == null || value < min) ? value : min;
            max = (max == null || value > max) ? value : max;
        }

        /** Adds another leg's running `{ sum, count, min, max }` of the same Measure and group. */
        public void combine(Partial other) {
            if (other == null) {
                return;
            }
            sum += other.sum == null ? 0 : other.sum;
            count += other.count == null ? 0 : other.count;
            min = (other.min != null && (min == null || other.min < min)) ? other.min : min;
            max = (other.max != null && (max == null || other.max > max)) ? other.max : max;
        }

        /** `COUNT` (rows added), `SUM`, `AVG`, `MIN` or `MAX`; null when no row had a value. */
        public Decimal value(String aggregateFunction) {
            if (aggregateFunction == 'COUNT') {
                return count;
            }
            if (count == 0) {
                return null;
            }
            // Average per record: the running partial holds one value per record.
            if (aggregateFunction == 'AVG' || aggregateFunction == BoardAveragePerRecord.AGGREGATE_FUNCTION) {
                return sum.divide(count, 10);
            }
            if (aggregateFunction == 'MIN') {
                return min;
            }
            return aggregateFunction == 'MAX' ? max : sum;
        }
    }

    /**
     * Grouped rows of one Chart query, keyed by category / series value. SOQL rows are `put` with final values; cursor
     * rows are `add`ed one record at a time. `state()` / `restore()` carry the running partials from one cursor chunk
     * call to the next.
     */
    public class Accumulator {
        public List<GroupedRow> rows = new List<GroupedRow>();
        private Map<String, GroupedRow> index = new Map<String, GroupedRow>();
        private Integer measureCount;

        public Accumulator(Integer measureCount) {
            this.measureCount = measureCount;
        }

        /** A grouped row with its final value per Measure (SOQL `GROUP BY` tier). */
        public void put(
            String categoryValue,
            String categoryLabel,
            String seriesValue,
            String seriesLabel,
            List<Object> measureValues
        ) {
            put(null, null, categoryValue, categoryLabel, seriesValue, seriesLabel, measureValues);
        }

        /** `put` in the Panel of `panelValue` (Small multiples). */
        public void put(
            String panelValue,
            String panelLabel,
            String categoryValue,
            String categoryLabel,
            String seriesValue,
            String seriesLabel,
            List<Object> measureValues
        ) {
            GroupedRow row = new GroupedRow(categoryValue, categoryLabel, seriesValue, seriesLabel);
            row.panelValue = panelValue;
            row.panelLabel = panelLabel;
            row.values = new List<Decimal>();
            for (Object value : measureValues) {
                row.values.add(BoardQueryService.toDecimal(value));
            }
            rows.add(row);
            index.put(rowKey(panelValue, categoryValue, seriesValue), row);
        }

        /**
         * One record's value per Measure (cursor tier). Pass `1` for a `COUNT` Measure: every non-null value counts.
         */
        public void add(
            String categoryValue,
            String categoryLabel,
            String seriesValue,
            String seriesLabel,
            List<Object> recordValues
        ) {
            add(null, null, categoryValue, categoryLabel, seriesValue, seriesLabel, recordValues);
        }

        /** `add` in the Panel of `panelValue` (Small multiples). */
        public void add(
            String panelValue,
            String panelLabel,
            String categoryValue,
            String categoryLabel,
            String seriesValue,
            String seriesLabel,
            List<Object> recordValues
        ) {
            String key = rowKey(panelValue, categoryValue, seriesValue);
            GroupedRow row = index.get(key);
            if (row == null) {
                row = new GroupedRow(categoryValue, categoryLabel, seriesValue, seriesLabel);
                row.panelValue = panelValue;
                row.panelLabel = panelLabel;
                row.partials = new List<Partial>();
                for (Integer i = 0; i < measureCount; i++) {
                    row.partials.add(new Partial());
                }
                rows.add(row);
                index.put(key, row);
            }
            for (Integer i = 0; i < measureCount; i++) {
                row.partials[i].add(recordValues[i]);
            }
        }

        /**
         * One group's partial per Measure from another leg (a Data provider's buckets, the provider standard leg),
         * merged into that group's running row; a new group keeps the labels given here.
         */
        public void addPartials(
            String categoryValue,
            String categoryLabel,
            String seriesValue,
            String seriesLabel,
            List<Partial> legPartials
        ) {
            addPartials(null, null, categoryValue, categoryLabel, seriesValue, seriesLabel, legPartials);
        }

        /** `addPartials` in the Panel of `panelValue` (Small multiples). */
        public void addPartials(
            String panelValue,
            String panelLabel,
            String categoryValue,
            String categoryLabel,
            String seriesValue,
            String seriesLabel,
            List<Partial> legPartials
        ) {
            String key = rowKey(panelValue, categoryValue, seriesValue);
            GroupedRow row = index.get(key);
            if (row == null) {
                row = new GroupedRow(categoryValue, categoryLabel, seriesValue, seriesLabel);
                row.panelValue = panelValue;
                row.panelLabel = panelLabel;
                row.partials = new List<Partial>();
                for (Integer i = 0; i < measureCount; i++) {
                    row.partials.add(new Partial());
                }
                rows.add(row);
                index.put(key, row);
            }
            for (Integer i = 0; i < measureCount; i++) {
                row.partials[i].combine(legPartials[i]);
            }
        }

        /** Serialized running rows, handed back by the caller with the next cursor chunk call. */
        public String state() {
            return JSON.serialize(rows);
        }

        /** Re-loads the rows of a previous `state()`; a malformed state fails as a retryable cursor error. */
        public Accumulator restore(String state) {
            if (String.isBlank(state)) {
                return this;
            }
            List<GroupedRow> restored;
            try {
                restored = (List<GroupedRow>) JSON.deserialize(state, List<GroupedRow>.class);
            } catch (Exception malformed) {
                throw BoardErrors.error(
                    BoardErrors.QUERY_ERROR,
                    'The chart calculation can no longer continue. Retry to recalculate.',
                    null,
                    null,
                    true
                );
            }
            for (GroupedRow row : restored) {
                rows.add(row);
                index.put(rowKey(row.panelValue, row.categoryValue, row.seriesValue), row);
            }
            return this;
        }
    }

    private static String rowKey(String panelValue, String categoryValue, String seriesValue) {
        return JSON.serialize(new List<String>{ panelValue, categoryValue, seriesValue });
    }

    // ---------------------------------------------------------------------------------------------------------
    // Shaping: sort, max categories + Other, series cap
    // ---------------------------------------------------------------------------------------------------------

    /** How a Chart widget turns grouped rows into categories and series. */
    public class Settings {
        /** One aggregate function per Measure, in Measure order. */
        public List<String> aggregateFunctions = new List<String>();
        public Boolean hasSeries = false;
        /** `VALUE_DESC` (default), `VALUE_ASC`, `LABEL_*`, `PICKLIST_ORDER`, `CHRONOLOGICAL_*`. */
        public String sortBy;
        /** A date axis defaults to `CHRONOLOGICAL_ASC` instead of `VALUE_DESC`. */
        public Boolean isDateAxis = false;
        public Integer maxCategories = 10;
        /**
         * `OTHER` rolls the categories beyond the maximum into "Other" (summed for COUNT/SUM; merged from partials for
         * other Measures, never for COUNT_DISTINCT); else truncate.
         */
        public String overflowMode = 'TRUNCATE';
        public Integer maxSeries = 6;
        public Boolean includeBlank = true;
        /** Category field picklist API values in describe order, for `PICKLIST_ORDER`. */
        public List<String> picklistOrder = new List<String>();
        /** Share of total per Measure, in Measure order (`SHOW_AS_*`; null or missing = plain value). */
        public List<String> showAs = new List<String>();
        /**
         * Grand total per Measure from an ungrouped query, when the grouped rows are incomplete (capped `GROUP BY`);
         * null = summed from the rows.
         */
        public List<Decimal> grandTotals;

        /**
         * Final values per Measure of an "Other" category or series from its rows' merged partials; null = each
         * Measure's partial read with its aggregate function (a Widget without Formula measures).
         */
        public OtherValues otherValues;

        /** True when every Measure's values add up, so "Other" can be summed. */
        public Boolean canRollUp() {
            for (String aggregateFunction : aggregateFunctions) {
                if (!ROLLUP_FUNCTIONS.contains(aggregateFunction)) {
                    return false;
                }
            }
            return true;
        }

        public String effectiveSort() {
            String requested = sortBy == null ? null : sortBy.trim().toUpperCase();
            if (SORTS.contains(requested)) {
                return requested;
            }
            return isDateAxis ? 'CHRONOLOGICAL_ASC' : 'VALUE_DESC';
        }
    }

    /** Final values per Measure of an "Other" category or series, from the merged partials of the rows it rolls up. */
    public interface OtherValues {
        List<Decimal> valuesOf(List<Partial> merged);
    }

    /** `OtherValues` of a Widget without Formula measures: each merged partial read with its Measure's aggregate. */
    private class PartialValues implements OtherValues {
        private List<String> aggregateFunctions;

        PartialValues(List<String> aggregateFunctions) {
            this.aggregateFunctions = aggregateFunctions;
        }

        public List<Decimal> valuesOf(List<Partial> merged) {
            List<Decimal> values = new List<Decimal>();
            for (Integer i = 0; i < aggregateFunctions.size(); i++) {
                values.add(i < merged.size() ? merged[i].value(aggregateFunctions[i]) : null);
            }
            return values;
        }
    }

    /** The partials an "Other" can merge for `row`: its running partials, or the inputs of its computed values. */
    private static List<Partial> otherInputsOf(GroupedRow row) {
        return row.partials != null ? row.partials : row.otherInputs;
    }

    /**
     * True when "Other" can be computed for Measures that don't add up (AVG, MIN, MAX, Average per record, Formula):
     * every row carries mergeable partials, and no Measure is COUNT_DISTINCT (distinct counts never merge).
     */
    private static Boolean canMergeOther(Settings settings, List<GroupedRow> rows) {
        if (settings.aggregateFunctions.contains('COUNT_DISTINCT')) {
            return false;
        }
        for (GroupedRow row : rows) {
            if (otherInputsOf(row) == null) {
                return false;
            }
        }
        return true;
    }

    /** One category or series of the shaped chart. `colourKey` is the stored value, `__other__` or `__blank__`. */
    public class ChartKey {
        @AuraEnabled
        public String key;
        /** Stored value (picklist API value, record Id, date bucket key); null for "Other" and "(Blank)". */
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String colourKey;
        @AuraEnabled
        public Boolean isOther = false;
        @AuraEnabled
        public Boolean isBlank = false;
    }

    /** One value of the shaped chart: Measure `measureIndex` at a (category, series) key. */
    public class ChartPoint {
        @AuraEnabled
        public Integer measureIndex;
        @AuraEnabled
        public String categoryKey;
        @AuraEnabled
        public String seriesKey;
        /** Series value colour key with a series field; `measure:<index>` without. */
        @AuraEnabled
        public String colourKey;
        @AuraEnabled
        public Decimal value;
        /** Small multiples: the key of the Panel this value is drawn in; null without a Panel field. */
        @AuraEnabled
        public String panelKey;
    }

    /** The shaped chart: ordered categories and series, their values, and what was cut. */
    public class ChartShape {
        @AuraEnabled
        public List<ChartKey> categories = new List<ChartKey>();
        @AuraEnabled
        public List<ChartKey> series = new List<ChartKey>();
        @AuraEnabled
        public List<ChartPoint> points = new List<ChartPoint>();
        /** True when categories beyond max categories were hidden or rolled into "Other". */
        @AuraEnabled
        public Boolean truncatedCategories = false;
        /** Number of categories hidden or rolled into "Other". */
        @AuraEnabled
        public Integer hiddenCategories = 0;
        /** True when series beyond max series were hidden or rolled into "Other". */
        @AuraEnabled
        public Boolean truncatedSeries = false;
    }

    /** Sorts, caps and rolls up grouped rows into the chart the Widget draws. */
    public static ChartShape shape(Settings settings, List<GroupedRow> rows) {
        Integer measureCount = settings.aggregateFunctions.size();
        ShareOfTotal share = new ShareOfTotal(settings);
        Map<String, Bucket> categories = new Map<String, Bucket>();
        Map<String, Bucket> seriesByKey = new Map<String, Bucket>();
        for (GroupedRow row : rows) {
            if (row.categoryValue == null && !settings.includeBlank) {
                continue;
            }
            Bucket category = categories.get(keyOf(row.categoryValue));
            if (category == null) {
                category = new Bucket(row.categoryValue, row.categoryLabel);
                categories.put(category.key, category);
            }
            String seriesKey = VALUE_KEY;
            if (settings.hasSeries) {
                Bucket seriesBucket = seriesByKey.get(keyOf(row.seriesValue));
                if (seriesBucket == null) {
                    seriesBucket = new Bucket(row.seriesValue, row.seriesLabel);
                    seriesByKey.put(seriesBucket.key, seriesBucket);
                }
                seriesKey = seriesBucket.key;
            }
            List<Decimal> values = new List<Decimal>();
            for (Integer i = 0; i < measureCount; i++) {
                values.add(row.value(i, settings.aggregateFunctions[i]));
            }
            category.cells.put(seriesKey, values);
            if (otherInputsOf(row) != null) {
                category.addPartials(seriesKey, otherInputsOf(row));
            }
            share.addToGrandTotals(values);
            Decimal primary = 0;
            if (!values.isEmpty() && values[0] != null) {
                primary = values[0];
            }
            category.total += primary;
            if (settings.hasSeries) {
                seriesByKey.get(seriesKey).total += primary;
            }
        }

        ChartShape shape = new ChartShape();
        Boolean canRollUp = settings.canRollUp();
        // Measures that don't add up: "Other" merges the rows' partials and computes its values from them.
        Boolean mergeOther = !canRollUp && canMergeOther(settings, rows);
        OtherValues otherValues = settings.otherValues != null
            ? settings.otherValues
            : new PartialValues(settings.aggregateFunctions);

        List<Bucket> sorted = categories.values();
        sorted.sort(new CategoryOrder(settings.effectiveSort(), settings.picklistOrder));
        Integer maxCategories = Math.max(1, settings.maxCategories == null ? 10 : settings.maxCategories);
        if (sorted.size() > maxCategories) {
            shape.truncatedCategories = true;
            // A date axis always truncates: "Other" would be a meaningless point on a timeline.
            Boolean useOther = settings.overflowMode == 'OTHER' && (canRollUp || mergeOther) && !settings.isDateAxis;
            Integer kept = useOther ? maxCategories - 1 : maxCategories;
            shape.hiddenCategories = sorted.size() - kept;
            List<Bucket> visible = new List<Bucket>();
            Bucket other = otherBucket();
            for (Integer i = 0; i < sorted.size(); i++) {
                if (i < kept) {
                    visible.add(sorted[i]);
                } else if (useOther && canRollUp) {
                    for (String seriesKey : sorted[i].cells.keySet()) {
                        other.addCell(seriesKey, sorted[i].cells.get(seriesKey));
                    }
                } else if (useOther) {
                    for (String seriesKey : sorted[i].partialCells.keySet()) {
                        other.addPartials(seriesKey, sorted[i].partialCells.get(seriesKey));
                    }
                }
            }
            if (useOther) {
                if (!canRollUp) {
                    for (String seriesKey : other.partialCells.keySet()) {
                        other.cells.put(seriesKey, otherValues.valuesOf(other.partialCells.get(seriesKey)));
                    }
                }
                visible.add(other);
            }
            sorted = visible;
        }

        // Category totals before the series cap adds "Other" series cells next to the rolled-up ones.
        for (Bucket category : sorted) {
            share.addCategory(category.key, category.cells.values());
        }

        List<Bucket> series = new List<Bucket>();
        if (settings.hasSeries) {
            series = seriesByKey.values();
            series.sort(new CategoryOrder('VALUE_DESC', null));
            Integer maxSeries = Math.max(1, settings.maxSeries == null ? 6 : settings.maxSeries);
            if (series.size() > maxSeries) {
                shape.truncatedSeries = true;
                Integer kept = canRollUp || mergeOther ? maxSeries - 1 : maxSeries;
                Set<String> rolled = new Set<String>();
                for (Integer i = kept; i < series.size(); i++) {
                    rolled.add(series[i].key);
                }
                List<Bucket> visibleSeries = new List<Bucket>();
                for (Integer i = 0; i < kept; i++) {
                    visibleSeries.add(series[i]);
                }
                if (canRollUp) {
                    for (Bucket category : sorted) {
                        for (String seriesKey : rolled) {
                            if (category.cells.containsKey(seriesKey)) {
                                category.addCell(OTHER_KEY, category.cells.get(seriesKey));
                            }
                        }
                    }
                    visibleSeries.add(otherBucket());
                } else if (mergeOther) {
                    for (Bucket category : sorted) {
                        for (String seriesKey : rolled) {
                            if (category.partialCells.containsKey(seriesKey)) {
                                category.addPartials(OTHER_KEY, category.partialCells.get(seriesKey));
                            }
                        }
                        if (category.partialCells.containsKey(OTHER_KEY)) {
                            category.cells.put(OTHER_KEY, otherValues.valuesOf(category.partialCells.get(OTHER_KEY)));
                        }
                    }
                    visibleSeries.add(otherBucket());
                }
                series = visibleSeries;
            }
        } else {
            Bucket single = new Bucket(VALUE_KEY, null);
            single.value = null;
            single.label = null;
            series.add(single);
        }

        for (Bucket category : sorted) {
            shape.categories.add(category.toKey());
        }
        for (Bucket entry : series) {
            ChartKey key = entry.toKey();
            if (!settings.hasSeries) {
                key.colourKey = null;
            }
            shape.series.add(key);
        }
        for (Bucket category : sorted) {
            for (Bucket entry : series) {
                List<Decimal> values = category.cells.get(entry.key);
                if (values == null) {
                    continue;
                }
                for (Integer i = 0; i < measureCount; i++) {
                    ChartPoint point = new ChartPoint();
                    point.measureIndex = i;
                    point.categoryKey = category.key;
                    point.seriesKey = entry.key;
                    point.colourKey = settings.hasSeries ? entry.key : MEASURE_COLOUR_PREFIX + i;
                    point.value = share.apply(i, category.key, values[i]);
                    shape.points.add(point);
                }
            }
        }
        return shape;
    }

    /**
     * Share of total maths: turns a Measure's plain value into a fraction (0.25 = 25%) of its grand total
     * (`percentOfTotal`) or of its category's total (`percentOfCategory`). Denominators come from every grouped row,
     * before max categories (+ "Other") or the series cap cut any of them (or from `Settings.grandTotals`). A category's
     * total sums every series of it and every Measure shown as `percentOfCategory`. Blank value or zero total: blank.
     */
    public class ShareOfTotal {
        private List<String> showAs = new List<String>();
        private List<Decimal> grandTotals = new List<Decimal>();
        private Boolean hasGivenGrandTotals;
        private Map<String, Decimal> categoryTotals = new Map<String, Decimal>();

        public ShareOfTotal(Settings settings) {
            Integer measureCount = settings.aggregateFunctions.size();
            hasGivenGrandTotals = settings.grandTotals != null;
            for (Integer i = 0; i < measureCount; i++) {
                showAs.add(
                    settings.showAs != null &&
                        i < settings.showAs.size() &&
                        settings.showAs[i] != null
                        ? settings.showAs[i]
                        : SHOW_AS_VALUE
                );
                Decimal total = 0;
                if (hasGivenGrandTotals) {
                    total = i < settings.grandTotals.size() ? settings.grandTotals[i] : null;
                }
                grandTotals.add(total);
            }
        }

        /** Adds one grouped cell (one value per Measure) to the grand totals, unless they were given. */
        public void addToGrandTotals(List<Decimal> values) {
            if (hasGivenGrandTotals) {
                return;
            }
            for (Integer i = 0; i < grandTotals.size(); i++) {
                if (values[i] != null) {
                    grandTotals[i] += values[i];
                }
            }
        }

        /** Sets the total of category `categoryKey` from its cells (one value list per series). */
        public void addCategory(String categoryKey, List<List<Decimal>> cells) {
            Decimal total = 0;
            for (List<Decimal> values : cells) {
                for (Integer i = 0; i < showAs.size(); i++) {
                    if (showAs[i] == SHOW_AS_PERCENT_OF_CATEGORY && values[i] != null) {
                        total += values[i];
                    }
                }
            }
            categoryTotals.put(categoryKey, total);
        }

        /** Measure `measureIndex`'s value at category `categoryKey`, as its Share of total. */
        public Decimal apply(Integer measureIndex, String categoryKey, Decimal value) {
            String mode = showAs[measureIndex];
            if (mode == SHOW_AS_PERCENT_OF_TOTAL) {
                return fraction(value, grandTotals[measureIndex]);
            }
            if (mode == SHOW_AS_PERCENT_OF_CATEGORY) {
                return fraction(value, categoryTotals.get(categoryKey));
            }
            return value;
        }

        private Decimal fraction(Decimal value, Decimal total) {
            if (value == null || total == null || total == 0) {
                return null;
            }
            return value.divide(total, 10);
        }
    }

    /**
     * Overall value per Measure over every grouped row, before max categories (+ "Other") or the series cap cut any (a
     * Reference line's value). Cursor partials merge exactly for every aggregate; final SOQL values merge for
     * COUNT/SUM (summed), MIN and MAX, but not AVG or COUNT_DISTINCT (null: the caller runs an ungrouped query).
     * Without `includeBlank` the "(Blank)" category's rows stay out, as in the chart.
     */
    public static List<Decimal> overallValues(
        List<String> aggregateFunctions,
        List<GroupedRow> rows,
        Boolean includeBlank
    ) {
        List<Decimal> overall = new List<Decimal>();
        for (Integer i = 0; i < aggregateFunctions.size(); i++) {
            String aggregateFunction = aggregateFunctions[i];
            Partial merged = new Partial();
            Decimal folded;
            Boolean mergeable = true;
            for (GroupedRow row : rows) {
                if (row.categoryValue == null && !includeBlank) {
                    continue;
                }
                if (row.partials != null) {
                    merged.combine(row.partials[i]);
                    continue;
                }
                Decimal value = row.value(i, aggregateFunction);
                mergeable =
                    mergeable &&
                    aggregateFunction != 'AVG' &&
                    aggregateFunction != BoardAveragePerRecord.AGGREGATE_FUNCTION &&
                    aggregateFunction != 'COUNT_DISTINCT';
                if (value == null) {
                    continue;
                }
                if (folded == null) {
                    folded = value;
                } else if (aggregateFunction == 'MIN') {
                    folded = Math.min(folded, value);
                } else if (aggregateFunction == 'MAX') {
                    folded = Math.max(folded, value);
                } else {
                    folded += value;
                }
            }
            if (!mergeable) {
                overall.add(null);
            } else if (folded != null) {
                overall.add(folded);
            } else {
                overall.add(merged.value(aggregateFunction));
            }
        }
        return overall;
    }

    private static Bucket otherBucket() {
        Bucket other = new Bucket(OTHER_KEY, OTHER_LABEL);
        other.isOther = true;
        return other;
    }

    private static String keyOf(String value) {
        return value == null ? BLANK_KEY : value;
    }

    /** A category or series while shaping: its values per series key (one per Measure) and its sort total. */
    private class Bucket {
        String key;
        String value;
        String label;
        Boolean isBlank;
        Boolean isOther = false;
        Decimal total = 0;
        Map<String, List<Decimal>> cells = new Map<String, List<Decimal>>();
        /** Merged partials per series key, when the rows carry them (see `canMergeOther`). */
        Map<String, List<Partial>> partialCells = new Map<String, List<Partial>>();

        Bucket(String value, String label) {
            this.value = value;
            this.key = keyOf(value);
            this.isBlank = value == null;
            this.label = value == null ? BLANK_LABEL : (label == null ? value : label);
        }

        /** Adds `values` into the cell at `seriesKey` (null + null stays null). */
        void addCell(String seriesKey, List<Decimal> values) {
            List<Decimal> current = cells.get(seriesKey);
            if (current == null) {
                cells.put(seriesKey, new List<Decimal>(values));
                return;
            }
            for (Integer i = 0; i < values.size(); i++) {
                if (values[i] != null) {
                    current[i] = current[i] == null ? values[i] : current[i] + values[i];
                }
            }
        }

        /** Merges `partials` into the partial cell at `seriesKey` (copies: the rows' partials are never changed). */
        void addPartials(String seriesKey, List<Partial> partials) {
            List<Partial> current = partialCells.get(seriesKey);
            if (current == null) {
                current = new List<Partial>();
                for (Integer i = 0; i < partials.size(); i++) {
                    current.add(new Partial());
                }
                partialCells.put(seriesKey, current);
            }
            for (Integer i = 0; i < partials.size() && i < current.size(); i++) {
                current[i].combine(partials[i]);
            }
        }

        ChartKey toKey() {
            ChartKey chartKey = new ChartKey();
            chartKey.key = key;
            chartKey.value = isOther || isBlank ? null : value;
            chartKey.label = label;
            chartKey.colourKey = key;
            chartKey.isOther = isOther;
            chartKey.isBlank = isBlank;
            return chartKey;
        }
    }

    /** Category order of a sort option; "(Blank)" sorts last for label, picklist and chronological orders. */
    private class CategoryOrder implements System.Comparator<Bucket> {
        String sortBy;
        Map<String, Integer> positions = new Map<String, Integer>();

        CategoryOrder(String sortBy, List<String> picklistOrder) {
            this.sortBy = sortBy;
            if (picklistOrder != null) {
                for (Integer i = 0; i < picklistOrder.size(); i++) {
                    positions.put(picklistOrder[i], i);
                }
            }
        }

        public Integer compare(Bucket a, Bucket b) {
            if (sortBy == 'VALUE_DESC') {
                Integer byValue = compareDecimals(b.total, a.total);
                return byValue != 0 ? byValue : compareLabels(a, b);
            }
            if (sortBy == 'VALUE_ASC') {
                Integer byValue = compareDecimals(a.total, b.total);
                return byValue != 0 ? byValue : compareLabels(a, b);
            }
            if (a.isBlank != b.isBlank) {
                return a.isBlank ? 1 : -1;
            }
            switch on sortBy {
                when 'LABEL_DESC' {
                    return compareLabels(b, a);
                }
                when 'PICKLIST_ORDER' {
                    Integer byPosition = compareDecimals(position(a), position(b));
                    return byPosition != 0 ? byPosition : compareLabels(a, b);
                }
                when 'CHRONOLOGICAL_ASC' {
                    return compareKeys(a.value, b.value);
                }
                when 'CHRONOLOGICAL_DESC' {
                    return compareKeys(b.value, a.value);
                }
                when else {
                    return compareLabels(a, b);
                }
            }
        }

        Decimal position(Bucket bucket) {
            Integer found = bucket.value == null ? null : positions.get(bucket.value);
            return found == null ? 2147483647 : found;
        }
    }

    private static Integer compareDecimals(Decimal a, Decimal b) {
        if (a == b) {
            return 0;
        }
        return a < b ? -1 : 1;
    }

    private static Integer compareLabels(Bucket a, Bucket b) {
        Integer byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
        return byLabel != 0 ? byLabel : a.key.compareTo(b.key);
    }

    /** Numeric keys compare as numbers, everything else (`2026-03`, `FY2026-Q1`) as text. */
    private static Integer compareKeys(String a, String b) {
        if (a == null || b == null) {
            return a == b ? 0 : (a == null ? 1 : -1);
        }
        if (a.isNumeric() && b.isNumeric()) {
            return compareDecimals(Decimal.valueOf(a), Decimal.valueOf(b));
        }
        return a.compareTo(b);
    }
}