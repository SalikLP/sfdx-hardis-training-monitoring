/**
 * Shared service module of the Board Flow Custom Property Editors (`c-board-cpe-common` and the four widget CPEs):
 * enum option lists, field path / binding / relative date grammar, memoized describe loaders, filterId derivation,
 * the versioned config envelope (`readCpeState`, ordering, serialization), and the design-time rules shared by
 * `validate()` and pasted Config JSON (`configErrors`).
 */
import getQueryableObjects from '@salesforce/apex/BoardSchemaService.getQueryableObjects';
import getObjectFields from '@salesforce/apex/BoardSchemaService.getObjectFields';
import getChildRelationships from '@salesforce/apex/BoardSchemaService.getChildRelationships';
import getScreenFlows from '@salesforce/apex/BoardSchemaService.getScreenFlows';
import { gaugeConfigProblems } from 'c/boardMetricGauge';
import { CHART_TYPE_OPTIONS, chartTypeIsSingleMeasure, isChartType, maxCategoriesFor } from 'c/boardChartUtils';
import {
    DATE_PRESETS,
    DATE_RANGE_OPERATORS,
    EMPTY_FILLED_OPERATORS,
    FILTER_TYPES,
    IGNORE_BINDING,
    RECORD_CONTEXT_OVERRIDE_TYPES,
    CHILD_ROWS_REMOVED_MESSAGE,
    CURRENCY_PICKER_ITEM,
    isCurrencyPickerItem,
    metricMeasures,
    normalizeConfigSpelling
} from 'c/boardConfigUtils';
import { bucketFieldErrors, bucketIdOf, findBucketField, unknownBucketFieldMessage } from 'c/boardBucketFields';
import { fixedColourErrors } from 'c/boardChartColours';
import { crossObjectMeasureErrors } from 'c/boardCrossObjectMeasure';
import { MAX_PANEL_CATEGORIES, hasPanelField, smallMultiplesErrors } from 'c/boardChartPanels';

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
/**
 * Aggregates of a Measures list (Chart and Metric widgets): the plain aggregates, Average per record (`AVG_PER`: one
 * value per record of a per-record lookup) and a Formula measure.
 */
export const MEASURE_AGGREGATE_OPTIONS = [
    ...AGGREGATE_OPTIONS,
    { label: 'Average per record', value: 'AVG_PER' },
    { label: 'Formula (over the other Measures)', value: 'FORMULA' }
];
const MEASURE_AGGREGATE_FUNCTIONS = optionValues(MEASURE_AGGREGATE_OPTIONS);
const FORMULA = 'FORMULA';
export const FORMULA_SLOTS = ['A', 'B', 'C', 'D', 'E', 'F'];
/** The error of a Chart config still carrying the single aggregate of the old Bar widget (retired). */
export const MEASURES_REPLACED_MESSAGE = 'aggregateFunction and valueFieldApiName were replaced by the Measures list.';
const FORMULA_SERIES_ERROR =
    "A Formula measure can't be used with a series field. Remove the Stack by field or the Formula measure.";
