import { LightningElement, api } from 'lwc';
import { illustrationPaths } from './illustrations';

let instanceCount = 0;

/**
 * Picture tiles: a single choice shown as small pictures of what each option looks like (Setup dialog, ADR 0002).
 * A drop-in for a `lightning-radio-group`: a fieldset of native radios, so it is keyboard operable (Tab into the
 * group, arrow keys move the choice) and read as a radio group with the option labels as names.
 *
 * - `label`: the group label (its legend); `fieldLevelHelp`: help text shown next to it
 * - `options`: `[{ label, value, illustration, disabled }]`; `illustration` is the name of a shipped illustration
 *   (see `illustrations.js`) or paths given as data, `[{ d, tone }]`; a tile without one shows its label only
 * - `value`: the selected option's value; `disabled`: disables every tile
 *
 * Fires `change` with `detail.value` when the Admin picks a tile.
 */
export default class BoardPictureTiles extends LightningElement {
    @api label;
    @api fieldLevelHelp;
    @api options = [];
    @api value;
    @api disabled = false;

    /** One radio group per picker, so arrow keys stay inside it (the synthetic shadow shares the document). */
    name = `c-picture-tiles-${++instanceCount}`;

    get tiles() {
        return (Array.isArray(this.options) ? this.options : []).map((option, index) => {
            const checked = option.value === this.value;
            const paths = illustrationPaths(option.illustration).map((path, pathIndex) => ({
                key: `p${pathIndex}`,
                d: path.d,
                className: `c-tone-${path.tone || 'series1'}`
            }));
            return {
                key: `${index}-${option.value}`,
                value: option.value,
                label: option.label,
                checked,
                disabled: this.disabled || option.disabled === true,
                paths,
                hasPicture: paths.length > 0,
                className: `c-tile${checked ? ' c-tile_selected' : ''}`
            };
        });
    }

    handleChange(event) {
        event.stopPropagation();
        const value = this.tiles.find((tile) => String(tile.value) === event.target.value)?.value;
        if (value !== undefined && value !== this.value) {
            this.dispatchEvent(new CustomEvent('change', { detail: { value } }));
        }
    }
}