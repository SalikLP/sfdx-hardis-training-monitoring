import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import LOCALE from '@salesforce/i18n/locale';
import getObjectFields from '@salesforce/apex/BoardSchemaService.getObjectFields';
import queryTable from '@salesforce/apex/BoardQueryService.queryTable';
import fetchTablePage from '@salesforce/apex/BoardQueryService.fetchTablePage';
import queryChildRows from '@salesforce/apex/BoardQueryService.queryChildRows';
import {
    parseAndMergeConfig,
    normalizeBoardError,
    resolveFilterBindings,
    applyServerIgnoredFilters,
    buildFilterBindingSummary,
    buildQuerySignature
} from 'c/boardConfigUtils';
import { subscribeFilterContext, publishFilterContext, acceptExternalFilterContext } from 'c/boardContextStore';
import { buildColumnViews, buildCellView, buildHighlightPattern } from './tableCells';

const DEFAULT_PAGE_SIZE = 25;
const MIN_PAGE_SIZE = 10;
const MAX_PAGE_SIZE = 100;
/** Rows a `Database.PaginationCursor` spans at most; the count badge shows `100,000+` at the cap. */
const MAX_TABLE_ROWS = 100000;
/** Distance (px) from the bottom of the scroll container that triggers the next page. */
const SCROLL_THRESHOLD_PX = 48;
/** `fieldPath` of the retryable `QUERY_ERROR` `fetchTablePage` raises when the held cursor expired. */
const CURSOR_EXPIRED_PATH = 'paginationCursor';
const DEFAULT_CHILD_LIMIT = 10;
const MAX_CHILD_LIMIT = 50;
let widgetInstanceCount = 0;

function clampPageSize(value) {
    const size = Number(value);
    if (!Number.isFinite(size)) {
        return DEFAULT_PAGE_SIZE;
    }
    return Math.min(MAX_PAGE_SIZE, Math.max(MIN_PAGE_SIZE, Math.round(size)));
}

function clampChildLimit(value) {
    const limit = Number(value);
    if (!Number.isFinite(limit)) {
        return DEFAULT_CHILD_LIMIT;
    }
    return Math.min(MAX_CHILD_LIMIT, Math.max(1, Math.round(limit)));
}

function serverColumnRequest(column) {
    return {
        id: column.id || column.fieldPath,
        fieldPath: column.fieldPath,
        linkToRecord: column.linkToRecord || 'auto'
    };
}

function configuredColumns(columns) {
    return Array.isArray(columns) ? columns.filter((column) => column && column.fieldPath) : [];
}

/**
 * Child state of rows the server auto-expanded because the text search matched their child records. The seeded
 * rows are the matches only (`matchedOnly`); a manual re-expand fetches the full child list.
 */
function autoExpandedChildState(rows) {
    const state = {};
    (rows || []).forEach((row) => {
        if (row.autoExpanded && row.children) {
            state[row.id] = { expanded: true, loading: false, result: row.children, error: null, matchedOnly: true };
        }
    });
    return state;
}

export default class BoardTableWidget extends NavigationMixin(LightningElement) {
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

    /**
     * Loaded table: `{ columns, rows, paginationCursor, nextIndex, hasMore, totalCount, sortBy, sortDirection }`
     * (`BoardQueryService.TableResult` with later `fetchTablePage` rows appended).
     */
    tableData = null;
    queryError = null;
    loadMoreError = null;
    isQuerying = false;
    isLoadingMore = false;
    bindingApplied = [];
    bindingIgnored = [];
    /** `ignoredFilterIds` of the last completed query; re-applied after every binding resolve. */
    _serverIgnoredIds = [];
    /**
     * Child sub-tables of the loaded query, keyed by parent row Id: `{ expanded, loading, result, error,
     * matchedOnly }` (`result` = `BoardQueryService.ChildRowsResult`). Cleared whenever `queryTable` loads a new
     * result, so filters, sorting, and refresh invalidate it.
     */
    childState = {};

