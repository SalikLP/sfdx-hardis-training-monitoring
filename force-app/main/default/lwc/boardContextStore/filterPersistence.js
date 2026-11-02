/**
 * Filter widget definitions, Web Storage hydration, config-drift sanitization, and initial load precedence
 * (LOCKED recordContext > stored state > DEFAULT recordContext > admin defaultValue > cleared).
 */
import { FILTER_TYPES, DATE_RANGE_OPERATORS, RECORD_CONTEXT_OVERRIDE_TYPES } from 'c/boardConfigUtils';

export const FILTER_STORAGE_PREFIX = 'sf-board-filters::v1::';

const TEXT_MATCH_MODES = ['SOSL', 'CONTAINS', 'STARTS_WITH'];
const FILTER_SOURCES = ['FILTER_WIDGET', 'RECORD_CONTEXT', 'CROSS_FILTER'];
const ENTRY_OPERATORS = ['IN', ...DATE_RANGE_OPERATORS, ...TEXT_MATCH_MODES];
const RECORD_ID_PATTERN = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;
const ISO_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const DATE_LITERAL_PATTERN = /^[A-Z_]+(?::\d+)?$/;

export function buildFilterStorageKey(userId, scopeKey) {
    return `${FILTER_STORAGE_PREFIX}${userId}::${scopeKey}`;
}

function getStorage(persistence) {
    try {
        if (persistence === 'LOCAL') {
            return window.localStorage;
        }
        if (persistence === 'SESSION') {
            return window.sessionStorage;
        }
    } catch (e) {
        // Storage blocked by browser privacy settings
    }
    return null;
}

export function readStoredFilterState(persistence, storageKey) {
    const storage = getStorage(persistence);
    if (!storage) {
        return null;
    }
    try {
        const raw = storage.getItem(storageKey);
        if (!raw) {
            return null;
        }
        const parsed = JSON.parse(raw);
        if (!parsed || parsed.version !== 1 || !parsed.filters || typeof parsed.filters !== 'object') {
            return null;
        }
        return parsed;
    } catch (e) {
        return null;
    }
}

export function writeStoredFilterState(persistence, storageKey, storedFilters) {
    const storage = getStorage(persistence);
    if (!storage) {
        return;
    }
    try {
        storage.setItem(storageKey, JSON.stringify({ version: 1, updatedAt: Date.now(), filters: storedFilters }));
    } catch (e) {
        // Quota exceeded: degrade to in-memory state
    }
}

export function clearStoredFilterState(storageKey) {
    ['SESSION', 'LOCAL'].forEach((persistence) => {
        const storage = getStorage(persistence);
        if (!storage) {
            return;
        }
        try {
            storage.removeItem(storageKey);
        } catch (e) {
            // Ignore storage access failures
        }
    });
}

