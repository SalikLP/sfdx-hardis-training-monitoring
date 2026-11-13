import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import LOCALE from '@salesforce/i18n/locale';
import getObjectFields from '@salesforce/apex/BoardSchemaService.getObjectFields';
import queryTable from '@salesforce/apex/BoardQueryService.queryTable';
import fetchTablePage from '@salesforce/apex/BoardQueryService.fetchTablePage';
import fetchGroupedTablePage from '@salesforce/apex/BoardQueryService.fetchGroupedTablePage';
import fetchTableAggregateChunk from '@salesforce/apex/BoardQueryService.fetchTableAggregateChunk';
import {
    parseAndMergeConfig,
    normalizeBoardError,
    resolveFilterBindings,
    applyServerIgnoredFilters,
    buildFilterBindingSummary,
    buildQuerySignature
} from 'c/boardConfigUtils';
import {
    subscribeFilterContext,
    publishFilterContext,
    acceptExternalFilterContext,
    getDisplayCurrency,
    getConfigCurrency,
    getBoardBucketFields
} from 'c/boardContextStore';
import { waitsForFilterWidget, waitingForBoardId } from 'c/boardConfigUtils';
import { createHiddenDeferral } from 'c/boardVisibilityWatcher';
import { formatCount } from 'c/boardCursorProgress';
import { columnBucketFields } from 'c/boardBucketFields';
import BoardTableFlowModal from 'c/boardTableFlowModal';
import { getObjectInfos } from 'lightning/uiObjectInfoApi';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import {
    normalizeRowActions,
    serverRowActionRequest,
    permissionObjectApiNames,
    withPolymorphicCandidates,
    buildCreatePageReference,
    buildActionHeaders,
    buildActionCells,
    buildFlowInputVariables,
    resolveActionRecordId
} from './rowActions';
import { buildColumnViews, buildCellView, buildHighlightPattern } from './tableCells';
import { withGroupRowActions, resolveGroupActionRow } from './groupRowActions';
import { withTotalRowRequest, buildTotalRowView } from './totalRow';
import { withGroupSummariesRequest, withGroupSummaryRows } from './groupSummaries';
import {
    GROUP_COLUMN_ID,
    groupByRequest,
    mergeGroups,
    toggledGroupDirection,
    buildGroupHeader,
    groupSpacerCell,
    buildGroupedRows
} from './rowGrouping';
import {
    aggregateRequestFields,
    buildAggregateGroupHeader,
    buildAggregateRowViews,
    sortAggregateTable
} from './aggregateTable';
import { followAggregateCursor, isIncompleteAggregateCursor } from './aggregateCursor';

const DEFAULT_PAGE_SIZE = 25;
const MIN_PAGE_SIZE = 10;
const MAX_PAGE_SIZE = 100;
/** Rows a `Database.PaginationCursor` spans at most; the count badge shows `100,000+` at the cap. */
const MAX_TABLE_ROWS = 100000;
/** Largest Row limit (Top N) a Table accepts. */
const MAX_ROW_LIMIT = 2000;
/** Distance (px) from the bottom of the scroll container that triggers the next page. */
const SCROLL_THRESHOLD_PX = 48;
/** `fieldPath` of the retryable `QUERY_ERROR` `fetchTablePage` raises when the held cursor expired. */
const CURSOR_EXPIRED_PATH = 'paginationCursor';
let widgetInstanceCount = 0;

function clampPageSize(value) {
    const size = Number(value);
    if (!Number.isFinite(size)) {
        return DEFAULT_PAGE_SIZE;
    }
    return Math.min(MAX_PAGE_SIZE, Math.max(MIN_PAGE_SIZE, Math.round(size)));
}

function serverColumnRequest(column) {
    return {
        id: column.id || column.fieldPath,
        fieldPath: column.fieldPath,
        linkToRecord: column.linkToRecord || 'auto'
    };
}

/** Row limit from config: a whole number from 1 to 2,000, else null (no limit). */
function validRowLimit(value) {
    const limit = Number(value);
    return Number.isInteger(limit) && limit >= 1 && limit <= MAX_ROW_LIMIT ? limit : null;
}

