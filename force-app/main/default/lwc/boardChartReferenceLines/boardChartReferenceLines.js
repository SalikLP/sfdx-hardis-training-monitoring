/**
 * Reference lines of the Chart widget: a Measure drawn as a Reference line (`render: 'referenceLine'`, bar and line
 * charts) is one flat line across the plot at the Measure's overall value (`overallValues` of the Chart query),
 * labelled at its end, on the Measure's value axis. It is not a series: it draws no dataset, takes no palette colour
 * (its own colour, else the theme's neutral text colour) and stays out of the legend. Pure: no canvas, so the
 * model, the Chart.js config and the drawing are unit tested with fakes.
 */

export const REFERENCE_LINE_RENDER = 'referenceLine';
const PLUGIN_ID = 'boardReferenceLines';
const SECONDARY_AXIS_SUFFIX = '1';
const LABEL_GAP_PX = 4;

function toNumber(value) {
    if (value === null || value === undefined || value === '') {
        return null;
    }
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : null;
}

/**
 * Inline Chart.js plugin drawing `options.lines` after the datasets: a dashed line across the plot at each value
 * (horizontal on vertical charts, vertical on horizontal bars), its text at the end (right end above the line, or
 * top end right of it).
 */
const referenceLinesPlugin = {
    id: PLUGIN_ID,
    afterDatasetsDraw(chart, args, options) {
        const lines = (options && options.lines) || [];
        const { ctx, chartArea } = chart;
        lines.forEach((line) => {
            const scale = chart.scales[line.axisId];
            if (!scale) {
                return;
            }
            const position = scale.getPixelForValue(line.value);
            ctx.save();
            ctx.strokeStyle = line.color;
            ctx.fillStyle = line.color;
            ctx.lineWidth = 2;
            ctx.setLineDash([6, 4]);
            ctx.beginPath();
            if (options.horizontal) {
                ctx.moveTo(position, chartArea.bottom);
                ctx.lineTo(position, chartArea.top);
            } else {
                ctx.moveTo(chartArea.left, position);
                ctx.lineTo(chartArea.right, position);
            }
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.font = options.font;
            if (options.horizontal) {
                ctx.textAlign = 'left';
                ctx.textBaseline = 'top';
                ctx.fillText(line.text, position + LABEL_GAP_PX, chartArea.top);
            } else {
                ctx.textAlign = 'right';
                ctx.textBaseline = 'bottom';
                ctx.fillText(line.text, chartArea.right, position - LABEL_GAP_PX);
            }
            ctx.restore();
        });
    }
};

/**
 * Moves the Reference line Measures of a chart model out of its `series` into `referenceLines`
 * (`{ measureIndex, label, value, axis, color }` each, `value` null when the query returned none).
 */
export function splitReferenceLines(model, { result, measures, measureLabels }) {
    // A hidden Measure (e.g. a Formula measure input) is never drawn, not even as a Reference line.
    const isLine = (index) =>
        Boolean(measures[index]) && measures[index].render === REFERENCE_LINE_RENDER && measures[index].hidden !== true;
    const overall = (result && result.overallValues) || [];
    const referenceLines = measures
        .map((measure, index) => index)
        .filter(isLine)
        .map((index) => ({
            measureIndex: index,
            label: measureLabels[index],
            value: toNumber(overall[index]),
            axis: measures[index].axis === 'secondary' ? 'secondary' : 'primary',
            color: measures[index].color || null
        }));
    return {
        ...model,
        series: model.series.filter((series) => !isLine(series.measureIndex || 0)),
        referenceLines
    };
}

/**
 * Adds the model's Reference lines to a bar or line Chart.js config: the drawing plugin (always, so a live chart
 * updated in place picks up lines added later), each line's axis grown to include its value, and the secondary
 * value axis when only a Reference line uses it. `formatValue(value, measureIndex)` labels the line,
 * `formatTick(value, measureIndex)` ticks a secondary axis it adds.
 */
export function withReferenceLines(config, model, { theme, formatValue, formatTick }) {
    const horizontal = config.options.indexAxis === 'y';
    const primaryId = horizontal ? 'x' : 'y';
    const scales = { ...config.options.scales };
    const lines = [];
    (model.referenceLines || []).forEach((line) => {
        const axisId = line.axis === 'secondary' ? `${primaryId}${SECONDARY_AXIS_SUFFIX}` : primaryId;
        if (!scales[axisId]) {
            const primary = scales[primaryId];
            scales[axisId] = {
                ...primary,
                position: horizontal ? 'top' : 'right',
                grid: { ...primary.grid, drawOnChartArea: false },
                ticks: { ...primary.ticks, callback: (value) => formatTick(value, line.measureIndex) }
            };
        }
        if (line.value === null) {
            return;
        }
        const scale = { ...scales[axisId] };
        if (line.value > 0) {
            scale.suggestedMax = Math.max(line.value, scale.suggestedMax ?? line.value);
        } else if (line.value < 0) {
            scale.suggestedMin = Math.min(line.value, scale.suggestedMin ?? line.value);
        }
        scales[axisId] = scale;
        lines.push({
            axisId,
            value: line.value,
            text: `${line.label}: ${formatValue(line.value, line.measureIndex)}`,
            color: line.color || theme.text
        });
    });
    return {
        ...config,
        options: {
            ...config.options,
            scales,
            plugins: {
                ...config.options.plugins,
                [PLUGIN_ID]: { lines, horizontal, font: `11px ${theme.fontFamily}` }
            }
        },
        plugins: [...(config.plugins || []), referenceLinesPlugin]
    };
}