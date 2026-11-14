import { LightningElement, api } from 'lwc';
import { SetupStepContent } from 'c/boardSetupStepContent';
import {
    DATE_FIELD_TYPES,
    DATE_GRANULARITY_OPTIONS,
    isPlainObject,
    parseNumber,
    resolveFieldDescribe,
    rowLimitMax
} from 'c/boardCpeUtils';
import { bucketIdOf, findBucketField, ownAndBoardBucketFieldOptions } from 'c/boardBucketFields';

const DIRECTION_OPTIONS = [
    { label: 'Ascending', value: 'ASC' },
    { label: 'Descending', value: 'DESC' }
];
const SUMMARY_LABELS = { SUM: 'Sum', AVG: 'Average', MIN: 'Min', MAX: 'Max' };
const MAX_GROUP_LEVELS = 2;
const DEFAULT_GRANULARITY = 'DAY';
/** The Row limit a "Top N" tile starts with. */
const DEFAULT_ROW_LIMIT = 10;

const ROW_LIMIT_TILES = [
    { label: 'All rows', value: 'all', illustration: 'rowLimitAll' },
    { label: 'Top N', value: 'top', illustration: 'rowLimitTop' }
];
const DETAIL_ROWS_TILES = [
    { label: 'Records under each group', value: 'on', illustration: 'detailRowsOn' },
    { label: 'Group rows only', value: 'off', illustration: 'detailRowsOff' }
];
const SUBTOTALS_TILES = [
    { label: 'No Subtotals', value: 'off', illustration: 'subtotalsOff' },
    { label: 'Subtotal per group', value: 'on', illustration: 'subtotalsOn' }
];

/**
 * Step content of the Table widget's Setup dialog (`c/boardSetupDialog`): the inputs of one step (`step`: `data`,
 * `columns`, `grouping`, `summaries`, `display`, `rowActions` or `filterBindings`, see `TABLE_STEPS` in
 * `c/boardSetupSteps`) over the dialog's draft (`config`).
 *
 * - Data: the object and the Base filters (`c-board-setup-base-filters`).
 * - Columns: the column list (`c-board-cpe-column-list`: field paths, Bucket columns, Data bars, link to record) and
 *   the Widget's Bucket fields.
 * - Grouping: Row grouping, one or two levels (date granularity, group order, order field), a Bucket field as group
 *   field with Detail rows off, Detail rows on / off and ordering groups by a summary.
 * - Summaries: the Total row with Stacked summaries (`c-board-cpe-total-row`) and Subtotals.
 * - Display: default sort, page size, Row limit and row count.
 * - Row actions: `c-board-cpe-row-action-list` (View, Edit, Create, Screen Flow).
 * - Filter bindings: `c-board-cpe-filter-bindings`.
 *
 * Row limit, Detail rows and Subtotals are picture tiles (`c-board-picture-tiles`); every setting carries field-level
 * help. Every edit fires `change` with `detail.patch` (merged into the draft by the dialog; null removes a key). A
 * Filter binding switched to "Field path" without a path fires `steperrors` with `detail.step` and `detail.errors`.
 *
 * `context`: `builderContext` and `elementInfo` (Filter widget discovery for the Filter bindings).
 */
export default class BoardTableSetupSteps extends SetupStepContent(LightningElement) {
    @api step;

    _config = {};
    _context = {};

    /** The Setup dialog's draft config. */
    @api
    get config() {
        return this._config;
    }
    set config(value) {
        this._config = isPlainObject(value) ? value : {};
        this.resolveGroupFieldTypes();
    }

    @api
    get context() {
        return this._context;
    }
    set context(value) {
        this._context = isPlainObject(value) ? value : {};
    }

    directionOptions = DIRECTION_OPTIONS;
    granularityOptions = DATE_GRANULARITY_OPTIONS;
    rowLimitTiles = ROW_LIMIT_TILES;
    detailRowsTiles = DETAIL_ROWS_TILES;
    subtotalsTiles = SUBTOTALS_TILES;
    /** `Schema.DisplayType` of each group field, by `Object::path`, once known (decides the date granularity box). */
    groupFieldTypes = {};

    get isData() {
        return this.step === 'data';
    }

    get isColumns() {
        return this.step === 'columns';
    }

    get isGrouping() {
        return this.step === 'grouping';
    }

