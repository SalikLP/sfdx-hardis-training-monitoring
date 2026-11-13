/**
 * Row grouping with Detail rows on: Group rows inserted client-side between the group-sorted records as pages arrive.
 *
 * The server streams records ordered by the group field (blanks last) and returns, with every page, the full-group
 * count of each group on that page (`BoardTableEngine.TableGroup`). A group's records are contiguous, so a Group row is
 * inserted wherever the group key changes; a group spanning pages keeps the one Group row of its first page.
 */

/** `data-column-id` of the group column (its header toggles the group order). */
export const GROUP_COLUMN_ID = 'group';
export const BLANK_GROUP_LABEL = '(Blank)';
const RECORD_ID_PATTERN = /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/;
const ARIA_SORT = { ASC: 'ascending', DESC: 'descending' };

function direction(value) {
    return String(value || '').toUpperCase() === 'DESC' ? 'DESC' : 'ASC';
}

const MAX_GROUP_LEVELS = 2;
/** Separates the first- and second-level keys in a second-level group's token. */
const TOKEN_SEPARATOR = '\u001f';

function groupEntryRequest(entry, sortDirection) {
    const request = { fieldPath: entry.fieldPath, sortDirection };
    if (entry.dateGranularity) {
        request.dateGranularity = entry.dateGranularity;
    }
    if (entry.orderBy) {
        request.orderBy = entry.orderBy;
    }
    return request;
}

/**
 * The `groupBy` request entries for the configured group fields (up to two), or null for an ungrouped Table.
 * @param {object} config Widget config (`groupBy: [{ fieldPath, sortDirection, dateGranularity, orderBy }]`)
 * @param {string|null} directionOverride end user's first-level group order from the group column header
 */
export function groupByRequest(config, directionOverride) {
    const entries = Array.isArray(config?.groupBy) ? config.groupBy.filter((entry) => entry?.fieldPath) : [];
    if (!entries.length) {
        return null;
    }
    return entries
        .slice(0, MAX_GROUP_LEVELS)
        .map((entry, index) =>
            groupEntryRequest(entry, (index === 0 && directionOverride) || direction(entry.sortDirection))
        );
}

/** Stable string token of a group key; the blank group's token is `''`. */
export function groupToken(key) {
    return key === null || key === undefined || key === '' ? '' : String(key);
}

/** Token of a second-level group: its first-level group's token and its own, so equal keys under two parents differ. */
function subgroupToken(parentToken, key) {
    return `${parentToken}${TOKEN_SEPARATOR}${groupToken(key)}`;
}

/** Group facts by token, with a page's groups merged in (a later page's count of the same group is the same count). */
export function mergeGroups(groupsByToken, pageGroups) {
    const merged = { ...(groupsByToken || {}) };
    (Array.isArray(pageGroups) ? pageGroups : []).forEach((group) => {
        if (group) {
            const token =
                group.level === 2 ? subgroupToken(groupToken(group.parentKey), group.key) : groupToken(group.key);
            merged[token] = group;
        }
    });
    return merged;
}

/** Group order after a click on the group column header. */
export function toggledGroupDirection(groupField) {
    return direction(groupField?.sortDirection) === 'ASC' ? 'DESC' : 'ASC';
}

/** Header of the group column: sortable, always sorted by the group order. */
export function buildGroupHeader(groupField) {
    const sortDirection = direction(groupField?.sortDirection);
    return {
        key: GROUP_COLUMN_ID,
        id: GROUP_COLUMN_ID,
        fieldPath: groupField?.fieldPath,
        label:
            [groupField, groupField?.secondLevel]
                .filter((level) => level?.fieldPath)
                .map((level) => level.label || level.fieldPath)
                .join(' / ') || 'Group',
        isSortable: true,
        isSorted: true,
        sortDirection,
        ariaSort: ARIA_SORT[sortDirection],
        sortIcon: sortDirection === 'DESC' ? 'utility:arrowdown' : 'utility:arrowup',
        sortAssistiveText: sortDirection === 'DESC' ? 'Groups sorted descending' : 'Groups sorted ascending',
        headerClass: 'c-board-table-col c-board-table-col_group',
        headerStyle: ''
    };
}

