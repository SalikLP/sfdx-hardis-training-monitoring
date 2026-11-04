import { LightningElement, api } from 'lwc';
import BoardBaseFilterDialog from 'c/boardBaseFilterDialog';
import { IGNORE_BINDING, RECORD_CONTEXT_FILTER_ID, normalizeBoardError } from 'c/boardConfigUtils';
import {
    BINDING_PATH_HELP,
    DIALOG_SAVE,
    FILTER_TYPE_LABELS,
    ORIENTATION_OPTIONS,
    WIDGET_TYPES,
    applyPatch,
    baseFilterErrorsByIndex,
    baseFilterSummary,
    configErrors,
    countLabel,
    deepCopy,
    formatConfig,
    hasText,
    initialSectionOpen,
    isDataWidget,
    isIgnoreBinding,
    isPlainObject,
    isValidBindingPath,
    loadObjectFields,
    openConfigDialog,
    orderConfig,
    joinSummary,
    readCpeState,
    sectionStates,
    serializeConfig,
    toggleSectionOpen,
    topLevelKeysFor,
    validateConfigText
} from 'c/boardCpeUtils';
import { discoverFilterWidgets, previewConventionBindings } from './cpeConfig';

const CHANGED_EVENT = 'configuration_editor_input_value_changed';
const DELETED_EVENT = 'configuration_editor_input_value_deleted';
const MODE_CONVENTION = 'CONVENTION';
const MODE_PATH = 'PATH';
const MODE_IGNORE = 'IGNORE';

const BINDING_MODE_OPTIONS = [
    { label: 'By convention', value: MODE_CONVENTION },
    { label: 'Field path', value: MODE_PATH },
    { label: 'Ignore', value: MODE_IGNORE }
];
const RESOLVED_CONVENTION = ['BOUND', 'RUNTIME', 'SOSL'];

/** The shell's own Config sections (see `sectionStates` in `c/boardCpeUtils`). */
const SECTIONS = [
    {
        name: 'board',
        errorKeys: ['boardId', 'title', 'objectApiName', 'orientation'],
        summary: (cpe) => cpe.boardSummary,
        openWhenNew: true
    },
    {
        name: 'bindings',
        errorKeys: ['filterBindings'],
        summary: (cpe) => cpe.bindingsSummary,
        hasError: (cpe) => cpe.hasBindingDraftErrors
    },
    { name: 'baseFilters', errorKeys: ['baseFilters'], summary: (cpe) => cpe.baseFiltersSummary },
    // Advanced: Config JSON; always collapsed on load.
    { name: 'advanced', summary: (cpe) => cpe.advancedSummary, hasError: (cpe) => cpe.hasDraftErrors }
];

/**
 * Shared Flow Custom Property Editor shell composed by every Board CPE.
 *
 * Renders the Board Config section (Board id/title, plus the Object Picker for data Widgets and orientation for Bar),
 * a default slot for widget-specific Config sections, the Filter bindings (`builderContext` Filter widget discovery +
 * `filterBindings` overrides) and Base filters Config sections (data Widgets), and the "Advanced: Config JSON"
 * portability section. Each is a `c-board-cpe-section`: Board starts open for a new Widget, everything else starts
 * collapsed, and a section with a validation error is forced open.
 *
 * Every edit dispatches `configuration_editor_input_value_changed` (or `..._deleted` for cleared values) for the
 * serialized `configJson`, and also for the discrete top-level property when `boardId`, `title`, `objectApiName`,
 * or `orientation` changes. A non-bubbling `configchange` event (`detail.config`) reports the current config.
 */
export default class BoardCpeCommon extends LightningElement {
    config = { version: 1, widgetType: 'metric' };
    storedJsonError = null;
    references = {};

    previewFields = [];
    previewLoading = false;
    previewError = null;

    manualFilterIds = [];
    manualDraft = '';
    manualError = null;
    pendingPathIds = [];

    /** Open state of the shell's Config sections: set once on load (a new Widget opens Board), then by the Admin. */
    sectionOpen = null;
    jsonDraft = null;
    draftErrors = [];
    drawerMessage = null;

