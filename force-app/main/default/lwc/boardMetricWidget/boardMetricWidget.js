import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import getObjectFields from '@salesforce/apex/BoardSchemaService.getObjectFields';
import queryMetric from '@salesforce/apex/BoardQueryService.queryMetric';
import fetchAggregateChunk from '@salesforce/apex/BoardQueryService.fetchAggregateChunk';
import evaluateMetric from '@salesforce/apex/BoardFormulaMeasures.evaluateMetric';
import {
    parseAndMergeConfig,
    normalizeBoardError,
    resolveFilterBindings,
    applyServerIgnoredFilters,
    buildFilterBindingSummary,
    buildQuerySignature,
    formatValue,
    formatTemporal,
    metricMeasures,
    perRecordSettings
} from 'c/boardConfigUtils';
import { runCursorLoad } from 'c/boardCursorProgress';
import { isGaugeDisplay, resolveGauge, gaugeConfigAmounts, gaugeConfigInDisplayCurrency } from 'c/boardMetricGauge';
import { createHiddenDeferral } from 'c/boardVisibilityWatcher';
import {
    subscribeFilterContext,
    publishFilterContext,
    acceptExternalFilterContext,
    getDisplayCurrency,
    getConfigCurrency,
    getBoardBucketFields
} from 'c/boardContextStore';
import { displayCurrencyFormat, configAmounts, displayAmount } from 'c/boardDisplayCurrency';
import { waitsForFilterWidget, waitingForBoardId } from 'c/boardConfigUtils';
import { crossObjectNotices, crossObjectRequestFields } from 'c/boardCrossObjectMeasure';

