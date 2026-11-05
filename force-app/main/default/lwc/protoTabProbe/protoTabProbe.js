// PROTOTYPE (throwaway): answers "Tabs sharing one Filter context". Logs mount/unmount, visibility and every
// Filter context delivery, into a timeline shared by all probes on the page (module-level = survives remounts,
// reset only by a full page reload). A delivery while connected = one query a real Widget would run.
import { LightningElement, api, track } from 'lwc';
import { subscribeFilterContext } from 'c/boardContextStore';

const PAGE_LOADED_AT = Date.now();
const timeline = [];
const mounts = {};
const renderers = new Set();

function log(label, event, detail = '') {
    const t = ((Date.now() - PAGE_LOADED_AT) / 1000).toFixed(1);
    timeline.unshift({ key: `${timeline.length}`, line: `+${t}s  [${label}]  ${event}  ${detail}` });
    renderers.forEach((r) => r());
}

function summarize(ctx) {
    const filters = Object.entries(ctx.filters || {})
        .map(([id, f]) => `${id}=${JSON.stringify(f && (f.value !== undefined ? f.value : f))}`)
        .join(', ');
    return `status=${ctx.status} updatedAt=${ctx.updatedAt} filters{${filters || 'none'}}`;
}

export default class ProtoTabProbe extends LightningElement {
    @api boardId = 'default';
    @api label = 'probe';
    @track lines = [];
    deliveries = 0;
    hiddenDeliveries = 0;
    visible = null;
    _unsub;
    _observer;
    _render = () => {
        this.lines = timeline.slice(0, 60);
    };

    get mountCount() {
        return mounts[this.label] || 0;
    }

    connectedCallback() {
        mounts[this.label] = (mounts[this.label] || 0) + 1;
        renderers.add(this._render);
        log(this.label, `CONNECTED (mount #${mounts[this.label]})`, `boardId=${this.boardId}`);
        this._unsub = subscribeFilterContext(this.boardId, null, (ctx) => {
            this.deliveries += 1;
            const hidden = this.visible === false;
            if (hidden) {
                this.hiddenDeliveries += 1;
            }
            log(this.label, `CONTEXT${hidden ? ' (while HIDDEN)' : ''} -> would query`, summarize(ctx));
        });
        this._render();
    }

    renderedCallback() {
        if (this._observer || typeof window.IntersectionObserver !== 'function') {
            return;
        }
        this._observer = new window.IntersectionObserver((entries) => {
            const nowVisible = entries.some((e) => e.isIntersecting || e.boundingClientRect.width > 0);
            if (nowVisible !== this.visible) {
                this.visible = nowVisible;
                log(this.label, nowVisible ? 'SHOWN' : 'HIDDEN');
            }
        });
        this._observer.observe(this.template.host);
    }

    disconnectedCallback() {
        if (this._unsub) {
            this._unsub();
        }
        if (this._observer) {
            this._observer.disconnect();
            this._observer = null;
        }
        renderers.delete(this._render);
        log(this.label, 'DISCONNECTED');
    }

    handleClear() {
        timeline.length = 0;
        renderers.forEach((r) => r());
    }
}