    bindingModeOptions = BINDING_MODE_OPTIONS;
    orientationOptions = ORIENTATION_OPTIONS;
    bindingPathHelp = BINDING_PATH_HELP;

    _widgetType = 'metric';
    _inputVariables = [];
    _builderContext = {};
    _elementInfo = {};
    _previewObject = null;
    _connected = false;

    /** `filter` | `metric` | `bar` | `table` */
    @api
    get widgetType() {
        return this._widgetType;
    }
    set widgetType(value) {
        this._widgetType = WIDGET_TYPES.includes(value) ? value : 'metric';
        this.syncFromInputs();
    }

    /** Flow Builder `inputVariables` (`[{ name, value, valueDataType }]`) passed through by the CPE. */
    @api
    get inputVariables() {
        return this._inputVariables;
    }
    set inputVariables(value) {
        this._inputVariables = Array.isArray(value) ? value : [];
        this.syncFromInputs();
    }

    /** Flow Builder `builderContext` (`screens -> fields`) used to discover the Filter widget. */
    @api
    get builderContext() {
        return this._builderContext;
    }
    set builderContext(value) {
        this._builderContext = value || {};
    }

    /** Flow Builder `elementInfo` (`{ apiName, type }`) identifying the screen component being edited. */
    @api
    get elementInfo() {
        return this._elementInfo;
    }
    set elementInfo(value) {
        this._elementInfo = value || {};
    }

    /** Current config (version 1 envelope) as a plain object. */
    @api
    getConfig() {
        return deepCopy(this.config);
    }

    /**
     * Shallow-merges `patch` into the config (null/undefined removes a key), then emits `configJson` and, for
     * `boardId`/`title`/`objectApiName`/`orientation` keys, the top-level property.
     */
    @api
    updateConfig(patch) {
        if (!isPlainObject(patch)) {
            return;
        }
        const changes = { ...patch };
        delete changes.version;
        delete changes.widgetType;
        const topLevelKeys = topLevelKeysFor(this._widgetType);
        this.commit(
            applyPatch(this.config, changes),
            Object.keys(changes).filter((key) => topLevelKeys.includes(key))
        );
    }

    /**
     * Design-time errors (`[{ key, errorString }]`): the Config JSON draft or saved JSON, the shared envelope rules,
     * the widget's own rules (`configErrors`), and Filter bindings switched to "Field path" without a path.
     */
    @api
    validate() {
        const errors = [];
        if (this.hasDraft) {
            errors.push({
                key: 'configJson',
                errorString: this.draftErrors.length
                    ? `Pasted Config JSON is invalid: ${this.draftErrors[0]}`
                    : 'Apply or discard the pasted Config JSON.'
            });
        } else if (this.storedJsonError) {
            errors.push({ key: 'configJson', errorString: this.storedJsonError });
        }
        errors.push(...configErrors(this._widgetType, this.config, this.references));
        if (this.isDataWidget) {
            this.pendingPathIds
                .filter((filterId) => !this.hasPathBinding(filterId))
                .forEach((filterId) =>
                    errors.push({
                        key: 'filterBindings',
                        errorString: `Filter binding "${filterId}": enter a field path.`
                    })
                );
        }
        return errors;
    }

    connectedCallback() {
        this._connected = true;
        if (!this.sectionOpen) {
            this.sectionOpen = initialSectionOpen(SECTIONS, this._widgetType, this._inputVariables);
        }
        this.notifyConfig();
    }

    disconnectedCallback() {
        this._connected = false;
    }

    renderedCallback() {
        // `<textarea>` content is a DOM property, not a template attribute.
        const textarea = this.template.querySelector('textarea.c-cpe-json');
        if (textarea && textarea.value !== this.jsonText) {
            textarea.value = this.jsonText;
        }
    }

    // ---- State ---------------------------------------------------------------------------------------------------

    syncFromInputs() {
        const state = readCpeState(this._widgetType, this._inputVariables);
        this.config = state.config;
        this.storedJsonError = state.storedJsonError;
        this.references = state.references;
        this.refreshPreviewFields();
        this.notifyConfig();
    }

