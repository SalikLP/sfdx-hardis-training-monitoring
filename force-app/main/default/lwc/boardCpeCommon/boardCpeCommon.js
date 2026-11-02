import { LightningElement, api } from 'lwc';
import { IGNORE_BINDING, RECORD_CONTEXT_FILTER_ID, DATE_PRESETS, normalizeBoardError } from 'c/boardConfigUtils';
import {
    BASE_FILTER_OPERATOR_OPTIONS,
    BINDING_PATH_HELP,
    FILTER_TYPE_LABELS,
    LIST_OPERATORS,
    ORIENTATION_OPTIONS,
    WIDGET_TYPES,
    applyPatch,
    baseFilterError,
    configErrors,
    formatConfig,
    isDataWidget,
    isDatePreset,
    isIgnoreBinding,
    isPlainObject,
    isRelativeDateLiteral,
    isValidBindingPath,
    loadObjectFields,
    nextSequentialId,
    orderConfig,
    readCpeState,
    serializeConfig,
    topLevelKeysFor,
    validateConfigText
} from 'c/boardCpeUtils';
import { discoverFilterWidgets, previewConventionBindings } from './cpeConfig';

const CHANGED_EVENT = 'configuration_editor_input_value_changed';
const DELETED_EVENT = 'configuration_editor_input_value_deleted';
const MODE_CONVENTION = 'CONVENTION';
const MODE_PATH = 'PATH';
const MODE_IGNORE = 'IGNORE';
const CUSTOM_LITERAL = '__CUSTOM__';

const BINDING_MODE_OPTIONS = [
    { label: 'By convention', value: MODE_CONVENTION },
    { label: 'Field path', value: MODE_PATH },
    { label: 'Ignore', value: MODE_IGNORE }
];
const NULL_OPTIONS = [
    { label: 'Is null', value: 'true' },
    { label: 'Is not null', value: 'false' }
];
const LITERAL_OPTIONS = [...DATE_PRESETS, { label: 'Custom literal (e.g. LAST_N_DAYS:45)', value: CUSTOM_LITERAL }];

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function hasText(value) {
    return typeof value === 'string' ? value.trim() !== '' : value !== null && value !== undefined;
}

