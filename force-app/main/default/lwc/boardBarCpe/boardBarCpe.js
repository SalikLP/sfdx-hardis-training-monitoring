import { LightningElement, api } from 'lwc';
import {
    AGGREGATE_OPTIONS,
    BAR_SORT_OPTIONS,
    DATE_FIELD_TYPES,
    DATE_GRANULARITY_OPTIONS,
    PICKLIST_FIELD_TYPES,
    ROLLUP_FUNCTIONS,
    parseNumber,
    resolveFieldDescribe,
    validateCpe
} from 'c/boardCpeUtils';

const STACK_MODE_OPTIONS = [
    { label: 'Stacked', value: 'stacked' },
    { label: 'Grouped', value: 'grouped' }
];
const LEGEND_OPTIONS = [
    { label: 'Auto (only when stacked)', value: 'auto' },
    { label: 'Top', value: 'top' },
    { label: 'Bottom', value: 'bottom' },
    { label: 'Hidden', value: 'hidden' }
];
const SORT_LABELS = new Map(BAR_SORT_OPTIONS.map((option) => [option.value, option.label]));
const CHRONOLOGICAL_SORTS = ['CHRONOLOGICAL_ASC', 'CHRONOLOGICAL_DESC'];

/**
 * Flow Custom Property Editor for the Board Bar Chart widget: Group by (+ date granularity for Date/DateTime fields),
 * optional Stack by, measure, sorting and overflow, legend, data labels, and value format, inside the shared
 * `c-board-cpe-common` shell (Board, Object, orientation, Filter bindings, Base filters, Config JSON).
 */
export default class BoardBarCpe extends LightningElement {
    @api inputVariables = [];
    @api builderContext = {};
    @api elementInfo = {};

    config = {};
    /** `Schema.DisplayType` of the Group by leaf field, once known. */
    groupByType = null;

    aggregateOptions = AGGREGATE_OPTIONS;
    granularityOptions = DATE_GRANULARITY_OPTIONS;
    stackModeOptions = STACK_MODE_OPTIONS;
    legendOptions = LEGEND_OPTIONS;

    _typedKey = null;

    @api
    validate() {
        return validateCpe(this.shell, 'bar', this.inputVariables);
    }

    get shell() {
        return this.template.querySelector('c-board-cpe-common');
    }

    handleConfigChange(event) {
        this.config = event.detail.config;
        this.resolveGroupByType();
    }

    update(patch) {
        this.shell.updateConfig(patch);
    }

    groupByKey(objectApiName, groupByField) {
        return objectApiName && groupByField ? `${objectApiName}::${groupByField}` : null;
    }

    /** Describes the saved Group by path (e.g. after reopening the editor) to decide which options apply. */
    resolveGroupByType() {
        const objectApiName = this.objectApiName;
        const groupByField = this.groupByField;
        const key = this.groupByKey(objectApiName, groupByField);
        if (key === this._typedKey) {
            return;
        }
        this._typedKey = key;
        this.groupByType = null;
        if (!key) {
            return;
        }
        resolveFieldDescribe(objectApiName, groupByField)
            .then((field) => {
                if (this._typedKey === key) {
                    this.groupByType = field ? field.dataType : null;
                }
            })
            .catch(() => {
                // Unknown type: every option stays available and the server validates at runtime.
            });
    }

    get objectApiName() {
        return this.config.objectApiName || null;
    }

    // ---- Dimensions ----------------------------------------------------------------------------------------------

    get groupByField() {
        return this.config.groupByField || '';
    }

    get isDateGroup() {
        return DATE_FIELD_TYPES.includes(this.groupByType);
    }

    get showGranularity() {
        return Boolean(this.groupByField) && (this.isDateGroup || Boolean(this.config.dateGranularity));
    }

    get dateGranularity() {
        return this.config.dateGranularity || 'DAY';
    }

    get stackByField() {
        return this.config.stackByField || '';
    }

    get hasStack() {
        return Boolean(this.config.stackByField);
    }

    get stackMode() {
        return this.config.stackMode === 'grouped' ? 'grouped' : 'stacked';
    }

    get maxSeries() {
        return this.config.maxSeries ?? '';
    }

    get includeNullBucket() {
        return this.config.includeNullBucket !== false;
    }

    handleGroupBy(event) {
        const groupByField = event.detail.value || null;
        const dataType = event.detail.field ? event.detail.field.dataType : null;
        this._typedKey = this.groupByKey(this.objectApiName, groupByField);
        this.groupByType = groupByField ? dataType : null;
        const patch = { groupByField };
        const isDate = DATE_FIELD_TYPES.includes(this.groupByType);
        if (!isDate) {
            patch.dateGranularity = null;
        }
        const sortBy = this.config.sortBy;
        if (
            (CHRONOLOGICAL_SORTS.includes(sortBy) && !isDate) ||
            (sortBy === 'PICKLIST_ORDER' && !PICKLIST_FIELD_TYPES.includes(this.groupByType))
        ) {
            patch.sortBy = null;
        }
        this.update(patch);
    }

