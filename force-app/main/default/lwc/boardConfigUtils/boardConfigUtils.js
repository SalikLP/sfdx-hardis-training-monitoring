import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import { bucketIdOf, bucketReference, findBucketField } from 'c/boardBucketFields';

/** `FilterEntry.type` values (spec §3). */
export const FILTER_TYPES = [
    'PICKLIST',
    'LOOKUP',
    'USER',
    'DATE_RANGE',
    'NUMBER_RANGE',
    'TEXT',
    'EMPTY_FILLED',
    'BUCKET'
];
/**
 * Item `type` of the Currency picker in a Filter widget's `filters` list (`{ type: 'currencyPicker', label? }`). Like
 * a Section item it is not a filter: never in the Filter context, never bound. At most one per Filter widget.
 */
export const CURRENCY_PICKER_ITEM = 'currencyPicker';

export function isCurrencyPickerItem(item) {
    return Boolean(item) && typeof item === 'object' && item.type === CURRENCY_PICKER_ITEM;
}

/**
 * A Filter widget config's `filters` list, reading the older Board-level `currencyPicker: { label }` setting as a
 * Currency picker item at the end of the list (unless the list already has one).
 */
export function filterItemsOf(config) {
    const filters = Array.isArray(config?.filters) ? config.filters : [];
    const legacy = config?.currencyPicker;
    if (!legacy || typeof legacy !== 'object' || Array.isArray(legacy) || filters.some(isCurrencyPickerItem)) {
        return filters;
    }
    const label = typeof legacy.label === 'string' && legacy.label.trim() ? legacy.label : null;
    return [...filters, label ? { type: CURRENCY_PICKER_ITEM, label } : { type: CURRENCY_PICKER_ITEM }];
}

/** `EMPTY_FILLED` operators: `field = null` / `field != null`. All is the inactive filter (no condition). */
export const EMPTY_FILLED_OPERATORS = ['EMPTY', 'FILLED'];
/** Filter types a `LOCKED`/`DEFAULT` Record context override (`overrideFilterId`) can target. */
export const RECORD_CONTEXT_OVERRIDE_TYPES = ['PICKLIST', 'LOOKUP', 'USER'];
/** `DATE_RANGE` operators: relative literal or ISO bounds. */
export const DATE_RANGE_OPERATORS = ['LITERAL', 'BETWEEN', 'GTE', 'LTE'];
/** `NUMBER_RANGE` operators: min and max (`BETWEEN`), min only (`GTE`) or max only (`LTE`). */
export const NUMBER_RANGE_OPERATORS = ['BETWEEN', 'GTE', 'LTE'];
/** `filterBindings` opt-out value. */
export const IGNORE_BINDING = 'IGNORE';

/** Grouped `DATE_RANGE` preset literals offered by the Filter bar and the Filter CPE (spec story 30). */
export const DATE_PRESET_GROUPS = [
    {
        key: 'relative',
        label: 'Relative',
        options: [
            { value: 'TODAY', label: 'Today' },
            { value: 'YESTERDAY', label: 'Yesterday' },
            { value: 'LAST_N_DAYS:7', label: 'Last 7 Days' },
            { value: 'LAST_N_DAYS:30', label: 'Last 30 Days' },
            { value: 'LAST_N_DAYS:90', label: 'Last 90 Days' }
        ]
    },
    {
        key: 'calendar',
        label: 'Calendar',
        options: [
            { value: 'THIS_WEEK', label: 'This Week' },
            { value: 'LAST_WEEK', label: 'Last Week' },
            { value: 'THIS_MONTH', label: 'This Month' },
            { value: 'LAST_MONTH', label: 'Last Month' },
            { value: 'THIS_QUARTER', label: 'This Quarter' },
            { value: 'LAST_QUARTER', label: 'Last Quarter' },
            { value: 'THIS_YEAR', label: 'This Year' },
            { value: 'LAST_YEAR', label: 'Last Year' }
        ]
    },
    {
        key: 'fiscal',
        label: 'Fiscal',
        options: [
            { value: 'THIS_FISCAL_QUARTER', label: 'This Fiscal Quarter' },
            { value: 'LAST_FISCAL_QUARTER', label: 'Last Fiscal Quarter' },
            { value: 'THIS_FISCAL_YEAR', label: 'This Fiscal Year' },
            { value: 'LAST_FISCAL_YEAR', label: 'Last Fiscal Year' }
        ]
    }
];
/** Flat `{ value, label, group }` view of `DATE_PRESET_GROUPS`. */
export const DATE_PRESETS = DATE_PRESET_GROUPS.flatMap((group) =>
    group.options.map((option) => ({ ...option, group: group.label }))
);

