import { LightningElement, api } from 'lwc';
import { SLDS_NAMED_COLOURS, contrastWarning, fixedColourErrors, namedColourOf } from 'c/boardChartColours';

const CUSTOM = 'custom';
const COLOUR_OPTIONS = [...SLDS_NAMED_COLOURS, { label: 'Custom hex colour…', value: CUSTOM }];

/**
 * Edits a Chart widget's fixed colours (`fixedColours`, see `c/boardChartColours`): each pins a colour to a stored
 * value (picklist API value or record Id). The colour is picked from the named SLDS colour set; a custom hex is the
 * advanced option, with a warning when its contrast is below 3:1 on the light or dark surface.
 *
 * Fires `change` with `detail.value`, the whole edited list, after every edit.
 */
export default class BoardFixedColourEditor extends LightningElement {
    colourOptions = COLOUR_OPTIONS;
    entries = [];
    /** Rows switched to a custom hex while their colour is still a named one. */
    customRows = new Set();

    @api
    get value() {
        return this.entries;
    }

    set value(value) {
        this.entries = Array.isArray(value) ? value : [];
    }

    get hasEntries() {
        return this.entries.length > 0;
    }

    get errors() {
        return fixedColourErrors(this.entries);
    }

    get hasErrors() {
        return this.errors.length > 0;
    }

    get rows() {
        return this.entries.map((entry, index) => {
            const safe = entry && typeof entry === 'object' ? entry : {};
            const colour = typeof safe.colour === 'string' ? safe.colour : '';
            const isCustom = this.customRows.has(index) || !namedColourOf(colour);
            return {
                key: `fixed-${index}`,
                index,
                value: safe.value ?? '',
                colour,
                choice: isCustom ? CUSTOM : namedColourOf(colour).value,
                isCustom,
                warning: isCustom ? contrastWarning(colour) : null,
                swatchStyle: `background-color: ${colour || 'transparent'}`
            };
        });
    }

    handleAdd() {
        const used = this.entries.map((entry) => String(entry?.colour || '').toLowerCase());
        const free = SLDS_NAMED_COLOURS.find((option) => !used.includes(option.value)) || SLDS_NAMED_COLOURS[0];
        this.commit([...this.entries, { value: '', colour: free.value }]);
    }

    handleRemove(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.customRows = new Set(
            [...this.customRows].filter((row) => row !== index).map((row) => (row > index ? row - 1 : row))
        );
        this.commit(this.entries.filter((entry, position) => position !== index));
    }

    handleValue(event) {
        const value = event.detail.value ? String(event.detail.value) : '';
        this.updateEntry(event, (entry) => ({ ...entry, value }));
    }

    handleColourChoice(event) {
        const index = Number(event.currentTarget.dataset.index);
        const choice = event.detail.value;
        const custom = new Set(this.customRows);
        if (choice === CUSTOM) {
            custom.add(index);
            this.customRows = custom;
            return;
        }
        custom.delete(index);
        this.customRows = custom;
        this.updateEntry(event, (entry) => ({ ...entry, colour: choice }));
    }

    handleHex(event) {
        const colour = event.detail.value ? String(event.detail.value).trim() : '';
        this.updateEntry(event, (entry) => ({ ...entry, colour }));
    }

    updateEntry(event, update) {
        const index = Number(event.currentTarget.dataset.index);
        this.commit(this.entries.map((entry, position) => (position === index ? update(entry || {}) : entry)));
    }

    commit(entries) {
        this.entries = entries;
        this.dispatchEvent(new CustomEvent('change', { detail: { value: entries } }));
    }
}