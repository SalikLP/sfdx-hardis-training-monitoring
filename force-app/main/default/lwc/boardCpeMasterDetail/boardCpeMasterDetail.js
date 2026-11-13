import { LightningElement, api } from 'lwc';
import { NO_DRAG, dragRowClass, dropRowDrag, overRowDrag, startRowDrag } from 'c/boardCpeUtils';

/**
 * Master-detail editor inside a Setup dialog step (e.g. the Filter widget's Filters step): an ordered item list on the
 * left (select, move up/down, remove; an error icon on invalid items; rows reorder by drag handle too) and the selected
 * item's editor on the right (default slot). Add controls go in the `actions` slot under the list. The layout fills
 * the modal body's height; each pane scrolls on its own.
 *
 * Stateless: the step owns the items and the selection and handles the non-bubbling events
 * `itemselect` (`{ key, index }`), `itemmove` (`{ index, offset }`, ±1 from the buttons or any offset from a drag), and `itemremove` (`{ index }`).
 */
export default class BoardCpeMasterDetail extends LightningElement {
    /** `[{ key, label, meta?, hasError? }]` in list order; `meta` shows as a badge (e.g. the filter type). */
    @api items = [];
    /** Key of the selected item (highlighted, `aria-current`). */
    @api selectedKey;
    /** Accessible name of the list (e.g. "Filters"). */
    @api listLabel = '';
    /** Shown instead of the list when there are no items. */
    @api emptyMessage = '';
    /** Drag-to-reorder state (see the drag helpers in c/boardCpeUtils). */
    drag = NO_DRAG;

    get hasItems() {
        return Array.isArray(this.items) && this.items.length > 0;
    }

    get rows() {
        const items = Array.isArray(this.items) ? this.items : [];
        const last = items.length - 1;
        return items.map((item, index) => {
            const selected = item.key === this.selectedKey;
            const label = item.label || `Item ${index + 1}`;
            return {
                key: item.key,
                index,
                label,
                meta: item.meta || '',
                hasError: Boolean(item.hasError),
                errorText: `${label} has errors`,
                upText: `Move ${label} up`,
                downText: `Move ${label} down`,
                removeText: `Remove ${label}`,
                isFirst: index === 0,
                isLast: index === last,
                ariaCurrent: selected ? 'true' : null,
                itemClass:
                    (selected
                        ? 'c-master-detail-item c-master-detail-item_selected slds-grid'
                        : 'c-master-detail-item slds-grid') + dragRowClass(this.drag, index)
            };
        });
    }

    /** Moves focus to the selected item's select button (e.g. after a remove). */
    @api
    focusSelected() {
        const button = this.template.querySelector(`li.c-master-detail-item_selected button.c-master-detail-select`);
        if (button) {
            button.focus();
        }
    }

    handleSelect(event) {
        const { key, index } = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('itemselect', { detail: { key, index: Number(index) } }));
    }

    handleMoveUp(event) {
        this.move(event, -1);
    }

    handleMoveDown(event) {
        this.move(event, 1);
    }

    move(event, offset) {
        const index = Number(event.currentTarget.dataset.index);
        this.dispatchEvent(new CustomEvent('itemmove', { detail: { index, offset } }));
    }

    handleDragStart(event) {
        this.drag = startRowDrag(event);
    }

    handleDragOver(event) {
        this.drag = overRowDrag(event, this.drag);
    }

    handleDrop(event) {
        const move = dropRowDrag(event, this.drag);
        this.drag = NO_DRAG;
        if (move) {
            this.dispatchEvent(new CustomEvent('itemmove', { detail: move }));
        }
    }

    handleDragEnd() {
        this.drag = NO_DRAG;
    }

    handleRemove(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.dispatchEvent(new CustomEvent('itemremove', { detail: { index } }));
    }
}