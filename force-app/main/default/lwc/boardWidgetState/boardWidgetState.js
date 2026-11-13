import { LightningElement, api } from 'lwc';

/** How long a Widget waits for the Board's Filter widget before the hint card replaces its loading state. */
const WAIT_HINT_DELAY_MS = 5000;

export default class BoardWidgetState extends LightningElement {
    @api state = 'UNCONFIGURED';
    @api widgetType = 'metric';
    @api orientation = 'vertical';
    @api error = null;
    @api hasActiveFilters = false;

    showWaitHint = false;
    _waitingForBoardId = '';
    _waitTimer = null;
    _connected = false;

    /**
     * Board id the Widget is waiting on (Wait for Filter widget, no Filter widget registered yet), or empty. While
     * set during the loading state, the hint card replaces the skeleton after ~5 s; clearing it removes the card.
     */
    @api
    get waitingForBoardId() {
        return this._waitingForBoardId;
    }
    set waitingForBoardId(value) {
        const next = value ? String(value) : '';
        if (next === this._waitingForBoardId) {
            return;
        }
        this._waitingForBoardId = next;
        this.restartWaitTimer();
    }

    connectedCallback() {
        this._connected = true;
        this.restartWaitTimer();
    }

    disconnectedCallback() {
        this._connected = false;
        this.clearWaitTimer();
    }

    restartWaitTimer() {
        this.clearWaitTimer();
        this.showWaitHint = false;
        if (!this._connected || !this._waitingForBoardId) {
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- the hint card appears after a fixed wait
        this._waitTimer = setTimeout(() => {
            this._waitTimer = null;
            this.showWaitHint = true;
        }, WAIT_HINT_DELAY_MS);
    }

    clearWaitTimer() {
        if (this._waitTimer) {
            clearTimeout(this._waitTimer);
            this._waitTimer = null;
        }
    }

    get isWaitHint() {
        return this.showWaitHint && this.isInitialLoading && Boolean(this._waitingForBoardId);
    }

    get isUnconfigured() {
        return this.state === 'UNCONFIGURED';
    }

    get isInitialLoading() {
        return this.state === 'INITIAL_LOADING';
    }

    get isEmpty() {
        return this.state === 'EMPTY';
    }

    get isError() {
        return this.state === 'ERROR';
    }

    get isMetricSkeleton() {
        return this.widgetType === 'metric';
    }

    get isBarSkeleton() {
        return this.widgetType === 'chart';
    }

    get isTableSkeleton() {
        return this.widgetType === 'table';
    }

    get barContainerClass() {
        return this.orientation === 'horizontal'
            ? 'c-board-skeleton-bars c-board-skeleton-bars_horizontal'
            : 'c-board-skeleton-bars';
    }

    /** Screen-reader announcement for the visual-only skeleton. */
    get loadingText() {
        const noun = { metric: 'metric', chart: 'chart', table: 'table' }[this.widgetType] || 'widget';
        return `Loading ${noun}…`;
    }

    get emptySubtext() {
        return this.hasActiveFilters
            ? 'Try adjusting or resetting the board filters.'
            : 'No records match the widget criteria.';
    }

    get errorMessage() {
        return this.error?.message || 'An unexpected error occurred.';
    }

    get errorDetails() {
        const parts = [];
        if (this.error?.filterId) {
            parts.push(`Filter: ${this.error.filterId}`);
        }
        if (this.error?.fieldPath) {
            parts.push(`Field: ${this.error.fieldPath}`);
        }
        return parts.length > 0 ? parts.join(' · ') : '';
    }

    get isRetryable() {
        return Boolean(this.error?.retryable);
    }

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry'));
    }
}