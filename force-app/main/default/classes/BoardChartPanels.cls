/**
 * Small multiples shaping, pure and in memory (no SOQL, no describes): turns grouped rows that carry a Panel field
 * value (`BoardChartEngine.GroupedRow.panelValue`) into one Panel per value.
 *
 * Panels: one per Panel field value with rows; no "Other" panel; a "(Blank)" panel only with include blank; sorted by
 * the Panel field's order (picklist order, else chronological for a date, else label) or a Measure's total; capped
 * at max panels, the rest cut (`cutPanels`). Categories and series are chosen once across the kept panels with
 * `BoardChartEngine.shape` (sort, max categories + "Other", series cap), so every Panel shows the same categories in the same
 * order and a value keeps its colour key in every Panel. Each Panel's points then come from its own rows only;
 * a Share of total is a share of the Panel total.
 */
public with sharing class BoardChartPanels {
    public static final Integer DEFAULT_MAX_PANELS = 6;
    /** Panel order: the Panel field's order (default), or a Measure's total high to low / low to high. */
    public static final String SORT_FIELD_ORDER = 'FIELD_ORDER';
    public static final String SORT_VALUE_DESC = 'VALUE_DESC';
    public static final String SORT_VALUE_ASC = 'VALUE_ASC';

    /** How the Panels are chosen and ordered. */
    public class Settings {
        public Integer maxPanels = DEFAULT_MAX_PANELS;
        /** `FIELD_ORDER` (default), `VALUE_DESC` or `VALUE_ASC`. */
        public String panelSort;
        /** The Measure whose Panel total `VALUE_*` sorts by. */
        public Integer panelSortMeasure = 0;
        /** Panel field picklist API values in describe order. */
        public List<String> picklistOrder = new List<String>();
        /** A date Panel field orders chronologically. */
        public Boolean isDatePanel = false;
    }

    /** The shaped Small multiples: Panels, the categories and series every Panel shares, and each Panel's points. */
    public class PanelShape {
        public List<BoardChartEngine.ChartKey> panels = new List<BoardChartEngine.ChartKey>();
        public List<BoardChartEngine.ChartKey> categories = new List<BoardChartEngine.ChartKey>();
        public List<BoardChartEngine.ChartKey> series = new List<BoardChartEngine.ChartKey>();
        /** Every Panel's points, each with its `panelKey`. */
        public List<BoardChartEngine.ChartPoint> points = new List<BoardChartEngine.ChartPoint>();
        public Boolean truncatedCategories = false;
        public Integer hiddenCategories = 0;
        public Boolean truncatedSeries = false;
        /** True when Panels beyond max panels were cut. */
        public Boolean cutPanels = false;
        public Integer hiddenPanels = 0;
    }

    public static PanelShape shape(
        BoardChartEngine.Settings chart,
        Settings panelSettings,
        List<BoardChartEngine.GroupedRow> rows
    ) {
        Integer measureCount = chart.aggregateFunctions.size();
        Map<String, Panel> panelsByKey = new Map<String, Panel>();
        for (BoardChartEngine.GroupedRow row : rows) {
            if ((row.categoryValue == null || row.panelValue == null) && !chart.includeBlank) {
                continue;
            }
            String key = keyOf(row.panelValue);
            Panel panel = panelsByKey.get(key);
            if (panel == null) {
                panel = new Panel(row.panelValue, row.panelLabel, measureCount);
                panelsByKey.put(key, panel);
            }
            panel.add(row, chart.aggregateFunctions);
        }

        PanelShape shape = new PanelShape();
        List<Panel> panels = panelsByKey.values();
        panels.sort(new PanelOrder(panelSettings));
        Integer maxPanels = Math.max(1, panelSettings.maxPanels == null ? DEFAULT_MAX_PANELS : panelSettings.maxPanels);
        if (panels.size() > maxPanels) {
            shape.cutPanels = true;
            shape.hiddenPanels = panels.size() - maxPanels;
            List<Panel> kept = new List<Panel>();
            for (Integer i = 0; i < maxPanels; i++) {
                kept.add(panels[i]);
            }
            panels = kept;
        }

        // Categories and series across every kept Panel (values summed per category / series to rank them).
        BoardChartEngine.ChartShape shared = BoardChartEngine.shape(chart, mergeAcrossPanels(panels, chart));
        shape.categories = shared.categories;
        shape.series = shared.series;
        shape.truncatedCategories = shared.truncatedCategories;
        shape.hiddenCategories = shared.hiddenCategories;
        shape.truncatedSeries = shared.truncatedSeries;
        SharedAxes layout = new SharedAxes(shared, chart.hasSeries);

        for (Panel panel : panels) {
            shape.panels.add(panel.toKey());
            shape.points.addAll(panelPoints(panel, chart, layout));
        }
        return shape;
    }

    /** One Panel's points over the shared categories and series; unknown keys go to "Other" or are dropped. */
    private static List<BoardChartEngine.ChartPoint> panelPoints(
        Panel panel,
        BoardChartEngine.Settings chart,
        SharedAxes layout
    ) {
        Integer measureCount = chart.aggregateFunctions.size();
        // A Share of total of a Panel is a share of the Panel total.
        BoardChartEngine.Settings panelChart = new BoardChartEngine.Settings();
        panelChart.aggregateFunctions = chart.aggregateFunctions;
        panelChart.showAs = chart.showAs;
        BoardChartEngine.ShareOfTotal share = new BoardChartEngine.ShareOfTotal(panelChart);
        Map<String, Map<String, List<Decimal>>> cells = new Map<String, Map<String, List<Decimal>>>();
        Map<String, List<List<Decimal>>> categoryCells = new Map<String, List<List<Decimal>>>();
        for (Integer r = 0; r < panel.rows.size(); r++) {
            BoardChartEngine.GroupedRow row = panel.rows[r];
            List<Decimal> values = panel.values[r];
            share.addToGrandTotals(values);
            String categoryKey = layout.categoryFor(row.categoryValue);
            if (categoryKey == null) {
                continue;
            }
            if (!categoryCells.containsKey(categoryKey)) {
                categoryCells.put(categoryKey, new List<List<Decimal>>());
                cells.put(categoryKey, new Map<String, List<Decimal>>());
            }
            categoryCells.get(categoryKey).add(values);
            String seriesKey = layout.seriesFor(row.seriesValue);
            if (seriesKey != null) {
                addCell(cells.get(categoryKey), seriesKey, values);
            }
        }
        for (String categoryKey : categoryCells.keySet()) {
            share.addCategory(categoryKey, categoryCells.get(categoryKey));
        }

        List<BoardChartEngine.ChartPoint> points = new List<BoardChartEngine.ChartPoint>();
        for (String categoryKey : layout.categoryOrder) {
            Map<String, List<Decimal>> bySeries = cells.get(categoryKey);
            if (bySeries == null) {
                continue;
            }
            for (String seriesKey : layout.seriesOrder) {
                List<Decimal> values = bySeries.get(seriesKey);
                if (values == null) {
                    continue;
                }
                for (Integer i = 0; i < measureCount; i++) {
                    BoardChartEngine.ChartPoint point = new BoardChartEngine.ChartPoint();
                    point.panelKey = panel.key;
                    point.measureIndex = i;
                    point.categoryKey = categoryKey;
                    point.seriesKey = seriesKey;
                    point.colourKey = chart.hasSeries ? seriesKey : BoardChartEngine.MEASURE_COLOUR_PREFIX + i;
                    point.value = share.apply(i, categoryKey, values[i]);
                    points.add(point);
                }
            }
        }
        return points;
    }

    /** The kept Panels' rows summed per category / series, to rank categories and series across every Panel. */
    private static List<BoardChartEngine.GroupedRow> mergeAcrossPanels(
        List<Panel> panels,
        BoardChartEngine.Settings chart
    ) {
        List<BoardChartEngine.GroupedRow> merged = new List<BoardChartEngine.GroupedRow>();
        Map<String, BoardChartEngine.GroupedRow> index = new Map<String, BoardChartEngine.GroupedRow>();
        for (Panel panel : panels) {
            for (Integer r = 0; r < panel.rows.size(); r++) {
                BoardChartEngine.GroupedRow row = panel.rows[r];
                String key = JSON.serialize(new List<String>{ row.categoryValue, row.seriesValue });
                BoardChartEngine.GroupedRow target = index.get(key);
                if (target == null) {
                    target = new BoardChartEngine.GroupedRow(
                        row.categoryValue,
                        row.categoryLabel,
                        row.seriesValue,
                        row.seriesLabel
                    );
                    target.values = new List<Decimal>(panel.values[r]);
                    merged.add(target);
                    index.put(key, target);
                } else {
                    sumInto(target.values, panel.values[r]);
                }
            }
        }
        return merged;
    }

    private static void addCell(Map<String, List<Decimal>> bySeries, String seriesKey, List<Decimal> values) {
        List<Decimal> current = bySeries.get(seriesKey);
        if (current == null) {
            bySeries.put(seriesKey, new List<Decimal>(values));
        } else {
            sumInto(current, values);
        }
    }

    /** Adds `values` into `target` (null + null stays null). */
    private static void sumInto(List<Decimal> target, List<Decimal> values) {
        for (Integer i = 0; i < values.size(); i++) {
            if (values[i] != null) {
                target[i] = target[i] == null ? values[i] : target[i] + values[i];
            }
        }
    }

    private static String keyOf(String value) {
        return value == null ? BoardChartEngine.BLANK_KEY : value;
    }

    /** Where a Panel row's category and series land among the shared categories and series. */
    private class SharedAxes {
        List<String> categoryOrder = new List<String>();
        List<String> seriesOrder = new List<String>();
        Set<String> categoryKeys = new Set<String>();
        Set<String> seriesKeys = new Set<String>();
        Boolean hasSeries;

        SharedAxes(BoardChartEngine.ChartShape shared, Boolean hasSeries) {
            this.hasSeries = hasSeries == true;
            for (BoardChartEngine.ChartKey category : shared.categories) {
                categoryOrder.add(category.key);
                categoryKeys.add(category.key);
            }
            for (BoardChartEngine.ChartKey entry : shared.series) {
                seriesOrder.add(entry.key);
                seriesKeys.add(entry.key);
            }
        }

        /** The shared category key, "Other" when the category was rolled up, or null when it is not shown. */
        String categoryFor(String value) {
            String key = keyOf(value);
            if (categoryKeys.contains(key)) {
                return key;
            }
            // "(Blank)" left out by include blank is never rolled into "Other".
            if (value == null) {
                return null;
            }
            return categoryKeys.contains(BoardChartEngine.OTHER_KEY) ? BoardChartEngine.OTHER_KEY : null;
        }

        String seriesFor(String value) {
            if (!hasSeries) {
                return BoardChartEngine.VALUE_KEY;
            }
            String key = keyOf(value);
            if (seriesKeys.contains(key)) {
                return key;
            }
            return seriesKeys.contains(BoardChartEngine.OTHER_KEY) ? BoardChartEngine.OTHER_KEY : null;
        }
    }

    /** One Panel while shaping: its rows, their final values per Measure, and its total per Measure. */
    private class Panel {
        String key;
        String value;
        String label;
        Boolean isBlank;
        List<BoardChartEngine.GroupedRow> rows = new List<BoardChartEngine.GroupedRow>();
        List<List<Decimal>> values = new List<List<Decimal>>();
        List<Decimal> totals = new List<Decimal>();

        Panel(String value, String label, Integer measureCount) {
            this.value = value;
            this.key = keyOf(value);
            this.isBlank = value == null;
            this.label = value == null ? BoardChartEngine.BLANK_LABEL : (label == null ? value : label);
            for (Integer i = 0; i < measureCount; i++) {
                totals.add(0);
            }
        }

        void add(BoardChartEngine.GroupedRow row, List<String> aggregateFunctions) {
            List<Decimal> rowValues = new List<Decimal>();
            for (Integer i = 0; i < aggregateFunctions.size(); i++) {
                Decimal measureValue = row.value(i, aggregateFunctions[i]);
                rowValues.add(measureValue);
                if (measureValue != null) {
                    totals[i] += measureValue;
                }
            }
            rows.add(row);
            values.add(rowValues);
        }

        Decimal total(Integer measureIndex) {
            Integer index = measureIndex == null ||
                measureIndex < 0 ||
                measureIndex >= totals.size()
                ? 0
                : measureIndex;
            return totals.isEmpty() ? 0 : totals[index];
        }

        BoardChartEngine.ChartKey toKey() {
            BoardChartEngine.ChartKey chartKey = new BoardChartEngine.ChartKey();
            chartKey.key = key;
            chartKey.value = isBlank ? null : value;
            chartKey.label = label;
            chartKey.colourKey = key;
            chartKey.isBlank = isBlank;
            return chartKey;
        }
    }

    /** Panel order (see `Settings.panelSort`); "(Blank)" sorts last in the Panel field's order. */
    private class PanelOrder implements System.Comparator<Panel> {
        String panelSort;
        Integer measureIndex;
        Boolean isDatePanel;
        Map<String, Integer> positions = new Map<String, Integer>();

        PanelOrder(Settings settings) {
            String requested = settings.panelSort == null ? '' : settings.panelSort.trim().toUpperCase();
            panelSort = requested == SORT_VALUE_DESC || requested == SORT_VALUE_ASC ? requested : SORT_FIELD_ORDER;
            measureIndex = settings.panelSortMeasure;
            isDatePanel = settings.isDatePanel == true;
            if (settings.picklistOrder != null) {
                for (Integer i = 0; i < settings.picklistOrder.size(); i++) {
                    positions.put(settings.picklistOrder[i], i);
                }
            }
        }

        public Integer compare(Panel a, Panel b) {
            if (panelSort == SORT_VALUE_DESC || panelSort == SORT_VALUE_ASC) {
                Integer byValue = compareDecimals(a.total(measureIndex), b.total(measureIndex));
                if (panelSort == SORT_VALUE_DESC) {
                    byValue = -byValue;
                }
                return byValue != 0 ? byValue : compareLabels(a, b);
            }
            if (a.isBlank != b.isBlank) {
                return a.isBlank ? 1 : -1;
            }
            if (isDatePanel) {
                return compareKeys(a.value, b.value);
            }
            if (!positions.isEmpty()) {
                Integer byPosition = compareDecimals(position(a), position(b));
                if (byPosition != 0) {
                    return byPosition;
                }
            }
            return compareLabels(a, b);
        }

        Decimal position(Panel panel) {
            Integer found = panel.value == null ? null : positions.get(panel.value);
            return found == null ? 2147483647 : found;
        }
    }

    private static Integer compareDecimals(Decimal a, Decimal b) {
        if (a == b) {
            return 0;
        }
        return a < b ? -1 : 1;
    }

    private static Integer compareLabels(Panel a, Panel b) {
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