/** Stable client-side sort of loaded rows by one field; blank values sort last in either direction. */
function sortRowsClientSide(rows, fieldPath, sortDirection) {
    const factor = sortDirection === 'DESC' ? -1 : 1;
    const isBlank = (value) => value === null || value === undefined || value === '';
    return rows
        .map((row, index) => ({ row, index }))
        .sort((a, b) => {
            const left = a.row.values?.[fieldPath];
            const right = b.row.values?.[fieldPath];
            if (isBlank(left) || isBlank(right)) {
                return isBlank(left) === isBlank(right) ? a.index - b.index : isBlank(left) ? 1 : -1;
            }
            const order =
                typeof left === 'number' && typeof right === 'number'
                    ? left - right
                    : String(left).localeCompare(String(right), LOCALE, { numeric: true });
            return order * factor || a.index - b.index;
        })
        .map((entry) => entry.row);
}

/**
 * `{ bucketFields }` with the Bucket fields the columns show or the Table groups by (`bucket:<id>`), or `{}` when
 * there are none.
 */
function bucketColumnRequestFields(config, columns) {
    const groupEntries = Array.isArray(config.groupBy) ? config.groupBy : [];
    const bucketFields = columnBucketFields(config.bucketFields, [...columns, ...groupEntries]);
    return bucketFields.length ? { bucketFields } : {};
}

function configuredColumns(columns) {
    return Array.isArray(columns) ? columns.filter((column) => column && column.fieldPath) : [];
}

export default class BoardTableWidget extends NavigationMixin(LightningElement) {
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

    /**
     * Loaded table: `{ columns, rows, paginationCursor, nextIndex, hasMore, totalCount, sortBy, sortDirection }`
     * (`BoardQueryService.TableResult` with later `fetchTablePage` rows appended).
     */
    tableData = null;
    queryError = null;
    loadMoreError = null;
    isQuerying = false;
    isLoadingMore = false;
    /** Detail rows off, cursor tier: progress `{ percent, label, ... }` while chunks load; null otherwise. */
    _cursorProgress = null;
    bindingApplied = [];
    bindingIgnored = [];
    /** `ignoredFilterIds` of the last completed query; re-applied after every binding resolve. */
    _serverIgnoredIds = [];
    /** End-user header sort (`{ sortBy, sortDirection }`); overrides the configured default until config changes. */
    _sortOverride = null;
    /** End-user group order from the group column header; overrides the configured one until config changes. */
    _groupDirectionOverride = null;
    /** Row grouping collapse: every group follows `_collapseAllGroups` except the toggled ones. */
    _collapseAllGroups = false;
    _toggledGroups = new Set();
    _activeRequest = null;
    _cursorGeneration = 0;
    _latestRequestId = 0;
    _lastQuerySignature = null;
    _fieldsByObject = new Map();
    _widgetId = `boardTableWidget-${++widgetInstanceCount}`;
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

    /** `{ updateable, createable }` per object API name, from `getObjectInfos` for the Edit targets and Create objects. */
    permissionsByObject = new Map();

