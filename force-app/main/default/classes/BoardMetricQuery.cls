/**
 * Metric widget Measures list, behind the Metric query entry point `BoardQueryService.queryMetric`.
 *
 * Request: `{ objectApiName, measures: [{ aggregateFunction, valueFieldApiName, hidden }] (1–6, exactly one without
 * `hidden: true`; no Share of total `showAs`: Chart widget only), filters[], baseFilters[], refreshToken }`. A request without `measures` (a single-aggregate Metric
 * saved before the Measures list) is one visible Measure built from its `aggregateFunction` / `valueFieldApiName`.
 *
 * Every Measure, hidden included, is aggregated over the same compiled scope with the Metric tiers of
 * `BoardQueryService.runMetric` (each Measure may open its own cursor). The result is the visible Measure's result
 * (so the cursor hand-off and Thresholds work as for one aggregate) plus `measures`, one result per Measure in Measure
 * order, and `visibleIndex`. Hidden Measures are inputs for later calculations, not shown. A Formula measure is not
 * aggregated: `BoardFormulaMeasures` evaluates it from the other Measures' results, or leaves it incomplete while an
 * input is on the cursor tier (the client finishes the inputs and calls `BoardFormulaMeasures.evaluateMetric`).
 *
 * A Measure's optional `condition` (Measure condition, a Base filter condition tree) narrows the scope for that
 * Measure only, ANDed with the Filter context and Base filters.
 *
 * A Cross-object measure (`sourceObject`, `filterBindings`) aggregates its own object's rows instead
 * (`BoardCrossObjectMeasures`); `crossObjectNotices` reports the filters each one ignores, or why it is blank.
 */