/**
 * Moves binding-resolution entries the server reported in `ignoredFilterIds` from `applied` to `ignored`.
 * Widgets keep the ids from their last completed query and re-apply them after every client-side resolve, so the
 * header helptext stays correct when an unchanged query signature skips the Apex call.
 * @returns {{ applied: Array, ignored: Array }}
 */
export function applyServerIgnoredFilters(applied = [], ignored = [], serverIgnoredIds = []) {
    const serverIgnored = new Set(serverIgnoredIds || []);
    if (!serverIgnored.size) {
        return { applied, ignored };
    }
    const moved = applied.filter((entry) => serverIgnored.has(entry.filterId));
    if (!moved.length) {
        return { applied, ignored };
    }
    return {
        applied: applied.filter((entry) => !serverIgnored.has(entry.filterId)),
        ignored: [...ignored, ...moved]
    };
}

/**
 * Top-level property values the `.js-meta.xml` design attributes pre-fill (`default="default"` /
 * `default="vertical"`). They don't count as explicit, so a pasted `configJson` can still set them. The defaults stay
 * in the metadata because the platform refuses to remove a property default that Flow versions reference.
 */
const METADATA_DEFAULTS = { boardId: 'default' };

function explicitTopLevel(topLevelProps, key) {
    const value = topLevelProps[key] ? String(topLevelProps[key]).trim() : '';
    return value && value !== METADATA_DEFAULTS[key] ? value : null;
}

/**
 * A Metric widget's Measures list. A config without one (a single-aggregate Metric saved before the Measures list) is
 * one visible Measure built from its `aggregateFunction`, `valueFieldApiName` and `format` (default: count records).
 */
export function metricMeasures(config) {
    const source = config && typeof config === 'object' ? config : {};
    if (Array.isArray(source.measures) && source.measures.length) {
        return source.measures;
    }
    const measure = { aggregateFunction: source.aggregateFunction || 'COUNT' };
    if (source.valueFieldApiName) {
        measure.valueFieldApiName = source.valueFieldApiName;
    }
    if (source.format && typeof source.format === 'object') {
        measure.format = source.format;
    }
    return [measure];
}

/**
 * The Average per record settings a Measure sends to Apex: for an `AVG_PER` Measure its per-record lookup `perField`
 * and how each record's value is taken, `inner` (`SUM` of its rows, the default, or `ONCE`); none for other Measures.
 */
export function perRecordSettings(measure) {
    const source = measure && typeof measure === 'object' ? measure : {};
    if (
        String(source.aggregateFunction || '')
            .trim()
            .toUpperCase() !== 'AVG_PER'
    ) {
        return {};
    }
    const inner = String(source.inner || '')
        .trim()
        .toUpperCase();
    return { perField: source.perField || null, inner: inner || 'SUM' };
}

/**
 * Whether a Widget waits for the Board's Filter widget before its first query: the `waitForFilterWidget` config key,
 * on unless explicitly `false`. The Setup dialog's live preview (`livePreview`) never waits.
 */
export function waitsForFilterWidget(config, livePreview = false) {
    return !livePreview && config?.waitForFilterWidget !== false;
}

/**
 * Board id a waiting Widget shows in its Wait for Filter widget hint card: set while the Widget waits and has no
 * Filter context yet, else empty.
 */
export function waitingForBoardId(config, livePreview, filterContext) {
    return waitsForFilterWidget(config, livePreview) && !filterContext ? config?.boardId || 'default' : '';
}

/**
 * Versioned configJson (version: 1) parser, validator, and top-level @api property precedence merger.
 */
/** Child rows were removed from the Table; a saved `childRelationship` is rejected, not migrated. */
export const CHILD_ROWS_REMOVED_MESSAGE =
    'Child rows were replaced by Row grouping: use the child object as source and group by the parent.';
