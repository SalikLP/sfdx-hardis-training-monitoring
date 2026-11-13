const ACTION_TYPES = new Set(['view', 'edit', 'create', 'flow']);
const RECORD_ID_PATTERN = /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/;
/** Key of the trailing column that holds every `placement: 'menu'` action. */
export const MENU_COLUMN_ID = '__rowActionsMenu';

/**
 * Configured Row actions `{ id, label, icon, type, target, placement, columnLabel }` that the Table can run
 * (`view` / `edit` / `create` / `flow` with a label); `id` defaults to its position.
 * @param {object[]} rawActions `config.rowActions`
 */
export function normalizeRowActions(rawActions) {
    if (!Array.isArray(rawActions)) {
        return [];
    }
    return rawActions
        .map((action, index) => ({ action, index }))
        .filter(({ action }) => action && ACTION_TYPES.has(action.type) && String(action.label || '').trim())
        .filter(({ action }) => action.type !== 'create' || String(action.object || '').trim())
        .filter(({ action }) => action.type !== 'flow' || String(action.flowApiName || '').trim())
        .map(({ action, index }) => ({
            id: action.id || `action${index + 1}`,
            label: String(action.label).trim(),
            icon: action.icon || null,
            type: action.type,
            target: String(action.target || '').trim(),
            placement: action.placement === 'column' ? 'column' : 'menu',
            columnLabel: String(action.columnLabel || '').trim() || String(action.label).trim(),
            ...(action.type === 'create' ? createSettings(action) : {}),
            ...(action.type === 'flow' ? flowSettings(action) : {})
        }));
}

/** A Screen Flow action's flow API name and the `{ name, rowField }` input variables mapped from row fields. */
function flowSettings(action) {
    return {
        flowApiName: String(action.flowApiName).trim(),
        inputs: (Array.isArray(action.inputs) ? action.inputs : [])
            .filter((entry) => entry && String(entry.name || '').trim() && String(entry.rowField || '').trim())
            .map((entry) => ({ name: String(entry.name).trim(), rowField: String(entry.rowField).trim() }))
    };
}

/** A Create action's object, record type and the `{ field, rowField }` defaults mapped from row fields. */
function createSettings(action) {
    return {
        object: String(action.object).trim(),
        recordTypeId: String(action.recordTypeId || '').trim() || null,
        defaults: (Array.isArray(action.defaults) ? action.defaults : [])
            .filter((entry) => entry && String(entry.field || '').trim() && String(entry.rowField || '').trim())
            .map((entry) => ({ field: String(entry.field).trim(), rowField: String(entry.rowField).trim() }))
    };
}

/**
 * `rowActions` entry of the `queryTable` request: the target path to fetch with each row, plus a Create action's
 * object and the row fields its defaults map from.
 */
export function serverRowActionRequest(actions) {
    return actions.map((action) => {
        if (action.type === 'flow') {
            return {
                id: action.id,
                target: action.target,
                type: 'flow',
                fields: action.inputs.map((entry) => entry.rowField)
            };
        }
        if (action.type !== 'create') {
            return { id: action.id, target: action.target };
        }
        return {
            id: action.id,
            target: action.target,
            type: 'create',
            object: action.object,
            fields: action.defaults.map((entry) => entry.rowField)
        };
    });
}

/**
 * Distinct objects whose `updateable` (Edit target) or `createable` (Create object) flag is needed (`getObjectInfos`);
 * a polymorphic Edit target needs every object its lookup can point to (`candidateObjectApiNames`).
 */
export function permissionObjectApiNames(actions, serverTargets) {
    const names = new Set();
    actions.forEach((action) => {
        if (action.type === 'create') {
            names.add(action.object);
        } else if (action.type === 'edit') {
            const target = targetFor(action, serverTargets);
            const objects = target?.targetObjectApiName
                ? [target.targetObjectApiName]
                : target?.candidateObjectApiNames || [];
            objects.forEach((name) => names.add(name));
        }
    });
    return [...names].filter(Boolean).sort();
}

/**
 * Server targets with `candidateObjectApiNames` added to each polymorphic Edit target (no single
 * `targetObjectApiName`): the objects its lookup can point to, read from the describe along the target path.
 * @param {object[]} actions normalized Row actions
 * @param {object[]} serverTargets `TableResult.rowActions`
 * @param {string} objectApiName the Table's object
 * @param {(objectApiName: string) => Promise<object[]>} loadFields describe of an object (`getObjectFields`)
 */
