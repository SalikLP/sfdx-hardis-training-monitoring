import LOCALE from '@salesforce/i18n/locale';

/**
 * Pure Bar Chart data shaping shared by the single-call and cursor tiers: merges grouped cursor partials, applies
 * `sortBy`, `maxBars` + `overflowMode`, and `maxSeries` overflow, and builds the Chart.js config.
 */

export const BLANK_LABEL = '(Blank)';
export const OTHER_LABEL = 'Other';
const BLANK_KEY = '__blank__';
const OTHER_KEY = '__other__';
const SINGLE_SERIES_KEY = '__value__';
const ROLLUP_FUNCTIONS = new Set(['COUNT', 'SUM']);
const SORT_OPTIONS = new Set([
    'VALUE_DESC',
    'VALUE_ASC',
    'LABEL_ASC',
    'LABEL_DESC',
    'PICKLIST_ORDER',
    'CHRONOLOGICAL_ASC',
    'CHRONOLOGICAL_DESC'
]);
const PALETTE_SIZE = 6;

function clampInteger(value, min, max, fallback) {
    const numeric = Number(value);
    if (value === null || value === undefined || value === '' || !Number.isFinite(numeric)) {
        return fallback;
    }
    return Math.min(max, Math.max(min, Math.round(numeric)));
}

function toNumber(value) {
    if (value === null || value === undefined || value === '') {
        return null;
    }
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : null;
}

/**
 * Display settings with defaults applied (`maxBars` 3..50 default 10, `maxSeries` 2..6 default 6). `maxSeries` is at
 * least 2 so a rolled-up "Other" series never replaces every named series.
 */
export function normalizeBarSettings(config = {}, groupBy = null) {
    const defaultSort = groupBy && groupBy.dateGranularity ? 'CHRONOLOGICAL_ASC' : 'VALUE_DESC';
    const sortBy = String(config.sortBy || '').toUpperCase();
    return {
        orientation: config.orientation === 'horizontal' ? 'horizontal' : 'vertical',
        sortBy: SORT_OPTIONS.has(sortBy) ? sortBy : defaultSort,
        maxBars: clampInteger(config.maxBars, 3, 50, 10),
        overflowMode: String(config.overflowMode || '').toUpperCase() === 'OTHER' ? 'OTHER' : 'TRUNCATE',
        maxSeries: clampInteger(config.maxSeries, 2, PALETTE_SIZE, PALETTE_SIZE),
        stackMode: config.stackMode === 'grouped' ? 'grouped' : 'stacked',
        includeNullBucket: config.includeNullBucket !== false,
        legendPosition: ['top', 'bottom', 'hidden'].includes(config.legendPosition) ? config.legendPosition : 'auto',
        showDataLabels: config.showDataLabels === true
    };
}

/** Adds one cursor chunk's grouped `{ sum, count, min, max }` partials to `totals` (keyed by group/stack values). */
export function mergeChunkBuckets(totals, buckets) {
    (buckets || []).forEach((bucket) => {
        const values = bucket.groupValues || [];
        const key = JSON.stringify(values);
        let entry = totals.get(key);
        if (!entry) {
            entry = { values, labels: bucket.groupLabels || [], sum: 0, count: 0, min: null, max: null };
            totals.set(key, entry);
        }
        entry.sum += Number(bucket.sum || 0);
        entry.count += Number(bucket.count || 0);
        const min = toNumber(bucket.min);
        const max = toNumber(bucket.max);
        if (min !== null) {
            entry.min = entry.min === null ? min : Math.min(entry.min, min);
        }
        if (max !== null) {
            entry.max = entry.max === null ? max : Math.max(entry.max, max);
        }
    });
    return totals;
}

/** Converts merged cursor totals into `BarBucket`-shaped `{ groupValue, groupLabel, stackValue, stackLabel, value }`. */
export function cursorTotalsToBuckets(totals, aggregateFunction) {
    return Array.from(totals.values()).map((entry) => {
        let value = null;
        if (entry.count > 0) {
            switch (aggregateFunction) {
                case 'AVG':
                    value = entry.sum / entry.count;
                    break;
                case 'MIN':
                    value = entry.min;
                    break;
                case 'MAX':
                    value = entry.max;
                    break;
                default:
                    value = entry.sum;
            }
        }
        return {
            groupValue: entry.values[0] ?? null,
            groupLabel: entry.labels[0] ?? null,
            stackValue: entry.values.length > 1 ? (entry.values[1] ?? null) : null,
            stackLabel: entry.labels.length > 1 ? (entry.labels[1] ?? null) : null,
            value
        };
    });
}