/** String literals (skipped) or identifiers not called as a function. */
const FORMULA_TOKEN = /("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|(?<![\w$.])([A-Za-z_]\w*)(?!\w|\s*\()/g;
/** How an Average per record Measure takes each record's value (`inner`). */
export const PER_RECORD_INNER_OPTIONS = [
    { label: 'Sum of its rows (e.g. deal size)', value: 'SUM' },
    { label: 'Same on every row, counted once (e.g. days to close)', value: 'ONCE' }
];
const PER_RECORD_INNERS = optionValues(PER_RECORD_INNER_OPTIONS);
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
    NUMBER_RANGE: 'Number range',
    TEXT: 'Text search',
    EMPTY_FILLED: 'Empty / Filled in',
    BUCKET: 'Bucket',
    // Items in the Filter definitions list that are not filter types.
    section: 'Section',
    [CURRENCY_PICKER_ITEM]: 'Currency picker'
};
export const FILTER_TYPE_OPTIONS = FILTER_TYPES.map((type) => ({ label: FILTER_TYPE_LABELS[type], value: type }));
export const TEXT_MATCH_MODE_OPTIONS = [
    { label: 'Search all text fields (SOSL)', value: 'SOSL' },
    { label: 'Field contains', value: 'CONTAINS' },
    { label: 'Field starts with', value: 'STARTS_WITH' }
];
const TEXT_MATCH_MODES = optionValues(TEXT_MATCH_MODE_OPTIONS);
/** User filter `matchMode`: the picked users only, or each picked user's Team. */
export const USER_MATCH_MODE_OPTIONS = [
    { label: 'Selected users', value: 'users' },
    { label: 'Selected users and their team', value: 'usersAndTeam' }
];
const USER_MATCH_MODES = optionValues(USER_MATCH_MODE_OPTIONS);
export const RECORD_CONTEXT_MODE_OPTIONS = [
    { label: 'Implicit: Widgets show data related to the record', value: 'IMPLICIT' },
    { label: "Locked: the record fills a filter viewers can't change", value: 'LOCKED' },
    { label: 'Default: the record pre-fills a filter viewers can change', value: 'DEFAULT' }
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
/** A plain number as the Number range filter reads it (mirrors `filterPersistence` NUMBER_PATTERN). */
const PLAIN_NUMBER = /^-?\d+(?:\.\d+)?$/;
const FILTER_ID = /^[A-Za-z][A-Za-z0-9_]*$/;
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

/** True for a non-blank string, or any other value that is not null/undefined. */
export function hasText(value) {
    return typeof value === 'string' ? value.trim() !== '' : value !== null && value !== undefined;
}

/** Deep copy of a JSON-compatible value (undefined stays undefined). */
export function deepCopy(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
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

const MAX_RELATIONSHIP_HOPS = 5;
const CHILD_PREFIX = new RegExp(`^${IDENT}\\(${IDENT}\\)\\.`);

/**
 * Config-time error for an Include team binding (User filter in `usersAndTeam` mode): the Team condition reaches
 * `<path>.UserRoleId`, one relationship hop past the bound path (counted inside a child semi-join), and SOQL allows
 * at most 5. Null when the path is within the limit or isn't a single field path.
 */
export function teamBindingHopError(filterId, path) {
    if (!isValidFieldPath(path)) {
        return null;
    }
    const trimmed = path.trim();
    const hops = trimmed.replace(CHILD_PREFIX, '').split('.').length;
    if (hops <= MAX_RELATIONSHIP_HOPS) {
        return null;
    }
    return `Filter binding "${filterId}": Include team needs ${trimmed}.UserRoleId, which exceeds the ${MAX_RELATIONSHIP_HOPS}-hop limit. Bind the filter to a shorter user-lookup path.`;
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

function stopEvent(event) {
    event.stopPropagation();
}

/**
 * Keeps the `change` events of the base components inside `component` from reaching its host. `lightning-input`,
 * `lightning-combobox` and the like fire `change` bubbling and composed, so a keystroke inside an editor would
 * otherwise also arrive at the parent's `onchange` on the editor, looking like the editor's own `change` with the
 * wrong detail. Call from `connectedCallback`; the component's own `change`, fired on its host, is not affected.
 */
export function containInnerChanges(component) {
    component.template.addEventListener('change', stopEvent);
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

// ---- Drag to reorder (shared by every ordered CPE list) ------------------------------------------------------------
//
// Pattern: each row has a handle (`draggable="true"`, `data-index`, `ondragstart` / `ondragend`); the row itself is the
// drop target (`data-index`, `ondragover` / `ondrop`). The component keeps the state in one field it reassigns
// (`drag = NO_DRAG`) so re-renders are reactive, and adds `dragRowClass(drag, index)` to each row's class.
// Styles: `@import 'c/boardCpeDragStyles';`. Up/down buttons stay as the keyboard-accessible alternative.

/** Idle drag state: `{ from, over }` are row indexes, or null. */
export const NO_DRAG = Object.freeze({ from: null, over: null });

/** `dragstart` on a row handle: starts a move of that row, using the whole row as the drag image. */
export function startRowDrag(event) {
    const from = Number(event.currentTarget.dataset.index);
    const { dataTransfer } = event;
    if (dataTransfer) {
        dataTransfer.effectAllowed = 'move';
        dataTransfer.setData('text/plain', String(from));
        const row = event.currentTarget.closest('li');
        if (row && typeof dataTransfer.setDragImage === 'function') {
            dataTransfer.setDragImage(row, 0, 0);
        }
    }
    return { from, over: null };
}

/** `dragover` on a row: accepts the drop while a row of this list is being dragged; returns the next state. */
export function overRowDrag(event, drag) {
    if (drag.from === null) {
        return drag;
    }
    event.preventDefault();
    if (event.dataTransfer) {
        event.dataTransfer.dropEffect = 'move';
    }
    const over = Number(event.currentTarget.dataset.index);
    return over === drag.over ? drag : { from: drag.from, over };
}

/** `drop` on a row: the `{ index, offset }` move to apply (see `moveItem`), or null when nothing moves. */
export function dropRowDrag(event, drag) {
    if (drag.from === null) {
        return null;
    }
    event.preventDefault();
    const offset = Number(event.currentTarget.dataset.index) - drag.from;
    return offset ? { index: drag.from, offset } : null;
}

/** Extra row classes: the dragged row is dimmed; the hovered row shows a marker on the side the row will land. */
export function dragRowClass(drag, index) {
    if (drag.from === null) {
        return '';
    }
    if (index === drag.from) {
        return ' c-drag-source';
    }
    if (index === drag.over) {
        return index < drag.from ? ' c-drop-before' : ' c-drop-after';
    }
    return '';
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

let screenFlowsPromise = null;

/** `BoardSchemaService.getScreenFlows`: the org's active Screen Flows (`[{ apiName, label }]`), shared by pickers. */
export function loadScreenFlows() {
    if (!screenFlowsPromise) {
        screenFlowsPromise = getScreenFlows().catch((err) => {
            screenFlowsPromise = null;
            throw err;
        });
    }
    return screenFlowsPromise;
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
        return filter.selectionMode === 'single' || filter.display === 'buttons' ? 'single' : 'multi';
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

/** NUMBER_RANGE `defaultValue { from?, to? }`: plain numbers (no grouping separators), min not above max. */
function numberDefaultErrors(defaultValue, label) {
    const bounds = [defaultValue.from, defaultValue.to].map((bound) => String(bound ?? '').trim());
    if (bounds.some((bound) => bound && !PLAIN_NUMBER.test(bound))) {
        return [`${label}: the default minimum and maximum must be plain numbers such as 5000 or 12.5.`];
    }
    const [from, to] = bounds;
    return from && to && Number(from) > Number(to)
        ? [`${label}: the default minimum must not be more than the default maximum.`]
        : [];
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
        case 'NUMBER_RANGE':
            return numberDefaultErrors(defaultValue, label);
        case 'EMPTY_FILLED':
            return hasValue(defaultValue.operator) && !EMPTY_FILLED_OPERATORS.includes(defaultValue.operator)
                ? [`${label}: the default must be ${EMPTY_FILLED_OPERATORS.join(' or ')} (or none for All).`]
                : [];
        case 'TEXT':
            return hasValue(defaultValue.text) && typeof defaultValue.text !== 'string'
                ? [`${label}: the default search text must be text.`]
                : [];
        default:
            return [];
    }
}

/** A Section item (`{ type: 'section', label, startCollapsed }`) only needs a heading. */
function sectionHeadingErrors(section, index) {
    return cleanString(section.label) ? [] : [`Section ${index + 1}: enter a heading.`];
}

function filterDefinitionErrors(filter, index, seenIds, bucketFields) {
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
        case 'EMPTY_FILLED':
            if (!cleanString(filter.fieldApiName)) {
                errors.push(`${label}: choose the field to check.`);
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
            if (hasValue(filter.matchMode) && !USER_MATCH_MODES.includes(filter.matchMode)) {
                errors.push(`${label}: match mode must be users or usersAndTeam.`);
            }
            break;
        case 'DATE_RANGE':
            break;
        case 'NUMBER_RANGE':
            if (!cleanString(filter.fieldApiName)) {
                errors.push(`${label}: choose the number or currency field.`);
            }
            break;
        case 'BUCKET': {
            const bucketFieldId = cleanString(filter.bucketFieldId);
            if (!bucketFieldId) {
                errors.push(`${label}: choose the Bucket field.`);
            } else if (Array.isArray(bucketFields) && !findBucketField(bucketFields, bucketFieldId)) {
                errors.push(
                    `${label}: Bucket field "${bucketFieldId}" is not defined. Choose one of the Bucket fields.`
                );
            }
            break;
        }
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

/**
 * Problems of a Filter widget's `recordContext` (`[{ key: 'recordContext', errorString }]`) given the filterId → type
 * map of its valid filters (`validateFilterDefinitions(filters).filterTypes`). Shared by `validateFilterConfig` and
 * the Setup dialog's Filters step.
 */
export function recordContextErrors(recordContext, filterTypes) {
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
    // Without a field path the filter receives the record Id, which is never one of a Picklist filter's values.
    const feedsRecordId = !overrideFieldPath || overrideFieldPath === 'Id';
    if (feedsRecordId && filterTypes.get(overrideFilterId) === 'PICKLIST') {
        errors.push(
            error(
                'recordContext',
                `Record context: Picklist filter "${overrideFilterId}" needs a host record field path (e.g. Industry), because a record Id is never a picklist value.`
            )
        );
    }
    return errors;
}

/**
 * Problems of each filter definition, in list order (`[[message, …], …]`; an empty list means the filter is valid),
 * plus the filterId → type map of the valid ids. A repeated filterId flags the later filter. The rules behind the
 * Filter widget's `validate()` and the Filters step of its Setup dialog (master list error flags). With the
 * Filter widget's `bucketFields`, a Bucket filter must name one of them.
 */
export function validateFilterDefinitions(filters, bucketFields = null) {
    const filterTypes = new Map();
    const byIndex = (Array.isArray(filters) ? filters : []).map((filter, index) => {
        if (isPlainObject(filter) && filter.type === 'section') {
            return sectionHeadingErrors(filter, index);
        }
        if (isCurrencyPickerItem(filter)) {
            const isFirst = filters.findIndex(isCurrencyPickerItem) === index;
            return isFirst ? [] : ['A Filter widget can have only one Currency picker. Remove this one.'];
        }
        return filterDefinitionErrors(filter, index, filterTypes, bucketFields);
    });
    return { byIndex, filterTypes };
}

/**
 * `{ mode, overrideFilterId?, overrideFieldPath? }` of a Filter widget, or null for the default (IMPLICIT without
 * overrides), so an untouched Record context stays out of the config.
 */
export function compactRecordContext(recordContext) {
    const source = isPlainObject(recordContext) ? recordContext : {};
    const next = applyPatch(
        { mode: source.mode || 'IMPLICIT' },
        {
            overrideFilterId: cleanString(source.overrideFilterId),
            overrideFieldPath: cleanString(source.overrideFieldPath)
        }
    );
    return next.mode === 'IMPLICIT' && Object.keys(next).length === 1 ? null : next;
}

/** Filter widget design-time errors: filter definitions, the recordContext override, and persistence. */
export function validateFilterConfig(config) {
    const errors = [];
    if (hasValue(config.filters) && !Array.isArray(config.filters)) {
        errors.push(error('filters', 'Filters must be a list.'));
    }
    const { byIndex, filterTypes } = validateFilterDefinitions(
        config.filters,
        Array.isArray(config.bucketFields) ? config.bucketFields : []
    );
    byIndex.forEach((messages) => messages.forEach((message) => errors.push(error('filters', message))));
    errors.push(...recordContextErrors(config.recordContext, filterTypes));
    if (hasValue(config.persistence) && !PERSISTENCE_MODES.includes(config.persistence)) {
        errors.push(error('persistence', `Persistence must be one of ${PERSISTENCE_MODES.join(', ')}.`));
    }
    // Board-level Bucket fields: the same rules as a Widget's own.
    errors.push(
        ...bucketFieldErrors(config.bucketFields, baseFilterError).map((message) => error('bucketFields', message))
    );
    return errors;
}

/** Max Measures of one Metric widget. */
export const MAX_METRIC_MEASURES = 6;

/**
 * Metric widget design-time errors. A Measures list needs exactly one visible Measure; a config without one is a
 * single-aggregate Metric (`aggregateFunction`, `valueFieldApiName`, `format`), checked as before.
 */
export function validateMetricConfig(config) {
    const errors = hasValue(config.measures)
        ? metricMeasureErrors(config)
        : [...aggregateErrors(config, 'Metric', false), ...formatErrors(config.format, 'format', 'Value format')];
    gaugeConfigProblems(config, metricMeasures(config)).forEach((message) =>
        errors.push(error(message.startsWith('Display') ? 'display' : 'gauge', message))
    );
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
    return errors;
}

function metricMeasureErrors(config) {
    const errors = measureListErrors(config, 'Metric', MAX_METRIC_MEASURES);
    if (!Array.isArray(config.measures) || !config.measures.length) {
        return errors;
    }
    const visible = config.measures.filter((measure) => isPlainObject(measure) && measure.hidden !== true).length;
    if (visible === 0) {
        errors.push(
            error('measures', 'A Metric widget shows exactly one Measure: every Measure is Hidden. Show one of them.')
        );
    } else if (visible > 1) {
        errors.push(
            error(
                'measures',
                `A Metric widget shows exactly one Measure: ${visible} Measures are visible. Mark the others Hidden.`
            )
        );
    }
    errors.push(...crossObjectMeasureErrors(config, 'metric').map((message) => error('measures', message)));
    return errors;
}

/**
 * Chart widget design-time errors; max categories depends on the chart type. `context.boardBucketFields`: the
 * Board-level Bucket fields (of the Board's Filter widget) a `bucket:<id>` reference may also name.
 */
export function validateChartConfig(config, context = {}) {
    const errors = [];
    if (hasValue(config.chartType) && !isChartType(config.chartType)) {
        const types = CHART_TYPE_OPTIONS.map((option) => option.value).join(', ');
        errors.push(error('chartType', `Chart type must be one of ${types}.`));
    }
    if (hasValue(config.orientation) && !ORIENTATIONS.includes(config.orientation)) {
        errors.push(error('orientation', 'Orientation must be vertical or horizontal.'));
    }
    const groupByField = cleanString(config.groupByField);
    if (!groupByField) {
        errors.push(error('groupByField', 'Choose a Group by field.'));
    } else if (bucketIdOf(groupByField) !== null) {
        errors.push(...bucketReferenceErrors(config, 'groupByField', 'Group by', context));
    } else if (!isParentFieldPath(groupByField)) {
        errors.push(error('groupByField', `Group by field "${groupByField}" must be a field or 1–5 hop parent path.`));
    }
    if (hasValue(config.dateGranularity) && !DATE_GRANULARITIES.includes(config.dateGranularity)) {
        errors.push(error('dateGranularity', `Date granularity must be one of ${DATE_GRANULARITIES.join(', ')}.`));
    }
    const measures = chartMeasures(config);
    const stackByField = cleanString(config.stackByField);
    const stackByBucket = stackByField && bucketIdOf(stackByField) !== null;
    if (stackByBucket && bucketReferenceErrors(config, 'stackByField', 'Stack by', context).length) {
        errors.push(...bucketReferenceErrors(config, 'stackByField', 'Stack by', context));
    } else if (stackByField && !stackByBucket && !isParentFieldPath(stackByField)) {
        errors.push(error('stackByField', `Stack by field "${stackByField}" must be a field or 1–5 hop parent path.`));
    } else if (stackByField && groupByField && stackByField.toLowerCase() === groupByField.toLowerCase()) {
        errors.push(error('stackByField', 'Stack by field must differ from the Group by field.'));
    } else if (stackByField && measures.length > 1) {
        errors.push(error('stackByField', 'Use several Measures or a Stack by field, not both.'));
    }
    errors.push(...measureListErrors(config));
    errors.push(...crossObjectMeasureErrors(config, 'chart').map((message) => error('measures', message)));
    if (chartTypeIsSingleMeasure(config.chartType)) {
        const type = config.chartType;
        if (measures.length > 1) {
            errors.push(error('measures', `A ${type} chart shows exactly one Measure.`));
        }
        if (stackByField) {
            errors.push(error('stackByField', `A ${type} chart has no Stack by field.`));
        }
    }
    if (hasValue(config.labelMode) && !['value', 'percent', 'both', 'none'].includes(config.labelMode)) {
        errors.push(error('labelMode', 'Label mode must be one of value, percent, both, none.'));
    }
    errors.push(
        ...bucketFieldErrors(config.bucketFields, baseFilterError).map((message) => error('bucketFields', message))
    );
    errors.push(...fixedColourErrors(config.fixedColours).map((message) => error('fixedColours', message)));
    if (hasValue(config.sortBy) && !BAR_SORTS.includes(config.sortBy)) {
        errors.push(error('sortBy', `Sort must be one of ${BAR_SORTS.join(', ')}.`));
    }
    // Small multiples show at most 50 categories per Panel.
    const maxCategories = hasPanelField(config)
        ? Math.min(MAX_PANEL_CATEGORIES, maxCategoriesFor(config.chartType))
        : maxCategoriesFor(config.chartType);
    const panelErrors = smallMultiplesErrors(config).map((entry) => error(entry.key, entry.message));
    if (
        bucketIdOf(cleanString(config.panelField)) !== null &&
        !panelErrors.some((entry) => entry.key === 'panelField')
    ) {
        panelErrors.unshift(...bucketReferenceErrors(config, 'panelField', 'Panel field', context));
    }
    errors.push(...panelErrors);
    if (hasValue(config.maxBars) && !isIntegerInRange(config.maxBars, 3, maxCategories)) {
        const noun = (config.chartType || 'bar') === 'bar' ? 'bars' : 'categories';
        errors.push(error('maxBars', `Maximum ${noun} must be a whole number from 3 to ${maxCategories}.`));
    }
    // One series slot is always the "Other" series, so fewer than 2 would hide every named series.
    if (hasValue(config.maxSeries) && !isIntegerInRange(config.maxSeries, 2, 12)) {
        errors.push(error('maxSeries', 'Maximum series must be a whole number from 2 to 12.'));
    }
    const otherProblem = config.overflowMode === 'OTHER' ? otherBarProblem(config) : null;
    if (otherProblem) {
        errors.push(error('overflowMode', otherProblem));
    }
    return errors;
}

/**
 * Why the Chart's Measures can't have an "Other" bar, or null when they can. "Other" merges the rolled-up rows (AVG,
 * MIN, MAX, Average per record and Formula measures included, hidden ones too), except distinct counts, which never
 * merge; Small multiples panels can only sum their "Other". The Display step offers "Other" by the same rule.
 */
export function otherBarProblem(config) {
    const functions = chartMeasures(config)
        .filter(isPlainObject)
        .map((measure) => measure.aggregateFunction || 'COUNT');
    if (functions.includes('COUNT_DISTINCT')) {
        return 'An "Other" bar is not available with COUNT_DISTINCT Measures.';
    }
    const nonAdditive = functions.find((fn) => !ROLLUP_FUNCTIONS.includes(fn));
    if (nonAdditive && hasPanelField(config)) {
        return `With Small multiples, an "Other" bar is only available for COUNT and SUM Measures, not ${nonAdditive}.`;
    }
    return null;
}

/** A group or series field `bucket:<id>` must name one of the Widget's Bucket fields or the Board's. */
function bucketReferenceErrors(config, key, label, context = {}) {
    const id = bucketIdOf(config[key]);
    return findBucketField(config.bucketFields, id) || findBucketField(context.boardBucketFields, id)
        ? []
        : [error(key, unknownBucketFieldMessage(label, id))];
}

/** Max Measures of one Chart widget. */
export const MAX_CHART_MEASURES = 6;
/**
 * Share of total modes of a Chart widget Measure (`showAs`; unset = its plain value). Only COUNT and SUM Measures add
 * up to a total; percent of category needs a series (Stack by) field or several Measures.
 */
export const SHOW_AS_OPTIONS = [
    { label: 'Value', value: 'value' },
    { label: 'Percent of total', value: 'percentOfTotal' },
    { label: 'Percent of category', value: 'percentOfCategory' }
];
const SHOW_AS_MODES = SHOW_AS_OPTIONS.map((option) => option.value);
const HEX_COLOUR = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i;

/** Measures step summary of a Widget without Measures: it counts records, the default. */
const DEFAULT_MEASURE_SUMMARY = 'Count of records (default)';

function hasDefinedMeasures(config) {
    return Array.isArray(config.measures) && config.measures.length > 0;
}

/** A Chart widget's Measures list; a config without one counts records (`[{ aggregateFunction: 'COUNT' }]`). */
export function chartMeasures(config) {
    const measures = Array.isArray(config.measures) ? config.measures : [];
    return measures.length ? measures : [{ aggregateFunction: 'COUNT' }];
}

function measureListErrors(config, widgetLabel = 'Chart', maxMeasures = MAX_CHART_MEASURES) {
    const errors = [];
    if (hasValue(config.aggregateFunction) || hasValue(config.valueFieldApiName)) {
        errors.push(error('measures', MEASURES_REPLACED_MESSAGE));
    }
    if (!hasValue(config.measures)) {
        return errors;
    }
    if (!Array.isArray(config.measures)) {
        return [...errors, error('measures', 'Measures must be a list.')];
    }
    if (!config.measures.length) {
        errors.push(error('measures', 'Add at least one Measure.'));
    }
    if (config.measures.length > maxMeasures) {
        errors.push(error('measures', `A ${widgetLabel} widget shows at most ${maxMeasures} Measures.`));
    }
    config.measures.forEach((measure, index) => {
        const label = `Measure ${index + 1}`;
        if (!isPlainObject(measure)) {
            errors.push(error('measures', `${label}: must be an object.`));
            return;
        }
        const fn = measure.aggregateFunction || 'COUNT';
        if (!MEASURE_AGGREGATE_FUNCTIONS.includes(fn)) {
            errors.push(
                error(
                    'measures',
                    `${label}: aggregate function must be one of ${MEASURE_AGGREGATE_FUNCTIONS.join(', ')}.`
                )
            );
            return;
        }
        const valueField = cleanString(measure.valueFieldApiName);
        if (fn === FORMULA) {
            errors.push(...formulaMeasureErrors(config.measures, index).map((message) => error('measures', message)));
        } else if (fn !== 'COUNT' && !valueField) {
            const kind = fn === 'COUNT_DISTINCT' ? 'a field' : 'a numeric field';
            errors.push(error('measures', `${label}: choose ${kind} to aggregate with ${fn}.`));
        } else if (valueField && !isParentFieldPath(valueField)) {
            errors.push(error('measures', `${label}: value field "${valueField}" is not a valid field path.`));
        }
        if (hasValue(measure.colour) && !HEX_COLOUR.test(String(measure.colour))) {
            errors.push(error('measures', `${label}: colour must be a hex colour such as #0176d3.`));
        }
        errors.push(...averagePerRecordErrors(measure, fn, label));
        errors.push(...shareOfTotalErrors(measure, fn, label, config, widgetLabel));
        errors.push(...formatErrors(measure.format, 'measures', `${label} format`));
        if (hasValue(measure.condition)) {
            const conditionProblem = baseFilterError(measure.condition);
            if (conditionProblem) {
                errors.push(error('measures', `${label} condition: ${conditionProblem}`));
            }
        }
        errors.push(...measureDisplayErrors(measure, label));
    });
    if (cleanString(config.stackByField) && config.measures.some(isFormulaMeasure)) {
        errors.push(error('measures', FORMULA_SERIES_ERROR));
    }
    return errors;
}

/** An Average per record Measure needs a per-record lookup path and takes each record's value as SUM or ONCE. */
function averagePerRecordErrors(measure, fn, label) {
    if (fn !== 'AVG_PER') {
        return [];
    }
    const errors = [];
    const perField = cleanString(measure.perField);
    if (!perField) {
        errors.push(error('measures', `${label}: choose the per-record field (a lookup) to average per record.`));
    } else if (!isParentFieldPath(perField)) {
        errors.push(error('measures', `${label}: per-record field "${perField}" is not a valid field path.`));
    }
    if (hasValue(measure.inner) && !PER_RECORD_INNERS.includes(measure.inner)) {
        errors.push(error('measures', `${label}: take each record's value as SUM or ONCE.`));
    }
    return errors;
}

// ---- Formula measures ------------------------------------------------------------------------------------------
// A Formula measure is Salesforce formula syntax over the Widget's other Measures by slot: Measure 1 is A, Measure 2
// is B … Measure 6 is F (case-insensitive). The server builds it with FormulaEval (`BoardFormulaMeasures`); these
// rules mirror its Measure-reference checks word for word.

export function isFormulaMeasure(measure) {
    return isPlainObject(measure) && String(measure.aggregateFunction || '').toUpperCase() === FORMULA;
}

/** Slot letter of Measure `index` (0 → A). */
export function formulaSlot(index) {
    return FORMULA_SLOTS[index] || '';
}

/** `Measure 2 (B)`: a Measure's title with its formula slot. */
export function measureTitle(index) {
    const slot = formulaSlot(index);
    return slot ? `Measure ${index + 1} (${slot})` : `Measure ${index + 1}`;
}

/** Rewrites each slot reference of `text` through `rename(slotIndex)` (returns a slot index); strings untouched. */
function mapFormulaSlots(text, rename) {
    return String(text).replace(FORMULA_TOKEN, (match, literal, name) => {
        const slot = name && name.length === 1 ? FORMULA_SLOTS.indexOf(name.toUpperCase()) : -1;
        if (slot < 0) {
            return match;
        }
        const target = formulaSlot(rename(slot));
        return target ? target : match;
    });
}

/** Slot indexes (0 = A) a formula references, ascending. */
export function formulaReferences(text) {
    const slots = new Set();
    mapFormulaSlots(text || '', (slot) => {
        slots.add(slot);
        return slot;
    });
    return [...slots].sort((a, b) => a - b);
}

/**
 * Keeps Formula measures pointing at the same Measures after the list is reordered or a Measure removed:
 * `newIndexOf(oldIndex)` is a Measure's new position (or -1 when removed; references to it are left as typed).
 */
export function remapFormulaMeasures(measures, newIndexOf) {
    return measures.map((measure) => {
        if (!isFormulaMeasure(measure) || typeof measure.formula !== 'string') {
            return measure;
        }
        const formula = mapFormulaSlots(measure.formula, (slot) => {
            const next = newIndexOf(slot);
            return next < 0 ? slot : next;
        });
        return { ...measure, formula };
    });
}

/** Config keys holding a Measure's 0-based list position (besides Formula slots and the Gauge's). */
const MEASURE_POSITION_KEYS = ['panelHeadlineMeasure', 'panelSortMeasure'];
const GAUGE_MEASURE_KEYS = ['minMeasure', 'maxMeasure', 'targetMeasure'];

/**
 * The patch that keeps every position-based Measure reference of `config` on the same Measure after its Measures list
 * became `measures` (reordered, or a Measure removed). `mapping[oldIndex]` is the Measure's new position, or -1 when
 * it was removed. Covers Formula slots (a removed slot is left as typed: the Formula reports it), the Gauge's
 * `minMeasure` / `maxMeasure` / `targetMeasure` and the Chart's `panelHeadlineMeasure` / `panelSortMeasure`; a
 * reference to a removed Measure is cleared, so the step's validation asks for a new one where one is required.
 */
export function remapMeasureRefs(config, measures, mapping) {
    const newIndexOf = (oldIndex) => (Number.isInteger(mapping[oldIndex]) ? mapping[oldIndex] : -1);
    const remap = (value) => {
        if (!Number.isInteger(value)) {
            return value;
        }
        const next = newIndexOf(value);
        return next < 0 ? null : next;
    };
    const patch = { measures: remapFormulaMeasures(measures, newIndexOf) };
    MEASURE_POSITION_KEYS.forEach((key) => {
        if (Number.isInteger(config[key])) {
            const next = remap(config[key]);
            // Panel sort by the first Measure is the default (no key).
            patch[key] = key === 'panelSortMeasure' && next === 0 ? null : next;
        }
    });
    if (isPlainObject(config.gauge) && GAUGE_MEASURE_KEYS.some((key) => Number.isInteger(config.gauge[key]))) {
        const gauge = { ...config.gauge };
        GAUGE_MEASURE_KEYS.forEach((key) => {
            const next = remap(gauge[key]);
            if (next === null || next === undefined) {
                delete gauge[key];
            } else {
                gauge[key] = next;
            }
        });
        patch.gauge = gauge;
    }
    return patch;
}

/** The Measure-reference errors of Formula measure `index` (the formula text itself is checked by the server). */
export function formulaMeasureErrors(measures, index) {
    const prefix = `${measureTitle(index)} formula`;
    const text = cleanString(measures[index].formula);
    if (!text) {
        return [`${prefix}: Enter a formula, e.g. A / B or 15000.`];
    }
    return formulaReferences(text)
        .map((slot) => {
            const letter = formulaSlot(slot);
            if (slot === index) {
                return `${prefix} can't use itself (${letter}).`;
            }
            if (slot >= measures.length) {
                return `${prefix} uses ${letter}, but there is no Measure ${slot + 1}.`;
            }
            if (isFormulaMeasure(measures[slot])) {
                return `${prefix} can't use ${letter}: a Formula measure can't reference another Formula measure.`;
            }
            return null;
        })
        .filter(Boolean);
}

function shareOfTotalErrors(measure, fn, label, config, widgetLabel) {
    if (!hasValue(measure.showAs) || measure.showAs === 'value') {
        return [];
    }
    if (widgetLabel !== 'Chart') {
        return [error('measures', `${label}: Share of total is only available on the Chart widget.`)];
    }
    if (!SHOW_AS_MODES.includes(measure.showAs)) {
        return [error('measures', `${label}: show as must be one of ${SHOW_AS_MODES.join(', ')}.`)];
    }
    if (!ROLLUP_FUNCTIONS.includes(fn)) {
        return [error('measures', `${label}: a percentage is only available for COUNT and SUM Measures, not ${fn}.`)];
    }
    // A Reference line is the Measure's overall value: as a share of the whole scope it would always be 100%.
    if (measure.render === 'referenceLine') {
        return [error('measures', `${label}: a Reference line shows the overall value, not a percentage.`)];
    }
    if (measure.showAs !== 'percentOfCategory') {
        return [];
    }
    // A pie, donut or polar area has one Measure and no series: every slice would be 100% of its own category.
    if (chartTypeIsSingleMeasure(config.chartType)) {
        return [
            error('measures', `${label}: a pie, donut or polar area chart offers percent of total, not of category.`)
        ];
    }
    if (!cleanString(config.stackByField) && config.measures.length < 2) {
        return [error('measures', `${label}: percent of category needs a Stack by field or several Measures.`)];
    }
    return [];
}

/** A Measure's combo chart settings: `render` (bar | line | referenceLine) and value `axis` (primary | secondary), both optional. */
function measureDisplayErrors(measure, label) {
    const errors = [];
    if (hasValue(measure.render) && !['bar', 'line', 'referenceLine'].includes(measure.render)) {
        errors.push(error('measures', `${label}: draw as must be bar, line or referenceLine.`));
    }
    if (hasValue(measure.axis) && !['primary', 'secondary'].includes(measure.axis)) {
        errors.push(error('measures', `${label}: axis must be primary or secondary.`));
    }
    return errors;
}

/**
 * `bucketFields`: the Widget's Bucket fields when its columns may show one (`fieldPath: 'bucket:<id>'`); a column
 * then must name one of them. Without it every column is a field path.
 */
function columnErrors(rawColumns, key, prefix, messages, bucketFields) {
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
        const bucketId = bucketFields ? bucketIdOf(column.fieldPath) : null;
        if (bucketId !== null) {
            if (!findBucketField(bucketFields, bucketId)) {
                errors.push(error(key, `${label} uses an unknown Bucket field "${bucketId}".`));
            }
        } else if (!isParentFieldPath(column.fieldPath)) {
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

/** Table widget design-time errors: columns, page size, and the and a leftover childRelationship (removed). */
export function validateTableConfig(config, context = {}) {
    // A Bucket field column uses the Widget's own Bucket fields or the Board's (`context.boardBucketFields`).
    const ownBuckets = Array.isArray(config.bucketFields) ? config.bucketFields : [];
    const boardBuckets = Array.isArray(context.boardBucketFields) ? context.boardBucketFields : [];
    const errors = columnErrors(
        config.columns,
        'columns',
        'Column',
        { notList: 'Columns must be a list.', empty: 'Add at least one column.' },
        [...ownBuckets, ...boardBuckets]
    );
    errors.push(
        ...bucketFieldErrors(config.bucketFields, baseFilterError).map((message) => error('bucketFields', message))
    );
    if (cleanString(config.sortBy) && !isParentFieldPath(config.sortBy)) {
        errors.push(error('sortBy', `Default sort "${config.sortBy}" must be a field or 1–5 hop parent path.`));
    }
    if (hasValue(config.pageSize) && !isIntegerInRange(config.pageSize, 10, 100)) {
        errors.push(error('pageSize', 'Page size must be a whole number from 10 to 100.'));
    }
    errors.push(...rowLimitErrors(config));
    errors.push(...columnSummaryErrors(config.columns));
    errors.push(...detailRowsErrors(config, context?.objectFields));
    if (hasValue(config.childRelationship)) {
        errors.push(error('childRelationship', CHILD_ROWS_REMOVED_MESSAGE));
    }
    errors.push(...rowActionErrors(config.rowActions));
    errors.push(...rowGroupingErrors(config.groupBy));
    errors.push(...bucketGroupErrors(config, [...ownBuckets, ...boardBuckets]));
    return errors;
}

/** A Bucket field group (`bucket:<id>`): Detail rows off only, the only group field, the Widget's or the Board's. */
function bucketGroupErrors(config, bucketFields) {
    const entries = Array.isArray(config.groupBy) ? config.groupBy.filter(isPlainObject) : [];
    const entry = entries.find((candidate) => bucketIdOf(candidate.fieldPath) !== null);
    if (!entry) {
        return [];
    }
    const errors = [];
    if (config.detailRows !== false) {
        errors.push(error('groupBy', 'A Table can group by a Bucket field with Detail rows off only.'));
    } else if (entries.length > 1) {
        errors.push(error('groupBy', 'A Table grouped by a Bucket field has no second group field.'));
    }
    const id = bucketIdOf(entry.fieldPath);
    if (!findBucketField(bucketFields, id)) {
        errors.push(error('groupBy', unknownBucketFieldMessage('Group by', id)));
    }
    return errors;
}

/**
 * Row grouping (Detail rows on): up to two group field paths, each with an optional ASC / DESC group order, a date
 * granularity (the Chart widget's options) and an order field constant per group (`orderBy`, e.g. `Opportunity.Amount`).
 */
function rowGroupingErrors(groupBy) {
    if (!hasValue(groupBy)) {
        return [];
    }
    if (!Array.isArray(groupBy)) {
        return [error('groupBy', 'Group fields must be a list.')];
    }
    const errors = groupBy.length > 2 ? [error('groupBy', 'A Table groups by up to two fields.')] : [];
    groupBy.forEach((entry, index) => {
        const fieldPath = isPlainObject(entry) ? cleanString(entry.fieldPath) : '';
        if (!fieldPath) {
            errors.push(error('groupBy', `Group ${index + 1}: choose a field.`));
            return;
        }
        if (bucketIdOf(fieldPath) === null && !isParentFieldPath(fieldPath)) {
            errors.push(error('groupBy', `Group field "${entry.fieldPath}" must be a field or 1–5 hop parent path.`));
        }
        if (hasValue(entry.sortDirection) && !['ASC', 'DESC'].includes(entry.sortDirection)) {
            errors.push(error('groupBy', `Group ${index + 1}: sort direction must be ASC or DESC.`));
        }
        if (hasValue(entry.orderBy) && !isParentFieldPath(entry.orderBy)) {
            errors.push(
                error('groupBy', `Group ${index + 1}: order field "${entry.orderBy}" must be a 1–5 hop parent path.`)
            );
        }
        if (hasValue(entry.dateGranularity) && !DATE_GRANULARITIES.includes(entry.dateGranularity)) {
            errors.push(
                error(
                    'groupBy',
                    `Group ${index + 1}: date granularity must be one of ${DATE_GRANULARITIES.join(', ')}.`
                )
            );
        }
    });
    return errors;
}

/** A Create action needs an object; each default maps a field of that object from a row field. */
function createActionErrors(action, label) {
    const errors = [];
    if (!cleanString(action.object)) {
        errors.push(error('rowActions', `${label}: choose an object to create.`));
    }
    const defaults = hasValue(action.defaults) ? action.defaults : [];
    const incomplete = (entry) => !isPlainObject(entry) || !cleanString(entry.field) || !cleanString(entry.rowField);
    if (!Array.isArray(defaults) || defaults.some(incomplete)) {
        errors.push(error('rowActions', `${label}: every default needs a field and a row field.`));
    }
    return errors;
}

/** A Screen Flow action needs a flow API name; each input maps a flow variable from a row field. */
function flowActionErrors(action, label) {
    const errors = [];
    if (!cleanString(action.flowApiName)) {
        errors.push(error('rowActions', `${label}: choose a flow.`));
    }
    const inputs = hasValue(action.inputs) ? action.inputs : [];
    const incomplete = (entry) => !isPlainObject(entry) || !cleanString(entry.name) || !cleanString(entry.rowField);
    if (!Array.isArray(inputs) || inputs.some(incomplete)) {
        errors.push(error('rowActions', `${label}: every input needs a variable name and a row field.`));
    }
    return errors;
}

/** Stacked summaries a numeric Table column can show, in the order they are offered. */
export const TABLE_SUMMARY_FUNCTIONS = ['SUM', 'AVG', 'MIN', 'MAX'];

/** Column `summaries`: when set, a list of 1–4 distinct Sum/Average/Min/Max. */
function columnSummaryErrors(rawColumns) {
    if (!Array.isArray(rawColumns)) {
        return [];
    }
    const errors = [];
    rawColumns.forEach((column, index) => {
        const summaries = isPlainObject(column) ? column.summaries : undefined;
        if (!hasValue(summaries)) {
            return;
        }
        const valid =
            Array.isArray(summaries) &&
            summaries.length <= 4 &&
            new Set(summaries).size === summaries.length &&
            summaries.every((name) => TABLE_SUMMARY_FUNCTIONS.includes(name));
        if (!valid) {
            errors.push(
                error('summaries', `Column ${index + 1} summaries: pick 1–4 of Sum, Average, Min and Max, each once.`)
            );
        }
    });
    return errors;
}

const SUMMARY_FUNCTION_LABELS = { SUM: 'Sum', AVG: 'Average', MIN: 'Min', MAX: 'Max' };

/**
 * Lower-cased path prefix of fields reached through a lookup group field (`AccountId` -> `account.`,
 * `Parent__c` -> `parent__r.`), or null when the path does not name a lookup.
 */
function lookupPrefix(groupPath) {
    const path = cleanString(groupPath).toLowerCase();
    if (path.endsWith('__c')) {
        return `${path.slice(0, -3)}__r.`;
    }
    return path.length > 2 && path.endsWith('id') ? `${path.slice(0, -2)}.` : null;
}

/**
 * True when a group entry groups by a date: it has a granularity, or (Day, the default, is left out of the config)
 * its direct field is a Date or DateTime in the object's field describes (`objectFields`, when loaded).
 */
function isDateGroup(entry, objectFields) {
    if (cleanString(entry.dateGranularity)) {
        return true;
    }
    const lowerPath = cleanString(entry.fieldPath).toLowerCase();
    const field = (Array.isArray(objectFields) ? objectFields : []).find(
        (candidate) => cleanString(candidate?.apiName).toLowerCase() === lowerPath
    );
    return ['DATE', 'DATETIME'].includes(field?.dataType);
}

/**
 * True when `lowerPath` has one value per group of a group entry: the group field itself (not a date: its groups are
 * date buckets) or a field through a lookup group field.
 */
function isConstantPerGroup(lowerPath, entry, objectFields) {
    const groupPath = cleanString(entry?.fieldPath);
    if (!groupPath) {
        return false;
    }
    const prefix = lookupPrefix(groupPath);
    const isGroupField = lowerPath === groupPath.toLowerCase() && !isDateGroup(entry, objectFields);
    return isGroupField || Boolean(prefix && lowerPath.startsWith(prefix));
}

/**
 * Detail rows (Row grouping): off makes the Table an aggregated table, so it needs a group field and every column
 * must have one value per group of one of the (up to two) group fields: a group field, a field through a lookup
 * group field, or a column with summaries. Ordering groups by a summary (`orderBySummary`) needs Detail rows off and
 * a summary the Table shows.
 */
function detailRowsErrors(config, objectFields) {
    const errors = [];
    if (hasValue(config.detailRows) && typeof config.detailRows !== 'boolean') {
        return [error('groupBy', 'Detail rows must be on or off.')];
    }
    const detailRowsOff = config.detailRows === false;
    const entries = Array.isArray(config.groupBy) ? config.groupBy.filter(isPlainObject) : [];
    const [first] = entries;
    const groupPath = cleanString(first?.fieldPath);
    if (detailRowsOff && !groupPath) {
        return [error('groupBy', 'Detail rows off needs a group field.')];
    }
    const columns = Array.isArray(config.columns) ? config.columns : [];
    if (detailRowsOff) {
        columns.forEach((column, index) => {
            const path = isPlainObject(column) ? cleanString(column.fieldPath) : '';
            const hasSummaries = Array.isArray(column?.summaries) && column.summaries.length > 0;
            const lowerPath = path.toLowerCase();
            const constant = entries.some((entry) => isConstantPerGroup(lowerPath, entry, objectFields));
            if (path && !hasSummaries && !constant) {
                errors.push(
                    error(
                        'columns',
                        `Column ${index + 1} "${path}": with Detail rows off, show the group field, a field through the group lookup, or a column with summaries.`
                    )
                );
            }
        });
    }
    const summaryOrder = first?.orderBySummary;
    if (hasValue(summaryOrder)) {
        if (!detailRowsOff) {
            errors.push(error('groupBy', 'Order groups by a summary only with Detail rows off.'));
        } else {
            const columnId = summaryOrder?.columnId;
            const summaryFunction = summaryOrder?.summaryFunction;
            const column = columns.find((candidate) => (candidate?.id || candidate?.fieldPath) === columnId);
            const shown = Array.isArray(column?.summaries) && column.summaries.includes(summaryFunction);
            if (!shown) {
                const label = SUMMARY_FUNCTION_LABELS[summaryFunction] || summaryFunction;
                errors.push(error('groupBy', `Group order: column "${columnId}" has no ${label} summary.`));
            }
        }
    }
    return errors;
}

/** Most first-level groups a Row limit keeps with Detail rows on (the record stream is filtered by an IN-list). */
export const GROUPED_DETAIL_ROW_LIMIT_MAX = 200;
/** Most rows (ungrouped) or Group rows (Detail rows off) a Row limit keeps. */
export const ROW_LIMIT_MAX = 2000;

/** True when the Table has Row grouping (a first group field). */
export function isGroupedTable(config) {
    const [first] = Array.isArray(config?.groupBy) ? config.groupBy.filter(isPlainObject) : [];
    return Boolean(cleanString(first?.fieldPath));
}

/** Largest Row limit the config allows: 200 groups with Row grouping and Detail rows on, else 2,000. */
export function rowLimitMax(config) {
    return isGroupedTable(config) && config.detailRows !== false ? GROUPED_DETAIL_ROW_LIMIT_MAX : ROW_LIMIT_MAX;
}

/**
 * Row limit on a grouped Table: counts first-level groups ("Top N groups"), ranked by the group order, so it needs
 * no default sort; 1-200 groups with Detail rows on, 1-2,000 with Detail rows off.
 */
function groupedRowLimitErrors(config) {
    const max = rowLimitMax(config);
    if (isIntegerInRange(config.rowLimit, 1, max)) {
        return [];
    }
    const message =
        max === GROUPED_DETAIL_ROW_LIMIT_MAX
            ? 'With Detail rows on, Row limit must be a whole number from 1 to 200 groups.'
            : 'Row limit must be a whole number from 1 to 2,000.';
    return [error('rowLimit', message)];
}

/** Row limit (Top N): a whole number from 1 to 2,000 that needs a default sort to mean anything. */
function rowLimitErrors(config) {
    if (!hasValue(config.rowLimit)) {
        return [];
    }
    if (isGroupedTable(config)) {
        return groupedRowLimitErrors(config);
    }
    if (!isIntegerInRange(config.rowLimit, 1, ROW_LIMIT_MAX)) {
        return [error('rowLimit', 'Row limit must be a whole number from 1 to 2,000.')];
    }
    return cleanString(config.sortBy) ? [] : [error('rowLimit', 'A Row limit needs a default sort.')];
}

/** Row actions: a list of `view` / `edit` / `create` / `flow` actions, each with a label and (when set) a lookup path target. */
function rowActionErrors(rawActions) {
    if (!hasValue(rawActions)) {
        return [];
    }
    if (!Array.isArray(rawActions)) {
        return [error('rowActions', 'Row actions must be a list.')];
    }
    const errors = [];
    rawActions.forEach((action, index) => {
        const label = `Row action ${index + 1}`;
        if (!isPlainObject(action) || !cleanString(action.label)) {
            errors.push(error('rowActions', `${label} needs a label.`));
            return;
        }
        if (!['view', 'edit', 'create', 'flow'].includes(action.type)) {
            errors.push(error('rowActions', `${label}: type must be view, edit, create, or flow.`));
        }
        if (action.type === 'create') {
            errors.push(...createActionErrors(action, label));
        }
        if (action.type === 'flow') {
            errors.push(...flowActionErrors(action, label));
        }
        if (cleanString(action.target) && !isParentFieldPath(action.target)) {
            errors.push(error('rowActions', `${label}: target "${action.target}" must be a lookup field or path.`));
        }
    });
    return errors;
}

// ---- Widget specs and the config envelope --------------------------------------------------------------------------

const DEFAULT_CHART_TYPE = 'bar';
const BASE_KEYS = ['boardId', 'title'];
const DATA_KEYS = [...BASE_KEYS, 'objectApiName'];

/**
 * Per widget type: data widget (object, bindings, base filters), Widget-level Data provider, dual-written top-level
 * keys, widget rules.
 */
const WIDGET_SPECS = {
    filter: { dataWidget: false, topLevelKeys: BASE_KEYS, validate: validateFilterConfig },
    metric: { dataWidget: true, dataProvider: true, topLevelKeys: DATA_KEYS, validate: validateMetricConfig },
    chart: { dataWidget: true, dataProvider: true, topLevelKeys: DATA_KEYS, validate: validateChartConfig },
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
    const source = isPlainObject(raw) ? normalizeConfigSpelling(raw) : {};
    const ordered = { version: 1, widgetType };
    if (widgetType === 'chart') {
        ordered.chartType = cleanString(source.chartType) || DEFAULT_CHART_TYPE;
    }
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

export const CONDITION_LOGIC_OPTIONS = [
    { label: 'All conditions (AND)', value: 'AND' },
    { label: 'Any condition (OR)', value: 'OR' }
];

/** Whether a condition tree entry is an AND / OR group (`{ id, logic, conditions[] }`) rather than a condition. */
export function isConditionGroup(entry) {
    return isPlainObject(entry) && Object.prototype.hasOwnProperty.call(entry, 'conditions');
}

/** Every entry of a list of condition tree entries (groups and their conditions), depth first. */
export function flattenConditions(entries) {
    return (Array.isArray(entries) ? entries : []).flatMap((entry) => {
        return isConditionGroup(entry) ? [entry, ...flattenConditions(entry.conditions)] : [entry];
    });
}

/** Number of conditions in a list of condition tree entries, counting the conditions inside groups. */
export function countConditions(entries) {
    return (Array.isArray(entries) ? entries : []).reduce(
        (total, entry) => total + (isConditionGroup(entry) ? countConditions(entry.conditions) : 1),
        0
    );
}

const BASE_FILTER_ID_PREFIX = 'bf';

/**
 * Gives entries without an id, or with an id already used elsewhere in the tree (e.g. hand-edited JSON), a fresh
 * `bfN` id; group conditions get the same treatment.
 */
function withBaseFilterIds(entries) {
    const all = flattenConditions(entries);
    const seen = new Set();
    const assigned = [];
    const visit = (list) =>
        list.map((entry) => {
            const id = cleanString(entry.id);
            let next = entry;
            if (!id || seen.has(id)) {
                // Fresh ids count every id in the tree plus the ones already handed out, so they never repeat.
                next = { ...entry, id: nextSequentialId([...all, ...assigned], BASE_FILTER_ID_PREFIX) };
                assigned.push(next);
            }
            seen.add(next.id);
            if (isConditionGroup(next) && Array.isArray(next.conditions)) {
                next = { ...next, conditions: visit(next.conditions.map((c) => (isPlainObject(c) ? c : {}))) };
            }
            return next;
        });
    return visit(entries);
}

/**
 * A Widget's `baseFilters` as the condition tree the condition editor edits: `{ tree: { logic, conditions },
 * rootGroupId }`. The entries of `baseFilters` combine with AND, so a flat list loads as the AND top level; a single
 * stored OR group loads as the OR top level (`rootGroupId` is its id). Missing or duplicate ids get fresh `bfN` ids.
 */
export function baseFiltersToTree(baseFilters) {
    const entries = withBaseFilterIds(
        (Array.isArray(baseFilters) ? baseFilters : []).map((entry) => (isPlainObject(entry) ? entry : {}))
    );
    const only = entries.length === 1 ? entries[0] : null;
    if (isConditionGroup(only) && only.logic === 'OR' && Array.isArray(only.conditions)) {
        return { tree: { logic: 'OR', conditions: only.conditions }, rootGroupId: only.id };
    }
    return { tree: { logic: 'AND', conditions: entries }, rootGroupId: null };
}

/**
 * The `baseFilters` list of a condition tree (`baseFiltersToTree`'s inverse): an AND top level is the list itself;
 * OR at the top level is stored as one OR group entry `{ id, logic: 'OR', conditions }`, keeping `rootGroupId`.
 */
export function baseFiltersFromTree(tree, rootGroupId = null) {
    const { logic, conditions } = tree;
    if (logic !== 'OR' || conditions.length === 0) {
        return conditions;
    }
    const entries = flattenConditions(conditions);
    const taken = entries.some((entry) => entry.id === rootGroupId);
    const id = rootGroupId && !taken ? rootGroupId : nextSequentialId(entries, BASE_FILTER_ID_PREFIX);
    return [{ id, logic: 'OR', conditions }];
}

/** First problem with an AND / OR group itself (not its conditions), or null. */
export function conditionGroupError(entry) {
    if (entry.logic !== 'AND' && entry.logic !== 'OR') {
        return 'Choose AND or OR.';
    }
    if (!Array.isArray(entry.conditions) || entry.conditions.length === 0) {
        return 'Add at least one condition.';
    }
    return null;
}

/**
 * First problem with a condition tree entry (a Base filter condition, or an AND / OR group and its conditions), or
 * null when it compiles. Shared by Base filters and every other condition tree.
 */
export function baseFilterError(condition) {
    if (!isPlainObject(condition)) {
        return 'Each base filter must be an object.';
    }
    if (isConditionGroup(condition)) {
        const problem = conditionGroupError(condition);
        if (problem) {
            return problem;
        }
        for (let index = 0; index < condition.conditions.length; index++) {
            const childProblem = baseFilterError(condition.conditions[index]);
            if (childProblem) {
                return `Condition ${index + 1}: ${childProblem}`;
            }
        }
        return null;
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

/**
 * Messages per Base filter condition (`string[][]`, parallel to `baseFilters`): the condition's own problem
 * (`baseFilterError`) plus a missing or duplicate `id`. Shared by `configErrors` and the Base filters of the Setup dialog's Data step.
 */
export function baseFilterErrorsByIndex(baseFilters) {
    const ids = new Set();
    return (Array.isArray(baseFilters) ? baseFilters : []).map((condition) => {
        const messages = [];
        const problem = baseFilterError(condition);
        if (problem) {
            messages.push(problem);
        }
        messages.push(...conditionIdErrors(condition, ids));
        return messages;
    });
}

/** Missing or duplicate `id`s of a condition tree entry and the conditions of a group (ids are unique per tree). */
function conditionIdErrors(condition, ids) {
    if (!isPlainObject(condition)) {
        return [];
    }
    const messages = [];
    const id = cleanString(condition.id);
    if (!id) {
        messages.push('id is required.');
    } else if (ids.has(id)) {
        messages.push(`duplicate id "${id}".`);
    }
    ids.add(id);
    if (isConditionGroup(condition) && Array.isArray(condition.conditions)) {
        condition.conditions.forEach((child) => messages.push(...conditionIdErrors(child, ids)));
    }
    return messages;
}

const BASE_FILTER_OPERATOR_LABELS = Object.fromEntries(
    BASE_FILTER_OPERATOR_OPTIONS.map((option) => [option.value, option.label])
);

/**
 * Read-only description of a Base filter condition: `{ label, operatorLabel, valueText }`, e.g.
 * `Status` · `Not in list` · `Closed, Duplicate`. `label` falls back to `Condition N` without a field.
 */
export function baseFilterSummary(condition, index) {
    if (isConditionGroup(condition)) {
        return conditionGroupSummary(condition);
    }
    const safe = isPlainObject(condition) ? condition : {};
    const operator = safe.operator;
    const value = safe.value;
    let valueText = '';
    if (operator === 'IS_NULL') {
        valueText = value === false || value === 'false' ? 'is not null' : 'is null';
    } else if (Array.isArray(value)) {
        valueText = value.join(', ');
    } else if (hasValue(value)) {
        valueText = String(value);
    }
    return {
        label: cleanString(safe.fieldPath) || `Condition ${index + 1}`,
        operatorLabel: operator === 'IS_NULL' ? 'Null check' : BASE_FILTER_OPERATOR_LABELS[operator] || 'No operator',
        valueText
    };
}

/**
 * Read-only description of an AND / OR group, e.g. `Any of 2 conditions` · `OR group` ·
 * `Status: New or (Priority: High and Origin: Web)`.
 */
function conditionGroupSummary(group) {
    const conditions = Array.isArray(group.conditions) ? group.conditions : [];
    const logic = group.logic === 'OR' ? 'OR' : 'AND';
    const parts = conditions.map((child, index) => {
        if (isConditionGroup(child)) {
            const nested = conditionGroupSummary(child).valueText;
            return nested ? `(${nested})` : '()';
        }
        const { label, valueText } = baseFilterSummary(child, index);
        return valueText ? `${label}: ${valueText}` : label;
    });
    return {
        label: `${logic === 'OR' ? 'Any' : 'All'} of ${countLabel(conditions.length, 'condition')}`,
        operatorLabel: `${logic} group`,
        valueText: parts.join(logic === 'OR' ? ' or ' : ' and ')
    };
}

function baseFilterErrors(baseFilters) {
    if (baseFilters === undefined || baseFilters === null) {
        return [];
    }
    if (!Array.isArray(baseFilters)) {
        return [error('baseFilters', 'Base filters must be a list.')];
    }
    const errors = [];
    baseFilterErrorsByIndex(baseFilters).forEach((messages, index) =>
        messages.forEach((message) => errors.push(error('baseFilters', `Base filter ${index + 1}: ${message}`)))
    );
    return errors;
}

/**
 * Design-time errors of a config envelope (`[{ key, errorString }]`): the rules behind both `validate()` and pasted
 * Config JSON. `references` holds top-level keys bound to Flow resources (they satisfy required values).
 */
export function configErrors(widgetType, config, references = {}, context = {}) {
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
    if (spec.dataProvider) {
        errors.push(...dataProviderErrors(config.dataProvider));
    }
    errors.push(...spec.validate(config, context));
    return errors;
}

/** An Apex class name, optionally namespaced (`ns.ClassName`). */
const APEX_CLASS_NAME = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)?$/;

/**
 * The Widget-level Data provider (Chart and Metric): an Apex class name. Whether the class exists and implements
 * `BoardDataProvider` is checked by the server at query time; its message shows in the Widget (and the preview).
 */
function dataProviderErrors(dataProvider) {
    const name = cleanString(dataProvider);
    if (!hasValue(dataProvider) || (name && APEX_CLASS_NAME.test(name))) {
        return [];
    }
    return [error('dataProvider', `Data provider "${dataProvider}" must be an Apex class name, e.g. QuotaProvider.`)];
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
    const config = orderConfig(widgetType, parsed);
    errors.push(...configErrors(widgetType, config, references).map((item) => item.errorString));
    return { config: errors.length ? null : config, errors };
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

/**
 * True when the Widget being edited counts as new for the Config sections' default open state: its config is empty,
 * or it has no object (data Widgets, unless `objectApiName` is bound to a Flow resource) / no filters (Filter widget).
 * Call once on load (e.g. `connectedCallback`); open state must not follow later edits.
 */
export function isNewWidget(widgetType, inputVariables) {
    const { config, references } = readCpeState(widgetType, inputVariables);
    const keys = Object.keys(config).filter((key) => key !== 'version' && key !== 'widgetType');
    if (!keys.length && !Object.keys(references).length) {
        return true;
    }
    if (specFor(widgetType).dataWidget) {
        return !cleanString(config.objectApiName) && !references.objectApiName;
    }
    return !(Array.isArray(config.filters) && config.filters.length);
}

/** True when any `[{ key, errorString }]` error belongs to one of `keys` (a Config section's config keys). */
export function hasErrorFor(errors, keys) {
    return Array.isArray(errors) && errors.some((item) => item && keys.includes(item.key));
}

// ---- Config sections -------------------------------------------------------------------------------------------
//
// Each Config editor describes its Config sections once, as a list of descriptors:
//   `{ name, errorKeys, summary(cpe), openWhenNew?, hasError?(cpe) }`
// `name` is the `c-board-cpe-section` name (echoed by its `toggle` event), `errorKeys` the `validate()` error keys
// that belong to the section, `summary` the collapsed one-line summary, `openWhenNew` opens the section for a new
// Widget, and the optional `hasError` adds a section-specific error check. The template then binds
// `name={sections.x.name} summary={sections.x.summary} open={sections.x.open} has-error={sections.x.hasError}`.

/** Separator between the parts of a Config section summary (`default · Account`). */
export const SUMMARY_SEPARATOR = ' · ';

/** Joins the non-empty parts of a Config section summary. */
export function joinSummary(parts) {
    return parts.filter((part) => part !== null && part !== undefined && part !== '').join(SUMMARY_SEPARATOR);
}

/** `1 rule`, `3 rules` (`plural` for irregular nouns). */
export function countLabel(count, noun, plural = `${noun}s`) {
    return `${count} ${count === 1 ? noun : plural}`;
}

/**
 * Default open state of a Config editor's sections (`{ [name]: boolean }`): a new Widget (`isNewWidget`) opens the
 * `openWhenNew` sections, an existing one starts collapsed. Call once on load; open state must not follow edits.
 */
export function initialSectionOpen(sections, widgetType, inputVariables) {
    const isNew = isNewWidget(widgetType, inputVariables);
    return Object.fromEntries(sections.map((section) => [section.name, Boolean(isNew && section.openWhenNew)]));
}

/** The open state after a `c-board-cpe-section` `toggle` event (`detail: { name, open }`). */
export function toggleSectionOpen(sectionOpen, event) {
    const { name, open } = event.detail;
    return { ...sectionOpen, [name]: open };
}

/**
 * Header state of each Config section, keyed by name: `{ name, open, hasError, summary }`. The values are lazy, so a
 * template binding only computes what it reads. `errors()` returns the `validate()`-style errors the sections check.
 */
export function sectionStates(sections, cpe, sectionOpen, errors) {
    let cached;
    const sectionErrors = () => {
        if (!cached) {
            cached = errors();
        }
        return cached;
    };
    return Object.fromEntries(
        sections.map((section) => [
            section.name,
            {
                name: section.name,
                get open() {
                    return Boolean(sectionOpen && sectionOpen[section.name]);
                },
                get hasError() {
                    return (
                        hasErrorFor(sectionErrors(), section.errorKeys || []) ||
                        Boolean(section.hasError && section.hasError(cpe))
                    );
                },
                get summary() {
                    return section.summary ? section.summary(cpe) : '';
                }
            }
        ])
    );
}

const AGGREGATE_LABELS = new Map([
    ...AGGREGATE_OPTIONS.map((option) => [option.value, option.label]),
    ['AVG_PER', 'Average per record'],
    [FORMULA, 'Formula']
]);

/** The notation a Widget formats values with when `format.notation` is unset: Metric is compact, the rest standard. */
export function defaultNotationFor(widgetType) {
    return widgetType === 'metric' ? 'compact' : 'standard';
}

/**
 * Measure section summary of the Metric and Chart Config editors: the aggregate and the value notation, e.g.
 * `Count of records · compact` or `Sum of Amount · standard`.
 */
export function measureSummary(widgetType, config) {
    const fn = config.aggregateFunction || 'COUNT';
    const label = AGGREGATE_LABELS.get(fn) || fn;
    let measure = label;
    if (fn === FORMULA) {
        measure = cleanString(config.formula) ? `Formula ${cleanString(config.formula)}` : 'Formula (no formula)';
    } else if (fn !== 'COUNT') {
        measure = config.valueFieldApiName ? `${label} of ${config.valueFieldApiName}` : `${label} (no value field)`;
    }
    const format = isPlainObject(config.format) ? config.format : {};
    return joinSummary([measure, format.notation || defaultNotationFor(widgetType)]);
}

/**
 * Measures section summary of the Chart Config editor: one Measure reads like `measureSummary`
 * (`Sum of Amount · compact`); several list their labels (`2 Measures: Pipeline, Count of records`).
 */
export function chartMeasuresSummary(config) {
    if (!hasDefinedMeasures(config)) {
        return DEFAULT_MEASURE_SUMMARY;
    }
    const measures = chartMeasures(config).filter(isPlainObject);
    if (measures.length === 1) {
        return measureSummary('chart', measures[0]);
    }
    const labels = measures.map((measure) => {
        const custom = cleanString(measure.label);
        if (custom) {
            return custom;
        }
        const fn = measure.aggregateFunction || 'COUNT';
        const label = AGGREGATE_LABELS.get(fn) || fn;
        return fn === 'COUNT' || !measure.valueFieldApiName ? label : `${label} of ${measure.valueFieldApiName}`;
    });
    return `${measures.length} Measures: ${labels.join(', ')}`;
}

/**
 * Measure section summary of the Metric Config editor: the visible Measure like `measureSummary`, plus the Measure
 * count when there are several (`Sum of Amount · compact · 3 Measures (2 hidden)`).
 */
export function metricMeasuresSummary(config) {
    if (!hasDefinedMeasures(config) && !hasValue(config.aggregateFunction) && !hasValue(config.valueFieldApiName)) {
        return DEFAULT_MEASURE_SUMMARY;
    }
    const measures = metricMeasures(config).filter(isPlainObject);
    const visible = measures.find((measure) => measure.hidden !== true) || measures[0] || {};
    const summary = measureSummary('metric', visible);
    if (measures.length < 2) {
        return summary;
    }
    const hidden = measures.filter((measure) => measure.hidden === true).length;
    return joinSummary([summary, `${measures.length} Measures (${hidden} hidden)`]);
}

// ---- Setup dialog ----------------------------------------------------------------------------------------------

/** How the Setup dialog (`c/boardSetupDialog`) closes: Save with the whole draft, or dismiss (Cancel, X, Escape). */
export const DIALOG_SAVE = 'save';
export const DIALOG_DISMISS = 'dismiss';