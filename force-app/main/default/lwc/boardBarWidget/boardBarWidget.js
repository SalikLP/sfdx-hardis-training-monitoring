import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import LOCALE from '@salesforce/i18n/locale';
import getObjectFields from '@salesforce/apex/BoardSchemaService.getObjectFields';
import queryBar from '@salesforce/apex/BoardQueryService.queryBar';
import fetchAggregateChunk from '@salesforce/apex/BoardQueryService.fetchAggregateChunk';
import {
    parseAndMergeConfig,
    normalizeBoardError,
    resolveFilterBindings,
    applyServerIgnoredFilters,
    buildFilterBindingSummary,
    buildQuerySignature,
    formatValue
} from 'c/boardConfigUtils';
import { subscribeFilterContext, publishFilterContext, acceptExternalFilterContext } from 'c/boardContextStore';
import {
    loadChartJs,
    resolveChartTheme,
    matchesMediaQuery,
    watchMediaQuery,
    watchColorScheme,
    chartAnimation,
    createBarDataLabelsPlugin,
    PREFERS_REDUCED_MOTION_QUERY
} from 'c/boardChartUtils';
import {
    normalizeBarSettings,
    mergeChunkBuckets,
    cursorTotalsToBuckets,
    buildBarModel,
    buildBarChartConfig,
    applyBarChartConfig
} from './barModel';

const AGGREGATE_LABELS = {
    COUNT_DISTINCT: 'Unique count',
    SUM: 'Sum',
    AVG: 'Average',
    MIN: 'Min',
    MAX: 'Max'
};
const NO_VALUE = '—';
const CHART_LOAD_ERROR = {
    category: 'QUERY_ERROR',
    message: 'The chart library could not be loaded.',
    filterId: null,
    fieldPath: null,
    retryable: true
};
let widgetInstanceCount = 0;

export default class BoardBarWidget extends LightningElement {
    _boardId = 'default';
    _boardIdExplicitlySet = false;
    _title = '';
    _objectApiName = '';
    _orientation = 'vertical';
    _orientationExplicitlySet = false;
    _recordId = '';
    _filterContextJson = '';
    /** A Flow `filterContextJson` input received before connect; handed to the store in `connectedCallback`. */
    _pendingExternalJson = '';
    _configJson = '';

    filterContext = null;
    widgetRefreshToken = 0;

    /** Last server result: `{ buckets, aggregateFunction, valueType, groupBy, stackBy, isComplete, ... }`. */
    barData = null;
    /** Rendered model derived from `barData` and the display settings (see `barModel.buildBarModel`). */
    chartModel = null;
    queryError = null;
    chartLoadError = null;
    isQuerying = false;
    showTable = false;
    bindingApplied = [];
    bindingIgnored = [];
    /** `ignoredFilterIds` of the last completed query, re-applied after every client-side binding resolve. */
    _serverIgnoredIds = [];

    _latestRequestId = 0;
    _lastQuerySignature = null;
    _fieldsByObject = new Map();
    _fieldLabels = new Map();
    _widgetId = `boardBarWidget-${++widgetInstanceCount}`;
    _unsubscribe = null;
    _refreshHandlerId = null;
    _isConnected = false;

    _Chart = null;
    _chart = null;
    _chartContainer = null;
    _modelVersion = 0;
    _renderedVersion = 0;
    _reducedMotion = false;
    _mediaUnsubscribers = [];
    _themeKey = null;
    _dataLabelsPlugin = createBarDataLabelsPlugin((value) => this.formatMeasure(value));

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
    get orientation() {
        return this.effectiveOrientation;
    }
    set orientation(value) {
        if (value && String(value).trim()) {
            this._orientation = String(value).trim();
            this._orientationExplicitlySet = true;
        } else {
            this._orientation = 'vertical';
            this._orientationExplicitlySet = false;
        }
        this.rebuildModel();
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
        // Display-only settings (sorting, maxBars, legend...) re-shape cached data without a new query.
        this.rebuildModel();
        if (this._isConnected) {
            this.setupSubscription();
        }
    }

