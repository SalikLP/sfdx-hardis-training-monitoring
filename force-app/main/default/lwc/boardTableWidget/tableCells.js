import { formatValue, formatTemporal } from 'c/boardConfigUtils';
import { displayCurrencyFormat } from 'c/boardDisplayCurrency';

const NUMERIC_TYPES = new Set(['INTEGER', 'LONG', 'DOUBLE']);
const AUTO_DISPLAY = {
    CURRENCY: 'currency',
    PERCENT: 'percent',
    DATE: 'date',
    DATETIME: 'datetime',
    BOOLEAN: 'boolean',
    PICKLIST: 'badge'
};
const DATA_BAR = 'dataBar';
const RIGHT_ALIGNED = new Set(['number', 'currency', 'percent']);
const ARIA_SORT = { ASC: 'ascending', DESC: 'descending' };
/** Admin `width` values accepted into the header style; anything else (e.g. injected declarations) is dropped. */
const COLUMN_WIDTH_PATTERN = /^\d+(\.\d+)?(px|rem|em|%)$/;
/** 15- or 18-character Salesforce record Id; only these become record links. */
const RECORD_ID_PATTERN = /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/;

/** `displayAs` with `'auto'` resolved from the column's `Schema.DisplayType`. */
function resolveDisplayAs(displayAs, dataType) {
    if (displayAs && displayAs !== 'auto') {
        return displayAs;
    }
    if (NUMERIC_TYPES.has(dataType)) {
        return 'number';
    }
    return AUTO_DISPLAY[dataType] || 'text';
}

function resolveAlign(align, displayAs) {
    if (align && align !== 'auto') {
        return align;
    }
    if (RIGHT_ALIGNED.has(displayAs)) {
        return 'right';
    }
    return displayAs === 'boolean' ? 'center' : 'left';
}

/**
 * Merges server-resolved columns (`BoardQueryService.TableColumn`) with their admin `TableColumnConfig`.
 * @param {object[]} serverColumns `{ id, fieldPath, label, dataType, isSortable, linkPath, currencyIsoCode }`
 * @param {object[]} configColumns `TableColumnConfig[]`
 * @param {{ sortBy: string, sortDirection: string }} sort effective server sort
 */
export function buildColumnViews(serverColumns, configColumns, sort, barScales) {
    const scaleById = new Map((barScales || []).map((scale) => [scale.columnId, scale]));
    const configById = new Map((configColumns || []).map((column) => [column?.id || column?.fieldPath, column]));
    return (serverColumns || []).map((serverColumn, index) => {
        const config = configById.get(serverColumn.id) || {};
        const displayAs = resolveDisplayAs(config.displayAs, serverColumn.dataType);
        const align = resolveAlign(config.align, displayAs);
        // A Data bar column shows its value as the field's natural number style.
        const valueDisplayAs = displayAs === DATA_BAR ? resolveDisplayAs(null, serverColumn.dataType) : displayAs;
        const isSorted = Boolean(sort?.sortBy) && sort.sortBy === serverColumn.fieldPath;
        const isSortable = serverColumn.isSortable === true;
        const classes = ['c-board-table-col', `c-board-table-col_${align}`];
        if (index === 0) {
            classes.push('c-board-table-col_first');
        }
        // The first column is sticky, so it never narrow-hides.
        if (config.hideOnNarrow === true && index > 0) {
            classes.push('c-board-table-col_narrow-hidden');
        }
        const width = typeof config.width === 'string' ? config.width.trim() : '';
        const sortDirection = isSorted ? sort.sortDirection : null;
        return {
            key: serverColumn.id,
            id: serverColumn.id,
            fieldPath: serverColumn.fieldPath,
            linkPath: serverColumn.linkPath || null,
            dataType: serverColumn.dataType,
            label: config.label || serverColumn.label || serverColumn.fieldPath,
            displayAs,
            valueDisplayAs,
            barOnly: config.barOnly === true,
            barScale: displayAs === DATA_BAR ? scaleById.get(serverColumn.id) || null : null,
            format: config.format || null,
            currencyIsoCode: serverColumn.currencyIsoCode || null,
            wrapText: config.wrapText === true,
            isSortable,
            isSorted,
            sortDirection,
            ariaSort: isSortable ? (ARIA_SORT[sortDirection] ?? 'none') : null,
            sortIcon: sortDirection === 'DESC' ? 'utility:arrowdown' : 'utility:arrowup',
            sortAssistiveText: sortDirection === 'DESC' ? 'Sorted descending' : 'Sorted ascending',
            headerClass: classes.join(' '),
            cellClass: classes.join(' '),
            headerStyle: COLUMN_WIDTH_PATTERN.test(width) ? `width: ${width}; min-width: ${width};` : ''
        };
    });
}

