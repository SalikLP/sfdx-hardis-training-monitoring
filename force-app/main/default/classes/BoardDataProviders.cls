/**
 * Data provider dispatch for Metric and Chart widgets whose request names a `dataProvider` class, and for a
 * Cross-object measure naming one (`scanCrossObject`, called by `BoardCrossObjectMeasures`).
 *
 * Resolves the class (a missing class, or one not implementing `BoardDataProvider`, is a `CONFIG_ERROR`), compiles the
 * Widget's scope with `BoardQueryService.QueryScope`, hands the provider a `BoardDataProviderRequest` built from the
 * scope's condition tree, and merges the returned partial buckets (with the standard leg when the provider asks for
 * it) into the grouped rows the Widget shapes. `COUNT_DISTINCT` Measures can't merge and are rejected up front.
 *
 * Cursor tier hand-off: when the standard leg spans more rows than one SOQL aggregate reads, it opens the cursor tier
 * like any Widget. The provider is still called once, on the first call; its buckets come back as one more partial
 * chunk merged into that first response, and chunk continuations (`fetchChartChunk`, `fetchAggregateChunk`) never
 * reach this class.
 */
public with sharing class BoardDataProviders {
    private static final String CONFIG_KEY = 'dataProvider';
    private static final String RECORD_CONTEXT_TYPE = 'RECORD_CONTEXT';

    /** True when the Widget request names a Data provider. */
    public static Boolean isNamed(Map<String, Object> request) {
        return String.isNotBlank(BoardQueryService.getString(request, CONFIG_KEY));
    }

    /**
     * A Chart widget's grouped rows from its Data provider, unshaped (see `BoardChartQuery`). With Small multiples the
     * Panel field is one more grouping of the provider's buckets.
     */
    public static BoardChartQuery.ChartResult scanChart(Map<String, Object> request) {
        if (BoardChartQuery.hasPanelField(request)) {
            Boolean bucketGrouping =
                BoardBucketField.referencedId(BoardQueryService.getString(request, 'panelField')) != null ||
                BoardBucketField.referencedId(BoardQueryService.getString(request, 'groupByField')) != null ||
                BoardBucketField.referencedId(BoardQueryService.getString(request, 'stackByField')) != null;
            if (bucketGrouping) {
                throw configError(
                    'Small multiples with a Data provider cannot be grouped, split or panelled by a Bucket field yet.',
                    'panelField'
                );
            }
        }
        BoardQueryService.QueryScope scope = new BoardQueryService.QueryScope(request);
        return run(scope, request, 'chart', true, 0);
    }

    /**
     * One Cross-object measure's grouped partials from the Data provider it names: `request` is that Measure's leg
     * request (its source object, the category and panel mappings as grouping, Filter context after its Filter
     * bindings, the one Measure), `scope` compiled from it. Ungrouped (no `groupByField`) on a Metric widget. The
     * standard leg (`includeStandardResult`) never opens the cursor tier. `measureIndex` is the Measure's place in the
     * Widget, for error messages.
     */
    public static BoardChartQuery.ChartResult scanCrossObject(
        BoardQueryService.QueryScope scope,
        Map<String, Object> request,
        Integer measureIndex
    ) {
        String widgetType = String.isBlank(BoardQueryService.getString(request, 'groupByField')) ? 'metric' : 'chart';
        return run(scope, request, widgetType, false, measureIndex);
    }

    /** A Metric widget's value from its Data provider: its visible Measure merged over every bucket. */
    public static BoardQueryService.MetricResult queryMetric(Map<String, Object> request) {
        Integer visible = BoardMetricQuery.visibleMeasureIndex(request);
        Map<String, Object> chartRequest = metricAsChart(request);
        BoardQueryService.QueryScope scope = new BoardQueryService.QueryScope(chartRequest);
        BoardChartQuery.ChartResult merged = run(scope, chartRequest, 'metric', true, 0);
        String aggregateFunction = merged.aggregateFunctions[visible];
        BoardQueryService.MetricResult result = new BoardQueryService.MetricResult(aggregateFunction, scope);
        result.valueType = merged.valueTypes[visible];
        result.totalRows = merged.totalRows;
        result.appliedFilterIds = merged.appliedFilterIds;
        result.ignoredFilterIds = merged.ignoredFilterIds;
        BoardChartEngine.Partial total = new BoardChartEngine.Partial();
        for (BoardChartEngine.GroupedRow row : merged.accumulator.rows) {
            total.combine(row.partials[visible]);
        }
        if (merged.isComplete) {
            result.value = total.value(aggregateFunction);
            return result;
        }
        // First cursor chunk: the standard rows read so far plus the provider's partial, merged by the client.
        BoardChartEngine.Partial bucket = new BoardChartEngine.Partial();
        bucket.sum = total.sum;
        bucket.count = total.count;
        bucket.min = total.min;
        bucket.max = total.max;
        BoardQueryService.AggregateChunk chunk = new BoardQueryService.AggregateChunk();
        chunk.cursor = merged.cursor;
        chunk.offset = 0;
        chunk.nextOffset = merged.nextOffset;
        chunk.totalRows = merged.totalRows;
        chunk.isComplete = false;
        chunk.buckets = new List<BoardChartEngine.Partial>{ bucket };
        result.mode = merged.mode;
        result.isComplete = false;
        result.chunk = chunk;
        return result;
    }

    /** Engine helper behind `BoardDataProviderRequest.runStandardQuery`: the standard query's buckets for `query`. */
    public static List<BoardDataProviderResult.Bucket> standardBuckets(Map<String, Object> query) {
        return standardBuckets(query, null);
    }

    /**
     * `standardBuckets` with the queries and counts run by `executor` (e.g. system mode for the Quota provider; null
     * for USER_MODE). Never opens the cursor tier.
     */
    public static List<BoardDataProviderResult.Bucket> standardBuckets(
        Map<String, Object> query,
        BoardQueryService.QueryExecutor executor
    ) {
        Map<String, Object> request = query == null ? new Map<String, Object>() : query.clone();
        request.remove(CONFIG_KEY);
        if (!request.containsKey('measures')) {
            request = metricAsChart(request);
        }
        BoardQueryService.QueryScope scope = new BoardQueryService.QueryScope(request);
        scope.executor = executor;
        BoardChartQuery.ChartResult standard = BoardQueryService.scanPartials(scope, request, true);
        List<BoardDataProviderResult.Bucket> buckets = new List<BoardDataProviderResult.Bucket>();
        for (BoardChartEngine.GroupedRow row : standard.accumulator.rows) {
            BoardDataProviderResult.Bucket bucket = new BoardDataProviderResult.Bucket(
                row.categoryValue,
                row.categoryLabel,
                row.seriesValue,
                row.seriesLabel
            );
            bucket.panelValue = row.panelValue;
            bucket.panelLabel = row.panelLabel;
            for (BoardChartEngine.Partial partial : row.partials) {
                bucket.measures.add(
                    new BoardDataProviderResult.Partial(partial.sum, partial.count, partial.min, partial.max)
                );
            }
            buckets.add(bucket);
        }
        return buckets;
    }

    /**
     * Calls the provider once and merges its buckets (with the standard leg when asked; `allowCursor` lets that leg
     * open the cursor tier). `measureOffset` shifts Measure numbers in error messages (a Cross-object measure's leg).
     */
    private static BoardChartQuery.ChartResult run(
        BoardQueryService.QueryScope scope,
        Map<String, Object> request,
        String widgetType,
        Boolean allowCursor,
        Integer measureOffset
    ) {
        String className = BoardQueryService.getString(request, CONFIG_KEY).trim();
        BoardDataProvider provider = instantiate(className);
        // Header only (groups, Measures): validates the config, incl. unmergeable Measures, before the provider runs.
        BoardChartQuery.ChartResult result = BoardQueryService.scanPartials(scope, request, false);
        Integer measureCount = result.aggregateFunctions.size();

        BoardDataProviderResult supplied = provider.provide(buildRequest(scope, request, widgetType, result));
        if (supplied == null) {
            supplied = new BoardDataProviderResult();
        }
        for (Integer index : supplied.rejectedMeasures.keySet()) {
            String reason = supplied.rejectedMeasures.get(index);
            throw configError(
                'Data provider ' +
                    className +
                    ' can\'t supply Measure ' +
                    (index == null ? '?' : String.valueOf(index + measureOffset + 1)) +
                    (String.isBlank(reason) ? '.' : ': ' + reason),
                'measures'
            );
        }

        if (supplied.includeStandardResult == true) {
            // Above the single-query threshold this is the first cursor chunk; the provider buckets join it below.
            result = BoardQueryService.scanPartials(scope, request, true, allowCursor);
        }
        List<BoardDataProviderResult.Bucket> buckets = supplied.buckets == null
            ? new List<BoardDataProviderResult.Bucket>()
            : supplied.buckets;
        for (BoardDataProviderResult.Bucket bucket : buckets) {
            if (bucket == null) {
                continue;
            }
            if (bucket.measures == null || bucket.measures.size() != measureCount) {
                throw configError(
                    'Data provider ' +
                        className +
                        ' returned a bucket without one value per Measure (' +
                        measureCount +
                        ' expected).',
                    'measures'
                );
            }
            List<BoardChartEngine.Partial> partials = new List<BoardChartEngine.Partial>();
            for (BoardDataProviderResult.Partial supplier : bucket.measures) {
                BoardChartEngine.Partial partial = new BoardChartEngine.Partial();
                if (supplier != null) {
                    partial.sum = supplier.sum == null ? 0 : supplier.sum;
                    partial.count = supplier.count == null ? 0 : supplier.count;
                    partial.min = supplier.min;
                    partial.max = supplier.max;
                }
                partials.add(partial);
            }
            result.accumulator.addPartials(
                bucket.panelValue,
                bucket.panelLabel,
                bucket.categoryValue,
                bucket.categoryLabel,
                bucket.seriesValue,
                bucket.seriesLabel,
                partials
            );
        }
        reportFilters(result, supplied);
        return result;
    }

    /** The provider's applied / ignored filter ids override the scope's own classification of those ids. */
    private static void reportFilters(BoardChartQuery.ChartResult result, BoardDataProviderResult supplied) {
        Set<String> providerApplied = new Set<String>(
            supplied.appliedFilterIds == null ? new List<String>() : supplied.appliedFilterIds
        );
        Set<String> providerIgnored = new Set<String>(
            supplied.ignoredFilterIds == null ? new List<String>() : supplied.ignoredFilterIds
        );
        List<String> applied = new List<String>();
        List<String> ignored = new List<String>();
        List<String> candidates = new List<String>();
        candidates.addAll(result.appliedFilterIds);
        candidates.addAll(result.ignoredFilterIds);
        candidates.addAll(providerApplied);
        candidates.addAll(providerIgnored);
        Set<String> scopeApplied = new Set<String>(result.appliedFilterIds);
        Set<String> seen = new Set<String>();
        for (String filterId : candidates) {
            if (!seen.add(filterId)) {
                continue;
            }
            Boolean isApplied = providerIgnored.contains(filterId)
                ? false
                : providerApplied.contains(filterId) || scopeApplied.contains(filterId);
            if (isApplied) {
                applied.add(filterId);
            } else {
                ignored.add(filterId);
            }
        }
        result.appliedFilterIds = applied;
        result.ignoredFilterIds = ignored;
    }

    private static BoardDataProvider instantiate(String className) {
        Type providerType;
        try {
            providerType = Type.forName(className);
        } catch (Exception invalidName) {
            providerType = null;
        }
        if (providerType == null) {
            throw configError('Data provider class not found: ' + className + '.', CONFIG_KEY);
        }
        Object instance;
        try {
            instance = providerType.newInstance();
        } catch (Exception notConstructible) {
            instance = null;
        }
        if (!(instance instanceof BoardDataProvider)) {
            throw configError(
                'Data provider class ' +
                    className +
                    ' must implement BoardDataProvider and have a public no-argument constructor.',
                CONFIG_KEY
            );
        }
        return (BoardDataProvider) instance;
    }

    private static BoardDataProviderRequest buildRequest(
        BoardQueryService.QueryScope scope,
        Map<String, Object> request,
        String widgetType,
        BoardChartQuery.ChartResult header
    ) {
        BoardDataProviderRequest providerRequest = new BoardDataProviderRequest();
        providerRequest.widgetType = widgetType;
        providerRequest.objectApiName = scope.objectDescribe.getName();
        providerRequest.groupByField = header.groupBy == null ? null : header.groupBy.fieldPath;
        providerRequest.dateGranularity = header.groupBy == null ? null : header.groupBy.dateGranularity;
        providerRequest.seriesField = header.stackBy == null ? null : header.stackBy.fieldPath;
        providerRequest.panelField = header.panelBy == null ? null : header.panelBy.fieldPath;
        providerRequest.panelDateGranularity = header.panelBy == null ? null : header.panelBy.dateGranularity;
        providerRequest.query = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(request));
        providerRequest.displayCurrency = BoardCurrencyConverter.forRequest().displayIsoCode(request);

        Map<String, String> filterTypes = new Map<String, String>();
        for (Object rawFilter : BoardQueryService.getList(request, 'filters')) {
            Map<String, Object> filter = BoardQueryService.asMap(rawFilter);
            String filterType = BoardQueryService.getString(filter, 'type');
            filterTypes.put(
                BoardQueryService.getString(filter, 'filterId'),
                filterType == null ? '' : filterType.toUpperCase()
            );
        }
        for (BoardCondition.Node node : scope.conditions.children) {
            String filterId = firstFilterId(node);
            BoardDataProviderRequest.Condition condition = toCondition(node);
            if (!filterTypes.containsKey(filterId)) {
                providerRequest.baseFilters.add(condition);
            } else if (filterTypes.get(filterId) == RECORD_CONTEXT_TYPE) {
                providerRequest.recordContext.add(condition);
            } else {
                providerRequest.filters.add(condition);
            }
        }

        List<Object> rawMeasures = BoardQueryService.getList(request, 'measures');
        for (Integer i = 0; i < header.aggregateFunctions.size(); i++) {
            Map<String, Object> rawMeasure = i < rawMeasures.size()
                ? BoardQueryService.asMap(rawMeasures[i])
                : new Map<String, Object>();
            BoardDataProviderRequest.Measure measure = new BoardDataProviderRequest.Measure();
            measure.index = i;
            measure.aggregateFunction = header.aggregateFunctions[i];
            measure.valueFieldApiName = measure.aggregateFunction == 'COUNT'
                ? null
                : BoardQueryService.getString(rawMeasure, 'valueFieldApiName');
            measure.label = BoardQueryService.getString(rawMeasure, 'label');
            BoardCondition.Node condition = scope.measureConditionNode(rawMeasure.get('condition'));
            measure.condition = condition == null ? null : toCondition(condition);
            providerRequest.measures.add(measure);
        }
        return providerRequest;
    }

    /** The filter id of a scope node: its first condition's (a group's conditions share one filter or Base filter). */
    private static String firstFilterId(BoardCondition.Node node) {
        if (node instanceof BoardCondition.Predicate) {
            return ((BoardCondition.Predicate) node).filterId;
        }
        if (node instanceof BoardBucketField.Selection) {
            return ((BoardBucketField.Selection) node).filterId;
        }
        for (BoardCondition.Node child : ((BoardCondition.Junction) node).children) {
            String filterId = firstFilterId(child);
            if (filterId != null) {
                return filterId;
            }
        }
        return null;
    }

    private static BoardDataProviderRequest.Condition toCondition(BoardCondition.Node node) {
        BoardDataProviderRequest.Condition condition = new BoardDataProviderRequest.Condition();
        if (node instanceof BoardCondition.Predicate) {
            BoardCondition.Predicate predicate = (BoardCondition.Predicate) node;
            condition.filterId = predicate.filterId;
            condition.path = predicate.path;
            condition.operator = predicate.operator;
            condition.values = new List<Object>(predicate.values);
            return condition;
        }
        if (node instanceof BoardBucketField.Selection) {
            // A Bucket filter: `bucket:<id> IN (selected labels)`.
            BoardBucketField.Selection selection = (BoardBucketField.Selection) node;
            condition.filterId = selection.filterId;
            condition.path = BoardBucketField.REFERENCE_PREFIX + selection.bucketField.id;
            condition.operator = 'IN';
            condition.values = new List<Object>();
            for (String label : selection.labels()) {
                condition.values.add(label);
            }
            return condition;
        }
        BoardCondition.Junction junction = (BoardCondition.Junction) node;
        condition.logic = junction.logic;
        condition.filterId = firstFilterId(junction);
        for (BoardCondition.Node child : junction.children) {
            condition.children.add(toCondition(child));
        }
        return condition;
    }

    /** A Metric request as a one-Measure, ungrouped Chart request (`measures` kept when the Widget sends them). */
    private static Map<String, Object> metricAsChart(Map<String, Object> request) {
        Map<String, Object> chartRequest = request.clone();
        if (!chartRequest.containsKey('measures')) {
            chartRequest.put(
                'measures',
                new List<Object>{
                    new Map<String, Object>{
                        'aggregateFunction' => request.get('aggregateFunction'),
                        'valueFieldApiName' => request.get('valueFieldApiName')
                    }
                }
            );
        }
        chartRequest.remove('groupByField');
        chartRequest.remove('stackByField');
        return chartRequest;
    }

    private static BoardErrors.BoardException configError(String message, String fieldPath) {
        return BoardErrors.error(BoardErrors.CONFIG_ERROR, message, null, fieldPath);
    }
}