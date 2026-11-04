import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { DATE_PRESETS } from 'c/boardConfigUtils';
import {
    BASE_FILTER_OPERATOR_OPTIONS,
    ConfigDialogMixin,
    LIST_OPERATORS,
    baseFilterErrorsByIndex,
    baseFilterSummary,
    cleanString,
    hasText,
    isDatePreset,
    isPlainObject,
    isRelativeDateLiteral,
    nextSequentialId
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
 * Base filters Config dialog: a large `LightningModal` that edits a draft of a data Widget's `baseFilters`
 * (master-detail: ordered conditions on the left, the selected condition's field, operator, and value on the right).
 * Open it with `openConfigDialog(BoardBaseFilterDialog, { label, description, value: baseFilters, objectApiName })`.
 *
 * Closes with `{ action: 'save', draft: baseFilters }` or `{ action: 'dismiss' }`. Save stays disabled while any
 * draft condition breaks the Base filter validation rules (`baseFilterErrorsByIndex`).
 */
export default class BoardBaseFilterDialog extends ConfigDialogMixin(LightningModal) {
    /** The Widget's `baseFilters`, already deep-copied by `openConfigDialog`. */
    @api value;
    /** Object the field picker starts from. */
    @api objectApiName;

    conditions = [];
    rowKeyPrefix = 'condition';

    operatorOptions = BASE_FILTER_OPERATOR_OPTIONS;
    nullOptions = NULL_OPTIONS;
    literalOptions = LITERAL_OPTIONS;

    /** Row keys whose relative date is being typed as a custom literal. */
    _customLiteralKeys = [];

    // ---- Draft (ConfigDialogMixin) -------------------------------------------------------------------------------

    initDraft(value) {
        const conditions = Array.isArray(value) ? value : [];
        this.conditions = this.withIds(conditions.map((condition) => (isPlainObject(condition) ? condition : {})));
    }

    get draftItems() {
        return this.conditions;
    }

    setDraftItems(conditions, change) {
        if (change) {
            this._customLiteralKeys = this._customLiteralKeys.filter((key) => key !== change.removedKey);
        }
        this.conditions = conditions;
    }

    get draft() {
        return this.conditions;
    }

    /** Gives conditions without an id (or with a duplicate one, e.g. hand-edited JSON) a fresh `bfN` id. */
    withIds(conditions) {
        const seen = new Set();
        const result = [];
        conditions.forEach((condition) => {
            const id = cleanString(condition.id);
            // Fresh ids count the ones already handed out, so they never repeat.
            const next =
                id && !seen.has(id)
                    ? condition
                    : { ...condition, id: nextSequentialId([...conditions, ...result], 'bf') };
            seen.add(next.id);
            result.push(next);
        });
        return result;
    }

    // ---- Validation and master list ------------------------------------------------------------------------------

    /** Messages per draft condition, from the shared Base filter validation rules. */
    get errorsByIndex() {
        return baseFilterErrorsByIndex(this.conditions);
    }

    get masterItems() {
        const errors = this.errorsByIndex;
        return this.conditions.map((condition, index) => {
            const summary = baseFilterSummary(condition, index);
            return {
                key: this._rowKeys[index],
                label: summary.valueText ? `${summary.label}: ${summary.valueText}` : summary.label,
                meta: summary.operatorLabel,
                hasError: errors[index].length > 0
            };
        });
    }

    // ---- Selected condition --------------------------------------------------------------------------------------

    get row() {
        const index = this.selectedIndex;
        return index < 0 ? null : this.rowFor(this.conditions[index], index);
    }

    rowFor(condition, index) {
        const key = this._rowKeys[index];
        const operator = condition.operator || 'EQ';
        const value = condition.value;
        const isList = LIST_OPERATORS.has(operator);
        const isNull = operator === 'IS_NULL';
        const isLiteral = operator === 'LITERAL';
        const literal = typeof value === 'string' ? value.trim().toUpperCase() : '';
        const isCustomLiteral =
            isLiteral && (this._customLiteralKeys.includes(key) || (literal !== '' && !isDatePreset(literal)));
        let scalarValue = '';
        if (Array.isArray(value)) {
            scalarValue = value.join(', ');
        } else if (value !== null && value !== undefined) {
            scalarValue = String(value);
        }
        const errors = this.errorsByIndex[index].map((message, position) => ({
            key: `${key}-error-${position}`,
            message
        }));
        return {
            key,
            id: condition.id,
            index,
            title: `Condition ${index + 1}`,
            errors,
            hasErrors: errors.length > 0,
            fieldPath: condition.fieldPath || '',
            operator,
            isList,
            isNull,
            isLiteral,
            isCustomLiteral,
            isScalar: !isList && !isNull && !isLiteral,
            scalarValue,
            nullValue: value === false || value === 'false' ? 'false' : 'true',
            literalSelection: isCustomLiteral ? CUSTOM_LITERAL : literal,
            literalValue: literal
        };
    }

    // ---- Draft edits ---------------------------------------------------------------------------------------------

    handleAdd() {
        this.addDraftItem({ id: nextSequentialId(this.conditions, 'bf'), fieldPath: '', operator: 'EQ', value: null });
    }

    handleField(event) {
        const value = event.detail.value;
        this.updateCondition(event.target.dataset.index, { fieldPath: hasText(value) ? value : '' });
    }

    handleOperator(event) {
        const index = Number(event.target.dataset.index);
        const operator = event.detail.value;
        this.forgetCustomLiteral(index);
        this.updateCondition(index, { operator, value: convertValue(operator, this.conditions[index].value) });
    }

    handleValue(event) {
        const value = event.detail.value;
        this.updateCondition(event.target.dataset.index, { value: hasText(value) ? value : null });
    }

    handleList(event) {
        const values = String(event.detail.value || '')
            .split(',')
            .map((item) => item.trim())
            .filter(Boolean);
        this.updateCondition(event.target.dataset.index, { value: values });
    }

    handleNull(event) {
        this.updateCondition(event.target.dataset.index, { value: event.detail.value !== 'false' });
    }

    handleLiteral(event) {
        const index = Number(event.target.dataset.index);
        const selection = event.detail.value;
        if (selection === CUSTOM_LITERAL) {
            const key = this._rowKeys[index];
            if (!this._customLiteralKeys.includes(key)) {
                this._customLiteralKeys = [...this._customLiteralKeys, key];
            }
            return;
        }
        this.forgetCustomLiteral(index);
        this.updateCondition(index, { value: selection });
    }

    handleCustomLiteral(event) {
        const value = String(event.detail.value || '')
            .trim()
            .toUpperCase();
        this.updateCondition(event.target.dataset.index, { value: value || null });
    }

    forgetCustomLiteral(index) {
        const key = this._rowKeys[index];
        this._customLiteralKeys = this._customLiteralKeys.filter((item) => item !== key);
    }

    updateCondition(index, patch) {
        const position = Number(index);
        const next = { ...this.conditions[position], ...patch };
        this.conditions = this.conditions.map((condition, i) => (i === position ? next : condition));
    }
}