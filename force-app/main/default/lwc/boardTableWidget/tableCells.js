import { formatValue, formatTemporal } from 'c/boardConfigUtils';

const NUMERIC_TYPES = new Set(['INTEGER', 'LONG', 'DOUBLE']);
const AUTO_DISPLAY = {
    CURRENCY: 'currency',
    PERCENT: 'percent',
    DATE: 'date',
    DATETIME: 'datetime',
    BOOLEAN: 'boolean',
    PICKLIST: 'badge'
};
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
 * @param {object[]} serverColumns `{ id, fieldPath, label, dataType, isSortable, linkPath }`
 * @param {object[]} configColumns `TableColumnConfig[]`
 * @param {{ sortBy: string, sortDirection: string }} sort effective server sort
 */
export function buildColumnViews(serverColumns, configColumns, sort) {
    const configById = new Map((configColumns || []).map((column) => [column?.id || column?.fieldPath, column]));
    return (serverColumns || []).map((serverColumn, index) => {
        const config = configById.get(serverColumn.id) || {};
        const displayAs = resolveDisplayAs(config.displayAs, serverColumn.dataType);
        const align = resolveAlign(config.align, displayAs);
        const isSorted = Boolean(sort?.sortBy) && sort.sortBy === serverColumn.fieldPath;
        const isSortable = serverColumn.isSortable === true;
        const classes = ['c-board-table-col', `c-board-table-col_${align}`];
        if (index === 0) {
            classes.push('c-board-table-col_first');
        }
        // The first column hosts the child expander + count badge and is sticky, so it never narrow-hides.
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
            format: config.format || null,
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

function formatCell(value, column) {
    if (value === null || value === undefined || value === '') {
        return '';
    }
    switch (column.displayAs) {
        case 'number':
        case 'currency':
        case 'percent': {
            const numeric = Number(value);
            if (!Number.isFinite(numeric)) {
                return String(value);
            }
            const formatStyle = column.displayAs === 'number' ? column.format?.formatStyle : column.displayAs;
            return formatValue(
                numeric,
                { ...(column.format || {}), formatStyle: formatStyle || 'number' },
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
        isPlain: !recordId && !isBadge && !isBoolean,
        hasHighlight: Boolean(segments),
        segments,
        cellClass: column.cellClass,
        contentClass: column.wrapText ? 'slds-cell-wrap' : 'slds-truncate'
    };
}