/**
 * Pure Chart widget data shaping: the Widget config's display settings and Measures list, and the rendered model
 * built from a server-shaped `BoardChartQuery.ChartResult`. Sorting, the category limit with its "Other" bucket and
 * the series cap are computed by the server (`BoardChartEngine`); this module only lays the returned points out as
 * datasets and never re-aggregates.
 */

import {
    chartTypeHasSetting,
    chartTypeIsSingleMeasure,
    maxCategoriesFor,
    normalizeMeasureDisplay
} from 'c/boardChartUtils';
import { splitReferenceLines } from 'c/boardChartReferenceLines';
import { crossObjectRequestFields } from 'c/boardCrossObjectMeasure';
import { perRecordSettings } from 'c/boardConfigUtils';
import { MAX_PANEL_CATEGORIES, hasPanelField, panelHeadlineIndex } from 'c/boardChartPanels';

export const MAX_MEASURES = 6;
const VALUE_SERIES_KEY = '__value__';
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
const MAX_SERIES = 12;
/** Share of total modes of a Measure (`showAs`); the server returns percentages as fractions (0.25 = 25%). */
export const SHOW_AS_VALUE = 'value';
const SHOW_AS_MODES = new Set([SHOW_AS_VALUE, 'percentOfTotal', 'percentOfCategory']);
/** Number format of a Share of total Measure without its own format. */
export const SHARE_OF_TOTAL_FORMAT = Object.freeze({ formatStyle: 'percent', maximumFractionDigits: 1 });

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

function isPlainObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

/**
 * Display settings with defaults applied (`maxBars` 3..the chart type's max default 10, `maxSeries` 2..12 default 6).
 * `sortBy` stays null when unset: the server defaults to chronological for a date axis and to value, high to low,
 * otherwise. Settings of other chart types (e.g. a bar `orientation` on a line chart) are kept in the config but ignored.
 */
export function normalizeBarSettings(config = {}) {
    const sortBy = String(config.sortBy || '').toUpperCase();
    return {
        orientation:
            config.orientation === 'horizontal' && chartTypeHasSetting(config.chartType, 'orientation')
                ? 'horizontal'
                : 'vertical',
        sortBy: SORT_OPTIONS.has(sortBy) ? sortBy : null,
        // Small multiples show at most 50 categories per Panel.
        maxBars: clampInteger(
            config.maxBars,
            3,
            hasPanelField(config)
                ? Math.min(MAX_PANEL_CATEGORIES, maxCategoriesFor(config.chartType))
                : maxCategoriesFor(config.chartType),
            10
        ),
        overflowMode: String(config.overflowMode || '').toUpperCase() === 'OTHER' ? 'OTHER' : 'TRUNCATE',
        maxSeries: clampInteger(config.maxSeries, 2, MAX_SERIES, 6),
        stackMode: config.stackMode === 'grouped' ? 'grouped' : 'stacked',
        includeNullBucket: config.includeNullBucket !== false,
        legendPosition: ['top', 'bottom', 'hidden'].includes(config.legendPosition) ? config.legendPosition : 'auto',
        showDataLabels: config.showDataLabels === true,
        colorByCategory: config.colorByCategory === true,
        labelMode: ['value', 'percent', 'both', 'none'].includes(config.labelMode) ? config.labelMode : 'percent',
        centreTotal: config.centreTotal === true,
        showTotal: config.showTotal === true,
        waterfallIncreaseColor: config.waterfallIncreaseColor || null,
        waterfallDecreaseColor: config.waterfallDecreaseColor || null,
        waterfallTotalColor: config.waterfallTotalColor || null,
        showPoints: config.showPoints !== false
    };
}

/**
 * The Widget config's Measures list (max 6): `{ aggregateFunction, valueFieldApiName, label, format, color, showAs,
 * render, axis, condition, hidden, formula, isCurrency }` each (`condition`: the Measure condition tree, or null;
 * `isCurrency`: a currency Formula measure). A config without Measures counts records. A Share of total Measure without its own format gets `SHARE_OF_TOTAL_FORMAT`. A hidden
 * Measure is queried (e.g. as a Formula measure input) but not drawn; the Panel headline Measure is always hidden.
 * An Average per record (`AVG_PER`) Measure also has `perField` and `inner`.
 */