    connectedCallback() {
        this._isConnected = true;
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
        this._unsubscribe = subscribeFilterContext(effectiveBoardId, this._recordId, (ctx) => {
            this.filterContext = ctx;
            this.syncContextOutput(ctx);
            this.requestQuery();
        });
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

    /** Resolves bindings and fires `queryBar` unless the effective-query signature is unchanged. */
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
            widgetId: this._widgetId
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

        const aggregateFunction = this.aggregateFunction;
        const request = {
            objectApiName,
            aggregateFunction,
            valueFieldApiName: aggregateFunction === 'COUNT' ? null : config.valueFieldApiName || null,
            groupByField: config.groupByField,
            dateGranularity: config.dateGranularity || null,
            stackByField: config.stackByField || null,
            includeNullBucket: config.includeNullBucket !== false,
            filters: resolution.filters,
            baseFilters: Array.isArray(config.baseFilters) ? config.baseFilters : [],
            refreshToken: ctx.refreshToken || 0,
            widgetRefreshToken: this.widgetRefreshToken
        };
        const signature = buildQuerySignature(request);
        if (signature === this._lastQuerySignature) {
            return;
        }
        this._lastQuerySignature = signature;
        this._serverIgnoredIds = [];
        const reqId = ++this._latestRequestId;
        this.isQuerying = true;
        try {
            const result = await queryBar({ requestJson: JSON.stringify(request) });
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
            if (result?.mode === 'CURSOR') {
                await this.aggregateCursorChunks(reqId, request, result);
            } else {
                this.setBarData(result, result?.buckets || [], { isComplete: true });
            }
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

    /** Tier 2: merges grouped `Database.Cursor` chunks progressively; stops once a newer request starts. */
    async aggregateCursorChunks(reqId, request, result) {
        const totals = new Map();
        let chunk = result.chunk;
        for (;;) {
            mergeChunkBuckets(totals, chunk?.buckets);
            const isComplete = !chunk || chunk.isComplete;
            this.setBarData(result, cursorTotalsToBuckets(totals, request.aggregateFunction), {
                isComplete,
                processedRows: chunk ? chunk.nextOffset : 0,
                totalRows: chunk ? chunk.totalRows : result.totalRows
            });
            if (isComplete) {
                return;
            }
            // eslint-disable-next-line no-await-in-loop -- each chunk needs the previous chunk's cursor offset
            chunk = await fetchAggregateChunk({
                requestJson: JSON.stringify({ ...request, cursor: chunk.cursor, offset: chunk.nextOffset })
            });
            if (reqId !== this._latestRequestId) {
                return;
            }
        }
    }

    setBarData(result, buckets, progress) {
        this.barData = {
            buckets,
            aggregateFunction: result?.aggregateFunction || this.aggregateFunction,
            valueType: result?.valueType || null,
            groupBy: result?.groupBy || null,
            stackBy: result?.stackBy || null,
            hasMoreGroups: result?.hasMoreGroups === true,
            ...progress
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
        this.chartModel = buildBarModel({
            buckets: data.buckets,
            aggregateFunction: data.aggregateFunction,
            groupBy: data.groupBy,
            stackBy: data.stackBy,
            settings: this.settings,
            measureLabel: this.measureLabel
        });
        this._modelVersion += 1;
    }

    buildChartConfig(theme = resolveChartTheme(this.template.host)) {
        this._themeKey = JSON.stringify(theme);
        return buildBarChartConfig(this.chartModel, {
            settings: this.settings,
            theme,
            animation: chartAnimation(this._reducedMotion),
            formatValue: (value) => this.formatMeasure(value),
            formatTick: (value) => this.formatMeasure(value, 'compact'),
            dataLabelsPlugin: this._dataLabelsPlugin
        });
    }

    /**
     * Creates the chart once per mounted canvas container, then morphs it in place with `chart.update()`. The EMPTY
     * state keeps the container mounted (hidden), so zero rows morph the existing chart to no bars and back.
     */
    syncChart() {
        const container = this.template.querySelector('.c-board-chart-canvas');
        if (this._chart && this._chartContainer !== container) {
            this.destroyChart();
        }
        if (!container || !this._Chart || !this.chartModel) {
            return;
        }
        if (!this._chart && !this.chartModel.categories.length) {
            return;
        }
        if (!this._chart) {
            const canvas = document.createElement('canvas');
            canvas.setAttribute('role', 'img');
            canvas.setAttribute('aria-label', this.chartAriaLabel);
            container.appendChild(canvas);
            this._chart = new this._Chart(canvas, this.buildChartConfig());
            this._chartContainer = container;
            this._renderedVersion = this._modelVersion;
            return;
        }
        if (this._renderedVersion !== this._modelVersion) {
            applyBarChartConfig(this._chart, this.buildChartConfig());
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
        if (!this._chart || !this.chartModel) {
            return;
        }
        const theme = resolveChartTheme(this.template.host);
        if (JSON.stringify(theme) === this._themeKey) {
            return;
        }
        applyBarChartConfig(this._chart, this.buildChartConfig(theme));
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
        return parseAndMergeConfig('bar', this._configJson, {
            boardId: this._boardIdExplicitlySet ? this._boardId : '',
            title: this._title,
            objectApiName: this._objectApiName,
            orientation: this._orientationExplicitlySet ? this._orientation : ''
        });
    }

    /** No object or no group-by field yet: render the setup placeholder rather than an error. */
    get isUnconfigured() {
        const parsed = this.resolvedConfig;
        return parsed.isUnconfigured || (!parsed.error && !String(parsed.config?.groupByField || '').trim());
    }

    get settings() {
        return normalizeBarSettings(
            { ...(this.resolvedConfig.config || {}), orientation: this.effectiveOrientation },
            this.barData?.groupBy
        );
    }

    get effectiveTitle() {
        return this.resolvedConfig.config?.title || 'Bar Chart';
    }

    get effectiveObjectApiName() {
        return this.resolvedConfig.config?.objectApiName || '';
    }

    get effectiveOrientation() {
        return this.resolvedConfig.config?.orientation || this._orientation || 'vertical';
    }

    get effectiveBoardId() {
        return this.resolvedConfig.config?.boardId || this._boardId || 'default';
    }

    get aggregateFunction() {
        const fn = this.resolvedConfig.config?.aggregateFunction;
        return fn ? String(fn).trim().toUpperCase() : 'COUNT';
    }

    get subtitle() {
        return this.resolvedConfig.config?.subtitle || '';
    }

    get measureLabel() {
        const fn = this.barData?.aggregateFunction || this.aggregateFunction;
        if (fn === 'COUNT') {
            return 'Record Count';
        }
        const field = this.resolvedConfig.config?.valueFieldApiName || '';
        return `${AGGREGATE_LABELS[fn] || fn} of ${this._fieldLabels.get(field) || field}`;
    }

    get categoryHeader() {
        const path = this.barData?.groupBy?.fieldPath || this.resolvedConfig.config?.groupByField || '';
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

    get isRefreshing() {
        return this.isQuerying && Boolean(this.chartModel);
    }

    get ariaBusy() {
        return this.isQuerying ? 'true' : 'false';
    }

    get bodyClass() {
        return this.isRefreshing ? 'c-board-bar-content c-board-bar-content_refreshing' : 'c-board-bar-content';
    }

    get chartWrapperClass() {
        return this.showTable || this.isEmpty ? 'c-board-chart-wrapper slds-hide' : 'c-board-chart-wrapper';
    }

    get tableWrapperClass() {
        return this.isEmpty ? 'c-board-bar-table-wrapper slds-hide' : 'c-board-bar-table-wrapper';
    }

    /** Sets `--board-chart-height` so the narrow-card `@container` rule can still cap it. */
    get chartContainerStyle() {
        const bars = this.chartModel ? this.chartModel.categories.length : 0;
        const perBar = this.chartModel?.hasSeries && !this.chartModel.isStacked ? 2.5 : 1.75;
        const height = this.settings.orientation === 'horizontal' ? Math.max(16, bars * perBar + 4) : 18;
        return `--board-chart-height: ${height}rem;`;
    }

    get tableClass() {
        return this.showTable
            ? 'slds-table slds-table_bordered slds-table_cell-buffer c-board-bar-table'
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
        return `${this.effectiveTitle}: ${this.measureLabel} by ${this.categoryHeader}, ${model.categories.length} bars. Data table follows.`;
    }

    get tableCaption() {
        return `${this.effectiveTitle}: ${this.measureLabel} by ${this.categoryHeader}`;
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
        const model = this.chartModel;
        if (!model) {
            return [];
        }
        return model.categories.map((category, index) => {
            const values = model.series.map((series) => series.values[index]);
            const cells = values.map((value, seriesIndex) => ({
                key: `${category.key}-${model.series[seriesIndex].key}`,
                text: this.formatMeasure(value)
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

    get progressText() {
        const data = this.barData;
        if (!data || data.isComplete) {
            return '';
        }
        const format = (n) => new Intl.NumberFormat(LOCALE).format(n || 0);
        return `Calculating… ${format(data.processedRows)} of ${format(data.totalRows)} records`;
    }

    formatMeasure(value, notation = 'standard') {
        if (value === null || value === undefined) {
            return NO_VALUE;
        }
        const format = this.resolvedConfig.config?.format || {};
        return formatValue(
            value,
            { ...format, notation: notation === 'compact' ? 'compact' : format.notation },
            {
                notation: 'standard',
                valueType: this.barData?.valueType
            }
        );
    }

    // -----------------------------------------------------------------------------------------------------
    // Actions
    // -----------------------------------------------------------------------------------------------------

    handleToggleView() {
        this.showTable = !this.showTable;
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