const labelCollator = new Intl.Collator(LOCALE, { numeric: true, sensitivity: 'base' });

function compareKeys(a, b) {
    const numericA = Number(a);
    const numericB = Number(b);
    if (a !== '' && b !== '' && Number.isFinite(numericA) && Number.isFinite(numericB)) {
        return numericA - numericB;
    }
    if (a < b) {
        return -1;
    }
    return a > b ? 1 : 0;
}

function categoryComparator(sortBy, picklistOrder) {
    const byLabel = (a, b) => labelCollator.compare(a.label, b.label);
    // The null "(Blank)" bucket sorts last for label, picklist, and chronological orders.
    const blankLast = (compare) => (a, b) => {
        if (a.isBlank !== b.isBlank) {
            return a.isBlank ? 1 : -1;
        }
        return compare(a, b);
    };
    switch (sortBy) {
        case 'VALUE_ASC':
            return (a, b) => a.total - b.total || byLabel(a, b);
        case 'LABEL_ASC':
            return blankLast(byLabel);
        case 'LABEL_DESC':
            return blankLast((a, b) => byLabel(b, a));
        case 'PICKLIST_ORDER': {
            const positions = new Map((picklistOrder || []).map((value, index) => [value, index]));
            const position = (category) => {
                return positions.has(category.value) ? positions.get(category.value) : Number.MAX_SAFE_INTEGER;
            };
            return blankLast((a, b) => position(a) - position(b) || byLabel(a, b));
        }
        case 'CHRONOLOGICAL_ASC':
            return blankLast((a, b) => compareKeys(a.value, b.value));
        case 'CHRONOLOGICAL_DESC':
            return blankLast((a, b) => compareKeys(b.value, a.value));
        default:
            return (a, b) => b.total - a.total || byLabel(a, b);
    }
}

function sumInto(target, source) {
    source.forEach((value, key) => {
        if (value !== null) {
            target.set(key, (target.get(key) || 0) + value);
        } else if (!target.has(key)) {
            target.set(key, null);
        }
    });
}

/**
 * Builds the rendered Bar Chart model from raw buckets.
 *
 * @returns {{ categories: Array<{key, value, label}>, series: Array<{key, value, label, values: Array<number|null>}>,
 *   hasSeries: boolean, isStacked: boolean, canRollUp: boolean }} `canRollUp` is true for additive aggregates
 *   (COUNT/SUM), whose values may be summed into "Other" or a Total.
 */
export function buildBarModel({ buckets, aggregateFunction, groupBy, stackBy, settings, measureLabel }) {
    const hasSeries = Boolean(stackBy);
    const categories = new Map();
    const seriesInfo = new Map();
    (buckets || []).forEach((bucket) => {
        const groupValue = bucket.groupValue ?? null;
        if (groupValue === null && !settings.includeNullBucket) {
            return;
        }
        const categoryKey = groupValue === null ? BLANK_KEY : String(groupValue);
        let category = categories.get(categoryKey);
        if (!category) {
            category = {
                key: categoryKey,
                value: groupValue,
                label: groupValue === null ? BLANK_LABEL : String(bucket.groupLabel ?? groupValue),
                isBlank: groupValue === null,
                values: new Map()
            };
            categories.set(categoryKey, category);
        }
        let seriesKey = SINGLE_SERIES_KEY;
        let seriesLabel = measureLabel;
        if (hasSeries) {
            const stackValue = bucket.stackValue ?? null;
            seriesKey = stackValue === null ? BLANK_KEY : String(stackValue);
            seriesLabel = stackValue === null ? BLANK_LABEL : String(bucket.stackLabel ?? stackValue);
        }
        const value = toNumber(bucket.value);
        category.values.set(seriesKey, value);
        const info = seriesInfo.get(seriesKey) || { key: seriesKey, value: null, label: seriesLabel, total: 0 };
        info.value = seriesKey === BLANK_KEY || seriesKey === SINGLE_SERIES_KEY ? null : seriesKey;
        info.total += value || 0;
        seriesInfo.set(seriesKey, info);
    });

    const canRollUp = ROLLUP_FUNCTIONS.has(aggregateFunction);
    let sorted = Array.from(categories.values());
    sorted.forEach((category) => {
        category.total = Array.from(category.values.values()).reduce((sum, value) => sum + (value || 0), 0);
    });
    sorted.sort(categoryComparator(settings.sortBy, groupBy && groupBy.picklistOrder));
    if (sorted.length > settings.maxBars) {
        if (settings.overflowMode === 'OTHER' && canRollUp) {
            const other = { key: OTHER_KEY, value: null, label: OTHER_LABEL, isBlank: false, values: new Map() };
            sorted.slice(settings.maxBars - 1).forEach((category) => sumInto(other.values, category.values));
            sorted = [...sorted.slice(0, settings.maxBars - 1), other];
        } else {
            sorted = sorted.slice(0, settings.maxBars);
        }
    }

    let series = Array.from(seriesInfo.values()).sort(
        (a, b) => b.total - a.total || labelCollator.compare(a.label, b.label)
    );
    if (series.length > settings.maxSeries) {
        if (canRollUp) {
            const kept = series.slice(0, settings.maxSeries - 1);
            const rolled = new Set(series.slice(settings.maxSeries - 1).map((entry) => entry.key));
            sorted.forEach((category) => {
                let total = null;
                rolled.forEach((key) => {
                    const value = category.values.get(key);
                    if (value !== null && value !== undefined) {
                        total = (total || 0) + value;
                    }
                });
                category.values.set(OTHER_KEY, total);
            });
            series = [...kept, { key: OTHER_KEY, value: null, label: OTHER_LABEL }];
        } else {
            series = series.slice(0, settings.maxSeries);
        }
    }

    return {
        categories: sorted.map((category) => ({ key: category.key, value: category.value, label: category.label })),
        series: series.map((entry) => ({
            key: entry.key,
            value: entry.value,
            label: entry.label,
            values: sorted.map((category) => {
                const value = category.values.get(entry.key);
                return value === undefined ? null : value;
            })
        })),
        hasSeries,
        isStacked: hasSeries && settings.stackMode === 'stacked',
        canRollUp
    };
}