const CHILD_ROWS_REMOVED_ERROR = {
    category: 'CONFIG_ERROR',
    message: CHILD_ROWS_REMOVED_MESSAGE,
    fieldPath: 'childRelationship',
    retryable: false
};

export function parseAndMergeConfig(widgetType, rawConfigJson, topLevelProps = {}) {
    const cleanTop = {};
    ['boardId', 'title', 'objectApiName'].forEach((key) => {
        const value = explicitTopLevel(topLevelProps, key);
        if (value) {
            cleanTop[key] = value;
        }
    });

    let parsed = {};
    const hasRawJson = rawConfigJson !== null && rawConfigJson !== undefined && String(rawConfigJson).trim() !== '';

    if (hasRawJson) {
        try {
            parsed =
                typeof rawConfigJson === 'string'
                    ? JSON.parse(rawConfigJson)
                    : Array.isArray(rawConfigJson)
                      ? rawConfigJson
                      : { ...rawConfigJson };
        } catch (err) {
            return {
                config: null,
                isUnconfigured: false,
                error: {
                    category: 'CONFIG_ERROR',
                    message: 'Invalid configJson: malformed JSON syntax.',
                    fieldPath: 'configJson',
                    retryable: false
                }
            };
        }

        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
            return {
                config: null,
                isUnconfigured: false,
                error: {
                    category: 'CONFIG_ERROR',
                    message: 'Invalid configJson: root value must be a JSON object.',
                    fieldPath: 'configJson',
                    retryable: false
                }
            };
        }

        if (parsed.version !== undefined && parsed.version !== 1) {
            return {
                config: null,
                isUnconfigured: false,
                error: {
                    category: 'CONFIG_ERROR',
                    message: `Unsupported configJson version: ${parsed.version}. Expected version 1.`,
                    fieldPath: 'version',
                    retryable: false
                }
            };
        }
    }

    const merged = {
        version: 1,
        widgetType,
        ...parsed,
        boardId: cleanTop.boardId || parsed.boardId || 'default',
        title: cleanTop.title || parsed.title || getDefaultTitle(widgetType)
    };

    if (widgetType !== 'filter') {
        // configJson wins for objectApiName: on a Lightning Record Page the platform sets a top-level `@api
        // objectApiName` to the host record's object, which must not retarget a pasted configJson. Flow CPEs write the
        // same value to both places, so Flow Builder is unaffected.
        const configObject = typeof parsed.objectApiName === 'string' ? parsed.objectApiName.trim() : '';
        merged.objectApiName = configObject || cleanTop.objectApiName || '';
    }

    if (widgetType === 'table' && parsed.childRelationship !== undefined && parsed.childRelationship !== null) {
        return { config: merged, isUnconfigured: false, error: CHILD_ROWS_REMOVED_ERROR };
    }

    if (widgetType === 'chart') {
        merged.chartType = parsed.chartType || 'bar';
        merged.orientation = parsed.orientation || 'vertical';
    }

    if (widgetType === 'filter') {
        merged.persistence = parsed.persistence || 'SESSION';
        merged.filters = filterItemsOf(parsed);
        delete merged.currencyPicker;
        return {
            config: merged,
            isUnconfigured: false,
            error: null
        };
    }

    if (!merged.objectApiName) {
        return {
            config: merged,
            isUnconfigured: true,
            error: null
        };
    }

    return {
        config: merged,
        isUnconfigured: false,
        error: null
    };
}

function getDefaultTitle(widgetType) {
    switch (widgetType) {
        case 'filter':
            return 'Board Filter Bar';
        case 'metric':
            return 'Metric';
        case 'chart':
            return 'Chart';
        case 'table':
            return 'Table';
        default:
            return 'Board Widget';
    }
}