    commit(nextConfig, topLevelKeys = []) {
        this.config = orderConfig(this._widgetType, nextConfig);
        topLevelKeys.forEach((key) => this.emitInput(key, this.config[key]));
        this.emitInput('configJson', serializeConfig(this._widgetType, this.config));
        this.refreshPreviewFields();
        this.notifyConfig();
    }

    emitInput(name, value) {
        if (!hasText(value)) {
            this.dispatchEvent(
                new CustomEvent(DELETED_EVENT, { bubbles: true, composed: true, cancelable: false, detail: { name } })
            );
            return;
        }
        this.dispatchEvent(
            new CustomEvent(CHANGED_EVENT, {
                bubbles: true,
                composed: true,
                cancelable: false,
                detail: { name, newValue: String(value), newValueDataType: 'String' }
            })
        );
    }

    notifyConfig() {
        if (this._connected) {
            this.dispatchEvent(new CustomEvent('configchange', { detail: { config: deepCopy(this.config) } }));
        }
    }

    refreshPreviewFields() {
        const objectApiName =
            this.isDataWidget && hasText(this.config.objectApiName) ? String(this.config.objectApiName).trim() : null;
        if (objectApiName === this._previewObject) {
            return;
        }
        this._previewObject = objectApiName;
        this.previewFields = [];
        this.previewError = null;
        this.previewLoading = Boolean(objectApiName);
        if (!objectApiName) {
            return;
        }
        loadObjectFields(objectApiName)
            .then((fields) => {
                if (this._previewObject === objectApiName) {
                    this.previewFields = fields || [];
                    this.previewLoading = false;
                }
            })
            .catch((err) => {
                if (this._previewObject === objectApiName) {
                    this.previewError = normalizeBoardError(err).message;
                    this.previewLoading = false;
                }
            });
    }

    // ---- Config sections -----------------------------------------------------------------------------------------

    get sections() {
        return sectionStates(SECTIONS, this, this.sectionOpen, () =>
            configErrors(this._widgetType, this.config, this.references)
        );
    }

    /** Filter bindings switched to "Field path" without a path, or binding rows with an invalid path. */
    get hasBindingDraftErrors() {
        return (
            this.pendingPathIds.some((filterId) => !this.hasPathBinding(filterId)) ||
            this.bindingRows.some((row) => row.error)
        );
    }

    /** `default · Account`; the object part only for data Widgets. */
    get boardSummary() {
        const boardId = this.boardIdValue || 'default';
        if (!this.isDataWidget) {
            return boardId;
        }
        const object = this.objectApiNameValue || this.references.objectApiName || 'No object';
        return joinSummary([boardId, object]);
    }

    /** `3 bound · 1 opted out`, or `None` without any Filter to bind. */
    get bindingsSummary() {
        const rows = this.bindingRows;
        if (!rows.length) {
            return 'None';
        }
        const bound = rows.filter((row) => row.status === 'bound').length;
        const optedOut = rows.filter((row) => row.status === 'ignored').length;
        return joinSummary([`${bound} bound`, `${optedOut} opted out`]);
    }

    /** `None` or the number of conditions. */
    get baseFiltersSummary() {
        const count = this.baseFilters.length;
        return count ? countLabel(count, 'condition') : 'None';
    }

    get advancedSummary() {
        return this.hasDraft ? 'Pasted JSON not applied' : '';
    }

    handleSectionToggle(event) {
        this.sectionOpen = toggleSectionOpen(this.sectionOpen, event);
        if (event.detail.name === 'advanced') {
            this.drawerMessage = null;
        }
    }

    // ---- Header --------------------------------------------------------------------------------------------------

    get isDataWidget() {
        return isDataWidget(this._widgetType);
    }

    get isBar() {
        return this._widgetType === 'bar';
    }

    get boardIdValue() {
        return this.config.boardId || '';
    }

    get titleValue() {
        return this.config.title || '';
    }

    get objectApiNameValue() {
        return this.config.objectApiName || '';
    }

    get orientationValue() {
        return this.config.orientation || 'vertical';
    }

    get referenceNotes() {
        return Object.entries(this.references).map(([key, value]) => ({
            key,
            text: `${key} is bound to the Flow resource ${value}; it overrides configJson at runtime.`
        }));
    }

