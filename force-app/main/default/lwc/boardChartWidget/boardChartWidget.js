import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import getObjectFields from '@salesforce/apex/BoardSchemaService.getObjectFields';
import queryChart from '@salesforce/apex/BoardChartQuery.queryChart';
import fetchChartChunk from '@salesforce/apex/BoardChartQuery.fetchChartChunk';
import {
    parseAndMergeConfig,
    normalizeBoardError,
    resolveFilterBindings,
    applyServerIgnoredFilters,
    buildFilterBindingSummary,
    buildQuerySignature,
    formatValue
} from 'c/boardConfigUtils';
import {
    subscribeFilterContext,
    publishFilterContext,
    acceptExternalFilterContext,
    getDisplayCurrency,
    getConfigCurrency,
    getBoardBucketFields
} from 'c/boardContextStore';
import { displayCurrencyFormat } from 'c/boardDisplayCurrency';
import { waitsForFilterWidget, waitingForBoardId, perRecordSettings } from 'c/boardConfigUtils';
import {
    loadChartJs,
    resolveChartTheme,
    matchesMediaQuery,
    watchMediaQuery,
    watchColorScheme,
    chartAnimation,
    createBarDataLabelsPlugin,
    computeScrollLayout,
    chartTypeScrolls,
    chartTypeIsSingleMeasure,
    chartTypeHasSetting,
    visibleCategoryWindow,
    buildChartConfig,
    applyChartConfig,
    PREFERS_REDUCED_MOTION_QUERY
} from 'c/boardChartUtils';
import { REFERENCE_LINE_RENDER, withReferenceLines } from 'c/boardChartReferenceLines';
import { runCursorLoad } from 'c/boardCursorProgress';
import { createHiddenDeferral } from 'c/boardVisibilityWatcher';
import {
    bucketIdOf,
    bucketReference,
    findBucketField,
    resolveReferencedBucketFields,
    unknownBucketFieldMessage
} from 'c/boardBucketFields';
import { SHOW_AS_VALUE, normalizeBarSettings, normalizeMeasures, buildChartModel } from './chartModel';
import { applyBucketRuleColours, applyFixedColours } from 'c/boardChartColours';
import { crossObjectNotices, crossObjectRequestFields } from 'c/boardCrossObjectMeasure';
import {
    isPanelResult,
    normalizePanelSettings,
    panelRequestFields,
    panelSlice,
    panelTotalsOf
} from 'c/boardChartPanels';

const AGGREGATE_LABELS = {
    COUNT_DISTINCT: 'Unique count',
    SUM: 'Sum',
    AVG: 'Average',
    AVG_PER: 'Average per record',
    MIN: 'Min',
    MAX: 'Max'
};
const NO_VALUE = '—';
/** How a config key that may reference a Bucket field is named in messages. */
const BUCKET_REFERENCE_LABELS = { groupByField: 'Group by', stackByField: 'Stack by', panelField: 'Panel field' };
const CHART_LOAD_ERROR = {
    category: 'QUERY_ERROR',
    message: 'The chart library could not be loaded.',
    filterId: null,
    fieldPath: null,
    retryable: true
};
let widgetInstanceCount = 0;

export default class BoardChartWidget extends LightningElement {
    _boardId = 'default';
    _boardIdExplicitlySet = false;
    _livePreview = false;
    _title = '';
    _objectApiName = '';
    _recordId = '';
    _filterContextJson = '';
    /** A Flow `filterContextJson` input received before connect; handed to the store in `connectedCallback`. */
    _pendingExternalJson = '';
    _configJson = '';

    filterContext = null;
    widgetRefreshToken = 0;

    /** Last server-shaped `BoardChartQuery.ChartResult` (categories, series, points, progress). */
    barData = null;
    /** Rendered model derived from `barData` and the display settings (see `chartModel.buildChartModel`). */
    chartModel = null;
    /** Small multiples: `[{ key, label, model }]`, one rendered model per Panel; null without a Panel field. */
    panelModels = null;
    /** Bumped whenever the Panels must be redrawn (data, display settings, theme). */
    panelDrawVersion = 0;
    queryError = null;
    chartLoadError = null;
    isQuerying = false;
    /** Cursor-tier progress `{ percent, label, ... }` while a large scope loads; null otherwise. */
    _cursorProgress = null;
    showTable = false;
    bindingApplied = [];
    bindingIgnored = [];
    /** `ignoredFilterIds` of the last completed query, re-applied after every client-side binding resolve. */
    _serverIgnoredIds = [];

    _latestRequestId = 0;
    _lastQuerySignature = null;
    _fieldsByObject = new Map();
    _fieldLabels = new Map();
    _widgetId = `boardChartWidget-${++widgetInstanceCount}`;
    _unsubscribe = null;
    _refreshHandlerId = null;
    _isConnected = false;

