import LightningModal from 'lightning/modal';
import { api } from 'lwc';

const FINISHED_STATUSES = new Set(['FINISHED', 'FINISHED_SCREEN']);

/**
 * Screen Flow modal of a Table Row action. Closes with `{ finished: true }` when the flow reports it finished, so the
 * Table can refresh; closing the modal any other way resolves `undefined`.
 */
export default class BoardTableFlowModal extends LightningModal {
    @api flowApiName;
    /** `[{ name, type, value }]` flow input variables mapped from the row. */
    @api inputVariables = [];

    handleStatusChange(event) {
        if (FINISHED_STATUSES.has(event.detail?.status)) {
            this.close({ finished: true });
        }
    }
}