/**
 * Steps of a Widget's Setup dialog, as plain data shared by the Setup dialog and the Config editor panel (ADR 0002:
 * steps = Config sections). A step descriptor extends a Config section descriptor (`name`, `errorKeys`, `summary`):
 *
 *   `{ name, label, required, errorKeys, sections, summary(config, context), validate(config, context), intro, example }`
 *
 * - `required`: Guided mode blocks Next until the step is valid; optional steps can be skipped (defaults apply).
 * - `errorKeys`: the `configErrors` keys (`[{ key, errorString }]`) that belong to the step.
 * - `sections`: the panel Config sections the step covers, `{ [sectionName]: summary(config, context) }`; the panel
 *   reads its one-line section summaries from here (`stepSectionSummary`).
 * - `summary`: the step's one-line summary of the draft.
 * - `validate`: the step's errors over the WHOLE draft config, so an upstream change (e.g. a different object) makes
 *   a later step invalid without clearing anything.
 * - `intro` / `example`: a short explanation and a worked example shown when the step opens.
 * - `retired` (optional): `[{ message, keys }]`, retired settings of a saved config whose error (`message`) the step
 *   reports; the Setup dialog offers "Remove retired setting" on that error, which drops `keys` from the draft.
 *
 * `context` (all optional) carries what a pure function over the config can't know:
 * - `references`: top-level keys bound to Flow resources (`readCpeState`)
 * - `boardBucketFields`: the Board's Bucket fields (of its Filter widget)
 * - `groupByType`: `Schema.DisplayType` of the Group by field, once described
 * - `objectFields`: the field describes (`apiName`, `relationshipName`) of the draft's object, once loaded; a field
 *   path whose first segment isn't on the object makes its step invalid
 * - `bindingRows`: the Filter bindings rows of the Config editor (`status` `bound` / `ignored` / ...)
 */
import {
    BAR_SORT_OPTIONS,
    DATE_FIELD_TYPES,
    DATE_GRANULARITY_OPTIONS,
    chartMeasures,
    chartMeasuresSummary,
    cleanString,
    configErrors,
    countConditions,
    countLabel,
    flattenConditions,
    isConditionGroup,
    isIgnoreBinding,
    isPlainObject,
    joinSummary,
    MEASURES_REPLACED_MESSAGE,
    metricMeasuresSummary
} from 'c/boardCpeUtils';
import { CHILD_ROWS_REMOVED_MESSAGE, filterItemsOf, isCurrencyPickerItem, metricMeasures } from 'c/boardConfigUtils';
import { isGaugeDisplay } from 'c/boardMetricGauge';
import { isCrossObjectMeasure } from 'c/boardCrossObjectMeasure';
import { bucketIdOf, findBucketField } from 'c/boardBucketFields';
import { CHART_TYPE_OPTIONS, chartTypeHasSetting } from 'c/boardChartUtils';
import { hasPanelField, normalizePanelSettings } from 'c/boardChartPanels';

const CHART_TYPE_LABELS = new Map(CHART_TYPE_OPTIONS.map((option) => [option.value, option.label]));
const SORT_LABELS = new Map(BAR_SORT_OPTIONS.map((option) => [option.value, option.label]));
const GRANULARITY_LABELS = new Map([
    ...DATE_GRANULARITY_OPTIONS.map((option) => [option.value, option.label]),
    ['DAY', 'Day']
]);

// ---- Generic helpers -----------------------------------------------------------------------------------------------

function error(key, errorString) {
    return { key, errorString };
}

/** True when `path`'s first segment is a field (or, for a parent path, a relationship) of the described object. */
function isOnObject(path, objectFields) {
    const segments = path.split('.');
    const first = segments[0].toLowerCase();
    const key = segments.length === 1 ? 'apiName' : 'relationshipName';
    return objectFields.some((field) => (cleanString(field && field[key]) || '').toLowerCase() === first);
}

/**
 * Errors for field paths of the draft that aren't on its object (`context.objectFields`), e.g. after the Admin
 * changed the object. `paths(config)` lists `{ key, label, path }`; Bucket field references are skipped.
 */