    _Chart = null;
    _chart = null;
    /** Chart type `_chart` was created with. */
    _chartType = null;
    _chartContainer = null;
    _modelVersion = 0;
    _renderedVersion = 0;
    _reducedMotion = false;
    _mediaUnsubscribers = [];
    _themeKey = null;
    /** Scroll sizing of the bars (`boardChartUtils.computeScrollLayout`), measured from the rendered scroll container. */
    _scrollLayout = null;
    _scrollOffset = 0;
    _renderedScrollKey = '';
    /** Axis the bars scroll along (`x` vertical bars, `y` horizontal bars) or '' when everything fits. */
    scrollAxis = '';
    scrollContentPx = 0;
    _dataLabelsPlugin = createBarDataLabelsPlugin((value, measureIndex) =>
        this.formatMeasure(value, 'standard', measureIndex)
    );

    /** Setup dialog live preview: never waits for the Filter widget, whatever the config says. */
    @api
    get livePreview() {
        return this._livePreview;
    }
    set livePreview(value) {
        this._livePreview = Boolean(value);
        if (this._isConnected) {
            this.setupSubscription();
        }
    }

    @api
    get boardId() {
        return this.effectiveBoardId;
    }
    set boardId(value) {
        if (value !== undefined && value !== null && String(value).trim()) {
            this._boardId = String(value).trim();
            this._boardIdExplicitlySet = true;
        } else {
            this._boardId = 'default';
            this._boardIdExplicitlySet = false;
        }
        if (this._isConnected) {
            this.setupSubscription();
        }
    }

    @api
    get title() {
        return this._title;
    }
    set title(value) {
        this._title = value || '';
    }