/**
 * Shared Flow Custom Property Editor shell composed by every Board CPE.
 *
 * Renders the Board id/title header (plus the Object Picker for data Widgets and orientation for Bar), a default
 * slot for widget-specific sections, the `builderContext` Filter widget discovery + `filterBindings` override table
 * and visual Base filter builder (data Widgets), and the "View / Copy Config JSON" portability drawer.
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
    customLiteralIds = [];

    isDrawerOpen = false;
    jsonDraft = null;
    draftErrors = [];
    drawerMessage = null;

    bindingModeOptions = BINDING_MODE_OPTIONS;
    operatorOptions = BASE_FILTER_OPERATOR_OPTIONS;
    nullOptions = NULL_OPTIONS;
    literalOptions = LITERAL_OPTIONS;
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
        return clone(this.config);
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
            this.dispatchEvent(new CustomEvent('configchange', { detail: { config: clone(this.config) } }));
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
        const conventionText = isManual
            ? 'Resolved by convention at runtime'
            : this.conventionText(preview ? preview.get(filterId) : null);
        let effectiveText = conventionText;
        if (mode === MODE_IGNORE || (mode === MODE_PATH && hasBinding && !path)) {
            effectiveText = 'Ignored by this widget';
        } else if (path) {
            effectiveText = path;
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

    get baseFilterRows() {
        return this.baseFilters.map((condition, index) => {
            const safe = isPlainObject(condition) ? condition : {};
            const operator = safe.operator || 'EQ';
            const value = safe.value;
            const isList = LIST_OPERATORS.has(operator);
            const isNull = operator === 'IS_NULL';
            const isLiteral = operator === 'LITERAL';
            const literal = typeof value === 'string' ? value.trim().toUpperCase() : '';
            const isCustomLiteral =
                isLiteral && (this.customLiteralIds.includes(safe.id) || (literal !== '' && !isDatePreset(literal)));
            let scalarValue = '';
            if (Array.isArray(value)) {
                scalarValue = value.join(', ');
            } else if (value !== null && value !== undefined) {
                scalarValue = String(value);
            }
            return {
                key: safe.id || `index-${index}`,
                id: safe.id,
                number: index + 1,
                title: `Condition ${index + 1}`,
                fieldPath: safe.fieldPath || '',
                operator,
                isList,
                isNull,
                isLiteral,
                isCustomLiteral,
                isScalar: !isList && !isNull && !isLiteral,
                scalarValue,
                nullValue: value === false || value === 'false' ? 'false' : 'true',
                literalSelection: isCustomLiteral ? CUSTOM_LITERAL : literal,
                literalValue: literal,
                error: baseFilterError(safe)
            };
        });
    }

    handleAddBaseFilter() {
        const condition = { id: nextSequentialId(this.baseFilters, 'bf'), fieldPath: '', operator: 'EQ', value: null };
        this.commit({ ...this.config, baseFilters: [...this.baseFilters, condition] });
    }

    handleRemoveBaseFilter(event) {
        const id = event.target.dataset.id;
        const remaining = this.baseFilters.filter((condition) => condition.id !== id);
        this.customLiteralIds = this.customLiteralIds.filter((item) => item !== id);
        const next = { ...this.config };
        if (remaining.length) {
            next.baseFilters = remaining;
        } else {
            delete next.baseFilters;
        }
        this.commit(next);
    }

    handleBaseFilterField(event) {
        const value = event.detail.value;
        this.updateBaseFilter(event.target.dataset.id, { fieldPath: hasText(value) ? value : '' });
    }

    handleBaseFilterOperator(event) {
        const id = event.target.dataset.id;
        const operator = event.detail.value;
        const current = this.baseFilters.find((condition) => condition.id === id);
        this.customLiteralIds = this.customLiteralIds.filter((item) => item !== id);
        this.updateBaseFilter(id, { operator, value: convertValue(operator, current ? current.value : null) });
    }

    handleBaseFilterValue(event) {
        const value = event.detail.value;
        this.updateBaseFilter(event.target.dataset.id, { value: hasText(value) ? value : null });
    }

    handleBaseFilterList(event) {
        const values = String(event.detail.value || '')
            .split(',')
            .map((item) => item.trim())
            .filter(Boolean);
        this.updateBaseFilter(event.target.dataset.id, { value: values });
    }

    handleBaseFilterNull(event) {
        this.updateBaseFilter(event.target.dataset.id, { value: event.detail.value !== 'false' });
    }

    handleBaseFilterLiteral(event) {
        const id = event.target.dataset.id;
        const selection = event.detail.value;
        if (selection === CUSTOM_LITERAL) {
            if (!this.customLiteralIds.includes(id)) {
                this.customLiteralIds = [...this.customLiteralIds, id];
            }
            return;
        }
        this.customLiteralIds = this.customLiteralIds.filter((item) => item !== id);
        this.updateBaseFilter(id, { value: selection });
    }

    handleBaseFilterCustomLiteral(event) {
        const value = String(event.detail.value || '')
            .trim()
            .toUpperCase();
        this.updateBaseFilter(event.target.dataset.id, { value: value || null });
    }

    updateBaseFilter(id, patch) {
        const baseFilters = this.baseFilters.map((condition) => {
            return condition.id === id ? { ...condition, ...patch } : condition;
        });
        this.commit({ ...this.config, baseFilters });
    }

    // ---- Config JSON drawer --------------------------------------------------------------------------------------

    get drawerToggleIcon() {
        return this.isDrawerOpen ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get drawerExpanded() {
        return String(this.isDrawerOpen);
    }

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

    handleToggleDrawer() {
        this.isDrawerOpen = !this.isDrawerOpen;
        this.drawerMessage = null;
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
        this.customLiteralIds = [];
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

function convertValue(operator, value) {
    if (LIST_OPERATORS.has(operator)) {
        if (Array.isArray(value)) {
            return value;
        }
        return hasText(value) && typeof value !== 'boolean' ? [String(value)] : [];
    }
    if (operator === 'IS_NULL') {
        return true;
    }
    if (operator === 'LITERAL') {
        return isRelativeDateLiteral(value) ? String(value).trim().toUpperCase() : 'TODAY';
    }
    if (Array.isArray(value)) {
        return value.length ? value[0] : null;
    }
    return typeof value === 'boolean' ? null : value;
}