function fieldsOnObjectErrors(config, context, paths) {
    const objectFields = Array.isArray(context.objectFields) ? context.objectFields : null;
    const object = cleanString(config.objectApiName);
    if (!objectFields || !object) {
        return [];
    }
    return paths(config)
        .map((entry) => ({ ...entry, path: cleanString(entry.path) }))
        .filter(({ path }) => path && checkablePath(path) && !isOnObject(path, objectFields))
        .map(({ key, label, path }) => error(key, `${label} "${path}" is not a field of ${object}.`));
}

/**
 * Whether a path can be checked against the object's field describes: not a Bucket field reference, `SELF`, or a
 * child semi-join (`Child(ForeignKey).Path`, whose relationship isn't among the object's fields).
 */
function checkablePath(path) {
    return bucketIdOf(path) === null && path.toUpperCase() !== 'SELF' && !path.includes('(');
}

/** `{ key, label, path }` of every condition in a condition tree (a list of entries, or one group or condition). */
function conditionPaths(tree, key, label) {
    const entries = Array.isArray(tree) ? tree : [tree];
    return flattenConditions(entries)
        .filter((entry) => isPlainObject(entry) && !isConditionGroup(entry))
        .map((condition) => ({ key, label, path: condition.fieldPath }));
}

/** Combines several `paths(config)` lists into one. */
function allPaths(...lists) {
    return (config) => lists.flatMap((paths) => paths(config));
}

/** The Base filters' fields (Data step): a condition tree on the Widget's object. */
function baseFilterPaths(config) {
    return conditionPaths(config.baseFilters || [], 'baseFilters', 'Base filter field').map((entry, index) => ({
        ...entry,
        label: `Base filter ${index + 1} field`
    }));
}

/** The fields of a list of Measures read on the Widget's object: conditions and Average per record fields. */
function measureFieldPaths(measures) {
    return measures.flatMap((measure, index) => {
        if (!isPlainObject(measure) || isCrossObjectMeasure(measure)) {
            return [];
        }
        const label = `Measure ${index + 1}`;
        return [
            ...(measure.condition ? conditionPaths(measure.condition, 'measures', `${label} condition field`) : []),
            { key: 'measures', label: `${label}: per-record field`, path: measure.perField }
        ];
    });
}

/** The fields of the Widget's own Bucket field rules. */
function bucketRulePaths(config) {
    return (Array.isArray(config.bucketFields) ? config.bucketFields : []).filter(isPlainObject).flatMap((field) =>
        (Array.isArray(field.rules) ? field.rules : []).filter(isPlainObject).flatMap((rule, index) => {
            const label = `Bucket field "${field.label || field.id}" rule ${index + 1} field`;
            return rule.condition ? conditionPaths(rule.condition, 'bucketFields', label) : [];
        })
    );
}

/** The Filter binding paths set to a field path (each target of a multi-field binding). */
function filterBindingPaths(config) {
    const bindings = isPlainObject(config.filterBindings) ? config.filterBindings : {};
    return Object.entries(bindings)
        .filter(([, binding]) => typeof binding === 'string' && !isIgnoreBinding(binding))
        .flatMap(([filterId, binding]) =>
            binding
                .split(',')
                .map((path) => ({ key: 'filterBindings', label: `Filter binding "${filterId}" field`, path }))
        );
}

/** The Table's Row action row fields: lookup targets, Create defaults' row fields and Screen Flow inputs. */
function rowActionPaths(config) {
    return (Array.isArray(config.rowActions) ? config.rowActions : [])
        .filter(isPlainObject)
        .flatMap((action, index) => {
            const label = `Row action ${index + 1}`;
            const rowFields = (list, what) =>
                (Array.isArray(list) ? list : [])
                    .filter(isPlainObject)
                    .map((entry) => ({ key: 'rowActions', label: `${label} ${what} row field`, path: entry.rowField }));
            return [
                { key: 'rowActions', label: `${label} target`, path: action.target },
                ...rowFields(action.defaults, 'default'),
                ...rowFields(action.inputs, 'input')
            ];
        });
}

