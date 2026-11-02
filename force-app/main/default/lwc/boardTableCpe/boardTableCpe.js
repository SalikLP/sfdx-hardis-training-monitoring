import { LightningElement, api } from 'lwc';
import { applyPatch, isPlainObject, parseNumber, validateCpe } from 'c/boardCpeUtils';

const DIRECTION_OPTIONS = [
    { label: 'Ascending', value: 'ASC' },
    { label: 'Descending', value: 'DESC' }
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
    directionOptions = DIRECTION_OPTIONS;

    @api
    validate() {
        return validateCpe(this.shell, 'table', this.inputVariables);
    }

    get shell() {
        return this.template.querySelector('c-board-cpe-common');
    }

    handleConfigChange(event) {
        this.config = event.detail.config;
    }

    update(patch) {
        this.shell.updateConfig(patch);
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