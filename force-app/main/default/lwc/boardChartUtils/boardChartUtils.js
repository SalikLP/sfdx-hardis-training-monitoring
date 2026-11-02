import { loadScript } from 'lightning/platformResourceLoader';
import CHARTJS from '@salesforce/resourceUrl/chartjs';

/**
 * Shared Chart.js v4 engine for Board chart Widgets: singleton static resource loader, SLDS 1/2 theme sampler,
 * media query listeners, the SLDS Color-Safe categorical palette, and an inline bar data-label plugin.
 */

export const PREFERS_DARK_QUERY = '(prefers-color-scheme: dark)';
export const PREFERS_REDUCED_MOTION_QUERY = '(prefers-reduced-motion: reduce)';

/**
 * 6-color categorical palette: SLDS 2 mid-scale palette hooks `blue/teal/orange/pink/indigo/hot-orange-50`, constant in
 * light and dark mode (≥3:1 on both surfaces). Same values as the `--board-chart-palette-1..6` CSS fallbacks.
 */
export const SLDS_COLOR_SAFE_PALETTE = ['#0176d3', '#0b827c', '#a96404', '#e3066a', '#5867e8', '#d83a00'];

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

/**
 * Inline Chart.js plugin drawing formatted values at the end of each bar (or each stack total when
 * `options.stacked`). Enabled via `options.plugins.boardBarDataLabels.display`; `formatValue` stays in the closure
 * because Chart.js resolves plugin option functions as scriptable values.
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
            if (options.stacked) {
                const referenceMeta = chart.getDatasetMeta(visible[visible.length - 1]);
                referenceMeta.data.forEach((element, index) => {
                    const total = visible.reduce(
                        (sum, datasetIndex) => sum + (Number(chart.data.datasets[datasetIndex].data[index]) || 0),
                        0
                    );
                    const position = valueScale.getPixelForValue(total);
                    labels.push({
                        value: total,
                        x: horizontal ? position : element.x,
                        y: horizontal ? element.y : position
                    });
                });
            } else {
                visible.forEach((datasetIndex) => {
                    chart.getDatasetMeta(datasetIndex).data.forEach((element, index) => {
                        const value = chart.data.datasets[datasetIndex].data[index];
                        if (value !== null && value !== undefined) {
                            labels.push({ value, x: element.x, y: element.y });
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
                    formatValue(label.value),
                    horizontal ? label.x + 4 : label.x,
                    horizontal ? label.y : label.y - 4
                );
            });
            ctx.restore();
        }
    };
}