/** The Filter bindings step, shared by every data Widget: binding paths must be on the Widget's object. */
function filterBindingsStep(widgetType) {
    return step(widgetType, {
        name: 'filterBindings',
        label: 'Filter bindings',
        required: false,
        errorKeys: ['filterBindings'],
        summary: (config, context = {}) => filterBindingsSummary(context.bindingRows),
        extraErrors: (config, context) => fieldsOnObjectErrors(config, context, filterBindingPaths),
        intro: "Choose which field of this Widget's object each Filter of the Board applies to, or opt out of a Filter.",
        example: 'The Account filter applies to Opportunity.AccountId; the Owner filter is ignored.'
    });
}

/**
 * A step descriptor of `widgetType`: `validate` keeps the `configErrors` of the whole draft that belong to the step
 * (`errorKeys`), plus the step's own `extraErrors(config, context)`.
 */
function step(widgetType, { extraErrors, ...descriptor }) {
    return {
        sections: {},
        ...descriptor,
        validate(config = {}, context = {}) {
            const keys = descriptor.errorKeys;
            const own = configErrors(widgetType, config, context.references || {}, context).filter((item) =>
                keys.includes(item.key)
            );
            return [...own, ...(extraErrors ? extraErrors(config, context) : [])];
        }
    };
}

/** Data step summary: the object (or `No object`), plus the Base filter count (conditions inside groups too). */
function dataSummary(config, context = {}) {
    const references = context.references || {};
    const object = cleanString(config.objectApiName) || references.objectApiName || 'No object';
    const count = Array.isArray(config.baseFilters) ? countConditions(config.baseFilters) : 0;
    return joinSummary([object, count ? countLabel(count, 'base filter') : '']);
}

/**
 * The Data step of a data Widget (`widgetType`): the object and the Base filters (`c-board-setup-base-filters` in
 * the step content). Base filter errors make the step invalid. `overrides` sets e.g. the step's `intro` / `example`.
 */
export function dataStep(widgetType, overrides = {}) {
    return step(widgetType, {
        name: 'data',
        label: 'Data',
        required: true,
        errorKeys: ['objectApiName', 'baseFilters', 'dataProvider'],
        summary: dataSummary,
        extraErrors: (config, context) => fieldsOnObjectErrors(config, context, baseFilterPaths),
        ...overrides
    });
}

/** Filter bindings summary: `3 bound · 1 opted out`, or `None` without any Filter to bind. */
export function filterBindingsSummary(bindingRows) {
    const rows = Array.isArray(bindingRows) ? bindingRows : [];
    if (!rows.length) {
        return 'None';
    }
    const bound = rows.filter((row) => row.status === 'bound').length;
    const optedOut = rows.filter((row) => row.status === 'ignored').length;
    return joinSummary([`${bound} bound`, `${optedOut} opted out`]);
}

// ---- Chart widget --------------------------------------------------------------------------------------------------

/** A field path as is, or a Bucket field reference as its label (the Widget's own, else the Board's). */
function dimensionLabel(config, context, fieldReference) {
    const id = bucketIdOf(fieldReference);
    if (id === null) {
        return fieldReference;
    }
    const bucketField = findBucketField(config.bucketFields, id) || findBucketField(context.boardBucketFields, id);
    return bucketField?.label || id;
}

/** Whether the chart groups by date: a date Group by field (once described) or a saved date granularity. */
function showsGranularity(config, context) {
    return (
        Boolean(config.groupByField) &&
        (DATE_FIELD_TYPES.includes(context.groupByType) || Boolean(config.dateGranularity))
    );
}

function chartTypeOf(config) {
    return config.chartType || 'bar';
}

