import { LightningElement, api } from 'lwc';
import {
    CONDITION_LOGIC_OPTIONS,
    NO_DRAG,
    baseFilterError,
    baseFilterSummary,
    conditionGroupError,
    dragRowClass,
    dropRowDrag,
    flattenConditions,
    isConditionGroup,
    isPlainObject,
    moveItem,
    nextSequentialId,
    overRowDrag,
    startRowDrag
} from 'c/boardCpeUtils';

const ROOT = 'root';

/**
 * The shared condition editor: edits one condition tree `{ logic: 'AND' | 'OR', conditions[] }`, where each entry is
 * a condition (`{ id, fieldPath, operator, value }`) or an AND / OR group (`{ id, logic, conditions[] }`) of
 * conditions. Base filters use it, and so can any other condition tree (e.g. Bucket rules).
 *
 * Fires `conditionchange` with `detail.value`, the whole edited tree, after every edit. New entries get ids
 * `<idPrefix>N`, unique across the tree. Groups nested deeper than one level (hand-edited JSON) show read-only.
 *
 * Top-level entries, and the conditions inside a group, reorder by dragging their handle (the shared drag helpers of
 * `c/boardCpeUtils`) or with Move up / Move down; an entry only moves within its own list.
 */
export default class BoardConditionEditor extends LightningElement {
    /** Object the field pickers start from. */
    @api objectApiName;
    /** Prefix of the ids of added conditions and groups. */
    @api idPrefix = 'c';

    logicOptions = CONDITION_LOGIC_OPTIONS;
    rootId = ROOT;

    tree = { logic: 'AND', conditions: [] };
    /** Drag-to-reorder state; `scope` is the list being reordered (`root` or a group id). */
    drag = { ...NO_DRAG, scope: null };

    @api
    get value() {
        return this.tree;
    }

    set value(value) {
        const source = isPlainObject(value) ? value : {};
        this.tree = {
            logic: source.logic === 'OR' ? 'OR' : 'AND',
            conditions: Array.isArray(source.conditions) ? source.conditions : []
        };
    }

    get logic() {
        return this.tree.logic;
    }

    get hasEntries() {
        return this.tree.conditions.length > 0;
    }

    get entries() {
        const count = this.tree.conditions.length;
        return this.tree.conditions.map((entry, index) => ({
            ...this.entryView(entry, index),
            ...this.positionView(ROOT, 'c-condition-entry slds-m-bottom_small', index, count)
        }));
    }

    /** Index, ends and row classes (drag markers) of entry `index` of the list `scope` (`count` entries). */
    positionView(scope, baseClass, index, count) {
        const drag = this.drag.scope === scope ? this.drag : NO_DRAG;
        return {
            index,
            isFirst: index === 0,
            isLast: index === count - 1,
            rowClass: `${baseClass}${dragRowClass(drag, index)}`
        };
    }

    entryView(entry, index) {
        const safe = isPlainObject(entry) ? entry : {};
        const key = safe.id || `entry-${index}`;
        if (!isConditionGroup(safe)) {
            return { key, id: safe.id, isGroup: false, condition: safe, errors: this.conditionErrors(safe) };
        }
        const children = Array.isArray(safe.conditions) ? safe.conditions : [];
        return {
            key,
            id: safe.id,
            isGroup: true,
            logic: safe.logic,
            groupError: conditionGroupError(safe),
            children: children.map((child, position) => {
                const childSafe = isPlainObject(child) ? child : {};
                const isNested = isConditionGroup(childSafe);
                const summary = isNested ? baseFilterSummary(childSafe, position) : null;
                return {
                    ...this.positionView(safe.id, 'c-condition-child slds-m-bottom_x-small', position, children.length),
                    key: childSafe.id || `${key}-${position}`,
                    id: childSafe.id,
                    isNested,
                    nestedText: summary ? `${summary.label}: ${summary.valueText}` : '',
                    condition: childSafe,
                    errors: isNested ? [] : this.conditionErrors(childSafe)
                };
            })
        };
    }

    conditionErrors(condition) {
        const problem = baseFilterError(condition);
        return problem ? [problem] : [];
    }

    // ---- Edits ---------------------------------------------------------------------------------------------------

