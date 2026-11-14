import { LightningElement, api } from 'lwc';
import { RECORD_CONTEXT_OVERRIDE_TYPES } from 'c/boardConfigUtils';
import {
    PERSISTENCE_OPTIONS,
    RECORD_CONTEXT_MODE_OPTIONS,
    cleanString,
    compactRecordContext,
    isPlainObject,
    containInnerChanges
} from 'c/boardCpeUtils';

/** What each Record context mode does, with an example, shown under the Mode picker. */
const RECORD_CONTEXT_MODE_HELP = {
    IMPLICIT: {
        description:
            'Every Widget shows only data related to the record, without a visible filter. Each Widget finds the field that points at the record on its own, or uses its Filter bindings.',
        example:
            "On an Account page, an Opportunity chart shows that Account's Opportunities and a Case table shows its Cases."
    },
    LOCKED: {
        description:
            "The record is put into the filter chosen below, and viewers can't change it. Widgets then follow that filter like any other. A badge can show which record the Board is locked to.",
        example:
            'On an Account page with the Account filter chosen below, the Account filter always shows this Account and is read-only.'
    },
    DEFAULT: {
        description:
            'The record is pre-filled in the filter chosen below when the page opens. Viewers can change or clear it to look at other records.',
        example:
            'On an Account page with the Account filter chosen below, the Board opens on this Account, and a viewer can pick another Account.'
    }
};

/**
 * Step content of the Filter widget's Setup dialog (`c/boardSetupDialog`): the inputs of one step (`step`: `filters`,
 * `bucketFields`, `recordContext`, `persistence` or `currency`, see `FILTER_STEPS` in `c/boardSetupSteps`) over the
 * dialog's draft (`config`).
 *
 * - Filters: the Filter definitions, Filter sections and the Currency picker item, master-detail inside the step
 *   (`c-board-setup-filter-definitions`).
 * - Bucket fields: the Board-level Bucket fields (`c-board-bucket-field-editor`) and the object their rule fields are
 *   picked from (`bucketObjectApiName`, design time only).
 * - Record context: the mode, the filter the record feeds into, the host record field path and the locked badge.
 * - Remember selections: the persistence of the viewer's selections.
 * - Currency: the Board's Config currency (`c-board-config-currency`).
 *
 * Every edit fires `change` with `detail.patch` (merged into the draft by the dialog; null removes a key).
 */
export default class BoardFilterSetupSteps extends LightningElement {
    connectedCallback() {
        containInnerChanges(this);
    }

    @api step;
    /** Not read by the Filter widget's steps; part of the step content seam. */
    @api context;

    recordContextOptions = RECORD_CONTEXT_MODE_OPTIONS;
    persistenceOptions = PERSISTENCE_OPTIONS;

    _config = {};

    /** The Setup dialog's draft config. */
    @api
    get config() {
        return this._config;
    }
    set config(value) {
        this._config = isPlainObject(value) ? value : {};
    }

    get isFilters() {
        return this.step === 'filters';
    }

    get isBucketFields() {
        return this.step === 'bucketFields';
    }

    get isRecordContext() {
        return this.step === 'recordContext';
    }

    get isPersistence() {
        return this.step === 'persistence';
    }

    get isCurrency() {
        return this.step === 'currency';
    }

    update(patch) {
        this.dispatchEvent(new CustomEvent('change', { detail: { patch } }));
    }

    // ---- Filters -------------------------------------------------------------------------------------------------

    handleDefinitionsChange(event) {
        event.stopPropagation();
        this.update(event.detail.patch);
    }

    // ---- Bucket fields -------------------------------------------------------------------------------------------

    get bucketFields() {
        return Array.isArray(this._config.bucketFields) ? this._config.bucketFields : [];
    }

    /** Object the rule conditions' field pickers start from (design time only; Widgets read their own object). */
    get bucketObjectApiName() {
        return this._config.bucketObjectApiName || '';
    }

    handleBucketFields(event) {
        event.stopPropagation();
        const bucketFields = event.detail.value;
        this.update({ bucketFields: Array.isArray(bucketFields) && bucketFields.length ? bucketFields : null });
    }

    handleBucketObject(event) {
        event.stopPropagation();
        this.update({ bucketObjectApiName: cleanString(event.detail.value) || null });
    }

    // ---- Record context ------------------------------------------------------------------------------------------

    get recordContext() {
        return isPlainObject(this._config.recordContext) ? this._config.recordContext : {};
    }

    get recordContextMode() {
        return this.recordContext.mode || 'IMPLICIT';
    }

    /** What the chosen mode does, with an example, shown under the Mode picker. */
    get recordContextModeHelp() {
        return RECORD_CONTEXT_MODE_HELP[this.recordContextMode] || RECORD_CONTEXT_MODE_HELP.IMPLICIT;
    }

    get isLocked() {
        return this.recordContextMode === 'LOCKED';
    }

    get filters() {
        return Array.isArray(this._config.filters) ? this._config.filters.filter(isPlainObject) : [];
    }

    get overrideFilterOptions() {
        return [
            { label: 'None (filter Widgets by the record Id)', value: '' },
            ...this.filters
                .filter((filter) => cleanString(filter.filterId) && RECORD_CONTEXT_OVERRIDE_TYPES.includes(filter.type))
                .map((filter) => ({
                    label: `${filter.label || filter.filterId} (${filter.filterId})`,
                    value: filter.filterId
                }))
        ];
    }

    get overrideFilterId() {
        return this.recordContext.overrideFilterId || '';
    }

    get overrideFieldPath() {
        return this.recordContext.overrideFieldPath || '';
    }

    get showRecordContextBadge() {
        return this._config.showRecordContextBadge !== false;
    }

    handleRecordContextMode(event) {
        this.updateRecordContext({ mode: event.detail.value });
    }

    handleOverrideFilterId(event) {
        this.updateRecordContext({ overrideFilterId: event.detail.value || null });
    }

    handleOverrideFieldPath(event) {
        this.updateRecordContext({ overrideFieldPath: cleanString(event.detail.value) });
    }

    handleBadge(event) {
        this.update({ showRecordContextBadge: event.detail.checked ? null : false });
    }

    updateRecordContext(patch) {
        this.update({ recordContext: compactRecordContext({ ...this.recordContext, ...patch }) });
    }

    // ---- Remember selections -------------------------------------------------------------------------------------

    get persistence() {
        return this._config.persistence || 'SESSION';
    }

    handlePersistence(event) {
        this.update({ persistence: event.detail.value });
    }

    // ---- Currency ------------------------------------------------------------------------------------------------

    /** The Board's Config currency (blank: corporate). */
    get configCurrency() {
        return this._config.configCurrency || '';
    }

    handleConfigCurrency(event) {
        event.stopPropagation();
        this.update({ configCurrency: event.detail.value || null });
    }
}