/** `CreatedDate · Calendar month · Stacked by Status`. */
function chartDimensionsSummary(config, context = {}) {
    if (!config.groupByField) {
        return 'No Group by field';
    }
    const parts = [dimensionLabel(config, context, config.groupByField)];
    if (showsGranularity(config, context)) {
        const granularity = config.dateGranularity || 'DAY';
        parts.push(GRANULARITY_LABELS.get(granularity) || granularity);
    }
    if (config.stackByField) {
        const mode = config.stackMode === 'grouped' ? 'Grouped' : 'Stacked';
        parts.push(`${mode} by ${dimensionLabel(config, context, config.stackByField)}`);
    }
    return joinSummary(parts);
}

/** `Panels by Type · Max 6` (a Bucket field Panel field by its label), or `Off` without a Panel field. */
function chartSmallMultiplesSummary(config, context = {}) {
    if (!hasPanelField(config)) {
        return 'Off';
    }
    const panels = normalizePanelSettings(config);
    return joinSummary([`Panels by ${dimensionLabel(config, context, config.panelField)}`, `Max ${panels.maxPanels}`]);
}

/** `Value (high to low) · Max 10 bars`, plus the "Other" bar and data labels when on. */
function chartDisplaySummary(config, context = {}) {
    const chartType = chartTypeOf(config);
    const sortBy = config.sortBy || (showsGranularity(config, context) ? 'CHRONOLOGICAL_ASC' : 'VALUE_DESC');
    const noun = chartType === 'bar' ? 'bars' : 'categories';
    const parts = [SORT_LABELS.get(sortBy) || sortBy, `Max ${config.maxBars ?? 10} ${noun}`];
    if (config.overflowMode === 'OTHER') {
        parts.push('"Other" bar');
    }
    const showLabelMode = chartTypeHasSetting(chartType, 'labelMode');
    if (config.showDataLabels === true && !showLabelMode) {
        parts.push('Data labels');
    }
    if (showLabelMode) {
        parts.push(`Labels: ${config.labelMode || 'percent'}`);
    }
    return joinSummary(parts);
}

/** The Chart widget's field paths that must exist on its object, per step. */
function chartGroupingPaths(config) {
    return [
        { key: 'groupByField', label: 'Group by field', path: config.groupByField },
        { key: 'stackByField', label: 'Stack by field', path: config.stackByField },
        { key: 'panelField', label: 'Panel field', path: config.panelField }
    ];
}

/** The Chart widget's Measure fields that must exist on its object (a Cross-object measure reads another object). */
function chartMeasurePaths(config) {
    return chartMeasures(config).map((measure, index) => ({
        key: 'measures',
        label: `Measure ${index + 1}: value field`,
        path: measure && !isCrossObjectMeasure(measure) ? measure.valueFieldApiName : null
    }));
}

const GROUPING_KEYS = [
    'groupByField',
    'dateGranularity',
    'stackByField',
    'maxSeries',
    'bucketFields',
    'panelField',
    'panelDateGranularity',
    'maxPanels',
    'panelsPerRow',
    'panelHeight',
    'panelHeadlineMeasure'
];