const ZERO_WHEN_EMPTY = new Set(['COUNT', 'COUNT_DISTINCT', 'SUM']);
/** Schema.DisplayType names whose aggregate may arrive as a numeric string (high-precision Decimal). */
const NUMERIC_VALUE_TYPES = new Set(['CURRENCY', 'DOUBLE', 'INTEGER', 'LONG', 'PERCENT']);
const DECIMAL_STRING = /^[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$/;
const THRESHOLD_ICONS = {
    success: { iconName: 'utility:success', label: 'Status: success' },
    warning: { iconName: 'utility:warning', label: 'Status: warning' },
    error: { iconName: 'utility:error', label: 'Status: error' }
};
const NO_VALUE = '—';
let widgetInstanceCount = 0;

/**
 * A Measure as the Metric query sends it: `{ aggregateFunction, valueFieldApiName, perField?, inner?, hidden?,
 * condition?, formula? }` (`perField` / `inner`: Average per record).
 */
function requestMeasure(measure) {
    const source = measure && typeof measure === 'object' ? measure : {};
    const aggregateFunction = source.aggregateFunction
        ? String(source.aggregateFunction).trim().toUpperCase()
        : 'COUNT';
    const request = {
        aggregateFunction,
        valueFieldApiName: aggregateFunction === 'COUNT' ? null : source.valueFieldApiName || null,
        ...perRecordSettings({ ...source, aggregateFunction })
    };
    if (source.hidden === true) {
        request.hidden = true;
    }
    if (aggregateFunction === 'FORMULA') {
        request.formula = typeof source.formula === 'string' ? source.formula : null;
        if (source.isCurrency === true) {
            request.isCurrency = true;
        }
    }
    const condition = source.condition;
    if (
        condition &&
        typeof condition === 'object' &&
        Array.isArray(condition.conditions) &&
        condition.conditions.length
    ) {
        request.condition = condition;
    }
    return { ...request, ...crossObjectRequestFields(source) };
}

export default class BoardMetricWidget extends LightningElement {
    _boardId = 'default';
    _boardIdExplicitlySet = false;
    _livePreview = false;
    _title = '';
    _objectApiName = '';
    _recordId = '';
    _filterContextJson = '';
    _pendingExternalContext = null;
    _configJson = '';

    filterContext = null;
    widgetRefreshToken = 0;

    /** Last rendered aggregate: `{ aggregateFunction, value, valueType, isComplete, processedRows, totalRows }`. */
    metricResult = null;
    queryError = null;
    isQuerying = false;
    /** Cursor-tier progress `{ percent, label, ... }` while a large scope loads; null otherwise. */
    _cursorProgress = null;
    bindingApplied = [];
    bindingIgnored = [];
    /** The last result's `crossObjectNotices` (one per Cross-object measure). */
    crossObjectNoticeData = [];
    /** `ignoredFilterIds` of the last completed query; re-applied after every binding resolve. */
    _serverIgnoredIds = [];

    _latestRequestId = 0;
    _lastQuerySignature = null;
    _fieldsByObject = new Map();
    _widgetId = `boardMetricWidget-${++widgetInstanceCount}`;
    _unsubscribe = null;
    _refreshHandlerId = null;
    _isConnected = false;

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
    set filterContextJson(value) {
        this._filterContextJson = value || '';
        if (!value) {
            return;
        }
        if (this._isConnected) {
            this.acceptExternalContext(value);
        } else {
            this._pendingExternalContext = value;
        }
    }

    @api
    get configJson() {
        return this._configJson;
    }
    set configJson(value) {
        this._configJson = value || '';
        if (this._isConnected) {
            this.setupSubscription();
        }
    }

    connectedCallback() {
        this._isConnected = true;
        this._hiddenDeferral = createHiddenDeferral(this.template.host, () => this.handleShownStale());
        this.setupSubscription();
        if (this._pendingExternalContext) {
            const pending = this._pendingExternalContext;
            this._pendingExternalContext = null;
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
        if (this._refreshHandlerId) {
            try {
                unregisterRefreshHandler(this._refreshHandlerId);
            } catch (e) {
                // Ignore
            }
            this._refreshHandlerId = null;
        }
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

    teardownSubscription() {
        if (this._unsubscribe) {
            this._unsubscribe();
            this._unsubscribe = null;
        }
    }

    /**
     * Hands a reactive Flow `filterContextJson` input to the store, which scope- and precedence-checks it; the
     * subscription delivers accepted state. A rejected input is answered by echoing the actual context.
     */
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

    // -----------------------------------------------------------------------------------------------------
    // Query lifecycle
    // -----------------------------------------------------------------------------------------------------

    /** Describe per object, re-fetched when the Board `refreshToken` changes (busts the cacheable Apex result). */
    loadFields(objectApiName, refreshToken) {
        const cached = this._fieldsByObject.get(objectApiName);
        if (!cached || cached.refreshToken !== refreshToken) {
            const pending = Promise.resolve(getObjectFields({ objectApiName, refreshToken })).catch((error) => {
                if (this._fieldsByObject.get(objectApiName)?.pending === pending) {
                    this._fieldsByObject.delete(objectApiName);
                }
                throw error;
            });
            this._fieldsByObject.set(objectApiName, { refreshToken, pending });
        }
        return this._fieldsByObject.get(objectApiName).pending;
    }

    /** Resolves bindings and fires `queryMetric` unless the effective-query signature is unchanged. */
    async requestQuery() {
        const initial = this.resolvedConfig;
        if (initial.error || initial.isUnconfigured || this.filterContext?.status !== 'READY') {
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
            parsed.isUnconfigured ||
            parsed.config.objectApiName !== objectApiName ||
            ctx?.status !== 'READY'
        ) {
            return;
        }
        const config = parsed.config;
        const resolution = resolveFilterBindings({
            objectApiName,
            fields,
            filterContext: ctx,
            filterBindings: config.filterBindings,
            widgetId: this._widgetId,
            bucketFields: config.bucketFields,
            boardBucketFields: getBoardBucketFields(this.effectiveBoardId)
        });
        this.applyBindingResolution(resolution);
        if (resolution.error) {
            // Broken explicit filterBinding: fail closed instead of querying without that filter.
            this._latestRequestId += 1;
            this._lastQuerySignature = null;
            this.isQuerying = false;
            this.queryError = resolution.error;
            return;
        }

        const aggregateFunction = this.aggregateFunction;
        const request = {
            objectApiName,
            measures: this.measures.map(requestMeasure),
            filters: resolution.filters,
            baseFilters: Array.isArray(config.baseFilters) ? config.baseFilters : [],
            displayCurrency: getDisplayCurrency(this.effectiveBoardId),
            configCurrency: getConfigCurrency(this.effectiveBoardId),
            thresholdAmounts: configAmounts(config.thresholds),
            ...(isGaugeDisplay(config) ? { gaugeAmounts: gaugeConfigAmounts(config) } : {}),
            dataProvider: config.dataProvider || null,
            refreshToken: ctx.refreshToken || 0,
            widgetRefreshToken: this.widgetRefreshToken
        };
        const signature = buildQuerySignature(request);
        if (signature === this._lastQuerySignature || this._hiddenDeferral?.deferIfHidden()) {
            return;
        }
        this._lastQuerySignature = signature;
        const reqId = ++this._latestRequestId;
        this._serverIgnoredIds = [];
        this.applyBindingResolution(resolution);
        this._cursorProgress = null;
        this.isQuerying = true;
        try {
            const result = await queryMetric({ requestJson: JSON.stringify(request) });
            if (reqId !== this._latestRequestId) {
                return;
            }
            this._serverIgnoredIds = result?.ignoredFilterIds || [];
            this.crossObjectNoticeData = result?.crossObjectNotices || [];
            this.applyBindingResolution(resolution);
            if (result?.mode === 'CURSOR') {
                await this.aggregateCursorChunks(reqId, request, result);
            } else if (aggregateFunction === 'FORMULA' && result?.isComplete === false) {
                await this.finishFormulaInputs(reqId, request, result);
            } else {
                this.metricResult = {
                    aggregateFunction,
                    value: result?.value ?? null,
                    valueType: result?.valueType || null,
                    currencyIsoCode: result?.currencyIsoCode || null,
                    thresholdAmounts: result?.thresholdAmounts || null,
                    gaugeAmounts: result?.gaugeAmounts || null,
                    measureValues: (result?.measures || []).map((measure) => measure?.value ?? null),
                    isComplete: true
                };
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

    /** Tier 2: merges `Database.Cursor` chunks; shows progress only and renders the final number once. */
    async aggregateCursorChunks(reqId, request, result) {
        const value = await this.loadCursorValue(reqId, request, this.visibleMeasure, result.chunk);
        if (value !== undefined) {
            this.metricResult = {
                aggregateFunction: requestMeasure(this.visibleMeasure).aggregateFunction,
                value,
                valueType: result.valueType || null,
                currencyIsoCode: result.currencyIsoCode || null,
                thresholdAmounts: result.thresholdAmounts || null,
                gaugeAmounts: result.gaugeAmounts || null,
                isComplete: true
            };
        }
    }

    /**
     * A visible Formula measure whose inputs are still on the cursor tier: finishes each such input, then has the
     * server evaluate the formula from the completed input values (in the Display currency, with each input's ISO
     * code so a currency Formula measure reads its constants in the Config currency).
     */
    async finishFormulaInputs(reqId, request, result) {
        const results = Array.isArray(result.measures) ? result.measures : [];
        const values = results.map((entry) => entry?.value ?? null);
        for (let index = 0; index < results.length; index++) {
            const entry = results[index];
            // A cursor input's value is in its chunks, even when the first chunk is already the last one.
            if (entry?.mode === 'CURSOR') {
                // eslint-disable-next-line no-await-in-loop -- one cursor at a time keeps the progress bar honest
                const value = await this.loadCursorValue(reqId, request, this.measures[index], entry.chunk);
                if (value === undefined) {
                    return;
                }
                values[index] = value;
            }
        }
        const currencyIsoCodes = results.map((entry) => entry?.currencyIsoCode || null);
        const value = await evaluateMetric({ requestJson: JSON.stringify({ ...request, values, currencyIsoCodes }) });
        if (reqId === this._latestRequestId) {
            this.metricResult = {
                aggregateFunction: 'FORMULA',
                value: value ?? null,
                valueType: result.valueType || null,
                currencyIsoCode: result.currencyIsoCode || null,
                thresholdAmounts: result.thresholdAmounts || null,
                gaugeAmounts: result.gaugeAmounts || null,
                isComplete: true
            };
        }
    }

    /** Merges the cursor chunks of one Measure; its final value, or undefined when the run was superseded. */
    async loadCursorValue(reqId, request, measure, firstChunk) {
        const totals = { sum: 0, count: 0, min: null, max: null };
        const completed = await runCursorLoad({
            first: firstChunk,
            isCurrent: () => reqId === this._latestRequestId,
            merge: (chunk) => {
                (chunk?.buckets || []).forEach((bucket) => {
                    totals.sum += Number(bucket.sum || 0);
                    totals.count += Number(bucket.count || 0);
                    if (bucket.min !== null && bucket.min !== undefined) {
                        totals.min = totals.min === null ? bucket.min : Math.min(totals.min, bucket.min);
                    }
                    if (bucket.max !== null && bucket.max !== undefined) {
                        totals.max = totals.max === null ? bucket.max : Math.max(totals.max, bucket.max);
                    }
                });
            },
            onProgress: (progress) => {
                this._cursorProgress = progress;
            },
            fetchNext: (chunk) =>
                fetchAggregateChunk({
                    requestJson: JSON.stringify({
                        ...request,
                        measures: undefined,
                        ...requestMeasure(measure),
                        hidden: undefined,
                        cursor: chunk.cursor,
                        offset: chunk.nextOffset
                    })
                })
        });
        return completed ? this.cursorValue(requestMeasure(measure).aggregateFunction, totals) : undefined;
    }

    cursorValue(aggregateFunction, totals) {
        switch (aggregateFunction) {
            case 'SUM':
                return totals.sum;
            case 'AVG':
            case 'AVG_PER': // Each chunk's count is records, its sum their values.
                return totals.count ? totals.sum / totals.count : null;
            case 'MIN':
                return totals.min;
            case 'MAX':
                return totals.max;
            default:
                return totals.count;
        }
    }

    /** Header disclosure: client binding resolution plus the filters the last completed query ignored server-side. */
    applyBindingResolution(resolution) {
        const { applied, ignored } = applyServerIgnoredFilters(
            resolution.applied,
            resolution.ignored,
            this._serverIgnoredIds
        );
        this.bindingApplied = applied;
        this.bindingIgnored = ignored;
    }

    // -----------------------------------------------------------------------------------------------------
    // Derived state
    // -----------------------------------------------------------------------------------------------------

    get resolvedConfig() {
        return parseAndMergeConfig('metric', this._configJson, {
            boardId: this._boardIdExplicitlySet ? this._boardId : '',
            title: this._title,
            objectApiName: this._objectApiName
        });
    }

    get effectiveTitle() {
        return this.resolvedConfig.config?.title || 'Metric';
    }

    get effectiveObjectApiName() {
        return this.resolvedConfig.config?.objectApiName || '';
    }

    /** Board id for the Wait for Filter widget hint card while this Widget waits, else empty. */
    get waitingBoardId() {
        return waitingForBoardId(this.resolvedConfig.config, this._livePreview, this.filterContext);
    }

    get effectiveBoardId() {
        return this.resolvedConfig.config?.boardId || this._boardId || 'default';
    }

    /** The Measures list (a single-aggregate config is its one visible Measure). */
    get measures() {
        return metricMeasures(this.resolvedConfig.config);
    }

    /** The one Measure the Metric shows; the others are hidden (fetched, not shown). */
    get visibleMeasure() {
        const measures = this.measures;
        return measures.find((measure) => measure && measure.hidden !== true) || measures[0] || {};
    }

    get aggregateFunction() {
        return requestMeasure(this.visibleMeasure).aggregateFunction;
    }

    get activeScopeKey() {
        return this.filterContext?.scopeKey || '';
    }

    get viewState() {
        const parsed = this.resolvedConfig;
        if (parsed.error) {
            return 'ERROR';
        }
        if (parsed.isUnconfigured) {
            return 'UNCONFIGURED';
        }
        if (this.filterContext?.error || this.queryError) {
            return 'ERROR';
        }
        if (!this.metricResult) {
            return 'INITIAL_LOADING';
        }
        return 'READY';
    }

    get showMetricBody() {
        return this.viewState === 'READY';
    }

    get showWidgetState() {
        if (this.showCursorProgress && this.viewState === 'INITIAL_LOADING') {
            return false;
        }
        return this.viewState !== 'READY';
    }

    get errorPayload() {
        if (this.resolvedConfig.error) {
            return this.resolvedConfig.error;
        }
        if (this.filterContext?.error) {
            return normalizeBoardError(this.filterContext.error);
        }
        return this.queryError;
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
        const measureLabels = this.measures.map(
            (measure, index) =>
                (measure && typeof measure.label === 'string' && measure.label) || `Measure ${index + 1}`
        );
        return crossObjectNotices(this.crossObjectNoticeData, measureLabels, filterLabels);
    }

    get isRefreshing() {
        return this.isQuerying && Boolean(this.metricResult);
    }

    get ariaBusy() {
        return this.isQuerying ? 'true' : 'false';
    }

    get bodyClass() {
        return this.isRefreshing
            ? 'c-board-metric-content c-board-metric-content_refreshing'
            : 'c-board-metric-content';
    }

    get hasNoValue() {
        const result = this.metricResult;
        return Boolean(result) && (result.value === null || result.value === undefined);
    }

    /** `AVG`/`MIN`/`MAX` over zero rows render "—" with "No matching records" and no threshold. */
    get isNoMatchingRecords() {
        return this.hasNoValue && !ZERO_WHEN_EMPTY.has(this.metricResult.aggregateFunction);
    }

    get numericValue() {
        if (!this.metricResult || this.isNoMatchingRecords) {
            return null;
        }
        if (this.hasNoValue) {
            return 0;
        }
        const { value, valueType } = this.metricResult;
        // Apex serializes high-precision Decimals as strings; accept those for numeric fields only, so
        // MIN/MAX over Text values such as "00123" still render verbatim.
        if (typeof value === 'string' && !(NUMERIC_VALUE_TYPES.has(valueType) && DECIMAL_STRING.test(value.trim()))) {
            return null;
        }
        const numeric = Number(value);
        return Number.isFinite(numeric) ? numeric : null;
    }

    get formatConfig() {
        return displayCurrencyFormat(this.visibleMeasure.format, this.metricResult?.currencyIsoCode);
    }

    get displayValue() {
        if (!this.metricResult) {
            return '';
        }
        if (this.isNoMatchingRecords) {
            return NO_VALUE;
        }
        if (this.numericValue === null) {
            return this.temporalValue(this.metricResult.value, this.metricResult.valueType);
        }
        return formatValue(this.numericValue, this.formatConfig, {
            notation: 'compact',
            valueType: this.metricResult.valueType
        });
    }

    /** The Gauge of a `display: 'gauge'` Metric: `{ model }` or `{ error }`; null for the number display. */
    get gaugeResult() {
        const config = this.resolvedConfig.config;
        if (!isGaugeDisplay(config) || !this.metricResult) {
            return null;
        }
        return resolveGauge({
            config: { ...gaugeConfigInDisplayCurrency(config, this.metricResult), measures: this.measures },
            value: this.numericValue,
            measureValues: this.metricResult.measureValues,
            format: (number) =>
                formatValue(number, this.formatConfig, { notation: 'compact', valueType: this.metricResult.valueType })
        });
    }

    get gaugeModel() {
        return this.gaugeResult?.model || null;
    }

    get gaugeError() {
        return this.gaugeResult?.error || null;
    }

    get exactValue() {
        if (this.numericValue === null) {
            return this.displayValue;
        }
        return formatValue(
            this.numericValue,
            { ...this.formatConfig, notation: 'standard' },
            { valueType: this.metricResult.valueType }
        );
    }

    get subtitle() {
        if (this.isNoMatchingRecords) {
            return 'No matching records';
        }
        return this.resolvedConfig.config?.subtitle || '';
    }

    /** Progress bar state; only while the cursor tier of the latest run is loading. */
    get cursorProgress() {
        return this.isQuerying ? this._cursorProgress : null;
    }

    get showCursorProgress() {
        return Boolean(this.cursorProgress);
    }

    /** First matching ordered threshold rule's variant (amounts converted Config → Display currency), or null. */
    get thresholdVariant() {
        const value = this.numericValue;
        const rules = this.resolvedConfig.config?.thresholds;
        if (value === null || !Array.isArray(rules)) {
            return null;
        }
        const match = rules.find((rule, index) => {
            const limit = displayAmount(rule, index, this.metricResult.thresholdAmounts);
            if (!THRESHOLD_ICONS[rule?.variant] || !Number.isFinite(limit)) {
                return false;
            }
            switch (rule.operator) {
                case 'gt':
                    return value > limit;
                case 'gte':
                    return value >= limit;
                case 'lt':
                    return value < limit;
                case 'lte':
                    return value <= limit;
                default:
                    return false;
            }
        });
        return match ? match.variant : null;
    }

    get thresholdIcon() {
        return this.thresholdVariant ? THRESHOLD_ICONS[this.thresholdVariant].iconName : null;
    }

    get thresholdLabel() {
        return this.thresholdVariant ? THRESHOLD_ICONS[this.thresholdVariant].label : null;
    }

    get valueClass() {
        return this.thresholdVariant
            ? `c-board-metric-value c-board-metric-value_${this.thresholdVariant}`
            : 'c-board-metric-value';
    }

    /** MIN/MAX over Date/DateTime fields; any other non-numeric value renders as text. */
    temporalValue(value, valueType) {
        if (value === null || value === undefined) {
            return NO_VALUE;
        }
        if (valueType === 'DATE' || valueType === 'DATETIME') {
            return formatTemporal(value, valueType === 'DATE' ? 'date' : 'datetime');
        }
        return String(value);
    }

    // -----------------------------------------------------------------------------------------------------
    // Actions
    // -----------------------------------------------------------------------------------------------------

    /** Shown again after a Filter change while hidden: loading state instead of stale data, then one query. */
    handleShownStale() {
        this.metricResult = null;
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
        this.queryError = null;
        this.handleRefresh();
    }
}