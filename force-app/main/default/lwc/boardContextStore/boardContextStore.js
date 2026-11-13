/**
 * Shared in-memory pub/sub state coordinator per Board scope.
 */
import VIEWER_CURRENCY from '@salesforce/i18n/currency';
import { buildExternalFilterEntry } from './filterPersistence';

export {
    buildFilterStorageKey,
    readStoredFilterState,
    writeStoredFilterState,
    clearStoredFilterState,
    normalizeFilterDefinitions,
    normalizeFilterLayout,
    sanitizeStoredFilters,
    resolveInitialFilters,
    recordContextOverrideDefinition,
    buildFilterValue,
    buildFilterEntry,
    clearedFilterValue,
    dateRangeOperator,
    cleanNumberBound,
    toStoredFilterEntry
} from './filterPersistence';

const scopes = new Map();
const boardDefaultRecordIds = new Map();
/** Display currency per Board id (not persisted: a page load starts again from the viewer's currency). */
const displayCurrencies = new Map();
/** Config currency per Board id, published by the Board's Filter widget (absent: the corporate currency). */
const configCurrencies = new Map();
/** Board-level Bucket fields per Board id, published by the Board's Filter widget. */
const boardBucketFields = new Map();
/** Filter context listeners subscribed with Wait for Filter widget on. */
const waitingListeners = new WeakSet();

export function normalizeBoardId(boardId) {
    return boardId && String(boardId).trim() ? String(boardId).trim() : 'default';
}

export function normalizeRecordId(recordId) {
    return recordId && String(recordId).trim() ? String(recordId).trim() : null;
}

/** `%` and `:` are escaped in the boardId part so a boardId containing `::` never collides with another scope. */
function escapeBoardIdForScope(boardId) {
    return boardId.replace(/%/g, '%25').replace(/:/g, '%3A');
}

export function computeScopeKey(boardId, recordId) {
    const cleanBoardId = escapeBoardIdForScope(normalizeBoardId(boardId));
    const cleanRecordId = normalizeRecordId(recordId);
    return cleanRecordId ? `${cleanBoardId}::${cleanRecordId}` : cleanBoardId;
}

export function createInitialFilterContext(boardId = 'default', recordId = null, status = 'INITIALIZING') {
    const cleanBoardId = normalizeBoardId(boardId);
    const cleanRecordId = normalizeRecordId(recordId);
    const scopeKey = computeScopeKey(cleanBoardId, cleanRecordId);

    return {
        version: 1,
        boardId: cleanBoardId,
        scopeKey,
        status,
        updatedAt: Date.now(),
        refreshToken: 0,
        lastRefreshedAt: null,
        recordContext: {
            recordId: cleanRecordId,
            objectApiName: null,
            overrideFilterId: null,
            overrideFieldPath: null,
            resolvedValue: cleanRecordId,
            mode: 'IMPLICIT',
            overrideApplies: false
        },
        filters: {},
        crossFilters: {}
    };
}

function getOrCreateScope(scopeKey, boardId, recordId) {
    if (!scopes.has(scopeKey)) {
        scopes.set(scopeKey, {
            state: null,
            hasFilterWidget: false,
            definitions: null,
            userId: null,
            pendingExternal: null,
            lastReadyAt: null,
            listeners: new Set()
        });
    }
    const entry = scopes.get(scopeKey);
    if (!entry.state && (boardId || recordId)) {
        entry.state = createInitialFilterContext(boardId, recordId, 'INITIALIZING');
    }
    return entry;
}

/** Scope a Widget reads: its explicit recordId, else the recordId a Filter widget registered for the Board. */
function resolveWidgetScope(boardId, recordId) {
    const cleanBoardId = normalizeBoardId(boardId);
    const cleanRecordId = normalizeRecordId(recordId) || boardDefaultRecordIds.get(cleanBoardId) || null;
    const scopeKey = computeScopeKey(cleanBoardId, cleanRecordId);
    return { cleanBoardId, cleanRecordId, scopeKey, entry: getOrCreateScope(scopeKey, cleanBoardId, cleanRecordId) };
}

function notifyScopeListeners(entry) {
    if (!entry || !entry.state) {
        return;
    }
    const snapshot = cloneContext(entry.state);
    entry.listeners.forEach((listener) => {
        if (entry.isFallback && waitingListeners.has(listener)) {
            return;
        }
        try {
            listener(snapshot);
        } catch (e) {
            // Listener isolation
        }
    });
}

function cloneContext(ctx) {
    return JSON.parse(JSON.stringify(ctx));
}

