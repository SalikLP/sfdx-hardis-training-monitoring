/**
 * Shared service module of the Board Flow Custom Property Editors (`c-board-cpe-common` and the four widget CPEs):
 * enum option lists, field path / binding / relative date grammar, memoized describe loaders, filterId derivation,
 * the versioned config envelope (`readCpeState`, ordering, serialization), and the design-time rules shared by
 * `validate()` and pasted Config JSON (`configErrors`).
 */
import getQueryableObjects from '@salesforce/apex/BoardSchemaService.getQueryableObjects';
import getObjectFields from '@salesforce/apex/BoardSchemaService.getObjectFields';
import getChildRelationships from '@salesforce/apex/BoardSchemaService.getChildRelationships';
import {
    DATE_PRESETS,
    DATE_RANGE_OPERATORS,
    FILTER_TYPES,
    IGNORE_BINDING,
    RECORD_CONTEXT_OVERRIDE_TYPES
} from 'c/boardConfigUtils';

// ---- Enums: one `{ value, label }` list each; value arrays are derived -------------------------------------------

function optionValues(options) {
    return options.map((option) => option.value);
}

export const AGGREGATE_OPTIONS = [
    { label: 'Count of records', value: 'COUNT' },
    { label: 'Count distinct', value: 'COUNT_DISTINCT' },
    { label: 'Sum', value: 'SUM' },
    { label: 'Average', value: 'AVG' },
    { label: 'Minimum', value: 'MIN' },
    { label: 'Maximum', value: 'MAX' }
];
const AGGREGATE_FUNCTIONS = optionValues(AGGREGATE_OPTIONS);
export const ROLLUP_FUNCTIONS = ['COUNT', 'SUM'];
export const DATE_GRANULARITY_OPTIONS = [
    { label: 'Day (default)', value: 'DAY' },
    { label: 'Calendar month', value: 'CALENDAR_MONTH' },
    { label: 'Calendar quarter', value: 'CALENDAR_QUARTER' },
    { label: 'Calendar year', value: 'CALENDAR_YEAR' },
    { label: 'Fiscal quarter', value: 'FISCAL_QUARTER' },
    { label: 'Fiscal year', value: 'FISCAL_YEAR' }
];
const DATE_GRANULARITIES = optionValues(DATE_GRANULARITY_OPTIONS);
export const BAR_SORT_OPTIONS = [
    { label: 'Value (high to low)', value: 'VALUE_DESC' },
    { label: 'Value (low to high)', value: 'VALUE_ASC' },
    { label: 'Label (A to Z)', value: 'LABEL_ASC' },
    { label: 'Label (Z to A)', value: 'LABEL_DESC' },
    { label: 'Picklist order', value: 'PICKLIST_ORDER' },
    { label: 'Chronological (oldest first)', value: 'CHRONOLOGICAL_ASC' },
    { label: 'Chronological (newest first)', value: 'CHRONOLOGICAL_DESC' }
];
const BAR_SORTS = optionValues(BAR_SORT_OPTIONS);
export const THRESHOLD_OPERATOR_OPTIONS = [
    { label: 'Greater than', value: 'gt' },
    { label: 'Greater or equal', value: 'gte' },
    { label: 'Less than', value: 'lt' },
    { label: 'Less or equal', value: 'lte' }
];
const THRESHOLD_OPERATORS = optionValues(THRESHOLD_OPERATOR_OPTIONS);
export const THRESHOLD_VARIANT_OPTIONS = [
    { label: 'Success (green)', value: 'success' },
    { label: 'Warning (orange)', value: 'warning' },
    { label: 'Error (red)', value: 'error' }
];
const THRESHOLD_VARIANTS = optionValues(THRESHOLD_VARIANT_OPTIONS);
export const FORMAT_STYLE_OPTIONS = [
    { label: 'Number', value: 'number' },
    { label: 'Currency', value: 'currency' },
    { label: 'Percent', value: 'percent' }
];
const FORMAT_STYLES = optionValues(FORMAT_STYLE_OPTIONS);
export const NOTATION_OPTIONS = [
    { label: 'Standard (1,234,567)', value: 'standard' },
    { label: 'Compact (1.2M)', value: 'compact' }
];
const NOTATIONS = optionValues(NOTATION_OPTIONS);
export const FILTER_TYPE_LABELS = {
    PICKLIST: 'Picklist',
    LOOKUP: 'Lookup',
    USER: 'User',
    DATE_RANGE: 'Date range',
    TEXT: 'Text search'
};
export const FILTER_TYPE_OPTIONS = FILTER_TYPES.map((type) => ({ label: FILTER_TYPE_LABELS[type], value: type }));
export const TEXT_MATCH_MODE_OPTIONS = [
    { label: 'Search all text fields (SOSL)', value: 'SOSL' },
    { label: 'Field contains', value: 'CONTAINS' },
    { label: 'Field starts with', value: 'STARTS_WITH' }
];
const TEXT_MATCH_MODES = optionValues(TEXT_MATCH_MODE_OPTIONS);
export const RECORD_CONTEXT_MODE_OPTIONS = [
    { label: 'Implicit: the record filters Widgets by convention', value: 'IMPLICIT' },
    { label: 'Locked: the record value is fixed', value: 'LOCKED' },
    { label: 'Default: the record value is preselected', value: 'DEFAULT' }
];
export const RECORD_CONTEXT_MODES = optionValues(RECORD_CONTEXT_MODE_OPTIONS);
export const PERSISTENCE_OPTIONS = [
    { label: 'This browser tab (session)', value: 'SESSION' },
    { label: 'This browser (local)', value: 'LOCAL' },
    { label: 'Do not remember', value: 'NONE' }
];
const PERSISTENCE_MODES = optionValues(PERSISTENCE_OPTIONS);
export const BASE_FILTER_OPERATOR_OPTIONS = [
    { label: 'Equals', value: 'EQ' },
    { label: 'Not equal to', value: 'NEQ' },
    { label: 'In list', value: 'IN' },
    { label: 'Not in list', value: 'NOT_IN' },
    { label: 'Greater than', value: 'GT' },
    { label: 'Greater or equal', value: 'GTE' },
    { label: 'Less than', value: 'LT' },
    { label: 'Less or equal', value: 'LTE' },
    { label: 'Contains (LIKE)', value: 'LIKE' },
    { label: 'Is null', value: 'IS_NULL' },
    { label: 'Relative date', value: 'LITERAL' }
];
const BASE_FILTER_OPERATORS = optionValues(BASE_FILTER_OPERATOR_OPTIONS);
export const VALUE_REQUIRED_OPERATORS = new Set(['GT', 'GTE', 'LT', 'LTE', 'LIKE']);
export const LIST_OPERATORS = new Set(['IN', 'NOT_IN']);
export const ORIENTATION_OPTIONS = [
    { label: 'Vertical', value: 'vertical' },
    { label: 'Horizontal', value: 'horizontal' }
];
const ORIENTATIONS = optionValues(ORIENTATION_OPTIONS);
export const DATE_FIELD_TYPES = ['DATE', 'DATETIME'];
export const PICKLIST_FIELD_TYPES = ['PICKLIST', 'MULTIPICKLIST'];

