/**
 * Cross-object measures of a Chart or Metric widget: a Measure with its own `sourceObject` whose rows come from that
 * object instead of the Widget's (e.g. targets next to Opportunity pipeline).
 *
 * Measure shape (on top of `aggregateFunction`, `valueFieldApiName`, `condition`, `showAs`, `render`):
 * `{ sourceObject, categoryMapping, panelMapping, filterBindings, dataProvider }`. `categoryMapping` is the field (or
 * 1–5 hop parent path) on the source object matching the Widget's category; a date field groups at the Widget's date
 * granularity.
 * `panelMapping` is the field matching the Panel field (Small multiples). `filterBindings` (`{ filterId: fieldPath |
 * 'IGNORE' }`) binds the Board's filters to the source object; a filter without one binds by convention only where its
 * field (`fieldApiName`, `OwnerId` for a user filter) exists on the source object, or through the lookup convention.
 * Filters that don't apply are returned per Measure (`Notice.ignoredFilterIds`) so the Widget can list them.
 * `dataProvider` names a Data provider class (`BoardDataProvider`) that supplies the Measure's grouped values instead
 * of the source object's query: it receives that one Measure's request (source object, mappings as grouping,
 * conditions after Filter bindings) and its buckets join like the query's (`BoardDataProviders.scanCrossObject`).
 *
 * Each source (object + mappings + Filter bindings) runs as one grouped query over that object in USER_MODE
 * (`BoardQueryService.scanPartials`; Measures with the same Measure condition share it), joined on the category value:
 * a full outer join, so a category with a target but no pipeline still shows. A source the viewer can't read (object
 * or field) leaves its Measures blank with a Notice (`isBlank`), and Formula measures using them blank too; the rest
 * of the Widget renders. Blocked with a config error: a series field, a Bucket-field category, Small multiples without
 * a panel mapping, Average per record and COUNT_DISTINCT.
 */
