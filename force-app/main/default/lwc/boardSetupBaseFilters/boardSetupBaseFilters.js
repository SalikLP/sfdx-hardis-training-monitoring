import { LightningElement, api } from 'lwc';
import { baseFiltersFromTree, baseFiltersToTree } from 'c/boardCpeUtils';

const ID_PREFIX = 'bf';

/**
 * Base filters of a data Widget inside its Setup dialog's Data step (ADR 0002): the shared condition editor
 * (`c-board-condition-editor`) over the draft's `baseFilters`, inline in the step (no modal in the modal). Every
 * Widget's step content embeds it the same way:
 *
 *   `<c-board-setup-base-filters value={config.baseFilters} object-api-name={objectApiName} onchange={...}>`
 *
 * and patches its draft with `{ baseFilters: detail.baseFilters.length ? detail.baseFilters : null }`. The Data step
 * (`dataStep` in `c/boardSetupSteps`) validates the Base filters and counts them in its summary.
 *
 * Fires `change` with `detail.baseFilters` (the whole list) after every edit. OR at the top level is stored as one
 * OR group entry (`baseFiltersFromTree`); the first edit gives entries with a missing or duplicate id a fresh one.
 */
export default class BoardSetupBaseFilters extends LightningElement {
    /** Object the field pickers start from. */
    @api objectApiName;

    idPrefix = ID_PREFIX;
    tree = { logic: 'AND', conditions: [] };
    rootGroupId = null;

    _value = null;
    /** The list last fired (JSON), so the draft echoing it back keeps the tree (e.g. OR with no conditions yet). */
    _fired = null;

    /** The draft's `baseFilters`. */
    @api
    get value() {
        return this._value;
    }
    set value(value) {
        this._value = value;
        const list = Array.isArray(value) ? value : [];
        if (this._fired !== null && JSON.stringify(list) === this._fired) {
            return;
        }
        this._fired = null;
        const { tree, rootGroupId } = baseFiltersToTree(list);
        this.tree = tree;
        this.rootGroupId = rootGroupId;
    }

    handleConditionChange(event) {
        event.stopPropagation();
        this.tree = event.detail.value;
        const baseFilters = baseFiltersFromTree(this.tree, this.rootGroupId);
        this._fired = JSON.stringify(baseFilters);
        this.dispatchEvent(new CustomEvent('change', { detail: { baseFilters } }));
    }
}