    get hasReferenceNotes() {
        return this.referenceNotes.length > 0;
    }

    handleBoardIdChange(event) {
        this.setTopLevel('boardId', event.detail.value);
    }

    handleTitleChange(event) {
        this.setTopLevel('title', event.detail.value);
    }

    handleObjectChange(event) {
        this.setTopLevel('objectApiName', event.detail.value);
    }

    handleOrientationChange(event) {
        this.setTopLevel('orientation', event.detail.value);
    }

    setTopLevel(key, value) {
        const next = { ...this.config };
        if (hasText(value)) {
            next[key] = value;
        } else {
            delete next[key];
        }
        if (key in this.references) {
            const references = { ...this.references };
            delete references[key];
            this.references = references;
        }
        this.commit(next, [key]);
    }

    // ---- Filter bindings -----------------------------------------------------------------------------------------

    get bindings() {
        return isPlainObject(this.config.filterBindings) ? this.config.filterBindings : {};
    }

    get discovery() {
        return discoverFilterWidgets(this._builderContext, this._elementInfo, this.config.boardId);
    }

    get discoveryMessage() {
        const { widgets, sameScreen } = this.discovery;
        const boardId = this.config.boardId || 'default';
        if (!widgets.length) {
            return `No Filter widget with Board id "${boardId}" was found on this screen. Add a filterId manually to bind a Filter widget that lives outside this Flow.`;
        }
        const names = widgets.map((widget) => widget.name).join(', ');
        const where = sameScreen ? 'on this screen' : 'in this Flow';
        return `Filter widget ${names} found ${where} (Board id "${boardId}"). Filters bind by convention on ${
            this.objectApiNameValue || 'the selected object'
        } unless overridden.`;
    }

    get bindingRows() {
        const { widgets } = this.discovery;
        const definitions = [];
        const seen = new Set();
        widgets.forEach((widget) =>
            widget.filters.forEach((def) => {
                if (!seen.has(def.filterId)) {
                    seen.add(def.filterId);
                    definitions.push(def);
                }
            })
        );
        const includeRecordContext = widgets.some((widget) => widget.scopesRecordContext);
        const preview =
            this.objectApiNameValue && !this.previewLoading && !this.previewError
                ? previewConventionBindings({
                      objectApiName: this.objectApiNameValue,
                      fields: this.previewFields,
                      filters: definitions,
                      includeRecordContext
                  })
                : null;

        const rows = definitions.map((def) =>
            this.bindingRow(def.filterId, def.label, FILTER_TYPE_LABELS[def.type], false, preview)
        );
        if (includeRecordContext) {
            seen.add(RECORD_CONTEXT_FILTER_ID);
            rows.push(this.bindingRow(RECORD_CONTEXT_FILTER_ID, 'Record context', 'Record', false, preview));
        }
        [...Object.keys(this.bindings), ...this.manualFilterIds].forEach((filterId) => {
            if (!seen.has(filterId)) {
                seen.add(filterId);
                rows.push(this.bindingRow(filterId, filterId, 'Manual', true, null));
            }
        });
        return rows;
    }

    get hasBindingRows() {
        return this.bindingRows.length > 0;
    }

    bindingRow(filterId, label, typeLabel, isManual, preview) {
        const hasBinding = Object.prototype.hasOwnProperty.call(this.bindings, filterId);
        const binding = this.bindings[filterId];
        let mode = MODE_CONVENTION;
        if (this.pendingPathIds.includes(filterId)) {
            mode = MODE_PATH;
        } else if (hasBinding) {
            mode = isIgnoreBinding(binding) ? MODE_IGNORE : MODE_PATH;
        }
        const path = this.hasPathBinding(filterId) ? String(binding) : '';
        const previewItem = preview ? preview.get(filterId) : null;
        const conventionText = isManual ? 'Resolved by convention at runtime' : this.conventionText(previewItem);
        let effectiveText = conventionText;
        let status =
            isManual || (previewItem && RESOLVED_CONVENTION.includes(previewItem.status)) ? 'bound' : 'unbound';
        if (mode === MODE_IGNORE || (mode === MODE_PATH && hasBinding && !path)) {
            effectiveText = 'Ignored by this widget';
            status = 'ignored';
        } else if (path) {
            effectiveText = path;
            status = 'bound';
        }
        return {
            key: filterId,
            filterId,
            label,
            typeLabel,
            isManual,
            mode,
            isPath: mode === MODE_PATH,
            path,
            conventionText,
            effectiveText,
            status,
            error: path && !isValidBindingPath(path) ? `Invalid binding. ${BINDING_PATH_HELP}` : null
        };
    }

