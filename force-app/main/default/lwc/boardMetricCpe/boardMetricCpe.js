import { LightningElement, api } from 'lwc';
import {
    AGGREGATE_OPTIONS,
    THRESHOLD_OPERATOR_OPTIONS,
    THRESHOLD_VARIANT_OPTIONS,
    countLabel,
    defaultNotationFor,
    dragRowClass,
    dropRowDrag,
    initialSectionOpen,
    measureSummary,
    moveItem,
    NO_DRAG,
    overRowDrag,
    parseNumber,
    startRowDrag,
    toggleSectionOpen,
    validateCpe,
    widgetSectionStates
} from 'c/boardCpeUtils';

const VALUE_CAPABILITY = {
    COUNT_DISTINCT: '',
    SUM: 'numeric',
    AVG: 'numeric',
    MIN: 'numeric|date',
    MAX: 'numeric|date'
};

/** Config sections of the Metric Config editor (see `sectionStates` in `c/boardCpeUtils`). */
const SECTIONS = [
    {
        name: 'measure',
        errorKeys: ['aggregateFunction', 'valueFieldApiName', 'subtitle', 'format'],
        summary: (cpe) => measureSummary('metric', cpe.config),
        openWhenNew: true
    },
    {
        name: 'thresholds',
        errorKeys: ['thresholds'],
        // `None` or the number of rules.
        summary: (cpe) => (cpe.thresholds.length ? countLabel(cpe.thresholds.length, 'rule') : 'None')
    }
];

// Short labels for the compact threshold row, so the chosen values aren't truncated in the narrow panel. The option
// values (the config contract) come from the shared options.
const OPERATOR_SYMBOLS = { gt: '>', gte: '≥', lt: '<', lte: '≤' };
const VARIANT_LABELS = { success: 'Success', warning: 'Warning', error: 'Error' };
const THRESHOLD_OPERATORS = THRESHOLD_OPERATOR_OPTIONS.map(({ value }) => ({ label: OPERATOR_SYMBOLS[value], value }));
const THRESHOLD_VARIANTS = THRESHOLD_VARIANT_OPTIONS.map(({ value }) => ({ label: VARIANT_LABELS[value], value }));

/**
 * Flow Custom Property Editor for the Board Metric widget: aggregate function + capability-filtered value field,
 * value format, subtitle, and ordered thresholds, inside the shared `c-board-cpe-common` shell (Board, Object, Filter
 * bindings, Base filters, Config JSON). Its own Config sections are Measure and Thresholds.
 */
export default class BoardMetricCpe extends LightningElement {
    @api inputVariables = [];
    @api builderContext = {};
    @api elementInfo = {};

    config = {};
    /** Set once the shell has sent its first `configchange`; section errors wait for it (no flash of errors). */
    configLoaded = false;
    /** Widget default notation, shown by the format editor. */
    defaultNotation = defaultNotationFor('metric');
    aggregateOptions = AGGREGATE_OPTIONS;
    thresholdOperatorOptions = THRESHOLD_OPERATORS;
    thresholdVariantOptions = THRESHOLD_VARIANTS;
    /** Open state of the Config sections: set once on load (a new Widget opens Measure), then by the Admin. */
    sectionOpen = null;
    /** Drag-to-reorder state of the threshold rules (see the drag helpers in c/boardCpeUtils). */
    drag = NO_DRAG;

    connectedCallback() {
        if (!this.sectionOpen) {
            this.sectionOpen = initialSectionOpen(SECTIONS, 'metric', this.inputVariables);
        }
    }

    @api
    validate() {
        return validateCpe(this.shell, 'metric', this.inputVariables);
    }

    get shell() {
        return this.template.querySelector('c-board-cpe-common');
    }

    handleConfigChange(event) {
        this.config = event.detail.config;
        this.configLoaded = true;
    }

    update(patch) {
        this.shell.updateConfig(patch);
    }

    // ---- Config sections -----------------------------------------------------------------------------------------

    get sections() {
        return widgetSectionStates('metric', SECTIONS, this);
    }

    handleSectionToggle(event) {
        this.sectionOpen = toggleSectionOpen(this.sectionOpen, event);
    }

    // ---- Measure -------------------------------------------------------------------------------------------------

    get objectApiName() {
        return this.config.objectApiName || null;
    }

