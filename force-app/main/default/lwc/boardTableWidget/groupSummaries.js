import { buildTotalRowView, SUMMARY_LABELS } from './totalRow';

/**
 * Group summaries and Subtotals of a Table with Row grouping and Detail rows on.
 *
 * The server returns each group's Stacked summaries over the whole group with every page that holds its records
 * (`BoardTableEngine.TableGroup.summaries`). Group rows show them under their columns; with Subtotals on, a Subtotal
 * row closes each group after its last record. A group's last record is known once the next group starts or the
 * stream has no more pages, so a group spanning pages gets its Subtotal only when its last page has arrived.
 */

function isGrouped(config) {
    return Array.isArray(config?.groupBy) && config.groupBy.some((entry) => entry?.fieldPath);
}

/**
 * Adds each column's ordered `summaries` to the query request of a grouped Table, so Group and Subtotal rows have
 * them even when the Total row is off. Unchanged when ungrouped.
 * @param {object} request `queryTable` request whose `columns` are index-aligned with `configColumns`
 * @param {object} config Table config (`groupBy`)
 * @param {object[]} configColumns `TableColumnConfig[]`
 */
export function withGroupSummariesRequest(request, config, configColumns) {
    if (!isGrouped(config)) {
        return request;
    }
    return {
        ...request,
        columns: request.columns.map((column, index) => {
            const summaries = Array.isArray(configColumns[index]?.summaries)
                ? configColumns[index].summaries.filter((name) => SUMMARY_LABELS[name])
                : [];
            return summaries.length ? { ...column, summaries } : column;
        })
    };
}

/** Summary cells of one group under every header, tagged with their header id; null when it has no summaries. */
function summaryCells(group, headerViews, columnViews, keyPrefix) {
    if (!Array.isArray(group?.summaries) || !group.summaries.length) {
        return null;
    }
    const view = buildTotalRowView(headerViews, columnViews, group.summaries, false);
    return view.cells.map((cell, index) => ({
        ...cell,
        key: `${keyPrefix}-${headerViews[index].id}`,
        columnId: headerViews[index].id
    }));
}

function subtotalRow(groupView, group, headerViews, columnViews) {
    const key = `subtotal-${groupView.key}`;
    const cells = summaryCells(group, headerViews, columnViews, key) || [];
    const level = groupView.level || 1;
    return {
        key,
        isSubtotal: true,
        token: groupView.token,
        level,
        rowClass: `c-board-table-subtotal-row c-board-table-subtotal-row_level-${level}`,
        title: `Subtotal: ${groupView.label}`,
        cells: cells.slice(1),
        labelColspan: cells.length ? 1 : headerViews.length
    };
}

/**
 * Group rows (from `buildGroupedRows`) with their summary cells, plus a Subtotal row closing each expanded group when
 * Subtotals are on: a second-level group closes before the next second-level group or its first-level group's
 * Subtotal. Group rows get `summaryCells` (under every header after the group column) and `groupColspan`.
 * @param {object[]} views output of `buildGroupedRows`
 * @param {object} options
 * @param {object} options.groupsByToken from `mergeGroups`
 * @param {object[]} options.headerViews every rendered header, the group column first
 * @param {object[]} options.columnViews data columns from `buildColumnViews`
 * @param {boolean} options.showSubtotals config `showSubtotals`
 * @param {boolean} options.complete true when no more pages will arrive (closes the last groups)
 */
export function withGroupSummaryRows(views, { groupsByToken, headerViews, columnViews, showSubtotals, complete }) {
    const rows = [];
    /** Open Group rows by level, innermost last. */
    let open = [];
    const closeFrom = (level) => {
        const closing = open.filter((groupView) => (groupView.level || 1) >= level).reverse();
        open = open.filter((groupView) => (groupView.level || 1) < level);
        if (!showSubtotals) {
            return;
        }
        closing
            .filter((groupView) => !groupView.collapsed)
            .forEach((groupView) =>
                rows.push(subtotalRow(groupView, groupsByToken?.[groupView.token], headerViews, columnViews))
            );
    };
    views.forEach((view) => {
        if (!view.isGroup) {
            rows.push(view);
            return;
        }
        closeFrom(view.level || 1);
        const cells = summaryCells(groupsByToken?.[view.token], headerViews, columnViews, `summary-${view.key}`);
        const groupView = {
            ...view,
            summaryCells: cells ? cells.slice(1) : [],
            groupColspan: cells ? 1 : headerViews.length
        };
        open.push(groupView);
        rows.push(groupView);
    });
    if (complete) {
        closeFrom(1);
    }
    return rows;
}