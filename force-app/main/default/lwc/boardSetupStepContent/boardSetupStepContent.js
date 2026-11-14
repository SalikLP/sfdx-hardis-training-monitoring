import { containInnerChanges } from 'c/boardCpeUtils';

/**
 * Shared step content logic of the data Widgets' Setup dialog steps (`c-board-chart-setup-steps`,
 * `c-board-metric-setup-steps`, `c-board-table-setup-steps`): the draft `change` / `steperrors` events and the Data,
 * Filter bindings and subtitle handlers they all have.
 *
 *   export default class BoardChartSetupSteps extends SetupStepContent(LightningElement) { ... }
 *
 * The component keeps its own `@api config` / `@api context` (read here as `this.config` and `this._context`).
 * `change` carries `detail.patch` (shallow merged into the draft; null removes a key); `steperrors` carries
 * `detail.step` and `detail.errors` (messages).
 */

/** A trimmed text value, or null when blank (null removes the key from the draft). */
function textOrNull(value) {
    return value && String(value).trim() ? value : null;
}

export const SetupStepContent = (Base) =>
    class extends Base {
        connectedCallback() {
            containInnerChanges(this);
        }

        update(patch) {
            this.dispatchEvent(new CustomEvent('change', { detail: { patch } }));
        }

        reportErrors(step, errors) {
            this.dispatchEvent(new CustomEvent('steperrors', { detail: { step, errors } }));
        }

        get builderContext() {
            return (this._context && this._context.builderContext) || {};
        }

        get elementInfo() {
            return (this._context && this._context.elementInfo) || {};
        }

        // ---- Data --------------------------------------------------------------------------------------------------

        get objectApiName() {
            return this.config.objectApiName || null;
        }

        get objectPickerValue() {
            return this.objectApiName || '';
        }

        handleObject(event) {
            this.update({ objectApiName: textOrNull(event.detail.value) });
        }

        get baseFilters() {
            return this.config.baseFilters || null;
        }

        handleBaseFilters(event) {
            event.stopPropagation();
            const baseFilters = event.detail.baseFilters || [];
            this.update({ baseFilters: baseFilters.length ? baseFilters : null });
        }

        /** The Widget-level Data provider: an Apex class implementing `BoardDataProvider` (Chart and Metric). */
        get dataProvider() {
            return this.config.dataProvider || '';
        }

        handleDataProvider(event) {
            const value = textOrNull(event.detail.value);
            this.update({ dataProvider: value ? String(value).trim() : null });
        }

        // ---- Filter bindings ---------------------------------------------------------------------------------------

        handleBindingsChange(event) {
            event.stopPropagation();
            this.update({ filterBindings: event.detail.filterBindings || null });
        }

        handleBindingState(event) {
            event.stopPropagation();
            this.reportErrors(
                'filterBindings',
                (event.detail.errors || []).map((item) => item.errorString)
            );
        }

        // ---- Display -----------------------------------------------------------------------------------------------

        get subtitle() {
            return this.config.subtitle || '';
        }

        handleSubtitle(event) {
            this.update({ subtitle: textOrNull(event.detail.value) });
        }
    };