const DATE_PRESET_VALUES = new Set(optionValues(DATE_PRESETS));
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const FILTER_ID = /^[A-Za-z][A-Za-z0-9_]*$/;
const CURRENCY_CODE = /^[A-Za-z]{3}$/;
/** Mirrors BoardQueryService.MIN_SEARCH_CHARACTERS. */
export const MIN_SEARCH_CHARACTERS = 2;
const RECORD_ID = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;
const STRING_KEYS = ['boardId', 'title', 'subtitle'];

// Mirrors BoardQueryService.RELATIVE_DATE_PATTERN.
const RELATIVE_DATE_PATTERN = new RegExp(
    '^(YESTERDAY|TODAY|TOMORROW|(LAST|THIS|NEXT)_(WEEK|MONTH|QUARTER|YEAR|FISCAL_QUARTER|FISCAL_YEAR)' +
        '|(LAST|NEXT)_90_DAYS|(LAST|NEXT)_N_(DAYS|WEEKS|MONTHS|QUARTERS|YEARS|FISCAL_QUARTERS|FISCAL_YEARS):\\d{1,4}' +
        '|N_(DAYS|WEEKS|MONTHS|QUARTERS|YEARS|FISCAL_QUARTERS|FISCAL_YEARS)_AGO:\\d{1,4})$'
);

// Binding grammar: `Field`, 1–5 hop `Parent.Field`, `Child(ForeignKey).Path`.
const IDENT = '[A-Za-z][A-Za-z0-9_]*';
const DOT_PATH = `${IDENT}(?:\\.${IDENT}){0,5}`;
const SINGLE_PATH = new RegExp(`^(?:${IDENT}\\(${IDENT}\\)\\.)?${DOT_PATH}$`);
const PARENT_PATH = new RegExp(`^${DOT_PATH}$`);
const CHILD_TARGET = new RegExp(`^${IDENT}\\(${IDENT}\\)$`);

export const BINDING_PATH_HELP = 'Use Field, Parent.Field (1–5 hops), Child(ForeignKey).Field, or IGNORE.';

// ---- Small helpers -------------------------------------------------------------------------------------------------

/** Trimmed non-empty string, else null. */
export function cleanString(value) {
    return typeof value === 'string' && value.trim() ? value.trim() : null;
}