    @wire(getObjectInfos, { objectApiNames: '$permissionObjectApiNames' })
    wiredObjectInfos({ data }) {
        const permissions = new Map();
        (data?.results || []).forEach((entry) => {
            if (entry?.result?.apiName) {
                permissions.set(entry.result.apiName, {
                    updateable: entry.result.updateable === true,
                    createable: entry.result.createable === true,
                    keyPrefix: entry.result.keyPrefix || null
                });
            }
        });
        this.permissionsByObject = permissions;
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
        this._sortOverride = null;
        this._groupDirectionOverride = null;
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
        this._sortOverride = null;
        this._groupDirectionOverride = null;
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
        this.isLoadingMore = false;
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
        if (this.needsFieldsFetch(objectApiName, refreshToken)) {
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

    needsFieldsFetch(objectApiName, refreshToken) {
        return this._fieldsByObject.get(objectApiName)?.refreshToken !== refreshToken;
    }

    get isQueryable() {
        const parsed = this.resolvedConfig;
        return !parsed.error && !parsed.isUnconfigured && this.configColumns.length > 0;
    }

    /** Resolves bindings and opens a new cursor via `queryTable` unless the effective-query signature is unchanged. */
    async requestQuery() {
        if (!this.isQueryable || this.filterContext?.status !== 'READY') {
            return;
        }
        const objectApiName = this.effectiveObjectApiName;
        const refreshToken = this.filterContext.refreshToken || 0;
        // A new describe always means a new query (refreshToken is in the request): defer before calling Apex.
        if (this.needsFieldsFetch(objectApiName, refreshToken) && this._hiddenDeferral?.deferIfHidden()) {
            return;
        }
        let fields;
        try {
            fields = await this.loadFields(objectApiName, refreshToken);
        } catch (error) {
            if (objectApiName === this.effectiveObjectApiName) {
                this._latestRequestId += 1;
                this._lastQuerySignature = null;
                this.isQuerying = false;
                this.queryError = normalizeBoardError(error);
            }
            return;
        }

        // Re-read state after the describe await: config, sort, or filters may have changed meanwhile.
        const ctx = this.filterContext;
        if (
            !this._isConnected ||
            !this.isQueryable ||
            this.effectiveObjectApiName !== objectApiName ||
            ctx?.status !== 'READY'
        ) {
            return;
        }
        const config = this.resolvedConfig.config;
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
            this.isLoadingMore = false;
            this.queryError = resolution.error;
            return;
        }

        const sort = this.requestedSort;
        const rowLimit = this.rowLimit;
        const baseRequest = {
            objectApiName,
            columns: this.configColumns.map(serverColumnRequest),
            sortBy: sort.sortBy,
            sortDirection: sort.sortDirection,
            ...(rowLimit ? { rowLimit } : {}),
            pageSize: clampPageSize(config.pageSize ?? DEFAULT_PAGE_SIZE),
            filters: resolution.filters,
            baseFilters: Array.isArray(config.baseFilters) ? config.baseFilters : [],
            configCurrency: getConfigCurrency(this.effectiveBoardId),
            rowActions: serverRowActionRequest(this.rowActions),
            displayCurrency: getDisplayCurrency(this.effectiveBoardId),
            refreshToken: ctx.refreshToken || 0,
            widgetRefreshToken: this.widgetRefreshToken
        };
        const request = withGroupSummariesRequest(
            withTotalRowRequest(baseRequest, config, this.configColumns),
            config,
            this.configColumns
        );
        const groupBy = groupByRequest(config, this._groupDirectionOverride);
        if (groupBy) {
            request.groupBy = groupBy;
        }
        Object.assign(request, aggregateRequestFields(request, config));
        Object.assign(request, bucketColumnRequestFields(config, this.configColumns));
        const signature = buildQuerySignature(request);
        if (signature === this._lastQuerySignature || this._hiddenDeferral?.deferIfHidden()) {
            return;
        }
        this._lastQuerySignature = signature;
        const reqId = ++this._latestRequestId;
        this._serverIgnoredIds = [];
        this.applyBindingResolution(resolution);
        this.isQuerying = true;
        this.isLoadingMore = false;
        this.loadMoreError = null;
        this._cursorProgress = null;
        try {
            let result = await queryTable({ requestJson: JSON.stringify(request) });
            if (reqId !== this._latestRequestId) {
                return;
            }
            if (isIncompleteAggregateCursor(result)) {
                result = await this.followAggregateChunks(reqId, request, result);
                if (!result) {
                    return;
                }
            }
            const actionTargets = await withPolymorphicCandidates(
                this.rowActions,
                result?.rowActions,
                objectApiName,
                (name) => this.loadFields(name, ctx.refreshToken || 0)
            );
            if (reqId !== this._latestRequestId) {
                return;
            }
            this._serverIgnoredIds = result?.ignoredFilterIds || [];
            this.applyBindingResolution(resolution);
            this._activeRequest = request;
            this.tableData = {
                columns: result?.columns || [],
                rows: result?.rows || [],
                paginationCursor: result?.paginationCursor || null,
                nextIndex: result?.nextIndex || 0,
                hasMore: Boolean(result?.hasMore),
                totalCount: result?.totalCount ?? null,
                sortBy: result?.sortBy || null,
                sortDirection: result?.sortDirection || null,
                rowLimit: result?.rowLimit || null,
                groupLimit: result?.groupLimit || null,
                rowActions: actionTargets,
                totals: result?.totals ?? null,
                totalRowUnavailable: result?.totalRowUnavailable === true,
                barScales: result?.barScales || [],

                groupField: result?.groupField || null,
                groups: mergeGroups(null, result?.groups),
                aggregateGroups: result?.aggregateGroups || null
            };
            this.queryError = null;
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

    /** Detail rows off, cursor tier: reads every chunk with a progress bar; null when a newer run superseded it. */
    followAggregateChunks(reqId, request, first) {
        return followAggregateCursor({
            first,
            request,
            fetchChunk: fetchTableAggregateChunk,
            isCurrent: () => reqId === this._latestRequestId,
            onProgress: (progress) => {
                this._cursorProgress = progress;
            }
        });
    }

    /**
     * Appends the next cursor page. An expired cursor is transparently re-opened by `queryTable` at the same
     * `start` (with a new `cursorGeneration` so the cacheable call is not served from cache).
     */
    async loadMore() {
        const data = this.tableData;
        if (!data?.hasMore || !data.paginationCursor || this.isLoadingMore || this.isQuerying || !this._activeRequest) {
            return;
        }
        const reqId = this._latestRequestId;
        const request = this._activeRequest;
        this.isLoadingMore = true;
        this.loadMoreError = null;
        try {
            let page;
            try {
                page = await this.fetchNextPage(request, data);
            } catch (error) {
                if (normalizeBoardError(error).fieldPath !== CURSOR_EXPIRED_PATH || reqId !== this._latestRequestId) {
                    throw error;
                }
                page = await queryTable({
                    requestJson: JSON.stringify({
                        ...request,
                        start: data.nextIndex,
                        cursorGeneration: ++this._cursorGeneration
                    })
                });
            }
            if (reqId !== this._latestRequestId) {
                return;
            }
            this.tableData = {
                ...this.tableData,
                rows: [...this.tableData.rows, ...(page?.rows || [])],
                paginationCursor: page?.paginationCursor || null,
                nextIndex: page?.nextIndex || data.nextIndex,
                hasMore: Boolean(page?.hasMore),
                totalCount: page?.totalCount ?? this.tableData.totalCount,
                groups: mergeGroups(this.tableData.groups, page?.groups)
            };
        } catch (error) {
            if (reqId === this._latestRequestId) {
                this.loadMoreError = normalizeBoardError(error);
            }
        } finally {
            if (reqId === this._latestRequestId) {
                this.isLoadingMore = false;
            }
        }
    }

    /**
     * Next cursor page; a grouped Table's page also carries the full-group counts of its groups, and a Table with
     * Bucket field columns needs the request so the server can label the page's rows.
     */
    fetchNextPage(request, data) {
        if (request.groupBy || request.bucketFields) {
            return fetchGroupedTablePage({
                requestJson: JSON.stringify(request),
                paginationCursor: data.paginationCursor,
                start: data.nextIndex
            });
        }
        return fetchTablePage({
            paginationCursor: data.paginationCursor,
            start: data.nextIndex,
            pageSize: request.pageSize,
            displayCurrency: request.displayCurrency
        });
    }

    /** `<mark>` pattern for the text search terms applied to this Table's loaded query. */
    get highlightPattern() {
        const terms = (this._activeRequest?.filters || [])
            .filter((filter) => filter.type === 'TEXT' && filter.text)
            .map((filter) => filter.text);
        return buildHighlightPattern(terms);
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
        return parseAndMergeConfig('table', this._configJson, {
            boardId: this._boardIdExplicitlySet ? this._boardId : '',
            title: this._title,
            objectApiName: this._objectApiName
        });
    }

    get configColumns() {
        return configuredColumns(this.resolvedConfig.config?.columns);
    }

    /** Row actions show in the Setup dialog's Live preview but are disabled there (no navigation, no flow modal). */
    get rowActionsDisabled() {
        return this._livePreview;
    }

    /** Configured Row actions the Table can run (view / edit / create / flow). */
    get rowActions() {
        return normalizeRowActions(this.resolvedConfig.config?.rowActions);
    }

    /** Objects whose Edit/Create permission the Row actions need, or `undefined` (wire idle) when there are none. */
    get permissionObjectApiNames() {
        const names = permissionObjectApiNames(this.rowActions, this.tableData?.rowActions);
        return names.length ? names : undefined;
    }

    /** Configured Row limit (Top N), or null; a limited Table is one bounded page that header clicks re-sort locally. */
    get rowLimit() {
        return validRowLimit(this.resolvedConfig.config?.rowLimit);
    }

    /** Sort sent to `queryTable`: the end user's header choice, else the configured default (always, when limited). */
    get requestedSort() {
        if (this._sortOverride && (!this.rowLimit || this.isGroupedConfig)) {
            return this._sortOverride;
        }
        const config = this.resolvedConfig.config || {};
        return {
            sortBy: config.sortBy || null,
            sortDirection: String(config.sortDirection || '').toUpperCase() === 'DESC' ? 'DESC' : 'ASC'
        };
    }

    get effectiveTitle() {
        return this.resolvedConfig.config?.title || 'Table';
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

    get activeScopeKey() {
        return this.filterContext?.scopeKey || '';
    }

    get viewState() {
        const parsed = this.resolvedConfig;
        if (parsed.error) {
            return 'ERROR';
        }
        if (parsed.isUnconfigured || !this.configColumns.length) {
            return 'UNCONFIGURED';
        }
        if (this.filterContext?.error || this.queryError) {
            return 'ERROR';
        }
        if (!this.tableData) {
            return 'INITIAL_LOADING';
        }
        if (!this.tableData.rows.length && !this.tableData.aggregateGroups?.length) {
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

    /** Cursor-tier progress of the latest run while it loads; null otherwise. */
    get cursorProgress() {
        return this.isQuerying ? this._cursorProgress : null;
    }

    get showCursorProgress() {
        return Boolean(this.cursorProgress);
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
        return this.isQuerying && Boolean(this.tableData);
    }

    get ariaBusy() {
        return this.isQuerying || this.isLoadingMore ? 'true' : 'false';
    }

    get bodyClass() {
        return this.isRefreshing ? 'c-board-table-content c-board-table-content_refreshing' : 'c-board-table-content';
    }

    get showRowCount() {
        return (
            this.resolvedConfig.config?.showRowCount !== false &&
            typeof this.tableData?.totalCount === 'number' &&
            !this.showWidgetState
        );
    }

    /** Row grouping configured: a Row limit then counts first-level groups, and header clicks re-query. */
    get isGroupedConfig() {
        return Boolean(groupByRequest(this.resolvedConfig.config || {}, null));
    }

    get rowCountLabel() {
        const total = this.tableData?.totalCount || 0;
        const groupLimit = this.tableData?.groupLimit;
        if (groupLimit) {
            return `Top ${formatCount(groupLimit)} groups · ${formatCount(total)} ${total === 1 ? 'record' : 'records'}`;
        }
        const limit = this.tableData?.rowLimit;
        if (limit && total > limit) {
            return `Top ${formatCount(limit)} of ${formatCount(total)}`;
        }
        const formatted = formatCount(total);
        // Detail rows off counts every record exactly (the cursor tier reads up to 200,000); no pagination cap.
        const suffix = total >= MAX_TABLE_ROWS && !this.isAggregate ? '+' : '';
        return `${formatted}${suffix} ${total === 1 ? 'record' : 'records'}`;
    }

    get columnViews() {
        return buildColumnViews(
            this.tableData?.columns,
            this.configColumns,
            {
                sortBy: this.tableData?.sortBy,
                sortDirection: this.tableData?.sortDirection
            },
            this.tableData?.barScales
        );
    }

    /** Column headers: the group column (Row grouping), the data columns, then the Row action columns. */
    get headerViews() {
        const groupHeader = this.isAggregate
            ? buildAggregateGroupHeader(this.groupField, this.tableData.sortBy)
            : buildGroupHeader(this.groupField);
        const groupHeaders = this.groupField ? [groupHeader] : [];
        return [...groupHeaders, ...this.columnViews, ...buildActionHeaders(this.rowActions)];
    }

    /** Resolved group field of a grouped Table (`{ fieldPath, labelPath, label, sortDirection }`), else null. */
    get groupField() {
        return this.tableData?.groupField || null;
    }

    get isGrouped() {
        return Boolean(this.groupField);
    }

    /** Detail rows off: the Table shows only its Group rows (an aggregated table). */
    get isAggregate() {
        return Boolean(this.tableData?.aggregateGroups);
    }

    /** Collapse all / Expand all: grouped Tables with Detail rows on. */
    get showGroupCollapse() {
        return this.isGrouped && !this.isAggregate;
    }

    isGroupCollapsed(token) {
        return this._collapseAllGroups !== this._toggledGroups.has(token);
    }

    /** Rendered rows: `{ key, id, cells[] }` (data cells, then action cells). */
    get rowViews() {
        if (this.isAggregate) {
            return this.withGroupRowActions(
                buildAggregateRowViews(this.tableData.aggregateGroups, this.headerViews, this.columnViews, formatCount)
            );
        }
        const columns = this.columnViews;
        const highlight = this.highlightPattern;
        const actions = this.rowActions;
        const targets = this.tableData?.rowActions || [];
        const groupField = this.groupField;
        const buildDetail = (row) => ({
            key: row.id,
            id: row.id,
            rowClass: groupField ? 'slds-hint-parent c-board-table-detail-row' : 'slds-hint-parent',
            cells: [
                ...(groupField ? [groupSpacerCell(row.id)] : []),
                ...columns.map((column) => buildCellView(column, row, highlight)),
                ...buildActionCells(actions, row, targets, this.permissionsByObject)
            ]
        });
        const rows = this.tableData?.rows || [];
        if (!groupField) {
            return rows.map(buildDetail);
        }
        const views = buildGroupedRows(
            rows,
            groupField,
            this.tableData.groups,
            (token) => this.isGroupCollapsed(token),
            buildDetail,
            formatCount
        );
        return this.withGroupRowActions(
            withGroupSummaryRows(views, {
                groupsByToken: this.tableData.groups,
                headerViews: this.headerViews,
                columnViews: columns,
                showSubtotals: this.resolvedConfig.config?.showSubtotals === true,
                complete: !this.tableData.hasMore
            })
        );
    }

    /** Group rows offer only the Row actions acting on the group's lookup record (`groupRowActions`). */
    withGroupRowActions(views) {
        return withGroupRowActions(views, {
            actions: this.rowActions,
            actionHeaders: buildActionHeaders(this.rowActions),
            headerCount: this.headerViews.length,
            tableData: this.tableData,
            permissionsByObject: this.permissionsByObject
        });
    }

    /** Total row (sticky footer), or null when the Total row is off. */
    get totalRowView() {
        const data = this.tableData;
        return buildTotalRowView(this.headerViews, this.columnViews, data?.totals, data?.totalRowUnavailable === true);
    }

    get showLoadMore() {
        return Boolean(this.tableData?.hasMore) && !this.isLoadingMore;
    }

    get loadMoreErrorMessage() {
        return this.loadMoreError?.message || '';
    }

    // -----------------------------------------------------------------------------------------------------
    // Actions
    // -----------------------------------------------------------------------------------------------------

    handleSort(event) {
        if (this.isAggregate) {
            this.tableData = sortAggregateTable(this.tableData, event.currentTarget.dataset);
            return;
        }
        if (event.currentTarget.dataset.columnId === GROUP_COLUMN_ID) {
            this.toggleGroupOrder();
            return;
        }
        const fieldPath = event.currentTarget.dataset.fieldPath;
        if (!fieldPath) {
            return;
        }
        const current = this.tableData || {};
        const sortDirection = current.sortBy === fieldPath && current.sortDirection === 'ASC' ? 'DESC' : 'ASC';
        if (current.rowLimit) {
            this.tableData = {
                ...current,
                rows: sortRowsClientSide(current.rows, fieldPath, sortDirection),
                sortBy: fieldPath,
                sortDirection
            };
            return;
        }
        this._sortOverride = { sortBy: fieldPath, sortDirection };
        this.requestQuery();
    }

    /** Group column header: flips the group order and keeps the within-group sort. */
    toggleGroupOrder() {
        this._groupDirectionOverride = toggledGroupDirection(this.groupField);
        this.requestQuery();
    }

    handleGroupToggle(event) {
        const token = event.currentTarget.dataset.groupToken || '';
        const toggled = new Set(this._toggledGroups);
        if (toggled.has(token)) {
            toggled.delete(token);
        } else {
            toggled.add(token);
        }
        this._toggledGroups = toggled;
    }

    handleCollapseAll() {
        this._collapseAllGroups = true;
        this._toggledGroups = new Set();
    }

    handleExpandAll() {
        this._collapseAllGroups = false;
        this._toggledGroups = new Set();
    }

    handleScroll(event) {
        const container = event.currentTarget;
        if (container.scrollTop + container.clientHeight >= container.scrollHeight - SCROLL_THRESHOLD_PX) {
            this.loadMore();
        }
    }

    handleLoadMore() {
        this.loadMore();
    }

    handleRecordLinkClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.recordId;
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    handleActionClick(event) {
        this.runRowAction(event.currentTarget.dataset.rowId, event.currentTarget.dataset.actionId);
    }

    handleActionSelect(event) {
        this.runRowAction(event.currentTarget.dataset.rowId, event.detail.value);
    }

    /**
     * View / Edit open the target record's standard page; Create opens the standard create modal pre-filled from the
     * row. The platform enforces CRUD/FLS. The Setup dialog's Live preview is inert: no action runs.
     */
    runRowAction(rowId, actionId) {
        if (this.rowActionsDisabled) {
            return;
        }
        const action = this.rowActions.find((candidate) => candidate.id === actionId);
        const row =
            (this.tableData?.rows || []).find((candidate) => candidate.id === rowId) ||
            resolveGroupActionRow(rowId, this.tableData);
        if (action?.type === 'create' && row) {
            const serverTarget = (this.tableData.rowActions || []).find((target) => target.id === action.id);
            this[NavigationMixin.Navigate](
                buildCreatePageReference(action, row, serverTarget, encodeDefaultFieldValues)
            );
            return;
        }
        if (action?.type === 'flow' && row) {
            this.runFlowAction(action, row);
            return;
        }
        const recordId = action && row ? resolveActionRecordId(action, row, this.tableData.rowActions) : null;
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: action.type }
        });
    }

    /** Shown again after a Filter change while hidden: loading state instead of stale data, then one query. */
    handleShownStale() {
        this.tableData = null;
        this.queryError = null;
        this.requestQuery();
    }

    /** Opens the Screen Flow in a modal with the mapped row values; refreshes the Table only when the flow finishes. */
    async runFlowAction(action, row) {
        const serverTarget = (this.tableData.rowActions || []).find((target) => target.id === action.id);
        const result = await BoardTableFlowModal.open({
            size: 'medium',
            label: action.label,
            flowApiName: action.flowApiName,
            inputVariables: buildFlowInputVariables(action, row, serverTarget)
        });
        if (result?.finished) {
            this.handleRefresh();
        }
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