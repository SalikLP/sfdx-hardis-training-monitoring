import { LightningElement, api } from 'lwc';
import { isPlainObject } from 'c/boardCpeUtils';

/** How long the draft has to stay unchanged before the preview Widget gets it. */
export const PREVIEW_DEBOUNCE_MS = 600;
const PREVIEW_BOARD_ID_PREFIX = '__setupPreview_';

let previewCount = 0;

/**
 * Live preview pane of the Setup dialog (ADR 0002): renders the real Widget of `widgetType` (`chart`, `metric`,
 * `table`, `filter`) with the dialog's draft `config` and real data. The Filter widget shows its Filter bar with the
 * draft's defaults and `persistence` forced to `NONE`, publishing only on the preview Board id.
 *
 * - The Widget gets a preview Board id unique to this pane and kept for its lifetime (one per dialog), so no Filter
 *   widget ever publishes on it: the Filter context is a fixed empty one and Base filters still apply. The Widget
 *   unsubscribes from the context store when it unmounts (pane hidden, dialog closed).
 * - `livePreview` forces *Wait for Filter widget* off, whatever the draft says.
 * - Draft changes reach the Widget once the draft has been unchanged for `PREVIEW_DEBOUNCE_MS`; the Widget stays
 *   mounted between updates and keeps showing its last result while it re-queries, so the pane doesn't flicker.
 * - Query errors render through the Widget's own error state.
 * - The pane is collapsible: hiding it unmounts the Widget, showing it remounts it with the latest draft (a fresh
 *   query). Each toggle fires `previewtoggle` with `detail.open`, so the host can resize its columns.
 */
export default class BoardSetupPreview extends LightningElement {
    @api widgetType;

    @api
    get config() {
        return this._config;
    }
    set config(value) {
        this._config = value;
        if (this._connected) {
            this.scheduleApply();
        }
    }

    previewBoardId = `${PREVIEW_BOARD_ID_PREFIX}${Date.now().toString(36)}_${++previewCount}`;
    livePreview = true;
    previewConfigJson = '';
    isOpen = true;

    _config;
    _connected = false;
    _timer = null;

    connectedCallback() {
        this._connected = true;
        this.applyDraft();
    }

    disconnectedCallback() {
        this._connected = false;
        this.cancelPending();
    }

    get isChart() {
        return this.widgetType === 'chart';
    }

    get isMetric() {
        return this.widgetType === 'metric';
    }

    get isTable() {
        return this.widgetType === 'table';
    }

    get isFilter() {
        return this.widgetType === 'filter';
    }

    get hint() {
        return this.isFilter
            ? 'The Filter bar with its defaults; selections here are never remembered.'
            : 'Real data with Base filters applied; no Filter context.';
    }

    get toggleLabel() {
        return this.isOpen ? 'Hide preview' : 'Show preview';
    }

    get toggleIcon() {
        return this.isOpen ? 'utility:chevronright' : 'utility:chevronleft';
    }

    get ariaExpanded() {
        return String(this.isOpen);
    }

    scheduleApply() {
        this.cancelPending();
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce: the preview re-queries once editing pauses
        this._timer = setTimeout(() => {
            this._timer = null;
            this.applyDraft();
        }, PREVIEW_DEBOUNCE_MS);
    }

    cancelPending() {
        if (this._timer) {
            clearTimeout(this._timer);
            this._timer = null;
        }
    }

    applyDraft() {
        this.cancelPending();
        let json = '';
        if (isPlainObject(this._config)) {
            // The previewed Filter bar never writes the viewer's selections to Web Storage.
            json = JSON.stringify(this.isFilter ? { ...this._config, persistence: 'NONE' } : this._config);
        }
        if (json !== this.previewConfigJson) {
            this.previewConfigJson = json;
        }
    }

    handleToggle() {
        this.isOpen = !this.isOpen;
        if (this.isOpen) {
            this.applyDraft();
        }
        this.dispatchEvent(new CustomEvent('previewtoggle', { detail: { open: this.isOpen } }));
    }
}