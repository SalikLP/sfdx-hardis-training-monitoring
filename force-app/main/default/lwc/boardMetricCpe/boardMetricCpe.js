import { LightningElement, api } from 'lwc';
import { validateCpe } from 'c/boardCpeUtils';

/**
 * Flow Custom Property Editor for the Board Metric widget (ADR 0002). The panel is an overview inside the shared
 * `c-board-cpe-common` shell: Board (Board id, title, *Wait for Filter widget*), one summary
 * line per step of the Metric widget's Setup dialog (Data, Measures, Display, Thresholds, Filter bindings) with
 * "Edit…" opening the dialog at that step, and Advanced: Config JSON. Every other setting is edited in the Setup
 * dialog's steps (`c-board-metric-setup-steps`).
 */
export default class BoardMetricCpe extends LightningElement {
    @api inputVariables = [];
    @api builderContext = {};
    @api elementInfo = {};

    @api
    validate() {
        return validateCpe(this.shell, 'metric', this.inputVariables);
    }

    get shell() {
        return this.template.querySelector('c-board-cpe-common');
    }
}