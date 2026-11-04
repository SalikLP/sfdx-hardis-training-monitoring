import { LightningElement, api } from 'lwc';
import {
    applyPatch,
    countLabel,
    initialSectionOpen,
    isPlainObject,
    joinSummary,
    parseNumber,
    toggleSectionOpen,
    validateCpe,
    widgetSectionStates
} from 'c/boardCpeUtils';

const DIRECTION_OPTIONS = [
    { label: 'Ascending', value: 'ASC' },
    { label: 'Descending', value: 'DESC' }
];

const DEFAULT_PAGE_SIZE = 25;

/** Config sections of the Table Config editor (see `sectionStates` in `c/boardCpeUtils`). */
const SECTIONS = [
    { name: 'columns', errorKeys: ['columns'], summary: (cpe) => cpe.columnsSummary, openWhenNew: true },
    { name: 'sorting', errorKeys: ['sortBy', 'pageSize'], summary: (cpe) => cpe.sortingSummary },
    { name: 'child', errorKeys: ['childRelationship'], summary: (cpe) => cpe.childSummary }
];

/**
 * Flow Custom Property Editor for the Board Table widget: repeatable columns, default sort, page size, row count, and
 * the optional expandable `childRelationship` (relationship, child columns, sort, limit), inside the shared
 * `c-board-cpe-common` shell (Board, Object, Filter bindings, Base filters, Config JSON).
 */
export default class BoardTableCpe extends LightningElement {
    @api inputVariables = [];
    @api builderContext = {};
    @api elementInfo = {};

    config = {};
    /** Set by the shell's first `configchange`; until then `config` is a placeholder and must not flag errors. */
    configLoaded = false;
    directionOptions = DIRECTION_OPTIONS;

    /** Open state of the Config sections: set once on load (a new Widget opens Columns), then by the Admin. */
    sectionOpen = null;

    connectedCallback() {
        if (!this.sectionOpen) {
            this.sectionOpen = initialSectionOpen(SECTIONS, 'table', this.inputVariables);
        }
    }

    @api
    validate() {
        return validateCpe(this.shell, 'table', this.inputVariables);
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

    // ---- Config sections -----------------------------------------------------------------------------------------

    get sections() {
        return widgetSectionStates('table', SECTIONS, this);
    }

    /** `3 columns`, or `No columns`. */
    get columnsSummary() {
        const count = this.columns.length;
        return count ? countLabel(count, 'column') : 'No columns';
    }

    /** `CreatedDate desc · 50 per page`, plus `No row count` when hidden. */
    get sortingSummary() {
        const sort = this.sortBy ? `${this.sortBy} ${this.sortDirection.toLowerCase()}` : 'Default sort';
        const parts = [sort, `${this.config.pageSize ?? DEFAULT_PAGE_SIZE} per page`];
        if (!this.showRowCount) {
            parts.push('No row count');
        }
        return joinSummary(parts);
    }

    /** `None`, or the child relationship and its column count (e.g. `CaseComments · 2 columns`). */
    get childSummary() {
        const child = this.child;
        if (!child) {
            return 'None';
        }
        const relationship = child.relationshipName || child.childObjectApiName || 'No relationship';
        return joinSummary([relationship, countLabel(this.childColumns.length, 'column')]);
    }

    handleSectionToggle(event) {
        this.sectionOpen = toggleSectionOpen(this.sectionOpen, event);
    }

    get objectApiName() {
        return this.config.objectApiName || null;
    }

    get columns() {
        return Array.isArray(this.config.columns) ? this.config.columns : [];
    }

    get sortBy() {
        return this.config.sortBy || '';
    }

    get sortDirection() {
        return this.config.sortDirection === 'DESC' ? 'DESC' : 'ASC';
    }

    get pageSize() {
        return this.config.pageSize ?? '';
    }

    get showRowCount() {
        return this.config.showRowCount !== false;
    }

    handleColumns(event) {
        const columns = event.detail.columns;
        this.update({ columns: columns.length ? columns : null });
    }

    handleSortBy(event) {
        this.update({ sortBy: event.detail.value || null });
    }

    handleSortDirection(event) {
        this.update({ sortDirection: event.detail.value });
    }

    handlePageSize(event) {
        this.update({ pageSize: parseNumber(event.detail.value) });
    }

    handleShowRowCount(event) {
        this.update({ showRowCount: event.detail.checked ? null : false });
    }

    // ---- Child relationship --------------------------------------------------------------------------------------

    get child() {
        return isPlainObject(this.config.childRelationship) ? this.config.childRelationship : null;
    }

    get hasChild() {
        return Boolean(this.child);
    }

    get childValue() {
        const child = this.child;
        return child && child.childObjectApiName && child.foreignKeyField
            ? `${child.childObjectApiName}(${child.foreignKeyField})`
            : '';
    }

    get childObjectApiName() {
        return this.child ? this.child.childObjectApiName || null : null;
    }

    get childLabel() {
        return this.child ? this.child.label || '' : '';
    }

    get childColumns() {
        return this.child && Array.isArray(this.child.columns) ? this.child.columns : [];
    }

    get childSortBy() {
        return this.child ? this.child.sortBy || '' : '';
    }

    get childSortDirection() {
        return this.child && this.child.sortDirection === 'DESC' ? 'DESC' : 'ASC';
    }

    get childLimit() {
        return this.child ? (this.child.limit ?? '') : '';
    }

    handleChildToggle(event) {
        this.update({ childRelationship: event.detail.checked ? { columns: [], limit: 10 } : null });
    }

    handleChildRelationship(event) {
        const rel = event.detail.childRelationship;
        const current = this.child || {};
        const sameChild =
            rel &&
            rel.childObjectApiName === current.childObjectApiName &&
            rel.foreignKeyField === current.foreignKeyField;
        const next = {
            ...current,
            relationshipName: rel ? rel.relationshipName || null : null,
            childObjectApiName: rel ? rel.childObjectApiName : null,
            foreignKeyField: rel ? rel.foreignKeyField : null
        };
        if (!sameChild) {
            // Columns and sort belong to the previous child object.
            next.columns = [];
            delete next.sortBy;
        }
        this.updateChild(next);
    }

    handleChildLabel(event) {
        const value = event.detail.value;
        this.updateChild({ ...this.child, label: value && value.trim() ? value : null });
    }

    handleChildColumns(event) {
        this.updateChild({ ...this.child, columns: event.detail.columns });
    }

    handleChildSortBy(event) {
        this.updateChild({ ...this.child, sortBy: event.detail.value || null });
    }

    handleChildSortDirection(event) {
        this.updateChild({ ...this.child, sortDirection: event.detail.value });
    }

    handleChildLimit(event) {
        this.updateChild({ ...this.child, limit: parseNumber(event.detail.value) });
    }

    updateChild(child) {
        this.update({ childRelationship: applyPatch({}, child) });
    }
}