    get isSummaries() {
        return this.step === 'summaries';
    }

    get isDisplay() {
        return this.step === 'display';
    }

    get isRowActions() {
        return this.step === 'rowActions';
    }

    get isFilterBindings() {
        return this.step === 'filterBindings';
    }

    // ---- Columns -------------------------------------------------------------------------------------------------

    get columns() {
        return Array.isArray(this.config.columns) ? this.config.columns : [];
    }

    handleColumns(event) {
        const columns = event.detail.columns;
        this.update({ columns: columns.length ? columns : null });
    }

    get bucketFields() {
        return Array.isArray(this.config.bucketFields) ? this.config.bucketFields : [];
    }

    /** Bucket fields of the Board's Filter widget, usable as columns by id. */
    get boardBucketFields() {
        return Array.isArray(this._context.boardBucketFields) ? this._context.boardBucketFields : [];
    }

    /** Writes the Bucket fields; the columns and group field of a removed Bucket field go with it. */
    handleBucketFields(event) {
        const bucketFields = event.detail.value;
        const patch = { bucketFields };
        const isKept = (fieldPath) => {
            const id = bucketIdOf(fieldPath);
            return (
                id === null || Boolean(findBucketField(bucketFields, id) || findBucketField(this.boardBucketFields, id))
            );
        };
        const kept = this.columns.filter((column) => isKept(column.fieldPath));
        if (kept.length !== this.columns.length) {
            patch.columns = kept.length ? kept : null;
        }
        if (this.groupsByBucket && !isKept(this.groupEntries[0].fieldPath)) {
            patch.groupBy = null;
        }
        this.update(patch);
    }

    // ---- Grouping ------------------------------------------------------------------------------------------------

    groupTypeKey(fieldPath) {
        return `${this.objectApiName}::${fieldPath}`;
    }

    /** Describes saved group fields (e.g. after reopening the dialog) to know which are dates. */
    resolveGroupFieldTypes() {
        this.groupEntries.forEach(({ fieldPath }) => {
            const key = this.groupTypeKey(fieldPath);
            if (!this.objectApiName || bucketIdOf(fieldPath) !== null || key in this.groupFieldTypes) {
                return;
            }
            this.groupFieldTypes = { ...this.groupFieldTypes, [key]: null };
            resolveFieldDescribe(this.objectApiName, fieldPath)
                .then((field) => {
                    this.groupFieldTypes = { ...this.groupFieldTypes, [key]: field ? field.dataType : null };
                })
                .catch(() => {
                    // Unknown type: the granularity box shows only for a saved granularity; the server validates.
                });
        });
    }

    /** The configured group fields, first level first. */
    get groupEntries() {
        return (Array.isArray(this.config.groupBy) ? this.config.groupBy : []).filter((entry) => entry?.fieldPath);
    }

    get isGrouped() {
        return this.groupEntries.length > 0;
    }

    /**
     * One editor block per group level: the configured ones, plus an empty "Then group by" below a single level (none
     * below a Bucket field, which groups an aggregated table by itself).
     */
    get groupLevels() {
        const entries = this.groupEntries.slice(0, MAX_GROUP_LEVELS);
        const count = this.groupsByBucket ? 1 : Math.min(entries.length + 1, MAX_GROUP_LEVELS);
        return Array.from({ length: count }, (unused, index) => {
            const entry = entries[index] || {};
            const isBucket = bucketIdOf(entry.fieldPath) !== null;
            const fieldPath = isBucket ? '' : entry.fieldPath || '';
            const isDate = DATE_FIELD_TYPES.includes(this.groupFieldTypes[this.groupTypeKey(fieldPath)]);
            return {
                key: `level-${index}`,
                index: String(index),
                levelClass: index ? 'slds-m-top_small' : '',
                label: index ? 'Then group by' : 'Group by',
                help: index
                    ? 'Optional second level: groups inside each first-level group.'
                    : 'One Group row per value of this field (or of a parent field up to five lookups away).',
                fieldPath,
                showBucketGroup: index === 0 && this.showBucketGroup,
                showFieldSettings: Boolean(fieldPath),
                showDirection: Boolean(entry.fieldPath),
                showGranularity: Boolean(fieldPath) && (isDate || Boolean(entry.dateGranularity)),
                dateGranularity: entry.dateGranularity || DEFAULT_GRANULARITY,
                sortDirection: entry.sortDirection === 'DESC' ? 'DESC' : 'ASC',
                orderBy: entry.orderBy || ''
            };
        });
    }