export function normalizeMeasures(config = {}) {
    const raw = Array.isArray(config.measures) ? config.measures.filter(isPlainObject) : [];
    const measures = raw.length ? raw.slice(0, MAX_MEASURES) : [{ aggregateFunction: 'COUNT' }];
    if (chartTypeIsSingleMeasure(config.chartType)) {
        measures.length = 1;
    }
    const headlineIndex = panelHeadlineIndex(config);
    return measures.map((measure, index) => {
        const aggregateFunction =
            String(measure.aggregateFunction || '')
                .trim()
                .toUpperCase() || 'COUNT';
        const showAs = SHOW_AS_MODES.has(measure.showAs) ? measure.showAs : SHOW_AS_VALUE;
        const hasFormat = isPlainObject(measure.format) && Object.keys(measure.format).length > 0;
        let format = hasFormat ? measure.format : {};
        if (!hasFormat && showAs !== SHOW_AS_VALUE) {
            format = { ...SHARE_OF_TOTAL_FORMAT };
        }
        return {
            aggregateFunction,
            valueFieldApiName: aggregateFunction === 'COUNT' ? null : measure.valueFieldApiName || null,
            showAs,
            label: typeof measure.label === 'string' && measure.label.trim() ? measure.label.trim() : null,
            format,
            color: typeof measure.color === 'string' && measure.color.trim() ? measure.color.trim() : null,
            hidden: measure.hidden === true || index === headlineIndex,
            formula: aggregateFunction === 'FORMULA' && typeof measure.formula === 'string' ? measure.formula : null,
            isCurrency: aggregateFunction === 'FORMULA' && measure.isCurrency === true,
            condition: hasMeasureCondition(measure) ? measure.condition : null,
            ...crossObjectRequestFields(measure),
            ...perRecordSettings({ ...measure, aggregateFunction }),
            ...normalizeMeasureDisplay(measure, config.chartType)
        };
    });
}

/** True when a Measure has a Measure condition with at least one condition. */
function hasMeasureCondition(measure) {
    const condition = measure && measure.condition;
    return isPlainObject(condition) && Array.isArray(condition.conditions) && condition.conditions.length > 0;
}

/**
 * Builds the rendered chart model from a server-shaped result: categories in server order and one dataset per
 * series value (one Measure split by a series field) or per Measure.
 *
 * @returns {{ categories: Array<{key, value, label, isOther, isBlank}>, series: Array<{key, label, colourKey,
 *   measureIndex, color, render, axis, isOther, isBlank, values: Array<number|null>}>, hasSeries: boolean, isStacked: boolean,
 *   canRollUp: boolean, referenceLines: Array }} Reference line Measures are `referenceLines`, not series. `canRollUp` is true when every Measure is additive (COUNT/SUM), so a Total may be summed.
 */
export function buildChartModel({ result, measures, measureLabels, settings }) {
    const categories = (result && result.categories) || [];
    const hasSeries = Boolean(result && result.stackBy);
    const values = new Map();
    ((result && result.points) || []).forEach((point) => {
        values.set(`${point.categoryKey}|${point.seriesKey}|${point.measureIndex}`, toNumber(point.value));
    });
    const valueAt = (categoryKey, seriesKey, measureIndex) => {
        const value = values.get(`${categoryKey}|${seriesKey}|${measureIndex}`);
        return value === undefined ? null : value;
    };

    let series;
    if (hasSeries) {
        series = ((result && result.series) || []).map((entry) => ({
            key: entry.key,
            label: entry.label,
            colourKey: entry.colourKey,
            measureIndex: 0,
            color: null,
            render: measures[0] ? measures[0].render : null,
            axis: measures[0] ? measures[0].axis : 'primary',
            isOther: entry.isOther === true,
            isBlank: entry.isBlank === true,
            values: categories.map((category) => valueAt(category.key, entry.key, 0))
        }));
    } else {
        const seriesKey = (result && result.series && result.series[0] && result.series[0].key) || VALUE_SERIES_KEY;
        // Hidden Measures (e.g. Formula measure inputs) are never drawn: no dataset, legend entry, tooltip or column.
        series = measures
            .map((measure, index) => ({
                key: `measure-${index}`,
                label: measureLabels[index],
                colourKey: `measure:${index}`,
                measureIndex: index,
                color: measure.color,
                render: measure.render,
                axis: measure.axis,
                isOther: false,
                isBlank: false,
                hidden: measure.hidden === true,
                values: categories.map((category) => valueAt(category.key, seriesKey, index))
            }))
            .filter((entry) => !entry.hidden);
    }

    const functions = (result && result.aggregateFunctions) || measures.map((measure) => measure.aggregateFunction);
    const model = {
        categories: categories.map((category) => ({
            key: category.key,
            value: category.value,
            label: category.label,
            isOther: category.isOther === true,
            isBlank: category.isBlank === true,
            color: typeof category.color === 'string' && category.color.trim() ? category.color.trim() : null
        })),
        series,
        hasSeries,
        isStacked: hasSeries && settings.stackMode === 'stacked',
        canRollUp: functions.every((fn) => ROLLUP_FUNCTIONS.has(fn))
    };
    return splitReferenceLines(model, { result, measures, measureLabels });
}