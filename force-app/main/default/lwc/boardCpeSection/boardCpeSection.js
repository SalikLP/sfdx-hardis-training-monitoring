import { LightningElement, api } from 'lwc';

/**
 * Config section: one collapsible group of settings in a Config editor, built on the SLDS expandable section
 * blueprint. The header is a real `<button>` (`aria-expanded` / `aria-controls`) showing the title, the one-line
 * `summary` while collapsed, and an error icon while `has-error` is set.
 *
 * Open state is supplied by the parent (`open`) and changed by the Admin: each header click flips it and fires a
 * non-bubbling `toggle` event (`detail: { name, open }`) so a parent that tracks the state can mirror it. A section
 * with `has-error` is forced open and cannot be collapsed; once the error clears it stays open (no collapse while the
 * Admin is still fixing it) until the Admin collapses it.
 *
 * The slotted content is always rendered and only hidden while collapsed, so control state survives a collapse.
 */
export default class BoardCpeSection extends LightningElement {
    /** Section title shown in the header. */
    @api label = '';
    /** One-line summary shown in the header while the section is collapsed. */
    @api summary = '';
    /** Identifies the section in `toggle` events. */
    @api name;

    _open = false;
    _hasError = false;

    /** Whether the section is expanded. Always true while `hasError` is set. */
    @api
    get open() {
        return this.isExpanded;
    }
    set open(value) {
        this._open = Boolean(value) || this._hasError;
    }

    /** Shows the error indicator and forces the section open. */
    @api
    get hasError() {
        return this._hasError;
    }
    set hasError(value) {
        this._hasError = Boolean(value);
        if (this._hasError) {
            this._open = true;
        }
    }

    get isExpanded() {
        return this._open || this._hasError;
    }

    get isCollapsed() {
        return !this.isExpanded;
    }

    get ariaExpanded() {
        return String(this.isExpanded);
    }

    get sectionClass() {
        return this.isExpanded ? 'slds-section slds-is-open' : 'slds-section';
    }

    get toggleIconName() {
        return this.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get showSummary() {
        return this.isCollapsed && typeof this.summary === 'string' && this.summary.trim() !== '';
    }

    handleToggle() {
        if (this._hasError) {
            return;
        }
        this._open = !this._open;
        this.dispatchEvent(new CustomEvent('toggle', { detail: { name: this.name, open: this._open } }));
    }
}