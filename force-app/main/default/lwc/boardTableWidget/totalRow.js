import { formatCell } from './tableCells';

/** Stacked summary labels, in the order an Admin can pick them. */
export const SUMMARY_LABELS = { SUM: 'Sum', AVG: 'Average', MIN: 'Min', MAX: 'Max' };
const UNAVAILABLE_TEXT = 'Too many records to total';

/** A column's configured summaries: the known functions in order, or [] for none. */
function columnSummaries(column) {
    return Array.isArray(column?.summaries) ? column.summaries.filter((name) => SUMMARY_LABELS[name]) : [];
}

/**
 * Adds the Total row to a Table query request: `showTotalRow` plus each column's ordered `summaries`. Unchanged when
 * the Total row is off.
 * @param {object} request `queryTable` request whose `columns` are index-aligned with `configColumns`
 * @param {object} config Table config (`showTotalRow`)
 * @param {object[]} configColumns `TableColumnConfig[]`
 */
export function withTotalRowRequest(request, config, configColumns) {
    if (config?.showTotalRow !== true) {
        return request;
    }
    return {
        ...request,
        showTotalRow: true,
        columns: request.columns.map((column, index) => {
            const summaries = columnSummaries(configColumns[index]);
            return summaries.length ? { ...column, summaries } : column;
        })
    };
}

/**
 * The Total row: one cell per header. Data columns with summaries show them labelled and stacked, formatted like
 * the column; every other cell (non-numeric columns, the group column, Row action columns) is blank. Null when
 * there is nothing to show.
 * @param {object[]} headerViews every rendered header (`{ id, headerClass }`), in order
 * @param {object[]} columnViews data columns from `buildColumnViews`
 * @param {object[]|null} totals `TableResult.totals` (`{ columnId, summaries: [{ summaryFunction, value }] }`)
 * @param {boolean} unavailable `TableResult.totalRowUnavailable`
 */
export function buildTotalRowView(headerViews, columnViews, totals, unavailable) {
    if (!Array.isArray(totals) && !unavailable) {
        return null;
    }
    const columnsById = new Map(columnViews.map((column) => [column.id, column]));
    const totalsById = new Map((totals || []).map((total) => [total.columnId, total.summaries || []]));
    const cells = headerViews.map((header, index) => {
        const column = columnsById.get(header.id);
        const summaries = column ? totalsById.get(column.id) || [] : [];
        return {
            key: `total-${header.id}`,
            cellClass: column ? column.cellClass : header.headerClass || '',
            isFirst: index === 0,
            note: index === 0 && unavailable ? UNAVAILABLE_TEXT : null,
            lines: summaries.map((summary) => {
                const label = SUMMARY_LABELS[summary.summaryFunction] || summary.summaryFunction;
                const text = formatCell(summary.value, column);
                return { key: summary.summaryFunction, label, text, title: `${label}: ${text}` };
            })
        };
    });
    return { cells };
}