/**
 * Currency columns format with the Display currency ISO code Apex returned on the column (a saved `currencyCode`
 * is ignored); other columns keep their format (a currency style there uses the viewer's currency).
 */
function cellFormat(format, currencyIsoCode) {
    if (currencyIsoCode) {
        return displayCurrencyFormat(format, currencyIsoCode);
    }
    const { currencyCode, ...rest } = format; // eslint-disable-line no-unused-vars
    return rest;
}

export function formatCell(value, column) {
    if (value === null || value === undefined || value === '') {
        return '';
    }
    switch (column.valueDisplayAs || column.displayAs) {
        case 'number':
        case 'currency':
        case 'percent': {
            const numeric = Number(value);
            if (!Number.isFinite(numeric)) {
                return String(value);
            }
            const valueDisplayAs = column.valueDisplayAs || column.displayAs;
            const formatStyle = valueDisplayAs === 'number' ? column.format?.formatStyle : valueDisplayAs;
            return formatValue(
                numeric,
                cellFormat({ ...(column.format || {}), formatStyle: formatStyle || 'number' }, column.currencyIsoCode),
                {
                    valueType: column.dataType
                }
            );
        }
        case 'date':
        case 'datetime':
            return formatTemporal(value, column.displayAs);
        default:
            return String(value);
    }
}

function percent(part, whole) {
    return Math.min(100, Math.max(0, (part / whole) * 100));
}

/**
 * Geometry of a Data bar. The server scale `{ max, min }` spans the whole scope, so the axis runs from the most
 * negative value (left) through the zero line to the largest positive one (right) and never shifts as pages load.
 * Returns null when the cell has no bar (blank or non-numeric value, no scale, or an all-zero axis).
 * @param {unknown} value raw cell value
 * @param {{ max: number, min: number }|null} scale
 * @returns {{ left: number, width: number, zero: number, isNegative: boolean }|null} percentages of the axis
 */
export function dataBarGeometry(value, scale) {
    if (!scale || value === null || value === undefined || value === '') {
        return null;
    }
    const numeric = Number(value);
    const negativeSpan = Math.max(0, -Number(scale.min));
    const span = Math.max(0, Number(scale.max)) + negativeSpan;
    if (!Number.isFinite(numeric) || !Number.isFinite(span) || span <= 0) {
        return null;
    }
    const zero = percent(negativeSpan, span);
    if (numeric < 0) {
        const width = percent(-numeric, span);
        return { left: Math.max(0, zero - width), width, zero, isNegative: true };
    }
    return { left: zero, width: Math.min(percent(numeric, span), 100 - zero), zero, isNegative: false };
}

function barView(column, raw, text) {
    const geometry = dataBarGeometry(raw, column.barScale);
    if (!geometry) {
        return { isDataBar: Boolean(column.barScale), hasBar: false, barText: text, showBarValue: !column.barOnly };
    }
    return {
        isDataBar: true,
        barText: text,
        showBarValue: !column.barOnly,
        hasBar: true,
        barFillClass: `c-data-bar-fill ${geometry.isNegative ? 'c-data-bar-fill_negative' : 'c-data-bar-fill_positive'}`,
        barFillStyle: `left: ${geometry.left}%; width: ${geometry.width}%;`,
        barZeroStyle: `left: ${geometry.zero}%;`,
        hasNegativeAxis: geometry.zero > 0
    };
}