    /** True when the first group field is a Bucket field (`bucket:<id>`). */
    get groupsByBucket() {
        return bucketIdOf(this.groupEntries[0]?.fieldPath) !== null;
    }

    /** Offered with Detail rows off; kept visible while a flagged Bucket group (Detail rows on) is set. */
    get showBucketGroup() {
        return (this.detailRowsOff && this.bucketGroupFieldOptions.length > 0) || this.groupsByBucket;
    }

    /** The Widget's own Bucket fields, then the Board's not shadowed by an own one with the same id. */
    get bucketGroupFieldOptions() {
        return ownAndBoardBucketFieldOptions(this.bucketFields, this.boardBucketFields);
    }

    get bucketGroupOptions() {
        return [{ label: 'None', value: '' }, ...this.bucketGroupFieldOptions];
    }

    get bucketGroupValue() {
        return this.groupsByBucket ? this.groupEntries[0].fieldPath : '';
    }

    /** Groups by a Bucket field (one level, no order field), or clears the group field when blank. */
    handleBucketGroup(event) {
        const fieldPath = event.detail.value;
        const sortDirection = this.groupEntries[0]?.sortDirection;
        if (fieldPath) {
            this.updateGroupEntries([{ fieldPath, sortDirection }]);
        } else if (this.groupsByBucket) {
            this.updateGroupEntries([]);
        }
    }

    /** A new group field keeps the level's group order but drops its granularity and order field; blank removes it. */
    handleGroupField(event) {
        const index = Number(event.target.dataset.index);
        const fieldPath = event.detail.value;
        if (fieldPath) {
            const dataType = event.detail.field ? event.detail.field.dataType : null;
            this.groupFieldTypes = { ...this.groupFieldTypes, [this.groupTypeKey(fieldPath)]: dataType };
        }
        const entries = this.groupEntries.slice(0, MAX_GROUP_LEVELS);
        if (fieldPath) {
            entries[index] = { fieldPath, sortDirection: entries[index]?.sortDirection };
        } else {
            entries.splice(index, 1);
        }
        this.updateGroupEntries(entries);
    }

    handleGroupDirection(event) {
        this.patchGroupEntry(event, { sortDirection: event.detail.value });
    }

    handleGroupGranularity(event) {
        this.patchGroupEntry(event, { dateGranularity: event.detail.value });
    }

    handleGroupOrderBy(event) {
        this.patchGroupEntry(event, { orderBy: event.detail.value || null });
    }

    patchGroupEntry(event, patch) {
        const index = Number(event.target.dataset.index);
        const entries = this.groupEntries.slice(0, MAX_GROUP_LEVELS);
        entries[index] = { ...entries[index], ...patch };
        this.updateGroupEntries(entries);
    }

    /** Defaults (ascending order, Day granularity, order by group value) are left out of the config. */
    updateGroupEntries(entries) {
        const groupBy = entries
            .filter((entry) => entry?.fieldPath)
            .map(({ fieldPath, sortDirection, dateGranularity, orderBy, orderBySummary }) => {
                const entry = { fieldPath };
                if (sortDirection === 'DESC') {
                    entry.sortDirection = sortDirection;
                }
                if (dateGranularity && dateGranularity !== DEFAULT_GRANULARITY) {
                    entry.dateGranularity = dateGranularity;
                }
                if (orderBy) {
                    entry.orderBy = orderBy;
                }
                if (orderBySummary) {
                    entry.orderBySummary = orderBySummary;
                }
                return entry;
            });
        this.update({ groupBy: groupBy.length ? groupBy : null });
    }

    // ---- Detail rows ---------------------------------------------------------------------------------------------

    /** Detail rows on (default): records under their Group rows; off: only Group rows, an aggregated table. */
    get detailRows() {
        return this.config.detailRows !== false;
    }

    get detailRowsValue() {
        return this.detailRows ? 'on' : 'off';
    }

    get detailRowsOff() {
        return this.isGrouped && this.config.detailRows === false;
    }

    handleDetailRows(event) {
        this.update({ detailRows: event.detail.value === 'off' ? false : null });
    }

    get groupOrderBySummary() {
        return this.groupEntries[0]?.orderBySummary || null;
    }