export function normalizeBoardError(err) {
    if (!err) {
        return {
            category: 'QUERY_ERROR',
            message: 'An unexpected error occurred.',
            filterId: null,
            fieldPath: null,
            retryable: true
        };
    }

    if (err.category && err.message) {
        return {
            category: err.category,
            message: err.message,
            filterId: err.filterId || null,
            fieldPath: err.fieldPath || null,
            retryable: err.retryable !== undefined ? Boolean(err.retryable) : err.category === 'QUERY_ERROR'
        };
    }

    const rawMessage = err.body?.message || err.message || String(err);
    try {
        const parsed = JSON.parse(rawMessage);
        if (parsed && parsed.category && parsed.message) {
            return {
                category: parsed.category,
                message: parsed.message,
                filterId: parsed.filterId || null,
                fieldPath: parsed.fieldPath || null,
                retryable:
                    parsed.retryable !== undefined ? Boolean(parsed.retryable) : parsed.category === 'QUERY_ERROR'
            };
        }
    } catch (e) {
        // Not a serialized BoardErrorPayload
    }

    return {
        category: 'QUERY_ERROR',
        message: rawMessage,
        filterId: null,
        fieldPath: null,
        retryable: true
    };
}

/**
 * Filter binding resolution
 *
 * Resolves every active Board filter (IMPLICIT Record context, `filters`, and `crossFilters` not published by this
 * Widget) against a Widget's `filterBindings` and object describe (`BoardSchemaService.getObjectFields`):
 * 1. Explicit path (`"AccountId"`, `"Account.ParentId"`, `"CaseComment(ParentId).CreatedById"`) → bound, explicit.
 * 2. `"IGNORE"` / `null` → ignored.
 * 3. Convention: Step 1 exact `fieldApiName` (USER defaults to `OwnerId`); Step 2 (LOOKUP, USER, Record context)
 *    `Id` on the target object or the single filterable reference field to the target (excluding audit fields).
 *    Record context with an unknown object is sent without a path so `BoardQueryService` resolves Step 2 from the ID.
 * Any other explicit binding value (blank, non-string) fails closed with a `CONFIG_ERROR`.
 */
export const RECORD_CONTEXT_FILTER_ID = '$recordContext';
const AUDIT_REFERENCE_FIELDS = new Set(['createdbyid', 'lastmodifiedbyid']);
const STEP_TWO_TYPES = new Set(['LOOKUP', 'USER', 'RECORD_CONTEXT']);
const COMPATIBLE_FIELD_TYPES = {
    PICKLIST: new Set(['PICKLIST', 'MULTIPICKLIST', 'STRING', 'BOOLEAN', 'COMBOBOX']),
    DATE_RANGE: new Set(['DATE', 'DATETIME']),
    NUMBER_RANGE: new Set(['INTEGER', 'LONG', 'DOUBLE', 'CURRENCY', 'PERCENT']),
    TEXT: new Set(['STRING', 'TEXTAREA', 'EMAIL', 'PHONE', 'URL', 'PICKLIST', 'COMBOBOX'])
};

function hasSelection(entry) {
    const text = entry.text ? String(entry.text).trim() : '';
    switch (entry.operator || 'IN') {
        case 'IN':
            return (Array.isArray(entry.values) && entry.values.length > 0) || entry.token === 'ME';
        case 'LITERAL':
            return Boolean(entry.literal);
        case 'BETWEEN':
            return Boolean(entry.from || entry.to);
        case 'GTE':
            return Boolean(entry.from);
        case 'LTE':
            return Boolean(entry.to);
        case 'CONTAINS':
        case 'STARTS_WITH':
        case 'SOSL':
            return text.length > 0;
        case 'EMPTY':
        case 'FILLED':
            return true;
        default:
            return false;
    }
}

/** Active filter entries of a FilterContext that apply to the Widget identified by `widgetId`. */
export function collectActiveFilters(filterContext, widgetId = null) {
    if (!filterContext) {
        return [];
    }
    const active = [];
    const recordContext = filterContext.recordContext || {};
    const recordValue = recordContext.resolvedValue;
    // The Record context scopes Widgets unless a LOCKED/DEFAULT override replaced it with a PICKLIST/LOOKUP/USER
    // filter. A value read through `overrideFieldPath` is not an Id of the host object, so it is sent without a target
    // object and `BoardQueryService` resolves Step 2 from its key prefix.
    if (!recordContext.overrideApplies && recordValue) {
        active.push({
            filterId: RECORD_CONTEXT_FILTER_ID,
            label: 'Record',
            type: 'RECORD_CONTEXT',
            operator: 'IN',
            values: [recordValue],
            targetObjectApiName: recordValue === recordContext.recordId ? recordContext.objectApiName || null : null
        });
    }
    Object.values(filterContext.filters || {}).forEach((entry) => {
        if (entry && entry.filterId && entry.active && hasSelection(entry)) {
            active.push(entry);
        }
    });
    Object.values(filterContext.crossFilters || {}).forEach((entry) => {
        if (
            entry &&
            entry.filterId &&
            entry.active &&
            hasSelection(entry) &&
            (!widgetId || entry.publisherWidgetId !== widgetId)
        ) {
            active.push(entry);
        }
    });
    return active;
}

