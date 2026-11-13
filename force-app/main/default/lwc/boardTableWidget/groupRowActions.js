/**
 * Row actions on Group rows (Row grouping, Detail rows on or off).
 *
 * Detail rows keep every Row action. A Group row offers only the actions that act on the group's lookup record (View /
 * Edit targeting the group lookup, a Screen Flow with an input mapped from it or from `Id`), run on a stand-in row whose group field
 * holds the group's record Id (plus, with Detail rows off, the group's values through the lookup).
 */
import { buildGroupActionCells } from './rowActions';
import { groupToken } from './rowGrouping';

const GROUP_ROW_ID_PREFIX = 'group:';

/** Group field path of a Group row at `level` (1 or 2). */
function groupFieldPathAt(groupField, level) {
    return (level === 2 ? groupField?.secondLevel?.fieldPath : groupField?.fieldPath) || null;
}

/**
 * The row a Group row's actions run on: `{ id, values }` with the group's record Id under its group field and under
 * `Id` (a Group row has no record of its own, so a Screen Flow input mapped from `Id` gets the group's record).
 */
function groupActionRow(token, group, groupFieldPath) {
    const recordId = group?.recordId ?? null;
    return {
        id: `${GROUP_ROW_ID_PREFIX}${token}`,
        values: { ...(group?.values || {}), Id: recordId, [groupFieldPath]: recordId }
    };
}

/** Group facts and group field of a Group row token, for the current Table state. */
function groupOf(token, tableData) {
    const groupField = tableData?.groupField;
    if (tableData?.aggregateGroups) {
        const group = tableData.aggregateGroups.find((candidate) => groupToken(candidate.key) === token);
        return { group, fieldPath: groupFieldPathAt(groupField, 1) };
    }
    const group = tableData?.groups?.[token];
    return { group, fieldPath: groupFieldPathAt(groupField, group?.level === 2 ? 2 : 1) };
}

/**
 * The stand-in row of a Group row action's `data-row-id`, or null when `rowId` is not a Group row's.
 * @param {string} rowId
 * @param {object} tableData widget table state (`groupField`, `groups` or `aggregateGroups`)
 */
export function resolveGroupActionRow(rowId, tableData) {
    if (!String(rowId || '').startsWith(GROUP_ROW_ID_PREFIX)) {
        return null;
    }
    const token = rowId.slice(GROUP_ROW_ID_PREFIX.length);
    const { group, fieldPath } = groupOf(token, tableData);
    return group && fieldPath ? groupActionRow(token, group, fieldPath) : null;
}

/**
 * Rendered rows with action cells on their Group rows. Aggregated Group rows swap their blank action-column cells for
 * action cells; Group rows with Detail rows on end their `summaryCells` with them (narrowing the group cell's colspan
 * when they have no summaries). Unchanged when there are no Row action columns.
 * @param {object[]} views rendered rows
 * @param {object} options
 * @param {object[]} options.actions normalized Row actions
 * @param {object[]} options.actionHeaders from `buildActionHeaders`
 * @param {number} options.headerCount every rendered header
 * @param {object} options.tableData widget table state
 * @param {Map<string, object>} options.permissionsByObject
 */
export function withGroupRowActions(views, { actions, actionHeaders, headerCount, tableData, permissionsByObject }) {
    if (!actionHeaders.length) {
        return views;
    }
    const actionCellsOf = (view) => {
        const { group, fieldPath } = groupOf(view.token, tableData);
        return buildGroupActionCells(
            actions,
            groupActionRow(view.token, group, fieldPath),
            fieldPath,
            tableData?.rowActions || [],
            permissionsByObject
        );
    };
    const actionIds = new Set(actionHeaders.map((header) => header.id));
    return views.map((view) => {
        if (view.isAggregateGroup) {
            const cells = actionCellsOf(view);
            return { ...view, cells: [...view.cells.filter((cell) => !actionIds.has(cell.columnId)), ...cells] };
        }
        if (view.isGroup) {
            const cells = actionCellsOf(view);
            const summaryCells = view.summaryCells || [];
            return summaryCells.length
                ? { ...view, summaryCells: [...summaryCells.slice(0, -actionHeaders.length), ...cells] }
                : { ...view, summaryCells: cells, groupColspan: headerCount - actionHeaders.length };
        }
        return view;
    });
}