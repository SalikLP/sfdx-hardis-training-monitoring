/**
 * Small multiples settings of the Chart widget: a Panel field turns the Widget into a grid of Panels, one per Panel
 * field value (shaped by the server, `BoardChartPanels`). Pure: the Widget config's Panel settings with defaults, the
 * request keys they add to the Chart query, one Panel's slice of a result, and design-time validation.
 */

export const MAX_PANEL_CATEGORIES = 50;
export const DEFAULT_MAX_PANELS = 6;
export const DEFAULT_PANELS_PER_ROW = 3;
export const DEFAULT_PANEL_HEIGHT = 250;
export const MIN_PANEL_HEIGHT = 150;
export const MAX_PANEL_HEIGHT = 600;
export const PANEL_SORTS = ['FIELD_ORDER', 'VALUE_DESC', 'VALUE_ASC'];
/** Every Widget config key of Small multiples, cleared together with the Panel field. */
export const PANEL_KEYS = [
    'panelField',
    'panelDateGranularity',
    'maxPanels',
    'panelSort',
    'panelSortMeasure',
    'panelsPerRow',
    'panelHeight',
    'independentScales',
    'panelHeadlineMeasure'
];

function clampInteger(value, min, max, fallback) {
    const numeric = Number(value);
    if (value === null || value === undefined || value === '' || !Number.isFinite(numeric)) {
        return fallback;
    }
    return Math.min(max, Math.max(min, Math.round(numeric)));
}

function cleanString(value) {
    return typeof value === 'string' ? value.trim() : '';
}

/** Whether the Widget config sets a Panel field (Small multiples). */
export function hasPanelField(config = {}) {
    return cleanString(config.panelField) !== '';
}

/**
 * The Widget config's Small multiples settings with defaults: max panels 2–12 (6), panels per row 1–6 (3), panel
 * height 150–600 px (250), Panel sort (`FIELD_ORDER` unless a Measure's total), Independent scales off, Panel headline
 * Measure index (null without one).
 */
export function normalizePanelSettings(config = {}) {
    const panelSort = String(config.panelSort || '').toUpperCase();
    return {
        panelField: cleanString(config.panelField) || null,
        panelDateGranularity: cleanString(config.panelDateGranularity) || null,
        maxPanels: clampInteger(config.maxPanels, 2, 12, DEFAULT_MAX_PANELS),
        panelSort: PANEL_SORTS.includes(panelSort) ? panelSort : 'FIELD_ORDER',
        panelSortMeasure: clampInteger(config.panelSortMeasure, 0, 5, 0),
        panelsPerRow: clampInteger(config.panelsPerRow, 1, 6, DEFAULT_PANELS_PER_ROW),
        panelHeight: clampInteger(config.panelHeight, MIN_PANEL_HEIGHT, MAX_PANEL_HEIGHT, DEFAULT_PANEL_HEIGHT),
        independentScales: config.independentScales === true,
        panelHeadlineMeasure: panelHeadlineIndex(config)
    };
}

/**
 * Index of the Measure shown as the Panel headline (a hidden Measure, one number per Panel header), or null without a
 * Panel field or headline.
 */
export function panelHeadlineIndex(config = {}) {
    const raw = config.panelHeadlineMeasure;
    if (!hasPanelField(config) || raw === null || raw === undefined || raw === '') {
        return null;
    }
    const index = Number(raw);
    return Number.isInteger(index) && index >= 0 && index <= 5 ? index : null;
}

/** Chart query request keys of the Panel field and its settings; none without a Panel field. */
export function panelRequestFields(config = {}) {
    if (!hasPanelField(config)) {
        return {};
    }
    const settings = normalizePanelSettings(config);
    return {
        panelField: settings.panelField,
        panelDateGranularity: settings.panelDateGranularity,
        maxPanels: settings.maxPanels,
        panelSort: settings.panelSort,
        panelSortMeasure: settings.panelSortMeasure,
        ...(settings.panelHeadlineMeasure === null ? {} : { panelHeadlineMeasure: settings.panelHeadlineMeasure })
    };
}

/** Whether a Chart query result is Small multiples (it carries Panels). */
export function isPanelResult(result) {
    return Boolean(result && Array.isArray(result.panels) && result.panels.length);
}

/** One Panel's total per Measure (`panelTotals` of the result), or null when the server returned none. */
export function panelTotalsOf(result, panelKey) {
    const entry = ((result && result.panelTotals) || []).find((total) => total.panelKey === panelKey);
    return entry && Array.isArray(entry.values) ? entry.values : null;
}

/**
 * One Panel's slice of a Small multiples result: the shared categories and series, only that Panel's points, and its
 * Panel totals as the overall values, so its Reference lines sit at the Panel's value.
 */
export function panelSlice(result, panelKey) {
    const totals = panelTotalsOf(result, panelKey);
    return {
        ...result,
        points: ((result && result.points) || []).filter((point) => point.panelKey === panelKey),
        ...(totals ? { overallValues: totals } : {})
    };
}

function isWholeNumberIn(value, min, max) {
    const numeric = Number(value);
    return Number.isInteger(numeric) && numeric >= min && numeric <= max;
}

/** A Bucket field reference (`bucket:<id>`) rather than a field path. */
function isBucketReference(value) {
    return cleanString(value).toLowerCase().startsWith('bucket:');
}

function hasValue(value) {
    return value !== null && value !== undefined && value !== '';
}

/** Design-time errors `{ key, message }` of the Small multiples settings. */
export function smallMultiplesErrors(config = {}) {
    const errors = [];
    const panelField = cleanString(config.panelField);
    if (!panelField) {
        return errors;
    }
    const same = (other) => cleanString(other).toLowerCase() === panelField.toLowerCase();
    if (same(config.groupByField) || same(config.stackByField)) {
        errors.push({
            key: 'panelField',
            message: 'The Panel field must differ from the Group by and Stack by fields.'
        });
    } else if (
        isBucketReference(panelField) &&
        (isBucketReference(config.groupByField) || isBucketReference(config.stackByField))
    ) {
        errors.push({
            key: 'panelField',
            message: 'A Chart widget uses one Bucket field: as its Group by, Stack by or Panel field.'
        });
    }
    if (hasValue(config.panelHeadlineMeasure)) {
        const measureCount = Array.isArray(config.measures) ? config.measures.length : 0;
        if (!isWholeNumberIn(config.panelHeadlineMeasure, 0, Math.min(5, measureCount - 1))) {
            errors.push({
                key: 'panelHeadlineMeasure',
                message: 'The Panel headline must be one of the Measures.'
            });
        }
    }
    if (hasValue(config.maxPanels) && !isWholeNumberIn(config.maxPanels, 2, 12)) {
        errors.push({ key: 'maxPanels', message: 'Maximum panels must be a whole number from 2 to 12.' });
    }
    if (hasValue(config.panelsPerRow) && !isWholeNumberIn(config.panelsPerRow, 1, 6)) {
        errors.push({ key: 'panelsPerRow', message: 'Panels per row must be a whole number from 1 to 6.' });
    }
    if (hasValue(config.panelHeight) && !isWholeNumberIn(config.panelHeight, MIN_PANEL_HEIGHT, MAX_PANEL_HEIGHT)) {
        errors.push({
            key: 'panelHeight',
            message: `Panel height must be a whole number of pixels from ${MIN_PANEL_HEIGHT} to ${MAX_PANEL_HEIGHT}.`
        });
    }
    return errors;
}