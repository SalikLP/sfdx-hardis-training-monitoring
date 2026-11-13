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
    startRowDrag
} from 'c/boardCpeUtils';

const TYPE_OPTIONS = [
    { label: 'View record', value: 'view' },
    { label: 'Edit record', value: 'edit' },
    { label: 'Create record', value: 'create' },
    { label: 'Screen Flow', value: 'flow' }
];
const PLACEMENT_OPTIONS = [
    { label: 'Row menu', value: 'menu' },
    { label: 'Button column', value: 'column' }
];

/**
 * Repeatable Table Row action editor (`id`, `label`, `icon`, `type`, `target`, `placement`, `columnLabel`).
 * Create actions use `object`, `recordTypeId` and `defaults` (`[{ field, rowField }]`) instead of `target`.
 * Screen Flow actions use `flowApiName` and `inputs` (`[{ name, rowField }]`, default `recordId` from `Id`).
 * `target` is blank for the row's own record, else a lookup field path. Fires a non-bubbling `change` event with
 * `detail.rowActions` (the full, re-ordered/edited array).
 */
export default class BoardCpeRowActionList extends LightningElement {
    @api objectApiName;

    typeOptions = TYPE_OPTIONS;
    placementOptions = PLACEMENT_OPTIONS;
    _actions = [];
    /** Drag-to-reorder state (see the drag helpers in c/boardCpeUtils). */
    drag = NO_DRAG;

    @api
    get rowActions() {
        return this._actions;
    }
    set rowActions(value) {
        this._actions = Array.isArray(value) ? value.filter(isPlainObject) : [];
    }

    get hasActions() {
        return this._actions.length > 0;
    }

    get rows() {
        const last = this._actions.length - 1;
        return this._actions.map((action, index) => {
            const placement = action.placement === 'column' ? 'column' : 'menu';
            return {
                key: action.id || `index-${index}`,
                index,
                title: `Action ${index + 1}`,
                label: action.label || '',
                icon: action.icon || '',
                type: ['edit', 'create', 'flow'].includes(action.type) ? action.type : 'view',
                isCreate: action.type === 'create',
                isFlow: action.type === 'flow',
                isLookupTarget: !['create', 'flow'].includes(action.type),
                flowApiName: action.flowApiName || '',
                inputs: (Array.isArray(action.inputs) ? action.inputs : []).map((entry, position) => ({
                    key: `${index}-${position}`,
                    position,
                    name: entry?.name || '',
                    rowField: entry?.rowField || ''
                })),
                object: action.object || '',
                recordTypeId: action.recordTypeId || '',
                defaults: (Array.isArray(action.defaults) ? action.defaults : []).map((entry, position) => ({
                    key: `${index}-${position}`,
                    position,
                    field: entry?.field || '',
                    rowField: entry?.rowField || ''
                })),
                target: action.target || '',
                placement,
                columnLabel: action.columnLabel || '',
                showColumnLabel: placement === 'column',
                isFirst: index === 0,
                isLast: index === last,
                rowClass: `c-row-action slds-p-vertical_x-small${dragRowClass(this.drag, index)}`
            };
        });
    }

    handleAdd() {
        this.emit([
            ...this._actions,
            { id: nextSequentialId(this._actions, 'action'), label: 'View record', type: 'view', placement: 'menu' }
        ]);
    }

    handleRemove(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.emit(this._actions.filter((action, position) => position !== index));
    }

    handleMoveUp(event) {
        this.emit(moveItem(this._actions, Number(event.currentTarget.dataset.index), -1));
    }

    handleMoveDown(event) {
        this.emit(moveItem(this._actions, Number(event.currentTarget.dataset.index), 1));
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
            this.emit(moveItem(this._actions, move.index, move.offset));
        }
    }

    handleDragEnd() {
        this.drag = NO_DRAG;
    }

    handleTarget(event) {
        this.updateAction(event, { target: event.detail.value || null });
    }

    handleText(event) {
        const value = event.detail.value;
        this.updateAction(event, { [event.target.dataset.name]: value && value.trim() ? value : null });
    }

    handleChoice(event) {
        this.updateAction(event, { [event.target.dataset.name]: event.detail.value });
    }

    /** Create and Screen Flow actions have no lookup target; each type drops the other types' settings. */
    handleType(event) {
        const type = event.detail.value;
        const noCreate = { object: null, recordTypeId: null, defaults: null };
        const noFlow = { flowApiName: null, inputs: null };
        if (type === 'create') {
            this.updateAction(event, { ...noFlow, type, target: null });
        } else if (type === 'flow') {
            this.updateAction(event, {
                ...noCreate,
                type,
                target: null,
                inputs: [{ name: 'recordId', rowField: 'Id' }]
            });
        } else {
            this.updateAction(event, { ...noCreate, ...noFlow, type });
        }
    }

    handleAddInput(event) {
        const index = Number(event.currentTarget.dataset.index);
        const inputs = Array.isArray(this._actions[index].inputs) ? this._actions[index].inputs : [];
        this.updateAction(event, { inputs: [...inputs, { name: null, rowField: null }] });
    }

    handleRemoveInput(event) {
        this.patchInput(event, null);
    }

    handleInputName(event) {
        const value = event.detail.value;
        this.patchInput(event, { name: value && value.trim() ? value : null });
    }

    handleInputRowField(event) {
        this.patchInput(event, { rowField: event.detail.value || null });
    }

    /** Patches (or, with a null patch, removes) one input of a Screen Flow action; an emptied list is dropped. */
    patchInput(event, patch) {
        const index = Number(event.currentTarget.dataset.index);
        const position = Number(event.currentTarget.dataset.position);
        const inputs = this._actions[index].inputs
            .map((entry, at) => (at === position ? (patch ? { ...entry, ...patch } : null) : entry))
            .filter(Boolean);
        this.updateAction(event, { inputs: inputs.length ? inputs : null });
    }

    handleObject(event) {
        this.updateAction(event, { object: event.detail.value || null, defaults: null });
    }

    handleAddDefault(event) {
        const index = Number(event.currentTarget.dataset.index);
        const defaults = Array.isArray(this._actions[index].defaults) ? this._actions[index].defaults : [];
        this.updateAction(event, { defaults: [...defaults, { field: null, rowField: null }] });
    }

    handleRemoveDefault(event) {
        this.patchDefault(event, null);
    }

    handleDefaultField(event) {
        this.patchDefault(event, { field: event.detail.value || null });
    }

    handleDefaultRowField(event) {
        this.patchDefault(event, { rowField: event.detail.value || null });
    }

    /** Patches (or, with a null patch, removes) one default of an action; an emptied list is dropped. */
    patchDefault(event, patch) {
        const index = Number(event.currentTarget.dataset.index);
        const position = Number(event.currentTarget.dataset.position);
        const defaults = this._actions[index].defaults
            .map((entry, at) => (at === position ? (patch ? { ...entry, ...patch } : null) : entry))
            .filter(Boolean);
        this.updateAction(event, { defaults: defaults.length ? defaults : null });
    }

    updateAction(event, patch) {
        const index = Number(event.target.dataset.index);
        this.emit(this._actions.map((action, position) => (position === index ? applyPatch(action, patch) : action)));
    }

    emit(rowActions) {
        this._actions = rowActions;
        this.dispatchEvent(new CustomEvent('change', { detail: { rowActions } }));
    }
}