/** Chart widget steps, in order (chart type early, so the live preview starts early). */
export const CHART_STEPS = [
    dataStep('chart', {
        intro: 'Choose the object whose records the chart counts and adds up.',
        example: 'Opportunity: one bar per stage, counting or summing Opportunities.'
    }),
    step('chart', {
        name: 'chartType',
        label: 'Chart type',
        required: false,
        errorKeys: ['chartType', 'orientation'],
        sections: { chartType: (config) => CHART_TYPE_LABELS.get(chartTypeOf(config)) || chartTypeOf(config) },
        summary: (config) => CHART_TYPE_LABELS.get(chartTypeOf(config)) || chartTypeOf(config),
        intro: 'Pick how the values are drawn. Bars compare categories, lines show a trend, donuts show shares.',
        example: 'Line chart of Amount by Close Date month to see the pipeline trend.'
    }),
    step('chart', {
        name: 'measures',
        label: 'Measures',
        required: true,
        errorKeys: ['measures'],
        sections: { measure: (config) => chartMeasuresSummary(config) },
        summary: (config) => chartMeasuresSummary(config),
        retired: [{ message: MEASURES_REPLACED_MESSAGE, keys: ['aggregateFunction', 'valueFieldApiName'] }],
        extraErrors: (config, context) =>
            fieldsOnObjectErrors(
                config,
                context,
                allPaths(chartMeasurePaths, (c) => measureFieldPaths(chartMeasures(c)))
            ),
        intro: 'Each Measure is one value per category: a count, a sum or average of a field, or a Formula over the other Measures.',
        example: 'Win rate: Measure A counts Won Opportunities, Measure B counts Closed ones, Formula Won ÷ Closed.'
    }),
    step('chart', {
        name: 'grouping',
        label: 'Grouping',
        required: true,
        errorKeys: GROUPING_KEYS,
        sections: { dimensions: chartDimensionsSummary, smallMultiples: chartSmallMultiplesSummary },
        summary: (config, context = {}) => {
            const panels = hasPanelField(config) ? chartSmallMultiplesSummary(config) : '';
            return joinSummary([chartDimensionsSummary(config, context), panels]);
        },
        extraErrors: (config, context) =>
            fieldsOnObjectErrors(config, context, allPaths(chartGroupingPaths, bucketRulePaths)),
        intro: 'Group by gives the categories on the axis; Stack by splits each category into series; a Panel field draws one small chart per value.',
        example: 'Group by Stage, stacked by Type: one bar per stage, split into New Business and Renewal.'
    }),
    step('chart', {
        name: 'display',
        label: 'Display',
        required: false,
        errorKeys: ['subtitle', 'sortBy', 'maxBars', 'overflowMode', 'labelMode', 'fixedColours'],
        sections: { display: chartDisplaySummary },
        summary: chartDisplaySummary,
        intro: 'Sort the categories, cap how many are shown, and set the legend, labels and colours.',
        example: 'Top 10 Accounts by Amount, the rest summed into one "Other" bar.'
    }),
    filterBindingsStep('chart')
];

// ---- Metric widget -------------------------------------------------------------------------------------------------

/** The Metric widget's Measure fields that must exist on its object (a Cross-object measure reads another object). */
function metricMeasurePaths(config) {
    return metricMeasures(config).map((measure, index) => ({
        key: 'measures',
        label: `Measure ${index + 1}: value field`,
        path: measure && !isCrossObjectMeasure(measure) ? measure.valueFieldApiName : null
    }));
}

/** `Gauge · Open pipeline`: Number or Gauge, plus the subtitle. */
function metricDisplaySummary(config) {
    return joinSummary([isGaugeDisplay(config) ? 'Gauge' : 'Number', cleanString(config.subtitle) || '']);
}

/** `None` or the number of Threshold rules. */
function metricThresholdsSummary(config) {
    const count = Array.isArray(config.thresholds) ? config.thresholds.length : 0;
    return count ? countLabel(count, 'rule') : 'None';
}

/** Metric widget steps, in order. */
export const METRIC_STEPS = [
    dataStep('metric', {
        intro: 'Choose the object whose records the Metric counts or adds up into one number.',
        example: 'Opportunity, filtered to open deals: the total open pipeline.'
    }),
    step('metric', {
        name: 'measures',
        label: 'Measures',
        required: true,
        errorKeys: ['measures', 'aggregateFunction', 'valueFieldApiName', 'format'],
        sections: { measure: (config) => metricMeasuresSummary(config) },
        summary: (config) => metricMeasuresSummary(config),
        extraErrors: (config, context) =>
            fieldsOnObjectErrors(
                config,
                context,
                allPaths(metricMeasurePaths, (c) => measureFieldPaths(metricMeasures(c)))
            ),
        intro: 'The Metric shows exactly one visible Measure: a count, a sum or average of a field, or a Formula over Hidden Measures. Hidden Measures can also feed the Gauge.',
        example: 'Win rate: Hidden Measures count Won and Closed Opportunities, the visible Formula is Won ÷ Closed.'
    }),
    step('metric', {
        name: 'display',
        label: 'Display',
        required: false,
        errorKeys: ['display', 'gauge', 'subtitle'],
        sections: { display: metricDisplaySummary },
        summary: metricDisplaySummary,
        intro: 'Show the value as a number or on a Gauge, and add a subtitle under it.',
        example: 'A Gauge from 0 to the quota (a Hidden Measure), with the target marked.'
    }),
    step('metric', {
        name: 'thresholds',
        label: 'Thresholds',
        required: false,
        errorKeys: ['thresholds'],
        sections: { thresholds: metricThresholdsSummary },
        summary: metricThresholdsSummary,
        intro: 'Colour the value by rules checked in order; the first rule that matches sets the status. On a Gauge the rules are its bands.',
        example: 'Green at 100 or more, amber at 50 or more, red below 50.'
    }),
    filterBindingsStep('metric')
];

