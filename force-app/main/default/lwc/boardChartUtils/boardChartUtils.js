import { loadScript } from 'lightning/platformResourceLoader';
import CHARTJS from '@salesforce/resourceUrl/chartjs';
import { resolveColours } from 'c/boardChartColours';

/**
 * Shared Chart.js v4 engine for Board chart Widgets: singleton static resource loader, SLDS 1/2 theme sampler,
 * media query listeners, the SLDS Color-Safe categorical palette, and an inline bar data-label plugin.
 */

export const PREFERS_DARK_QUERY = '(prefers-color-scheme: dark)';
export const PREFERS_REDUCED_MOTION_QUERY = '(prefers-reduced-motion: reduce)';

/**
 * 12-color categorical palette, constant in light and dark mode (each ≥3:1 on a white and a #181818 surface). The
 * first 6 are the SLDS 2 mid-scale palette hooks `blue/teal/orange/pink/indigo/hot-orange-50` and match the
 * `--board-chart-palette-1..6` CSS fallbacks; 7..12 can be overridden with `--board-chart-palette-7..12`.
 */
export const SLDS_COLOR_SAFE_PALETTE = [
    '#0176d3',
    '#0b827c',
    '#a96404',
    '#e3066a',
    '#5867e8',
    '#d83a00',
    '#2e844a',
    '#9050e9',
    '#8a6d00',
    '#b0409a',
    '#2f8fa0',
    '#c23934'
];
/** Neutral greys for the "Other" roll-up and the "(Blank)" value; never taken from the palette. */
export const OTHER_COLOR = '#747474';
export const BLANK_COLOR = '#9a9a9a';

/**
 * Colour for each item (series or category) in order: "Other" and "(Blank)" items get their grey, every other item
 * takes the next palette colour (wrapping), so the greys never use up a palette colour.
 */
export function assignColors(items, theme) {
    let next = 0;
    return items.map((item) => {
        if (item.isOther) {
            return theme.otherColor || OTHER_COLOR;
        }
        if (item.isBlank) {
            return theme.blankColor || BLANK_COLOR;
        }
        const color = theme.palette[next % theme.palette.length];
        next += 1;
        return color;
    });
}

/**
 * Colour of each series of a model: series field values honour their fixed colours (the palette skips colours they
 * take, see `c/boardChartColours`); Measures take palette colours by position, a Measure's own colour applied on top.
 */
function seriesItemColors(model, theme) {
    return model.hasSeries ? resolveColours(model.series, theme) : assignColors(model.series, theme);
}

const THEME_DEFAULTS = {
    text: '#5c5c5c',
    grid: '#e5e5e5',
    dataLabel: '#2e2e2e',
    tooltipBackground: '#032d60',
    tooltipText: '#ffffff',
    fontFamily: "-apple-system, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"
};
const THEME_PROPERTIES = {
    text: '--board-chart-text',
    grid: '--board-chart-grid',
    dataLabel: '--board-chart-data-label',
    tooltipBackground: '--board-chart-tooltip-background',
    tooltipText: '--board-chart-tooltip-text',
    fontFamily: '--board-chart-font-family'
};

let chartJsPromise = null;

/**
 * Loads the `chartjs` static resource (`chart.umd.min.js`) once per page and resolves to the `Chart` constructor.
 * A failed load is not cached, so a later call retries.
 */
export function loadChartJs(component) {
    if (!chartJsPromise) {
        chartJsPromise = loadScript(component, CHARTJS)
            .then(() => {
                if (typeof window.Chart !== 'function') {
                    throw new Error('Chart.js did not initialize.');
                }
                return window.Chart;
            })
            .catch((error) => {
                chartJsPromise = null;
                throw error;
            });
    }
    return chartJsPromise;
}

/**
 * Samples the `--board-chart-*` custom properties (backed by `--slds-g-*` styling hooks) declared on `element`, since
 * `<canvas>` drawing cannot resolve CSS `var()` references. SLDS 2 hooks may hold `light-dark(<light>, <dark>)`, which
 * canvas also cannot parse (it paints black), so each value is reduced to the branch for the element's color scheme.
 */
export function resolveChartTheme(element) {
    let style = null;
    try {
        style = element ? window.getComputedStyle(element) : null;
    } catch (e) {
        style = null;
    }
    const dark = usesDarkColorScheme(style);
    const read = (property, fallback) => {
        const value = style ? style.getPropertyValue(property) : '';
        return value && value.trim() ? resolveLightDark(value.trim(), dark) : fallback;
    };
    const theme = {};
    Object.keys(THEME_PROPERTIES).forEach((key) => {
        theme[key] = read(THEME_PROPERTIES[key], THEME_DEFAULTS[key]);
    });
    theme.palette = SLDS_COLOR_SAFE_PALETTE.map((color, index) => read(`--board-chart-palette-${index + 1}`, color));
    theme.otherColor = read('--board-chart-other', OTHER_COLOR);
    theme.blankColor = read('--board-chart-blank', BLANK_COLOR);
    return theme;
}

