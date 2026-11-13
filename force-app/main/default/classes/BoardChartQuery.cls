/**
 * Chart widget query entry points.
 *
 * Request: `{ objectApiName, measures: [{ aggregateFunction, valueFieldApiName, showAs, perField, inner }] (1–6),
 * groupByField, dateGranularity, stackByField (series field; only with one Measure), includeNullBucket, sortBy, maxCategories,
 * overflowMode ('OTHER' | 'TRUNCATE'), maxSeries, filters[], baseFilters[], displayCurrency, refreshToken }`.
 * SUM/AVG/MIN/MAX of currency fields come back in `displayCurrency` (`currencyIsoCodes`, one per Measure). A Formula
 * measure (`{ aggregateFunction: 'FORMULA', formula }`) is not queried; `BoardFormulaMeasures` evaluates it per category.
 * An `AVG_PER` (Average per record) Measure averages one value per record of its `perField` lookup, each (`inner`) the
 * `SUM` of the record's rows or its value counted `ONCE` (see `BoardAveragePerRecord`).
 * A Cross-object measure (`sourceObject`, `categoryMapping`, `filterBindings`) is queried on its own object and
 * full-outer-joined onto the categories by `BoardCrossObjectMeasures` (`crossObjectNotices`: one per such Measure).
 *
 * `BoardQueryService.scanChart` groups the scope by category and series and aggregates every Measure per group, in one
 * SOQL `GROUP BY` or through the `Database.Cursor` tier; `BoardChartEngine` then sorts, applies max categories + "Other" and
 * the series cap. Each response is the shaped chart (`categories`, `series`, `points`) so the client never
 * re-aggregates. A cursor-tier response (`mode: 'CURSOR'`, `isComplete: false`) also carries `cursor`, `nextOffset`
 * and `partialState`; the client sends them back to `fetchChartChunk` until `isComplete`, and each chunk response is
 * the chart shaped from every row read so far.
 *
 * Share of total (`showAs`: `value` (default), `percentOfTotal`, `percentOfCategory`; COUNT and SUM Measures only)
 * returns that Measure's points as fractions (0.25 = 25%) of the full total, never converted to a currency.
 * `percentOfCategory` needs a series field or several Measures. When the grouped query was capped and dropped groups,
 * one extra ungrouped query gives the grand totals.
 *
 * Reference lines (a Measure's `render: 'referenceLine'`): `overallValues` (one per Measure, null unless it is drawn
 * as a Reference line) is that Measure's value over the whole scope, whatever max categories cut; the SOQL
 * tier runs one extra ungrouped query for it, the cursor tier merges it from the running partials.
 *
 * Small multiples (`panelField` + `panelDateGranularity`, `maxPanels` 2–12 default 6, `panelSort` `FIELD_ORDER` |
 * `VALUE_DESC` | `VALUE_ASC`, `panelSortMeasure`): the Panel field is one more `GROUP BY` of the same query (sharing
 * its group cap; a capped result re-runs through the cursor tier up to its row cap, so max categories, the series cap and the
 * Panel cut run on every group, else it comes back with `hasMoreGroups`), shaped by `BoardChartPanels`: `panels` in order, `cutPanels` / `hiddenPanels`, and every point
 * carries its `panelKey`. Max categories per Panel is 3–50. With a Panel headline (`panelHeadlineMeasure`, the index of a
 * hidden Measure) or a Reference line, `panelTotals` carries each Panel's total per Measure (`BoardChartPanelTotals`).
 */
