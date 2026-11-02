import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import LOCALE from '@salesforce/i18n/locale';
import getObjectFields from '@salesforce/apex/BoardSchemaService.getObjectFields';
import queryMetric from '@salesforce/apex/BoardQueryService.queryMetric';
import fetchAggregateChunk from '@salesforce/apex/BoardQueryService.fetchAggregateChunk';
import {
    parseAndMergeConfig,
    normalizeBoardError,
    resolveFilterBindings,
    applyServerIgnoredFilters,
    buildFilterBindingSummary,
    buildQuerySignature,
    formatValue,
    formatTemporal
} from 'c/boardConfigUtils';
import { subscribeFilterContext, publishFilterContext, acceptExternalFilterContext } from 'c/boardContextStore';

const ZERO_WHEN_EMPTY = new Set(['COUNT', 'COUNT_DISTINCT', 'SUM']);
const THRESHOLD_ICONS = {
    success: { iconName: 'utility:success', label: 'Status: success' },
    warning: { iconName: 'utility:warning', label: 'Status: warning' },
    error: { iconName: 'utility:error', label: 'Status: error' }
};
const NO_VALUE = '—';
let widgetInstanceCount = 0;

export default class BoardMetricWidget extends LightningElement {
    _boardId = 'default';
    _boardIdExplicitlySet = false;
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
    bindingApplied = [];
    bindingIgnored = [];
    /** `ignoredFilterIds` of the last completed query; re-applied after every binding resolve. */
    _serverIgnoredIds = [];

    _latestRequestId = 0;
    _lastQuerySignature = null;
    _fieldsByObject = new Map();
    _widgetId = `boardMetricWidget-${++widgetInstanceCount}`;
    _unsubscribe = null;
    _refreshHandlerId = null;
    _isConnected = false;

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
        this._unsubscribe = subscribeFilterContext(effectiveBoardId, this._recordId, (ctx) => {
            this.filterContext = ctx;
            this.syncContextOutput(ctx);
            this.requestQuery();
        });
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
            widgetId: this._widgetId
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
            aggregateFunction,
            valueFieldApiName: aggregateFunction === 'COUNT' ? null : config.valueFieldApiName || null,
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
        const reqId = ++this._latestRequestId;
        this._serverIgnoredIds = [];
        this.applyBindingResolution(resolution);
        this.isQuerying = true;
        try {
            const result = await queryMetric({ requestJson: JSON.stringify(request) });
            if (reqId !== this._latestRequestId) {
                return;
            }
            this._serverIgnoredIds = result?.ignoredFilterIds || [];
            this.applyBindingResolution(resolution);
            if (result?.mode === 'CURSOR') {
                await this.aggregateCursorChunks(reqId, request, result);
            } else {
                this.metricResult = {
                    aggregateFunction,
                    value: result?.value ?? null,
                    valueType: result?.valueType || null,
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

    /** Tier 2: merges `Database.Cursor` chunks progressively; stops as soon as a newer request starts. */
    async aggregateCursorChunks(reqId, request, result) {
        const totals = { sum: 0, count: 0, min: null, max: null };
        let chunk = result.chunk;
        for (;;) {
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
            const isComplete = !chunk || chunk.isComplete;
            this.metricResult = {
                aggregateFunction: request.aggregateFunction,
                value: this.cursorValue(request.aggregateFunction, totals),
                valueType: result.valueType || null,
                isComplete,
                processedRows: chunk ? chunk.nextOffset : 0,
                totalRows: chunk ? chunk.totalRows : result.totalRows
            };
            if (isComplete) {
                return;
            }
            // eslint-disable-next-line no-await-in-loop -- cursor chunks are sequential: each call needs the previous offset
            chunk = await fetchAggregateChunk({
                requestJson: JSON.stringify({ ...request, cursor: chunk.cursor, offset: chunk.nextOffset })
            });
            if (reqId !== this._latestRequestId) {
                return;
            }
        }
    }

    cursorValue(aggregateFunction, totals) {
        switch (aggregateFunction) {
            case 'SUM':
                return totals.sum;
            case 'AVG':
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

    get effectiveBoardId() {
        return this.resolvedConfig.config?.boardId || this._boardId || 'default';
    }

    get aggregateFunction() {
        const fn = this.resolvedConfig.config?.aggregateFunction;
        return fn ? String(fn).trim().toUpperCase() : 'COUNT';
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

    get showWidgetState() {
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
        const numeric = Number(this.metricResult.value);
        return Number.isFinite(numeric) && typeof this.metricResult.value !== 'string' ? numeric : null;
    }

    get formatConfig() {
        return this.resolvedConfig.config?.format || {};
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

    get progressText() {
        const result = this.metricResult;
        if (!result || result.isComplete) {
            return '';
        }
        const format = (n) => new Intl.NumberFormat(LOCALE).format(n || 0);
        return `Calculating… ${format(result.processedRows)} of ${format(result.totalRows)} records`;
    }

    /** First matching ordered threshold rule's variant (`success` | `warning` | `error`), or null. */
    get thresholdVariant() {
        const value = this.numericValue;
        const rules = this.resolvedConfig.config?.thresholds;
        if (value === null || !Array.isArray(rules)) {
            return null;
        }
        const match = rules.find((rule) => {
            const limit = Number(rule?.value);
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