    /** Summary group order: offered with Detail rows off, and kept visible while a flagged one is set. */
    get showSummaryOrder() {
        return this.detailRowsOff || Boolean(this.groupOrderBySummary);
    }

    /** `columnId:FUNCTION` of the summary groups are ordered by, or `''` for the group value. */
    get summaryOrder() {
        const order = this.groupOrderBySummary;
        return order ? `${order.columnId}:${order.summaryFunction}` : '';
    }

    /** `Group value`, then one option per summary the columns show (`Sum of Amount`). */
    get summaryOrderOptions() {
        const options = [{ label: 'Group value', value: '' }];
        this.columns.forEach((column) => {
            const columnId = column.id || column.fieldPath;
            (Array.isArray(column.summaries) ? column.summaries : []).forEach((summaryFunction) => {
                options.push({
                    label: `${SUMMARY_LABELS[summaryFunction] || summaryFunction} of ${column.label || column.fieldPath}`,
                    value: `${columnId}:${summaryFunction}`
                });
            });
        });
        return options;
    }

    /** Orders the first-level groups by a summary (Detail rows off), or by the group value when blank. */
    handleSummaryOrder(event) {
        const value = event.detail.value || '';
        const separator = value.lastIndexOf(':');
        const entries = this.groupEntries.slice(0, MAX_GROUP_LEVELS);
        entries[0] = {
            ...entries[0],
            orderBySummary:
                separator > 0
                    ? { columnId: value.slice(0, separator), summaryFunction: value.slice(separator + 1) }
                    : null
        };
        this.updateGroupEntries(entries);
    }

    // ---- Summaries -----------------------------------------------------------------------------------------------

    get showTotalRow() {
        return this.config.showTotalRow === true;
    }

    handleTotalRow(event) {
        const { showTotalRow, columns } = event.detail;
        this.update({ showTotalRow, columns: columns.length ? columns : null });
    }

    /** Subtotals close groups of records: offered with Row grouping and Detail rows on. */
    get showSubtotalsSetting() {
        return this.isGrouped && this.detailRows;
    }

    get subtotalsValue() {
        return this.config.showSubtotals === true ? 'on' : 'off';
    }

    handleSubtotals(event) {
        this.update({ showSubtotals: event.detail.value === 'on' ? true : null });
    }

    // ---- Display -------------------------------------------------------------------------------------------------

    get sortBy() {
        return this.config.sortBy || '';
    }

    get sortDirection() {
        return this.config.sortDirection === 'DESC' ? 'DESC' : 'ASC';
    }

    get pageSize() {
        return this.config.pageSize ?? '';
    }

    get hasRowLimit() {
        return this.config.rowLimit !== undefined && this.config.rowLimit !== null && this.config.rowLimit !== '';
    }

    get rowLimitMode() {
        return this.hasRowLimit ? 'top' : 'all';
    }

    get rowLimit() {
        return this.config.rowLimit ?? '';
    }

    /** Largest Row limit: 200 groups with Row grouping and Detail rows on, else 2,000 rows or Group rows. */
    get rowLimitMax() {
        return rowLimitMax(this.config);
    }

    /** With Row grouping a Row limit counts first-level groups in the group order. */
    get rowLimitHelp() {
        if (this.isGrouped) {
            const max = this.rowLimitMax === 200 ? '200' : '2,000';
            return `Show only the first N groups in the group order (1-${max}).`;
        }
        return 'Show only the first N rows in the default sort (1-2,000). Needs a default sort; turns off infinite scroll.';
    }

    get showRowCount() {
        return this.config.showRowCount !== false;
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

    handleRowLimitMode(event) {
        this.update({ rowLimit: event.detail.value === 'top' ? DEFAULT_ROW_LIMIT : null });
    }

    handleRowLimit(event) {
        this.update({ rowLimit: parseNumber(event.detail.value) });
    }

    handleShowRowCount(event) {
        this.update({ showRowCount: event.detail.checked ? null : false });
    }

    // ---- Row actions ---------------------------------------------------------------------------------------------

    get rowActions() {
        return Array.isArray(this.config.rowActions) ? this.config.rowActions : [];
    }

    handleRowActions(event) {
        const rowActions = event.detail.rowActions;
        this.update({ rowActions: rowActions.length ? rowActions : null });
    }
}