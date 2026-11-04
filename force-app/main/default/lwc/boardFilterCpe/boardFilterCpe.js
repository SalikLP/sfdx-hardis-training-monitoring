import { LightningElement, api } from 'lwc';
import BoardFilterDialog from 'c/boardFilterDialog';
import { RECORD_CONTEXT_OVERRIDE_TYPES } from 'c/boardConfigUtils';
import {
    DIALOG_SAVE,
    FILTER_TYPE_LABELS,
    PERSISTENCE_OPTIONS,
    RECORD_CONTEXT_MODE_OPTIONS,
    cleanString,
    compactRecordContext,
    countLabel,
    validateFilterDefinitions,
    initialSectionOpen,
    isPlainObject,
    joinSummary,
    openConfigDialog,
    toggleSectionOpen,
    validateCpe,
    widgetSectionStates
} from 'c/boardCpeUtils';

const RECORD_CONTEXT_MODE_LABELS = { IMPLICIT: 'Implicit', LOCKED: 'Locked', DEFAULT: 'Default' };
const PERSISTENCE_LABELS = { SESSION: 'This browser tab', LOCAL: 'This browser', NONE: 'Not remembered' };

/** Config sections of the Filter Config editor (see `sectionStates` in `c/boardCpeUtils`). */
const SECTIONS = [
    { name: 'filters', errorKeys: ['filters'], summary: (cpe) => cpe.filtersSummary, openWhenNew: true },
    { name: 'recordContext', errorKeys: ['recordContext'], summary: (cpe) => cpe.recordContextSummary },
    { name: 'persistence', errorKeys: ['persistence'], summary: (cpe) => cpe.persistenceSummary }
];

/**
 * Flow Custom Property Editor for the Board Filter widget, inside the shared `c-board-cpe-common` shell (Board,
 * Config JSON). The Filters section is a read-only list; filter definitions are edited in the Filter definitions
 * Config dialog (`c-board-filter-dialog`) and committed as one config change on Save. Record context and persistence
 * are edited inline.
 */
export default class BoardFilterCpe extends LightningElement {
    @api inputVariables = [];
    @api builderContext = {};
    @api elementInfo = {};

    config = {};
    /** Set once the shell has sent its first `configchange`; section errors wait for it (no flash of errors). */
    configLoaded = false;

    recordContextOptions = RECORD_CONTEXT_MODE_OPTIONS;
    persistenceOptions = PERSISTENCE_OPTIONS;

    /** Open state of the Config sections: set once on load (a new Widget opens Filters), then by the Admin. */
    sectionOpen = null;

    @api
    validate() {
        return validateCpe(this.shell, 'filter', this.inputVariables);
    }

    connectedCallback() {
        if (!this.sectionOpen) {
            this.sectionOpen = initialSectionOpen(SECTIONS, 'filter', this.inputVariables);
        }
    }

    // ---- Config sections -----------------------------------------------------------------------------------------

    get sections() {
        return widgetSectionStates('filter', SECTIONS, this);
    }

    /** `None`, `1 filter`, or `N filters`. */
    get filtersSummary() {
        const count = this.filters.length;
        return count ? countLabel(count, 'filter') : 'None';
    }

    /** The mode, plus the override filterId and host field path when set (e.g. `Locked · account · AccountId`). */
    get recordContextSummary() {
        const mode = this.recordContextMode;
        return joinSummary([RECORD_CONTEXT_MODE_LABELS[mode] || mode, this.overrideFilterId, this.overrideFieldPath]);
    }

    get persistenceSummary() {
        return PERSISTENCE_LABELS[this.persistence] || this.persistence;
    }

    handleSectionToggle(event) {
        this.sectionOpen = toggleSectionOpen(this.sectionOpen, event);
    }

    get shell() {
        return this.template.querySelector('c-board-cpe-common');
    }

    handleConfigChange(event) {
        this.config = event.detail.config;
        this.configLoaded = true;
    }

    update(patch) {
        this.shell.updateConfig(patch);
    }

    get filters() {
        return Array.isArray(this.config.filters) ? this.config.filters.map((f) => (isPlainObject(f) ? f : {})) : [];
    }

    get hasFilters() {
        return this.filters.length > 0;
    }

    // ---- Filters: read-only list + Filter definitions Config dialog ----------------------------------------------

    /** Label (or filterId), type badge, and error indicator of each saved filter. */
    get filterRows() {
        const errors = validateFilterDefinitions(this.filters).byIndex;
        return this.filters.map((filter, index) => {
            const label = cleanString(filter.label) || cleanString(filter.filterId) || `Filter ${index + 1}`;
            return {
                key: `filter-${index}`,
                label,
                typeLabel: FILTER_TYPE_LABELS[filter.type] || 'Unknown type',
                hasError: errors[index].length > 0,
                errorText: `${label} has errors. Edit filters to fix them.`
            };
        });
    }

    /**
     * Opens the Filter definitions Config dialog on a draft of the filters. Save applies the draft as one config
     * change (plus the Record context override when the draft renamed, removed, or retyped its filter); Cancel,
     * Escape, and the header X change nothing. Focus then returns to "Edit filters…".
     */
    async handleEditFilters() {
        const result = await openConfigDialog(BoardFilterDialog, {
            label: 'Edit filters',
            description: 'Add, reorder, remove, and configure the filters of this Filter widget.',
            value: { filters: this.filters, recordContext: this.config.recordContext ?? null }
        });
        if (result.action === DIALOG_SAVE) {
            this.applyFiltersDraft(result.draft);
            // Let the read-only list re-render before restoring focus, so focus is not lost to <body>.
            await Promise.resolve();
        }
        this.focusEditFilters();
    }

    applyFiltersDraft(draft) {
        const filters = draft && Array.isArray(draft.filters) ? draft.filters : [];
        const patch = { filters: filters.length ? filters : null };
        const recordContext = draft ? draft.recordContext : undefined;
        if (
            recordContext !== undefined &&
            JSON.stringify(recordContext ?? null) !== JSON.stringify(this.config.recordContext ?? null)
        ) {
            patch.recordContext = recordContext;
        }
        this.update(patch);
    }

    focusEditFilters() {
        const button = this.template.querySelector('lightning-button.c-filter-edit');
        if (button) {
            button.focus();
        }
    }

    // ---- Record context & persistence ----------------------------------------------------------------------------

    get recordContext() {
        return isPlainObject(this.config.recordContext) ? this.config.recordContext : {};
    }

    get recordContextMode() {
        return this.recordContext.mode || 'IMPLICIT';
    }

    get isLocked() {
        return this.recordContextMode === 'LOCKED';
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
        return this.config.showRecordContextBadge !== false;
    }

    get persistence() {
        return this.config.persistence || 'SESSION';
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

    handlePersistence(event) {
        this.update({ persistence: event.detail.value });
    }

    updateRecordContext(patch) {
        this.update({ recordContext: compactRecordContext({ ...this.recordContext, ...patch }) });
    }
}