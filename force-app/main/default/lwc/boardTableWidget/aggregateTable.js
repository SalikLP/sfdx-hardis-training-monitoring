/**
 * Row grouping with Detail rows off: the Table as an aggregated table.
 *
 * The server returns every Group row at once (`TableResult.aggregateGroups`, see `BoardTableAggregate`), each with
 * its record count, the values of fields reached through the lookup group field and the Stacked summaries of the
 * columns with summaries. There is no paging and no collapse; header clicks re-sort the loaded Group rows: by the
 * column's first summary, by the column's value, or (group column) by the group label. "(Blank)" always stays last.
 */
import LOCALE from '@salesforce/i18n/locale';
import { GROUP_COLUMN_ID, BLANK_GROUP_LABEL, buildGroupHeader, groupToken } from './rowGrouping';
import { SUMMARY_LABELS } from './totalRow';
import { buildCellView, formatCell, summaryBarView } from './tableCells';

const RECORD_ID_PATTERN = /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/;

function direction(value) {
    return String(value || '').toUpperCase() === 'DESC' ? 'DESC' : 'ASC';
}

function isBlank(value) {
    return value === null || value === undefined || value === '';
}

function firstGroupEntry(config) {
    return (Array.isArray(config?.groupBy) ? config.groupBy : []).find((entry) => entry?.fieldPath) || null;
}

/** True when the config groups rows with Detail rows off. */
export function isAggregateConfig(config) {
    return config?.detailRows === false && Boolean(firstGroupEntry(config));
}

/**
 * Request fields of an aggregated table (`{}` otherwise): `detailRows: false` and the group order by summary.
 * Column `summaries` come with every grouped request (`withGroupSummariesRequest`).
 * @param {object} request grouped `queryTable` request (`groupBy`)
 * @param {object} config Table config
 */
export function aggregateRequestFields(request, config) {
    if (!isAggregateConfig(config) || !Array.isArray(request.groupBy)) {
        return {};
    }
    const entry = firstGroupEntry(config);
    const order = {};
    if (entry.orderBySummary) {
        order.orderBySummary = entry.orderBySummary;
    } else if (entry.orderBy) {
        order.orderBy = entry.orderBy;
    }
    return {
        detailRows: false,
        groupBy: request.groupBy.map((groupEntry, index) => (index === 0 ? { ...groupEntry, ...order } : groupEntry))
    };
}

/** Group column header of an aggregated table: sorted only while Group rows are ordered by the group itself. */
export function buildAggregateGroupHeader(groupField, sortBy) {
    const header = buildGroupHeader(groupField);
    return sortBy ? { ...header, isSorted: false, ariaSort: 'none' } : header;
}

function summariesOf(group, columnId) {
    return (group.summaries || []).find((entry) => entry.columnId === columnId)?.summaries || null;
}

function compareValues(left, right) {
    if (typeof left === 'number' && typeof right === 'number') {
        return left - right;
    }
    return String(left).localeCompare(String(right), LOCALE, { numeric: true });
}

/**
 * The loaded aggregated table re-sorted after a header click: the group column toggles the group order by label;
 * a column with summaries sorts by its first summary; any other column by its value. Blank values sort last and
 * "(Blank)" stays the last Group row. No query.
 * @param {object} tableData widget table state (`aggregateGroups`, `groupField`, `sortBy`, `sortDirection`)
 * @param {{ columnId: string, fieldPath: string }} header clicked header
 */