    handleGranularity(event) {
        this.update({ dateGranularity: event.detail.value });
    }

    handleStackBy(event) {
        const stackByField = event.detail.value || null;
        const patch = { stackByField };
        if (!stackByField) {
            patch.stackMode = null;
            patch.maxSeries = null;
        }
        this.update(patch);
    }

    handleStackMode(event) {
        this.update({ stackMode: event.detail.value });
    }

    handleMaxSeries(event) {
        this.update({ maxSeries: parseNumber(event.detail.value) });
    }

    handleIncludeNull(event) {
        this.update({ includeNullBucket: event.detail.checked ? null : false });
    }

    // ---- Measure -------------------------------------------------------------------------------------------------

    get aggregateFunction() {
        return this.config.aggregateFunction || 'COUNT';
    }

    get showValueField() {
        return this.aggregateFunction !== 'COUNT';
    }

    get valueCapability() {
        return this.aggregateFunction === 'COUNT_DISTINCT' ? '' : 'numeric';
    }

    get valueFieldApiName() {
        return this.config.valueFieldApiName || '';
    }

    handleAggregate(event) {
        const aggregateFunction = event.detail.value;
        const patch = { aggregateFunction };
        if (aggregateFunction === 'COUNT') {
            patch.valueFieldApiName = null;
        }
        if (!ROLLUP_FUNCTIONS.includes(aggregateFunction) && this.config.overflowMode === 'OTHER') {
            patch.overflowMode = 'TRUNCATE';
        }
        this.update(patch);
    }

    handleValueField(event) {
        this.update({ valueFieldApiName: event.detail.value || null });
    }

    // ---- Display -------------------------------------------------------------------------------------------------

    get sortOptions() {
        const values = ['VALUE_DESC', 'VALUE_ASC', 'LABEL_ASC', 'LABEL_DESC'];
        if (PICKLIST_FIELD_TYPES.includes(this.groupByType)) {
            values.push('PICKLIST_ORDER');
        }
        if (this.showGranularity) {
            values.push(...CHRONOLOGICAL_SORTS);
        }
        const current = this.config.sortBy;
        if (current && !values.includes(current)) {
            values.push(current);
        }
        const fallback = this.showGranularity ? 'chronological, oldest first' : 'value, high to low';
        return [
            { label: `Default (${fallback})`, value: '' },
            ...values.map((value) => ({ label: SORT_LABELS.get(value) || value, value }))
        ];
    }

    get sortBy() {
        return this.config.sortBy || '';
    }

    get maxBars() {
        return this.config.maxBars ?? '';
    }

    get overflowOptions() {
        const options = [{ label: 'Hide extra bars', value: 'TRUNCATE' }];
        if (ROLLUP_FUNCTIONS.includes(this.aggregateFunction)) {
            options.push({ label: 'Combine into "Other"', value: 'OTHER' });
        }
        return options;
    }

    get overflowMode() {
        return this.config.overflowMode === 'OTHER' ? 'OTHER' : 'TRUNCATE';
    }

    get overflowHelp() {
        return ROLLUP_FUNCTIONS.includes(this.aggregateFunction)
            ? 'Bars beyond the maximum are hidden or summed into one "Other" bar.'
            : `An "Other" bar is only available for COUNT and SUM; ${this.aggregateFunction} hides extra bars.`;
    }

    get legendPosition() {
        return this.config.legendPosition || 'auto';
    }

    get showDataLabels() {
        return this.config.showDataLabels === true;
    }

    get subtitle() {
        return this.config.subtitle || '';
    }

    get format() {
        return this.config.format || null;
    }

    handleSortBy(event) {
        this.update({ sortBy: event.detail.value || null });
    }

    handleMaxBars(event) {
        this.update({ maxBars: parseNumber(event.detail.value) });
    }

    handleOverflow(event) {
        this.update({ overflowMode: event.detail.value });
    }

    handleLegend(event) {
        this.update({ legendPosition: event.detail.value });
    }

    handleDataLabels(event) {
        this.update({ showDataLabels: event.detail.checked });
    }

    handleSubtitle(event) {
        const value = event.detail.value;
        this.update({ subtitle: value && value.trim() ? value : null });
    }

    handleFormat(event) {
        this.update({ format: event.detail.value });
    }
}