import { LightningElement, api } from 'lwc';
import { applyPatch, isPlainObject, moveItem, nextSequentialId } from 'c/boardCpeUtils';

const DISPLAY_AS_OPTIONS = [
    { label: 'Auto (from field type)', value: 'auto' },
    { label: 'Text', value: 'text' },
    { label: 'Badge', value: 'badge' },
    { label: 'Number', value: 'number' },
    { label: 'Currency', value: 'currency' },
    { label: 'Percent', value: 'percent' },
    { label: 'Date', value: 'date' },
    { label: 'Date/time', value: 'datetime' },
    { label: 'Checkbox', value: 'boolean' }
];
const LINK_OPTIONS = [
    { label: 'Auto (name fields)', value: 'auto' },
    { label: 'Always', value: 'always' },
    { label: 'Never', value: 'never' }
];
const ALIGN_OPTIONS = [
    { label: 'Auto', value: 'auto' },
    { label: 'Left', value: 'left' },
    { label: 'Center', value: 'center' },
    { label: 'Right', value: 'right' }
];
const NUMERIC_DISPLAY = new Set(['auto', 'number', 'currency', 'percent']);

/**
 * Repeatable Table column editor (`fieldPath` with 1–5 hop parent paths, `label`, `displayAs`, `linkToRecord`,
 * `align`, `wrapText`, `width`, `hideOnNarrow`, `format`) used for Table columns and child-relationship columns.
 * Fires a non-bubbling `change` event with `detail.columns` (the full, re-ordered/edited array).
 */
export default class BoardCpeColumnList extends LightningElement {
    @api objectApiName;
    @api addLabel = 'Add column';
    /** Prefix of generated column ids (`col1`, `col2`, …). */
    @api idPrefix = 'col';

    displayAsOptions = DISPLAY_AS_OPTIONS;
    linkOptions = LINK_OPTIONS;
    alignOptions = ALIGN_OPTIONS;
    _columns = [];

    @api
    get columns() {
        return this._columns;
    }
    set columns(value) {
        this._columns = Array.isArray(value) ? value.filter(isPlainObject) : [];
    }

    get hasColumns() {
        return this._columns.length > 0;
    }

    get rows() {
        const last = this._columns.length - 1;
        return this._columns.map((column, index) => {
            const displayAs = column.displayAs || 'auto';
            return {
                key: column.id || `index-${index}`,
                index,
                title: `Column ${index + 1}`,
                fieldPath: column.fieldPath || '',
                label: column.label || '',
                displayAs,
                linkToRecord: column.linkToRecord || 'auto',
                align: column.align || 'auto',
                wrapText: column.wrapText === true,
                hideOnNarrow: column.hideOnNarrow === true,
                width: column.width || '',
                format: column.format || null,
                showFormat: NUMERIC_DISPLAY.has(displayAs),
                isFirst: index === 0,
                isLast: index === last
            };
        });
    }

    handleAdd(event) {
        const fieldPath = event.detail.value;
        if (!fieldPath) {
            return;
        }
        this.emit([...this._columns, { id: nextSequentialId(this._columns, this.idPrefix), fieldPath }]);
    }

    handleRemove(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.emit(this._columns.filter((column, position) => position !== index));
    }

    handleMoveUp(event) {
        this.emit(moveItem(this._columns, Number(event.currentTarget.dataset.index), -1));
    }

    handleMoveDown(event) {
        this.emit(moveItem(this._columns, Number(event.currentTarget.dataset.index), 1));
    }

    handleField(event) {
        this.updateColumn(event, { fieldPath: event.detail.value || '' });
    }

    handleText(event) {
        const value = event.detail.value;
        this.updateColumn(event, { [event.target.dataset.name]: value && value.trim() ? value : null });
    }

    handleChoice(event) {
        const value = event.detail.value;
        this.updateColumn(event, { [event.target.dataset.name]: value && value !== 'auto' ? value : null });
    }

    handleToggle(event) {
        this.updateColumn(event, { [event.target.dataset.name]: event.detail.checked ? true : null });
    }

    handleFormat(event) {
        this.updateColumn(event, { format: event.detail.value });
    }

    updateColumn(event, patch) {
        const index = Number(event.target.dataset.index);
        this.emit(this._columns.map((column, position) => (position === index ? applyPatch(column, patch) : column)));
    }

    emit(columns) {
        this._columns = columns;
        this.dispatchEvent(new CustomEvent('change', { detail: { columns } }));
    }
}