import { LightningElement, api } from 'lwc';
import { resolveFieldDescribe, validateCpe } from 'c/boardCpeUtils';
import { bucketIdOf } from 'c/boardBucketFields';

/**
 * Flow Custom Property Editor for the Board Chart widget (ADR 0002). The panel is an overview inside the shared
 * `c-board-cpe-common` shell: Board (Board id, title, *Wait for Filter widget*), one summary
 * line per step of the Chart widget's Setup dialog (Data, Chart type, Measures, Grouping, Display, Filter bindings)
 * with "Edit…" opening the dialog at that step, and Advanced: Config JSON. Every other setting (Base filters too, in
 * the Data step) is edited in the Setup dialog's steps (`c-board-chart-setup-steps`).
 */
export default class BoardChartCpe extends LightningElement {
    @api inputVariables = [];
    @api builderContext = {};
    @api elementInfo = {};

    config = {};
    /** `Schema.DisplayType` of the Group by leaf field, once known (the Grouping summary shows its granularity). */
    groupByType = null;

    _typedKey = null;

    @api
    validate() {
        return validateCpe(this.shell, 'chart', this.inputVariables);
    }

    get shell() {
        return this.template.querySelector('c-board-cpe-common');
    }

    /** What the step summaries can't read from the config: the Group by field type. */
    get stepContext() {
        return { groupByType: this.groupByType };
    }

    handleConfigChange(event) {
        this.config = event.detail.config;
        this.resolveGroupByType();
    }

    /** Describes the saved Group by path to decide whether the Grouping summary shows a date granularity. */
    resolveGroupByType() {
        const objectApiName = this.config.objectApiName || null;
        const groupByField = this.config.groupByField || null;
        const key = objectApiName && groupByField ? `${objectApiName}::${groupByField}` : null;
        if (key === this._typedKey) {
            return;
        }
        this._typedKey = key;
        this.groupByType = null;
        if (!key || bucketIdOf(groupByField) !== null) {
            return;
        }
        resolveFieldDescribe(objectApiName, groupByField)
            .then((field) => {
                if (this._typedKey === key) {
                    this.groupByType = field ? field.dataType : null;
                }
            })
            .catch(() => {
                // Unknown type: the summary shows a saved granularity only.
            });
    }
}