// ---- Table widget --------------------------------------------------------------------------------------------------

const TABLE_DEFAULT_PAGE_SIZE = 25;

function tableColumns(config) {
    return Array.isArray(config.columns) ? config.columns.filter(isPlainObject) : [];
}

function tableGroupEntries(config) {
    return (Array.isArray(config.groupBy) ? config.groupBy : []).filter(
        (entry) => isPlainObject(entry) && entry.fieldPath
    );
}

/** Row grouping with Detail rows on (the default): records under their Group rows. */
function tableHasDetailRows(config) {
    return config.detailRows !== false;
}

/** `3 columns`, or `No columns`. */
function tableColumnsSummary(config) {
    const count = tableColumns(config).length;
    return count ? countLabel(count, 'column') : 'No columns';
}

/** `Grouped by StageName asc, then Deal size desc`, plus `Group rows only` with Detail rows off, or `No grouping`. */
function tableGroupingSummary(config, context = {}) {
    const levels = tableGroupEntries(config).map(
        (entry) =>
            `${dimensionLabel(config, context, entry.fieldPath)} ${entry.sortDirection === 'DESC' ? 'desc' : 'asc'}`
    );
    if (!levels.length) {
        return 'No grouping';
    }
    return joinSummary([`Grouped by ${levels.join(', then ')}`, tableHasDetailRows(config) ? '' : 'Group rows only']);
}

/** `Total row · Subtotals · 2 columns summarized`, or `None`. */
function tableSummariesSummary(config) {
    const grouped = tableGroupEntries(config).length > 0;
    const summarized = tableColumns(config).filter(
        (column) => Array.isArray(column.summaries) && column.summaries.length
    ).length;
    const parts = [
        config.showTotalRow === true ? 'Total row' : '',
        grouped && tableHasDetailRows(config) && config.showSubtotals === true ? 'Subtotals' : '',
        summarized ? `${countLabel(summarized, 'column')} summarized` : ''
    ];
    return joinSummary(parts) || 'None';
}

/** `CloseDate desc · 50 per page · Top 10 · No row count`. */
function tableDisplaySummary(config) {
    const sortBy = cleanString(config.sortBy);
    const sort = sortBy ? `${sortBy} ${config.sortDirection === 'DESC' ? 'desc' : 'asc'}` : 'Default sort';
    const parts = [sort, `${config.pageSize ?? TABLE_DEFAULT_PAGE_SIZE} per page`];
    if (config.rowLimit) {
        parts.push(`Top ${config.rowLimit}${tableGroupEntries(config).length ? ' groups' : ''}`);
    }
    if (config.showRowCount === false) {
        parts.push('No row count');
    }
    return joinSummary(parts);
}

/** `2 row actions`, or `No row actions`. */
function tableRowActionsSummary(config) {
    const count = Array.isArray(config.rowActions) ? config.rowActions.length : 0;
    return count ? countLabel(count, 'row action') : 'No row actions';
}

function tableColumnPaths(config) {
    return tableColumns(config).map((column, index) => ({
        key: 'columns',
        label: `Column ${index + 1}`,
        path: column.fieldPath
    }));
}

function tableGroupPaths(config) {
    return tableGroupEntries(config).flatMap((entry, index) => [
        { key: 'groupBy', label: `Group ${index + 1} field`, path: entry.fieldPath },
        { key: 'groupBy', label: `Group ${index + 1} order field`, path: entry.orderBy }
    ]);
}