/**
 * `isFallback` marks the microtask fallback (no Filter widget, no explicit publish): Wait-for-Filter-widget
 * subscribers are not notified of it. Any explicit commit clears it.
 */
function commitState(entry, state, isFallback = false) {
    entry.isFallback = isFallback;
    entry.state = state;
    if (state.status === 'READY') {
        entry.lastReadyAt = Math.max(entry.lastReadyAt || 0, state.updatedAt || 0);
    }
    notifyScopeListeners(entry);
}

/**
 * Marks the scope as owned by a Filter widget and sets the `INITIALIZING` barrier (clearing any previous scope
 * error). `definitions` (normalized FilterDefinitions) and `userId` let `acceptExternalFilterContext` validate
 * external filter entries against the Filter widget's configuration.
 */
export function registerFilterWidget(boardId, recordId, initialContextOverride = null, { definitions, userId } = {}) {
    const cleanBoardId = normalizeBoardId(boardId);
    const cleanRecordId = normalizeRecordId(recordId);
    const scopeKey = computeScopeKey(cleanBoardId, cleanRecordId);

    if (cleanRecordId) {
        boardDefaultRecordIds.set(cleanBoardId, cleanRecordId);
    }

    const entry = getOrCreateScope(scopeKey, cleanBoardId, cleanRecordId);
    entry.hasFilterWidget = true;
    entry.definitions = Array.isArray(definitions) ? definitions : null;
    entry.userId = userId || null;
    entry.pendingExternal = null;
    entry.lastReadyAt = null;
    entry.isFallback = false;
    const baseState = entry.state || createInitialFilterContext(cleanBoardId, cleanRecordId, 'INITIALIZING');
    entry.state = {
        ...baseState,
        ...(initialContextOverride || {}),
        boardId: cleanBoardId,
        scopeKey,
        status: 'INITIALIZING',
        error: null,
        updatedAt: Date.now()
    };

    // Migrate any early-mounted widgets on the bare boardId scope that lack an explicit recordId
    if (cleanRecordId) {
        const bareEntry = scopes.get(computeScopeKey(cleanBoardId, null));
        if (bareEntry && bareEntry !== entry && bareEntry.listeners.size > 0) {
            bareEntry.listeners.forEach((listener) => {
                entry.listeners.add(listener);
            });
            bareEntry.listeners.clear();
        }
    }

    notifyScopeListeners(entry);
    return cloneContext(entry.state);
}

export function publishFilterContext(contextPayload) {
    if (!contextPayload) {
        return null;
    }
    const cleanBoardId = normalizeBoardId(contextPayload.boardId);
    const cleanRecordId = normalizeRecordId(contextPayload.recordContext?.recordId);
    const scopeKey = computeScopeKey(cleanBoardId, cleanRecordId);

    const entry = getOrCreateScope(scopeKey, cleanBoardId, cleanRecordId);
    let nextState = {
        ...createInitialFilterContext(cleanBoardId, cleanRecordId, contextPayload.status || 'READY'),
        ...contextPayload,
        version: 1,
        boardId: cleanBoardId,
        scopeKey,
        updatedAt: contextPayload.updatedAt || Date.now()
    };
    if (nextState.status === 'READY' && entry.pendingExternal) {
        // A reactive Flow input received during the Filter widget's INITIALIZING barrier applies on top of READY.
        nextState = mergeExternalContext(entry, nextState, entry.pendingExternal);
        entry.pendingExternal = null;
    }
    commitState(entry, nextState);

    return cloneContext(nextState);
}

/** Test seam: merges a partial update into a scope (defaults `recordId` to the Board's Filter widget recordId). */
export function updateFilterContext(boardId, recordId, partialUpdate) {
    const { cleanBoardId, cleanRecordId, entry } = resolveWidgetScope(boardId, recordId);
    const base = entry.state || createInitialFilterContext(cleanBoardId, cleanRecordId, 'READY');
    return publishFilterContext({
        ...base,
        ...(partialUpdate || {}),
        boardId: cleanBoardId,
        recordContext: {
            ...(base.recordContext || {}),
            ...(partialUpdate?.recordContext || {}),
            recordId: cleanRecordId
        },
        filters: {
            ...(base.filters || {}),
            ...(partialUpdate?.filters || {})
        },
        updatedAt: Date.now()
    });
}

/**
 * Sets (or clears, with `null`) a scope-wide error every Widget renders instead of data. The status is kept, so an
 * error raised during the `INITIALIZING` barrier keeps Widgets from ever querying the unscoped object.
 */