export function sortAggregateTable(tableData, header) {
    const groups = tableData.aggregateGroups || [];
    let valueOf;
    let sortBy = null;
    let sortDirection;
    let groupField = tableData.groupField;
    if (header.columnId === GROUP_COLUMN_ID) {
        sortDirection = !tableData.sortBy && direction(groupField?.sortDirection) === 'ASC' ? 'DESC' : 'ASC';
        groupField = { ...groupField, sortDirection };
        valueOf = (group) => group.label;
    } else {
        sortBy = header.fieldPath;
        sortDirection = tableData.sortBy === sortBy && tableData.sortDirection === 'ASC' ? 'DESC' : 'ASC';
        const bySummary = groups.some((group) => summariesOf(group, header.columnId));
        valueOf = bySummary
            ? (group) => summariesOf(group, header.columnId)?.[0]?.value
            : (group) => group.values?.[header.fieldPath];
    }
    const factor = sortDirection === 'DESC' ? -1 : 1;
    const sorted = groups
        .map((group, index) => ({ group, index }))
        .sort((a, b) => {
            const aBlankGroup = groupToken(a.group.key) === '';
            const bBlankGroup = groupToken(b.group.key) === '';
            if (aBlankGroup !== bBlankGroup) {
                return aBlankGroup ? 1 : -1;
            }
            const left = valueOf(a.group);
            const right = valueOf(b.group);
            if (isBlank(left) || isBlank(right)) {
                return isBlank(left) === isBlank(right) ? a.index - b.index : isBlank(left) ? 1 : -1;
            }
            return compareValues(left, right) * factor || a.index - b.index;
        })
        .map((entry) => entry.group);
    return { ...tableData, aggregateGroups: sorted, groupField, sortBy, sortDirection };
}

function groupLabelCell(group, token, header, formatCount) {
    const label = token === '' ? BLANK_GROUP_LABEL : group.label || token;
    const candidateId = token === '' ? null : group.recordId;
    const recordId = RECORD_ID_PATTERN.test(String(candidateId ?? '')) ? String(candidateId) : null;
    const hasCount = typeof group.count === 'number';
    return {
        key: `${token}-${header.id}`,
        columnId: header.id,
        isGroupLabel: true,
        label,
        recordId,
        href: recordId ? `/${recordId}` : null,
        isLink: Boolean(recordId),
        hasCount,
        countText: hasCount ? formatCount(group.count) : '',
        cellClass: `${header.headerClass} c-board-table-group-cell`
    };
}

function summaryCell(token, column, summaries) {
    return {
        key: `${token}-${column.id}`,
        columnId: column.id,
        isSummary: true,
        cellClass: column.cellClass,
        lines: summaries.map((summary) => {
            const label = SUMMARY_LABELS[summary.summaryFunction] || summary.summaryFunction;
            const text = formatCell(summary.value, column);
            return { key: summary.summaryFunction, label, text, title: `${label}: ${text}` };
        })
    };
}

/**
 * Rendered Group rows of an aggregated table: one cell per header (group label and count, field values, stacked
 * summaries; Row action columns blank).
 * @param {object[]} groups `TableResult.aggregateGroups`, in display order
 * @param {object[]} headerViews every rendered header, in order
 * @param {object[]} columnViews data columns from `buildColumnViews`
 * @param {(count: number) => string} formatCount
 */
export function buildAggregateRowViews(groups, headerViews, columnViews, formatCount) {
    const columnsById = new Map(columnViews.map((column) => [column.id, column]));
    return (groups || []).map((group, index) => {
        const token = groupToken(group.key);
        const cells = headerViews.map((header) => {
            if (header.id === GROUP_COLUMN_ID) {
                return groupLabelCell(group, token, header, formatCount);
            }
            const column = columnsById.get(header.id);
            if (!column) {
                return { key: `${token}-${header.id}`, columnId: header.id, isEmpty: true, cellClass: '' };
            }
            const summaries = summariesOf(group, column.id);
            if (summaries) {
                return { ...summaryCell(token, column, summaries), ...summaryBarView(column, summaries) };
            }
            const cell = buildCellView(column, { id: `group-${token}`, values: group.values || {} });
            return { ...cell, columnId: column.id, isValue: true };
        });
        return {
            key: `aggregate-${index}-${token}`,
            isAggregateGroup: true,
            token,
            rowClass: 'c-board-table-group-row c-board-table-aggregate-row',
            cells
        };
    });
}