function isFieldCompatible(entry, field, objectApiName) {
    const dataType = field.dataType;
    if (entry.type === 'LOOKUP' || entry.type === 'USER') {
        const targets = (field.referenceTo || []).map((name) => name.toLowerCase());
        if (dataType === 'ID') {
            const target = entry.type === 'USER' ? 'user' : (entry.targetObjectApiName || '').toLowerCase();
            return !target || target === objectApiName.toLowerCase();
        }
        if (dataType !== 'REFERENCE') {
            return false;
        }
        if (entry.type === 'USER') {
            return targets.includes('user') || targets.includes('group');
        }
        return !entry.targetObjectApiName || targets.includes(entry.targetObjectApiName.toLowerCase());
    }
    if (entry.type === 'TEXT') {
        return COMPATIBLE_FIELD_TYPES.TEXT.has(dataType);
    }
    if (entry.type === 'EMPTY_FILLED') {
        // Any filterable field; the readable-field list already excludes what the user cannot see.
        return true;
    }
    const compatible = COMPATIBLE_FIELD_TYPES[entry.type];
    return Boolean(compatible && compatible.has(dataType));
}

function conventionFieldPath(entry, objectApiName, fieldsByName, fields) {
    if (entry.type === 'TEXT') {
        const hinted = entry.fieldApiName ? fieldsByName.get(entry.fieldApiName.toLowerCase()) : null;
        const hintedPath =
            hinted && hinted.isFilterable && isFieldCompatible(entry, hinted, objectApiName) ? hinted.apiName : null;
        if (entry.operator === 'SOSL') {
            // A fieldApiName hint on this object searches that column (sent as CONTAINS); otherwise server-side SOSL
            // over the Widget object with no field path.
            return hintedPath || undefined;
        }
        if (entry.operator !== 'CONTAINS' && entry.operator !== 'STARTS_WITH') {
            return null;
        }
        if (hintedPath) {
            return hintedPath;
        }
        const nameField = fields.find((field) => field.isNameField && field.isFilterable);
        return nameField ? nameField.apiName : null;
    }

    // Step 1: exact fieldApiName match
    const fieldApiName = entry.fieldApiName || (entry.type === 'USER' ? 'OwnerId' : null);
    const direct = fieldApiName ? fieldsByName.get(fieldApiName.toLowerCase()) : null;
    if (direct && direct.isFilterable && isFieldCompatible(entry, direct, objectApiName)) {
        return direct.apiName;
    }
    if (!STEP_TWO_TYPES.has(entry.type)) {
        return null;
    }

    // Step 2: targetObjectApiName match
    const target = entry.targetObjectApiName || (entry.type === 'USER' ? 'User' : null);
    if (!target) {
        return undefined;
    }
    if (target.toLowerCase() === objectApiName.toLowerCase()) {
        return 'Id';
    }
    const candidates = fields.filter(
        (field) =>
            field.dataType === 'REFERENCE' &&
            field.isFilterable &&
            !AUDIT_REFERENCE_FIELDS.has(field.apiName.toLowerCase()) &&
            (field.referenceTo || []).some((name) => name.toLowerCase() === target.toLowerCase())
    );
    return candidates.length === 1 ? candidates[0].apiName : null;
}

