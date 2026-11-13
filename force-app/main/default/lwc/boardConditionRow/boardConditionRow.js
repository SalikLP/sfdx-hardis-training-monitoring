import { LightningElement, api } from 'lwc';
import { DATE_PRESETS } from 'c/boardConfigUtils';
import {
    BASE_FILTER_OPERATOR_OPTIONS,
    LIST_OPERATORS,
    hasText,
    isDatePreset,
    isRelativeDateLiteral
} from 'c/boardCpeUtils';

const CUSTOM_LITERAL = '__CUSTOM__';
const NULL_OPTIONS = [
    { label: 'Is null', value: 'true' },
    { label: 'Is not null', value: 'false' }
];
const LITERAL_OPTIONS = [...DATE_PRESETS, { label: 'Custom literal (e.g. LAST_N_DAYS:45)', value: CUSTOM_LITERAL }];

/** Carries a condition's value over to a new operator (list ↔ scalar, null check, relative date). */
function convertValue(operator, value) {
    if (LIST_OPERATORS.has(operator)) {
        if (Array.isArray(value)) {
            return value;
        }
        return hasText(value) && typeof value !== 'boolean' ? [String(value)] : [];
    }
    if (operator === 'IS_NULL') {
        return true;
    }
    if (operator === 'LITERAL') {
        return isRelativeDateLiteral(value) ? String(value).trim().toUpperCase() : 'TODAY';
    }
    if (Array.isArray(value)) {
        return value.length ? value[0] : null;
    }
    return typeof value === 'boolean' ? null : value;
}

/**
 * One condition of a condition tree (`{ id, fieldPath, operator, value }`): field, operator, and value inputs plus
 * its validation messages. Fires `rowchange` (`detail.condition`, the edited condition) and `rowremove`.
 */
export default class BoardConditionRow extends LightningElement {
    @api condition;
    /** Object the field picker starts from. */
    @api objectApiName;
    /** Validation messages of this condition. */
    @api errors;

    operatorOptions = BASE_FILTER_OPERATOR_OPTIONS;
    nullOptions = NULL_OPTIONS;
    literalOptions = LITERAL_OPTIONS;

    /** True while the relative date is typed as a custom literal. */
    customLiteral = false;

    get safe() {
        return this.condition || {};
    }

    get fieldPath() {
        return this.safe.fieldPath || '';
    }

    get operator() {
        return this.safe.operator || 'EQ';
    }

    get isList() {
        return LIST_OPERATORS.has(this.operator);
    }

    get isNull() {
        return this.operator === 'IS_NULL';
    }

    get isLiteral() {
        return this.operator === 'LITERAL';
    }

    get isScalar() {
        return !this.isList && !this.isNull && !this.isLiteral;
    }

    get literal() {
        const value = this.safe.value;
        return typeof value === 'string' ? value.trim().toUpperCase() : '';
    }

    get isCustomLiteral() {
        return this.isLiteral && (this.customLiteral || (this.literal !== '' && !isDatePreset(this.literal)));
    }

    get literalSelection() {
        return this.isCustomLiteral ? CUSTOM_LITERAL : this.literal;
    }

    get scalarValue() {
        const value = this.safe.value;
        if (Array.isArray(value)) {
            return value.join(', ');
        }
        return value === null || value === undefined ? '' : String(value);
    }

    get nullValue() {
        const value = this.safe.value;
        return value === false || value === 'false' ? 'false' : 'true';
    }

    get errorItems() {
        return (Array.isArray(this.errors) ? this.errors : []).map((message, position) => ({
            key: `error-${position}`,
            message
        }));
    }

    get hasErrors() {
        return this.errorItems.length > 0;
    }

    // ---- Edits ---------------------------------------------------------------------------------------------------

    handleField(event) {
        const value = event.detail.value;
        this.update({ fieldPath: hasText(value) ? value : '' });
    }

    handleOperator(event) {
        const operator = event.detail.value;
        this.customLiteral = false;
        this.update({ operator, value: convertValue(operator, this.safe.value) });
    }

    handleValue(event) {
        const value = event.detail.value;
        this.update({ value: hasText(value) ? value : null });
    }

    handleList(event) {
        const values = String(event.detail.value || '')
            .split(',')
            .map((item) => item.trim())
            .filter(Boolean);
        this.update({ value: values });
    }

    handleNull(event) {
        this.update({ value: event.detail.value !== 'false' });
    }

    handleLiteral(event) {
        const selection = event.detail.value;
        if (selection === CUSTOM_LITERAL) {
            this.customLiteral = true;
            return;
        }
        this.customLiteral = false;
        this.update({ value: selection });
    }

    handleCustomLiteral(event) {
        const value = String(event.detail.value || '')
            .trim()
            .toUpperCase();
        this.update({ value: value || null });
    }

    handleRemove() {
        this.dispatchEvent(new CustomEvent('rowremove'));
    }

    update(patch) {
        this.dispatchEvent(new CustomEvent('rowchange', { detail: { condition: { ...this.safe, ...patch } } }));
    }
}