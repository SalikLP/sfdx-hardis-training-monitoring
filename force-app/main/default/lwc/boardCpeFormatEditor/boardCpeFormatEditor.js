import { LightningElement, api } from 'lwc';
import { FORMAT_STYLE_OPTIONS, NOTATION_OPTIONS, applyPatch, isPlainObject, parseNumber } from 'c/boardCpeUtils';

const DEFAULT = '';
const STYLE_OPTIONS = [{ label: 'Default (number)', value: DEFAULT }, ...FORMAT_STYLE_OPTIONS];
const STYLE_LABELS = Object.fromEntries(FORMAT_STYLE_OPTIONS.map((option) => [option.value, option.label]));

function isSet(value) {
    return value !== null && value !== undefined && value !== '';
}

/** Explicit values equal to the default (`formatStyle: 'number'`, the Widget's own notation) don't count as custom. */
function isCustomized(format, defaultNotation) {
    return Object.entries(format).some(([key, value]) => {
        if (!isSet(value) || key === 'currencyCode') {
            return false;
        }
        if (key === 'formatStyle') {
            return value !== 'number';
        }
        if (key === 'notation') {
            return value !== defaultNotation;
        }
        return true;
    });
}

/**
 * ValueFormatConfig editor (`formatStyle`, `notation`, fraction digits, `prefix`, `suffix`) shared by the Metric,
 * Chart, and Table column CPEs. There is no currency code: currency amounts are shown in the Board's Display currency
 * (a `currencyCode` saved by an older version is kept; Widgets format with the ISO code Apex returns instead). Collapsed, it shows one summary line (`Number format: Default (compact)`)
 * with a "Customize" link that reveals the controls; it starts expanded when any setting differs from the default
 * (an explicit default such as the Widget's own notation does not count).
 * Fires a non-bubbling `change` event with `detail.value`: the edited format, or null once every setting is back to its
 * default.
 */
export default class BoardCpeFormatEditor extends LightningElement {
    @api label = 'Number format';
    /** Widget default notation shown in the Notation picker: `standard` (Bar/Table) or `compact` (Metric). */
    @api defaultNotation = 'standard';

    styleOptions = STYLE_OPTIONS;
    _value = {};
    /**
     * Open state chosen by the Admin (toggle, or editing a control), or null while it still follows the value: then
     * the controls show whenever a setting differs from the default. Once set, value updates never override it.
     */
    _expandedChoice = null;

    /** Current ValueFormatConfig (null/undefined = defaults). */
    @api
    get value() {
        return this._value;
    }
    set value(format) {
        this._value = isPlainObject(format) ? { ...format } : {};
    }

    get expanded() {
        return this._expandedChoice === null ? isCustomized(this._value, this.fallbackNotation) : this._expandedChoice;
    }

    get summaryLine() {
        const style = STYLE_LABELS[this._value.formatStyle] || 'Default';
        const notation = this._value.notation || this.fallbackNotation;
        return `${this.label}: ${style} (${notation})`;
    }

    get toggleLabel() {
        return this.expanded ? 'Hide' : 'Customize';
    }

    get ariaExpanded() {
        return String(this.expanded);
    }

    get fallbackNotation() {
        return this.defaultNotation === 'compact' ? 'compact' : 'standard';
    }

    get notationOptions() {
        return [{ label: `Default (${this.fallbackNotation})`, value: DEFAULT }, ...NOTATION_OPTIONS];
    }

    get formatStyle() {
        return this._value.formatStyle || DEFAULT;
    }

    get notation() {
        return this._value.notation || DEFAULT;
    }

    get minimumFractionDigits() {
        return this.numberText(this._value.minimumFractionDigits);
    }

    get maximumFractionDigits() {
        return this.numberText(this._value.maximumFractionDigits);
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

    handleToggle() {
        this._expandedChoice = !this.expanded;
    }

    handleStyle(event) {
        const formatStyle = event.detail.value || null;
        this.update({ formatStyle });
    }

    handleNotation(event) {
        this.update({ notation: event.detail.value || null });
    }

    handleDigits(event) {
        this.update({ [event.target.dataset.name]: parseNumber(event.detail.value) });
    }

    handleAffix(event) {
        const text = event.detail.value;
        this.update({ [event.target.dataset.name]: text === '' || text === undefined ? null : text });
    }

    update(patch) {
        // Editing keeps the controls open, even when the value goes back to the default.
        this._expandedChoice = true;
        const next = applyPatch(this._value, patch);
        this._value = next;
        this.dispatchEvent(new CustomEvent('change', { detail: { value: Object.keys(next).length ? next : null } }));
    }
}