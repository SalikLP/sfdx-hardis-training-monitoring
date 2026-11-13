import { LightningElement, api } from 'lwc';
import { TABLE_SUMMARY_FUNCTIONS, isPlainObject, resolveFieldDescribe } from 'c/boardCpeUtils';

const SUMMARY_LABELS = { SUM: 'Sum', AVG: 'Average', MIN: 'Min', MAX: 'Max' };
const SUMMARY_OPTIONS = TABLE_SUMMARY_FUNCTIONS.map((value) => ({ label: SUMMARY_LABELS[value], value }));
const MAX_STACKED_SUMMARIES = 4;
/** Columns with no summaries get Sum when the Admin turns the Total row on. */
const DEFAULT_SUMMARIES = ['SUM'];

/**
 * Total row editor of the Table Config editor: the Total row on/off and, per numeric column, an ordered list of 1–4
 * Stacked summaries (Sum, Average, Min, Max). Numeric columns are found from the field describe of each column path.
 * Fires a non-bubbling `change` event with `detail.showTotalRow` (true or null) and `detail.columns` (the full
 * column array with `summaries` set or removed).
 */
export default class BoardCpeTotalRow extends LightningElement {
    @api showTotalRow = false;
    /** Row grouping is on: Group and Subtotal rows show the summaries, so the pickers show with the Total row off. */
    @api grouped = false;

    summaryOptions = SUMMARY_OPTIONS;
    maxSummaries = MAX_STACKED_SUMMARIES;
    /** Lower-cased field path -> true when the column's field is numeric. */
    numericByPath = {};
    _objectApiName = null;
    _columns = [];
    _loadToken = 0;

    @api
    get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(value) {
        this._objectApiName = value || null;
        this.resolveNumericColumns();
    }

    @api
    get columns() {
        return this._columns;
    }
    set columns(value) {
        this._columns = Array.isArray(value) ? value.filter(isPlainObject) : [];
        this.resolveNumericColumns();
    }

    /** Looks up which column paths are numeric (describes are memoized per object). */
    async resolveNumericColumns() {
        const token = ++this._loadToken;
        const objectApiName = this._objectApiName;
        const paths = this._columns.map((column) => column.fieldPath).filter(Boolean);
        const entries = await Promise.all(
            paths.map(async (path) => {
                try {
                    const field = await resolveFieldDescribe(objectApiName, path);
                    return [path.toLowerCase(), Boolean(field?.isNumeric)];
                } catch {
                    return [path.toLowerCase(), false];
                }
            })
        );
        if (token === this._loadToken) {
            this.numericByPath = Object.fromEntries(entries);
        }
    }

    isNumeric(column) {
        return Boolean(column.fieldPath && this.numericByPath[column.fieldPath.toLowerCase()]);
    }

    get isOn() {
        return this.showTotalRow === true;
    }

    /** One summary picker per numeric column. */
    get summaryRows() {
        return this._columns
            .map((column, index) => ({ column, index }))
            .filter(({ column }) => this.isNumeric(column))
            .map(({ column, index }) => ({
                key: column.id || `index-${index}`,
                columnId: column.id || column.fieldPath,
                index,
                label: column.label || column.fieldPath,
                value: Array.isArray(column.summaries) ? column.summaries : []
            }));
    }

    get hasSummaryRows() {
        return (this.isOn || this.grouped === true) && this.summaryRows.length > 0;
    }

    get showNoNumericColumns() {
        return this.isOn && this.summaryRows.length === 0;
    }

    handleToggle(event) {
        const on = event.detail.checked === true;
        const withDefault = (column) => {
            const needsDefault = this.isNumeric(column) && !Array.isArray(column.summaries);
            return needsDefault ? { ...column, summaries: [...DEFAULT_SUMMARIES] } : column;
        };
        this.emit(on ? true : null, on ? this._columns.map(withDefault) : this._columns);
    }

    handleSummaries(event) {
        const index = Number(event.target.dataset.index);
        const summaries = Array.isArray(event.detail.value) ? [...event.detail.value] : [];
        const columns = this._columns.map((column, position) => {
            if (position !== index) {
                return column;
            }
            const next = { ...column };
            if (summaries.length) {
                next.summaries = summaries;
            } else {
                delete next.summaries;
            }
            return next;
        });
        this.emit(this.isOn ? true : null, columns);
    }

    emit(showTotalRow, columns) {
        this.dispatchEvent(new CustomEvent('change', { detail: { showTotalRow, columns } }));
    }
}