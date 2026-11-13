import { LightningElement, api } from 'lwc';

/**
 * Single-select segmented button group: exactly one option active at a time.
 * Shared by the Filter widget's Buttons display and Empty / Filled in filter.
 * Fires `change` with `detail.value` (the clicked option's value).
 */
export default class BoardSegmentedButtons extends LightningElement {
    /** Group label, used as the accessible name. */
    @api label;
    /** `[{ label, value }]` in display order. */
    @api options = [];
    /** Value of the active option. */
    @api value;
    @api disabled = false;
    /** Compact drawer (below 768px): 44px touch targets. */
    @api compact = false;

    get items() {
        return (this.options || []).map((option) => {
            const active = option.value === this.value;
            return {
                key: option.value,
                value: option.value,
                label: option.label,
                ariaPressed: String(active),
                className: `slds-button c-board-segment${this.compact ? ' c-board-segment_compact' : ''} ${
                    active ? 'slds-button_brand' : 'slds-button_neutral'
                }`
            };
        });
    }

    handleClick(event) {
        const value = event.currentTarget.dataset.value;
        if (this.disabled || value === this.value) {
            return;
        }
        this.dispatchEvent(new CustomEvent('change', { detail: { value } }));
    }
}