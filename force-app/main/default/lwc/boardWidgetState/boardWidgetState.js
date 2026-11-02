import { LightningElement, api } from 'lwc';

export default class BoardWidgetState extends LightningElement {
    @api state = 'UNCONFIGURED';
    @api widgetType = 'metric';
    @api orientation = 'vertical';
    @api error = null;
    @api hasActiveFilters = false;

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
        return this.widgetType === 'bar';
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
        const noun = { metric: 'metric', bar: 'chart', table: 'table' }[this.widgetType] || 'widget';
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