function tableSortPaths(config) {
    return [{ key: 'sortBy', label: 'Default sort field', path: config.sortBy }];
}

/** Table widget steps, in order (mirrors a report builder). */
export const TABLE_STEPS = [
    dataStep('table', {
        intro: 'Choose the object whose records the table lists, one row per record.',
        example: 'Opportunity: one row per open Opportunity, without the Closed Lost ones.'
    }),
    step('table', {
        name: 'columns',
        label: 'Columns',
        required: true,
        errorKeys: ['columns', 'bucketFields'],
        summary: tableColumnsSummary,
        extraErrors: (config, context) =>
            fieldsOnObjectErrors(config, context, allPaths(tableColumnPaths, bucketRulePaths)),
        intro: 'Each column shows a field of the record or of a parent record up to five lookups away, or a Bucket field.',
        example: 'Name, Account.Name, Amount shown as a Data bar, and Close Date.'
    }),
    step('table', {
        name: 'grouping',
        label: 'Grouping',
        required: false,
        errorKeys: ['groupBy', 'childRelationship'],
        retired: [{ message: CHILD_ROWS_REMOVED_MESSAGE, keys: ['childRelationship'] }],
        summary: tableGroupingSummary,
        extraErrors: (config, context) => fieldsOnObjectErrors(config, context, tableGroupPaths),
        intro: 'Group the rows by up to two fields. Turn Detail rows off to show only the Group rows: an aggregated table.',
        example: 'Group by Account, then by Stage: the Opportunities of each Account, split by Stage.'
    }),
    step('table', {
        name: 'summaries',
        label: 'Summaries',
        required: false,
        errorKeys: ['summaries'],
        summary: tableSummariesSummary,
        intro: 'Add a Total row with Stacked summaries per numeric column, and Subtotals closing each group.',
        example: 'Sum and Average of Amount in the Total row and in each Account’s Subtotal.'
    }),
    step('table', {
        name: 'display',
        label: 'Display',
        required: false,
        errorKeys: ['sortBy', 'pageSize', 'rowLimit'],
        summary: tableDisplaySummary,
        extraErrors: (config, context) => fieldsOnObjectErrors(config, context, tableSortPaths),
        intro: 'Set the default sort, how many rows load per page, and an optional Row limit.',
        example: 'Top 10 Opportunities by Amount, highest first.'
    }),
    step('table', {
        name: 'rowActions',
        label: 'Row actions',
        required: false,
        errorKeys: ['rowActions'],
        summary: tableRowActionsSummary,
        extraErrors: (config, context) => fieldsOnObjectErrors(config, context, rowActionPaths),
        intro: 'Row actions open, edit or create a record, or run a Screen Flow, from the row’s menu.',
        example: 'Edit the Opportunity, or create a Task with WhatId set from the row’s Id.'
    }),
    filterBindingsStep('table')
];

// ---- Filter widget -------------------------------------------------------------------------------------------------

const RECORD_CONTEXT_MODE_LABELS = { IMPLICIT: 'Implicit', LOCKED: 'Locked', DEFAULT: 'Default' };
const PERSISTENCE_LABELS = { SESSION: 'This browser tab', LOCAL: 'This browser', NONE: 'Not remembered' };

/** `3 filters · 1 section · Currency picker`, or `None`. A saved Board-level `currencyPicker` counts as the item. */
function filterItemsSummary(config) {
    const items = filterItemsOf(config).filter(isPlainObject);
    const sections = items.filter((item) => item.type === 'section').length;
    const hasPicker = items.some(isCurrencyPickerItem);
    const filters = items.length - sections - items.filter(isCurrencyPickerItem).length;
    const summary = joinSummary([
        filters ? countLabel(filters, 'filter') : '',
        sections ? countLabel(sections, 'section') : '',
        hasPicker ? 'Currency picker' : ''
    ]);
    return summary || 'None';
}

/** `None`, `1 Bucket field`, or `N Bucket fields`. */
function boardBucketFieldsSummary(config) {
    const count = Array.isArray(config.bucketFields) ? config.bucketFields.length : 0;
    return count ? countLabel(count, 'Bucket field') : 'None';
}