/** Empty leading cell of a detail row, under the group column. */
export function groupSpacerCell(rowId) {
    return {
        key: `${rowId}-${GROUP_COLUMN_ID}`,
        text: '',
        title: '',
        isPlain: true,
        cellClass: 'c-board-table-col c-board-table-col_group',
        contentClass: 'slds-truncate'
    };
}

/** Path in a row's values holding the group key (a date group's bucket key is added by the server). */
function keyPath(groupField) {
    return groupField.keyPath || groupField.fieldPath;
}

function groupRowView({ token, key, level }, group, row, groupField, index, collapsed, formatCount) {
    const isBlank = groupToken(key) === '';
    const fallbackLabel = groupField.labelPath
        ? row.values?.[groupField.labelPath]
        : row.values?.[groupField.fieldPath];
    const label = isBlank ? BLANK_GROUP_LABEL : group?.label || fallbackLabel || groupToken(key);
    const candidateId = isBlank ? null : group?.recordId;
    const recordId = RECORD_ID_PATTERN.test(String(candidateId ?? '')) ? String(candidateId) : null;
    const count = typeof group?.count === 'number' ? group.count : null;
    return {
        key: `group-${index}-${token}`,
        isGroup: true,
        token,
        level,
        rowClass: `c-board-table-group-row c-board-table-group-row_level-${level}`,
        label,
        recordId,
        href: recordId ? `/${recordId}` : null,
        isLink: Boolean(recordId),
        countText: count === null ? '' : formatCount(count),
        hasCount: count !== null,
        collapsed,
        ariaExpanded: collapsed ? 'false' : 'true',
        toggleIcon: collapsed ? 'utility:chevronright' : 'utility:chevrondown',
        toggleLabel: collapsed ? `Expand ${label}` : `Collapse ${label}`
    };
}

/**
 * The loaded rows gathered by group key in first-seen order, nested `{ token, key, row, rows, subgroups }`. Groups
 * are contiguous in the stream except records whose parent-path group field has a missing parent (they sort by a
 * platform placeholder value): gathering keeps every group, "(Blank)" included, under one Group row per level.
 */
function gatherGroups(rows, path, tokenOf) {
    const groups = new Map();
    (rows || []).forEach((row) => {
        const key = row.values?.[path];
        const token = tokenOf(key);
        if (!groups.has(token)) {
            groups.set(token, { token, key, row, rows: [] });
        }
        groups.get(token).rows.push(row);
    });
    return [...groups.values()];
}

/**
 * Group rows interleaved with the detail rows of the loaded records: first-level Group rows, then (with a second
 * group field) the nested second-level Group rows, then the records. A collapsed group hides everything under it.
 * @param {object[]} rows loaded `BoardQueryService.TableRow`s, group-sorted
 * @param {object} groupField `{ fieldPath, keyPath, labelPath, secondLevel }`
 * @param {object} groupsByToken from `mergeGroups`
 * @param {(token: string) => boolean} isCollapsed
 * @param {(row: object) => object} buildDetail detail row view
 * @param {(count: number) => string} formatCount
 */
export function buildGroupedRows(rows, groupField, groupsByToken, isCollapsed, buildDetail, formatCount) {
    const secondField = groupField.secondLevel?.fieldPath ? groupField.secondLevel : null;
    const views = [];
    const groupRow = (identity, field, row, collapsed) =>
        groupRowView(identity, groupsByToken?.[identity.token], row, field, views.length, collapsed, formatCount);
    gatherGroups(rows, keyPath(groupField), groupToken).forEach((group) => {
        const collapsed = isCollapsed(group.token);
        views.push(groupRow({ token: group.token, key: group.key, level: 1 }, groupField, group.row, collapsed));
        if (collapsed) {
            return;
        }
        if (!secondField) {
            group.rows.forEach((row) => views.push(buildDetail(row)));
            return;
        }
        gatherGroups(group.rows, keyPath(secondField), (key) => subgroupToken(group.token, key)).forEach((subgroup) => {
            const subCollapsed = isCollapsed(subgroup.token);
            views.push(
                groupRow(
                    { token: subgroup.token, key: subgroup.key, level: 2 },
                    secondField,
                    subgroup.row,
                    subCollapsed
                )
            );
            if (!subCollapsed) {
                subgroup.rows.forEach((row) => views.push(buildDetail(row)));
            }
        });
    });
    return views;
}