export function setScopeWidgetError(boardId, recordId, errorPayload) {
    const { cleanBoardId, cleanRecordId, entry } = resolveWidgetScope(boardId, recordId);
    const base = entry.state || createInitialFilterContext(cleanBoardId, cleanRecordId, 'READY');
    commitState(
        entry,
        {
            ...base,
            error: errorPayload || null,
            updatedAt: Date.now()
        },
        Boolean(entry.isFallback)
    );
    return cloneContext(entry.state);
}

function isPlainObject(value) {
    return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function sanitizeEntries(entry, incoming, current = {}) {
    const next = { ...current };
    Object.keys(incoming).forEach((key) => {
        if (current[key]?.locked) {
            return;
        }
        const sanitized = buildExternalFilterEntry(entry.definitions, key, incoming[key], entry.userId);
        if (sanitized) {
            next[key] = sanitized;
        }
    });
    return next;
}

function mergeExternalContext(entry, base, parsed) {
    const merged = {
        ...base,
        filters: isPlainObject(parsed.filters)
            ? sanitizeEntries(entry, parsed.filters, base.filters || {})
            : base.filters || {},
        crossFilters: isPlainObject(parsed.crossFilters)
            ? sanitizeEntries({ definitions: null, userId: entry.userId }, parsed.crossFilters)
            : base.crossFilters || {},
        updatedAt: Math.max(Date.now(), (base.updatedAt || 0) + 1)
    };
    if (Number.isInteger(parsed.refreshToken) && parsed.refreshToken > (base.refreshToken || 0)) {
        merged.refreshToken = parsed.refreshToken;
        merged.lastRefreshedAt = typeof parsed.lastRefreshedAt === 'number' ? parsed.lastRefreshedAt : Date.now();
    }
    return merged;
}

/**
 * Applies a reactive Flow `filterContextJson` input to the caller's Board scope (`boardId` + `recordId`, defaulting
 * to the Board's Filter widget recordId). Returns true when the input was applied (or queued behind the Filter
 * widget's `INITIALIZING` barrier), false when rejected:
 * - malformed JSON, `version` other than 1, or a `status` other than `READY`;
 * - another scope: `boardId`, `scopeKey`, or `recordContext.recordId` differing from the caller's scope;
 * - stale or echoed: `updatedAt` not newer than the latest `READY` state since the Filter widget registered, or
 *   equal to the current state's `updatedAt`.
 * Accepted input merges `filters` per entry (validated against the Filter widget's definitions when one is
 * registered; `LOCKED` entries are never replaced), replaces `crossFilters`, and adopts a higher `refreshToken`.
 * `recordContext`, `error`, and `status` are never taken from the input; a scope without a Filter widget becomes
 * `READY`.
 */
export function acceptExternalFilterContext(boardId, recordId, filterContextJson) {
    let parsed;
    try {
        parsed = typeof filterContextJson === 'string' ? JSON.parse(filterContextJson) : filterContextJson;
    } catch (e) {
        return false;
    }
    if (!isPlainObject(parsed) || (parsed.version !== undefined && parsed.version !== 1)) {
        return false;
    }
    if (parsed.status !== undefined && parsed.status !== 'READY') {
        return false;
    }
    const { cleanBoardId, cleanRecordId, scopeKey, entry } = resolveWidgetScope(boardId, recordId);
    const parsedRecordId = parsed.recordContext ? normalizeRecordId(parsed.recordContext.recordId) : null;
    if (
        (parsed.boardId !== undefined && normalizeBoardId(parsed.boardId) !== cleanBoardId) ||
        (parsed.scopeKey !== undefined && parsed.scopeKey !== scopeKey) ||
        (parsedRecordId && parsedRecordId !== cleanRecordId)
    ) {
        return false;
    }
    const base = entry.state || createInitialFilterContext(cleanBoardId, cleanRecordId, 'INITIALIZING');
    if (
        typeof parsed.updatedAt === 'number' &&
        (parsed.updatedAt === base.updatedAt || (entry.lastReadyAt !== null && parsed.updatedAt <= entry.lastReadyAt))
    ) {
        return false;
    }
    if (entry.hasFilterWidget && base.status !== 'READY') {
        entry.pendingExternal = parsed;
        return true;
    }
    commitState(entry, { ...mergeExternalContext(entry, base, parsed), status: 'READY' });
    return true;
}

/**
 * Subscribes `callback` to the caller's Board scope. With `waitForFilterWidget` on, the subscriber gets no `READY`
 * until a Filter widget registers on the Board id (or a Flow input / explicit publish sets the context): it never
 * falls back to an unfiltered context on its own, and never sees another subscriber's microtask fallback. With it
 * off, a scope without a Filter widget becomes `READY` (no filters) one microtask after subscribe, and a Filter
 * widget that registers later is still followed.
 */
export function subscribeFilterContext(boardId, recordId, callback, { waitForFilterWidget = false } = {}) {
    const { cleanBoardId, cleanRecordId, entry } = resolveWidgetScope(boardId, recordId);
    entry.listeners.add(callback);
    if (waitForFilterWidget) {
        waitingListeners.add(callback);
    } else {
        waitingListeners.delete(callback);
    }

    if (entry.state && entry.state.status === 'READY') {
        if (!(waitForFilterWidget && entry.isFallback)) {
            callback(cloneContext(entry.state));
        }
    } else if (entry.hasFilterWidget && entry.state) {
        callback(cloneContext(entry.state));
    } else if (!waitForFilterWidget) {
        // Microtask fallback when no Filter widget is mounted on this scopeKey
        Promise.resolve().then(() => {
            if (!entry.listeners.has(callback)) {
                return;
            }
            if (!entry.hasFilterWidget && (!entry.state || entry.state.status === 'INITIALIZING')) {
                commitState(entry, createInitialFilterContext(cleanBoardId, cleanRecordId, 'READY'), true);
            }
        });
    }

    return () => {
        entry.listeners.delete(callback);
        scopes.forEach((s) => s.listeners.delete(callback));
    };
}

/**
 * The Board's Display currency: the ISO code every Widget converts and formats currency amounts in. Defaults to the
 * viewer's own currency (the org currency in single-currency orgs). It never changes which records count.
 */
export function getDisplayCurrency(boardId) {
    return displayCurrencies.get(normalizeBoardId(boardId)) || VIEWER_CURRENCY;
}

/**
 * Sets the Board's Display currency (`null` or blank restores the viewer's currency). Published by the Filter
 * widget's Currency picker; not persisted. When it changes, every subscriber on the Board id is notified with its
 * unchanged Filter context, so Widgets re-query in the new Display currency (their query signature carries it).
 */
export function setDisplayCurrency(boardId, isoCode) {
    const cleanBoardId = normalizeBoardId(boardId);
    const previous = getDisplayCurrency(cleanBoardId);
    const code = isoCode ? String(isoCode).trim().toUpperCase() : '';
    if (code) {
        displayCurrencies.set(cleanBoardId, code);
    } else {
        displayCurrencies.delete(cleanBoardId);
    }
    if (getDisplayCurrency(cleanBoardId) !== previous) {
        scopes.forEach((entry) => {
            if (entry.state?.boardId === cleanBoardId) {
                notifyScopeListeners(entry);
            }
        });
    }
}

/**
 * The Board's Config currency: the ISO code Admin-entered amounts (Metric thresholds, Base filter amounts) are written
 * in. Null means the org's corporate currency, which Apex resolves (a Board without a Filter widget, or a Filter widget
 * without the setting).
 */
export function getConfigCurrency(boardId) {
    return configCurrencies.get(normalizeBoardId(boardId)) || null;
}

/** Publishes the Board's Config currency (`null` or blank: the corporate currency). Set by the Filter widget. */
export function setConfigCurrency(boardId, isoCode) {
    const code = isoCode ? String(isoCode).trim().toUpperCase() : '';
    if (code) {
        configCurrencies.set(normalizeBoardId(boardId), code);
    } else {
        configCurrencies.delete(normalizeBoardId(boardId));
    }
}

/**
 * The Board-level Bucket fields (`[{ id, label, rules, fallback }]`, see `c/boardBucketFields`) a Widget can use by id
 * next to its own; a copy, empty when the Board's Filter widget defines none.
 */
export function getBoardBucketFields(boardId) {
    const fields = boardBucketFields.get(normalizeBoardId(boardId));
    return fields ? JSON.parse(JSON.stringify(fields)) : [];
}

/** Publishes the Board-level Bucket fields (not a list, or empty: none). Set by the Filter widget. */
export function setBoardBucketFields(boardId, bucketFields) {
    if (Array.isArray(bucketFields) && bucketFields.length) {
        boardBucketFields.set(normalizeBoardId(boardId), JSON.parse(JSON.stringify(bucketFields)));
    } else {
        boardBucketFields.delete(normalizeBoardId(boardId));
    }
}

export function resetBoardContextStore() {
    scopes.clear();
    boardDefaultRecordIds.clear();
    displayCurrencies.clear();
    configCurrencies.clear();
    boardBucketFields.clear();
}