export async function withPolymorphicCandidates(actions, serverTargets, objectApiName, loadFields) {
    const targets = serverTargets || [];
    const polymorphicIds = new Set(
        actions
            .filter((action) => action.type === 'edit')
            .map((action) => targetFor(action, targets))
            .filter((target) => target && !target.targetObjectApiName && target.targetPath)
            .map((target) => target.id)
    );
    if (!polymorphicIds.size) {
        return targets;
    }
    return Promise.all(
        targets.map(async (target) => {
            if (!polymorphicIds.has(target.id)) {
                return target;
            }
            const candidateObjectApiNames = await lookupTargets(objectApiName, target.targetPath, loadFields);
            return { ...target, candidateObjectApiNames };
        })
    );
}

/** Objects the lookup at `path` (e.g. `OwnerId`, `Account.OwnerId`) can point to; empty when it can't be resolved. */
async function lookupTargets(objectApiName, path, loadFields) {
    const segments = String(path).split('.');
    let current = objectApiName;
    try {
        for (let i = 0; i < segments.length; i++) {
            const segment = segments[i].toLowerCase();
            const isLast = i === segments.length - 1;
            // eslint-disable-next-line no-await-in-loop -- each hop needs the previous object's describe
            const fields = (await loadFields(current)) || [];
            const field = fields.find(
                (candidate) =>
                    String((isLast ? candidate.apiName : candidate.relationshipName) || '').toLowerCase() === segment
            );
            const referenceTo = Array.isArray(field?.referenceTo) ? field.referenceTo : [];
            if (isLast) {
                return [...referenceTo];
            }
            if (referenceTo.length !== 1) {
                return [];
            }
            current = referenceTo[0];
        }
    } catch (error) {
        // An unreadable describe leaves the action hidden.
    }
    return [];
}

function targetFor(action, serverTargets) {
    return (serverTargets || []).find((target) => target.id === action.id) || null;
}

/** Trailing headers: one per `column` action, then one for the shared row menu when any `menu` action exists. */
export function buildActionHeaders(actions) {
    const headers = actions
        .filter((action) => action.placement === 'column')
        .map((action) => ({
            key: `action-${action.id}`,
            id: `action-${action.id}`,
            label: action.columnLabel,
            isSortable: false,
            headerClass: 'c-board-table-col c-board-table-col_left c-board-table-col_action',
            headerStyle: '',
            ariaSort: null
        }));
    if (actions.some((action) => action.placement === 'menu')) {
        headers.push({
            key: MENU_COLUMN_ID,
            id: MENU_COLUMN_ID,
            label: 'Actions',
            isSortable: false,
            headerClass: 'c-board-table-col c-board-table-col_right c-board-table-col_action',
            headerStyle: '',
            ariaSort: null
        });
    }
    return headers;
}

/**
 * Whether `action` shows on `row`: Create needs the object createable; otherwise its target lookup must hold an Id, and
 * Edit needs the target object to be updateable (`permissionsByObject`; hidden until known). A polymorphic Edit target
 * resolves the row's object from the record Id's key prefix among its candidate objects; hidden when none matches.
 */
function isVisible(action, row, serverTargets, permissionsByObject) {
    if (action.type === 'create') {
        return permissionsByObject.get(action.object)?.createable === true;
    }
    const target = targetFor(action, serverTargets);
    if (!target || !resolveActionRecordId(action, row, serverTargets)) {
        return false;
    }
    if (action.type === 'edit') {
        const recordId = resolveActionRecordId(action, row, serverTargets);
        return editPermission(target, recordId, permissionsByObject)?.updateable === true;
    }
    return true;
}

/** Permissions of the object an Edit action opens: its single target object, else the candidate with the Id's key prefix. */
function editPermission(target, recordId, permissionsByObject) {
    if (target.targetObjectApiName) {
        return permissionsByObject.get(target.targetObjectApiName);
    }
    const keyPrefix = recordId.slice(0, 3);
    const objectApiName = (target.candidateObjectApiNames || []).find(
        (name) => permissionsByObject.get(name)?.keyPrefix === keyPrefix
    );
    return objectApiName ? permissionsByObject.get(objectApiName) : null;
}

/** Record Id `action` opens on `row`, or null when the target lookup is empty. */
export function resolveActionRecordId(action, row, serverTargets) {
    const target = targetFor(action, serverTargets);
    const value = String(target ? (row.values?.[target.targetPath] ?? '') : '');
    return RECORD_ID_PATTERN.test(value) ? value : null;
}

function actionView(action) {
    return { key: action.id, value: action.id, label: action.label, icon: action.icon };
}

/**
 * Action cells of one row, parallel to `buildActionHeaders`. A menu with a single visible action is a button.
 * @param {object[]} actions normalized Row actions
 * @param {{ id: string, values: object }} row
 * @param {{ id: string, targetPath: string, targetObjectApiName: string }[]} serverTargets `TableResult.rowActions`
 * @param {Map<string, { updateable: boolean, createable: boolean }>} permissionsByObject
 */
