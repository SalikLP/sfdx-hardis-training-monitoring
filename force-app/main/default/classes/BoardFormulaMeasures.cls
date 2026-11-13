/**
 * Formula measures of a Chart or Metric widget's Measures list (`aggregateFunction: 'FORMULA'`, `formula`).
 *
 * A Formula measure is computed in one step after the Widget's other Measures, per category (Chart) or once
 * (Metric), with `BoardFormula`: Measure 1 is slot A, Measure 2 slot B, … Measure 6 slot F. `build` validates every
 * Formula measure with an Admin-readable `CONFIG_ERROR`: the formula itself (`FormulaEval` build), a slot without a
 * Measure, a reference to itself or to another Formula measure (one level only), and a series field (Measures mode
 * only). Formula measures are never queried: the Chart widget queries only its other Measures (`forChart`), or a record
 * count for the categories when every Measure is a Formula measure (a constant target such as `15000`).
 *
 * Currency (`BoardFormulaCurrency`): a Formula measure flagged `isCurrency` returns an amount in the Display currency,
 * its constants read in the Config currency; an unflagged one reads its inputs in the Display currency and never
 * converts. Share of total inputs are their raw values; a Formula measure is never a Share of total.
 */
public with sharing class BoardFormulaMeasures {
    public static final String FORMULA = 'FORMULA';
    /** `MetricResult.mode` of a cursor-tier aggregate. */
    private static final String CURSOR_MODE = 'CURSOR';
    /** Request flag while a Chart widget's `measures` holds only the queried Measures (`forChart`). */
    private static final String FORMULA_FLAG = 'hasFormulaMeasures';

    /** True while `request` is a Chart request whose Formula measures were taken out to query the rest (`forChart`). */
    public static Boolean hasFormulaMeasures(Map<String, Object> request) {
        return request.get(FORMULA_FLAG) == true;
    }

    /** True when `measure` is a Formula measure. */
    public static Boolean isFormula(Object measure) {
        if (!(measure instanceof Map<String, Object>)) {
            return false;
        }
        Object aggregateFunction = ((Map<String, Object>) measure).get('aggregateFunction');
        return aggregateFunction != null && FORMULA.equalsIgnoreCase(String.valueOf(aggregateFunction).trim());
    }

    /**
     * Validates and builds every Formula measure of `measures` (Measure index → formula); empty when there is none.
     * `hasSeries`: the Widget splits its Measure by a series field.
     */
    public static Map<Integer, BoardFormula> build(List<Map<String, Object>> measures, Boolean hasSeries) {
        Map<Integer, BoardFormula> formulas = new Map<Integer, BoardFormula>();
        for (Integer i = 0; i < measures.size(); i++) {
            if (!isFormula(measures[i])) {
                continue;
            }
            if (measures.size() > BoardFormula.SLOTS.size()) {
                throw configError('A Widget shows at most ' + BoardFormula.SLOTS.size() + ' Measures.');
            }
            if (hasSeries == true) {
                throw configError(
                    'A Formula measure can\'t be used with a series field. Remove the Stack by field or the Formula measure.'
                );
            }
            String prefix = 'Measure ' + (i + 1) + ' (' + BoardFormula.SLOTS[i] + ') formula';
            BoardFormula built;
            try {
                Object text = measures[i].get('formula');
                built = BoardFormula.build(text == null ? null : String.valueOf(text));
                built.isCurrency = measures[i].get('isCurrency') == true;
            } catch (BoardErrors.BoardException invalid) {
                throw configError(prefix + ': ' + invalid.getMessage());
            }
            List<Integer> inputs = new List<Integer>(built.inputIndexes());
            inputs.sort();
            for (Integer input : inputs) {
                String slot = BoardFormula.SLOTS[input];
                if (input == i) {
                    throw configError(prefix + ' can\'t use itself (' + slot + ').');
                }
                if (input >= measures.size()) {
                    throw configError(prefix + ' uses ' + slot + ', but there is no Measure ' + (input + 1) + '.');
                }
                if (isFormula(measures[input])) {
                    throw configError(
                        prefix + ' can\'t use ' + slot + ': a Formula measure can\'t reference another Formula measure.'
                    );
                }
            }
            formulas.put(i, built);
        }
        return formulas;
    }

    /** `values` in Measure order with each Formula measure's result filled in from its inputs. */
    public static List<Decimal> apply(Map<Integer, BoardFormula> formulas, List<Decimal> values) {
        return apply(formulas, values, null, null, null);
    }

    /**
     * `apply` with currency: `amounts[i]` marks the values that are amounts in `valuesIsoCode` (see
     * `BoardFormulaCurrency`); a null `formulaCurrency` evaluates as entered.
     */
    public static List<Decimal> apply(
        Map<Integer, BoardFormula> formulas,
        List<Decimal> values,
        BoardFormulaCurrency formulaCurrency,
        List<Boolean> amounts,
        String valuesIsoCode
    ) {
        List<Decimal> inputs = new List<Decimal>(values);
        for (Integer index : formulas.keySet()) {
            // Inputs are never Formula measures, so evaluation order doesn't matter.
            values[index] = formulaCurrency == null
                ? formulas.get(index).evaluate(inputs)
                : formulaCurrency.evaluate(formulas.get(index), inputs, amounts, valuesIsoCode);
        }
        return values;
    }

    // ---------------------------------------------------------------------------------------------------------
    // Chart widget
    // ---------------------------------------------------------------------------------------------------------

    /**
     * Validates the request's Formula measures and replaces its `measures` with the Measures to query (the plan maps
     * them back). A request without Formula measures is left as is.
     */
    public static ChartPlan forChart(Map<String, Object> request) {
        ChartPlan plan = new ChartPlan();
        Object raw = request.get('measures');
        if (!(raw instanceof List<Object>)) {
            return plan;
        }
        List<Map<String, Object>> measures = new List<Map<String, Object>>();
        Boolean hasFormula = false;
        for (Object measure : (List<Object>) raw) {
            if (!(measure instanceof Map<String, Object>) || measure == null) {
                // Malformed lists are reported by the query itself.
                return plan;
            }
            measures.add((Map<String, Object>) measure);
            hasFormula = hasFormula || isFormula(measure);
        }
        if (!hasFormula) {
            return plan;
        }
        Object stackByField = request.get('stackByField');
        plan.formulas = build(measures, stackByField != null && String.isNotBlank(String.valueOf(stackByField)));
        plan.measures = (List<Object>) raw;
        plan.request = request;
        plan.converter = BoardCurrencyConverter.forRequest();
        plan.formulaCurrency = new BoardFormulaCurrency(plan.converter, request);
        Boolean formulaReferenceLine = false;
        for (Integer index : plan.formulas.keySet()) {
            formulaReferenceLine =
                formulaReferenceLine ||
                String.valueOf(measures[index].get('render')) == BoardChartQuery.REFERENCE_LINE_RENDER;
        }
        List<Object> queried = new List<Object>();
        for (Integer i = 0; i < measures.size(); i++) {
            plan.queriedIndexes.add(plan.formulas.containsKey(i) ? -1 : queried.size());
            if (plan.formulas.containsKey(i)) {
                continue;
            }
            Map<String, Object> measure = measures[i];
            if (formulaReferenceLine) {
                // A Formula measure drawn as a Reference line needs its inputs' overall values too.
                measure = new Map<String, Object>(measure);
                measure.put('render', BoardChartQuery.REFERENCE_LINE_RENDER);
            }
            queried.add(measure);
        }
        if (queried.isEmpty()) {
            queried.add(new Map<String, Object>{ 'aggregateFunction' => 'COUNT' });
        }
        request.put('measures', queried);
        request.put(FORMULA_FLAG, true);
        return plan;
    }

    /** How a Chart widget's queried Measures map back onto its Measures list. */
    public class ChartPlan {
        /** Measure index → formula; empty when the Widget has no Formula measure. */
        private Map<Integer, BoardFormula> formulas = new Map<Integer, BoardFormula>();
        /** Per Measure: its index among the queried Measures, or -1 for a Formula measure. */
        private List<Integer> queriedIndexes = new List<Integer>();
        /** The request's full Measures list; null when the Widget has no Formula measure. */
        private List<Object> measures;
        private Map<String, Object> request;
        private BoardCurrencyConverter converter;
        private BoardFormulaCurrency formulaCurrency;
        /** Per Measure: whether its (corporate) value is an amount; set by `apply`. */
        private List<Boolean> amounts = new List<Boolean>();
        /** The queried Measures' aggregate functions; set by `apply`. */
        private List<String> queriedFunctions;

        /**
         * How an "Other" category or series computes its values from its rows' merged partials: the queried Measures
         * read from them, then each Formula measure evaluated on those (`BoardChartEngine.OtherValues`); null without
         * Formula measures (the engine reads each partial itself). Call after `apply`.
         */
        public BoardChartEngine.OtherValues otherValues() {
            return formulas.isEmpty() || queriedFunctions == null
                ? null
                : new FormulaOtherValues(this, queriedFunctions);
        }

        /** Puts the full Measures list back into the request after the query (Reference line flags read it). */
        public void restoreMeasures(Map<String, Object> request) {
            if (measures != null) {
                request.put('measures', measures);
                request.remove(FORMULA_FLAG);
            }
        }

        /**
         * One value per queried Measure widened to the Measures list, each Formula measure evaluated on them (e.g. a
         * Panel total); returned as is without Formula measures.
         */
        public List<Decimal> widen(List<Decimal> queriedValues) {
            if (formulas.isEmpty()) {
                return queriedValues;
            }
            List<Decimal> values = new List<Decimal>();
            for (Integer queried : queriedIndexes) {
                values.add(queried < 0 || queried >= queriedValues.size() ? null : queriedValues[queried]);
            }
            return evaluate(values);
        }

        /** Formula measures over corporate `values`: a currency Formula measure's result is a corporate amount. */
        private List<Decimal> evaluate(List<Decimal> values) {
            return BoardFormulaMeasures.apply(
                formulas,
                values,
                formulaCurrency,
                amounts,
                converter.getCorporateIsoCode()
            );
        }

        /** `apply` keeping the "(Blank)" category in the Reference line overall values. */
        public List<BoardChartEngine.GroupedRow> apply(BoardChartQuery.ChartResult result) {
            return apply(result, true);
        }

        /**
         * The result's grouped rows with one value per Measure, Formula measures evaluated per category (and
         * series); `aggregateFunctions` and `valueTypes` are widened to the Measures list (`FORMULA`, no value type).
         * The accumulator (the cursor state) keeps only the queried Measures.
         */
        public List<BoardChartEngine.GroupedRow> apply(BoardChartQuery.ChartResult result, Boolean includeBlank) {
            if (formulas.isEmpty()) {
                return result.accumulator.rows;
            }
            queriedFunctions = result.aggregateFunctions;
            List<String> queriedTypes = result.valueTypes == null ? new List<String>() : result.valueTypes;
            List<String> functions = new List<String>();
            List<String> types = new List<String>();
            amounts = new List<Boolean>();
            for (Integer i = 0; i < queriedIndexes.size(); i++) {
                Integer queried = queriedIndexes[i];
                String valueType = queried < 0 || queried >= queriedTypes.size() ? null : queriedTypes[queried];
                if (queried < 0 && formulas.get(i).isCurrency) {
                    // A currency Formula measure is an amount: converted to the Display currency like one.
                    valueType = Schema.DisplayType.CURRENCY.name();
                }
                functions.add(queried < 0 ? FORMULA : queriedFunctions[queried]);
                types.add(valueType);
                amounts.add(
                    queried >= 0 && converter.isoCodeFor(queriedFunctions[queried], valueType, request) != null
                );
            }
            List<BoardChartEngine.GroupedRow> rows = new List<BoardChartEngine.GroupedRow>();
            for (BoardChartEngine.GroupedRow row : result.accumulator.rows) {
                List<Decimal> values = new List<Decimal>();
                for (Integer queried : queriedIndexes) {
                    values.add(queried < 0 ? null : row.value(queried, queriedFunctions[queried]));
                }
                BoardChartEngine.GroupedRow widened = new BoardChartEngine.GroupedRow(
                    row.categoryValue,
                    row.categoryLabel,
                    row.seriesValue,
                    row.seriesLabel
                );
                widened.panelValue = row.panelValue;
                widened.panelLabel = row.panelLabel;
                widened.values = evaluate(values);
                widened.otherInputs = row.partials;
                rows.add(widened);
            }
            result.aggregateFunctions = functions;
            result.valueTypes = types;
            if (result.grandTotals != null) {
                // Share of total denominators of the queried Measures; a Formula measure is never a share.
                List<Decimal> grandTotals = new List<Decimal>();
                for (Integer queried : queriedIndexes) {
                    grandTotals.add(
                        queried < 0 || queried >= result.grandTotals.size() ? null : result.grandTotals[queried]
                    );
                }
                result.grandTotals = grandTotals;
            }
            // Reference line overall values: the queried Measures' (from the query, or merged from the rows), and
            // each Formula measure evaluated over them.
            List<Decimal> queriedOverall = result.overallValues != null
                ? result.overallValues
                : BoardChartEngine.overallValues(queriedFunctions, result.accumulator.rows, includeBlank);
            List<Decimal> overall = new List<Decimal>();
            for (Integer queried : queriedIndexes) {
                overall.add(queried < 0 || queried >= queriedOverall.size() ? null : queriedOverall[queried]);
            }
            result.overallValues = evaluate(overall);
            return rows;
        }
    }

    /** "Other" values of a Widget with Formula measures: the queried Measures' merged partials, widened and evaluated. */
    private class FormulaOtherValues implements BoardChartEngine.OtherValues {
        private ChartPlan plan;
        private List<String> queriedFunctions;

        FormulaOtherValues(ChartPlan plan, List<String> queriedFunctions) {
            this.plan = plan;
            this.queriedFunctions = queriedFunctions;
        }

        public List<Decimal> valuesOf(List<BoardChartEngine.Partial> merged) {
            List<Decimal> queriedValues = new List<Decimal>();
            for (Integer q = 0; q < queriedFunctions.size(); q++) {
                queriedValues.add(q < merged.size() ? merged[q].value(queriedFunctions[q]) : null);
            }
            return plan.widen(queriedValues);
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Metric widget
    // ---------------------------------------------------------------------------------------------------------

    /** The placeholder result of a Formula measure, filled by `applyToMetric`. */
    public static BoardQueryService.MetricResult formulaResult(BoardQueryService.QueryScope scope) {
        BoardQueryService.MetricResult result = scope == null
            ? new BoardQueryService.MetricResult()
            : new BoardQueryService.MetricResult(FORMULA, scope);
        result.aggregateFunction = FORMULA;
        return result;
    }

    /**
     * Evaluates each Formula measure's result from its inputs' results. While an input is still on the cursor tier
     * (`isComplete: false`), the Formula measure stays incomplete: the client finishes the inputs and calls
     * `evaluateMetric`.
     */
    public static void applyToMetric(
        Map<Integer, BoardFormula> formulas,
        List<BoardQueryService.MetricResult> results
    ) {
        applyToMetric(formulas, results, new Map<String, Object>());
    }

    /**
     * `applyToMetric` in the request's currencies: the other Measures' results are in the Display currency; a
     * currency Formula measure's result is an amount in it (`currencyIsoCode`, `valueType: CURRENCY`, with the
     * request's Thresholds and Gauge amounts converted).
     */
    public static void applyToMetric(
        Map<Integer, BoardFormula> formulas,
        List<BoardQueryService.MetricResult> results,
        Map<String, Object> request
    ) {
        if (formulas.isEmpty()) {
            return;
        }
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        BoardFormulaCurrency formulaCurrency = new BoardFormulaCurrency(converter, request);
        String displayIsoCode = converter.displayIsoCode(request);
        List<Decimal> values = new List<Decimal>();
        List<Boolean> amounts = new List<Boolean>();
        for (BoardQueryService.MetricResult result : results) {
            values.add(BoardQueryService.toDecimalOrNull(result.value));
            amounts.add(result.currencyIsoCode != null);
        }
        for (Integer index : formulas.keySet()) {
            BoardFormula built = formulas.get(index);
            Boolean inputsComplete = true;
            for (Integer input : built.inputIndexes()) {
                // A cursor-tier input carries its value in chunk buckets (even when the first chunk is the last one).
                inputsComplete =
                    inputsComplete &&
                    results[input].isComplete != false &&
                    results[input].mode != CURSOR_MODE;
            }
            results[index].isComplete = inputsComplete;
            results[index].value = inputsComplete
                ? formulaCurrency.evaluate(built, values, amounts, displayIsoCode)
                : null;
            stampCurrency(results[index], built, converter, request);
        }
    }

    /** A Formula measure's result: an amount in the Display currency when flagged, else no currency. */
    private static void stampCurrency(
        BoardQueryService.MetricResult result,
        BoardFormula built,
        BoardCurrencyConverter converter,
        Map<String, Object> request
    ) {
        result.valueType = built.isCurrency ? Schema.DisplayType.CURRENCY.name() : null;
        result.currencyIsoCode = converter.isoCodeFor(FORMULA, result.valueType, request);
        converter.configAmountsToDisplay(result, request);
    }

    /**
     * The visible Formula measure of a Metric widget, from input values the client finished on the cursor tier.
     * Request: `{ measures, values, currencyIsoCodes, displayCurrency, configCurrency }` (`values`: one per Measure,
     * in Measure order, in the Display currency; `currencyIsoCodes`: each Measure result's ISO code, null for a
     * non-amount). A currency Formula measure's result is in the Display currency.
     */
    @AuraEnabled(cacheable=true)
    public static Decimal evaluateMetric(String requestJson) {
        try {
            Map<String, Object> request = BoardQueryService.parseRequest(requestJson);
            List<Map<String, Object>> measures = new List<Map<String, Object>>();
            for (Object measure : BoardQueryService.getList(request, 'measures')) {
                measures.add(BoardQueryService.asMap(measure));
            }
            Integer visibleIndex = BoardMetricQuery.visibleMeasureIndex(request);
            Map<Integer, BoardFormula> formulas = build(measures, false);
            if (!formulas.containsKey(visibleIndex)) {
                throw configError('The visible Measure is not a Formula measure.');
            }
            List<Decimal> values = new List<Decimal>();
            Object rawValues = request.get('values');
            for (Object value : rawValues instanceof List<Object> ? (List<Object>) rawValues : new List<Object>()) {
                values.add(BoardQueryService.toDecimalOrNull(value));
            }
            List<Boolean> amounts = new List<Boolean>();
            Object rawIsoCodes = request.get('currencyIsoCodes');
            for (
                Object isoCode : rawIsoCodes instanceof List<Object> ? (List<Object>) rawIsoCodes : new List<Object>()
            ) {
                amounts.add(isoCode != null);
            }
            BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
            return new BoardFormulaCurrency(converter, request)
                .evaluate(formulas.get(visibleIndex), values, amounts, converter.displayIsoCode(request));
        } catch (Exception error) {
            throw BoardErrors.toAuraException(error);
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Config editor
    // ---------------------------------------------------------------------------------------------------------

    /**
     * Config-save check of formula texts: per formula, the `FormulaEval` build error, or null when it builds. The
     * Config editor checks the Measure references itself.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> checkFormulas(List<String> formulas) {
        try {
            List<String> messages = new List<String>();
            for (String text : formulas == null ? new List<String>() : formulas) {
                try {
                    BoardFormula.build(text);
                    messages.add(null);
                } catch (BoardErrors.BoardException invalid) {
                    messages.add(invalid.getMessage());
                }
            }
            return messages;
        } catch (Exception failure) {
            throw BoardErrors.toAuraException(failure);
        }
    }

    private static BoardErrors.BoardException configError(String message) {
        return BoardErrors.error(BoardErrors.CONFIG_ERROR, message, null, 'measures');
    }
}