/**
 * @param {object} params
 * @param {string} params.objectApiName Widget object
 * @param {Array} params.fields `BoardSchemaService.getObjectFields(objectApiName)` (readable fields only)
 * @param {object} params.filterContext Board FilterContext
 * @param {object} [params.filterBindings] Widget `filterBindings`
 * @param {string} [params.widgetId] Widget id used to skip its own cross filters
 * @param {Array} [params.bucketFields] the Widget's own Bucket fields
 * @param {Array} [params.boardBucketFields] the Board-level Bucket fields (`getBoardBucketFields`)
 * @returns {{ filters: Array, applied: Array<{filterId, label, fieldPath}>, ignored: Array<{filterId, label}>,
 *   error: object|null }} `filters` is the `BoardQueryService` request payload (sorted by filterId). `error` is a
 *   `CONFIG_ERROR` BoardErrorPayload for the first malformed explicit binding; Widgets render it instead of querying
 *   (the payload still carries that filter as explicit without a path, which the server rejects).
 *   A `BUCKET` filter binds to a Bucket field (`bucket:<id>`, by convention the filter's own): the Widget's own first,
 *   else the Board's. Its payload carries that Bucket field's config as `bucketField`; an unknown id is ignored by
 *   convention and a `CONFIG_ERROR` when explicit.
 */
export function resolveFilterBindings({
    objectApiName,
    fields,
    filterContext,
    filterBindings,
    widgetId,
    bucketFields,
    boardBucketFields
}) {
    const bindings = filterBindings && typeof filterBindings === 'object' ? filterBindings : {};
    const fieldList = Array.isArray(fields) ? fields : [];
    const fieldsByName = new Map(fieldList.map((field) => [field.apiName.toLowerCase(), field]));
    const filters = [];
    const applied = [];
    const ignored = [];
    let error = null;

    collectActiveFilters(filterContext, widgetId).forEach((entry) => {
        const label = entry.label || entry.filterId;
        let fieldPath = null;
        let explicit = false;
        let operator = entry.operator || 'IN';
        if (Object.prototype.hasOwnProperty.call(bindings, entry.filterId)) {
            const binding = bindings[entry.filterId];
            const trimmed = typeof binding === 'string' ? binding.trim() : '';
            if (binding === null || trimmed.toUpperCase() === IGNORE_BINDING) {
                ignored.push({ filterId: entry.filterId, label });
                return;
            }
            explicit = true;
            if (trimmed) {
                fieldPath = trimmed;
            } else if (!error) {
                error = {
                    category: 'CONFIG_ERROR',
                    message: `Filter binding for "${entry.filterId}" must be a field path, "IGNORE", or null.`,
                    filterId: entry.filterId,
                    fieldPath: `filterBindings.${entry.filterId}`,
                    retryable: false
                };
            }
        }
        let bucketField = null;
        if (entry.type === 'BUCKET') {
            const bucketId = explicit ? bucketIdOf(fieldPath) : entry.bucketFieldId || null;
            bucketField = bucketId
                ? findBucketField(bucketFields, bucketId) || findBucketField(boardBucketFields, bucketId)
                : null;
            if (!bucketField) {
                if (explicit && !error) {
                    error = {
                        category: 'CONFIG_ERROR',
                        message: `Filter binding for "${entry.filterId}" must name a Bucket field of this Widget or the Board (bucket:<id>); "${fieldPath}" is unknown.`,
                        filterId: entry.filterId,
                        fieldPath: `filterBindings.${entry.filterId}`,
                        retryable: false
                    };
                }
                ignored.push({ filterId: entry.filterId, label });
                return;
            }
            fieldPath = bucketReference(bucketId);
        } else if (!explicit) {
            fieldPath = conventionFieldPath(entry, objectApiName, fieldsByName, fieldList);
            if (fieldPath === null) {
                ignored.push({ filterId: entry.filterId, label });
                return;
            }
            // undefined: Record context without a known object (BoardQueryService resolves Step 2 from the ID) or a
            // SOSL search without a field hint.
            fieldPath = fieldPath || null;
            if (operator === 'SOSL' && fieldPath) {
                operator = 'CONTAINS';
            }
        }
        applied.push({ filterId: entry.filterId, label, fieldPath });
        const filter = {
            filterId: entry.filterId,
            type: entry.type,
            fieldPath,
            explicit,
            operator,
            values: Array.isArray(entry.values) ? [...entry.values].sort() : [],
            token: entry.token || null,
            literal: entry.literal || null,
            from: entry.from || null,
            to: entry.to || null,
            text: entry.text ? String(entry.text).trim() : null,
            targetObjectApiName: entry.targetObjectApiName || null,
            fieldApiName: entry.fieldApiName || null,
            minCharacters: Number.isInteger(entry.minCharacters) ? entry.minCharacters : null
        };
        if (entry.type === 'USER' && entry.matchMode === 'usersAndTeam') {
            // Each picked user's Team; BoardQueryService resolves the roles below theirs (never sent to the client).
            filter.matchMode = entry.matchMode;
        }
        if (bucketField) {
            filter.bucketField = bucketField;
        }
        filters.push(filter);
    });

    filters.sort((a, b) => a.filterId.localeCompare(b.filterId));
    return { filters, applied, ignored, error };
}