/**
 * Data bar of a Group row's summary cell (Detail rows off): the column's first summary on the server's group scale.
 * `{ isDataBar: false }` unless the column is a Data bar.
 * @param {object} column column view from `buildColumnViews`
 * @param {{ summaryFunction: string, value: number }[]} summaries the group's Stacked summaries of the column
 */
export function summaryBarView(column, summaries) {
    if (column.displayAs !== DATA_BAR || !summaries?.length) {
        return { isDataBar: false };
    }
    const raw = summaries[0].value;
    return barView(column, raw, formatCell(raw, column));
}

function escapeRegExp(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Case-insensitive pattern matching active search terms (each full term plus its words of 2+ characters,
 * longest first), or null when there is nothing to highlight.
 * @param {string[]} terms
 */
export function buildHighlightPattern(terms) {
    const parts = new Set();
    (terms || []).forEach((term) => {
        const trimmed = String(term || '').trim();
        if (trimmed) {
            parts.add(trimmed.toLowerCase());
            trimmed
                .split(/\s+/)
                .filter((word) => word.length > 1)
                .forEach((word) => parts.add(word.toLowerCase()));
        }
    });
    if (!parts.size) {
        return null;
    }
    const alternatives = [...parts].sort((a, b) => b.length - a.length).map(escapeRegExp);
    return new RegExp(`(${alternatives.join('|')})`, 'i');
}

/** `<mark>` segments of `text` (`{ key, text, isMatch }`), or null when nothing matches. */
function highlightSegments(text, pattern, keyPrefix) {
    if (!pattern || !text) {
        return null;
    }
    const splitter = new RegExp(pattern.source, 'gi');
    const pieces = text.split(splitter);
    if (pieces.length < 2) {
        return null;
    }
    // `split` with a capture group puts matches at odd indexes.
    return pieces
        .map((piece, index) => ({ key: `${keyPrefix}-${index}`, text: piece, isMatch: index % 2 === 1 }))
        .filter((segment) => segment.text !== '');
}

/**
 * One rendered `<td>`: formatted text plus the record link target (`row.values[linkPath]`) when the column links.
 * Text and link cells matching `highlight` also carry `segments` for `<mark>` rendering.
 * @param {object} column column view from `buildColumnViews`
 * @param {{ id: string, values: object }} row `BoardQueryService.TableRow`
 * @param {RegExp|null} [highlight] pattern from `buildHighlightPattern`
 */
export function buildCellView(column, row, highlight = null) {
    const values = row.values || {};
    const raw = values[column.fieldPath];
    const text = formatCell(raw, column);
    const linkValue = column.linkPath && text ? values[column.linkPath] : null;
    const recordId = RECORD_ID_PATTERN.test(String(linkValue ?? '')) ? String(linkValue) : null;
    const isBoolean = column.displayAs === 'boolean';
    const isBadge = column.displayAs === 'badge' && Boolean(text) && !recordId;
    const key = `${row.id}-${column.id}`;
    const bar = column.displayAs === DATA_BAR ? barView(column, raw, text) : { isDataBar: false };
    const segments = column.displayAs === 'text' ? highlightSegments(text, highlight, key) : null;
    return {
        key,
        text,
        title: text,
        recordId,
        href: recordId ? `/${recordId}` : null,
        isLink: Boolean(recordId),
        isBadge,
        isBoolean,
        isChecked: isBoolean && (raw === true || raw === 'true'),
        isPlain: !recordId && !isBadge && !isBoolean && !bar.isDataBar,
        ...bar,
        hasHighlight: Boolean(segments),
        segments,
        cellClass: column.cellClass,
        contentClass: column.wrapText ? 'slds-cell-wrap' : 'slds-truncate'
    };
}