/** The mode, plus the override filterId and host field path when set (`Locked · account · AccountId`). */
function recordContextSummary(config) {
    const recordContext = isPlainObject(config.recordContext) ? config.recordContext : {};
    const mode = recordContext.mode || 'IMPLICIT';
    return joinSummary([
        RECORD_CONTEXT_MODE_LABELS[mode] || mode,
        cleanString(recordContext.overrideFilterId) || '',
        cleanString(recordContext.overrideFieldPath) || ''
    ]);
}

function persistenceSummary(config) {
    const persistence = config.persistence || 'SESSION';
    return PERSISTENCE_LABELS[persistence] || persistence;
}

/** `Config currency EUR`, or `Corporate currency`. */
function currencySummary(config) {
    const code = cleanString(config.configCurrency);
    return code ? `Config currency ${code.toUpperCase()}` : 'Corporate currency';
}

/**
 * Filter widget steps, in order. All are optional: a Filter widget without filters is valid (a Record context or
 * refresh-only bar), so Guided mode never blocks Next; Save still waits for every step to be valid.
 */
export const FILTER_STEPS = [
    step('filter', {
        name: 'filters',
        label: 'Filters',
        required: false,
        errorKeys: ['filters'],
        summary: filterItemsSummary,
        intro: 'The Filter bar shows these items in order: filters that Widgets bind by Filter id, Filter sections that group the filters after them under a heading, and an optional Currency picker.',
        example: 'A Section "Who" with Account and Owner, then a Section "When" (start collapsed) with Close date.'
    }),
    step('filter', {
        name: 'bucketFields',
        label: 'Bucket fields',
        required: false,
        errorKeys: ['bucketFields'],
        summary: boardBucketFieldsSummary,
        intro: 'Board-level Bucket fields sort records into labelled buckets by rules. Every Widget on this Board can group or split by them, and a Bucket filter offers their labels.',
        example: 'Deal size: Large when Amount is at least 100,000, Small otherwise.'
    }),
    step('filter', {
        name: 'recordContext',
        label: 'Record context',
        required: false,
        errorKeys: ['recordContext'],
        summary: recordContextSummary,
        intro: 'What the Board does with the record it sits on (a record page, or a Flow recordId): show only data related to it, or put it into one of the filters. Off a record page this step has no effect.',
        example:
            'On a Case page, Locked with the Account filter and field path AccountId makes every Widget show the Account of that Case only.'
    }),
    step('filter', {
        name: 'persistence',
        label: 'Remember selections',
        required: false,
        errorKeys: ['persistence'],
        summary: persistenceSummary,
        intro: "Choose whether a viewer's filter selections are kept when they come back to the page.",
        example: 'This browser tab: the selections survive a page refresh, and a new tab starts from the defaults.'
    }),
    step('filter', {
        name: 'currency',
        label: 'Currency',
        required: false,
        errorKeys: ['configCurrency'],
        summary: currencySummary,
        intro: 'In a multi-currency org, the Config currency is the currency Admin amounts on this Board are written in (Metric thresholds, Base filter amounts). Viewers pick their Display currency with the Currency picker item in the Filters step.',
        example: 'Thresholds written in EUR; a viewer showing USD sees them converted to USD.'
    })
];

const STEPS_BY_WIDGET_TYPE = { chart: CHART_STEPS, metric: METRIC_STEPS, table: TABLE_STEPS, filter: FILTER_STEPS };

/** The Setup dialog steps of `widgetType` (`[]` for an unknown type). */
export function stepsFor(widgetType) {
    return STEPS_BY_WIDGET_TYPE[widgetType] || [];
}

/**
 * The one-line summary of a panel Config section (`sectionName`), from the step that covers it, or null when no step
 * does.
 */
export function stepSectionSummary(steps, sectionName, config = {}, context = {}) {
    const owner = steps.find((candidate) => candidate.sections && candidate.sections[sectionName]);
    return owner ? owner.sections[sectionName](config, context) : null;
}