export function isPlainObject(value) {
    return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function hasValue(value) {
    return value !== null && value !== undefined && value !== '';
}

/** Shallow copy of `target` with `patch` merged in; a null/undefined patch value deletes the key. */
export function applyPatch(target, patch) {
    const next = { ...target };
    Object.entries(patch).forEach(([key, value]) => {
        if (value === null || value === undefined) {
            delete next[key];
        } else {
            next[key] = value;
        }
    });
    return next;
}

/** True for `IGNORE` (any case) or null: the Widget opts out of the filter. */
export function isIgnoreBinding(binding) {
    return binding === null || (typeof binding === 'string' && binding.trim().toUpperCase() === IGNORE_BINDING);
}

// ---- Grammar -------------------------------------------------------------------------------------------------------

/** True for `IGNORE`, `null`, a direct/parent/child path, or a TEXT multi-field / SOSL target list. */
export function isValidBindingPath(binding) {
    if (binding === null) {
        return true;
    }
    if (typeof binding !== 'string' || !binding.trim()) {
        return false;
    }
    const trimmed = binding.trim();
    if (trimmed.toUpperCase() === IGNORE_BINDING) {
        return true;
    }
    const parts = trimmed.split(',').map((part) => part.trim());
    if (parts.length === 1) {
        return SINGLE_PATH.test(parts[0]);
    }
    return parts.every(
        (part) => part && (SINGLE_PATH.test(part) || part.toUpperCase() === 'SELF' || CHILD_TARGET.test(part))
    );
}

/** A direct field, 1–5 hop parent path, or `Child(ForeignKey).Path`. */
export function isValidFieldPath(path) {
    return typeof path === 'string' && SINGLE_PATH.test(path.trim());
}

/** A direct field or 1–5 hop parent path (no child semi-join). */
export function isParentFieldPath(path) {
    return typeof path === 'string' && PARENT_PATH.test(path.trim());
}

export function isRelativeDateLiteral(value) {
    return typeof value === 'string' && RELATIVE_DATE_PATTERN.test(value.trim().toUpperCase());
}

/** True when `literal` is one of the shared `DATE_PRESETS` (the Filter bar's preset list). */
export function isDatePreset(literal) {
    return DATE_PRESET_VALUES.has(literal);
}

// ---- Ids and lists -------------------------------------------------------------------------------------------------

/** `"Account Owner"` → `accountOwner`; identifiers always start with a letter. */
export function toCamelCase(label) {
    const words = String(label || '')
        .normalize('NFKD')
        .replace(/[\u0300-\u036f]/g, '')
        .split(/[^A-Za-z0-9]+/)
        .filter(Boolean);
    const camel = words
        .map((word, index) => {
            const lower = word === word.toUpperCase() ? word.toLowerCase() : word;
            return index === 0
                ? lower.charAt(0).toLowerCase() + lower.slice(1)
                : lower.charAt(0).toUpperCase() + lower.slice(1);
        })
        .join('');
    if (!camel) {
        return 'filter';
    }
    return /^[A-Za-z]/.test(camel) ? camel : `filter${camel}`;
}

/** `base`, or `base2`, `base3`, … when taken. */
export function uniqueId(base, takenIds) {
    const taken = new Set(takenIds);
    if (!taken.has(base)) {
        return base;
    }
    let suffix = 2;
    while (taken.has(`${base}${suffix}`)) {
        suffix += 1;
    }
    return `${base}${suffix}`;
}

/** True when `filterId` was derived from `label` (optionally de-duplicated with a numeric suffix). */
export function isDerivedId(filterId, label) {
    if (!filterId) {
        return true;
    }
    const base = toCamelCase(label);
    return filterId === base || new RegExp(`^${base}\\d+$`).test(filterId);
}

/** Next `<prefix>N` id (max + 1) over items' `id`s. */
export function nextSequentialId(items, prefix) {
    const pattern = new RegExp(`^${prefix}(\\d+)$`);
    const max = (Array.isArray(items) ? items : []).reduce((highest, item) => {
        const match = pattern.exec(isPlainObject(item) ? item.id || '' : '');
        return match ? Math.max(highest, Number(match[1])) : highest;
    }, 0);
    return `${prefix}${max + 1}`;
}

/** Number input value → number, or null when empty / not numeric. */
export function parseNumber(value) {
    if (value === null || value === undefined || String(value).trim() === '') {
        return null;
    }
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
}

/** Moves `items[index]` by `offset`, returning a new array (or the same array when out of range). */
export function moveItem(items, index, offset) {
    const target = index + offset;
    if (index < 0 || index >= items.length || target < 0 || target >= items.length) {
        return items;
    }
    const next = [...items];
    const [item] = next.splice(index, 1);
    next.splice(target, 0, item);
    return next;
}

// ---- Describe loaders (org-wide results memoized per page; failed calls are evicted) ------------------------------

let objectsPromise = null;
const fieldPromises = new Map();
const childPromises = new Map();

function memoize(cache, objectApiName, loader) {
    const key = objectApiName.toLowerCase();
    if (!cache.has(key)) {
        cache.set(
            key,
            loader({ objectApiName }).catch((err) => {
                cache.delete(key);
                throw err;
            })
        );
    }
    return cache.get(key);
}

/** `BoardSchemaService.getQueryableObjects` (slow on a cold cache, so shared by every picker). */
export function loadQueryableObjects() {
    if (!objectsPromise) {
        objectsPromise = getQueryableObjects().catch((err) => {
            objectsPromise = null;
            throw err;
        });
    }
    return objectsPromise;
}

/** `BoardSchemaService.getObjectFields` for `objectApiName`. */
export function loadObjectFields(objectApiName) {
    return memoize(fieldPromises, objectApiName, getObjectFields);
}

/** `BoardSchemaService.getChildRelationships` for `objectApiName`. */
export function loadChildRelationships(objectApiName) {
    return memoize(childPromises, objectApiName, getChildRelationships);
}

/**
 * Leaf field describe (`BoardSchemaService.FieldInfo`) of a direct or 1–5 hop parent `path` on `objectApiName`,
 * traversing polymorphic lookups to `User` like `BoardQueryService`. Resolves null when the path does not resolve.
 */
export async function resolveFieldDescribe(objectApiName, path) {
    if (!cleanString(objectApiName) || !isParentFieldPath(path)) {
        return null;
    }
    const segments = path.trim().split('.');
    let current = objectApiName.trim();
    for (let index = 0; index < segments.length; index++) {
        // Each hop's object is only known once the previous describe resolves.
        // eslint-disable-next-line no-await-in-loop
        const fields = (await loadObjectFields(current)) || [];
        const segment = segments[index].toLowerCase();
        if (index === segments.length - 1) {
            return fields.find((field) => field.apiName.toLowerCase() === segment) || null;
        }
        const reference = fields.find(
            (field) => field.relationshipName && field.relationshipName.toLowerCase() === segment
        );
        const targets = reference ? reference.referenceTo || [] : [];
        if (!targets.length) {
            return null;
        }
        current = targets.includes('User') ? 'User' : targets[0];
    }
    return null;
}

// ---- Widget validation ([{ key, errorString }]) -------------------------------------------------------------------

function error(key, errorString) {
    return { key, errorString };
}

function isIntegerInRange(value, min, max) {
    return Number.isInteger(value) && value >= min && value <= max;
}

/** Problems with a ValueFormatConfig, prefixed by `label`. */
export function formatErrors(format, key, label) {
    if (format === undefined || format === null) {
        return [];
    }
    if (!isPlainObject(format)) {
        return [error(key, `${label} must be an object.`)];
    }
    const errors = [];
    if (hasValue(format.formatStyle) && !FORMAT_STYLES.includes(format.formatStyle)) {
        errors.push(error(key, `${label}: style must be number, currency, or percent.`));
    }
    if (hasValue(format.notation) && !NOTATIONS.includes(format.notation)) {
        errors.push(error(key, `${label}: notation must be standard or compact.`));
    }
    const min = format.minimumFractionDigits;
    const max = format.maximumFractionDigits;
    if (hasValue(min) && !isIntegerInRange(min, 0, 20)) {
        errors.push(error(key, `${label}: minimum fraction digits must be a whole number from 0 to 20.`));
    }
    if (hasValue(max) && !isIntegerInRange(max, 0, 20)) {
        errors.push(error(key, `${label}: maximum fraction digits must be a whole number from 0 to 20.`));
    }
    if (isIntegerInRange(min, 0, 20) && isIntegerInRange(max, 0, 20) && min > max) {
        errors.push(error(key, `${label}: minimum fraction digits cannot exceed maximum fraction digits.`));
    }
    if (hasValue(format.currencyCode) && !CURRENCY_CODE.test(String(format.currencyCode))) {
        errors.push(error(key, `${label}: currency code must be a 3-letter ISO code such as USD.`));
    }
    return errors;
}

function aggregateErrors(config, widgetLabel, numericOnly) {
    const errors = [];
    const fn = config.aggregateFunction;
    if (hasValue(fn) && !AGGREGATE_FUNCTIONS.includes(fn)) {
        errors.push(error('aggregateFunction', `Aggregate function must be one of ${AGGREGATE_FUNCTIONS.join(', ')}.`));
        return errors;
    }
    if (hasValue(fn) && fn !== 'COUNT' && !cleanString(config.valueFieldApiName)) {
        const kind = fn === 'COUNT_DISTINCT' || !numericOnly ? 'a field' : 'a numeric field';
        errors.push(error('valueFieldApiName', `Choose ${kind} to aggregate with ${fn} on this ${widgetLabel}.`));
    } else if (cleanString(config.valueFieldApiName) && !isParentFieldPath(config.valueFieldApiName)) {
        // Direct field or 1–5 hop parent path, matching BoardQueryService.resolveValueField.
        errors.push(error('valueFieldApiName', `Value field "${config.valueFieldApiName}" is not a valid field path.`));
    }
    return errors;
}

function filterLabel(filter, index) {
    const label = isPlainObject(filter) ? cleanString(filter.label) || cleanString(filter.filterId) : null;
    return label ? `Filter ${index + 1} ("${label}")` : `Filter ${index + 1}`;
}

/** Effective selection mode, matching `normalizeFilterDefinitions`. */
export function filterSelectionMode(filter) {
    if (filter.type === 'PICKLIST') {
        return filter.selectionMode === 'single' ? 'single' : 'multi';
    }
    return filter.selectionMode === 'multi' ? 'multi' : 'single';
}

/** Effective PICKLIST options source, matching `normalizeFilterDefinitions` (options imply CUSTOM). */
export function filterOptionsSource(filter) {
    const hasOptions = Array.isArray(filter.options) && filter.options.length > 0;
    return filter.optionsSource === 'CUSTOM' || (!filter.optionsSource && hasOptions) ? 'CUSTOM' : 'FIELD_DESCRIBE';
}

function dateDefaultErrors(defaultValue, label) {
    const errors = [];
    const literal = cleanString(defaultValue.literal);
    const from = cleanString(defaultValue.from);
    const to = cleanString(defaultValue.to);
    if (hasValue(defaultValue.operator) && !DATE_RANGE_OPERATORS.includes(defaultValue.operator)) {
        errors.push(`${label}: default operator must be one of ${DATE_RANGE_OPERATORS.join(', ')}.`);
    }
    if (literal && !isRelativeDateLiteral(literal)) {
        errors.push(`${label}: default "${literal}" is not a relative date literal such as THIS_QUARTER.`);
    }
    if ((from && !ISO_DATE.test(from)) || (to && !ISO_DATE.test(to))) {
        errors.push(`${label}: default dates must use YYYY-MM-DD.`);
    } else if (from && to && from > to) {
        errors.push(`${label}: default start date must be on or before the end date.`);
    }
    if (defaultValue.operator && defaultValue.operator !== 'LITERAL' && !from && !to) {
        errors.push(`${label}: enter a default start or end date.`);
    }
    return errors;
}

/** PICKLIST / LOOKUP / USER `defaultValue { values?, token? }` (spec §5), checked as `buildFilterValue` reads it. */
function choiceDefaultErrors(filter, defaultValue, label) {
    const rawValues = defaultValue.values;
    if (rawValues !== undefined && (!Array.isArray(rawValues) || rawValues.some((value) => !cleanString(value)))) {
        return [`${label}: default values must be a list of non-empty values.`];
    }
    const errors = [];
    const values = (rawValues || []).map((value) => value.trim());
    const isUser = filter.type === 'USER';
    if (hasValue(defaultValue.token) && (!isUser || defaultValue.token !== 'ME')) {
        errors.push(`${label}: ${isUser ? 'the only default token is ME' : 'default tokens apply to User filters'}.`);
    }
    const count = values.length + (isUser && defaultValue.token === 'ME' ? 1 : 0);
    if (filterSelectionMode(filter) === 'single' && count > 1) {
        errors.push(`${label}: a single-select filter can default to only one value.`);
    }
    if (filter.type === 'PICKLIST' && filterOptionsSource(filter) === 'CUSTOM') {
        const options = Array.isArray(filter.options) ? filter.options.filter(isPlainObject) : [];
        const allowed = new Set(options.map((option) => cleanString(option.value)));
        values
            .filter((value) => !allowed.has(value))
            .forEach((value) => errors.push(`${label}: default "${value}" is not one of the custom options.`));
    }
    if (filter.type === 'LOOKUP' || isUser) {
        values
            .filter((value) => !RECORD_ID.test(value))
            .forEach((value) => errors.push(`${label}: default "${value}" is not a 15- or 18-character record Id.`));
    }
    return errors;
}

function defaultValueErrors(filter, label) {
    const defaultValue = filter.defaultValue;
    if (defaultValue === undefined || defaultValue === null) {
        return [];
    }
    if (!isPlainObject(defaultValue)) {
        return [`${label}: the default value must be an object.`];
    }
    switch (filter.type) {
        case 'PICKLIST':
        case 'LOOKUP':
        case 'USER':
            return choiceDefaultErrors(filter, defaultValue, label);
        case 'DATE_RANGE':
            return dateDefaultErrors(defaultValue, label);
        case 'TEXT':
            return hasValue(defaultValue.text) && typeof defaultValue.text !== 'string'
                ? [`${label}: the default search text must be text.`]
                : [];
        default:
            return [];
    }
}

function filterDefinitionErrors(filter, index, seenIds) {
    const label = filterLabel(filter, index);
    if (!isPlainObject(filter)) {
        return [`${label} must be an object.`];
    }
    const errors = [];
    const filterId = cleanString(filter.filterId);
    if (!filterId) {
        errors.push(`${label}: enter a filterId.`);
    } else if (!FILTER_ID.test(filterId)) {
        errors.push(`${label}: filterId "${filterId}" must start with a letter and use only letters, digits, or _.`);
    } else if (seenIds.has(filterId)) {
        errors.push(`${label}: filterId "${filterId}" is already used by another filter.`);
    }
    if (filterId && !seenIds.has(filterId)) {
        seenIds.set(filterId, filter.type);
    }
    switch (filter.type) {
        case 'PICKLIST':
            if (filterOptionsSource(filter) === 'CUSTOM') {
                const options = Array.isArray(filter.options) ? filter.options : [];
                const values = options.map((option) => (isPlainObject(option) ? cleanString(option.value) : null));
                if (!values.length) {
                    errors.push(`${label}: add at least one custom option.`);
                } else if (values.some((value) => !value)) {
                    errors.push(`${label}: every custom option needs a value.`);
                } else if (new Set(values).size !== values.length) {
                    errors.push(`${label}: custom option values must be unique.`);
                }
            } else {
                if (!cleanString(filter.sourceObjectApiName)) {
                    errors.push(`${label}: choose the object whose picklist supplies the options.`);
                }
                if (!cleanString(filter.fieldApiName)) {
                    errors.push(`${label}: choose the picklist field that supplies the options.`);
                }
            }
            break;
        case 'LOOKUP':
            if (!cleanString(filter.targetObjectApiName)) {
                errors.push(`${label}: choose the lookup target object.`);
            }
            break;
        case 'TEXT':
            if (hasValue(filter.matchMode) && !TEXT_MATCH_MODES.includes(filter.matchMode)) {
                errors.push(`${label}: match mode must be SOSL, CONTAINS, or STARTS_WITH.`);
            }
            // Mirrors BoardQueryService.MIN_SEARCH_CHARACTERS: the server never searches shorter terms.
            if (hasValue(filter.minCharacters) && !isIntegerInRange(filter.minCharacters, MIN_SEARCH_CHARACTERS, 50)) {
                errors.push(`${label}: minimum characters must be a whole number from ${MIN_SEARCH_CHARACTERS} to 50.`);
            }
            break;
        case 'USER':
        case 'DATE_RANGE':
            break;
        default:
            errors.push(`${label}: choose a filter type (${FILTER_TYPES.join(', ')}).`);
            return errors;
    }
    errors.push(...defaultValueErrors(filter, label));
    if (cleanString(filter.fieldApiName) && !isParentFieldPath(filter.fieldApiName)) {
        errors.push(`${label}: field API name "${filter.fieldApiName}" is not a valid field.`);
    }
    return errors;
}

function recordContextErrors(recordContext, filterTypes) {
    if (recordContext === undefined || recordContext === null) {
        return [];
    }
    if (!isPlainObject(recordContext) || !RECORD_CONTEXT_MODES.includes(recordContext.mode || 'IMPLICIT')) {
        return [error('recordContext', `Record context mode must be one of ${RECORD_CONTEXT_MODES.join(', ')}.`)];
    }
    const errors = [];
    const overrideFilterId = cleanString(recordContext.overrideFilterId);
    if (overrideFilterId && !filterTypes.has(overrideFilterId)) {
        errors.push(error('recordContext', `Record context override filter "${overrideFilterId}" does not exist.`));
    } else if (overrideFilterId && !RECORD_CONTEXT_OVERRIDE_TYPES.includes(filterTypes.get(overrideFilterId))) {
        errors.push(
            error(
                'recordContext',
                `Record context override filter "${overrideFilterId}" must be a Picklist, Lookup, or User filter.`
            )
        );
    }
    const overrideFieldPath = cleanString(recordContext.overrideFieldPath);
    if (overrideFieldPath && !isParentFieldPath(overrideFieldPath)) {
        errors.push(
            error(
                'recordContext',
                `Record context field path "${overrideFieldPath}" must be a field or 1–5 hop parent path.`
            )
        );
    }
    return errors;
}

/** Filter widget design-time errors: filter definitions, the recordContext override, and persistence. */
export function validateFilterConfig(config) {
    const errors = [];
    if (hasValue(config.filters) && !Array.isArray(config.filters)) {
        errors.push(error('filters', 'Filters must be a list.'));
    }
    const filters = Array.isArray(config.filters) ? config.filters : [];
    const filterTypes = new Map();
    filters.forEach((filter, index) => {
        filterDefinitionErrors(filter, index, filterTypes).forEach((message) => errors.push(error('filters', message)));
    });
    errors.push(...recordContextErrors(config.recordContext, filterTypes));
    if (hasValue(config.persistence) && !PERSISTENCE_MODES.includes(config.persistence)) {
        errors.push(error('persistence', `Persistence must be one of ${PERSISTENCE_MODES.join(', ')}.`));
    }
    return errors;
}

/** Metric widget design-time errors. */
export function validateMetricConfig(config) {
    const errors = aggregateErrors(config, 'Metric', false);
    const thresholds = config.thresholds;
    if (hasValue(thresholds) && !Array.isArray(thresholds)) {
        errors.push(error('thresholds', 'Thresholds must be a list.'));
    } else {
        (thresholds || []).forEach((rule, index) => {
            const label = `Threshold ${index + 1}`;
            if (!isPlainObject(rule) || !THRESHOLD_OPERATORS.includes(rule.operator)) {
                errors.push(error('thresholds', `${label}: choose an operator.`));
                return;
            }
            if (typeof rule.value !== 'number' || !Number.isFinite(rule.value)) {
                errors.push(error('thresholds', `${label}: enter a numeric value.`));
            }
            if (!THRESHOLD_VARIANTS.includes(rule.variant)) {
                errors.push(error('thresholds', `${label}: choose a status (success, warning, or error).`));
            }
        });
    }
    errors.push(...formatErrors(config.format, 'format', 'Value format'));
    return errors;
}

/** Bar Chart widget design-time errors. */
export function validateBarConfig(config) {
    const errors = [];
    if (hasValue(config.orientation) && !ORIENTATIONS.includes(config.orientation)) {
        errors.push(error('orientation', 'Orientation must be vertical or horizontal.'));
    }
    const groupByField = cleanString(config.groupByField);
    if (!groupByField) {
        errors.push(error('groupByField', 'Choose a Group by field.'));
    } else if (!isParentFieldPath(groupByField)) {
        errors.push(error('groupByField', `Group by field "${groupByField}" must be a field or 1–5 hop parent path.`));
    }
    if (hasValue(config.dateGranularity) && !DATE_GRANULARITIES.includes(config.dateGranularity)) {
        errors.push(error('dateGranularity', `Date granularity must be one of ${DATE_GRANULARITIES.join(', ')}.`));
    }
    const stackByField = cleanString(config.stackByField);
    if (stackByField && !isParentFieldPath(stackByField)) {
        errors.push(error('stackByField', `Stack by field "${stackByField}" must be a field or 1–5 hop parent path.`));
    } else if (stackByField && groupByField && stackByField.toLowerCase() === groupByField.toLowerCase()) {
        errors.push(error('stackByField', 'Stack by field must differ from the Group by field.'));
    }
    errors.push(...aggregateErrors(config, 'Bar Chart', true));
    if (hasValue(config.sortBy) && !BAR_SORTS.includes(config.sortBy)) {
        errors.push(error('sortBy', `Sort must be one of ${BAR_SORTS.join(', ')}.`));
    }
    if (hasValue(config.maxBars) && !isIntegerInRange(config.maxBars, 3, 50)) {
        errors.push(error('maxBars', 'Maximum bars must be a whole number from 3 to 50.'));
    }
    // One series slot is always the "Other" series, so fewer than 2 would hide every named series.
    if (hasValue(config.maxSeries) && !isIntegerInRange(config.maxSeries, 2, 6)) {
        errors.push(error('maxSeries', 'Maximum series must be a whole number from 2 to 6.'));
    }
    const fn = config.aggregateFunction || 'COUNT';
    if (config.overflowMode === 'OTHER' && !ROLLUP_FUNCTIONS.includes(fn)) {
        errors.push(error('overflowMode', `An "Other" bar is only available for COUNT and SUM, not ${fn}.`));
    }
    errors.push(...formatErrors(config.format, 'format', 'Value format'));
    return errors;
}

function columnErrors(rawColumns, key, prefix, messages) {
    if (hasValue(rawColumns) && !Array.isArray(rawColumns)) {
        return [error(key, messages.notList)];
    }
    const columns = rawColumns || [];
    const errors = [];
    if (!columns.length) {
        errors.push(error(key, messages.empty));
    }
    const ids = new Set();
    columns.forEach((column, index) => {
        const label = `${prefix} ${index + 1}`;
        if (!isPlainObject(column) || !cleanString(column.fieldPath)) {
            errors.push(error(key, `${label}: choose a field.`));
            return;
        }
        if (!isParentFieldPath(column.fieldPath)) {
            errors.push(error(key, `${label}: "${column.fieldPath}" must be a field or 1–5 hop parent path.`));
        }
        const id = cleanString(column.id) || column.fieldPath;
        if (ids.has(id)) {
            errors.push(error(key, `${label}: duplicate column id "${id}".`));
        }
        ids.add(id);
        errors.push(...formatErrors(column.format, key, `${label} format`));
    });
    return errors;
}

/** Table widget design-time errors: columns, page size, and the optional childRelationship. */
export function validateTableConfig(config) {
    const errors = columnErrors(config.columns, 'columns', 'Column', {
        notList: 'Columns must be a list.',
        empty: 'Add at least one column.'
    });
    if (cleanString(config.sortBy) && !isParentFieldPath(config.sortBy)) {
        errors.push(error('sortBy', `Default sort "${config.sortBy}" must be a field or 1–5 hop parent path.`));
    }
    if (hasValue(config.pageSize) && !isIntegerInRange(config.pageSize, 10, 100)) {
        errors.push(error('pageSize', 'Page size must be a whole number from 10 to 100.'));
    }
    const child = config.childRelationship;
    if (hasValue(child)) {
        if (!isPlainObject(child)) {
            errors.push(error('childRelationship', 'Child records must be an object.'));
            return errors;
        }
        if (!cleanString(child.childObjectApiName) || !cleanString(child.foreignKeyField)) {
            errors.push(error('childRelationship', 'Child records: choose a child relationship.'));
        }
        errors.push(
            ...columnErrors(child.columns, 'childRelationship', 'Child column', {
                notList: 'Child records: columns must be a list.',
                empty: 'Child records: add at least one child column.'
            })
        );
        if (cleanString(child.sortBy) && !isParentFieldPath(child.sortBy)) {
            errors.push(
                error('childRelationship', `Child records: sort "${child.sortBy}" must be a field or parent path.`)
            );
        }
        if (hasValue(child.limit) && !isIntegerInRange(child.limit, 1, 50)) {
            errors.push(error('childRelationship', 'Child records: limit must be a whole number from 1 to 50.'));
        }
    }
    return errors;
}

// ---- Widget specs and the config envelope --------------------------------------------------------------------------

const BASE_KEYS = ['boardId', 'title'];
const DATA_KEYS = [...BASE_KEYS, 'objectApiName'];

/** Per widget type: data widget (object, bindings, base filters), dual-written top-level keys, widget rules. */
const WIDGET_SPECS = {
    filter: { dataWidget: false, topLevelKeys: BASE_KEYS, validate: validateFilterConfig },
    metric: { dataWidget: true, topLevelKeys: DATA_KEYS, validate: validateMetricConfig },
    bar: { dataWidget: true, topLevelKeys: [...DATA_KEYS, 'orientation'], validate: validateBarConfig },
    table: { dataWidget: true, topLevelKeys: DATA_KEYS, validate: validateTableConfig }
};
export const WIDGET_TYPES = Object.keys(WIDGET_SPECS);

function specFor(widgetType) {
    return WIDGET_SPECS[widgetType] || WIDGET_SPECS.metric;
}

export function isDataWidget(widgetType) {
    return specFor(widgetType).dataWidget;
}

/** Top-level `@api` properties the CPE dual-writes to both the component property and `configJson`. */
export function topLevelKeysFor(widgetType) {
    return specFor(widgetType).topLevelKeys;
}

/** Canonical key order: `version`, `widgetType`, top-level keys, then the rest. */
export function orderConfig(widgetType, raw) {
    const source = isPlainObject(raw) ? raw : {};
    const ordered = { version: 1, widgetType };
    const topLevelKeys = topLevelKeysFor(widgetType);
    topLevelKeys.forEach((key) => {
        if (hasValue(source[key])) {
            ordered[key] = source[key];
        }
    });
    Object.keys(source).forEach((key) => {
        if (!(key in ordered) && !topLevelKeys.includes(key) && source[key] !== undefined) {
            ordered[key] = source[key];
        }
    });
    return ordered;
}

export function serializeConfig(widgetType, config) {
    return JSON.stringify(orderConfig(widgetType, config));
}

export function formatConfig(widgetType, config) {
    return JSON.stringify(orderConfig(widgetType, config), null, 2);
}

function findVariable(inputVariables, name) {
    return (Array.isArray(inputVariables) ? inputVariables : []).find((variable) => variable && variable.name === name);
}

/**
 * Reads the CPE config from Flow `inputVariables`: `configJson` merged with non-empty top-level literals (top-level
 * wins, matching runtime precedence). Top-level values bound to Flow resources (`valueDataType: 'reference'`) are
 * returned in `references` and never copied into `configJson`.
 */
export function readCpeState(widgetType, inputVariables) {
    const rawJson = findVariable(inputVariables, 'configJson');
    let parsed = {};
    let storedJsonError = null;
    const text = rawJson && typeof rawJson.value === 'string' ? rawJson.value.trim() : '';
    if (text) {
        try {
            const value = JSON.parse(text);
            if (isPlainObject(value)) {
                parsed = value;
            } else {
                storedJsonError = 'Saved configJson is not a JSON object.';
            }
        } catch (err) {
            storedJsonError = 'Saved configJson is malformed JSON.';
        }
    }

    const config = orderConfig(widgetType, parsed);
    const references = {};
    topLevelKeysFor(widgetType).forEach((key) => {
        const variable = findVariable(inputVariables, key);
        if (!variable) {
            return;
        }
        if (variable.valueDataType === 'reference') {
            references[key] = variable.value;
            return;
        }
        const value = cleanString(variable.value);
        if (value) {
            config[key] = value;
        }
    });
    return { config: orderConfig(widgetType, config), storedJsonError, references };
}

/** First problem with a Base filter condition, or null when it compiles. */
export function baseFilterError(condition) {
    if (!isPlainObject(condition)) {
        return 'Each base filter must be an object.';
    }
    if (!cleanString(condition.fieldPath)) {
        return 'Choose a field.';
    }
    if (!isValidFieldPath(condition.fieldPath)) {
        return `Invalid field path "${condition.fieldPath}".`;
    }
    const operator = condition.operator;
    if (!BASE_FILTER_OPERATORS.includes(operator)) {
        return 'Choose an operator.';
    }
    const value = condition.value;
    if (LIST_OPERATORS.has(operator)) {
        const values = Array.isArray(value) ? value : [value];
        if (!values.some((item) => hasValue(item) && String(item).trim() !== '')) {
            return 'Enter at least one value.';
        }
    } else if (operator === 'LITERAL') {
        if (!isRelativeDateLiteral(value)) {
            return 'Choose a relative date literal such as TODAY or THIS_QUARTER.';
        }
    } else if (VALUE_REQUIRED_OPERATORS.has(operator)) {
        if (!hasValue(value) || String(value).trim() === '') {
            return 'Enter a value.';
        }
    }
    return null;
}

function bindingErrors(bindings) {
    if (bindings === undefined || bindings === null) {
        return [];
    }
    if (!isPlainObject(bindings)) {
        return [error('filterBindings', 'Filter bindings must be an object keyed by filterId.')];
    }
    return Object.keys(bindings)
        .filter((filterId) => !isValidBindingPath(bindings[filterId]))
        .map((filterId) => error('filterBindings', `Filter binding "${filterId}" is invalid. ${BINDING_PATH_HELP}`));
}

function baseFilterErrors(baseFilters) {
    if (baseFilters === undefined || baseFilters === null) {
        return [];
    }
    if (!Array.isArray(baseFilters)) {
        return [error('baseFilters', 'Base filters must be a list.')];
    }
    const errors = [];
    const ids = new Set();
    baseFilters.forEach((condition, index) => {
        const label = `Base filter ${index + 1}`;
        const problem = baseFilterError(condition);
        if (problem) {
            errors.push(error('baseFilters', `${label}: ${problem}`));
        }
        const id = isPlainObject(condition) ? cleanString(condition.id) : null;
        if (isPlainObject(condition) && !id) {
            errors.push(error('baseFilters', `${label}: id is required.`));
        } else if (id && ids.has(id)) {
            errors.push(error('baseFilters', `${label}: duplicate id "${id}".`));
        }
        ids.add(id);
    });
    return errors;
}

/**
 * Design-time errors of a config envelope (`[{ key, errorString }]`): the rules behind both `validate()` and pasted
 * Config JSON. `references` holds top-level keys bound to Flow resources (they satisfy required values).
 */
export function configErrors(widgetType, config, references = {}) {
    const spec = specFor(widgetType);
    const errors = [];
    STRING_KEYS.forEach((key) => {
        if (hasValue(config[key]) && typeof config[key] !== 'string') {
            errors.push(error(key, `${key} must be text.`));
        }
    });
    if (spec.dataWidget) {
        if (!cleanString(config.objectApiName) && !references.objectApiName) {
            errors.push(error('objectApiName', 'Select an object.'));
        }
        errors.push(...bindingErrors(config.filterBindings), ...baseFilterErrors(config.baseFilters));
    }
    errors.push(...spec.validate(config));
    return errors;
}

/**
 * Parses pasted `configJson` text and checks it with the same rules as `validate()` (`configErrors`).
 * @returns {{ config: object|null, errors: string[] }}
 */
export function validateConfigText(widgetType, text, references = {}) {
    if (typeof text !== 'string' || !text.trim()) {
        return { config: null, errors: ['Paste a configJson object.'] };
    }
    let parsed;
    try {
        parsed = JSON.parse(text);
    } catch (err) {
        return { config: null, errors: [`Malformed JSON: ${err.message}`] };
    }
    if (!isPlainObject(parsed)) {
        return { config: null, errors: ['Root value must be a JSON object.'] };
    }
    const errors = [];
    if (parsed.version !== undefined && parsed.version !== 1) {
        errors.push('version must be 1.');
    }
    if (parsed.widgetType !== undefined && parsed.widgetType !== widgetType) {
        errors.push(`widgetType must be "${widgetType}".`);
    }
    errors.push(...configErrors(widgetType, parsed, references).map((item) => item.errorString));
    return { config: errors.length ? null : orderConfig(widgetType, parsed), errors };
}

/**
 * `validate()` of an exposed CPE: the mounted shell's errors, or (fail-closed, before the shell renders) the errors
 * of the config read straight from Flow `inputVariables`.
 */
export function validateCpe(shell, widgetType, inputVariables) {
    if (shell) {
        return shell.validate();
    }
    const state = readCpeState(widgetType, inputVariables);
    const stored = state.storedJsonError ? [error('configJson', state.storedJsonError)] : [];
    return [...stored, ...configErrors(widgetType, state.config, state.references)];
}

// ---- Config dialog ---------------------------------------------------------------------------------------------

export const DIALOG_SAVE = 'save';
export const DIALOG_DISMISS = 'dismiss';

/**
 * Opens a Config dialog (a `LightningModal` subclass such as `c/boardCpeConfigDialog`) at size large with a deep copy
 * of `value`, and resolves with `{ action: 'save', draft }` or `{ action: 'dismiss' }` (Cancel, header X, Escape).
 * The caller applies a saved draft as exactly one config change and does nothing on dismiss.
 */
export async function openConfigDialog(Dialog, { value, ...props } = {}) {
    const result = await Dialog.open({
        ...props,
        size: 'large',
        value: value === undefined ? undefined : JSON.parse(JSON.stringify(value))
    });
    return result && result.action === DIALOG_SAVE
        ? { action: DIALOG_SAVE, draft: result.draft }
        : { action: DIALOG_DISMISS };
}