public with sharing class BoardCrossObjectMeasures {
    /** In-memory marker on a Cross-object measure of a Chart request: its index in the Widget's Measures list. */
    private static final String INDEX_KEY = '$crossObjectIndex';
    private static final String IGNORE_BINDING = 'IGNORE';
    private static final Set<String> BLOCKED_FUNCTIONS = new Set<String>{ 'AVG_PER', 'COUNT_DISTINCT' };

    /** True when `measure` is a Cross-object measure (a non-Formula Measure with a `sourceObject`). */
    public static Boolean isCrossObject(Object measure) {
        if (!(measure instanceof Map<String, Object>) || BoardFormulaMeasures.isFormula(measure)) {
            return false;
        }
        return String.isNotBlank(text((Map<String, Object>) measure, 'sourceObject'));
    }

    // ---------------------------------------------------------------------------------------------------------
    // Validation
    // ---------------------------------------------------------------------------------------------------------

    /** Config errors of one Cross-object measure (`index` in the Measures list) of a Chart (`isChart`) or Metric. */
    public static void validate(
        Map<String, Object> request,
        Map<String, Object> measure,
        Integer index,
        Boolean isChart
    ) {
        String label = 'Measure ' + (index + 1);
        String sourceObject = text(measure, 'sourceObject');
        String aggregateFunction = text(measure, 'aggregateFunction');
        aggregateFunction = aggregateFunction == null ? 'COUNT' : aggregateFunction.toUpperCase();
        if (BLOCKED_FUNCTIONS.contains(aggregateFunction)) {
            throw configError(
                label +
                    ': ' +
                    (aggregateFunction == 'AVG_PER' ? 'Average per record' : aggregateFunction) +
                    ' isn\'t available on a Cross-object measure.'
            );
        }
        if (!isChart) {
            return;
        }
        if (String.isNotBlank(text(request, 'stackByField'))) {
            throw configError(
                label +
                ': a Cross-object measure can\'t be used with a series field. Remove the Stack by field or the source object.'
            );
        }
        if (BoardBucketField.referencedId(text(request, 'groupByField')) != null) {
            throw configError(
                label +
                    ': a Cross-object measure can\'t join on a Bucket field category. Group by a plain field, or' +
                    ' supply this Widget\'s results from a Data provider.'
            );
        }
        if (String.isBlank(text(measure, 'categoryMapping'))) {
            throw configError(
                label +
                    ': map a field on ' +
                    sourceObject +
                    ' to the category (Group by field) so its rows line up with the chart.'
            );
        }
        if (String.isNotBlank(text(request, 'panelField')) && String.isBlank(text(measure, 'panelMapping'))) {
            throw configError(
                label +
                    ': with Small multiples, map a field on ' +
                    sourceObject +
                    ' to the Panel field too (panel mapping).'
            );
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Chart widget
    // ---------------------------------------------------------------------------------------------------------

    /**
     * Validates the request's Cross-object measures and marks them with their Measure index. Call before
     * `BoardFormulaMeasures.forChart`, then `detach` after it.
     */
    public static ChartPlan forChart(Map<String, Object> request) {
        ChartPlan plan = new ChartPlan();
        Object raw = request.get('measures');
        if (!(raw instanceof List<Object>)) {
            return plan;
        }
        List<Object> measures = (List<Object>) raw;
        for (Integer i = 0; i < measures.size(); i++) {
            if (isCrossObject(measures[i])) {
                Map<String, Object> measure = (Map<String, Object>) measures[i];
                validate(request, measure, i, true);
                measure.put(INDEX_KEY, i);
                plan.hasCrossObject = true;
            }
        }
        return plan;
    }

    /** How a Chart widget's Cross-object measures leave the Widget query and join back onto its categories. */
    public class ChartPlan {
        private Boolean hasCrossObject = false;
        /** The Measures list before `detach` (the queried Measures after Formula measures were taken out). */
        private List<Object> attachedMeasures;
        /** Per attached Measure: its index among the Widget-object Measures, or -1 for a Cross-object measure. */
        private List<Integer> positions = new List<Integer>();
        private List<Slot> slots = new List<Slot>();
        /** One per Cross-object measure, in Measure order; null without Cross-object measures. */
        private List<Notice> notices;

        /**
         * Takes the Cross-object measures out of the request's (queried) Measures, so the Widget query only reads the
         * Widget's object. Without Widget-object Measures a record count stands in, for the Widget's categories.
         */
        public void detach(Map<String, Object> request) {
            if (!hasCrossObject || !(request.get('measures') instanceof List<Object>)) {
                return;
            }
            attachedMeasures = (List<Object>) request.get('measures');
            List<Object> kept = new List<Object>();
            for (Integer p = 0; p < attachedMeasures.size(); p++) {
                Object measure = attachedMeasures[p];
                if (measure instanceof Map<String, Object> && ((Map<String, Object>) measure).containsKey(INDEX_KEY)) {
                    positions.add(-1);
                    slots.add(new Slot(p, (Map<String, Object>) measure));
                } else {
                    positions.add(kept.size());
                    kept.add(measure);
                }
            }
            if (kept.isEmpty()) {
                kept.add(new Map<String, Object>{ 'aggregateFunction' => 'COUNT' });
            }
            request.put('measures', kept);
        }

        /**
         * Queries every Cross-object source and joins its values into the result's grouped rows (full outer join on
         * the category value), widening `aggregateFunctions`, `valueTypes`, Reference line overall values and Share
         * of total grand totals back to the attached Measures. Puts the attached Measures back into the request.
         */
        public void attach(BoardChartQuery.ChartResult result, Map<String, Object> request, Boolean includeBlank) {
            if (attachedMeasures == null) {
                return;
            }
            request.put('measures', attachedMeasures);
            runLegs(request, slots, true);

            List<String> widgetFunctions = result.aggregateFunctions;
            List<String> widgetTypes = result.valueTypes == null ? new List<String>() : result.valueTypes;
            List<BoardChartEngine.GroupedRow> widgetRows = result.accumulator.rows;
            List<String> functions = new List<String>();
            List<String> types = new List<String>();
            Map<Integer, Slot> slotsByPosition = new Map<Integer, Slot>();
            for (Slot slot : slots) {
                slotsByPosition.put(slot.position, slot);
            }
            for (Integer p = 0; p < positions.size(); p++) {
                Integer widgetIndex = positions[p];
                if (widgetIndex >= 0) {
                    functions.add(widgetFunctions[widgetIndex]);
                    types.add(widgetIndex < widgetTypes.size() ? widgetTypes[widgetIndex] : null);
                } else {
                    Slot slot = slotsByPosition.get(p);
                    functions.add(slot.aggregateFunction);
                    types.add(slot.valueType);
                }
            }

            // Widget rows first (their order and labels win), then categories only a Cross-object source has.
            BoardChartEngine.Accumulator joined = new BoardChartEngine.Accumulator(positions.size());
            Map<String, BoardChartEngine.GroupedRow> index = new Map<String, BoardChartEngine.GroupedRow>();
            for (BoardChartEngine.GroupedRow row : widgetRows) {
                List<Object> values = new List<Object>();
                for (Integer p = 0; p < positions.size(); p++) {
                    Integer widgetIndex = positions[p];
                    if (widgetIndex >= 0) {
                        values.add(row.value(widgetIndex, widgetFunctions[widgetIndex]));
                    } else {
                        values.add(emptyValue(functions[p]));
                    }
                }
                joined.put(
                    row.panelValue,
                    row.panelLabel,
                    row.categoryValue,
                    row.categoryLabel,
                    row.seriesValue,
                    row.seriesLabel,
                    values
                );
                index.put(rowKey(row.panelValue, row.categoryValue), joined.rows[joined.rows.size() - 1]);
            }
            for (Slot slot : slots) {
                if (slot.leg.rows == null) {
                    continue;
                }
                for (BoardChartEngine.GroupedRow legRow : slot.leg.rows) {
                    String key = rowKey(legRow.panelValue, legRow.categoryValue);
                    BoardChartEngine.GroupedRow row = index.get(key);
                    if (row == null) {
                        List<Object> empty = new List<Object>();
                        for (String aggregateFunction : functions) {
                            empty.add(emptyValue(aggregateFunction));
                        }
                        joined.put(
                            legRow.panelValue,
                            legRow.panelLabel,
                            legRow.categoryValue,
                            legRow.categoryLabel,
                            null,
                            null,
                            empty
                        );
                        row = joined.rows[joined.rows.size() - 1];
                        index.put(key, row);
                    }
                    row.values[slot.position] = legRow.partials[slot.legIndex].value(slot.aggregateFunction);
                }
            }

            Boolean hasReferenceLines = BoardChartQuery.usesReferenceLines(request);
            if (result.overallValues != null || hasReferenceLines) {
                List<Decimal> widgetOverall = result.overallValues != null
                    ? result.overallValues
                    : BoardChartEngine.overallValues(widgetFunctions, widgetRows, includeBlank);
                result.overallValues = widen(widgetOverall, slotsByPosition, includeBlank);
            }
            if (result.grandTotals != null) {
                result.grandTotals = widen(result.grandTotals, slotsByPosition, true);
            }
            if (result.panelBy != null && BoardChartPanelTotals.isNeeded(request)) {
                // Panel headlines and per-Panel Reference lines: each Panel's total, Cross-object measures included.
                Map<String, List<Decimal>> widgetPanelTotals = result.panelQueryTotals != null
                    ? result.panelQueryTotals
                    : BoardChartPanelTotals.fromRows(widgetFunctions, widgetRows, includeBlank);
                Set<String> panelKeys = new Set<String>(widgetPanelTotals.keySet());
                for (Slot slot : slots) {
                    panelKeys.addAll(slot.panelKeys(includeBlank));
                }
                Map<String, List<Decimal>> panelTotals = new Map<String, List<Decimal>>();
                for (String panelKey : panelKeys) {
                    List<Decimal> widgetValues = widgetPanelTotals.get(panelKey);
                    List<Decimal> widened = new List<Decimal>();
                    for (Integer p = 0; p < positions.size(); p++) {
                        Integer widgetIndex = positions[p];
                        if (widgetIndex < 0) {
                            widened.add(slotsByPosition.get(p).panelTotal(panelKey, includeBlank));
                        } else if (widgetValues != null && widgetIndex < widgetValues.size()) {
                            widened.add(widgetValues[widgetIndex]);
                        } else {
                            widened.add(null);
                        }
                    }
                    panelTotals.put(panelKey, widened);
                }
                result.panelQueryTotals = panelTotals;
            }
            result.aggregateFunctions = functions;
            result.valueTypes = types;
            result.accumulator = joined;
            notices = new List<Notice>();
            for (Slot slot : slots) {
                notices.add(slot.toNotice());
                result.hasMoreGroups = result.hasMoreGroups || slot.leg.hasMoreGroups;
            }
            result.crossObjectNotices = notices;
        }

        /** Widget-object values per attached Measure, with each Cross-object measure's total over its rows. */
        private List<Decimal> widen(
            List<Decimal> widgetValues,
            Map<Integer, Slot> slotsByPosition,
            Boolean includeBlank
        ) {
            List<Decimal> widened = new List<Decimal>();
            for (Integer p = 0; p < positions.size(); p++) {
                Integer widgetIndex = positions[p];
                if (widgetIndex >= 0) {
                    widened.add(widgetIndex < widgetValues.size() ? widgetValues[widgetIndex] : null);
                } else {
                    widened.add(slotsByPosition.get(p).total(includeBlank));
                }
            }
            return widened;
        }

        /**
         * Blanks every Formula measure that uses a Cross-object measure the viewer can't access, in the rows and the
         * Reference line overall values. Call after the Formula measures were evaluated and the full Measures list is
         * back in the request.
         */
        public void blankDependentFormulas(
            Map<String, Object> request,
            List<BoardChartEngine.GroupedRow> rows,
            BoardChartQuery.ChartResult result
        ) {
            if (notices == null) {
                return;
            }
            Set<Integer> blanked = dependentFormulas(request.get('measures'), notices);
            for (Integer formulaIndex : blanked) {
                for (BoardChartEngine.GroupedRow row : rows) {
                    if (row.values != null && formulaIndex < row.values.size()) {
                        row.values[formulaIndex] = null;
                    }
                }
                if (result.overallValues != null && formulaIndex < result.overallValues.size()) {
                    result.overallValues[formulaIndex] = null;
                }
            }
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Metric widget
    // ---------------------------------------------------------------------------------------------------------

    /**
     * One Cross-object measure of a Metric widget (`index` in its Measures list), over its source object's rows the
     * Filter context allows (corporate amounts, like `BoardQueryService.runMetric`). A source the viewer can't access
     * gives a blank value; `notices` gets the Measure's Notice either way.
     */
    public static BoardQueryService.MetricResult metric(
        Map<String, Object> request,
        Map<String, Object> measure,
        Integer index,
        List<Notice> notices
    ) {
        validate(request, measure, index, false);
        Slot slot = new Slot(index, measure);
        runLegs(request, new List<Slot>{ slot }, false);
        BoardQueryService.MetricResult result = new BoardQueryService.MetricResult();
        result.aggregateFunction = slot.aggregateFunction;
        result.valueType = slot.valueType;
        result.value = slot.total(true);
        result.appliedFilterIds = new List<String>(slot.leg.appliedFilterIds);
        result.ignoredFilterIds = new List<String>(slot.leg.ignoredFilterIds);
        notices.add(slot.toNotice());
        return result;
    }

    /** Blanks the results of Formula measures that use a Cross-object measure the viewer can't access. */
    public static void blankDependentFormulas(
        List<Map<String, Object>> measures,
        List<Notice> notices,
        List<BoardQueryService.MetricResult> results
    ) {
        List<Object> rawMeasures = new List<Object>();
        for (Map<String, Object> measure : measures) {
            rawMeasures.add(measure);
        }
        for (Integer formulaIndex : dependentFormulas(rawMeasures, notices)) {
            results[formulaIndex].value = null;
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Shared
    // ---------------------------------------------------------------------------------------------------------

    /** Indexes of the Formula measures among `rawMeasures` that use a blank (inaccessible) Cross-object measure. */
    private static Set<Integer> dependentFormulas(Object rawMeasures, List<Notice> notices) {
        Set<Integer> blankInputs = new Set<Integer>();
        for (Notice notice : notices) {
            if (notice.isBlank) {
                blankInputs.add(notice.measureIndex);
            }
        }
        Set<Integer> dependents = new Set<Integer>();
        if (blankInputs.isEmpty() || !(rawMeasures instanceof List<Object>)) {
            return dependents;
        }
        List<Object> measures = (List<Object>) rawMeasures;
        for (Integer i = 0; i < measures.size(); i++) {
            if (!BoardFormulaMeasures.isFormula(measures[i])) {
                continue;
            }
            String formulaText = text((Map<String, Object>) measures[i], 'formula');
            Set<Integer> inputs = BoardFormula.build(formulaText).inputIndexes();
            inputs.retainAll(blankInputs);
            if (!inputs.isEmpty()) {
                dependents.add(i);
            }
        }
        return dependents;
    }

    /**
     * Runs one query per Cross-object source (object, mappings and Filter bindings) for `slots`, grouped by the
     * category mapping (`grouped`) or ungrouped (Metric widget).
     */
    private static void runLegs(Map<String, Object> request, List<Slot> slots, Boolean grouped) {
        Map<String, List<Slot>> slotsBySource = new Map<String, List<Slot>>();
        List<String> sourceOrder = new List<String>();
        for (Slot slot : slots) {
            String key = sourceKey(slot);
            if (!slotsBySource.containsKey(key)) {
                slotsBySource.put(key, new List<Slot>());
                sourceOrder.add(key);
            }
            slotsBySource.get(key).add(slot);
        }
        for (String key : sourceOrder) {
            List<Slot> sourceSlots = slotsBySource.get(key);
            Leg leg = runLeg(request, sourceSlots, grouped);
            for (Integer i = 0; i < sourceSlots.size(); i++) {
                Slot slot = sourceSlots[i];
                slot.leg = leg;
                slot.legIndex = i;
                if (leg.valueTypes != null && i < leg.valueTypes.size()) {
                    slot.valueType = leg.valueTypes[i];
                }
            }
        }
    }

    /** One Cross-object source's grouped partials, or its access failure. */
    private static Leg runLeg(Map<String, Object> request, List<Slot> sourceSlots, Boolean grouped) {
        Map<String, Object> first = sourceSlots[0].measure;
        Leg leg = new Leg();
        leg.sourceObject = text(first, 'sourceObject');
        List<Object> legMeasures = new List<Object>();
        for (Slot slot : sourceSlots) {
            Map<String, Object> legMeasure = new Map<String, Object>{
                'aggregateFunction' => slot.aggregateFunction,
                'valueFieldApiName' => slot.measure.get('valueFieldApiName')
            };
            if (slot.measure.get('condition') != null) {
                legMeasure.put('condition', slot.measure.get('condition'));
            }
            legMeasures.add(legMeasure);
        }
        Map<String, Object> legRequest = new Map<String, Object>{
            'objectApiName' => leg.sourceObject,
            'measures' => legMeasures,
            'displayCurrency' => request.get('displayCurrency'),
            'configCurrency' => request.get('configCurrency')
        };
        if (grouped) {
            legRequest.put('groupByField', text(first, 'categoryMapping'));
            legRequest.put('dateGranularity', request.get('dateGranularity'));
            legRequest.put('includeNullBucket', request.get('includeNullBucket'));
            if (BoardChartQuery.hasPanelField(request)) {
                // Small multiples: the panel mapping groups like the Panel field, at the same date granularity.
                legRequest.put('panelField', text(first, 'panelMapping'));
                legRequest.put('panelDateGranularity', request.get('panelDateGranularity'));
            }
        }
        try {
            Schema.DescribeSObjectResult source = BoardDescribe.requireReadableObject(leg.sourceObject);
            leg.sourceObject = source.getName();
            legRequest.put('objectApiName', leg.sourceObject);
            // ForecastingQuota: `ForecastingType.DeveloperName` conditions become `ForecastingTypeId` ones.
            BoardForecastingQuota.resolveConditions(leg.sourceObject, legMeasures);
            legRequest.put('filters', rebindFilters(request, first, source));
            BoardQueryService.QueryScope scope = new BoardQueryService.QueryScope(legRequest);
            String provider = text(first, 'dataProvider');
            BoardChartQuery.ChartResult legResult;
            if (provider == null) {
                legResult = BoardQueryService.scanPartials(scope, legRequest, true);
            } else {
                legRequest.put('dataProvider', provider);
                legResult = BoardDataProviders.scanCrossObject(scope, legRequest, sourceSlots[0].measureIndex());
            }
            leg.rows = legResult.accumulator.rows;
            leg.valueTypes = legResult.valueTypes;
            leg.appliedFilterIds = legResult.appliedFilterIds;
            leg.ignoredFilterIds = legResult.ignoredFilterIds;
            leg.hasMoreGroups = legResult.hasMoreGroups;
        } catch (BoardErrors.BoardException failure) {
            if (failure.category != BoardErrors.ACCESS_ERROR) {
                throw failure;
            }
            leg.blank(failure.getMessage());
        } catch (System.QueryException failure) {
            // USER_MODE rejects a field the viewer can't read.
            if (!failure.getMessage().containsIgnoreCase('inaccessible')) {
                throw failure;
            }
            leg.blank('You do not have access to some fields of ' + leg.sourceObject + '.');
        }
        return leg;
    }

    /**
     * The request's filters (as the Widget resolved them) bound to the source object: the Measure's own Filter
     * bindings first, else by convention where the filter's field exists on the source object (`fieldApiName`,
     * `OwnerId` for a user filter), else the lookup convention resolved by the query scope. Unbound filters end up in
     * the scope's ignored filter ids.
     */
    private static List<Object> rebindFilters(
        Map<String, Object> request,
        Map<String, Object> measure,
        Schema.DescribeSObjectResult source
    ) {
        Map<String, Object> bindings = measure.get('filterBindings') instanceof Map<String, Object>
            ? (Map<String, Object>) measure.get('filterBindings')
            : new Map<String, Object>();
        Map<String, Schema.SObjectField> sourceFields = source.fields.getMap();
        List<Object> rebound = new List<Object>();
        Object rawFilters = request.get('filters');
        for (Object raw : rawFilters instanceof List<Object> ? (List<Object>) rawFilters : new List<Object>()) {
            if (!(raw instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> filter = new Map<String, Object>((Map<String, Object>) raw);
            String filterId = text(filter, 'filterId');
            Boolean isSearch = 'SOSL'.equalsIgnoreCase(text(filter, 'operator'));
            filter.put('explicit', false);
            if (filterId != null && bindings.containsKey(filterId)) {
                Object binding = bindings.get(filterId);
                String path = binding == null ? null : String.valueOf(binding).trim();
                if (String.isBlank(path) || path.equalsIgnoreCase(IGNORE_BINDING)) {
                    filter.put('fieldPath', IGNORE_BINDING);
                } else {
                    filter.put('fieldPath', path);
                    filter.put('explicit', true);
                    if (isSearch) {
                        filter.put('operator', 'CONTAINS');
                    }
                }
                rebound.add(filter);
                continue;
            }
            String conventionField = text(filter, 'fieldApiName');
            if (conventionField == null && 'USER'.equalsIgnoreCase(text(filter, 'type'))) {
                conventionField = 'OwnerId';
            }
            if (conventionField != null && sourceFields.containsKey(conventionField.toLowerCase())) {
                filter.put('fieldPath', sourceFields.get(conventionField.toLowerCase()).getDescribe().getName());
                if (isSearch) {
                    filter.put('operator', 'CONTAINS');
                }
            } else {
                // No field of that name: only the lookup convention can bind it; a text search never spans objects.
                filter.put('fieldPath', isSearch ? IGNORE_BINDING : null);
            }
            rebound.add(filter);
        }
        return rebound;
    }

    /** Cross-object measures with equal keys run as one query; one with a Data provider runs on its own. */
    private static String sourceKey(Slot slot) {
        Map<String, Object> measure = slot.measure;
        return JSON.serialize(
            new List<Object>{
                text(measure, 'sourceObject') == null ? '' : text(measure, 'sourceObject').toLowerCase(),
                text(measure, 'categoryMapping'),
                text(measure, 'panelMapping'),
                measure.get('filterBindings'),
                text(measure, 'dataProvider') == null ? null : slot.position
            }
        );
    }

    private static Object emptyValue(String aggregateFunction) {
        return aggregateFunction == 'COUNT' ? 0 : null;
    }

    /** A Panel value's key in Panel totals (as `BoardChartPanelTotals` keys them). */
    private static String panelKeyOf(String panelValue) {
        return panelValue == null ? BoardChartEngine.BLANK_KEY : panelValue;
    }

    /** The join key: Panel value (Small multiples, else null) and category value. */
    private static String rowKey(String panelValue, String categoryValue) {
        return JSON.serialize(new List<String>{ panelValue, categoryValue });
    }

    private static String text(Map<String, Object> source, String key) {
        Object value = source == null ? null : source.get(key);
        return value == null || String.isBlank(String.valueOf(value)) ? null : String.valueOf(value).trim();
    }

    private static BoardErrors.BoardException configError(String message) {
        return BoardErrors.error(BoardErrors.CONFIG_ERROR, message, null, 'measures');
    }

    /** One Cross-object measure: its position in the attached Measures, and its source's query once run. */
    private class Slot {
        Integer position;
        Map<String, Object> measure;
        String aggregateFunction;
        String valueType;
        Leg leg;
        /** This Measure's index among its source's queried Measures. */
        Integer legIndex = 0;

        Slot(Integer position, Map<String, Object> measure) {
            this.position = position;
            this.measure = measure;
            String raw = text(measure, 'aggregateFunction');
            aggregateFunction = raw == null ? 'COUNT' : raw.toUpperCase();
        }

        /** This Measure's value over every row of its source (merged partials); blank when it can't be read. */
        Decimal total(Boolean includeBlank) {
            if (leg.rows == null) {
                return null;
            }
            BoardChartEngine.Partial merged = new BoardChartEngine.Partial();
            for (BoardChartEngine.GroupedRow row : leg.rows) {
                if (row.categoryValue == null && !includeBlank) {
                    continue;
                }
                merged.combine(row.partials[legIndex]);
            }
            return merged.value(aggregateFunction);
        }

        /** Panel keys (Small multiples; `BoardChartEngine.BLANK_KEY` for none) this Measure has rows in. */
        Set<String> panelKeys(Boolean includeBlank) {
            Set<String> keys = new Set<String>();
            for (
                BoardChartEngine.GroupedRow row : leg.rows == null ? new List<BoardChartEngine.GroupedRow>() : leg.rows
            ) {
                if (row.panelValue != null || includeBlank) {
                    keys.add(panelKeyOf(row.panelValue));
                }
            }
            return keys;
        }

        /** This Measure's value over its rows in the Panel of `panelKey`; blank when it can't be read. */
        Decimal panelTotal(String panelKey, Boolean includeBlank) {
            if (leg.rows == null) {
                return null;
            }
            BoardChartEngine.Partial merged = new BoardChartEngine.Partial();
            for (BoardChartEngine.GroupedRow row : leg.rows) {
                if ((row.categoryValue == null && !includeBlank) || !panelKeyOf(row.panelValue).equals(panelKey)) {
                    continue;
                }
                merged.combine(row.partials[legIndex]);
            }
            return merged.value(aggregateFunction);
        }

        /** The Measure's index in the Widget's Measures list. */
        Integer measureIndex() {
            Object rawIndex = measure.get(INDEX_KEY);
            return rawIndex == null ? position : (Integer) rawIndex;
        }

        Notice toNotice() {
            Notice result = new Notice();
            result.measureIndex = measureIndex();
            result.sourceObject = leg.sourceObject;
            result.appliedFilterIds = new List<String>(leg.appliedFilterIds);
            result.ignoredFilterIds = new List<String>(leg.ignoredFilterIds);
            result.isBlank = leg.rows == null;
            result.message = leg.message;
            return result;
        }
    }

    /** One Cross-object source's query: grouped partials (one per queried Measure), or why it is blank. */
    private class Leg {
        String sourceObject;
        List<BoardChartEngine.GroupedRow> rows;
        List<String> valueTypes;
        List<String> appliedFilterIds = new List<String>();
        List<String> ignoredFilterIds = new List<String>();
        Boolean hasMoreGroups = false;
        String message;

        void blank(String reason) {
            rows = null;
            message = reason;
        }
    }

    /**
     * What happened to one Cross-object measure: the filters it applied and ignored (the Widget lists the ignored ones
     * as a warning), and whether it is blank because the viewer can't access its object or fields (`message`).
     */
    public class Notice {
        /** The Measure's index in the Widget's Measures list. */
        @AuraEnabled
        public Integer measureIndex;
        @AuraEnabled
        public String sourceObject;
        @AuraEnabled
        public List<String> appliedFilterIds = new List<String>();
        @AuraEnabled
        public List<String> ignoredFilterIds = new List<String>();
        @AuraEnabled
        public Boolean isBlank = false;
        @AuraEnabled
        public String message;
    }
}