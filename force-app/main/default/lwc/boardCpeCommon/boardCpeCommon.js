import { LightningElement, api } from 'lwc';
import BoardSetupDialog from 'c/boardSetupDialog';
import { normalizeBoardError } from 'c/boardConfigUtils';
import {
    DIALOG_SAVE,
    WIDGET_TYPES,
    applyPatch,
    configErrors,
    deepCopy,
    formatConfig,
    hasText,
    initialSectionOpen,
    isDataWidget,
    isPlainObject,
    loadObjectFields,
    orderConfig,
    joinSummary,
    readCpeState,
    sectionStates,
    serializeConfig,
    toggleSectionOpen,
    topLevelKeysFor,
    validateConfigText
} from 'c/boardCpeUtils';
import { stepsFor } from 'c/boardSetupSteps';
import { bindingRows, bindingsOf, discoverFilterWidgets } from 'c/boardCpeBindings';

const CHANGED_EVENT = 'configuration_editor_input_value_changed';
const DELETED_EVENT = 'configuration_editor_input_value_deleted';

/** The shell's own Config sections (see `sectionStates` in `c/boardCpeUtils`). */
const SECTIONS = [
    {
        name: 'board',
        errorKeys: ['boardId', 'title'],
        summary: (cpe) => cpe.boardSummary,
        openWhenNew: true
    },
    // Advanced: Config JSON; always collapsed on load.
    { name: 'advanced', summary: (cpe) => cpe.advancedSummary, hasError: (cpe) => cpe.hasDraftErrors }
];

/**
 * Shared Flow Custom Property Editor shell composed by every Board CPE (ADR 0002). The panel is an overview: Board
 * (Board id, title, *Wait for Filter widget* for data Widgets), one summary line per Setup dialog step with "Edit…"
 * opening the dialog (`c/boardSetupDialog`) at that step, and Advanced: Config JSON. Everything else (object,
 * orientation, Filter bindings, Base filters, ...) is edited only in the dialog's steps; a Save there applies the
 * whole draft as one config change. Board and Advanced are `c-board-cpe-section`s: Board starts open for a new Widget,
 * Advanced collapsed, and a section with a validation error is forced open.
 *
 * Every edit dispatches `configuration_editor_input_value_changed` (or `..._deleted` for cleared values) for the
 * serialized `configJson`, and also for the discrete top-level property when `boardId`, `title`, or `objectApiName`
 * changes. A non-bubbling `configchange` event (`detail.config`) reports the current config.
 */
export default class BoardCpeCommon extends LightningElement {
    config = { version: 1, widgetType: 'metric' };
    storedJsonError = null;
    references = {};

    previewFields = [];
    previewLoading = false;
    previewError = null;

    /** Open state of the shell's Config sections: set once on load (a new Widget opens Board), then by the Admin. */
    sectionOpen = null;
    jsonDraft = null;
    draftErrors = [];
    drawerMessage = null;

    _widgetType = 'metric';
    _inputVariables = [];
    _builderContext = {};
    _elementInfo = {};
    _previewObject = null;
    _connected = false;

    /** `filter` | `metric` | `chart` | `table` */
    @api
    get widgetType() {
        return this._widgetType;
    }
    set widgetType(value) {
        this._widgetType = WIDGET_TYPES.includes(value) ? value : 'metric';
        this.syncFromInputs();
    }