    get aggregateFunction() {
        return this.config.aggregateFunction || 'COUNT';
    }

    get showValueField() {
        return this.aggregateFunction !== 'COUNT';
    }

    get valueCapability() {
        return VALUE_CAPABILITY[this.aggregateFunction] || '';
    }

    get valueFieldHelp() {
        switch (this.aggregateFunction) {
            case 'SUM':
            case 'AVG':
                return 'Numeric fields only.';
            case 'MIN':
            case 'MAX':
                return 'Numeric, date, or time fields.';
            default:
                return 'Any field; counts its distinct non-null values.';
        }
    }

    get valueFieldApiName() {
        return this.config.valueFieldApiName || '';
    }

    get subtitle() {
        return this.config.subtitle || '';
    }

    get format() {
        return this.config.format || null;
    }

    handleAggregate(event) {
        const aggregateFunction = event.detail.value;
        const patch = { aggregateFunction };
        if (aggregateFunction === 'COUNT') {
            patch.valueFieldApiName = null;
        }
        this.update(patch);
    }

    handleValueField(event) {
        this.update({ valueFieldApiName: event.detail.value || null });
    }

    handleSubtitle(event) {
        const value = event.detail.value;
        this.update({ subtitle: value && value.trim() ? value : null });
    }

    handleFormat(event) {
        this.update({ format: event.detail.value });
    }

    // ---- Thresholds ----------------------------------------------------------------------------------------------

    get thresholds() {
        return Array.isArray(this.config.thresholds) ? this.config.thresholds : [];
    }

    get hasThresholds() {
        return this.thresholds.length > 0;
    }

    get thresholdRows() {
        const last = this.thresholds.length - 1;
        return this.thresholds.map((rule, index) => ({
            key: `threshold-${index}`,
            index,
            operatorLabel: `Rule ${index + 1}: when value is`,
            valueLabel: `Rule ${index + 1}: value`,
            variantLabel: `Rule ${index + 1}: status`,
            moveUpLabel: `Move rule ${index + 1} up`,
            moveDownLabel: `Move rule ${index + 1} down`,
            removeLabel: `Remove rule ${index + 1}`,
            operator: rule && rule.operator ? rule.operator : '',
            value: rule && rule.value !== null && rule.value !== undefined ? String(rule.value) : '',
            variant: rule && rule.variant ? rule.variant : '',
            isFirst: index === 0,
            isLast: index === last,
            rowClass: `c-metric-threshold slds-p-vertical_xx-small${dragRowClass(this.drag, index)}`
        }));
    }

    handleThresholdDragStart(event) {
        this.drag = startRowDrag(event);
    }

    handleThresholdDragOver(event) {
        this.drag = overRowDrag(event, this.drag);
    }

    handleThresholdDrop(event) {
        const move = dropRowDrag(event, this.drag);
        this.drag = NO_DRAG;
        if (move) {
            this.setThresholds(moveItem(this.thresholds, move.index, move.offset));
        }
    }

    handleThresholdDragEnd() {
        this.drag = NO_DRAG;
    }

    handleAddThreshold() {
        this.setThresholds([...this.thresholds, { operator: 'gte', value: null, variant: 'success' }]);
    }

    handleRemoveThreshold(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.setThresholds(this.thresholds.filter((rule, position) => position !== index));
    }

    handleMoveThresholdUp(event) {
        this.setThresholds(moveItem(this.thresholds, Number(event.currentTarget.dataset.index), -1));
    }

    handleMoveThresholdDown(event) {
        this.setThresholds(moveItem(this.thresholds, Number(event.currentTarget.dataset.index), 1));
    }

    handleThresholdOperator(event) {
        this.updateThreshold(event, { operator: event.detail.value });
    }

    handleThresholdValue(event) {
        this.updateThreshold(event, { value: parseNumber(event.detail.value) });
    }

    handleThresholdVariant(event) {
        this.updateThreshold(event, { variant: event.detail.value });
    }

    updateThreshold(event, patch) {
        const index = Number(event.target.dataset.index);
        this.setThresholds(
            this.thresholds.map((rule, position) => (position === index ? { ...rule, ...patch } : rule))
        );
    }

    setThresholds(thresholds) {
        this.update({ thresholds: thresholds.length ? thresholds : null });
    }
}