export function buildActionCells(actions, row, serverTargets, permissionsByObject) {
    return actionCells(actions, row, (action) => isVisible(action, row, serverTargets, permissionsByObject));
}

/**
 * Whether `action` acts on the record of a Group row grouped by the lookup `groupFieldPath`: View / Edit whose target
 * is that lookup, or a Screen Flow with an input mapped from it or from `Id` (the group's record Id on a Group row).
 * Create and View / Edit of the row's own record never do.
 */
function targetsGroupLookup(action, groupFieldPath, serverTargets) {
    const groupPath = String(groupFieldPath || '').toLowerCase();
    const target = targetFor(action, serverTargets);
    if (!groupPath || !target) {
        return false;
    }
    if (action.type === 'flow') {
        // An input mapped from `Id` (the default `recordId`) gets the group's record Id on a Group row.
        return action.inputs.some((entry, index) => {
            const path = String(target.fieldPaths?.[index] || entry.rowField).toLowerCase();
            return path === groupPath || path === 'id';
        });
    }
    return (action.type === 'view' || action.type === 'edit') && target.targetPath.toLowerCase() === groupPath;
}

/**
 * Action cells of a Group row, parallel to `buildActionHeaders`: only actions targeting the group's lookup record show
 * (see `targetsGroupLookup`), and only when the group has a record (`groupRow` from `groupActionRow`).
 * @param {object[]} actions normalized Row actions
 * @param {{ id: string, values: object }} groupRow
 * @param {string} groupFieldPath the Group row's group field
 * @param {object[]} serverTargets `TableResult.rowActions`
 * @param {Map<string, { updateable: boolean, createable: boolean }>} permissionsByObject
 */
export function buildGroupActionCells(actions, groupRow, groupFieldPath, serverTargets, permissionsByObject) {
    const hasRecord = RECORD_ID_PATTERN.test(String(groupRow.values?.[groupFieldPath] ?? ''));
    return actionCells(actions, groupRow, (action) => {
        if (!hasRecord || !targetsGroupLookup(action, groupFieldPath, serverTargets)) {
            return false;
        }
        return action.type === 'flow' || isVisible(action, groupRow, serverTargets, permissionsByObject);
    });
}

function actionCells(actions, row, shows) {
    const cells = actions
        .filter((action) => action.placement === 'column')
        .map((action) => toCell(row, `action-${action.id}`, shows(action) ? [actionView(action)] : []));
    if (actions.some((action) => action.placement === 'menu')) {
        const menuActions = actions.filter((action) => action.placement === 'menu' && shows(action));
        cells.push(toCell(row, MENU_COLUMN_ID, menuActions.map(actionView)));
    }
    return cells;
}

function toCell(row, columnId, actions) {
    return {
        key: `${row.id}-${columnId}`,
        columnId,
        isActions: true,
        isSingleAction: actions.length === 1,
        isMenu: actions.length > 1,
        action: actions[0] || null,
        actions,
        rowId: row.id,
        cellClass: 'c-board-table-col c-board-table-col_action',
        contentClass: ''
    };
}

/**
 * Standard create page reference of a Create action: `defaultFieldValues` come from the row (empty values are
 * skipped), via `encodeDefaultFieldValues`; the optional record type is passed through.
 */
export function buildCreatePageReference(action, row, serverTarget, encodeDefaultFieldValues) {
    const defaults = {};
    action.defaults.forEach((entry, index) => {
        const path = serverTarget?.fieldPaths?.[index] || entry.rowField;
        const value = row.values?.[path];
        if (value !== null && value !== undefined && value !== '') {
            defaults[entry.field] = value;
        }
    });
    const state = {};
    if (Object.keys(defaults).length) {
        state.defaultFieldValues = encodeDefaultFieldValues(defaults);
    }
    if (action.recordTypeId) {
        state.recordTypeId = action.recordTypeId;
    }
    return {
        type: 'standard__objectPage',
        attributes: { objectApiName: action.object, actionName: 'new' },
        state
    };
}

/**
 * `lightning-flow` input variables of a Screen Flow action: each mapped row field (empty values are skipped) as a
 * String variable.
 */
export function buildFlowInputVariables(action, row, serverTarget) {
    const variables = [];
    action.inputs.forEach((entry, index) => {
        const path = serverTarget?.fieldPaths?.[index] || entry.rowField;
        const value = row.values?.[path];
        if (value !== null && value !== undefined && value !== '') {
            variables.push({ name: entry.name, type: 'String', value: String(value) });
        }
    });
    return variables;
}