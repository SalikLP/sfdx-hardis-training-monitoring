import { LightningElement, api } from 'lwc';
import { FORMAT_STYLE_OPTIONS, NOTATION_OPTIONS, applyPatch, isPlainObject, parseNumber } from 'c/boardCpeUtils';

const DEFAULT = '';
const STYLE_OPTIONS = [{ label: 'Default (number)', value: DEFAULT }, ...FORMAT_STYLE_OPTIONS];

/**
 * ValueFormatConfig editor (`formatStyle`, `notation`, fraction digits, `currencyCode`, `prefix`, `suffix`) shared by
 * the Metric, Bar Chart, and Table column CPEs. Fires a non-bubbling `change` event with `detail.value`: the edited
 * format, or null once every setting is back to its default.
 */
export default class BoardCpeFormatEditor extends LightningElement {
    @api label = 'Value format';
    /** Widget default notation shown in the Notation picker: `standard` (Bar/Table) or `compact` (Metric). */
    @api defaultNotation = 'standard';

    styleOptions = STYLE_OPTIONS;
    _value = {};

    /** Current ValueFormatConfig (null/undefined = defaults). */
    @api
    get value() {
        return this._value;
    }
    set value(format) {
        this._value = isPlainObject(format) ? { ...format } : {};
    }

    get notationOptions() {
        const fallback = this.defaultNotation === 'compact' ? 'compact' : 'standard';
        return [{ label: `Default (${fallback})`, value: DEFAULT }, ...NOTATION_OPTIONS];
    }

    get formatStyle() {
        return this._value.formatStyle || DEFAULT;
    }

    get notation() {
        return this._value.notation || DEFAULT;
    }

    get isCurrency() {
        return this._value.formatStyle === 'currency';
    }

    get minimumFractionDigits() {
        return this.numberText(this._value.minimumFractionDigits);
    }

    get maximumFractionDigits() {
        return this.numberText(this._value.maximumFractionDigits);
    }

    get currencyCode() {
        return this._value.currencyCode || '';
    }

    get prefix() {
        return this._value.prefix || '';
    }

    get suffix() {
        return this._value.suffix || '';
    }

    numberText(value) {
        return value === null || value === undefined ? '' : String(value);
    }

    handleStyle(event) {
        const formatStyle = event.detail.value || null;
        this.update({ formatStyle, currencyCode: formatStyle === 'currency' ? this._value.currencyCode : null });
    }

    handleNotation(event) {
        this.update({ notation: event.detail.value || null });
    }

    handleDigits(event) {
        this.update({ [event.target.dataset.name]: parseNumber(event.detail.value) });
    }

    handleCurrency(event) {
        const code = String(event.detail.value || '')
            .trim()
            .toUpperCase();
        this.update({ currencyCode: code || null });
    }

    handleAffix(event) {
        const text = event.detail.value;
        this.update({ [event.target.dataset.name]: text === '' || text === undefined ? null : text });
    }

    update(patch) {
        const next = applyPatch(this._value, patch);
        this._value = next;
        this.dispatchEvent(new CustomEvent('change', { detail: { value: Object.keys(next).length ? next : null } }));
    }
}