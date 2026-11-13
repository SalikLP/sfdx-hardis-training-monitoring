import { LightningElement, api } from 'lwc';
import { IGNORE_BINDING, normalizeBoardError } from 'c/boardConfigUtils';
import { BINDING_PATH_HELP, cleanString, hasText, loadObjectFields } from 'c/boardCpeUtils';
import {
    MODE_CONVENTION,
    MODE_IGNORE,
    MODE_PATH,
    bindingRowErrors,
    bindingRows,
    bindingsOf,
    discoverFilterWidgets,
    discoveryMessage
} from 'c/boardCpeBindings';

const BINDING_MODE_OPTIONS = [
    { label: 'By convention', value: MODE_CONVENTION },
    { label: 'Field path', value: MODE_PATH },
    { label: 'Ignore', value: MODE_IGNORE }
];

/**
 * Filter bindings editor of a data Widget: the Filters of the Board's discovered Filter widgets (`builderContext`)
 * with their convention binding on the config's object, a binding mode per Filter (convention, field path, ignore),
 * and Filter ids added by hand for Filter widgets outside this Flow. Used in the Config editor panel and in the
 * Filter bindings step of the Setup dialog.
 *
 * Reads `config` (`boardId`, `objectApiName`, `filterBindings`); fires `change` with `detail.filterBindings` (the
 * new map, or null when empty) and `bindingstate` with `detail.rows` and `detail.errors` (`[{ key, errorString }]`)
 * whenever its rows or errors may have changed.
 */
export default class BoardCpeFilterBindings extends LightningElement {
    @api builderContext = {};
    @api elementInfo = {};

    previewFields = [];
    previewLoading = false;
    previewError = null;
    manualFilterIds = [];
    manualDraft = '';
    manualError = null;
    pendingPathIds = [];

    bindingModeOptions = BINDING_MODE_OPTIONS;
    bindingPathHelp = BINDING_PATH_HELP;

    _config = {};
    _previewObject = null;
    _connected = false;

    @api
    get config() {
        return this._config;
    }
    set config(value) {
        this._config = value || {};
        this.refreshPreviewFields();
    }

    /** Design-time errors of the rows (`[{ key: 'filterBindings', errorString }]`). */
    @api
    validate() {
        return bindingRowErrors(this.bindingRows, this.bindings, this.pendingPathIds);
    }

    connectedCallback() {
        this._connected = true;
        this.notifyState();
    }

    disconnectedCallback() {
        this._connected = false;
    }

    get objectApiName() {
        return cleanString(this._config.objectApiName) || '';
    }

    get bindings() {
        return bindingsOf(this._config);
    }

    get discovery() {
        return discoverFilterWidgets(this.builderContext, this.elementInfo, this._config.boardId);
    }

    get discoveryMessage() {
        return discoveryMessage(this.discovery, this._config.boardId, this.objectApiName);
    }

    get bindingRows() {
        return bindingRows({
            discovery: this.discovery,
            bindings: this.bindings,
            objectApiName: this.objectApiName,
            previewFields: this.previewFields,
            previewLoading: this.previewLoading,
            previewError: this.previewError,
            pendingPathIds: this.pendingPathIds,
            manualFilterIds: this.manualFilterIds,
            bucketFields: this._config.bucketFields
        });
    }

    get hasBindingRows() {
        return this.bindingRows.length > 0;
    }

    notifyState() {
        if (this._connected) {
            const rows = this.bindingRows;
            this.dispatchEvent(
                new CustomEvent('bindingstate', {
                    detail: { rows, errors: bindingRowErrors(rows, this.bindings, this.pendingPathIds) }
                })
            );
        }
    }

    refreshPreviewFields() {
        const objectApiName = this.objectApiName || null;
        if (objectApiName === this._previewObject) {
            this.notifyState();
            return;
        }
        this._previewObject = objectApiName;
        this.previewFields = [];
        this.previewError = null;
        this.previewLoading = Boolean(objectApiName);
        this.notifyState();
        if (!objectApiName) {
            return;
        }
        loadObjectFields(objectApiName)
            .then((fields) => {
                if (this._previewObject === objectApiName) {
                    this.previewFields = fields || [];
                    this.previewLoading = false;
                    this.notifyState();
                }
            })
            .catch((err) => {
                if (this._previewObject === objectApiName) {
                    this.previewError = normalizeBoardError(err).message;
                    this.previewLoading = false;
                    this.notifyState();
                }
            });
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
            this.notifyState();
            return;
        }
        this.setBinding(filterId, undefined);
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
                this.notifyState();
                return;
            }
            delete bindings[filterId];
        } else {
            bindings[filterId] = value;
        }
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { filterBindings: Object.keys(bindings).length ? bindings : null }
            })
        );
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
        this.notifyState();
    }

    handleManualRemove(event) {
        const filterId = event.target.dataset.filterId;
        this.manualFilterIds = this.manualFilterIds.filter((id) => id !== filterId);
        this.pendingPathIds = this.pendingPathIds.filter((id) => id !== filterId);
        this.setBinding(filterId, undefined);
    }

    /** Forgets the rows switched to "Field path" and the hand-added ids (e.g. after pasting a whole config). */
    @api
    reset() {
        this.pendingPathIds = [];
        this.manualFilterIds = [];
        this.notifyState();
    }
}