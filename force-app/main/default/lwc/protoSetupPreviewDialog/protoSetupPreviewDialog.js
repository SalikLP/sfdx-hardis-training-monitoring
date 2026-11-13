// PROTOTYPE, throwaway. Wayfinder ticket "Live preview in the Setup dialog" (.scratch/crma-parity/issues/23).
// Question: can a LightningModal opened from a Flow Builder Config editor render the real Bar widget from a draft
// config, with real data, Base filters applied and no Filter context?
import { api } from 'lwc';
import LightningModal from 'lightning/modal';

const DEBOUNCE_MS = 600;
let openCount = 0;

/** Quick draft mutations to provoke the cases the ticket asks about. */
const PRESETS = [
    { key: 'stage', label: 'Group by StageName, Count', patch: { groupByField: 'StageName', stackByField: null, aggregateFunction: 'COUNT', valueFieldApiName: null, format: null } },
    { key: 'sum', label: 'Sum of Amount by Type', patch: { groupByField: 'Type', stackByField: null, aggregateFunction: 'SUM', valueFieldApiName: 'Amount' } },
    { key: 'cap', label: '>2,000 groups (Name)', patch: { groupByField: 'Name', stackByField: null, aggregateFunction: 'COUNT', valueFieldApiName: null, format: null } },
    { key: 'day', label: 'CreatedDate by Day', patch: { groupByField: 'CreatedDate', stackByField: null, dateGranularity: 'DAY', aggregateFunction: 'COUNT', format: null } },
    { key: 'badfield', label: 'Unknown field (error)', patch: { groupByField: 'No_Such_Field__c' } },
    { key: 'badobject', label: 'Unknown object (error)', patch: { objectApiName: 'No_Such_Object__c' } },
    { key: 'basefilter', label: 'Base filter: IsClosed = false', patch: { baseFilters: [{ id: 'bf1', fieldPath: 'IsClosed', operator: 'EQ', value: false }] } },
    { key: 'horizontal', label: 'Horizontal', patch: { orientation: 'horizontal' } }
];

export default class ProtoSetupPreviewDialog extends LightningModal {
    /** Draft config object handed in by the Config editor. */
    @api config;

    draftText = '';
    parseError = '';
    previewConfigJson = '';
    previewObjectApiName = '';
    previewOrientation = '';
    previewBoardId = '';
    previewOpen = true;
    debounceMs = DEBOUNCE_MS;
    log = [];

    presets = PRESETS;
    _timer = null;
    _t0 = 0;

    connectedCallback() {
        openCount += 1;
        // A Board id no Filter widget will ever use: the context store's microtask fallback publishes an empty
        // READY Filter context, so the Widget queries at once ("Wait for Filter widget" behaves as off).
        this.previewBoardId = `__setupPreview_${Date.now()}_${openCount}`;
        this._t0 = Date.now();
        const draft = this.config ? JSON.parse(JSON.stringify(this.config)) : {};
        this.draftText = JSON.stringify(draft, null, 2);
        this.applyDraft('open');
        this.addLog(`opened; boardId=${this.previewBoardId}; inFlowBuilder=${this.inFlowBuilder}`);
    }

    disconnectedCallback() {
        clearTimeout(this._timer);
    }

    get inFlowBuilder() {
        try {
            return /flowBuilder|builder_platform_interaction/i.test(window.location.href);
        } catch (e) {
            return 'unknown';
        }
    }

    get previewToggleLabel() {
        return this.previewOpen ? 'Hide preview' : 'Show preview';
    }

    get editorClass() {
        return this.previewOpen ? 'slds-col slds-size_1-of-3 c-pane' : 'slds-col slds-size_1-of-1 c-pane';
    }

    get hasPreview() {
        return this.previewOpen && Boolean(this.previewConfigJson);
    }

    get logText() {
        return this.log.join('\n');
    }

    addLog(line) {
        const ms = String(Date.now() - this._t0).padStart(6, ' ');
        this.log = [`${ms}ms  ${line}`, ...this.log].slice(0, 60);
    }

    /** Native textarea, written imperatively so re-renders never overwrite what the Admin is typing. */
    renderedCallback() {
        const el = this.refs && this.refs.draft;
        if (el && this._writtenText !== this.draftText) {
            el.value = this.draftText;
            this._writtenText = this.draftText;
        }
    }

    readTextarea() {
        const el = this.refs && this.refs.draft;
        if (el) {
            this.draftText = el.value;
            this._writtenText = el.value;
        }
    }

    handleDraftInput(event) {
        const value = event.target.value;
        this.draftText = value;
        this._writtenText = value;
        this.addLog(`change event (${value.length} chars)`);
        this.scheduleApply('typing');
    }

    handleApplyNow() {
        clearTimeout(this._timer);
        this.readTextarea();
        this.applyDraft('apply now');
    }

    handlePreset(event) {
        this.readTextarea();
        const preset = PRESETS.find((p) => p.key === event.currentTarget.dataset.key);
        let draft;
        try {
            draft = JSON.parse(this.draftText || '{}');
        } catch (e) {
            draft = {};
        }
        Object.assign(draft, preset.patch);
        this.draftText = JSON.stringify(draft, null, 2);
        this.scheduleApply(`preset ${preset.key}`);
    }

    handleDebounce(event) {
        this.debounceMs = Number(event.target.value) || 0;
    }

    scheduleApply(reason) {
        clearTimeout(this._timer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timer = setTimeout(() => this.applyDraft(reason), this.debounceMs);
    }

    applyDraft(reason) {
        let draft;
        try {
            draft = JSON.parse(this.draftText || '{}');
        } catch (e) {
            this.parseError = `Invalid JSON, preview keeps the last valid draft: ${e.message}`;
            this.addLog(`${reason}: parse error`);
            return;
        }
        this.parseError = '';
        const json = JSON.stringify(draft);
        if (json === this.previewConfigJson) {
            this.addLog(`${reason}: no change`);
            return;
        }
        this.previewObjectApiName = draft.objectApiName || '';
        this.previewOrientation = draft.orientation || '';
        this.previewConfigJson = json;
        this.addLog(`${reason}: preview updated (object=${this.previewObjectApiName || '—'}, groupBy=${draft.groupByField || '—'})`);
    }

    handleTogglePreview() {
        this.previewOpen = !this.previewOpen;
        this.addLog(this.previewOpen ? 'preview shown (Widget remounts)' : 'preview hidden (Widget unmounts)');
    }

    handleCancel() {
        this.close(null);
    }

    handleSave() {
        this.readTextarea();
        try {
            this.close(JSON.parse(this.draftText || '{}'));
        } catch (e) {
            this.parseError = `Can't save invalid JSON: ${e.message}`;
        }
    }
}