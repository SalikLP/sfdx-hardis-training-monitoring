import { LightningElement, api } from 'lwc';
import BoardCpeConfigDialog from 'c/boardCpeConfigDialog';
import {
    AGGREGATE_OPTIONS,
    DIALOG_SAVE,
    THRESHOLD_OPERATOR_OPTIONS,
    THRESHOLD_VARIANT_OPTIONS,
    isPlainObject,
    moveItem,
    openConfigDialog,
    parseNumber,
    validateCpe
} from 'c/boardCpeUtils';

function thresholdsDraftError(draft) {
    if (!Array.isArray(draft)) {
        return 'Thresholds must be a JSON array.';
    }
    return draft.every(isPlainObject) ? null : 'Each threshold rule must be an object.';
}

const VALUE_CAPABILITY = {
    COUNT_DISTINCT: '',
    SUM: 'numeric',
    AVG: 'numeric',
    MIN: 'numeric|date',
    MAX: 'numeric|date'
};

/**
 * Flow Custom Property Editor for the Board Metric widget: aggregate function + capability-filtered value field,
 * value format, subtitle, and ordered thresholds, inside the shared `c-board-cpe-common` shell (Board, Object, Filter
 * bindings, Base filters, Config JSON).
 */
export default class BoardMetricCpe extends LightningElement {
    @api inputVariables = [];
    @api builderContext = {};
    @api elementInfo = {};

    config = {};
    aggregateOptions = AGGREGATE_OPTIONS;
    thresholdOperatorOptions = THRESHOLD_OPERATOR_OPTIONS;
    thresholdVariantOptions = THRESHOLD_VARIANT_OPTIONS;

    @api
    validate() {
        return validateCpe(this.shell, 'metric', this.inputVariables);
    }

    get shell() {
        return this.template.querySelector('c-board-cpe-common');
    }

    handleConfigChange(event) {
        this.config = event.detail.config;
    }

    update(patch) {
        this.shell.updateConfig(patch);
    }

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
            title: `Rule ${index + 1}`,
            operator: rule && rule.operator ? rule.operator : '',
            value: rule && rule.value !== null && rule.value !== undefined ? String(rule.value) : '',
            variant: rule && rule.variant ? rule.variant : '',
            isFirst: index === 0,
            isLast: index === last
        }));
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

    /** Ticket 07 spike: edit the thresholds in a Config dialog; Save applies one config change, dismiss none. */
    async handleEditThresholdsInDialog() {
        const result = await openConfigDialog(BoardCpeConfigDialog, {
            label: 'Edit thresholds',
            description: 'Edit the Metric threshold rules',
            value: this.thresholds,
            validator: thresholdsDraftError
        });
        if (result.action === DIALOG_SAVE) {
            this.setThresholds(result.draft);
        }
    }

    setThresholds(thresholds) {
        this.update({ thresholds: thresholds.length ? thresholds : null });
    }
}