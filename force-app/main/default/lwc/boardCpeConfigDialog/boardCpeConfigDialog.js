import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { DIALOG_DISMISS, DIALOG_SAVE } from 'c/boardCpeUtils';

/**
 * Config dialog (ticket 07 spike): a large `LightningModal` that edits a deep-copied draft of one part of a Widget
 * config and closes with `{ action: 'save', draft }` or `{ action: 'dismiss' }`. Open it through `openConfigDialog`
 * (`c/boardCpeUtils`), which also maps the header X / Escape (`undefined` result) to a dismiss.
 *
 * The spike body edits the draft as JSON; a real Config dialog (e.g. Filter definitions) keeps this result contract
 * and footer but renders its own master-detail body.
 */
export default class BoardCpeConfigDialog extends LightningModal {
    /** The Config part to edit (already deep-copied by `openConfigDialog`). */
    @api value;
    /** Optional `(draft) => errorString | null` check; Save stays disabled while it returns an error. */
    @api validator;

    draftText = '';
    _initialized = false;

    connectedCallback() {
        if (!this._initialized) {
            this._initialized = true;
            this.draftText = JSON.stringify(this.value === undefined ? null : this.value, null, 2);
        }
    }

    get parsed() {
        try {
            return { draft: JSON.parse(this.draftText) };
        } catch (e) {
            return { error: `Invalid JSON: ${e.message}` };
        }
    }

    get errorMessage() {
        const { draft, error } = this.parsed;
        if (error) {
            return error;
        }
        return typeof this.validator === 'function' ? this.validator(draft) || null : null;
    }

    get isSaveDisabled() {
        return Boolean(this.errorMessage);
    }

    handleDraftChange(event) {
        this.draftText = event.detail.value;
    }

    handleCancel() {
        this.close({ action: DIALOG_DISMISS });
    }

    handleSave() {
        if (this.isSaveDisabled) {
            return;
        }
        this.close({ action: DIALOG_SAVE, draft: this.parsed.draft });
    }
}