    /** End-user header sort (`{ sortBy, sortDirection }`); overrides the configured default until config changes. */
    _sortOverride = null;
    _activeRequest = null;
    _cursorGeneration = 0;
    _latestRequestId = 0;
    _lastQuerySignature = null;
    _fieldsByObject = new Map();
    _widgetId = `boardTableWidget-${++widgetInstanceCount}`;
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
        this._sortOverride = null;
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
        this.isLoadingMore = false;
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
            widgetId: this._widgetId
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
        const request = {
            objectApiName,
            columns: this.configColumns.map(serverColumnRequest),
            sortBy: sort.sortBy,
            sortDirection: sort.sortDirection,
            pageSize: clampPageSize(config.pageSize ?? DEFAULT_PAGE_SIZE),
            childRelationship: this.childConfig,
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
        this.isLoadingMore = false;
        this.loadMoreError = null;
        try {
            const result = await queryTable({ requestJson: JSON.stringify(request) });
            if (reqId !== this._latestRequestId) {
                return;
            }
            this._serverIgnoredIds = result?.ignoredFilterIds || [];
            this.applyBindingResolution(resolution);
            this._activeRequest = request;
            this.childState = {};
            this.tableData = {
                columns: result?.columns || [],
                rows: result?.rows || [],
                paginationCursor: result?.paginationCursor || null,
                nextIndex: result?.nextIndex || 0,
                hasMore: Boolean(result?.hasMore),
                totalCount: result?.totalCount ?? null,
                sortBy: result?.sortBy || null,
                sortDirection: result?.sortDirection || null,
                searchChildIds: result?.searchChildIds || []
            };
            this.applyAutoExpanded(result?.rows);
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
                page = await fetchTablePage({
                    paginationCursor: data.paginationCursor,
                    start: data.nextIndex,
                    pageSize: request.pageSize,
                    childConfig: this.pageChildConfig(request)
                });
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
                totalCount: page?.totalCount ?? this.tableData.totalCount
            };
            this.applyAutoExpanded(page?.rows);
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
     * Expands (lazily fetching once per loaded query) or collapses one parent row's child sub-table. Expanding a row
     * that holds only search-matched children (or a failed load) fetches the full child list.
     */
    toggleChildRows(parentId) {
        const request = this._activeRequest;
        if (!request?.childRelationship) {
            return;
        }
        const current = this.childState[parentId];
        if (current?.expanded) {
            this.setChildState(parentId, { ...current, expanded: false });
            return;
        }
        if (current && !current.error && !current.matchedOnly) {
            this.setChildState(parentId, { ...current, expanded: true });
            return;
        }
        this.fetchChildRows(parentId);
    }

    /** Fetches one parent row's full child list (expanded, with an inline spinner while loading). */
    async fetchChildRows(parentId) {
        const request = this._activeRequest;
        if (!request?.childRelationship) {
            return;
        }
        this.setChildState(parentId, { expanded: true, loading: true, result: null, error: null });
        const reqId = this._latestRequestId;
        try {
            const result = await queryChildRows({
                childConfig: JSON.stringify({
                    ...request.childRelationship,
                    refreshToken: request.refreshToken,
                    widgetRefreshToken: request.widgetRefreshToken
                }),
                parentId
            });
            if (reqId === this._latestRequestId) {
                this.setChildRows(parentId, result);
            }
        } catch (error) {
            if (reqId === this._latestRequestId) {
                this.setChildState(parentId, {
                    ...this.childState[parentId],
                    loading: false,
                    error: normalizeBoardError(error)
                });
            }
        }
    }

    /** Caches one parent row's full child rows for the loaded query (keeps its expanded state). */
    setChildRows(parentId, result) {
        this.setChildState(parentId, {
            expanded: this.childState[parentId]?.expanded ?? false,
            loading: false,
            result,
            error: null,
            matchedOnly: false
        });
    }

    /** Expands rows whose child records matched the text search, with their batch-fetched matching children. */
    applyAutoExpanded(rows) {
        const expanded = autoExpandedChildState(rows);
        Object.keys(expanded).forEach((parentId) => this.setChildState(parentId, expanded[parentId]));
    }

    /** `fetchTablePage` child config: the relationship plus search-matched child Ids so later pages auto-expand. */
    pageChildConfig(request) {
        if (!request.childRelationship) {
            return null;
        }
        const matchedChildIds = this.tableData?.searchChildIds || [];
        return JSON.stringify(
            matchedChildIds.length ? { ...request.childRelationship, matchedChildIds } : request.childRelationship
        );
    }

    /** `<mark>` pattern for the text search terms applied to this Table's loaded query. */
    get highlightPattern() {
        const terms = (this._activeRequest?.filters || [])
            .filter((filter) => filter.type === 'TEXT' && filter.text)
            .map((filter) => filter.text);
        return buildHighlightPattern(terms);
    }

    setChildState(parentId, state) {
        this.childState = { ...this.childState, [parentId]: state };
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

    /**
     * Normalized `childRelationship` sent to `queryTable`, `fetchTablePage`, and `queryChildRows`; null when the
     * Table has none or it is incomplete.
     */
    get childConfig() {
        const child = this.resolvedConfig.config?.childRelationship;
        const columns = configuredColumns(child?.columns);
        if (!child || !child.childObjectApiName || !child.foreignKeyField || !columns.length) {
            return null;
        }
        return {
            relationshipName: child.relationshipName || null,
            childObjectApiName: child.childObjectApiName,
            foreignKeyField: child.foreignKeyField,
            columns: columns.map(serverColumnRequest),
            sortBy: child.sortBy || null,
            sortDirection: String(child.sortDirection || '').toUpperCase() === 'DESC' ? 'DESC' : 'ASC',
            limit: clampChildLimit(child.limit ?? DEFAULT_CHILD_LIMIT)
        };
    }

    get childLabel() {
        const child = this.resolvedConfig.config?.childRelationship;
        return child?.label || child?.relationshipName || child?.childObjectApiName || 'Related records';
    }

    /** Sort sent to `queryTable`: the end user's header choice, else the configured default. */
    get requestedSort() {
        if (this._sortOverride) {
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
        if (!this.tableData.rows.length) {
            return 'EMPTY';
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

    get rowCountLabel() {
        const total = this.tableData?.totalCount || 0;
        const formatted = new Intl.NumberFormat(LOCALE).format(total);
        const suffix = total >= MAX_TABLE_ROWS ? '+' : '';
        return `${formatted}${suffix} ${total === 1 ? 'record' : 'records'}`;
    }

    get columnViews() {
        return buildColumnViews(this.tableData?.columns, this.configColumns, {
            sortBy: this.tableData?.sortBy,
            sortDirection: this.tableData?.sortDirection
        });
    }

    /**
     * Rendered rows: `{ key, id, cells[], hasChildren, child }`. With a child relationship, the first cell
     * renders the count badge + expand chevron, and an expanded row's `child` renders the sibling
     * `<tr colspan>` sub-row (`key: ${row.key}-children`).
     */
    get rowViews() {
        const columns = this.columnViews;
        const highlight = this.highlightPattern;
        const hasChildren = Boolean(this._activeRequest?.childRelationship);
        return (this.tableData?.rows || []).map((row) => {
            const cells = columns.map((column) => buildCellView(column, row, highlight));
            const view = { key: row.id, id: row.id, cells, hasChildren, child: null };
            if (hasChildren && cells.length) {
                cells[0] = { ...cells[0], showExpander: true };
                Object.assign(view, this.buildChildView(row, columns.length, highlight));
            }
            return view;
        });
    }

    buildChildView(row, colspan, highlight) {
        // A null count with `childCountCapped` means the server could not count this parent's children.
        const unknownCount = row.childCountCapped === true && (row.childCount === null || row.childCount === undefined);
        const childCount = row.childCount || 0;
        const canExpand = childCount > 0 || unknownCount;
        const state = this.childState[row.id];
        const expanded = Boolean(state?.expanded) && canExpand;
        const view = {
            childBadgeLabel: unknownCount ? '?' : `${childCount}${row.childCountCapped ? '+' : ''}`,
            canExpand,
            ariaExpanded: expanded ? 'true' : 'false',
            chevron: expanded ? '▾' : '▸',
            expandLabel: `${expanded ? 'Collapse' : 'Expand'} ${this.childLabel}`
        };
        if (expanded) {
            const result = state.result;
            const columns = result
                ? buildColumnViews(result.columns, this.resolvedConfig.config?.childRelationship?.columns, {
                      sortBy: result.sortBy,
                      sortDirection: result.sortDirection
                  })
                : [];
            const rows = (result?.rows || []).map((childRow) => ({
                key: childRow.id,
                cells: columns.map((column) => buildCellView(column, childRow, highlight))
            }));
            view.child = {
                key: `${row.id}-children`,
                rowId: row.id,
                colspan,
                label: this.childLabel,
                isLoading: Boolean(state.loading),
                errorMessage: state.error?.message || '',
                hasRows: rows.length > 0,
                isEmpty: Boolean(result) && !rows.length,
                // Search auto-expansion seeds only the matching children; say so and offer the full list.
                matchSummary:
                    state.matchedOnly && result
                        ? `Showing ${rows.length} of ${view.childBadgeLabel} ${this.childLabel} matching the search.`
                        : '',
                showAllLabel: `Show all ${this.childLabel}`,
                columns,
                rows
            };
        }
        return view;
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
        const fieldPath = event.currentTarget.dataset.fieldPath;
        if (!fieldPath) {
            return;
        }
        const current = this.tableData || {};
        const sortDirection = current.sortBy === fieldPath && current.sortDirection === 'ASC' ? 'DESC' : 'ASC';
        this._sortOverride = { sortBy: fieldPath, sortDirection };
        this.requestQuery();
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

    handleToggleChildren(event) {
        const parentId = event.currentTarget.dataset.rowId;
        if (parentId) {
            this.toggleChildRows(parentId);
        }
    }

    handleShowAllChildren(event) {
        const parentId = event.currentTarget.dataset.rowId;
        if (parentId) {
            this.fetchChildRows(parentId);
        }
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