function cleanString(value) {
    return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function cleanStringArray(values) {
    return Array.isArray(values) ? values.filter((v) => typeof v === 'string' && v.trim()).map((v) => v.trim()) : [];
}

/**
 * Normalizes configJson `filters`. Entries without a `filterId`, with an unsupported `type`, or with a duplicate
 * `filterId` are skipped; when an `errors` array is passed, a `CONFIG_ERROR` BoardErrorPayload naming the offending
 * filter is pushed for each of them.
 */
export function normalizeFilterDefinitions(rawFilters, errors = null) {
    const seen = new Set();
    const defs = [];
    const reject = (filterId, message) => {
        if (errors) {
            errors.push({ category: 'CONFIG_ERROR', message, filterId, fieldPath: 'filters', retryable: false });
        }
    };
    (Array.isArray(rawFilters) ? rawFilters : []).forEach((raw, index) => {
        const filterId = cleanString(raw?.filterId);
        if (!filterId) {
            reject(null, `Filter #${index + 1} has no filterId.`);
            return;
        }
        if (seen.has(filterId)) {
            reject(filterId, `Filter "${filterId}" is defined more than once.`);
            return;
        }
        if (!FILTER_TYPES.includes(raw.type)) {
            reject(filterId, `Filter "${filterId}" has an unsupported type "${raw.type}".`);
            return;
        }
        seen.add(filterId);
        const type = raw.type;
        const isUser = type === 'USER';
        let selectionMode = null;
        if (type === 'PICKLIST') {
            selectionMode = raw.selectionMode === 'single' ? 'single' : 'multi';
        } else if (type === 'LOOKUP' || isUser) {
            selectionMode = raw.selectionMode === 'multi' ? 'multi' : 'single';
        }
        const options = Array.isArray(raw.options)
            ? raw.options
                  .filter((o) => o && o.value !== undefined && o.value !== null && String(o.value) !== '')
                  .map((o) => ({ label: String(o.label ?? o.value), value: String(o.value) }))
            : [];
        let optionsSource = null;
        if (type === 'PICKLIST') {
            const impliedCustom = !raw.optionsSource && options.length > 0;
            optionsSource = raw.optionsSource === 'CUSTOM' || impliedCustom ? 'CUSTOM' : 'FIELD_DESCRIBE';
        }
        defs.push({
            filterId,
            label: cleanString(raw.label) || filterId,
            type,
            selectionMode,
            fieldApiName: cleanString(raw.fieldApiName) || (isUser ? 'OwnerId' : null),
            targetObjectApiName: cleanString(raw.targetObjectApiName) || (isUser ? 'User' : null),
            optionsSource,
            sourceObjectApiName: cleanString(raw.sourceObjectApiName),
            options,
            includeQueues: raw.includeQueues === true,
            matchMode: TEXT_MATCH_MODES.includes(raw.matchMode) ? raw.matchMode : 'SOSL',
            minCharacters: Number.isInteger(raw.minCharacters) && raw.minCharacters > 0 ? raw.minCharacters : 2,
            placeholder: cleanString(raw.placeholder),
            defaultValue: raw.defaultValue && typeof raw.defaultValue === 'object' ? raw.defaultValue : null
        });
    });
    return defs;
}

/**
 * Filter value shape shared by FilterEntry and StoredFilterEntry (minus metadata).
 */
export function clearedFilterValue(def) {
    return {
        active: false,
        operator: defaultOperator(def),
        values: [],
        token: null,
        literal: null,
        from: null,
        to: null,
        text: null
    };
}

function defaultOperator(def) {
    if (def.type === 'DATE_RANGE') {
        return 'LITERAL';
    }
    if (def.type === 'TEXT') {
        return def.matchMode;
    }
    return 'IN';
}

export function dateRangeOperator(from, to) {
    if (from && to) {
        return 'BETWEEN';
    }
    if (from) {
        return 'GTE';
    }
    return to ? 'LTE' : 'LITERAL';
}

function constrainValues(def, values) {
    let next = Array.from(new Set(cleanStringArray(values)));
    if ((def.type === 'LOOKUP' || def.type === 'USER') && next.some((v) => !RECORD_ID_PATTERN.test(v))) {
        next = next.filter((v) => RECORD_ID_PATTERN.test(v));
    }
    if (def.type === 'PICKLIST' && def.optionsSource === 'CUSTOM') {
        const allowed = new Set(def.options.map((o) => o.value));
        next = next.filter((v) => allowed.has(v));
    }
    if (def.selectionMode === 'single' && next.length > 1) {
        next = [next[0]];
    }
    return next;
}

/**
 * Builds a validated filter value from a loose `{ values, token, operator, literal, from, to, text }` input.
 * Returns null when the input is malformed for the definition's type.
 */
export function buildFilterValue(def, input, userId) {
    if (!input || typeof input !== 'object') {
        return null;
    }
    const value = clearedFilterValue(def);
    switch (def.type) {
        case 'PICKLIST':
        case 'LOOKUP': {
            if (input.values !== undefined && !Array.isArray(input.values)) {
                return null;
            }
            value.values = constrainValues(def, input.values);
            break;
        }
        case 'USER': {
            if (input.values !== undefined && !Array.isArray(input.values)) {
                return null;
            }
            const isMe = input.token === 'ME';
            const others = cleanStringArray(input.values).filter((v) => v !== userId);
            const candidate = isMe ? [userId, ...others] : cleanStringArray(input.values);
            value.values = constrainValues(def, candidate);
            value.token = isMe && value.values.includes(userId) ? 'ME' : null;
            break;
        }
        case 'DATE_RANGE': {
            const literal = cleanString(input.literal);
            const from = cleanString(input.from);
            const to = cleanString(input.to);
            if (input.operator !== undefined && input.operator !== null) {
                if (!DATE_RANGE_OPERATORS.includes(input.operator)) {
                    return null;
                }
            }
            if (literal && (!input.operator || input.operator === 'LITERAL')) {
                if (!DATE_LITERAL_PATTERN.test(literal)) {
                    return null;
                }
                value.literal = literal;
            } else if (from || to) {
                if ((from && !ISO_DATE_PATTERN.test(from)) || (to && !ISO_DATE_PATTERN.test(to))) {
                    return null;
                }
                value.from = from;
                value.to = to;
                value.operator = dateRangeOperator(from, to);
            }
            break;
        }
        case 'TEXT': {
            value.text = cleanString(input.text);
            break;
        }
        default:
            return null;
    }
    value.active = Boolean(value.values.length || value.literal || value.from || value.to || value.text);
    return value;
}

/**
 * Validates one stored entry against its current FilterDefinition (config-drift sanitization).
 * Returns `{ value, labels }` or null when the stored entry must be discarded.
 */
export function sanitizeStoredFilterEntry(def, stored, userId) {
    if (!def || !stored || typeof stored !== 'object' || stored.type !== def.type) {
        return null;
    }
    if (typeof stored.active !== 'boolean') {
        return null;
    }
    if (!stored.active) {
        return { value: clearedFilterValue(def), labels: {} };
    }
    const value = buildFilterValue(def, stored, userId);
    if (!value) {
        return null;
    }
    const labels = {};
    if (stored.labels && typeof stored.labels === 'object') {
        value.values.forEach((id) => {
            if (typeof stored.labels[id] === 'string' && stored.labels[id]) {
                labels[id] = stored.labels[id];
            }
        });
    }
    return { value, labels };
}

export function sanitizeStoredFilters(defs, storedState, userId) {
    const filters = {};
    const labels = {};
    const storedFilters = storedState?.filters || {};
    defs.forEach((def) => {
        if (!Object.prototype.hasOwnProperty.call(storedFilters, def.filterId)) {
            return;
        }
        const sanitized = sanitizeStoredFilterEntry(def, storedFilters[def.filterId], userId);
        if (sanitized) {
            filters[def.filterId] = toStoredFilterEntry(def, sanitized.value, sanitized.labels);
            Object.assign(labels, sanitized.labels);
        }
    });
    return { filters, labels };
}

export function toStoredFilterEntry(def, value, labelCache = {}) {
    const entry = {
        type: def.type,
        active: value.active,
        operator: value.operator,
        values: value.values || [],
        token: value.token || null,
        literal: value.literal || null,
        from: value.from || null,
        to: value.to || null,
        text: value.text || null
    };
    if (def.type === 'LOOKUP' || def.type === 'USER') {
        entry.labels = {};
        entry.values.forEach((id) => {
            if (labelCache[id]) {
                entry.labels[id] = labelCache[id];
            }
        });
    }
    return entry;
}

export function buildFilterEntry(def, value, { source = 'FILTER_WIDGET', locked = false } = {}) {
    const entry = {
        filterId: def.filterId,
        label: def.label,
        type: def.type,
        source,
        publisherWidgetId: null,
        active: Boolean(value.active),
        locked,
        fieldApiName: def.fieldApiName,
        targetObjectApiName: def.targetObjectApiName,
        operator: value.operator,
        values: value.values || [],
        token: value.token || null,
        literal: value.literal || null,
        from: value.from || null,
        to: value.to || null,
        text: value.text || null
    };
    if (def.type === 'TEXT' && Number.isInteger(def.minCharacters)) {
        entry.minCharacters = def.minCharacters;
    }
    return entry;
}

/**
 * Validates a FilterEntry received through a reactive Flow `filterContextJson` input. With Filter widget
 * `definitions`, the entry must match a configured filter and is rebuilt from it (config-drift rules apply);
 * without them (no Filter widget on the scope) it is checked structurally. Never produces a locked entry.
 * Returns null when the entry must be discarded.
 */
export function buildExternalFilterEntry(definitions, key, incoming, userId) {
    if (!incoming || typeof incoming !== 'object' || Array.isArray(incoming)) {
        return null;
    }
    const filterId = cleanString(incoming.filterId) || key;
    if (definitions) {
        const def = definitions.find((candidate) => candidate.filterId === key);
        if (!def || filterId !== key || (incoming.type !== undefined && incoming.type !== def.type)) {
            return null;
        }
        const value = incoming.active === false ? clearedFilterValue(def) : buildFilterValue(def, incoming, userId);
        return value ? buildFilterEntry(def, value) : null;
    }
    const operator = incoming.operator || 'IN';
    if (!FILTER_TYPES.includes(incoming.type) || !ENTRY_OPERATORS.includes(operator)) {
        return null;
    }
    if (incoming.values !== undefined && !Array.isArray(incoming.values)) {
        return null;
    }
    const entry = buildFilterEntry(
        {
            filterId,
            label: cleanString(incoming.label) || filterId,
            type: incoming.type,
            fieldApiName: cleanString(incoming.fieldApiName),
            targetObjectApiName: cleanString(incoming.targetObjectApiName),
            minCharacters: incoming.minCharacters
        },
        {
            active: incoming.active === true,
            operator,
            values: cleanStringArray(incoming.values),
            token: incoming.token === 'ME' ? 'ME' : null,
            literal: cleanString(incoming.literal),
            from: cleanString(incoming.from),
            to: cleanString(incoming.to),
            text: cleanString(incoming.text)
        },
        { source: FILTER_SOURCES.includes(incoming.source) ? incoming.source : 'FILTER_WIDGET' }
    );
    entry.publisherWidgetId = cleanString(incoming.publisherWidgetId);
    return entry;
}

/**
 * The FilterDefinition a `LOCKED`/`DEFAULT` Record context override targets, or null when the mode is `IMPLICIT`
 * or `overrideFilterId` names no `PICKLIST`/`LOOKUP`/`USER` filter (Widgets then keep the `$recordContext` scope).
 */
export function recordContextOverrideDefinition(defs, recordContext) {
    if (!recordContext || recordContext.mode === 'IMPLICIT' || !recordContext.overrideFilterId) {
        return null;
    }
    const def = defs.find((candidate) => candidate.filterId === recordContext.overrideFilterId);
    return def && RECORD_CONTEXT_OVERRIDE_TYPES.includes(def.type) ? def : null;
}

function recordContextOverrideApplies(def, recordContext, mode) {
    return Boolean(
        recordContext &&
        recordContext.mode === mode &&
        recordContext.overrideFilterId === def.filterId &&
        recordContext.resolvedValue &&
        RECORD_CONTEXT_OVERRIDE_TYPES.includes(def.type)
    );
}

/**
 * Applies per-filter initial precedence:
 * LOCKED recordContext > stored entry (incl. explicit clear) > DEFAULT recordContext > admin defaultValue > cleared.
 */
export function resolveInitialFilters(defs, { storedFilters = {}, recordContext = null, userId = null } = {}) {
    const filters = {};
    defs.forEach((def) => {
        const overrideValue = () => ({
            ...clearedFilterValue(def),
            active: true,
            operator: 'IN',
            values: [recordContext.resolvedValue]
        });
        if (recordContextOverrideApplies(def, recordContext, 'LOCKED')) {
            filters[def.filterId] = buildFilterEntry(def, overrideValue(), { source: 'RECORD_CONTEXT', locked: true });
            return;
        }
        const stored = storedFilters[def.filterId];
        if (stored) {
            filters[def.filterId] = buildFilterEntry(def, stored);
            return;
        }
        if (recordContextOverrideApplies(def, recordContext, 'DEFAULT')) {
            filters[def.filterId] = buildFilterEntry(def, overrideValue(), { source: 'RECORD_CONTEXT' });
            return;
        }
        const adminDefault = def.defaultValue ? buildFilterValue(def, def.defaultValue, userId) : null;
        filters[def.filterId] = buildFilterEntry(def, adminDefault || clearedFilterValue(def));
    });
    return filters;
}