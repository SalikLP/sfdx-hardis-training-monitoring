/**
 * Pure Small multiples layout helpers: panels per row narrowed to the available width, one value axis shared across
 * the Panels' Chart.js configs, and the one legend lifted out of them. No canvas, so they are tested through the
 * panel grid with a mocked Chart.js.
 */

/** Narrowest a Panel may get before the grid drops a column. */
export const MIN_PANEL_WIDTH_PX = 200;
/** Gap between Panels (`--slds-g-spacing-3`). */
export const PANEL_GAP_PX = 12;

const SLICE_TYPES = ['pie', 'doughnut', 'polarArea'];
const RADIAL_TYPES = ['radar', 'polarArea'];

/** Panels per row: the Admin's number, reduced so each Panel keeps `MIN_PANEL_WIDTH_PX`; unmeasured width keeps it. */
export function effectivePanelsPerRow(requested, widthPx) {
    const wanted = Math.max(1, Number(requested) || 1);
    if (!widthPx || widthPx <= 0) {
        return wanted;
    }
    const fitting = Math.floor((widthPx + PANEL_GAP_PX) / (MIN_PANEL_WIDTH_PX + PANEL_GAP_PX));
    return Math.max(1, Math.min(wanted, fitting));
}

/** Value axis id a dataset is drawn on; null for pie and donut (no value axis). */
function valueAxisOf(config, dataset) {
    if (RADIAL_TYPES.includes(config.type)) {
        return 'r';
    }
    if (SLICE_TYPES.includes(config.type)) {
        return null;
    }
    if (dataset.yAxisID) {
        return dataset.yAxisID;
    }
    if (dataset.xAxisID) {
        return dataset.xAxisID;
    }
    return config.options && config.options.indexAxis === 'y' ? 'x' : 'y';
}

function widen(extents, axis, value) {
    if (!Number.isFinite(value)) {
        return;
    }
    const extent = extents.get(axis) || { min: 0, max: 0 };
    extent.min = Math.min(extent.min, value);
    extent.max = Math.max(extent.max, value);
    extents.set(axis, extent);
}

/** Adds one config's data range per value axis to `extents` (stacked axes by their per-category sums). */
function collectExtents(config, extents) {
    const scales = (config.options && config.options.scales) || {};
    const stacks = new Map();
    ((config.data && config.data.datasets) || []).forEach((dataset) => {
        const axis = valueAxisOf(config, dataset);
        if (!axis) {
            return;
        }
        const stacked = Boolean(scales[axis] && scales[axis].stacked);
        (dataset.data || []).forEach((entry, index) => {
            if (Array.isArray(entry)) {
                entry.forEach((value) => widen(extents, axis, value === null ? NaN : Number(value)));
                return;
            }
            const value = entry === null || entry === undefined ? NaN : Number(entry);
            if (!stacked) {
                widen(extents, axis, value);
                return;
            }
            if (!Number.isFinite(value)) {
                return;
            }
            const sums = stacks.get(axis) || { positive: [], negative: [] };
            const side = value < 0 ? sums.negative : sums.positive;
            side[index] = (side[index] || 0) + value;
            stacks.set(axis, sums);
        });
    });
    stacks.forEach((sums, axis) => {
        [...sums.positive, ...sums.negative].forEach((value) => widen(extents, axis, value));
    });
}

/**
 * Gives every Panel the same value axis: each value scale gets the range of all Panels' data as its suggested
 * minimum and maximum, so Chart.js picks the same ticks in every Panel. Mutates and returns `configs`.
 */
export function shareValueScales(configs) {
    const extents = new Map();
    configs.forEach((config) => collectExtents(config, extents));
    configs.forEach((config) => {
        if (config.type === 'pie' || config.type === 'doughnut') {
            return;
        }
        config.options = config.options || {};
        config.options.scales = config.options.scales || {};
        extents.forEach((extent, axis) => {
            config.options.scales[axis] = {
                ...(config.options.scales[axis] || {}),
                suggestedMin: extent.min,
                suggestedMax: extent.max
            };
        });
    });
    return configs;
}

function datasetColour(config, dataset) {
    const drawnAsBars = dataset.type === 'bar' || (config.type === 'bar' && dataset.type !== 'line');
    const colour = drawnAsBars ? dataset.backgroundColor : dataset.borderColor || dataset.backgroundColor;
    return Array.isArray(colour) ? colour[0] : colour;
}

/**
 * The legend a Panel's config would draw, as `{ position: 'top' | 'bottom', items: [{ key, label, color }] }`, or
 * null when it shows none: one item per category for pie, donut and polarArea, else one per dataset.
 */
export function legendFromConfig(config) {
    const legend = config && config.options && config.options.plugins && config.options.plugins.legend;
    if (!legend || legend.display === false) {
        return null;
    }
    const datasets = (config.data && config.data.datasets) || [];
    let items;
    if (SLICE_TYPES.includes(config.type)) {
        const colours = (datasets[0] && datasets[0].backgroundColor) || [];
        items = (config.data.labels || []).map((label, index) => ({
            key: `category-${index}`,
            label,
            color: Array.isArray(colours) ? colours[index] : colours
        }));
    } else {
        items = datasets.map((dataset, index) => ({
            key: `series-${dataset.boardKey || index}`,
            label: dataset.label,
            color: datasetColour(config, dataset)
        }));
    }
    return { position: legend.position === 'bottom' ? 'bottom' : 'top', items };
}

/** Turns a Panel's own Chart.js legend off: the grid draws one legend for every Panel. */
export function withoutLegend(config) {
    const plugins = (config.options && config.options.plugins) || {};
    config.options = {
        ...(config.options || {}),
        plugins: { ...plugins, legend: { ...(plugins.legend || {}), display: false } }
    };
    return config;
}