    /** What the step summaries can't read from the config (e.g. the Group by field type), from the Widget's CPE. */
    @api stepContext = {};

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
        // The discovered Filter widgets' Board-level Bucket fields may have changed.
        this.notifyConfig();
    }

    /** Flow Builder `elementInfo` (`{ apiName, type }`) identifying the screen component being edited. */
    @api
    get elementInfo() {
        return this._elementInfo;
    }
    set elementInfo(value) {
        this._elementInfo = value || {};
        this.notifyConfig();
    }

    /** Current config (version 1 envelope) as a plain object. */
    @api
    getConfig() {
        return deepCopy(this.config);
    }

    /**
     * Shallow-merges `patch` into the config (null/undefined removes a key), then emits `configJson` and, for
     * `boardId`/`title`/`objectApiName` keys, the top-level property.
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
     * Design-time errors (`[{ key, errorString }]`): the Config JSON draft or saved JSON, the shared envelope rules and
     * the widget's own rules (`configErrors`).
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
        errors.push(
            ...configErrors(this._widgetType, this.config, this.references, {
                boardBucketFields: this.boardBucketFields
            })
        );
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

    /**
     * Applies one config change: one `configJson` event, plus one per changed top-level property. The top-level
     * events are required, not duplicates: `boardId`, `title` and `objectApiName` are separate Flow inputs in the
     * Widget's meta, and Flow Builder keeps their last value. `readCpeState` lets a stored top-level value override
     * `configJson` when the editor reopens, so a Setup dialog Save that changes the object without also writing
     * `objectApiName` would reopen on the old object.
     */
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

    /**
     * `configchange` detail: the config, plus the Board-level Bucket fields (`boardBucketFields`) of the discovered
     * Filter widgets on this Board, which a data Widget can use by id.
     */
    notifyConfig() {
        if (this._connected) {
            this.dispatchEvent(
                new CustomEvent('configchange', {
                    detail: { config: deepCopy(this.config), boardBucketFields: deepCopy(this.boardBucketFields) }
                })
            );
        }
    }

    /** Bucket fields of the Filter widgets discovered on this Board (`builderContext`). */
    get boardBucketFields() {
        if (!this.isDataWidget) {
            return [];
        }
        return this.discovery.widgets.flatMap((widget) => widget.bucketFields);
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

    /** `default · Account`; the object part only for data Widgets. */
    get boardSummary() {
        const boardId = this.boardIdValue || 'default';
        if (!this.isDataWidget) {
            return boardId;
        }
        const object = this.objectApiNameValue || this.references.objectApiName || 'No object';
        return joinSummary([boardId, object]);
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

    get boardIdValue() {
        return this.config.boardId || '';
    }

    get titleValue() {
        return this.config.title || '';
    }

    get objectApiNameValue() {
        return this.config.objectApiName || '';
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

    /** Wait for Filter widget: on unless the config says `false`. */
    get waitForFilterWidgetValue() {
        return this.config.waitForFilterWidget !== false;
    }

    /** Off writes `waitForFilterWidget: false`; on removes the key (missing = on). */
    handleWaitForFilterWidgetChange(event) {
        const next = { ...this.config };
        if (event.detail.checked) {
            delete next.waitForFilterWidget;
        } else {
            next.waitForFilterWidget = false;
        }
        this.commit(next);
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

    get discovery() {
        return discoverFilterWidgets(this._builderContext, this._elementInfo, this.config.boardId);
    }

    /** The Filter binding rows of the config, for the Filter bindings step summary. */
    get bindingRows() {
        return bindingRows({
            discovery: this.discovery,
            bindings: bindingsOf(this.config),
            objectApiName: this.objectApiNameValue,
            previewFields: this.previewFields,
            previewLoading: this.previewLoading,
            previewError: this.previewError,
            bucketFields: this.config.bucketFields
        });
    }

    // ---- Setup dialog --------------------------------------------------------------------------------------------

    /** What the step summaries and validators read besides the config. */
    get stepSummaryContext() {
        return {
            ...(this.stepContext || {}),
            references: this.references,
            boardBucketFields: this.boardBucketFields,
            bindingRows: this.bindingRows
        };
    }

    /** One line per Setup dialog step: label, summary of the config, error flag. */
    get setupSteps() {
        const context = this.stepSummaryContext;
        return stepsFor(this._widgetType).map((step) => ({
            name: step.name,
            label: step.label,
            summary: step.summary(this.config, context),
            hasError: step.validate(this.config, context).length > 0,
            editLabel: `Edit ${step.label}`
        }));
    }

    get hasSetupSteps() {
        return stepsFor(this._widgetType).length > 0;
    }

    /**
     * Opens the Setup dialog at the step whose "Edit…" was clicked, on a copy of the config. Save applies the
     * returned draft as one config change (plus the top-level properties it changed); Cancel changes nothing.
     * Focus then returns to the "Edit…" button.
     */
    async handleEditStep(event) {
        const startStep = event.target.dataset.step;
        const result = await BoardSetupDialog.open({
            size: 'full',
            label: this.titleValue ? `Set up ${this.titleValue}` : 'Set up the Widget',
            description: 'Each step edits one part of the Widget. Save applies all steps at once.',
            widgetType: this._widgetType,
            config: deepCopy(this.config),
            context: {
                ...this.stepSummaryContext,
                builderContext: this._builderContext,
                elementInfo: this._elementInfo
            },
            startStep
        });
        if (result && result.action === DIALOG_SAVE && isPlainObject(result.config)) {
            const next = { ...result.config, version: this.config.version, widgetType: this.config.widgetType };
            const changedKeys = topLevelKeysFor(this._widgetType).filter(
                (key) => (next[key] || null) !== (this.config[key] || null)
            );
            if (changedKeys.length) {
                const references = { ...this.references };
                changedKeys.forEach((key) => delete references[key]);
                this.references = references;
            }
            this.commit(next, changedKeys);
            await Promise.resolve();
        }
        const button = this.template.querySelector(`lightning-button.c-cpe-step-edit[data-step="${startStep}"]`);
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