    @api
    get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(value) {
        this._objectApiName = value || '';
        if (this._isConnected) {
            this.requestQuery();
        }
    }

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value || '';
        if (this._isConnected) {
            this.setupSubscription();
        }
    }

    @api
    get filterContextJson() {
        return this._filterContextJson;
    }
    /**
     * Reactive Flow input: handed to the Board context store, which checks scope and precedence before publishing.
     * The widget's own `filterContext` only ever comes from the store subscription.
     */
    set filterContextJson(value) {
        const json = value || '';
        if (json === this._filterContextJson) {
            return;
        }
        this._filterContextJson = json;
        if (!json) {
            return;
        }
        if (this._isConnected) {
            this.acceptExternalContext(json);
        } else {
            this._pendingExternalJson = json;
        }
    }

    @api
    get configJson() {
        return this._configJson;
    }
    set configJson(value) {
        this._configJson = value || '';
        // Display-only settings (legend, stacking, Measure labels and formats...) re-render cached data; settings the
        // server shapes with (sorting, max categories...) change the query signature and re-query.
        this.rebuildModel();
        if (this._isConnected) {
            this.setupSubscription();
        }
    }

    connectedCallback() {
        this._isConnected = true;
        this._hiddenDeferral = createHiddenDeferral(this.template.host, () => this.handleShownStale());
        this._reducedMotion = matchesMediaQuery(PREFERS_REDUCED_MOTION_QUERY);
        this._mediaUnsubscribers = [
            watchMediaQuery(PREFERS_REDUCED_MOTION_QUERY, (matches) => {
                this._reducedMotion = matches;
            }),
            watchColorScheme(() => this.rethemeChart())
        ];
        this.loadChartLibrary();
        this.setupSubscription();
        if (this._pendingExternalJson) {
            const pending = this._pendingExternalJson;
            this._pendingExternalJson = '';
            this.acceptExternalContext(pending);
        }
        try {
            this._refreshHandlerId = registerRefreshHandler(this.template.host, () => this.handleRefresh());
        } catch (e) {
            // Ignore in environments without refresh service
        }
    }

    disconnectedCallback() {
        this._isConnected = false;
        this._latestRequestId += 1;
        this._lastQuerySignature = null;
        this.isQuerying = false;
        this._hiddenDeferral?.dispose();
        this.teardownSubscription();
        this._mediaUnsubscribers.forEach((unsubscribe) => unsubscribe());
        this._mediaUnsubscribers = [];
        this.destroyChart();
        if (this._refreshHandlerId) {
            try {
                unregisterRefreshHandler(this._refreshHandlerId);
            } catch (e) {
                // Ignore
            }
            this._refreshHandlerId = null;
        }
    }

    renderedCallback() {
        this.syncChart();
    }

    setupSubscription() {
        this.teardownSubscription();
        const effectiveBoardId = this.effectiveBoardId;
        this._unsubscribe = subscribeFilterContext(
            effectiveBoardId,
            this._recordId,
            (ctx) => {
                this.filterContext = ctx;
                this.syncContextOutput(ctx);
                this.requestQuery();
            },
            { waitForFilterWidget: waitsForFilterWidget(this.resolvedConfig.config, this._livePreview) }
        );
        this.requestQuery();
    }

    /** Hands a Flow input to the store; a rejected input re-echoes the Board's actual context to the Flow output. */
    acceptExternalContext(json) {
        if (!acceptExternalFilterContext(this.effectiveBoardId, this._recordId, json) && this.filterContext) {
            this.syncContextOutput(this.filterContext);
        }
    }

    /** Echoes the Filter context to the Flow output `filterContextJson` when it changed. */
    syncContextOutput(ctx) {
        const serialized = JSON.stringify(ctx);
        if (serialized === this._filterContextJson) {
            return;
        }
        this._filterContextJson = serialized;
        try {
            this.dispatchEvent(new FlowAttributeChangeEvent('filterContextJson', serialized));
        } catch (e) {
            // Ignore outside Flow
        }
    }

    teardownSubscription() {
        if (this._unsubscribe) {
            this._unsubscribe();
            this._unsubscribe = null;
        }
    }

    // -----------------------------------------------------------------------------------------------------
    // Query lifecycle
    // -----------------------------------------------------------------------------------------------------

    /** Describe per object, re-fetched when the Board `refreshToken` changes (it busts the cacheable Apex result). */
    loadFields(objectApiName, refreshToken) {
        const key = `${objectApiName}::${refreshToken}`;
        if (!this._fieldsByObject.has(key)) {
            const pending = Promise.resolve(getObjectFields({ objectApiName, refreshToken })).catch((error) => {
                this._fieldsByObject.delete(key);
                throw error;
            });
            this._fieldsByObject.set(key, pending);
        }
        return this._fieldsByObject.get(key);
    }

    /** Resolves bindings and fires `queryChart` unless the effective-query signature is unchanged. */
    async requestQuery() {
        const initial = this.resolvedConfig;
        if (initial.error || this.isUnconfigured || this.filterContext?.status !== 'READY') {
            return;
        }
        const objectApiName = initial.config.objectApiName;
        let fields;
        try {
            fields = await this.loadFields(objectApiName, this.filterContext.refreshToken || 0);
        } catch (error) {
            if (objectApiName === this.effectiveObjectApiName) {
                this._latestRequestId += 1;
                this._lastQuerySignature = null;
                this.isQuerying = false;
                this.queryError = normalizeBoardError(error);
            }
            return;
        }

        // Re-read state after the describe await: config or filters may have changed meanwhile.
        const parsed = this.resolvedConfig;
        const ctx = this.filterContext;
        if (
            !this._isConnected ||
            parsed.error ||
            this.isUnconfigured ||
            parsed.config.objectApiName !== objectApiName ||
            ctx?.status !== 'READY'
        ) {
            return;
        }
        const config = parsed.config;
        this._fieldLabels = new Map((fields || []).map((field) => [field.apiName, field.label]));
        const resolution = resolveFilterBindings({
            objectApiName,
            fields,
            filterContext: ctx,
            filterBindings: config.filterBindings,
            widgetId: this._widgetId,
            bucketFields: config.bucketFields,
            boardBucketFields: getBoardBucketFields(this.effectiveBoardId)
        });
        if (resolution.error) {
            // Fail closed: an unusable explicit binding must never fall back to unfiltered bars.
            this._latestRequestId += 1;
            this._lastQuerySignature = null;
            this.isQuerying = false;
            this.queryError = normalizeBoardError(resolution.error);
            return;
        }
        // Server-ignored filters of the last completed query stay "ignored" even when the query is skipped below.
        const summary = applyServerIgnoredFilters(resolution.applied, resolution.ignored, this._serverIgnoredIds);
        this.bindingApplied = summary.applied;
        this.bindingIgnored = summary.ignored;

        const measures = normalizeMeasures(config);
        const settings = normalizeBarSettings(config);
        // Several Measures or one Measure split by a series field, never both.
        const stackByField =
            measures.length === 1 && !chartTypeIsSingleMeasure(config.chartType) ? config.stackByField || null : null;
        const buckets = resolveReferencedBucketFields(
            { ...config, stackByField },
            ['groupByField', 'stackByField', 'panelField'],
            getBoardBucketFields(this.effectiveBoardId)
        );
        if (buckets.missing.length) {
            // A Bucket field id defined neither here nor on the Board (e.g. deleted from the Filter widget).
            const { key: missingKey, id } = buckets.missing[0];
            this._latestRequestId += 1;
            this._lastQuerySignature = null;
            this.isQuerying = false;
            this.queryError = normalizeBoardError({
                category: 'CONFIG_ERROR',
                message: unknownBucketFieldMessage(BUCKET_REFERENCE_LABELS[missingKey], id),
                filterId: null,
                fieldPath: bucketReference(id),
                retryable: false
            });
            return;
        }
        const request = {
            objectApiName,
            measures: measures.map((measure) => ({
                aggregateFunction: measure.aggregateFunction,
                valueFieldApiName: measure.valueFieldApiName,
                ...perRecordSettings(measure),
                ...(measure.showAs === SHOW_AS_VALUE ? {} : { showAs: measure.showAs }),
                ...(measure.render === REFERENCE_LINE_RENDER ? { render: measure.render } : {}),
                ...(measure.condition ? { condition: measure.condition } : {}),
                ...(measure.aggregateFunction === 'FORMULA' ? { formula: measure.formula } : {}),
                ...(measure.isCurrency ? { isCurrency: true } : {}),
                ...crossObjectRequestFields(measure)
            })),
            groupByField: config.groupByField,
            dateGranularity: config.dateGranularity || null,
            stackByField,
            includeNullBucket: settings.includeNullBucket,
            sortBy: settings.sortBy,
            maxCategories: settings.maxBars,
            overflowMode: settings.overflowMode,
            maxSeries: settings.maxSeries,
            filters: resolution.filters,
            baseFilters: Array.isArray(config.baseFilters) ? config.baseFilters : [],
            bucketFields: buckets.bucketFields,
            boardBucketFields: buckets.boardBucketFields,
            displayCurrency: getDisplayCurrency(this.effectiveBoardId),
            configCurrency: getConfigCurrency(this.effectiveBoardId),
            dataProvider: config.dataProvider || null,
            ...panelRequestFields(config),
            refreshToken: ctx.refreshToken || 0,
            widgetRefreshToken: this.widgetRefreshToken
        };
        const signature = buildQuerySignature(request);
        if (signature === this._lastQuerySignature || this._hiddenDeferral?.deferIfHidden()) {
            return;
        }
        this._lastQuerySignature = signature;
        this._serverIgnoredIds = [];
        const reqId = ++this._latestRequestId;
        this._cursorProgress = null;
        this.isQuerying = true;
        try {
            const result = await queryChart({ requestJson: JSON.stringify(request) });
            if (reqId !== this._latestRequestId) {
                return;
            }
            this._serverIgnoredIds = result?.ignoredFilterIds || [];
            const withServerIgnored = applyServerIgnoredFilters(
                this.bindingApplied,
                this.bindingIgnored,
                this._serverIgnoredIds
            );
            this.bindingApplied = withServerIgnored.applied;
            this.bindingIgnored = withServerIgnored.ignored;
            await this.followCursorChunks(reqId, request, result);
            if (reqId === this._latestRequestId) {
                this.queryError = null;
            }
        } catch (error) {
            if (reqId === this._latestRequestId) {
                this._lastQuerySignature = null;
                this.queryError = normalizeBoardError(error);
            }
        } finally {
            if (reqId === this._latestRequestId) {
                this.isQuerying = false;
            }
        }
    }

    /**
     * Draws a server-shaped result. In the cursor tier, follows `fetchChartChunk` with a progress bar: each response
     * is already shaped from every row read so far (the client never merges), and only the final one is drawn.
     */
    async followCursorChunks(reqId, request, first) {
        if (!first || first.mode !== 'CURSOR' || first.isComplete !== false) {
            this.setBarData(first);
            return;
        }
        let latest = first;
        const completed = await runCursorLoad({
            first,
            isCurrent: () => reqId === this._latestRequestId,
            merge: (chunk) => {
                latest = chunk;
            },
            onProgress: (progress) => {
                this._cursorProgress = progress;
            },
            fetchNext: (chunk) =>
                fetchChartChunk({
                    requestJson: JSON.stringify({
                        ...request,
                        cursor: chunk.cursor,
                        offset: chunk.nextOffset,
                        partialState: chunk.partialState
                    })
                })
        });
        if (completed) {
            this.setBarData(latest);
        }
    }

    setBarData(result) {
        this.barData = {
            ...(result || {}),
            isComplete: result?.isComplete !== false,
            hasMoreGroups: result?.hasMoreGroups === true
        };
        this.rebuildModel();
    }

    // -----------------------------------------------------------------------------------------------------
    // Chart.js rendering
    // -----------------------------------------------------------------------------------------------------

    loadChartLibrary() {
        loadChartJs(this)
            .then((Chart) => {
                this._Chart = Chart;
                this.chartLoadError = null;
                this.syncChart();
            })
            .catch(() => {
                this.chartLoadError = CHART_LOAD_ERROR;
            });
    }

    rebuildModel() {
        const data = this.barData;
        if (!data) {
            return;
        }
        const measures = this.measures;
        const model = buildChartModel({
            result: data,
            measures,
            measureLabels: measures.map((measure, index) => this.measureLabel(index)),
            settings: this.settings
        });
        // Bucket rule colours, then Widget fixed colours (keyed by stored value), which win over them.
        const config = this.resolvedConfig.config;
        // Widget-level Bucket fields come first, so they win over a Board-level one of the same id.
        const bucketFields = [
            ...(Array.isArray(config?.bucketFields) ? config.bucketFields : []),
            ...(getBoardBucketFields(this.effectiveBoardId) || [])
        ];
        const colour = (rendered) =>
            applyFixedColours(applyBucketRuleColours(rendered, { ...config, bucketFields }), config?.fixedColours);
        this.chartModel = colour(model);
        // Small multiples: every Panel shares the categories and series, so a value keeps its colour in each.
        this.panelModels = isPanelResult(data)
            ? data.panels.map((panel) => ({
                  key: panel.key,
                  label: panel.label,
                  model: colour(
                      buildChartModel({
                          result: panelSlice(data, panel.key),
                          measures,
                          measureLabels: measures.map((measure, index) => this.measureLabel(index)),
                          settings: this.settings
                      })
                  ),
                  headline: this.panelHeadline(data, panel.key)
              }))
            : null;
        this._modelVersion += 1;
        this.panelDrawVersion += 1;
    }

    /** Small multiples: the Panel headline, e.g. `Avg Days to Close: 12.3` (its Panel total); null without one. */
    panelHeadline(result, panelKey) {
        const index = this.panelSettings.panelHeadlineMeasure;
        if (index === null || !this.measures[index]) {
            return null;
        }
        const totals = panelTotalsOf(result, panelKey);
        const value = totals ? totals[index] : null;
        return `${this.measureLabel(index)}: ${this.formatMeasure(value, 'standard', index)}`;
    }

    /** Small multiples: a fresh Chart.js config per Panel (the panel grid shares scales and lifts the legend). */
    buildPanelConfigs = () => {
        const theme = resolveChartTheme(this.template.host);
        const configs = new Map();
        (this.panelModels || []).forEach((panel) => {
            const options = {
                settings: this.settings,
                theme,
                animation: chartAnimation(this._reducedMotion),
                formatValue: (value, measureIndex) => this.formatMeasure(value, 'standard', measureIndex),
                formatTick: (value, measureIndex) => this.formatMeasure(value, 'compact', measureIndex),
                dataLabelsPlugin: this._dataLabelsPlugin,
                scroll: null,
                scrollWindow: null
            };
            const config = buildChartConfig(this.chartType, panel.model, options);
            configs.set(
                panel.key,
                chartTypeHasSetting(this.chartType, 'comboMeasures')
                    ? withReferenceLines(config, panel.model, options)
                    : config
            );
        });
        return configs;
    };

    buildChartConfig(theme = resolveChartTheme(this.template.host)) {
        this._themeKey = JSON.stringify(theme);
        const options = {
            settings: this.settings,
            theme,
            animation: chartAnimation(this._reducedMotion),
            formatValue: (value, measureIndex) => this.formatMeasure(value, 'standard', measureIndex),
            formatTick: (value, measureIndex) => this.formatMeasure(value, 'compact', measureIndex),
            dataLabelsPlugin: this._dataLabelsPlugin,
            scroll: this._scrollLayout,
            scrollWindow: this.currentScrollWindow()
        };
        const config = buildChartConfig(this.chartType, this.chartModel, options);
        return chartTypeHasSetting(this.chartType, 'comboMeasures')
            ? withReferenceLines(config, this.chartModel, options)
            : config;
    }

    /** Measures the scroll container and derives the scroll layout; updates the reactive scroll state if it changed. */
    updateScrollLayout() {
        const model = this.chartModel;
        const scrollElement = this.template.querySelector('.c-board-chart-scroll');
        const horizontal = this.settings.orientation === 'horizontal';
        const viewportPx = scrollElement ? (horizontal ? scrollElement.clientHeight : scrollElement.clientWidth) : 0;
        this._scrollLayout =
            model && chartTypeScrolls(this.chartType)
                ? computeScrollLayout({
                      categoryCount: model.categories.length,
                      seriesCount: model.series.filter((series) => series.render !== 'line').length,
                      stacked: model.isStacked,
                      viewportPx
                  })
                : null;
        const scrolls = Boolean(this._scrollLayout && this._scrollLayout.scrolls);
        if (!scrolls) {
            this._scrollOffset = 0;
        }
        this.scrollAxis = scrolls ? (horizontal ? 'y' : 'x') : '';
        this.scrollContentPx = scrolls ? this._scrollLayout.contentPx : 0;
    }

    currentScrollWindow() {
        return this._scrollLayout && this._scrollLayout.scrolls
            ? visibleCategoryWindow(this._scrollLayout, this._scrollOffset)
            : null;
    }

    /** Moves the pinned chart's category window to the scroll offset; the value axis and legend never move. */
    handleChartScroll(event) {
        const layout = this._scrollLayout;
        if (!this._chart || !layout || !layout.scrolls) {
            return;
        }
        const horizontal = this.settings.orientation === 'horizontal';
        this._scrollOffset = horizontal ? event.target.scrollTop : event.target.scrollLeft;
        const visible = visibleCategoryWindow(layout, this._scrollOffset);
        const axis = this._chart.options.scales[horizontal ? 'y' : 'x'];
        if (axis.min !== visible.min || axis.max !== visible.max) {
            axis.min = visible.min;
            axis.max = visible.max;
            this._chart.update('none');
        }
    }

    /**
     * Creates the chart once per mounted canvas container, then morphs it in place with `chart.update()`. The EMPTY
     * state keeps the container mounted (hidden), so zero rows morph the existing chart to no bars and back.
     */
    syncChart() {
        const container = this.template.querySelector('.c-board-chart-canvas');
        // Chart.js can't morph one chart type into another: a new chart type gets a new chart.
        if (this._chart && (this._chartContainer !== container || this._chartType !== this.chartType)) {
            this.destroyChart();
        }
        if (!container || !this._Chart || !this.chartModel) {
            return;
        }
        if (!this._chart && !this.chartModel.categories.length) {
            return;
        }
        this.updateScrollLayout();
        const scrollKey = `${this.scrollAxis}|${this.scrollContentPx}`;
        if (!this._chart) {
            this._renderedScrollKey = scrollKey;
            const canvas = document.createElement('canvas');
            canvas.setAttribute('role', 'img');
            canvas.setAttribute('aria-label', this.chartAriaLabel);
            container.appendChild(canvas);
            this._chart = new this._Chart(canvas, this.buildChartConfig());
            this._chartType = this.chartType;
            this._chartContainer = container;
            this._renderedVersion = this._modelVersion;
            return;
        }
        if (this._renderedVersion !== this._modelVersion || this._renderedScrollKey !== scrollKey) {
            this._renderedScrollKey = scrollKey;
            applyChartConfig(this._chart, this.buildChartConfig());
            this._chart.update();
            this._renderedVersion = this._modelVersion;
            const canvas = container.querySelector('canvas');
            if (canvas) {
                canvas.setAttribute('aria-label', this.chartAriaLabel);
            }
        }
    }

    /** Re-samples `--board-chart-*` colors after a possible color-scheme switch; repaints only when they changed. */
    rethemeChart() {
        if (this.isPanelled) {
            this.panelDrawVersion += 1;
            return;
        }
        if (!this._chart || !this.chartModel) {
            return;
        }
        const theme = resolveChartTheme(this.template.host);
        if (JSON.stringify(theme) === this._themeKey) {
            return;
        }
        applyChartConfig(this._chart, this.buildChartConfig(theme));
        this._chart.update('none');
    }

    destroyChart() {
        if (this._chart) {
            this._chart.destroy();
            this._chart = null;
        }
        if (this._chartContainer) {
            this._chartContainer.textContent = '';
            this._chartContainer = null;
        }
    }

    // -----------------------------------------------------------------------------------------------------
    // Derived state
    // -----------------------------------------------------------------------------------------------------

    get resolvedConfig() {
        return parseAndMergeConfig('chart', this._configJson, {
            boardId: this._boardIdExplicitlySet ? this._boardId : '',
            title: this._title,
            objectApiName: this._objectApiName
        });
    }

    /** No object or no group-by field yet: render the setup placeholder rather than an error. */
    get isUnconfigured() {
        const parsed = this.resolvedConfig;
        return parsed.isUnconfigured || (!parsed.error && !String(parsed.config?.groupByField || '').trim());
    }

    get settings() {
        return normalizeBarSettings(this.resolvedConfig.config || {});
    }

    /** The Widget config's Measures list (a config without one counts records). */
    get measures() {
        return normalizeMeasures(this.resolvedConfig.config || {});
    }

    get effectiveTitle() {
        return this.resolvedConfig.config?.title || 'Chart';
    }

    get effectiveObjectApiName() {
        return this.resolvedConfig.config?.objectApiName || '';
    }

    get chartType() {
        return this.resolvedConfig.config?.chartType || 'bar';
    }

    /** Bar orientation; other chart types are always laid out vertically. */
    get effectiveOrientation() {
        return this.settings.orientation;
    }

    /** Board id for the Wait for Filter widget hint card while this Widget waits, else empty. */
    get waitingBoardId() {
        return waitingForBoardId(this.resolvedConfig.config, this._livePreview, this.filterContext);
    }

    get effectiveBoardId() {
        return this.resolvedConfig.config?.boardId || this._boardId || 'default';
    }

    get subtitle() {
        return this.resolvedConfig.config?.subtitle || '';
    }

    /** Measure `index`'s label: the Admin's label, else e.g. `Record Count` or `Sum of Amount`. */
    measureLabel(index) {
        const measure = this.measures[index];
        if (!measure) {
            return '';
        }
        if (measure.label) {
            return measure.label;
        }
        const fn = measure.aggregateFunction;
        if (fn === 'COUNT') {
            return 'Record Count';
        }
        if (fn === 'FORMULA') {
            return 'Formula';
        }
        const field = measure.valueFieldApiName || '';
        return `${AGGREGATE_LABELS[fn] || fn} of ${this._fieldLabels.get(field) || field}`;
    }

    /** Every Measure's label, for the accessible chart description and table caption. */
    get measuresLabel() {
        return this.measures
            .map((measure, index) => (measure.hidden ? null : this.measureLabel(index)))
            .filter(Boolean)
            .join(', ');
    }

    get categoryHeader() {
        const path = this.barData?.groupBy?.fieldPath || this.resolvedConfig.config?.groupByField || '';
        const bucketId = bucketIdOf(path);
        if (bucketId !== null) {
            const bucketField =
                findBucketField(this.resolvedConfig.config?.bucketFields, bucketId) ||
                findBucketField(getBoardBucketFields(this.effectiveBoardId), bucketId);
            return bucketField?.label || bucketId;
        }
        const label = this._fieldLabels.get(path);
        return label ? label.replace(/ ID$/, '') : path;
    }

    get activeScopeKey() {
        return this.filterContext?.scopeKey || '';
    }

    get viewState() {
        const parsed = this.resolvedConfig;
        if (parsed.error) {
            return 'ERROR';
        }
        if (this.isUnconfigured) {
            return 'UNCONFIGURED';
        }
        if (this.filterContext?.error || this.queryError || this.chartLoadError) {
            return 'ERROR';
        }
        if (!this.chartModel) {
            return 'INITIAL_LOADING';
        }
        if (!this.chartModel.categories.length) {
            return 'EMPTY';
        }
        return 'READY';
    }

    get showWidgetState() {
        if (this.showCursorProgress && this.viewState === 'INITIAL_LOADING') {
            return false;
        }
        return this.viewState !== 'READY';
    }

    /** READY and EMPTY keep the chart body (and its canvas) mounted; EMPTY only hides it behind the state card. */
    get showChartBody() {
        const state = this.viewState;
        return state === 'READY' || state === 'EMPTY';
    }

    get isEmpty() {
        return this.viewState === 'EMPTY';
    }

    /** Small multiples: the result carries Panels. */
    get isPanelled() {
        return Boolean(this.panelModels && this.panelModels.length);
    }

    get panelSettings() {
        return normalizePanelSettings(this.resolvedConfig.config || {});
    }

    get panelGridPanels() {
        return (this.panelModels || []).map((panel) => ({
            key: panel.key,
            label: panel.label,
            headline: panel.headline
        }));
    }

    get chartLibrary() {
        return this._Chart;
    }

    /** Panels beyond max panels were cut by the server. */
    get hasCutPanels() {
        return this.isPanelled && this.barData?.cutPanels === true;
    }

    get cutPanelsMessage() {
        const hidden = Number(this.barData?.hiddenPanels) || 0;
        const more = hidden === 1 ? '1 more panel' : `${hidden} more panels`;
        return `Showing the first ${this.panelModels.length} panels: ${more} were left out. Raise the maximum panels or add filters to see them.`;
    }

    /** The server capped the grouped query (`hasMoreGroups`): bars, "Other" and totals may miss groups. */
    get hasPartialResults() {
        return this.barData?.hasMoreGroups === true && !this.isEmpty;
    }

    get errorPayload() {
        if (this.resolvedConfig.error) {
            return this.resolvedConfig.error;
        }
        if (this.filterContext?.error) {
            return normalizeBoardError(this.filterContext.error);
        }
        return this.queryError || this.chartLoadError;
    }

    get hasActiveFilters() {
        return this.bindingApplied.length > 0;
    }

    get filterBindingSummary() {
        return buildFilterBindingSummary(this.bindingApplied, this.bindingIgnored);
    }

    /** Cross-object measures that are blank (no access) or ignore some of the Board's filters. */
    get crossObjectNoticeRows() {
        const filterLabels = new Map(
            [...this.bindingApplied, ...this.bindingIgnored].map((entry) => [entry.filterId, entry.label])
        );
        return crossObjectNotices(
            this.barData?.crossObjectNotices,
            this.measures.map((measure, index) => this.measureLabel(index)),
            filterLabels
        );
    }

    get isRefreshing() {
        return this.isQuerying && Boolean(this.chartModel);
    }

    get ariaBusy() {
        return this.isQuerying ? 'true' : 'false';
    }

    get bodyClass() {
        return this.isRefreshing ? 'c-board-chart-content c-board-chart-content_refreshing' : 'c-board-chart-content';
    }

    get chartWrapperClass() {
        return this.showTable || this.isEmpty ? 'c-board-chart-wrapper slds-hide' : 'c-board-chart-wrapper';
    }

    get tableWrapperClass() {
        return this.isEmpty ? 'c-board-chart-table-wrapper slds-hide' : 'c-board-chart-table-wrapper';
    }

    /** Sets `--board-chart-height` so the narrow-card `@container` rule can still cap it. */
    get chartContainerStyle() {
        const bars = this.chartModel ? this.chartModel.categories.length : 0;
        const perBar = this.chartModel?.hasSeries && !this.chartModel.isStacked ? 2.5 : 1.75;
        const height = this.settings.orientation === 'horizontal' ? Math.min(30, Math.max(16, bars * perBar + 4)) : 18;
        return `--board-chart-height: ${height}rem;`;
    }

    get scrollStyle() {
        return this.chartContainerStyle;
    }

    /** Gives the scroll container its full length along the category axis; empty while everything fits. */
    get spacerStyle() {
        if (!this.scrollAxis) {
            return '';
        }
        return this.scrollAxis === 'y' ? `height: ${this.scrollContentPx}px;` : `width: ${this.scrollContentPx}px;`;
    }

    get tableClass() {
        return this.showTable
            ? 'slds-table slds-table_bordered slds-table_cell-buffer c-board-chart-table'
            : 'slds-assistive-text';
    }

    get toggleLabel() {
        return this.showTable ? 'View as chart' : 'View as table';
    }

    get toggleIcon() {
        return this.showTable ? 'utility:chart' : 'utility:table';
    }

    get showToggle() {
        return this.viewState === 'READY';
    }

    get chartAriaLabel() {
        const model = this.chartModel;
        if (!model) {
            return this.effectiveTitle;
        }
        return `${this.effectiveTitle}: ${this.measuresLabel} by ${this.categoryHeader}, ${model.categories.length} bars. Data table follows.`;
    }

    get tableCaption() {
        return `${this.effectiveTitle}: ${this.measuresLabel} by ${this.categoryHeader}`;
    }

    /**
     * Column headers after the category column: one per series, plus a Total for stacked/grouped series when the
     * aggregate is additive (COUNT/SUM); summing averages, minimums or maximums across series would be wrong.
     */
    get tableColumns() {
        const model = this.chartModel;
        if (!model) {
            return [];
        }
        const columns = model.series.map((series) => ({ key: `series-${series.key}`, label: series.label }));
        if (model.hasSeries && model.canRollUp) {
            columns.push({ key: 'total', label: 'Total' });
        }
        return columns;
    }

    get tableRows() {
        if (this.isPanelled) {
            // Small multiples: one row per Panel and category, labelled `Panel · Category`.
            return this.panelModels.flatMap((panel) =>
                this.tableRowsOf(panel.model).map((row) => ({
                    ...row,
                    key: `${panel.key}|${row.key}`,
                    label: `${panel.label} · ${row.label}`
                }))
            );
        }
        return this.tableRowsOf(this.chartModel);
    }

    tableRowsOf(model) {
        if (!model) {
            return [];
        }
        return model.categories.map((category, index) => {
            const values = model.series.map((series) => series.values[index]);
            const cells = values.map((value, seriesIndex) => ({
                key: `${category.key}-${model.series[seriesIndex].key}`,
                text: this.formatMeasure(value, 'standard', model.series[seriesIndex].measureIndex)
            }));
            if (model.hasSeries && model.canRollUp) {
                const present = values.filter((value) => value !== null && value !== undefined);
                cells.push({
                    key: `${category.key}-total`,
                    text: present.length ? this.formatMeasure(present.reduce((sum, value) => sum + value, 0)) : NO_VALUE
                });
            }
            return { key: category.key, label: category.label, cells };
        });
    }

    /** Progress bar state; only while the cursor tier of the latest run is loading. */
    get cursorProgress() {
        return this.isQuerying ? this._cursorProgress : null;
    }

    get showCursorProgress() {
        return Boolean(this.cursorProgress);
    }

    /** Formats a value with the number format, value type and returned currency of Measure `measureIndex`. */
    formatMeasure(value, notation = 'standard', measureIndex = 0) {
        if (value === null || value === undefined) {
            return NO_VALUE;
        }
        const index = Number(measureIndex) || 0;
        const measure = this.measures[index];
        const format = displayCurrencyFormat(measure?.format, this.barData?.currencyIsoCodes?.[index]);
        // A Share of total is a fraction of a total: never a currency or a stored percent field value.
        const isShare = Boolean(measure) && measure.showAs !== SHOW_AS_VALUE;
        return formatValue(
            value,
            { ...format, notation: notation === 'compact' ? 'compact' : format.notation },
            {
                notation: 'standard',
                valueType: isShare ? null : this.barData?.valueTypes?.[index] || null
            }
        );
    }

    // -----------------------------------------------------------------------------------------------------
    // Actions
    // -----------------------------------------------------------------------------------------------------

    handleToggleView() {
        this.showTable = !this.showTable;
    }

    /** Shown again after a Filter change while hidden: loading state instead of stale data, then one query. */
    handleShownStale() {
        this.chartModel = null;
        this.queryError = null;
        this.requestQuery();
    }

    handleRefresh() {
        this.widgetRefreshToken += 1;
        this.requestQuery();
        return Promise.resolve(true);
    }

    handleRefreshClick() {
        this.handleRefresh();
    }

    handleRetry() {
        if (this.filterContext?.error) {
            publishFilterContext({
                ...this.filterContext,
                error: null,
                refreshToken: (this.filterContext.refreshToken || 0) + 1,
                updatedAt: Date.now()
            });
        }
        if (this.chartLoadError) {
            this.chartLoadError = null;
            this.loadChartLibrary();
        }
        this.queryError = null;
        this.handleRefresh();
    }
}