/** Header `<lightning-helptext>` text, or null when every active filter applies to the Widget. */
export function buildFilterBindingSummary(applied = [], ignored = []) {
    if (!ignored.length) {
        return null;
    }
    const appliedLabels = applied.length ? applied.map((entry) => entry.label).join(', ') : 'None';
    return `Applied filters: ${appliedLabels} · Ignored on this widget: ${ignored.map((entry) => entry.label).join(', ')}`;
}

function canonicalize(value) {
    if (Array.isArray(value)) {
        return value.map(canonicalize);
    }
    if (value && typeof value === 'object') {
        return Object.keys(value)
            .sort()
            .reduce((acc, key) => {
                acc[key] = canonicalize(value[key]);
                return acc;
            }, {});
    }
    return value === undefined ? null : value;
}

/** Canonical effective-query signature (key-order independent) used to skip redundant Apex calls. */
export function buildQuerySignature(request) {
    return JSON.stringify(canonicalize(request));
}

/**
 * `Intl.NumberFormat` value formatter for `ValueFormatConfig`.
 * @param {number} value
 * @param {object} [format] ValueFormatConfig
 * @param {object} [options] `{ notation }` widget default, `{ valueType }` source `Schema.DisplayType` name
 *   (`PERCENT` field values are stored as whole percentages and are divided by 100 for `formatStyle: 'percent'`).
 */
export function formatValue(value, format = {}, options = {}) {
    const cfg = format || {};
    const style = cfg.formatStyle || 'number';
    const notation = cfg.notation || options.notation || 'standard';
    const numberOptions = { style: style === 'number' ? 'decimal' : style, notation };
    if (style === 'currency') {
        numberOptions.currency = cfg.currencyCode || CURRENCY;
    }
    const hasMin = typeof cfg.minimumFractionDigits === 'number';
    const hasMax = typeof cfg.maximumFractionDigits === 'number';
    if (hasMin) {
        numberOptions.minimumFractionDigits = cfg.minimumFractionDigits;
    }
    if (hasMax) {
        numberOptions.maximumFractionDigits = Math.max(
            cfg.maximumFractionDigits,
            hasMin ? cfg.minimumFractionDigits : 0
        );
    } else if (notation === 'compact') {
        numberOptions.maximumFractionDigits = Math.max(1, hasMin ? cfg.minimumFractionDigits : 0);
    }
    const numeric = style === 'percent' && options.valueType === 'PERCENT' ? Number(value) / 100 : Number(value);
    let formatted;
    try {
        formatted = new Intl.NumberFormat(LOCALE, numberOptions).format(numeric);
    } catch (e) {
        formatted = String(value);
    }
    return `${cfg.prefix || ''}${formatted}${cfg.suffix || ''}`;
}

/**
 * Locale-formats a Date or DateTime value. An ISO `yyyy-mm-dd` Date renders in UTC so it never shifts a day; other
 * values render in the user's time zone. Returns the raw value as text when it cannot be parsed.
 * @param {string} value non-empty Date/DateTime value
 * @param {'date'|'datetime'} displayAs
 */
export function formatTemporal(value, displayAs) {
    try {
        if (displayAs === 'date') {
            const isoDate = /^\d{4}-\d{2}-\d{2}$/.test(String(value));
            return new Intl.DateTimeFormat(LOCALE, {
                dateStyle: 'medium',
                timeZone: isoDate ? 'UTC' : TIME_ZONE
            }).format(new Date(isoDate ? `${value}T00:00:00Z` : value));
        }
        return new Intl.DateTimeFormat(LOCALE, { dateStyle: 'medium', timeStyle: 'short', timeZone: TIME_ZONE }).format(
            new Date(value)
        );
    } catch (e) {
        return String(value);
    }
}