    conventionText(item) {
        if (!this.objectApiNameValue) {
            return 'Select an object to preview';
        }
        if (this.previewLoading) {
            return 'Loading fields…';
        }
        if (this.previewError) {
            return this.previewError;
        }
        switch (item ? item.status : null) {
            case 'BOUND':
                return item.fieldPath;
            case 'RUNTIME':
                return 'Record Id (matched at runtime)';
            case 'SOSL':
                return 'SOSL search (all searchable fields)';
            default:
                return 'Unbound (skipped)';
        }
    }

    handleBindingModeChange(event) {
        const filterId = event.target.dataset.filterId;
        const mode = event.detail.value;
        this.pendingPathIds = this.pendingPathIds.filter((id) => id !== filterId);
        if (mode === MODE_IGNORE) {
            this.setBinding(filterId, IGNORE_BINDING);
            return;
        }
        if (mode === MODE_PATH) {
            // An existing IGNORE stays in effect until a path is entered; validate() blocks an empty path.
            this.pendingPathIds = [...this.pendingPathIds, filterId];
            return;
        }
        this.setBinding(filterId, undefined);
    }

    /** True when `filterId` has a non-IGNORE path binding. */
    hasPathBinding(filterId) {
        return (
            Object.prototype.hasOwnProperty.call(this.bindings, filterId) && !isIgnoreBinding(this.bindings[filterId])
        );
    }

    handleBindingPathChange(event) {
        const value = event.detail.value;
        this.setBinding(event.target.dataset.filterId, hasText(value) ? value.trim() : undefined);
    }

    handleBindingPick(event) {
        const value = event.detail.value;
        this.setBinding(event.target.dataset.filterId, hasText(value) ? value : undefined);
    }

    setBinding(filterId, value) {
        const bindings = { ...this.bindings };
        if (value === undefined) {
            if (!(filterId in bindings)) {
                return;
            }
            delete bindings[filterId];
        } else {
            bindings[filterId] = value;
        }
        const next = { ...this.config };
        if (Object.keys(bindings).length) {
            next.filterBindings = bindings;
        } else {
            delete next.filterBindings;
        }
        this.commit(next);
    }

    handleManualDraftChange(event) {
        this.manualDraft = event.detail.value || '';
        this.manualError = null;
    }

    handleManualAdd() {
        const filterId = this.manualDraft.trim();
        if (!filterId) {
            this.manualError = 'Enter a filterId.';
            return;
        }
        if (this.bindingRows.some((row) => row.filterId === filterId)) {
            this.manualError = `"${filterId}" is already listed.`;
            return;
        }
        this.manualFilterIds = [...this.manualFilterIds, filterId];
        this.pendingPathIds = [...this.pendingPathIds, filterId];
        this.manualDraft = '';
        this.manualError = null;
    }

    handleManualRemove(event) {
        const filterId = event.target.dataset.filterId;
        this.manualFilterIds = this.manualFilterIds.filter((id) => id !== filterId);
        this.pendingPathIds = this.pendingPathIds.filter((id) => id !== filterId);
        this.setBinding(filterId, undefined);
    }

    // ---- Base filters --------------------------------------------------------------------------------------------

    get baseFilters() {
        return Array.isArray(this.config.baseFilters) ? this.config.baseFilters : [];
    }

    get hasBaseFilters() {
        return this.baseFilters.length > 0;
    }

