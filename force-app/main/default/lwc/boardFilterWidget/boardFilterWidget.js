import { LightningElement, api, wire } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { RefreshEvent, registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import FORM_FACTOR from '@salesforce/client/formFactor';
import getPicklistOptions from '@salesforce/apex/BoardSchemaService.getPicklistOptions';
import resolveRecordLabels from '@salesforce/apex/BoardSchemaService.resolveRecordLabels';
import searchUsersAndQueues from '@salesforce/apex/BoardSchemaService.searchUsersAndQueues';
import {
    parseAndMergeConfig,
    normalizeBoardError,
    DATE_PRESET_GROUPS,
    DATE_PRESETS,
    DATE_RANGE_OPERATORS
} from 'c/boardConfigUtils';
import {
    registerFilterWidget,
    publishFilterContext,
    subscribeFilterContext,
    acceptExternalFilterContext,
    setScopeWidgetError,
    recordContextOverrideDefinition,
    buildFilterStorageKey,
    readStoredFilterState,
    writeStoredFilterState,
    clearStoredFilterState,
    normalizeFilterDefinitions,
    sanitizeStoredFilters,
    resolveInitialFilters,
    buildFilterValue,
    buildFilterEntry,
    clearedFilterValue,
    dateRangeOperator,
    toStoredFilterEntry
} from 'c/boardContextStore';

const SELECTION_DEBOUNCE_MS = 150;
const USER_SEARCH_DEBOUNCE_MS = 300;
const TEXT_SEARCH_DEBOUNCE_MS = 300;
const PICKLIST_SEARCH_THRESHOLD = 7;
const NARROW_CONTAINER_PX = 768;
const PERSISTENCE_MODES = ['SESSION', 'LOCAL', 'NONE'];
const RECORD_CONTEXT_MODES = ['IMPLICIT', 'LOCKED', 'DEFAULT'];
const CUSTOM_DATE_RANGE = 'CUSTOM';
const CUSTOM_DATE_OPERATORS = DATE_RANGE_OPERATORS.filter((operator) => operator !== 'LITERAL');
const PENDING_LABEL = 'Loading…';
const UNKNOWN_RECORD_LABEL = 'Unavailable record';
const DATE_PRESET_LABELS = new Map(DATE_PRESETS.map((preset) => [preset.value, preset.label]));

function cleanString(value) {
    return value !== undefined && value !== null && String(value).trim() ? String(value).trim() : null;
}

function eventValue(event) {
    if (event.detail && event.detail.value !== undefined) {
        return event.detail.value;
    }
    return event.target.value;
}

function titleCase(token) {
    return token
        .toLowerCase()
        .split('_')
        .filter(Boolean)
        .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
        .join(' ');
}

/** Preset label, or a readable label for any other relative literal (`NEXT_WEEK`, `LAST_N_DAYS:14`). */
function describeDateLiteral(literal) {
    const preset = DATE_PRESET_LABELS.get(literal);
    if (preset) {
        return preset;
    }
    const nLiteral = /^(LAST|NEXT)_N_([A-Z_]+):(\d+)$/.exec(literal);
    if (nLiteral) {
        return `${titleCase(nLiteral[1])} ${nLiteral[3]} ${titleCase(nLiteral[2])}`;
    }
    return titleCase(literal);
}

export default class BoardFilterWidget extends LightningElement {
    _boardId = 'default';
    _boardIdExplicitlySet = false;
    _title = '';
    _recordId = '';
    _filterContextJson = '';
    _pendingExternalJson = null;
    _configJson = '';

    filterContext = null;
    _unsubscribe = null;
    _isConnected = false;
    _initEpoch = 0;

    _defs = [];
    _persistence = 'SESSION';
    _storageKey = null;
    _storedFilters = {};
    _labelCache = {};
    _unresolvedLabelIds = {};
    _labelRequests = new Set();
    _picklistOptions = {};
    _picklistErrors = {};
    _drafts = {};
    _debounceTimers = {};
    _openPicklistId = null;
    _picklistSearch = {};
    _userSearch = {};
    /** Raw text typed into each `TEXT` control (may be shorter than `minCharacters`, so not yet published). */
    _textInput = {};
    _userSearchTimers = {};
    _dateCustomMode = {};
    _isNarrow = false;
    _drawerExpanded = false;
    _resizeObserver = null;
    _refreshHandlerId = null;
    _loadedAt = Date.now();
    /** Configuration or Record context failure this Filter widget raised as the scope-wide Widget error. */
    _scopeError = null;

    // Host-record traversal for recordContext.overrideFieldPath (two-step: record type, then field value). The field
    // wire stays bound after READY so a record edit (or a lightning/refresh RefreshEvent) re-reads the value.
    _requiresTraversal = false;
    _recordContextBase = null;
    _pendingRecordContext = null;
    _hostTypeRecordId;
    _overrideRecordId;
    _overrideFields;

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
            this.initializeContext();
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
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value || '';
        if (this._isConnected) {
            this.initializeContext();
        }
    }

    @api
    get filterContextJson() {
        return this._filterContextJson;
    }
    set filterContextJson(value) {
        const raw = value ? String(value) : '';
        if (!raw || raw === this._filterContextJson) {
            return;
        }
        this._filterContextJson = raw;
        if (this._isConnected && this.filterContext) {
            this.acceptExternalContext(raw);
        } else {
            this._pendingExternalJson = raw;
        }
    }

    @api
    get configJson() {
        return this._configJson;
    }
    set configJson(value) {
        this._configJson = value || '';
        if (this._isConnected) {
            this.initializeContext();
        }
    }

    connectedCallback() {
        this._isConnected = true;
        this.initializeContext();
        try {
            this._refreshHandlerId = registerRefreshHandler(this.template.host, () => this.handlePageRefresh());
        } catch (e) {
            // Ignore in environments without the refresh service
        }
    }

    renderedCallback() {
        if (this._resizeObserver || typeof window.ResizeObserver !== 'function') {
            return;
        }
        const card = this.template.querySelector('.c-board-card');
        if (!card) {
            return;
        }
        this._resizeObserver = new window.ResizeObserver((entries) => {
            const width = entries && entries[0] && entries[0].contentRect ? entries[0].contentRect.width : 0;
            if (width > 0) {
                const narrow = width < NARROW_CONTAINER_PX;
                if (narrow !== this._isNarrow) {
                    this._isNarrow = narrow;
                }
            }
        });
        this._resizeObserver.observe(card);
    }

    disconnectedCallback() {
        this._isConnected = false;
        this.teardown();
        if (this._resizeObserver) {
            this._resizeObserver.disconnect();
            this._resizeObserver = null;
        }
        if (this._refreshHandlerId) {
            try {
                unregisterRefreshHandler(this._refreshHandlerId);
            } catch (e) {
                // Ignore
            }
            this._refreshHandlerId = null;
        }
    }

    teardown() {
        if (this._unsubscribe) {
            this._unsubscribe();
            this._unsubscribe = null;
        }
        this.cancelPendingSelections();
        Object.values(this._userSearchTimers).forEach((timer) => clearTimeout(timer));
        this._userSearchTimers = {};
    }

    cancelPendingSelections() {
        Object.values(this._debounceTimers).forEach((timer) => clearTimeout(timer));
        this._debounceTimers = {};
        this._drafts = {};
    }

    // ---------------------------------------------------------------------------------------------
    // Initialization: INITIALIZING barrier -> Web Storage hydration -> recordContext resolution -> READY
    // ---------------------------------------------------------------------------------------------

    initializeContext() {
        this.teardown();
        this._initEpoch += 1;

        const effectiveBoardId = this.effectiveBoardId;
        const cleanRecordId = cleanString(this._recordId);
        const parsedConfig = this.resolvedConfig;
        const cfg = parsedConfig.config;
        const definitionErrors = [];

        this._defs = normalizeFilterDefinitions(cfg?.filters, definitionErrors);
        this._persistence = PERSISTENCE_MODES.includes(cfg?.persistence) ? cfg.persistence : 'SESSION';
        this._dateCustomMode = {};
        this._openPicklistId = null;
        this._picklistSearch = {};
        this._userSearch = {};
        this._scopeError = null;
        this._recordContextBase = null;
        this._pendingRecordContext = null;
        this._hostTypeRecordId = undefined;
        this._overrideRecordId = undefined;
        this._overrideFields = undefined;

        const recordCtxConfig = cfg?.recordContext || {};
        const overrideFieldPath = cleanString(recordCtxConfig.overrideFieldPath);
        this._requiresTraversal = Boolean(cleanRecordId && overrideFieldPath && overrideFieldPath !== 'Id');
        const recordContext = {
            recordId: cleanRecordId,
            objectApiName: null,
            overrideFilterId: cleanString(recordCtxConfig.overrideFilterId),
            overrideFieldPath,
            resolvedValue: this._requiresTraversal ? null : cleanRecordId,
            mode: RECORD_CONTEXT_MODES.includes(recordCtxConfig.mode) ? recordCtxConfig.mode : 'IMPLICIT',
            overrideApplies: false
        };
        recordContext.overrideApplies = Boolean(recordContextOverrideDefinition(this._defs, recordContext));

        // 1. Synchronously set the INITIALIZING barrier
        const initializingCtx = registerFilterWidget(
            effectiveBoardId,
            cleanRecordId,
            {
                recordContext,
                filters: resolveInitialFilters(this._defs, { recordContext: null, userId: USER_ID })
            },
            { definitions: this._defs, userId: USER_ID }
        );
        this.filterContext = initializingCtx;
        this._unsubscribe = subscribeFilterContext(effectiveBoardId, cleanRecordId, (ctx) => {
            this.reconcileTextInput(ctx);
            this.filterContext = ctx;
            if (ctx.status === 'READY' || ctx.error) {
                this.syncContextOutput(ctx);
            }
        });
        this._storageKey = buildFilterStorageKey(USER_ID, initializingCtx.scopeKey);

        // 2. Broken configuration fails closed: Widgets render the error and never query unscoped data
        const configError = parsedConfig.error || definitionErrors[0] || null;
        if (configError) {
            this.raiseScopeError(configError);
            return;
        }

        // 3. Synchronous Web Storage hydration + config-drift sanitization
        this.hydrateStoredFilters();
        this.loadPicklistOptions();

        // 4. A reactive filterContextJson input received before mount applies on top of READY
        if (this._pendingExternalJson) {
            const pending = this._pendingExternalJson;
            this._pendingExternalJson = null;
            this.acceptExternalContext(pending);
        }

        // 5. Resolve recordContext.overrideFieldPath on the host record before READY
        if (this._requiresTraversal) {
            this._pendingRecordContext = recordContext;
            this._hostTypeRecordId = cleanRecordId;
            this.syncContextOutput(initializingCtx);
            return;
        }
        this.finalizeInitialization(recordContext);
    }

    /** Hands a reactive Flow input to the store; a rejected input is answered by echoing the actual context. */
    acceptExternalContext(raw) {
        if (
            !acceptExternalFilterContext(this.effectiveBoardId, cleanString(this._recordId), raw) &&
            this.filterContext
        ) {
            this.syncContextOutput(this.filterContext);
        }
    }

    hydrateStoredFilters() {
        this._storedFilters = {};
        if (this._persistence === 'NONE') {
            clearStoredFilterState(this._storageKey);
            return;
        }
        const { filters, labels } = sanitizeStoredFilters(
            this._defs,
            readStoredFilterState(this._persistence, this._storageKey),
            USER_ID
        );
        this._storedFilters = filters;
        this._labelCache = { ...this._labelCache, ...labels };
    }

    /**
     * Fail-closed check of a resolved Record context: an `overrideFieldPath` that yields no value cannot scope the
     * Board (except a `DEFAULT` override, which only pre-fills a user-editable filter).
     */
    recordContextFailure(recordContext) {
        if (!this._requiresTraversal || recordContext.resolvedValue) {
            return null;
        }
        if (recordContext.mode === 'DEFAULT' && recordContext.overrideApplies) {
            return null;
        }
        return {
            category: 'CONFIG_ERROR',
            message: `Record context: the host record has no value for ${recordContext.overrideFieldPath}.`,
            filterId: recordContext.overrideFilterId,
            fieldPath: recordContext.overrideFieldPath,
            retryable: false
        };
    }

    raiseScopeError(error) {
        this._scopeError = error;
        this.syncContextOutput(setScopeWidgetError(this.effectiveBoardId, cleanString(this._recordId), error));
    }

    finalizeInitialization(recordContext) {
        const failure = this.recordContextFailure(recordContext);
        if (failure) {
            this.raiseScopeError(failure);
            return;
        }
        this._scopeError = null;
        this._recordContextBase = recordContext;
        const filters = resolveInitialFilters(this._defs, {
            storedFilters: this._storedFilters,
            recordContext,
            userId: USER_ID
        });
        const readyCtx = publishFilterContext({
            ...this.filterContext,
            boardId: this.effectiveBoardId,
            recordContext,
            filters,
            status: 'READY',
            error: null,
            updatedAt: Date.now()
        });
        this.syncContextOutput(readyCtx);
        this.resolveMissingLabels();
        this._defs.forEach((def) => this.prunePicklistSelection(def));
    }

    @wire(getRecord, { recordId: '$_hostTypeRecordId', layoutTypes: ['Compact'], modes: ['View'] })
    wiredHostRecordType({ data, error }) {
        const pending = this._pendingRecordContext;
        if (!pending || this._overrideFields) {
            return;
        }
        if (data) {
            const objectApiName = data.apiName;
            const prefix = `${objectApiName}.`;
            const relativePath = pending.overrideFieldPath.startsWith(prefix)
                ? pending.overrideFieldPath.substring(prefix.length)
                : pending.overrideFieldPath;
            this._pendingRecordContext = { ...pending, objectApiName };
            if (relativePath === 'Id') {
                this.resolveRecordContextValue(pending.recordId);
                return;
            }
            this._overrideFields = [`${objectApiName}.${relativePath}`];
            this._overrideRecordId = pending.recordId;
        } else if (error) {
            this.failRecordContext(error);
        }
    }

    @wire(getRecord, { recordId: '$_overrideRecordId', fields: '$_overrideFields' })
    wiredOverrideRecord({ data, error }) {
        if (!this._overrideFields) {
            return;
        }
        if (data) {
            const value = getFieldValue(data, this._overrideFields[0]);
            this.resolveRecordContextValue(value ? String(value) : null);
        } else if (error) {
            this.failRecordContext(error);
        }
    }

    /** First host-record read completes initialization; later reads (record edits, refresh) re-apply the value. */
    resolveRecordContextValue(resolvedValue) {
        const pending = this._pendingRecordContext;
        if (pending) {
            this._pendingRecordContext = null;
            this._hostTypeRecordId = undefined;
            this.finalizeInitialization({ ...pending, resolvedValue });
            return;
        }
        const ctx = this.filterContext;
        if (!ctx || !ctx.recordContext) {
            return;
        }
        if (this._scopeError || ctx.status !== 'READY') {
            this.finalizeInitialization({ ...(this._recordContextBase || ctx.recordContext), resolvedValue });
            return;
        }
        const recordContext = { ...ctx.recordContext, resolvedValue };
        if (ctx.recordContext.resolvedValue === resolvedValue) {
            return;
        }
        const failure = this.recordContextFailure(recordContext);
        if (failure) {
            this.raiseScopeError(failure);
            return;
        }
        const filters = { ...(ctx.filters || {}) };
        const def = recordContextOverrideDefinition(this._defs, recordContext);
        const current = def ? filters[def.filterId] : null;
        if (def && (current?.locked || current?.source === 'RECORD_CONTEXT' || recordContext.mode === 'LOCKED')) {
            // A LOCKED override follows the host record; a DEFAULT one only while the user has not changed it.
            filters[def.filterId] = resolveInitialFilters([def], { recordContext, userId: USER_ID })[def.filterId];
        }
        const nextCtx = publishFilterContext({ ...ctx, recordContext, filters, updatedAt: Date.now() });
        this.syncContextOutput(nextCtx);
        this.resolveMissingLabels();
    }

    /** A host record that cannot be read never drops or substitutes the configured Record context scope. */
    failRecordContext(error) {
        const recordContext = this._pendingRecordContext || this.filterContext?.recordContext || {};
        const body = Array.isArray(error?.body) ? error.body[0] : error?.body;
        const detail = body?.message || error?.statusText || normalizeBoardError(error).message;
        this.raiseScopeError({
            category: 'ACCESS_ERROR',
            message: `Record context: the host record could not be read (${detail}).`,
            filterId: recordContext.overrideFilterId || null,
            fieldPath: recordContext.overrideFieldPath || null,
            retryable: false
        });
    }

    syncContextOutput(ctx) {
        if (!ctx) {
            return;
        }
        this.filterContext = ctx;
        const serialized = JSON.stringify(ctx);
        if (serialized !== this._filterContextJson) {
            this._filterContextJson = serialized;
            try {
                this.dispatchEvent(new FlowAttributeChangeEvent('filterContextJson', serialized));
            } catch (e) {
                // Ignore outside Flow
            }
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Remote data: picklist options and record / user display labels
    // ---------------------------------------------------------------------------------------------

    loadPicklistOptions() {
        const epoch = this._initEpoch;
        const options = {};
        this._picklistErrors = {};
        this._defs
            .filter((def) => def.type === 'PICKLIST')
            .forEach((def) => {
                if (def.optionsSource === 'CUSTOM') {
                    options[def.filterId] = def.options;
                    return;
                }
                if (!def.sourceObjectApiName || !def.fieldApiName) {
                    options[def.filterId] = [];
                    return;
                }
                getPicklistOptions({
                    objectApiName: def.sourceObjectApiName,
                    fieldApiName: def.fieldApiName,
                    refreshToken: this.currentRefreshToken
                })
                    .then((result) => {
                        if (epoch !== this._initEpoch) {
                            return;
                        }
                        this._picklistOptions = {
                            ...this._picklistOptions,
                            [def.filterId]: (result || []).map((o) => ({ label: o.label, value: o.value }))
                        };
                        this.prunePicklistSelection(def);
                    })
                    .catch((error) => {
                        if (epoch !== this._initEpoch) {
                            return;
                        }
                        this._picklistErrors = {
                            ...this._picklistErrors,
                            [def.filterId]: normalizeBoardError(error).message
                        };
                    });
            });
        this._picklistOptions = options;
    }

    get currentRefreshToken() {
        return this.filterContext?.refreshToken || 0;
    }

    /**
     * Config-drift sanitization for described picklists: once the field's options load, selections that are no
     * longer valid values (stale storage, renamed values, another Board sharing the storage key) are dropped,
     * republished, and re-persisted.
     */
    prunePicklistSelection(def) {
        const options = this._picklistOptions[def.filterId];
        const ctx = this.filterContext;
        const entry = ctx?.filters?.[def.filterId];
        if (
            def.type !== 'PICKLIST' ||
            def.optionsSource === 'CUSTOM' ||
            !options ||
            this._picklistErrors[def.filterId] ||
            ctx?.status !== 'READY' ||
            !entry ||
            !entry.active ||
            entry.locked
        ) {
            return;
        }
        const allowed = new Set(options.map((option) => option.value));
        const values = entry.values || [];
        if (values.every((value) => allowed.has(value))) {
            return;
        }
        const value =
            buildFilterValue(def, { values: values.filter((v) => allowed.has(v)) }, USER_ID) || clearedFilterValue(def);
        this.syncContextOutput(
            publishFilterContext({
                ...ctx,
                filters: { ...ctx.filters, [def.filterId]: buildFilterEntry(def, value, { source: entry.source }) },
                updatedAt: Date.now()
            })
        );
        if (this._persistence !== 'NONE' && this._storedFilters[def.filterId]) {
            this._storedFilters = {
                ...this._storedFilters,
                [def.filterId]: toStoredFilterEntry(def, value, this._labelCache)
            };
            writeStoredFilterState(this._persistence, this._storageKey, this._storedFilters);
        }
    }

    resolveMissingLabels() {
        const ids = new Set();
        this._defs.forEach((def) => {
            if (def.type === 'LOOKUP' || def.type === 'USER') {
                this.currentValue(def).values.forEach((id) => ids.add(id));
            }
        });
        const badgeRecordId = this.recordContextBadgeRecordId;
        if (badgeRecordId) {
            ids.add(badgeRecordId);
        }
        const missing = [...ids].filter(
            (id) => !this._labelCache[id] && !this._unresolvedLabelIds[id] && !this._labelRequests.has(id)
        );
        if (!missing.length) {
            return;
        }
        missing.forEach((id) => this._labelRequests.add(id));
        const settle = (result) => {
            const labels = { ...this._labelCache };
            const unresolved = { ...this._unresolvedLabelIds };
            missing.forEach((id) => {
                this._labelRequests.delete(id);
                if (result && result[id]) {
                    labels[id] = result[id];
                } else {
                    unresolved[id] = true;
                }
            });
            this._labelCache = labels;
            this._unresolvedLabelIds = unresolved;
            this.refreshStoredLabels();
        };
        resolveRecordLabels({ recordIds: missing, refreshToken: this.currentRefreshToken })
            .then(settle)
            .catch(() => settle(null));
    }

    labelFor(recordId) {
        if (this._labelCache[recordId]) {
            return this._labelCache[recordId];
        }
        return this._unresolvedLabelIds[recordId] ? UNKNOWN_RECORD_LABEL : PENDING_LABEL;
    }

    optionLabelFor(def, value) {
        const option = (this._picklistOptions[def.filterId] || []).find((o) => o.value === value);
        return option ? option.label : value;
    }

    // ---------------------------------------------------------------------------------------------
    // Filter value application, debounce batching, and persistence
    // ---------------------------------------------------------------------------------------------

    defFor(filterId) {
        return this._defs.find((def) => def.filterId === filterId) || null;
    }

    currentValue(def) {
        const draft = this._drafts[def.filterId];
        if (draft) {
            return draft;
        }
        const entry = this.filterContext?.filters?.[def.filterId];
        if (!entry) {
            return clearedFilterValue(def);
        }
        return {
            active: Boolean(entry.active),
            operator: entry.operator,
            values: entry.values || [],
            token: entry.token || null,
            literal: entry.literal || null,
            from: entry.from || null,
            to: entry.to || null,
            text: entry.text || null
        };
    }

    isLocked(filterId) {
        return Boolean(this.filterContext?.filters?.[filterId]?.locked);
    }

    applyFilterValue(filterId, input) {
        const def = this.defFor(filterId);
        if (!def || !this.filterContext || this.isLocked(filterId)) {
            return;
        }
        const value = buildFilterValue(def, input, USER_ID) || clearedFilterValue(def);
        const nextCtx = publishFilterContext({
            ...this.filterContext,
            filters: {
                ...(this.filterContext.filters || {}),
                [filterId]: buildFilterEntry(def, value)
            },
            updatedAt: Date.now()
        });
        this.syncContextOutput(nextCtx);
        if (this._persistence !== 'NONE') {
            this._storedFilters = {
                ...this._storedFilters,
                [filterId]: toStoredFilterEntry(def, value, this._labelCache)
            };
            writeStoredFilterState(this._persistence, this._storageKey, this._storedFilters);
        }
        this.resolveMissingLabels();
    }

    applyFilterValueNow(filterId, input) {
        this.cancelPendingSelection(filterId);
        this.applyFilterValue(filterId, input);
    }

    scheduleFilterValue(filterId, input, delay = SELECTION_DEBOUNCE_MS) {
        const def = this.defFor(filterId);
        if (!def || this.isLocked(filterId)) {
            return;
        }
        this._drafts = {
            ...this._drafts,
            [filterId]: buildFilterValue(def, input, USER_ID) || clearedFilterValue(def)
        };
        clearTimeout(this._debounceTimers[filterId]);
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- selection debounce; cleared in cancelPendingSelection()/teardown()
        this._debounceTimers[filterId] = setTimeout(() => {
            const draft = this._drafts[filterId];
            this.cancelPendingSelection(filterId);
            if (draft) {
                this.applyFilterValue(filterId, draft);
            }
        }, delay);
    }

    cancelPendingSelection(filterId) {
        clearTimeout(this._debounceTimers[filterId]);
        delete this._debounceTimers[filterId];
        if (this._drafts[filterId]) {
            const drafts = { ...this._drafts };
            delete drafts[filterId];
            this._drafts = drafts;
        }
    }

    refreshStoredLabels() {
        if (this._persistence === 'NONE') {
            return;
        }
        let changed = false;
        const next = { ...this._storedFilters };
        Object.keys(next).forEach((filterId) => {
            const def = this.defFor(filterId);
            if (!def || !next[filterId].labels) {
                return;
            }
            const refreshed = toStoredFilterEntry(def, next[filterId], this._labelCache);
            if (JSON.stringify(refreshed.labels) !== JSON.stringify(next[filterId].labels)) {
                next[filterId] = refreshed;
                changed = true;
            }
        });
        if (changed) {
            this._storedFilters = next;
            writeStoredFilterState(this._persistence, this._storageKey, next);
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Template state
    // ---------------------------------------------------------------------------------------------

    get resolvedConfig() {
        return parseAndMergeConfig('filter', this._configJson, {
            boardId: this._boardIdExplicitlySet ? this._boardId : '',
            title: this._title
        });
    }

    get effectiveTitle() {
        return this.resolvedConfig.config?.title || 'Board Filter Bar';
    }

    get effectiveBoardId() {
        return this.resolvedConfig.config?.boardId || this._boardId || 'default';
    }

    get activeScopeKey() {
        return this.filterContext?.scopeKey || '';
    }

    /** Configuration or Record context error; the same payload is the scope error every Widget renders. */
    get bodyError() {
        return this._scopeError;
    }

    /** Non-error setup hint for a Filter widget without (valid) filter definitions (spec story 10). */
    get showSetupPlaceholder() {
        return !this._scopeError && this._defs.length === 0;
    }

    get lastUpdatedValue() {
        return Math.max(this.filterContext?.lastRefreshedAt || 0, this._loadedAt);
    }

    get cardClass() {
        return this.isCompact ? 'slds-card c-board-card c-board-card_compact' : 'slds-card c-board-card';
    }

    get isCompact() {
        return FORM_FACTOR === 'Small' || this._isNarrow;
    }

    get showControls() {
        return !this.isCompact || this._drawerExpanded;
    }

    get filterBarClass() {
        return this.isCompact ? 'c-board-filter-bar c-board-filter-bar_compact' : 'c-board-filter-bar';
    }

    get activeFilterCount() {
        return Object.values(this.filterContext?.filters || {}).filter((entry) => entry && entry.active).length;
    }

    get drawerToggleLabel() {
        return `Filters (${this.activeFilterCount} active)`;
    }

    get drawerAriaExpanded() {
        return String(this._drawerExpanded);
    }

    get drawerIconName() {
        return this._drawerExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get filterViews() {
        return this._defs.map((def) => {
            const value = this.currentValue(def);
            const view = {
                key: def.filterId,
                filterId: def.filterId,
                label: def.label,
                type: def.type,
                locked: this.isLocked(def.filterId),
                isPicklistSingle: def.type === 'PICKLIST' && def.selectionMode === 'single',
                isPicklistMulti: def.type === 'PICKLIST' && def.selectionMode === 'multi',
                isLookup: def.type === 'LOOKUP',
                isUser: def.type === 'USER',
                isDateRange: def.type === 'DATE_RANGE',
                isText: def.type === 'TEXT'
            };
            if (def.type === 'PICKLIST') {
                Object.assign(view, this.buildPicklistView(def, value));
            } else if (def.type === 'LOOKUP') {
                Object.assign(view, {
                    hasTargetObject: Boolean(def.targetObjectApiName),
                    objectApiName: def.targetObjectApiName,
                    placeholder: def.placeholder || `Search ${def.label}…`,
                    pickerValue: def.selectionMode === 'single' ? value.values[0] || null : null
                });
            } else if (def.type === 'USER') {
                Object.assign(view, this.buildUserView(def, value));
            } else if (def.type === 'DATE_RANGE') {
                Object.assign(view, this.buildDateRangeView(def, value));
            } else if (def.type === 'TEXT') {
                Object.assign(view, this.buildTextView(def, value));
            }
            return view;
        });
    }

    buildTextView(def, value) {
        const typed = this._textInput[def.filterId];
        const textValue = typed ?? (value.active ? value.text || '' : '');
        const length = textValue.trim().length;
        return {
            placeholder: def.placeholder || `Search ${def.label}…`,
            textValue,
            textHint:
                length > 0 && length < def.minCharacters
                    ? `Type at least ${def.minCharacters} character${def.minCharacters === 1 ? '' : 's'}`
                    : null
        };
    }

    buildPicklistView(def, value) {
        const options = this._picklistOptions[def.filterId] || [];
        const selected = new Set(value.values);
        if (def.selectionMode === 'single') {
            return {
                comboboxOptions: [{ label: 'All', value: '' }, ...options],
                comboboxValue: value.values[0] || '',
                optionsError: this._picklistErrors[def.filterId] || null
            };
        }
        let summaryLabel = 'All';
        if (value.values.length === 1) {
            summaryLabel = this.optionLabelFor(def, value.values[0]);
        } else if (value.values.length > 1) {
            summaryLabel = `${value.values.length} selected`;
        }
        const isOpen = this._openPicklistId === def.filterId;
        const searchTerm = this._picklistSearch[def.filterId] || '';
        const needle = searchTerm.toLowerCase();
        const visible = needle ? options.filter((o) => o.label.toLowerCase().includes(needle)) : options;
        return {
            summaryLabel,
            triggerAriaLabel: `${def.label}: ${summaryLabel}`,
            isOpen,
            ariaExpanded: String(isOpen),
            dropdownClass: `slds-dropdown-trigger slds-dropdown-trigger_click c-board-picklist${isOpen ? ' slds-is-open' : ''}`,
            showSearch: options.length > PICKLIST_SEARCH_THRESHOLD,
            searchTerm,
            optionItems: visible.map((option, index) => ({
                key: option.value,
                value: option.value,
                label: option.label,
                checked: selected.has(option.value),
                ariaSelected: String(selected.has(option.value)),
                inputId: `${def.filterId}-option-${index}`
            })),
            hasNoMatches: visible.length === 0,
            optionsError: this._picklistErrors[def.filterId] || null
        };
    }

    buildUserView(def, value) {
        const meActive = value.token === 'ME';
        const search = this._userSearch[def.filterId] || { term: '', results: [], open: false };
        const showUserResults = Boolean(search.open && search.results.length);
        const searchLabel = def.includeQueues ? 'Search users and queues' : 'Search users';
        return {
            meActive,
            meAriaPressed: String(meActive),
            meAriaLabel: `${def.label}: Me`,
            meButtonClass: `slds-button c-board-me-chip ${meActive ? 'slds-button_brand' : 'slds-button_neutral'}`,
            searchLabel,
            searchPlaceholder: def.placeholder || `${searchLabel}…`,
            userSearchTerm: search.term,
            showUserResults,
            userComboboxClass: `slds-dropdown-trigger slds-dropdown-trigger_click c-board-user-combobox${
                showUserResults ? ' slds-is-open' : ''
            }`,
            userResults: search.results.map((result) => ({
                ...result,
                iconName: result.entityType === 'Queue' ? 'standard:queue' : 'standard:user'
            }))
        };
    }

    buildDateRangeView(def, value) {
        const isCustomRange =
            this._dateCustomMode[def.filterId] ??
            Boolean(value.active && CUSTOM_DATE_OPERATORS.includes(value.operator));
        const selectedValue = isCustomRange ? CUSTOM_DATE_RANGE : value.literal || '';
        // An active literal outside the preset list (e.g. a NEXT_WEEK default) stays visible as the selected option.
        const extraPreset =
            selectedValue && selectedValue !== CUSTOM_DATE_RANGE && !DATE_PRESET_LABELS.has(selectedValue)
                ? { value: selectedValue, label: describeDateLiteral(selectedValue) }
                : null;
        return {
            selectId: `${def.filterId}-date-preset`,
            isAllTime: selectedValue === '',
            isCustomRange,
            extraPreset,
            dateGroups: DATE_PRESET_GROUPS.map((group) => ({
                key: group.key,
                label: group.label,
                options: group.options.map((option) => ({ ...option, selected: option.value === selectedValue }))
            })),
            fromValue: value.from,
            toValue: value.to
        };
    }

    get pillItems() {
        const pills = [];
        this._defs.forEach((def) => {
            const entry = this.filterContext?.filters?.[def.filterId];
            if (!entry || !entry.active || entry.locked) {
                return;
            }
            const values = entry.values || [];
            const push = (value, text) =>
                pills.push({
                    key: `${def.filterId}::${value}`,
                    filterId: def.filterId,
                    value,
                    label: `${def.label}: ${text}`,
                    removeLabel: `Remove ${def.label}: ${text}`
                });
            if (def.type === 'PICKLIST') {
                values.forEach((value) => push(value, this.optionLabelFor(def, value)));
            } else if (def.type === 'LOOKUP') {
                values.forEach((value) => push(value, this.labelFor(value)));
            } else if (def.type === 'USER') {
                values.forEach((value) =>
                    push(value, value === USER_ID && entry.token === 'ME' ? 'Me' : this.labelFor(value))
                );
            } else if (def.type === 'DATE_RANGE') {
                push('', this.describeDateRange(entry));
            } else if (def.type === 'TEXT') {
                push('', `"${entry.text}"`);
            }
        });
        return pills;
    }

    describeDateRange(entry) {
        if (entry.operator === 'LITERAL') {
            return describeDateLiteral(entry.literal);
        }
        if (entry.operator === 'BETWEEN') {
            return `${entry.from} – ${entry.to}`;
        }
        return entry.operator === 'GTE' ? `From ${entry.from}` : `Through ${entry.to}`;
    }

    /** `🔒 <Label>: <Value>` badge, shown only while a LOCKED Record context override is applied (story 32). */
    get recordContextBadgeInfo() {
        const rc = this.filterContext?.recordContext;
        if (
            !rc ||
            rc.mode !== 'LOCKED' ||
            !rc.overrideApplies ||
            this.resolvedConfig.config?.showRecordContextBadge === false
        ) {
            return null;
        }
        const def = this.defFor(rc.overrideFilterId);
        const entry = this.filterContext.filters?.[rc.overrideFilterId];
        const value = entry?.locked ? (entry.values || [])[0] : null;
        if (!def || !value) {
            return null;
        }
        const isPicklistValue = def.type === 'PICKLIST';
        return {
            label: def.label,
            recordId: isPicklistValue ? null : value,
            text: isPicklistValue ? this.optionLabelFor(def, value) : null
        };
    }

    get recordContextBadgeRecordId() {
        return this.recordContextBadgeInfo?.recordId || null;
    }

    get recordContextBadges() {
        const info = this.recordContextBadgeInfo;
        if (!info) {
            return [];
        }
        const name = info.text || this.labelFor(info.recordId);
        return [{ key: 'record-context', label: `🔒 ${info.label}: ${name}` }];
    }

    get hasPills() {
        return this.pillItems.length > 0 || this.recordContextBadges.length > 0;
    }

    // ---------------------------------------------------------------------------------------------
    // Event handlers
    // ---------------------------------------------------------------------------------------------

    handlePicklistSingleChange(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const value = eventValue(event);
        this.applyFilterValueNow(filterId, { values: value ? [value] : [] });
    }

    handlePicklistToggle(event) {
        const filterId = event.currentTarget.dataset.filterId;
        this._openPicklistId = this._openPicklistId === filterId ? null : filterId;
    }

    handlePicklistFocusOut(event) {
        const container = event.currentTarget;
        if (event.relatedTarget && container.contains(event.relatedTarget)) {
            return;
        }
        if (this._openPicklistId === container.dataset.filterId) {
            this._openPicklistId = null;
        }
    }

    handlePicklistKeydown(event) {
        if (event.key === 'Escape') {
            this._openPicklistId = null;
        }
    }

    handlePicklistSearch(event) {
        const filterId = event.currentTarget.dataset.filterId;
        this._picklistSearch = { ...this._picklistSearch, [filterId]: eventValue(event) || '' };
    }

    handlePicklistCheckboxChange(event) {
        const { filterId, value } = event.currentTarget.dataset;
        const def = this.defFor(filterId);
        if (!def) {
            return;
        }
        const current = this.currentValue(def).values.filter((v) => v !== value);
        this.scheduleFilterValue(filterId, { values: event.target.checked ? [...current, value] : current });
    }

    handlePicklistSelectAll(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const def = this.defFor(filterId);
        if (!def) {
            return;
        }
        const needle = (this._picklistSearch[filterId] || '').toLowerCase();
        const visible = (this._picklistOptions[filterId] || [])
            .filter((o) => !needle || o.label.toLowerCase().includes(needle))
            .map((o) => o.value);
        const current = this.currentValue(def).values;
        this.scheduleFilterValue(filterId, { values: [...current, ...visible.filter((v) => !current.includes(v))] });
    }

    handlePicklistClear(event) {
        this.scheduleFilterValue(event.currentTarget.dataset.filterId, { values: [] });
    }

    handleLookupChange(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const def = this.defFor(filterId);
        if (!def) {
            return;
        }
        const recordId = event.detail ? event.detail.recordId || null : null;
        if (def.selectionMode === 'single') {
            this.applyFilterValueNow(filterId, { values: recordId ? [recordId] : [] });
            return;
        }
        if (!recordId) {
            return;
        }
        const current = this.currentValue(def).values;
        if (!current.includes(recordId)) {
            this.applyFilterValueNow(filterId, { values: [...current, recordId] });
        }
        if (typeof event.target.clearSelection === 'function') {
            event.target.clearSelection();
        }
    }

    handleMeToggle(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const def = this.defFor(filterId);
        if (!def) {
            return;
        }
        const current = this.currentValue(def);
        const meActive = current.token === 'ME';
        if (def.selectionMode === 'single') {
            this.applyFilterValueNow(filterId, meActive ? { values: [] } : { values: [USER_ID], token: 'ME' });
            return;
        }
        const others = current.values.filter((v) => v !== USER_ID);
        this.applyFilterValueNow(
            filterId,
            meActive ? { values: others, token: null } : { values: [USER_ID, ...others], token: 'ME' }
        );
    }

    handleUserSearchChange(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const term = eventValue(event) || '';
        const search = this._userSearch[filterId] || { term: '', results: [], open: false };
        this._userSearch = { ...this._userSearch, [filterId]: { ...search, term } };
        clearTimeout(this._userSearchTimers[filterId]);
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- typeahead debounce; cleared in teardown()
        this._userSearchTimers[filterId] = setTimeout(
            () => this.runUserSearch(filterId, term),
            USER_SEARCH_DEBOUNCE_MS
        );
    }

    handleUserSearchFocus(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const search = this._userSearch[filterId];
        if (search && search.results.length) {
            this._userSearch = { ...this._userSearch, [filterId]: { ...search, open: true } };
            return;
        }
        this.runUserSearch(filterId, search ? search.term : '');
    }

    handleUserSearchFocusOut(event) {
        const container = event.currentTarget;
        if (event.relatedTarget && container.contains(event.relatedTarget)) {
            return;
        }
        this.closeUserResults(container.dataset.filterId);
    }

    handleUserSearchKeydown(event) {
        if (event.key === 'Escape') {
            this.closeUserResults(event.currentTarget.dataset.filterId);
        }
    }

    closeUserResults(filterId) {
        const search = this._userSearch[filterId];
        if (search && search.open) {
            this._userSearch = { ...this._userSearch, [filterId]: { ...search, open: false } };
        }
    }

    runUserSearch(filterId, term) {
        const def = this.defFor(filterId);
        if (!def) {
            return;
        }
        const epoch = this._initEpoch;
        searchUsersAndQueues({
            searchTerm: term,
            includeQueues: def.includeQueues,
            refreshToken: this.currentRefreshToken
        })
            .then((results) => {
                const search = this._userSearch[filterId] || { term: '', results: [], open: false };
                if (epoch !== this._initEpoch || search.term !== term) {
                    return;
                }
                const options = (results || []).map((r) => ({ id: r.id, label: r.label, entityType: r.entityType }));
                const labels = { ...this._labelCache };
                options.forEach((option) => {
                    labels[option.id] = option.label;
                });
                this._labelCache = labels;
                this._userSearch = { ...this._userSearch, [filterId]: { term, results: options, open: true } };
            })
            .catch(() => {
                // Search failures leave the current selection untouched
            });
    }

    handleUserResultSelect(event) {
        const { filterId, recordId } = event.currentTarget.dataset;
        const def = this.defFor(filterId);
        if (!def || !recordId) {
            return;
        }
        this._userSearch = { ...this._userSearch, [filterId]: { term: '', results: [], open: false } };
        const current = this.currentValue(def);
        if (def.selectionMode === 'single') {
            this.applyFilterValueNow(filterId, { values: [recordId], token: recordId === USER_ID ? 'ME' : null });
            return;
        }
        if (current.values.includes(recordId)) {
            return;
        }
        this.applyFilterValueNow(filterId, {
            values: [...current.values, recordId],
            token: current.token === 'ME' || recordId === USER_ID ? 'ME' : null
        });
    }

    handleDatePresetChange(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const selected = event.target.value;
        const isCustom = selected === CUSTOM_DATE_RANGE;
        this._dateCustomMode = { ...this._dateCustomMode, [filterId]: isCustom };
        if (isCustom || !selected) {
            this.applyFilterValueNow(filterId, {});
            return;
        }
        this.applyFilterValueNow(filterId, { operator: 'LITERAL', literal: selected });
    }

    handleDateInputChange(event) {
        const { filterId, bound } = event.currentTarget.dataset;
        const def = this.defFor(filterId);
        if (!def) {
            return;
        }
        const current = this.currentValue(def);
        const next = {
            from: current.operator === 'LITERAL' ? null : current.from,
            to: current.operator === 'LITERAL' ? null : current.to
        };
        next[bound] = cleanString(eventValue(event));
        this.scheduleFilterValue(filterId, { operator: dateRangeOperator(next.from, next.to), ...next });
    }

    handlePillRemove(event) {
        const { filterId, value } = event.currentTarget.dataset;
        const def = this.defFor(filterId);
        if (!def) {
            return;
        }
        if (def.type === 'DATE_RANGE') {
            this._dateCustomMode = { ...this._dateCustomMode, [filterId]: false };
            this.applyFilterValueNow(filterId, {});
            return;
        }
        if (def.type === 'TEXT') {
            this.clearTextInput(filterId);
            this.applyFilterValueNow(filterId, {});
            return;
        }
        const current = this.currentValue(def);
        const remaining = current.values.filter((v) => v !== value);
        const token = def.type === 'USER' && value !== USER_ID ? current.token : null;
        this.applyFilterValueNow(filterId, { values: remaining, token });
    }

    /** Published search term for typed text: blank until it reaches `minCharacters`. */
    effectiveSearchText(def, raw) {
        const trimmed = (raw || '').trim();
        return trimmed.length >= def.minCharacters ? trimmed : null;
    }

    /**
     * Debounces typing by 300ms; clearing the input applies immediately. Input shorter than `minCharacters`
     * never activates the filter (an already active search is cleared after the debounce).
     */
    handleTextSearchChange(event) {
        const filterId = event.currentTarget.dataset.filterId;
        const def = this.defFor(filterId);
        if (!def || this.isLocked(filterId)) {
            return;
        }
        const raw = eventValue(event) || '';
        this._textInput = { ...this._textInput, [filterId]: raw };
        if (!raw.trim()) {
            this.applyFilterValueNow(filterId, {});
            return;
        }
        const text = this.effectiveSearchText(def, raw);
        if (!text && !this.filterContext?.filters?.[filterId]?.active) {
            this.cancelPendingSelection(filterId);
            return;
        }
        this.scheduleFilterValue(filterId, { text }, TEXT_SEARCH_DEBOUNCE_MS);
    }

    /** `Enter` flushes the pending search immediately. */
    handleTextSearchKeydown(event) {
        if (event.key !== 'Enter') {
            return;
        }
        const filterId = event.currentTarget.dataset.filterId;
        const def = this.defFor(filterId);
        if (!def || this.isLocked(filterId)) {
            return;
        }
        const raw = this._textInput[filterId] ?? event.currentTarget.value ?? '';
        const text = this.effectiveSearchText(def, raw);
        if (!text && !this.filterContext?.filters?.[filterId]?.active) {
            this.cancelPendingSelection(filterId);
            return;
        }
        this.applyFilterValueNow(filterId, { text });
    }

    /**
     * Drops typed text that no longer matches the published search (a Flow input or another Widget changed it),
     * so the box never shows a term other than the active one. A pending debounce keeps its text: it is about
     * to publish it.
     */
    reconcileTextInput(ctx) {
        const filterIds = Object.keys(this._textInput);
        if (!filterIds.length) {
            return;
        }
        const next = { ...this._textInput };
        let changed = false;
        filterIds.forEach((filterId) => {
            const def = this.defFor(filterId);
            if (!def || this._debounceTimers[filterId]) {
                return;
            }
            const value = ctx?.filters?.[filterId];
            const published = (value?.active && (value.text || '').trim()) || null;
            if (published !== this.effectiveSearchText(def, next[filterId])) {
                delete next[filterId];
                changed = true;
            }
        });
        if (changed) {
            this._textInput = next;
        }
    }

    clearTextInput(filterId) {
        if (filterId in this._textInput) {
            const next = { ...this._textInput };
            delete next[filterId];
            this._textInput = next;
        }
    }

    handleDrawerToggle() {
        this._drawerExpanded = !this._drawerExpanded;
    }

    handleReset() {
        if (!this.filterContext) {
            return;
        }
        this.cancelPendingSelections();
        this._dateCustomMode = {};
        this._openPicklistId = null;
        this._picklistSearch = {};
        this._textInput = {};
        this._storedFilters = {};
        clearStoredFilterState(this._storageKey);
        const recordContext = this.filterContext.recordContext;
        const nextCtx = publishFilterContext({
            ...this.filterContext,
            filters: resolveInitialFilters(this._defs, { recordContext, userId: USER_ID }),
            crossFilters: {},
            updatedAt: Date.now()
        });
        this.syncContextOutput(nextCtx);
        this.resolveMissingLabels();
    }

    handleRefreshBoard() {
        if (!this.filterContext) {
            return;
        }
        const now = Date.now();
        const nextContext = publishFilterContext({
            ...this.filterContext,
            refreshToken: (this.filterContext.refreshToken || 0) + 1,
            lastRefreshedAt: now,
            updatedAt: now
        });
        this.syncContextOutput(nextContext);
        try {
            this.dispatchEvent(new RefreshEvent());
        } catch (e) {
            // Ignore
        }
    }

    /**
     * lightning/refresh handler (page-action edits, Board Refresh): renews the "Updated" timestamp and re-reads the
     * host record so an `overrideFieldPath` lock follows the edited record. Widgets refresh their own data.
     */
    handlePageRefresh() {
        this._loadedAt = Date.now();
        const recordId = cleanString(this._recordId);
        if (!this._requiresTraversal || !recordId) {
            return Promise.resolve(true);
        }
        return notifyRecordUpdateAvailable([{ recordId }]).then(
            () => true,
            () => true
        );
    }
}