public with sharing class BoardMetricQuery {
    /** Max Measures in one Metric widget. */
    public static final Integer MAX_MEASURES = 6;

    /**
     * Validates the Measures list, then aggregates every Measure over `scope`; currency Measures come back in the
     * request's Display currency (`BoardCurrencyConverter`).
     */
    public static BoardQueryService.MetricResult run(BoardQueryService.QueryScope scope, Map<String, Object> request) {
        List<Map<String, Object>> measures = measures(request);
        Integer visibleIndex = visibleIndex(measures);
        Map<Integer, BoardFormula> formulas = BoardFormulaMeasures.build(measures, false);
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        List<BoardQueryService.MetricResult> results = new List<BoardQueryService.MetricResult>();
        // Measures sharing a Measure condition share one narrowed scope.
        Map<String, BoardQueryService.QueryScope> scopesByCondition = new Map<String, BoardQueryService.QueryScope>();
        List<BoardCrossObjectMeasures.Notice> crossObjectNotices = new List<BoardCrossObjectMeasures.Notice>();
        for (Integer i = 0; i < measures.size(); i++) {
            Map<String, Object> measure = measures[i];
            if (formulas.containsKey(i)) {
                results.add(BoardFormulaMeasures.formulaResult(scope));
                continue;
            }
            if (BoardCrossObjectMeasures.isCrossObject(measure)) {
                // Rows of another object, through the Measure's own Filter bindings.
                BoardQueryService.MetricResult crossResult = BoardCrossObjectMeasures.metric(
                    request,
                    measure,
                    i,
                    crossObjectNotices
                );
                results.add(converter.toDisplay(crossResult, request));
                continue;
            }
            Object condition = BoardMeasureGroups.conditionOf(measure);
            String key = BoardMeasureGroups.groupKey(condition);
            if (!scopesByCondition.containsKey(key)) {
                scopesByCondition.put(key, scope.withMeasureCondition(condition));
            }
            results.add(converter.toDisplay(BoardQueryService.runMetric(scopesByCondition.get(key), measure), request));
        }
        // Formula measures: one step after the other Measures (`BoardFormulaMeasures`).
        BoardFormulaMeasures.applyToMetric(formulas, results, request);
        if (crossObjectNotices.isEmpty()) {
            return widgetResult(results, visibleIndex);
        }
        BoardCrossObjectMeasures.blankDependentFormulas(measures, crossObjectNotices, results);
        BoardQueryService.MetricResult widget = widgetResult(results, visibleIndex);
        widget.crossObjectNotices = crossObjectNotices;
        return widget;
    }

    /** Index of the request's visible Measure (0 for a single-aggregate request); validates the Measures list. */
    public static Integer visibleMeasureIndex(Map<String, Object> request) {
        return visibleIndex(measures(request));
    }

    /** The request's Measures, or the one legacy single-aggregate Measure. */
    private static List<Map<String, Object>> measures(Map<String, Object> request) {
        Object raw = request.get('measures');
        if (raw == null) {
            return new List<Map<String, Object>>{
                new Map<String, Object>{
                    'aggregateFunction' => request.get('aggregateFunction'),
                    'valueFieldApiName' => request.get('valueFieldApiName')
                }
            };
        }
        List<Object> rawMeasures = raw instanceof List<Object> ? (List<Object>) raw : new List<Object>();
        if (rawMeasures.isEmpty() || rawMeasures.size() > MAX_MEASURES) {
            throw configError('A Metric widget needs 1 to ' + MAX_MEASURES + ' Measures.');
        }
        List<Map<String, Object>> measures = new List<Map<String, Object>>();
        for (Integer i = 0; i < rawMeasures.size(); i++) {
            if (!(rawMeasures[i] instanceof Map<String, Object>)) {
                throw configError('Measure ' + (i + 1) + ' must be an object.');
            }
            Object showAs = ((Map<String, Object>) rawMeasures[i]).get('showAs');
            if (showAs != null && String.valueOf(showAs) != 'value') {
                throw configError('Measure ' + (i + 1) + ': Share of total is only available on the Chart widget.');
            }
            measures.add((Map<String, Object>) rawMeasures[i]);
        }
        return measures;
    }

    /** Index of the one Measure without `hidden: true`. */
    private static Integer visibleIndex(List<Map<String, Object>> measures) {
        Integer visible;
        Integer visibleCount = 0;
        for (Integer i = 0; i < measures.size(); i++) {
            if (measures[i].get('hidden') != true) {
                visible = i;
                visibleCount++;
            }
        }
        if (visibleCount != 1) {
            throw configError(
                'A Metric widget shows exactly one Measure: ' +
                (visibleCount == 0
                    ? 'every Measure is Hidden. Show one of them.'
                    : String.valueOf(visibleCount) + ' Measures are visible. Mark the others Hidden.')
            );
        }
        return visible;
    }

    /** A copy of the visible Measure's result carrying every Measure's result (no self-reference). */
    private static BoardQueryService.MetricResult widgetResult(
        List<BoardQueryService.MetricResult> results,
        Integer visibleIndex
    ) {
        BoardQueryService.MetricResult visible = results[visibleIndex];
        BoardQueryService.MetricResult widget = new BoardQueryService.MetricResult();
        widget.aggregateFunction = visible.aggregateFunction;
        widget.valueType = visible.valueType;
        widget.currencyIsoCode = visible.currencyIsoCode;
        widget.thresholdAmounts = visible.thresholdAmounts;
        widget.gaugeAmounts = visible.gaugeAmounts;
        widget.value = visible.value;
        widget.totalRows = visible.totalRows;
        widget.mode = visible.mode;
        widget.isComplete = visible.isComplete;
        widget.chunk = visible.chunk;
        widget.appliedFilterIds = visible.appliedFilterIds;
        widget.ignoredFilterIds = visible.ignoredFilterIds;
        widget.measures = results;
        widget.visibleIndex = visibleIndex;
        return widget;
    }

    private static BoardErrors.BoardException configError(String message) {
        return BoardErrors.error(BoardErrors.CONFIG_ERROR, message, null, 'measures');
    }
}