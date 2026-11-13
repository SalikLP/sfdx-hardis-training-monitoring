import { LightningElement, api } from 'lwc';
import {
    NO_DRAG,
    applyPatch,
    dragRowClass,
    dropRowDrag,
    isPlainObject,
    moveItem,
    nextSequentialId,
    overRowDrag,
    resolveFieldDescribe,
    startRowDrag
} from 'c/boardCpeUtils';
import { bucketFieldOptions, bucketIdOf, findBucketField } from 'c/boardBucketFields';

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
const NUMERIC_DISPLAY = new Set(['auto', 'number', 'currency', 'percent', 'dataBar']);
const DATA_BAR_OPTION = { label: 'Data bar', value: 'dataBar' };
/** Field types a Data bar can draw (number, currency, percent). */
const DATA_BAR_TYPES = new Set(['INTEGER', 'LONG', 'DOUBLE', 'CURRENCY', 'PERCENT']);

/**
 * Repeatable Table column editor (`fieldPath` with 1–5 hop parent paths, `label`, `displayAs`, `linkToRecord`,
 * `align`, `wrapText`, `width`, `hideOnNarrow`, `format`) used for Table columns and child-relationship columns.
 * Fires a non-bubbling `change` event with `detail.columns` (the full, re-ordered/edited array).
 */
export default class BoardCpeColumnList extends LightningElement {
    _objectApiName;
    @api addLabel = 'Add column';
    /** Prefix of generated column ids (`col1`, `col2`, …). */
    @api idPrefix = 'col';

    displayAsOptions = DISPLAY_AS_OPTIONS;
    linkOptions = LINK_OPTIONS;
    alignOptions = ALIGN_OPTIONS;
    _columns = [];
    /** The Widget's Bucket fields, offered as columns (`fieldPath: 'bucket:<id>'`). */
    @api bucketFields = [];
    /** Drag-to-reorder state (see the drag helpers in c/boardCpeUtils). */
    drag = NO_DRAG;

    /** Leaf field `dataType` per `object::path` (null when unknown), resolved lazily to offer Data bar. */
    _typeByPath = {};
    _typePending = new Set();

    @api
    get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(value) {
        this._objectApiName = value;
        this.resolveColumnTypes();
    }

    @api
    get columns() {
        return this._columns;
    }
    set columns(value) {
        this._columns = Array.isArray(value) ? value.filter(isPlainObject) : [];
        this.resolveColumnTypes();
    }

    resolveColumnTypes() {
        const objectApiName = this._objectApiName;
        if (!objectApiName) {
            return;
        }
        for (const column of this._columns) {
            const key = `${objectApiName}::${column.fieldPath}`;
            if (
                column.fieldPath &&
                bucketIdOf(column.fieldPath) === null &&
                !(key in this._typeByPath) &&
                !this._typePending.has(key)
            ) {
                this._typePending.add(key);
                const settle = (field) => {
                    this._typePending.delete(key);
                    this._typeByPath = { ...this._typeByPath, [key]: field ? field.dataType : null };
                };
                resolveFieldDescribe(objectApiName, column.fieldPath)
                    .then(settle)
                    .catch(() => settle(null));
            }
        }
    }

    /** "Display as" options; Data bar only for number, currency and percent fields (or when already chosen). */
    displayAsOptionsFor(column) {
        const type = this._typeByPath[`${this._objectApiName}::${column.fieldPath}`];
        return DATA_BAR_TYPES.has(type) || column.displayAs === DATA_BAR_OPTION.value
            ? [...DISPLAY_AS_OPTIONS, DATA_BAR_OPTION]
            : DISPLAY_AS_OPTIONS;
    }

    get hasColumns() {
        return this._columns.length > 0;
    }

    get bucketOptions() {
        return bucketFieldOptions(this.bucketFields);
    }

    get hasBucketFields() {
        return this.bucketOptions.length > 0;
    }

    /** A Bucket field column's Bucket field label (its id when unknown), or null for a field column. */
    bucketLabelOf(column) {
        const id = bucketIdOf(column.fieldPath);
        if (id === null) {
            return null;
        }
        return findBucketField(this.bucketFields, id)?.label || id;
    }

    get rows() {
        const last = this._columns.length - 1;
        return this._columns.map((column, index) => {
            const displayAs = column.displayAs || 'auto';
            const bucketLabel = this.bucketLabelOf(column);
            return {
                key: column.id || `index-${index}`,
                index,
                title: `Column ${index + 1}`,
                fieldPath: column.fieldPath || '',
                isBucket: bucketLabel !== null,
                isField: bucketLabel === null,
                bucketLabel,
                label: column.label || '',
                displayAs,
                displayAsOptions: this.displayAsOptionsFor(column),
                isDataBar: displayAs === DATA_BAR_OPTION.value,
                barOnly: column.barOnly === true,
                linkToRecord: column.linkToRecord || 'auto',
                align: column.align || 'auto',
                wrapText: column.wrapText === true,
                hideOnNarrow: column.hideOnNarrow === true,
                width: column.width || '',
                format: column.format || null,
                showFormat: bucketLabel === null && NUMERIC_DISPLAY.has(displayAs),
                isFirst: index === 0,
                isLast: index === last,
                rowClass: `c-column slds-p-vertical_x-small${dragRowClass(this.drag, index)}`
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

    /** Adds a column showing a Bucket field's label per row. */
    handleAddBucket(event) {
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

    handleDragStart(event) {
        this.drag = startRowDrag(event);
    }

    handleDragOver(event) {
        this.drag = overRowDrag(event, this.drag);
    }

    handleDrop(event) {
        const move = dropRowDrag(event, this.drag);
        this.drag = NO_DRAG;
        if (move) {
            this.emit(moveItem(this._columns, move.index, move.offset));
        }
    }

    handleDragEnd() {
        this.drag = NO_DRAG;
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
        const name = event.target.dataset.name;
        const patch = { [name]: value && value !== 'auto' ? value : null };
        if (name === 'displayAs' && value !== DATA_BAR_OPTION.value) {
            patch.barOnly = null;
        }
        this.updateColumn(event, patch);
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