    handleLogic(event) {
        const groupId = event.target.dataset.id;
        const logic = event.detail.value;
        if (groupId === ROOT) {
            this.commit({ ...this.tree, logic });
            return;
        }
        this.updateEntry(groupId, (entry) => ({ ...entry, logic }));
    }

    handleAddCondition(event) {
        const groupId = event.target.dataset.id;
        const condition = { id: this.nextId(), fieldPath: '', operator: 'EQ', value: null };
        if (groupId === ROOT) {
            this.commit({ ...this.tree, conditions: [...this.tree.conditions, condition] });
            return;
        }
        this.updateEntry(groupId, (entry) => ({ ...entry, conditions: [...entry.conditions, condition] }));
    }

    handleAddGroup() {
        const group = { id: this.nextId(), logic: this.tree.logic === 'OR' ? 'AND' : 'OR', conditions: [] };
        this.commit({ ...this.tree, conditions: [...this.tree.conditions, group] });
    }

    handleRemoveGroup(event) {
        this.removeEntry(event.target.dataset.id);
    }

    handleRowChange(event) {
        const id = event.target.dataset.id;
        const condition = event.detail.condition;
        this.updateEntry(id, () => condition);
    }

    handleRowRemove(event) {
        this.removeEntry(event.target.dataset.id);
    }

    // ---- Reorder --------------------------------------------------------------------------------------------------

    handleMoveUp(event) {
        const { scope, index } = event.currentTarget.dataset;
        this.moveEntry(scope, Number(index), -1);
    }

    handleMoveDown(event) {
        const { scope, index } = event.currentTarget.dataset;
        this.moveEntry(scope, Number(index), 1);
    }

    handleDragStart(event) {
        this.drag = { ...startRowDrag(event), scope: event.currentTarget.dataset.scope };
    }

    /** Rows only accept a drop from their own list (a group's condition never lands among the top-level entries). */
    handleDragOver(event) {
        if (this.drag.scope !== event.currentTarget.dataset.scope) {
            return;
        }
        const next = overRowDrag(event, this.drag);
        if (next !== this.drag) {
            this.drag = { ...next, scope: this.drag.scope };
        }
    }

    handleDrop(event) {
        const { scope } = this.drag;
        if (scope !== event.currentTarget.dataset.scope) {
            return;
        }
        const move = dropRowDrag(event, this.drag);
        this.drag = { ...NO_DRAG, scope: null };
        if (move) {
            this.moveEntry(scope, move.index, move.offset);
        }
    }

    handleDragEnd() {
        this.drag = { ...NO_DRAG, scope: null };
    }

    /** Moves entry `index` of the list `scope` (`root` or a group id) by `offset`. */
    moveEntry(scope, index, offset) {
        if (scope === ROOT) {
            this.commit({ ...this.tree, conditions: moveItem(this.tree.conditions, index, offset) });
            return;
        }
        this.updateEntry(scope, (entry) => ({ ...entry, conditions: moveItem(entry.conditions, index, offset) }));
    }

    nextId() {
        return nextSequentialId(flattenConditions(this.tree.conditions), this.idPrefix || 'c');
    }

    /** Replaces the entry `id` (top level or inside a group) with `update(entry)`. */
    updateEntry(id, update) {
        const replace = (conditions) =>
            conditions.map((entry) => {
                if (isPlainObject(entry) && entry.id === id) {
                    return update(entry);
                }
                return isConditionGroup(entry) && Array.isArray(entry.conditions)
                    ? { ...entry, conditions: replace(entry.conditions) }
                    : entry;
            });
        this.commit({ ...this.tree, conditions: replace(this.tree.conditions) });
    }

    removeEntry(id) {
        const remove = (conditions) =>
            conditions
                .filter((entry) => !(isPlainObject(entry) && entry.id === id))
                .map((entry) => {
                    return isConditionGroup(entry) && Array.isArray(entry.conditions)
                        ? { ...entry, conditions: remove(entry.conditions) }
                        : entry;
                });
        this.commit({ ...this.tree, conditions: remove(this.tree.conditions) });
    }

    commit(tree) {
        this.tree = tree;
        this.dispatchEvent(new CustomEvent('conditionchange', { detail: { value: tree } }));
    }
}