    /** Read-only list: `Status · Closed, Duplicate`, operator badge, and error indicator of each saved condition. */
    get baseFilterRows() {
        const errors = baseFilterErrorsByIndex(this.baseFilters);
        return this.baseFilters.map((condition, index) => {
            const { label, operatorLabel, valueText } = baseFilterSummary(condition, index);
            const id = isPlainObject(condition) ? condition.id : null;
            return {
                key: `condition-${index}`,
                id,
                text: joinSummary([label, valueText]),
                operatorLabel,
                hasError: errors[index].length > 0,
                errorText: `${label} has errors. Edit base filters to fix them.`
            };
        });
    }

    /**
     * Opens the Base filters Config dialog on a draft of the conditions. Save applies the draft as one config change;
     * Cancel, Escape, and the header X change nothing. Focus then returns to "Edit base filters…".
     */
    async handleEditBaseFilters() {
        const result = await openConfigDialog(BoardBaseFilterDialog, {
            label: 'Edit base filters',
            description: 'Add, reorder, remove, and edit the static conditions that scope this Widget.',
            value: this.baseFilters,
            objectApiName: this.objectApiNameValue || null
        });
        if (result.action === DIALOG_SAVE) {
            const draft = Array.isArray(result.draft) ? result.draft : [];
            this.updateConfig({ baseFilters: draft.length ? draft : null });
            // Let the read-only list re-render before restoring focus, so focus is not lost to <body>.
            await Promise.resolve();
        }
        const button = this.template.querySelector('lightning-button.c-cpe-base-filters-edit');
        if (button) {
            button.focus();
        }
    }

    // ---- Advanced: Config JSON -----------------------------------------------------------------------------------

    get hasDraft() {
        return this.jsonDraft !== null;
    }

    get jsonText() {
        return this.hasDraft ? this.jsonDraft : formatConfig(this._widgetType, this.config);
    }

    get hasDraftErrors() {
        return this.draftErrors.length > 0;
    }

    get draftIsValid() {
        return this.hasDraft && !this.hasDraftErrors;
    }

    get applyDisabled() {
        return !this.draftIsValid;
    }

    get discardDisabled() {
        return !this.hasDraft;
    }

    get draftErrorItems() {
        return this.draftErrors.map((message, index) => ({ key: `error-${index}`, message }));
    }

    handleJsonInput(event) {
        const text = event.target.value;
        this.jsonDraft = text;
        this.draftErrors = validateConfigText(this._widgetType, text, this.keptReferences(text)).errors;
        this.drawerMessage = null;
    }

    /** Flow resource references the pasted JSON does not set; applying keeps them bound. */
    keptReferences(text) {
        let parsed = null;
        try {
            parsed = JSON.parse(text);
        } catch (err) {
            parsed = null;
        }
        const kept = { ...this.references };
        if (isPlainObject(parsed)) {
            Object.keys(kept).forEach((key) => {
                if (hasText(parsed[key])) {
                    delete kept[key];
                }
            });
        }
        return kept;
    }

    handleApplyJson() {
        const references = this.keptReferences(this.jsonDraft);
        const { config, errors } = validateConfigText(this._widgetType, this.jsonDraft, references);
        if (errors.length) {
            this.draftErrors = errors;
            return;
        }
        this.jsonDraft = null;
        this.draftErrors = [];
        this.pendingPathIds = [];
        this.manualFilterIds = [];
        this.references = references;
        this.commit(
            config,
            topLevelKeysFor(this._widgetType).filter((key) => !(key in references))
        );
        this.drawerMessage = 'Pasted configuration applied.';
    }

    handleDiscardJson() {
        this.jsonDraft = null;
        this.draftErrors = [];
        this.drawerMessage = null;
    }

    async handleCopyJson() {
        const text = this.jsonText;
        let copied = false;
        try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                await navigator.clipboard.writeText(text);
                copied = true;
            }
        } catch (err) {
            copied = false;
        }
        if (!copied) {
            const textarea = this.template.querySelector('textarea.c-cpe-json');
            if (textarea) {
                textarea.select();
                try {
                    copied = document.execCommand('copy');
                } catch (err) {
                    copied = false;
                }
            }
        }
        this.drawerMessage = copied
            ? 'Config JSON copied. Paste it into the configJson property in Lightning App Builder.'
            : 'Copy failed. The JSON is selected; press Ctrl+C (Cmd+C) to copy it.';
    }
}