/**
 * Chart.js v4 `bar` config for a model. Datasets carry `boardKey` so in-place updates keep each series' dataset (and
 * its bar elements) alive for morph animations.
 */
export function buildBarChartConfig(model, { settings, theme, animation, formatValue, formatTick, dataLabelsPlugin }) {
    const horizontal = settings.orientation === 'horizontal';
    const legendDisplay = settings.legendPosition === 'auto' ? model.hasSeries : settings.legendPosition !== 'hidden';
    const legendPosition = settings.legendPosition === 'bottom' ? 'bottom' : 'top';
    const font = { family: theme.fontFamily, size: 12 };
    const categoryAxis = {
        stacked: model.isStacked,
        grid: { display: false },
        border: { color: theme.grid },
        ticks: { color: theme.text, font }
    };
    const valueAxis = {
        stacked: model.isStacked,
        beginAtZero: true,
        grid: { color: theme.grid },
        border: { display: false },
        ticks: { color: theme.text, font, callback: (value) => formatTick(value) }
    };
    return {
        type: 'bar',
        data: {
            labels: model.categories.map((category) => category.label),
            datasets: model.series.map((series, index) => {
                const color = theme.palette[index % theme.palette.length];
                return {
                    boardKey: series.key,
                    label: series.label,
                    data: series.values,
                    backgroundColor: color,
                    hoverBackgroundColor: color,
                    borderWidth: 0,
                    borderRadius: 2,
                    maxBarThickness: 48
                };
            })
        },
        options: {
            indexAxis: horizontal ? 'y' : 'x',
            responsive: true,
            maintainAspectRatio: false,
            animation,
            scales: horizontal ? { x: valueAxis, y: categoryAxis } : { x: categoryAxis, y: valueAxis },
            plugins: {
                colors: { enabled: false },
                legend: {
                    display: legendDisplay,
                    position: legendPosition,
                    labels: { color: theme.text, font, boxWidth: 12 }
                },
                tooltip: {
                    enabled: true,
                    backgroundColor: theme.tooltipBackground,
                    titleColor: theme.tooltipText,
                    bodyColor: theme.tooltipText,
                    bodyFont: font,
                    displayColors: model.hasSeries,
                    callbacks: {
                        title: () => '',
                        label: (context) => `${context.label} — ${context.dataset.label}: ${formatValue(context.raw)}`
                    }
                },
                boardBarDataLabels: {
                    display: settings.showDataLabels,
                    stacked: model.isStacked,
                    color: theme.dataLabel,
                    font: `11px ${theme.fontFamily}`
                }
            }
        },
        plugins: [dataLabelsPlugin]
    };
}

/** Mutates a live chart to a new config in place (labels, matching datasets, options) without recreating it. */
export function applyBarChartConfig(chart, config) {
    const existing = new Map(chart.data.datasets.map((dataset) => [dataset.boardKey, dataset]));
    chart.data.labels = config.data.labels;
    chart.data.datasets = config.data.datasets.map((next) => {
        const previous = existing.get(next.boardKey);
        return previous ? Object.assign(previous, next) : next;
    });
    chart.options = config.options;
}