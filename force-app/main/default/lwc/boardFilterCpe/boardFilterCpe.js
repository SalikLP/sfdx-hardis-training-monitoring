import { LightningElement, api } from 'lwc';
import { validateCpe } from 'c/boardCpeUtils';

/**
 * Flow Custom Property Editor for the Board Filter widget (ADR 0002). The panel is an overview inside the shared
 * `c-board-cpe-common` shell: Board (Board id, title), one summary line per step of the Filter
 * widget's Setup dialog (Filters, Bucket fields, Record context, Remember selections, Currency) with "Edit…" opening
 * the dialog at that step, and Advanced: Config JSON. Every other setting is edited in the Setup dialog's steps
 * (`c-board-filter-setup-steps`).
 */
export default class BoardFilterCpe extends LightningElement {
    @api inputVariables = [];
    @api builderContext = {};
    @api elementInfo = {};

    @api
    validate() {
        return validateCpe(this.shell, 'filter', this.inputVariables);
    }

    get shell() {
        return this.template.querySelector('c-board-cpe-common');
    }
}