public with sharing class BoardChartQuery {
    /** Max Measures in one Chart widget. */
    public static final Integer MAX_MEASURES = 6;
    private static final Integer DEFAULT_MAX_CATEGORIES = 10;
    private static final Integer MIN_MAX_CATEGORIES = 3;
    private static final Integer MAX_MAX_CATEGORIES = 200;
    private static final Integer MAX_PANEL_CATEGORIES = 50;
    private static final Integer MIN_MAX_PANELS = 2;
    private static final Integer MAX_MAX_PANELS = 12;
    private static final Integer DEFAULT_MAX_SERIES = 6;
    private static final Integer MIN_MAX_SERIES = 2;
    private static final Integer MAX_MAX_SERIES = 12;
    private static final Set<String> SHOW_AS_MODES = new Set<String>{
        BoardChartEngine.SHOW_AS_VALUE,
        BoardChartEngine.SHOW_AS_PERCENT_OF_TOTAL,
        BoardChartEngine.SHOW_AS_PERCENT_OF_CATEGORY
    };
    /** `render` of a Measure drawn as a Reference line. */
    public static final String REFERENCE_LINE_RENDER = 'referenceLine';
    private static final Set<String> SHAREABLE_FUNCTIONS = new Set<String>{ 'COUNT', 'SUM' };

    /** First call for a Chart widget: the shaped chart, or the first cursor chunk of it. */
    @AuraEnabled(cacheable=true)
    public static ChartResult queryChart(String requestJson) {
        try {
            Map<String, Object> request = BoardQueryService.parseRequest(requestJson);
            request.remove('cursor');
            List<String> showAs = parseShowAs(request);
            BoardCrossObjectMeasures.ChartPlan crossObject = BoardCrossObjectMeasures.forChart(request);
            BoardFormulaMeasures.ChartPlan formulas = BoardFormulaMeasures.forChart(request);
            crossObject.detach(request);
            if (BoardDataProviders.isNamed(request)) {
                return shape(request, showAs, BoardDataProviders.scanChart(request), formulas, crossObject);
            }
            return shape(request, showAs, BoardQueryService.scanChart(request), formulas, crossObject);
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    /**
     * Next cursor chunk of a Chart widget: the original request plus `{ cursor, offset, partialState }` from the
     * previous response.
     */
    @AuraEnabled(cacheable=true)
    public static ChartResult fetchChartChunk(String requestJson) {
        try {
            Map<String, Object> request = BoardQueryService.parseRequest(requestJson);
            if (request.get('cursor') == null) {
                throw BoardErrors.error(
                    BoardErrors.QUERY_ERROR,
                    'The chart calculation can no longer continue. Retry to recalculate.',
                    null,
                    null,
                    true
                );
            }
            List<String> showAs = parseShowAs(request);
            BoardCrossObjectMeasures.ChartPlan crossObject = BoardCrossObjectMeasures.forChart(request);
            BoardFormulaMeasures.ChartPlan formulas = BoardFormulaMeasures.forChart(request);
            crossObject.detach(request);
            return shape(request, showAs, BoardQueryService.scanChart(request), formulas, crossObject);
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    /** True when any Measure of the request is shown as a Share of total. */
    public static Boolean usesShareOfTotal(Map<String, Object> request) {
        for (String mode : parseShowAs(request)) {
            if (mode != BoardChartEngine.SHOW_AS_VALUE) {
                return true;
            }
        }
        return false;
    }

    /** The request's max categories (3-200, default 10). */
    public static Integer maxCategories(Map<String, Object> request) {
        return clamp(request.get('maxCategories'), MIN_MAX_CATEGORIES, MAX_MAX_CATEGORIES, DEFAULT_MAX_CATEGORIES);
    }

    /** The request's max series (2-12, default 6). */
    public static Integer maxSeries(Map<String, Object> request) {
        return clamp(request.get('maxSeries'), MIN_MAX_SERIES, MAX_MAX_SERIES, DEFAULT_MAX_SERIES);
    }

    /** True when the request draws Small multiples (a Panel field is set). */
    public static Boolean hasPanelField(Map<String, Object> request) {
        Object raw = request.get('panelField');
        return raw != null && String.isNotBlank(String.valueOf(raw));
    }

    /** True when any Measure of the request is drawn as a Reference line. */
    public static Boolean usesReferenceLines(Map<String, Object> request) {
        return referenceLineFlags(request).contains(true);
    }

    /** Per Measure: whether it is drawn as a Reference line. */
    private static List<Boolean> referenceLineFlags(Map<String, Object> request) {
        List<Boolean> flags = new List<Boolean>();
        if (request.get('measures') instanceof List<Object>) {
            for (Object raw : (List<Object>) request.get('measures')) {
                flags.add(
                    raw instanceof Map<String, Object> &&
                    String.valueOf(((Map<String, Object>) raw).get('render')) == REFERENCE_LINE_RENDER
                );
            }
        }
        return flags;
    }

    /** Each Measure's Share of total mode, validated (see the class comment). */
    private static List<String> parseShowAs(Map<String, Object> request) {
        List<Object> measures = request.get('measures') instanceof List<Object>
            ? (List<Object>) request.get('measures')
            : new List<Object>();
        Boolean hasSeries =
            request.get('stackByField') != null && String.isNotBlank(String.valueOf(request.get('stackByField')));
        List<String> modes = new List<String>();
        for (Integer i = 0; i < measures.size(); i++) {
            Map<String, Object> measure = measures[i] instanceof Map<String, Object>
                ? (Map<String, Object>) measures[i]
                : new Map<String, Object>();
            Object rawMode = measure.get('showAs');
            String mode = rawMode == null || String.isBlank(String.valueOf(rawMode))
                ? BoardChartEngine.SHOW_AS_VALUE
                : String.valueOf(rawMode).trim();
            String label = 'Measure ' + (i + 1);
            if (!SHOW_AS_MODES.contains(mode)) {
                throw shareError(label + ': show as must be value, percentOfTotal or percentOfCategory.');
            }
            if (mode != BoardChartEngine.SHOW_AS_VALUE) {
                Object rawFunction = measure.get('aggregateFunction');
                String aggregateFunction = rawFunction == null ? '' : String.valueOf(rawFunction).trim().toUpperCase();
                if (!SHAREABLE_FUNCTIONS.contains(aggregateFunction)) {
                    throw shareError(label + ': a percentage is only available for COUNT and SUM Measures.');
                }
                // A Reference line is the Measure's overall value; as a share of the whole scope it would always be 100%.
                if (String.valueOf(measure.get('render')) == REFERENCE_LINE_RENDER) {
                    throw shareError(label + ': a Reference line shows the overall value, not a percentage.');
                }
            }
            if (mode == BoardChartEngine.SHOW_AS_PERCENT_OF_CATEGORY && !hasSeries && measures.size() < 2) {
                throw shareError(label + ': percent of category needs a series (Stack by) field or several Measures.');
            }
            modes.add(mode);
        }
        return modes;
    }

    private static BoardErrors.BoardException shareError(String message) {
        return BoardErrors.error(BoardErrors.CONFIG_ERROR, message, null, 'measures');
    }

    private static ChartResult shape(
        Map<String, Object> request,
        List<String> showAs,
        ChartResult result,
        BoardFormulaMeasures.ChartPlan formulas,
        BoardCrossObjectMeasures.ChartPlan crossObject
    ) {
        // The running cursor state holds only the Widget-object Measures read so far.
        result.partialState = result.isComplete ? null : result.accumulator.state();
        Boolean includeBlank = request.get('includeNullBucket') != false;
        // Cross-object measures join onto the categories (`BoardCrossObjectMeasures`), then Formula measures run per
        // category over every Measure (`BoardFormulaMeasures`).
        crossObject.attach(result, request, includeBlank);
        List<String> queriedFunctions = result.aggregateFunctions;
        List<BoardChartEngine.GroupedRow> rows = formulas.apply(result, includeBlank);
        formulas.restoreMeasures(request);
        crossObject.blankDependentFormulas(request, rows, result);
        BoardChartEngine.Settings settings = new BoardChartEngine.Settings();
        settings.aggregateFunctions = result.aggregateFunctions;
        settings.hasSeries = result.stackBy != null;
        settings.sortBy = request.get('sortBy') == null ? null : String.valueOf(request.get('sortBy'));
        settings.isDateAxis = result.groupBy != null && result.groupBy.dateGranularity != null;
        settings.maxCategories = maxCategories(request);
        settings.overflowMode = 'OTHER'.equalsIgnoreCase(String.valueOf(request.get('overflowMode')))
            ? 'OTHER'
            : 'TRUNCATE';
        settings.maxSeries = maxSeries(request);
        settings.includeBlank = request.get('includeNullBucket') != false;
        settings.picklistOrder = result.groupBy == null ? new List<String>() : result.groupBy.picklistOrder;
        settings.showAs = showAs;
        settings.grandTotals = result.grandTotals;
        settings.otherValues = formulas.otherValues();

        BoardChartEngine.ChartShape chart = result.panelBy == null
            ? BoardChartEngine.shape(settings, rows)
            : shapePanels(request, settings, result, rows);
        result.categories = chart.categories;
        result.series = chart.series;
        result.points = chart.points;
        result.truncatedCategories = chart.truncatedCategories;
        result.hiddenCategories = chart.hiddenCategories;
        result.truncatedSeries = chart.truncatedSeries;
        // The running state stays corporate; only the shaped points are converted to the Display currency.
        // A Share of total is a fraction, never a currency: its points skip the conversion.
        result.points = new List<BoardChartEngine.ChartPoint>();
        for (BoardChartEngine.ChartPoint point : chart.points) {
            if (!isShare(showAs, point.measureIndex)) {
                result.points.add(point);
            }
        }
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        result = converter.toDisplay(result, request);
        result.points = chart.points;
        result.overallValues = referenceLineValues(request, result, settings.includeBlank, converter);
        for (Integer i = 0; i < result.currencyIsoCodes.size(); i++) {
            if (isShare(showAs, i)) {
                result.currencyIsoCodes[i] = null;
            }
        }
        result.panelTotals = panelTotals(request, showAs, result, queriedFunctions, formulas, converter);
        return result;
    }

    /** Small multiples: each Panel's total per Measure (`BoardChartPanelTotals`); null unless needed. */
    private static List<BoardChartPanelTotals.PanelTotal> panelTotals(
        Map<String, Object> request,
        List<String> showAs,
        ChartResult result,
        List<String> queriedFunctions,
        BoardFormulaMeasures.ChartPlan formulas,
        BoardCurrencyConverter converter
    ) {
        if (result.panelBy == null || !BoardChartPanelTotals.isNeeded(request)) {
            return null;
        }
        Map<String, List<Decimal>> queriedTotals = result.panelQueryTotals != null
            ? result.panelQueryTotals
            : BoardChartPanelTotals.fromRows(
                  queriedFunctions,
                  result.accumulator.rows,
                  request.get('includeNullBucket') != false
              );
        List<Boolean> shares = new List<Boolean>();
        for (Integer i = 0; i < result.aggregateFunctions.size(); i++) {
            shares.add(isShare(showAs, i));
        }
        return BoardChartPanelTotals.forPanels(
            result.panels,
            queriedTotals,
            formulas,
            result.currencyIsoCodes,
            shares,
            converter
        );
    }

    /** Small multiples: one Panel per Panel field value (`BoardChartPanels`), max 50 categories per Panel. */
    private static BoardChartEngine.ChartShape shapePanels(
        Map<String, Object> request,
        BoardChartEngine.Settings settings,
        ChartResult result,
        List<BoardChartEngine.GroupedRow> rows
    ) {
        settings.maxCategories = Math.min(settings.maxCategories, MAX_PANEL_CATEGORIES);
        BoardChartPanels.Settings panelSettings = new BoardChartPanels.Settings();
        panelSettings.maxPanels = clamp(
            request.get('maxPanels'),
            MIN_MAX_PANELS,
            MAX_MAX_PANELS,
            BoardChartPanels.DEFAULT_MAX_PANELS
        );
        panelSettings.panelSort = request.get('panelSort') == null ? null : String.valueOf(request.get('panelSort'));
        panelSettings.panelSortMeasure = clamp(
            request.get('panelSortMeasure'),
            0,
            Math.max(0, result.aggregateFunctions.size() - 1),
            0
        );
        panelSettings.picklistOrder = result.panelBy.picklistOrder;
        panelSettings.isDatePanel = result.panelBy.dateGranularity != null;
        BoardChartPanels.PanelShape panels = BoardChartPanels.shape(settings, panelSettings, rows);
        result.panels = panels.panels;
        result.cutPanels = panels.cutPanels;
        result.hiddenPanels = panels.hiddenPanels;
        BoardChartEngine.ChartShape chart = new BoardChartEngine.ChartShape();
        chart.categories = panels.categories;
        chart.series = panels.series;
        chart.points = panels.points;
        chart.truncatedCategories = panels.truncatedCategories;
        chart.hiddenCategories = panels.hiddenCategories;
        chart.truncatedSeries = panels.truncatedSeries;
        return chart;
    }

    /** Reference line overall values in the Display currency (see the class comment); null without Reference lines. */
    private static List<Decimal> referenceLineValues(
        Map<String, Object> request,
        ChartResult result,
        Boolean includeBlank,
        BoardCurrencyConverter converter
    ) {
        List<Boolean> flags = referenceLineFlags(request);
        if (!flags.contains(true)) {
            return null;
        }
        List<Decimal> overall = result.overallValues != null
            ? result.overallValues
            : BoardChartEngine.overallValues(result.aggregateFunctions, result.accumulator.rows, includeBlank);
        List<Decimal> values = new List<Decimal>();
        for (Integer i = 0; i < result.aggregateFunctions.size(); i++) {
            Boolean isReferenceLine = i < flags.size() && flags[i] && i < overall.size();
            values.add(
                isReferenceLine ? (Decimal) converter.fromCorporate(overall[i], result.currencyIsoCodes[i]) : null
            );
        }
        return values;
    }

    private static Boolean isShare(List<String> showAs, Integer measureIndex) {
        return measureIndex != null &&
            measureIndex < showAs.size() &&
            showAs[measureIndex] != BoardChartEngine.SHOW_AS_VALUE;
    }

    private static Integer clamp(Object raw, Integer min, Integer max, Integer fallback) {
        if (raw == null || String.isBlank(String.valueOf(raw))) {
            return fallback;
        }
        Decimal value;
        try {
            value = Decimal.valueOf(String.valueOf(raw));
        } catch (TypeException notNumeric) {
            return fallback;
        }
        return Math.min(max, Math.max(min, value.round(System.RoundingMode.HALF_UP).intValue()));
    }

    /** The shaped chart of one Chart query call (see the class comment). */
    public class ChartResult {
        /** `SINGLE` (one SOQL `GROUP BY`) or `CURSOR` (`Database.Cursor` chunks). */
        @AuraEnabled
        public String mode = 'SINGLE';
        @AuraEnabled
        public Boolean isComplete = true;
        /** Matching rows (counted when a value Measure or the cursor tier needs it; else null). */
        @AuraEnabled
        public Integer totalRows;
        /** Cursor tier: rows read so far. */
        @AuraEnabled
        public Integer processedRows;
        /** Cursor tier: handle, next offset and running state to send back to `fetchChartChunk`. */
        @AuraEnabled
        public String cursor;
        @AuraEnabled
        public Integer nextOffset;
        @AuraEnabled
        public String partialState;
        /** The grouped query was capped and the cursor tier could not run: groups may be missing. */
        @AuraEnabled
        public Boolean hasMoreGroups = false;
        /** One per Measure, in Measure order. */
        @AuraEnabled
        public List<String> aggregateFunctions = new List<String>();
        /** One per Measure: the value field's `Schema.DisplayType` name, or null for `COUNT`. */
        @AuraEnabled
        public List<String> valueTypes = new List<String>();
        /** One per Measure: the Display currency of an amount Measure, or null (counts, percentages). */
        @AuraEnabled
        public List<String> currencyIsoCodes = new List<String>();
        @AuraEnabled
        public BoardQueryService.ChartDimensionInfo groupBy;
        @AuraEnabled
        public BoardQueryService.ChartDimensionInfo stackBy;
        /** Small multiples: the Panel field; null without one. */
        @AuraEnabled
        public BoardQueryService.ChartDimensionInfo panelBy;
        /** Small multiples: the Panels in order (empty without a Panel field). */
        @AuraEnabled
        public List<BoardChartEngine.ChartKey> panels = new List<BoardChartEngine.ChartKey>();
        /** Small multiples: Panels beyond max panels were cut. */
        @AuraEnabled
        public Boolean cutPanels = false;
        @AuraEnabled
        public Integer hiddenPanels = 0;
        @AuraEnabled
        public List<String> appliedFilterIds = new List<String>();
        @AuraEnabled
        public List<String> ignoredFilterIds = new List<String>();

        @AuraEnabled
        public List<BoardChartEngine.ChartKey> categories = new List<BoardChartEngine.ChartKey>();
        @AuraEnabled
        public List<BoardChartEngine.ChartKey> series = new List<BoardChartEngine.ChartKey>();
        @AuraEnabled
        public List<BoardChartEngine.ChartPoint> points = new List<BoardChartEngine.ChartPoint>();
        @AuraEnabled
        public Boolean truncatedCategories = false;
        @AuraEnabled
        public Integer hiddenCategories = 0;
        @AuraEnabled
        public Boolean truncatedSeries = false;

        /**
         * One per Measure: a Reference line Measure's overall value over the whole scope, else null; null without
         * Reference lines. Set by the SOQL tier in corporate amounts, returned in the Display currency.
         */
        @AuraEnabled
        public List<Decimal> overallValues;

        /** One per Cross-object measure (`BoardCrossObjectMeasures`): the filters it ignores, or why it is blank. */
        @AuraEnabled
        public List<BoardCrossObjectMeasures.Notice> crossObjectNotices;
        /**
         * Small multiples with a Panel headline or a Reference line: each Panel's total per Measure, in Panel order
         * (`BoardChartPanelTotals`); null otherwise.
         */
        @AuraEnabled
        public List<BoardChartPanelTotals.PanelTotal> panelTotals;

        /** SOQL tier: queried Measures' totals per Panel key, corporate amounts (not returned). */
        public Map<String, List<Decimal>> panelQueryTotals;

        /** Share of total grand totals per Measure from the ungrouped query of a capped result (not returned). */
        public List<Decimal> grandTotals;

        /** Grouped rows read so far (not returned to the client; `partialState` carries them between chunks). */
        public BoardChartEngine.Accumulator accumulator;
    }
}