/** `light-dark()` follows the used color scheme: `dark` alone, or `light dark` while the OS prefers dark. */
function usesDarkColorScheme(style) {
    const scheme = style ? String(style.getPropertyValue('color-scheme') || '') : '';
    if (!/\bdark\b/.test(scheme)) {
        return false;
    }
    return !/\blight\b/.test(scheme) || matchesMediaQuery(PREFERS_DARK_QUERY);
}

/** Replaces every (possibly nested) `light-dark(a, b)` in `value` with `a` or `b`. */
function resolveLightDark(value, dark) {
    const marker = /light-dark\(/i;
    let result = value;
    let match = marker.exec(result);
    while (match) {
        const open = match.index + match[0].length;
        let depth = 0;
        let comma = -1;
        let close = -1;
        for (let i = open; i < result.length && close < 0; i++) {
            const char = result[i];
            if (char === '(') {
                depth++;
            } else if (char === ')') {
                if (depth === 0) {
                    close = i;
                }
                depth--;
            } else if (char === ',' && depth === 0 && comma < 0) {
                comma = i;
            }
        }
        if (close < 0 || comma < 0) {
            return result;
        }
        const branch = dark ? result.slice(comma + 1, close) : result.slice(open, comma);
        result = result.slice(0, match.index) + branch.trim() + result.slice(close + 1);
        match = marker.exec(result);
    }
    return result;
}

export function matchesMediaQuery(query) {
    try {
        return Boolean(window.matchMedia && window.matchMedia(query).matches);
    } catch (e) {
        return false;
    }
}

/** Calls `callback(matches)` whenever `query` changes; returns an unsubscribe function. */
export function watchMediaQuery(query, callback) {
    if (typeof window === 'undefined' || !window.matchMedia) {
        return () => {};
    }
    const mediaQueryList = window.matchMedia(query);
    if (!mediaQueryList) {
        return () => {};
    }
    const handler = (event) => callback(Boolean(event && event.matches));
    if (mediaQueryList.addEventListener) {
        mediaQueryList.addEventListener('change', handler);
        return () => mediaQueryList.removeEventListener('change', handler);
    }
    if (mediaQueryList.addListener) {
        mediaQueryList.addListener(handler);
        return () => mediaQueryList.removeListener(handler);
    }
    return () => {};
}

/**
 * Calls `callback()` when the page color scheme may have changed: the OS `prefers-color-scheme` media query, or a
 * `class`/`style`/`data-*` theme attribute change on `<html>`/`<body>` (in-app theme switches without a reload).
 * Callers compare the re-sampled theme before repainting. Returns an unsubscribe function.
 */
export function watchColorScheme(callback) {
    const unsubscribeMedia = watchMediaQuery(PREFERS_DARK_QUERY, () => callback());
    let observer = null;
    try {
        if (typeof MutationObserver === 'function') {
            observer = new MutationObserver(() => callback());
            [document.documentElement, document.body].filter(Boolean).forEach((target) => {
                observer.observe(target, {
                    attributes: true,
                    attributeFilter: ['class', 'style', 'data-theme', 'data-color-scheme']
                });
            });
        }
    } catch (e) {
        // Locker may deny observing page-level nodes; the media query listener still applies.
        observer = null;
    }
    return () => {
        unsubscribeMedia();
        if (observer) {
            observer.disconnect();
        }
    };
}

/** In-place update animation: `300ms easeOutQuart`, or `0ms` when `prefers-reduced-motion: reduce` matches. */
export function chartAnimation(reducedMotion) {
    return { duration: reducedMotion ? 0 : 300, easing: 'easeOutQuart' };
}

/** A bar's data label is skipped when the bar is outside the plot (scrolled away) or too thin to hold it. */
function labelFitsOnBar(chart, element, horizontal) {
    const area = chart.chartArea;
    if (area && (element.x < area.left || element.x > area.right || element.y < area.top || element.y > area.bottom)) {
        return false;
    }
    const thickness = horizontal ? element.height : element.width;
    return thickness === undefined || dataLabelFits(thickness);
}

/**
 * Inline Chart.js plugin drawing formatted values at the end of each bar (or each stack total when
 * `options.stacked`). Enabled via `options.plugins.boardBarDataLabels.display`; `formatValue(value, measureIndex)`
 * stays in the closure because Chart.js resolves plugin option functions as scriptable values. Each label uses the
 * format of its dataset's Measure (`boardMeasureIndex`); a stack total uses the stack's.
 */
export function createBarDataLabelsPlugin(formatValue) {
    return {
        id: 'boardBarDataLabels',
        afterDatasetsDraw(chart, args, options) {
            if (!options || !options.display) {
                return;
            }
            const horizontal = chart.options.indexAxis === 'y';
            const valueScale = horizontal ? chart.scales.x : chart.scales.y;
            const visible = chart.data.datasets.map((dataset, index) => index).filter((i) => chart.isDatasetVisible(i));
            if (!visible.length || !valueScale) {
                return;
            }
            const labels = [];
            const measureOf = (datasetIndex) => chart.data.datasets[datasetIndex].boardMeasureIndex || 0;
            if (options.stacked) {
                const referenceMeta = chart.getDatasetMeta(visible[visible.length - 1]);
                const measureIndex = measureOf(visible[visible.length - 1]);
                referenceMeta.data.forEach((element, index) => {
                    if (!labelFitsOnBar(chart, element, horizontal)) {
                        return;
                    }
                    const total = visible.reduce(
                        (sum, datasetIndex) => sum + (Number(chart.data.datasets[datasetIndex].data[index]) || 0),
                        0
                    );
                    const position = valueScale.getPixelForValue(total);
                    labels.push({
                        value: total,
                        measureIndex,
                        x: horizontal ? position : element.x,
                        y: horizontal ? element.y : position
                    });
                });
            } else {
                visible.forEach((datasetIndex) => {
                    chart.getDatasetMeta(datasetIndex).data.forEach((element, index) => {
                        if (!labelFitsOnBar(chart, element, horizontal)) {
                            return;
                        }
                        const raw = chart.data.datasets[datasetIndex].data[index];
                        // A floating waterfall step is `[start, end]`; its label is the step size
                        const value = Array.isArray(raw) ? raw[1] - raw[0] : raw;
                        if (value !== null && value !== undefined) {
                            labels.push({ value, measureIndex: measureOf(datasetIndex), x: element.x, y: element.y });
                        }
                    });
                });
            }
            const { ctx } = chart;
            ctx.save();
            ctx.fillStyle = options.color;
            ctx.font = options.font;
            ctx.textAlign = horizontal ? 'left' : 'center';
            ctx.textBaseline = horizontal ? 'middle' : 'bottom';
            labels.forEach((label) => {
                ctx.fillText(
                    formatValue(label.value, label.measureIndex),
                    horizontal ? label.x + 4 : label.x,
                    horizontal ? label.y : label.y - 4
                );
            });
            ctx.restore();
        }
    };
}

export const BAR_THICKNESS_PX = 20;
export const BAR_GAP_PX = 8;
const MIN_DATA_LABEL_THICKNESS_PX = 14;
const MAX_LABEL_CHARS = 18;

/**
 * Scroll sizing for a bar chart: every category slot is a fixed `BAR_THICKNESS_PX` per bar (grouped bars side by
 * side, stacked bars as one) plus a gap. `viewportPx` is the plot's extent along the category axis (0 = unknown,
 * never scrolls). `contentPx` is what the scroll container must span.
 */
export function computeScrollLayout({ categoryCount, seriesCount, stacked, viewportPx }) {
    const bars = stacked ? 1 : Math.max(1, seriesCount || 1);
    const slotPx = bars * BAR_THICKNESS_PX + BAR_GAP_PX;
    const contentPx = categoryCount * slotPx;
    return {
        scrolls: viewportPx > 0 && contentPx > viewportPx,
        slotPx,
        contentPx,
        viewportPx,
        categoryCount
    };
}

/** The first/last category index (inclusive) shown for a scroll offset along the category axis. */
export function visibleCategoryWindow(layout, scrollOffset) {
    const visible = Math.min(layout.categoryCount, Math.ceil(layout.viewportPx / layout.slotPx));
    const first = Math.max(
        0,
        Math.min(layout.categoryCount - visible, Math.floor(Math.max(0, scrollOffset) / layout.slotPx))
    );
    return { min: first, max: first + visible - 1 };
}

/** Category tick label shortened with an ellipsis; the tooltip keeps the full label. */
export function truncateLabel(label) {
    const text = label === null || label === undefined ? '' : String(label);
    return text.length > MAX_LABEL_CHARS ? `${text.slice(0, MAX_LABEL_CHARS - 1)}…` : text;
}

/** False when a bar is too thin (px across the category axis) to hold its data label. */
export function dataLabelFits(thicknessPx) {
    return thicknessPx >= MIN_DATA_LABEL_THICKNESS_PX;
}

/**
 * Chart types of the Chart widget, in picker order. Each descriptor says which type-specific Widget config settings
 * apply (the Config editor shows only these; the others are kept for a switch back), the max categories the Admin
 * may ask for, whether the plot scrolls along the category axis (fixed-thickness bars) or compresses and skips labels
 * (lines), and the pure Chart.js config builder. A new chart type is one more entry here.
 */
const CHART_TYPES = [
    {
        value: 'bar',
        label: 'Bar',
        settings: ['orientation', 'stackMode', 'colorByCategory', 'comboMeasures'],
        maxCategories: 200,
        scrolls: true,
        build: buildBarConfig
    },
    {
        value: 'line',
        label: 'Line',
        settings: ['showPoints', 'comboMeasures'],
        maxCategories: 200,
        scrolls: false,
        build: (model, options) => buildLineConfig(model, options, false)
    },
    {
        value: 'area',
        label: 'Area',
        settings: ['showPoints'],
        maxCategories: 200,
        scrolls: false,
        build: (model, options) => buildLineConfig(model, options, true)
    },
    {
        value: 'pie',
        label: 'Pie',
        settings: ['labelMode'],
        maxCategories: 12,
        scrolls: false,
        singleMeasure: true,
        build: (model, options) => buildSliceConfig(model, options, 'pie')
    },
    {
        value: 'donut',
        label: 'Donut',
        settings: ['labelMode', 'centreTotal'],
        maxCategories: 12,
        scrolls: false,
        singleMeasure: true,
        build: (model, options) => buildSliceConfig(model, options, 'doughnut')
    },
    {
        value: 'polarArea',
        label: 'Polar area',
        settings: ['labelMode'],
        maxCategories: 12,
        scrolls: false,
        singleMeasure: true,
        build: (model, options) => buildSliceConfig(model, options, 'polarArea')
    },
    {
        value: 'radar',
        label: 'Radar',
        settings: ['showPoints'],
        maxCategories: 12,
        scrolls: false,
        build: buildRadarConfig
    },
    {
        value: 'waterfall',
        label: 'Waterfall',
        settings: ['showTotal', 'waterfallColors'],
        maxCategories: 50,
        scrolls: false,
        singleMeasure: true,
        build: buildWaterfallConfig
    }
];

/** `{ label, value }` options of the chart type picker. */
export const CHART_TYPE_OPTIONS = CHART_TYPES.map(({ label, value }) => ({ label, value }));

/** The chart type's descriptor; an unknown or missing type is `bar`. */
function chartTypeDescriptor(chartType) {
    return CHART_TYPES.find((type) => type.value === chartType) || CHART_TYPES[0];
}

/** Whether `chartType` is one the Chart widget can draw. */
export function isChartType(chartType) {
    return CHART_TYPES.some((type) => type.value === chartType);
}

/** Whether a type-specific setting (e.g. `orientation`, `showPoints`) applies to `chartType` (missing means bar). */
export function chartTypeHasSetting(chartType, setting) {
    return chartTypeDescriptor(chartType).settings.includes(setting);
}

/** The largest max categories `chartType` accepts (the smallest is always 3). */
export function maxCategoriesFor(chartType) {
    return chartTypeDescriptor(chartType).maxCategories;
}

/** Whether `chartType` scrolls along the category axis when its categories don't fit (bars), instead of compressing. */
export function chartTypeScrolls(chartType) {
    return chartTypeDescriptor(chartType).scrolls;
}

/** Whether `chartType` draws exactly one Measure and no series field (pie, donut, polarArea). */
export function chartTypeIsSingleMeasure(chartType) {
    return chartTypeDescriptor(chartType).singleMeasure === true;
}

/**
 * A Measure's `render` (bar | line | referenceLine) and value `axis` (primary | secondary) in a chart type that draws combo charts
 * (bar, line). Unset, a Measure is drawn as the chart type draws it, on the primary axis. Other chart types ignore
 * both (the config keeps them for a switch back): `render` is null and `axis` primary.
 */
export function normalizeMeasureDisplay(measure, chartType) {
    if (!chartTypeHasSetting(chartType, 'comboMeasures')) {
        return { render: null, axis: 'primary' };
    }
    const fallback = chartType === 'line' ? 'line' : 'bar';
    return {
        render: ['bar', 'line', 'referenceLine'].includes(measure.render) ? measure.render : fallback,
        axis: measure.axis === 'secondary' ? 'secondary' : 'primary'
    };
}

/** `{ label, value }` options of a Measure's `render` and `axis` in the Config editor. */
export const MEASURE_RENDER_OPTIONS = [
    { label: 'Bars', value: 'bar' },
    { label: 'Line', value: 'line' },
    { label: 'Reference line', value: 'referenceLine' }
];
export const MEASURE_AXIS_OPTIONS = [
    { label: 'Primary', value: 'primary' },
    { label: 'Secondary (opposite side)', value: 'secondary' }
];

/**
 * Chart.js v4 config for a chart model, dispatched on the Widget config's `chartType`. Pure: no canvas, so it is
 * unit tested directly.
 */
export function buildChartConfig(chartType, model, options) {
    const descriptor = CHART_TYPES.find((type) => type.value === chartType);
    if (!descriptor) {
        throw new Error(`Unsupported chart type: ${chartType}`);
    }
    return descriptor.build(model, options);
}

/** Legend shown on `auto` only for several series; `bottom` or else `top`. */
function legendOptions(settings, multiSeries, theme, font) {
    return {
        display: settings.legendPosition === 'auto' ? multiSeries : settings.legendPosition !== 'hidden',
        position: settings.legendPosition === 'bottom' ? 'bottom' : 'top',
        labels: { color: theme.text, font, boxWidth: 12 }
    };
}

/** Tooltip shared by every chart type: `Category — Series: formatted value` in that series' Measure format. */
function tooltipOptions(theme, font, multiSeries, formatValue) {
    return {
        enabled: true,
        backgroundColor: theme.tooltipBackground,
        titleColor: theme.tooltipText,
        bodyColor: theme.tooltipText,
        bodyFont: font,
        displayColors: multiSeries,
        callbacks: {
            title: () => '',
            label: (context) =>
                `${context.label} — ${context.dataset.label}: ${formatValue(
                    context.raw,
                    context.dataset.boardMeasureIndex || 0
                )}`
        }
    };
}

/** `#rrggbb` at `alpha` opacity (`#rrggbbaa`); any other colour syntax is returned unchanged. */
function withAlpha(color, alpha) {
    return /^#[0-9a-f]{6}$/i.test(color)
        ? `${color}${Math.round(alpha * 255)
              .toString(16)
              .padStart(2, '0')}`
        : color;
}

/*
 * Combo charts: in bar and line charts each Measure's series carries `render` (bar | line) and `axis` (primary |
 * secondary). A series drawn the other way gets its own dataset `type`, and a secondary series is bound to a second
 * value axis opposite the primary one (right of vertical charts, above horizontal bars).
 */
const SECONDARY_AXIS_SUFFIX = '1';

/** Dataset property binding a series to its value axis: `y` (`x` for horizontal bars), or the secondary `y1`/`x1`. */
function valueAxisBinding(series, horizontal) {
    const primary = horizontal ? 'x' : 'y';
    const id = series.axis === 'secondary' ? `${primary}${SECONDARY_AXIS_SUFFIX}` : primary;
    return { [horizontal ? 'xAxisID' : 'yAxisID']: id };
}

/** The Measure whose format an axis' ticks use: the first one drawn on it (`primary` or `secondary`), else -1. */
function firstMeasureOnAxis(model, axis) {
    const series = model.series.find((entry) => (entry.axis === 'secondary' ? 'secondary' : 'primary') === axis);
    return series ? series.measureIndex || 0 : -1;
}

/** Primary value axis tick formatter: the format of its first Measure (the first Measure when none is on it). */
function primaryTickFormatter(model, formatTick) {
    const measureIndex = Math.max(0, firstMeasureOnAxis(model, 'primary'));
    return (value) => formatTick(value, measureIndex);
}

/**
 * Value scales keyed by axis id: the primary axis, plus the secondary axis only when a Measure uses it. The
 * secondary axis sits opposite the primary, draws no grid lines across the plot, and its ticks use the format of the
 * first Measure on it.
 */
function valueScales(model, primaryAxis, horizontal, formatTick) {
    const primaryId = horizontal ? 'x' : 'y';
    const scales = { [primaryId]: primaryAxis };
    const measureIndex = firstMeasureOnAxis(model, 'secondary');
    if (measureIndex >= 0) {
        scales[`${primaryId}${SECONDARY_AXIS_SUFFIX}`] = {
            ...primaryAxis,
            position: horizontal ? 'top' : 'right',
            grid: { ...primaryAxis.grid, drawOnChartArea: false },
            ticks: { ...primaryAxis.ticks, callback: (value) => formatTick(value, measureIndex) }
        };
    }
    return scales;
}

/** Dataset style of a series drawn as a line: straight segments, no fill, points of `pointRadius`. */
function lineDatasetStyle(color, pointRadius) {
    return {
        borderColor: color,
        backgroundColor: color,
        pointBackgroundColor: color,
        borderWidth: 2,
        fill: false,
        tension: 0,
        pointRadius,
        pointHoverRadius: pointRadius + 2,
        pointHitRadius: 6
    };
}

/** Dataset style of a series drawn as bars. */
function barDatasetStyle(color) {
    return { backgroundColor: color, hoverBackgroundColor: color, borderWidth: 0, borderRadius: 2 };
}

/**
 * Chart.js v4 `line` config for a line or area chart: one line per series value or per Measure, straight segments (no
 * smoothing), points shown unless `showPoints` is off. An area chart fills each line to the axis, and stacks the
 * areas when a series field splits its one Measure. The category axis never scrolls: it compresses and skips labels.
 */
function buildLineConfig(model, { settings, theme, animation, formatValue, formatTick, dataLabelsPlugin }, area) {
    const multiSeries = model.hasSeries || model.series.length > 1;
    const stacked = area && model.hasSeries;
    const font = { family: theme.fontFamily, size: 12 };
    const seriesColors = seriesItemColors(model, theme);
    const pointRadius = settings.showPoints === false ? 0 : 3;
    const fillFor = (index) => {
        if (!area) {
            return false;
        }
        return stacked && index > 0 ? '-1' : 'origin';
    };
    return {
        type: 'line',
        data: {
            labels: model.categories.map((category) => category.label),
            datasets: model.series.map((series, index) => {
                const color = series.color || seriesColors[index];
                const identity = {
                    boardKey: series.key,
                    boardMeasureIndex: series.measureIndex || 0,
                    label: series.label,
                    data: series.values,
                    ...valueAxisBinding(series, false)
                };
                if (series.render === 'bar') {
                    return { ...identity, type: 'bar', ...barDatasetStyle(color), maxBarThickness: 48 };
                }
                return {
                    ...identity,
                    ...lineDatasetStyle(color, pointRadius),
                    backgroundColor: area ? withAlpha(color, 0.5) : color,
                    fill: fillFor(index)
                };
            })
        },
        options: {
            indexAxis: 'x',
            responsive: true,
            maintainAspectRatio: false,
            animation,
            interaction: { mode: 'index', intersect: false },
            scales: {
                x: {
                    // Bars in a line chart need half a slot either side, or the first and last bars are cut off
                    offset: model.series.some((series) => series.render === 'bar'),
                    grid: { display: false },
                    border: { color: theme.grid },
                    ticks: { color: theme.text, font, autoSkip: true, autoSkipPadding: 8, maxRotation: 0 }
                },
                ...valueScales(
                    model,
                    {
                        stacked,
                        beginAtZero: true,
                        grid: { color: theme.grid },
                        border: { display: false },
                        ticks: { color: theme.text, font, callback: primaryTickFormatter(model, formatTick) }
                    },
                    false,
                    formatTick
                )
            },
            plugins: {
                colors: { enabled: false },
                legend: legendOptions(settings, multiSeries, theme, font),
                tooltip: tooltipOptions(theme, font, multiSeries, formatValue),
                boardBarDataLabels: {
                    display: settings.showDataLabels,
                    stacked,
                    color: theme.dataLabel,
                    font: `11px ${theme.fontFamily}`
                }
            }
        },
        plugins: [dataLabelsPlugin]
    };
}

/**
 * Chart.js v4 `bar` config for a model. Datasets carry `boardKey` so in-place updates keep each series' dataset (and
 * its bar elements) alive for morph animations, and `boardMeasureIndex` so tooltips and data labels format each value
 * with its Measure's format (`formatValue(value, measureIndex)`). A Measure's own `color` wins over the palette.
 */
function buildBarConfig(
    model,
    { settings, theme, animation, formatValue, formatTick, dataLabelsPlugin, scroll, scrollWindow }
) {
    const horizontal = settings.orientation === 'horizontal';
    const multiSeries = model.hasSeries || model.series.length > 1;
    const legendDisplay = settings.legendPosition === 'auto' ? multiSeries : settings.legendPosition !== 'hidden';
    const legendPosition = settings.legendPosition === 'bottom' ? 'bottom' : 'top';
    const font = { family: theme.fontFamily, size: 12 };
    const categoryAxis = {
        stacked: model.isStacked,
        grid: { display: false },
        border: { color: theme.grid },
        ticks: {
            color: theme.text,
            font,
            callback(value) {
                return truncateLabel(this.getLabelForValue(value));
            }
        }
    };
    if (scroll && scroll.scrolls && scrollWindow) {
        categoryAxis.min = scrollWindow.min;
        categoryAxis.max = scrollWindow.max;
    }
    const valueAxis = {
        stacked: model.isStacked,
        beginAtZero: true,
        grid: { color: theme.grid },
        border: { display: false },
        ticks: { color: theme.text, font, callback: primaryTickFormatter(model, formatTick) }
    };
    const seriesColors =
        settings.colorByCategory && !model.hasSeries && model.series.length === 1
            ? [resolveColours(model.categories, theme)]
            : seriesItemColors(model, theme);
    return {
        type: 'bar',
        data: {
            labels: model.categories.map((category) => category.label),
            datasets: model.series.map((series, index) => {
                const color = series.color || seriesColors[index];
                const identity = {
                    boardKey: series.key,
                    boardMeasureIndex: series.measureIndex || 0,
                    label: series.label,
                    data: series.values,
                    ...valueAxisBinding(series, horizontal)
                };
                if (series.render === 'line') {
                    return { ...identity, type: 'line', ...lineDatasetStyle(color, 3) };
                }
                return {
                    ...identity,
                    ...barDatasetStyle(color),
                    ...(scroll && scroll.scrolls ? { barThickness: BAR_THICKNESS_PX } : { maxBarThickness: 48 })
                };
            })
        },
        options: {
            indexAxis: horizontal ? 'y' : 'x',
            responsive: true,
            maintainAspectRatio: false,
            animation,
            scales: {
                [horizontal ? 'y' : 'x']: categoryAxis,
                ...valueScales(model, valueAxis, horizontal, formatTick)
            },
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
                    displayColors: multiSeries,
                    callbacks: {
                        title: () => '',
                        label: (context) =>
                            `${context.label} — ${context.dataset.label}: ${formatValue(
                                context.raw,
                                context.dataset.boardMeasureIndex || 0
                            )}`
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

const SLICE_LABEL_MODES = ['value', 'percent', 'both', 'none'];
const MIN_LABELLED_ARC_RADIANS = 0.25;

/** A pie/donut/polarArea slice label: the formatted value, its share of `total`, both, or nothing. */
export function sliceLabelText(value, total, mode, formatValue) {
    const percent = () => {
        const share = total > 0 ? Math.round((value / total) * 1000) / 10 : 0;
        return `${share}%`;
    };
    if (mode === 'value') {
        return formatValue(value);
    }
    if (mode === 'percent') {
        return percent();
    }
    if (mode === 'both') {
        return `${formatValue(value)} (${percent()})`;
    }
    return '';
}

/** The visible slices of a pie-like chart's first dataset as `{ value, element }`, and their sum. */
function visibleSlices(chart) {
    const dataset = chart.data.datasets[0];
    const meta = chart.getDatasetMeta(0);
    const slices = [];
    meta.data.forEach((element, index) => {
        const value = Number(dataset.data[index]);
        if (chart.getDataVisibility(index) && Number.isFinite(value) && value > 0) {
            slices.push({ value, element });
        }
    });
    return { slices, total: slices.reduce((sum, slice) => sum + slice.value, 0), dataset };
}

/**
 * Inline plugin writing each slice's label at the middle of its arc, in white on the slice. Slices too thin to hold a
 * label are skipped. `options.mode` is value | percent | both | none.
 */
function createSliceLabelsPlugin(formatValue) {
    return {
        id: 'boardSliceLabels',
        afterDatasetsDraw(chart, args, options) {
            if (!options || options.mode === 'none') {
                return;
            }
            const { slices, total, dataset } = visibleSlices(chart);
            const { ctx } = chart;
            ctx.save();
            ctx.fillStyle = options.color;
            ctx.font = options.font;
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            slices.forEach(({ value, element }) => {
                if (element.endAngle - element.startAngle < MIN_LABELLED_ARC_RADIANS) {
                    return;
                }
                const angle = (element.startAngle + element.endAngle) / 2;
                const radius = (element.innerRadius + element.outerRadius) / 2;
                ctx.fillText(
                    sliceLabelText(value, total, options.mode, (v) => formatValue(v, dataset.boardMeasureIndex || 0)),
                    element.x + Math.cos(angle) * radius,
                    element.y + Math.sin(angle) * radius
                );
            });
            ctx.restore();
        }
    };
}

/** Inline plugin writing the sum of the visible slices in the hole of a donut (`options.display`). */
function createCentreTotalPlugin(formatValue) {
    return {
        id: 'boardCentreTotal',
        afterDatasetsDraw(chart, args, options) {
            if (!options || !options.display) {
                return;
            }
            const { slices, total, dataset } = visibleSlices(chart);
            if (!slices.length) {
                return;
            }
            const { ctx } = chart;
            ctx.save();
            ctx.fillStyle = options.color;
            ctx.font = options.font;
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText(formatValue(total, dataset.boardMeasureIndex || 0), slices[0].element.x, slices[0].element.y);
            ctx.restore();
        }
    };
}

/**
 * Chart.js v4 `pie` / `doughnut` / `polarArea` config: one dataset (the single Measure) with one coloured slice per
 * category, labelled by `settings.labelMode`; a donut may show its total in the hole.
 */
function buildSliceConfig(model, { settings, theme, animation, formatValue }, type) {
    const font = { family: theme.fontFamily, size: 12 };
    const series = model.series[0];
    const mode = SLICE_LABEL_MODES.includes(settings.labelMode) ? settings.labelMode : 'percent';
    const colors = resolveColours(model.categories, theme);
    return {
        type,
        data: {
            labels: model.categories.map((category) => category.label),
            datasets: [
                {
                    boardKey: series.key,
                    boardMeasureIndex: series.measureIndex || 0,
                    label: series.label,
                    data: series.values,
                    backgroundColor: colors,
                    hoverBackgroundColor: colors,
                    borderColor: theme.surface || '#ffffff',
                    borderWidth: 1
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            animation,
            ...(type === 'doughnut' ? { cutout: '60%' } : {}),
            plugins: {
                colors: { enabled: false },
                legend: legendOptions(settings, true, theme, font),
                tooltip: tooltipOptions(theme, font, true, formatValue),
                boardSliceLabels: { mode, color: '#ffffff', font: `11px ${theme.fontFamily}` },
                boardCentreTotal: {
                    display: type === 'doughnut' && settings.centreTotal === true && model.canRollUp !== false,
                    color: theme.dataLabel,
                    font: `600 16px ${theme.fontFamily}`
                }
            }
        },
        plugins: [createSliceLabelsPlugin(formatValue), createCentreTotalPlugin(formatValue)]
    };
}

/**
 * Chart.js v4 `radar` config: categories are the spokes, each series value or Measure is a polygon (translucent fill,
 * outline in its palette colour or fixed colour). Points shown unless `showPoints` is off.
 */
function buildRadarConfig(model, { settings, theme, animation, formatValue, formatTick }) {
    const multiSeries = model.hasSeries || model.series.length > 1;
    const font = { family: theme.fontFamily, size: 12 };
    const seriesColors = assignColors(model.series, theme);
    const pointRadius = settings.showPoints === false ? 0 : 3;
    return {
        type: 'radar',
        data: {
            labels: model.categories.map((category) => category.label),
            datasets: model.series.map((series, index) => {
                const color = series.color || seriesColors[index];
                return {
                    boardKey: series.key,
                    boardMeasureIndex: series.measureIndex || 0,
                    label: series.label,
                    data: series.values,
                    borderColor: color,
                    backgroundColor: withAlpha(color, 0.25),
                    pointBackgroundColor: color,
                    borderWidth: 2,
                    fill: true,
                    pointRadius,
                    pointHoverRadius: pointRadius + 2,
                    pointHitRadius: 6
                };
            })
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            animation,
            scales: {
                r: {
                    beginAtZero: true,
                    angleLines: { color: theme.grid },
                    grid: { color: theme.grid },
                    pointLabels: { color: theme.text, font },
                    ticks: {
                        color: theme.text,
                        font,
                        backdropColor: 'transparent',
                        callback: (value) => formatTick(value, model.series[0] ? model.series[0].measureIndex || 0 : 0)
                    }
                }
            },
            plugins: {
                colors: { enabled: false },
                legend: legendOptions(settings, multiSeries, theme, font),
                tooltip: tooltipOptions(theme, font, multiSeries, formatValue)
            }
        }
    };
}

/** Default waterfall colours: increase green, decrease red, Total neutral; each can be overridden per Widget. */
export const WATERFALL_DEFAULT_COLORS = { increase: '#2e844a', decrease: '#ba0517', total: '#747474' };

/**
 * Floating steps of a waterfall: each value moves the running total from `start` to `end` (`increase` or `decrease`);
 * `showTotal` appends a `total` step from zero to the final running total. Missing values count as zero.
 */
export function buildWaterfallSteps(values, showTotal) {
    let running = 0;
    const steps = values.map((value) => {
        const delta = Number(value) || 0;
        const step = { start: running, end: running + delta, kind: delta < 0 ? 'decrease' : 'increase' };
        running += delta;
        return step;
    });
    if (showTotal) {
        steps.push({ start: 0, end: running, kind: 'total' });
    }
    return steps;
}

function waterfallColor(value, fallback) {
    return typeof value === 'string' && /^#[0-9a-f]{3,8}$/i.test(value.trim()) ? value.trim() : fallback;
}

/** Chart.js v4 `bar` config of floating `[start, end]` bars, coloured increase / decrease / total. */
function buildWaterfallConfig(model, { settings, theme, animation, formatValue, formatTick, dataLabelsPlugin }) {
    const font = { family: theme.fontFamily, size: 12 };
    const series = model.series[0];
    const showTotal = settings.showTotal === true;
    const steps = buildWaterfallSteps(series.values, showTotal);
    const colors = {
        increase: waterfallColor(settings.waterfallIncreaseColor, WATERFALL_DEFAULT_COLORS.increase),
        decrease: waterfallColor(settings.waterfallDecreaseColor, WATERFALL_DEFAULT_COLORS.decrease),
        total: waterfallColor(settings.waterfallTotalColor, WATERFALL_DEFAULT_COLORS.total)
    };
    const stepColors = steps.map((step) => colors[step.kind]);
    return {
        type: 'bar',
        data: {
            labels: [...model.categories.map((category) => category.label), ...(showTotal ? ['Total'] : [])],
            datasets: [
                {
                    boardKey: series.key,
                    boardMeasureIndex: series.measureIndex || 0,
                    label: series.label,
                    data: steps.map((step) => [step.start, step.end]),
                    backgroundColor: stepColors,
                    hoverBackgroundColor: stepColors,
                    borderWidth: 0,
                    maxBarThickness: 48
                }
            ]
        },
        options: {
            indexAxis: 'x',
            responsive: true,
            maintainAspectRatio: false,
            animation,
            scales: {
                x: {
                    grid: { display: false },
                    border: { color: theme.grid },
                    ticks: {
                        color: theme.text,
                        font,
                        autoSkip: true,
                        autoSkipPadding: 8,
                        maxRotation: 0,
                        callback(value) {
                            return truncateLabel(this.getLabelForValue(value));
                        }
                    }
                },
                y: {
                    beginAtZero: true,
                    grid: { color: theme.grid },
                    border: { display: false },
                    ticks: { color: theme.text, font, callback: primaryTickFormatter(model, formatTick) }
                }
            },
            plugins: {
                colors: { enabled: false },
                legend: { display: false },
                tooltip: {
                    ...tooltipOptions(theme, font, false, formatValue),
                    callbacks: {
                        title: () => '',
                        label: (context) =>
                            `${context.label} — ${context.dataset.label}: ${formatValue(
                                Array.isArray(context.raw) ? context.raw[1] - context.raw[0] : context.raw,
                                context.dataset.boardMeasureIndex || 0
                            )}`
                    }
                },
                boardBarDataLabels: {
                    display: settings.showDataLabels,
                    stacked: false,
                    color: theme.dataLabel,
                    font: `11px ${theme.fontFamily}`
                }
            }
        },
        plugins: [dataLabelsPlugin]
    };
}

/** Mutates a live chart to a new config in place (labels, matching datasets, options) without recreating it. */
export function applyChartConfig(chart, config) {
    const existing = new Map(chart.data.datasets.map((dataset) => [dataset.boardKey, dataset]));
    chart.data.labels = config.data.labels;
    chart.data.datasets = config.data.datasets.map((next) => {
        const previous = existing.get(next.boardKey);
        return previous ? Object.assign(previous, next) : next;
    });
    chart.options = config.options;
}