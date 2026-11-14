<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardChartUtils

<!-- LWC description -->

## JS Documentation

### PREFERS_DARK_QUERY

Shared Chart.js v4 engine for Board chart Widgets: singleton static resource loader, SLDS 1/2 theme sampler,
media query listeners, and an inline bar data-label plugin. The palette, the greys and colour resolution live in
`c/boardChartColours`.

**Kind**: global constant  
**Default**: <code>'(prefers-color-scheme: dark)'</code>  

### seriesItemColors(model, theme)

Colour of each series of a model: series field values honour their fixed colours (the palette skips colours they
take, see `c/boardChartColours`); Measures take palette colours by position, a Measure's own colour applied on top.

**Kind**: global function  

### WATERFALL_DEFAULT_COLORS

Waterfall step colours when neither the Widget nor the `--board-chart-waterfall-*` hooks set them; the same values
as those hooks' fallbacks in `boardChartWidget.css`.

**Kind**: global constant  
**Default**: <code>{ increase: '#2e844a', decrease: '#ba0517', total: '#747474' }</code>  

### loadChartJs(component)

Loads the `chartjs` static resource (`chart.umd.min.js`) once per page and resolves to the `Chart` constructor.
A failed load is not cached, so a later call retries.

**Kind**: global function  

### resolveChartTheme(element)

Samples the `--board-chart-*` custom properties (backed by `--slds-g-*` styling hooks) declared on `element`, since
`<canvas>` drawing cannot resolve CSS `var()` references. SLDS 2 hooks may hold `light-dark(<light>, <dark>)`, which
canvas also cannot parse (it paints black), so each value is reduced to the branch for the element's color scheme.

**Kind**: global function  

### usesDarkColorScheme(style)

`light-dark()` follows the used color scheme: `dark` alone, or `light dark` while the OS prefers dark.

**Kind**: global function  

### resolveLightDark(value, dark)

Replaces every (possibly nested) `light-dark(a, b)` in `value` with `a` or `b`.

**Kind**: global function  

### watchMediaQuery(query, callback)

Calls `callback(matches)` whenever `query` changes; returns an unsubscribe function.

**Kind**: global function  

### watchColorScheme(callback)

Calls `callback()` when the page color scheme may have changed: the OS `prefers-color-scheme` media query, or a
`class`/`style`/`data-*` theme attribute change on `<html>`/`<body>` (in-app theme switches without a reload).
Callers compare the re-sampled theme before repainting. Returns an unsubscribe function.

**Kind**: global function  

### chartAnimation(reducedMotion)

In-place update animation: `300ms easeOutQuart`, or `0ms` when `prefers-reduced-motion: reduce` matches.

**Kind**: global function  

### labelFitsOnBar(chart, element, horizontal)

A bar's data label is skipped when the bar is outside the plot (scrolled away) or too thin to hold it.

**Kind**: global function  

### createBarDataLabelsPlugin(formatValue)

Inline Chart.js plugin drawing formatted values at the end of each bar (or each stack total when
`options.stacked`). Enabled via `options.plugins.boardBarDataLabels.display`; `formatValue(value, measureIndex)`
stays in the closure because Chart.js resolves plugin option functions as scriptable values. Each label uses the
format of its dataset's Measure (`boardMeasureIndex`); a stack total uses the stack's.

**Kind**: global function  

### computeScrollLayout({ categoryCount, seriesCount, stacked, viewportPx })

Scroll sizing for a bar chart: every category slot is a fixed `BAR_THICKNESS_PX` per bar (grouped bars side by
side, stacked bars as one) plus a gap. `viewportPx` is the plot's extent along the category axis (0 = unknown,
never scrolls). `contentPx` is what the scroll container must span.

**Kind**: global function  

### visibleCategoryWindow(layout, scrollOffset)

The first/last category index (inclusive) shown for a scroll offset along the category axis.

**Kind**: global function  

### truncateLabel(label)

Category tick label shortened with an ellipsis; the tooltip keeps the full label.

**Kind**: global function  

### dataLabelFits(thicknessPx)

False when a bar is too thin (px across the category axis) to hold its data label.

**Kind**: global function  

### CHART_TYPES

Chart types of the Chart widget, in picker order. Each descriptor says which type-specific Widget config settings
apply (the Config editor shows only these; the others are kept for a switch back), the max categories the Admin
may ask for, whether the plot scrolls along the category axis (fixed-thickness bars) or compresses and skips labels
(lines), and the pure Chart.js config builder. A new chart type is one more entry here.

**Kind**: global constant  
**Default**: <code>[...]</code>  

### CHART_TYPE_OPTIONS

`{ label, value }` options of the chart type picker.

**Kind**: global constant  
**Default**: <code>CHART_TYPES.map(({ label, value }) =&gt; ({ label, value }))</code>  

### chartTypeDescriptor(chartType)

The chart type's descriptor; an unknown or missing type is `bar`.

**Kind**: global function  

### isChartType(chartType)

Whether `chartType` is one the Chart widget can draw.

**Kind**: global function  

### chartTypeHasSetting(chartType, setting)

Whether a type-specific setting (e.g. `orientation`, `showPoints`) applies to `chartType` (missing means bar).

**Kind**: global function  

### maxCategoriesFor(chartType)

The largest max categories `chartType` accepts (the smallest is always 3).

**Kind**: global function  

### chartTypeScrolls(chartType)

Whether `chartType` scrolls along the category axis when its categories don't fit (bars), instead of compressing.

**Kind**: global function  

### chartTypeIsSingleMeasure(chartType)

Whether `chartType` draws exactly one Measure and no series field (pie, donut, polarArea).

**Kind**: global function  

### normalizeMeasureDisplay(measure, chartType)

A Measure's `render` (bar | line | referenceLine) and value `axis` (primary | secondary) in a chart type that draws combo charts
(bar, line). Unset, a Measure is drawn as the chart type draws it, on the primary axis. Other chart types ignore
both (the config keeps them for a switch back): `render` is null and `axis` primary.

**Kind**: global function  

### MEASURE_RENDER_OPTIONS

`{ label, value }` options of a Measure's `render` and `axis` in the Config editor.

**Kind**: global constant  
**Default**: <code>[...]</code>  

### buildChartConfig(chartType, model, options)

Chart.js v4 config for a chart model, dispatched on the Widget config's `chartType`. Pure: no canvas, so it is
unit tested directly.

**Kind**: global function  

### legendOptions(settings, multiSeries, theme, font)

Legend shown on `auto` only for several series; `bottom` or else `top`.

**Kind**: global function  

### tooltipOptions(theme, font, multiSeries, formatValue)

Tooltip shared by every chart type: `Category — Series: formatted value` in that series' Measure format.

**Kind**: global function  

### withAlpha(color, alpha)

`#rrggbb` at `alpha` opacity (`#rrggbbaa`); any other colour syntax is returned unchanged.

**Kind**: global function  

### valueAxisBinding(series, horizontal)

Dataset property binding a series to its value axis: `y` (`x` for horizontal bars), or the secondary `y1`/`x1`.

**Kind**: global function  

### firstMeasureOnAxis(model, axis)

The Measure whose format an axis' ticks use: the first one drawn on it (`primary` or `secondary`), else -1.

**Kind**: global function  

### primaryTickFormatter(model, formatTick)

Primary value axis tick formatter: the format of its first Measure (the first Measure when none is on it).

**Kind**: global function  

### valueScales(model, primaryAxis, horizontal, formatTick)

Value scales keyed by axis id: the primary axis, plus the secondary axis only when a Measure uses it. The
secondary axis sits opposite the primary, draws no grid lines across the plot, and its ticks use the format of the
first Measure on it.

**Kind**: global function  

### lineDatasetStyle(color, pointRadius)

Dataset style of a series drawn as a line: straight segments, no fill, points of `pointRadius`.

**Kind**: global function  

### barDatasetStyle(color)

Dataset style of a series drawn as bars.

**Kind**: global function  

### buildLineConfig(model, { settings, theme, animation, formatValue, formatTick, dataLabelsPlugin }, area)

Chart.js v4 `line` config for a line or area chart: one line per series value or per Measure, straight segments (no
smoothing), points shown unless `showPoints` is off. An area chart fills each line to the axis, and stacks the
areas when a series field splits its one Measure. The category axis never scrolls: it compresses and skips labels.

**Kind**: global function  

### buildBarConfig(model, { settings, theme, animation, formatValue, formatTick, dataLabelsPlugin, scroll, scrollWindow })

Chart.js v4 `bar` config for a model. Datasets carry `boardKey` so in-place updates keep each series' dataset (and
its bar elements) alive for morph animations, and `boardMeasureIndex` so tooltips and data labels format each value
with its Measure's format (`formatValue(value, measureIndex)`). A Measure's own `color` wins over the palette.

**Kind**: global function  

### sliceLabelText(value, total, mode, formatValue)

A pie/donut/polarArea slice label: the formatted value, its share of `total`, both, or nothing.

**Kind**: global function  

### visibleSlices(chart)

The visible slices of a pie-like chart's first dataset as `{ value, element }`, and their sum.

**Kind**: global function  

### createSliceLabelsPlugin(formatValue)

Inline plugin writing each slice's label at the middle of its arc, in white on the slice. Slices too thin to hold a
label are skipped. `options.mode` is value | percent | both | none.

**Kind**: global function  

### createCentreTotalPlugin(formatValue)

Inline plugin writing the sum of the visible slices in the hole of a donut (`options.display`).

**Kind**: global function  

### buildSliceConfig(model, { settings, theme, animation, formatValue }, type)

Chart.js v4 `pie` / `doughnut` / `polarArea` config: one dataset (the single Measure) with one coloured slice per
category, labelled by `settings.labelMode`; a donut may show its total in the hole.

**Kind**: global function  

### buildRadarConfig(model, { settings, theme, animation, formatValue, formatTick })

Chart.js v4 `radar` config: categories are the spokes, each series value or Measure is a polygon (translucent fill,
outline in its palette colour or fixed colour). Points shown unless `showPoints` is off.

**Kind**: global function  

### buildWaterfallSteps(values, showTotal)

Floating steps of a waterfall: each value moves the running total from `start` to `end` (`increase` or `decrease`);
`showTotal` appends a `total` step from zero to the final running total. Missing values count as zero.

**Kind**: global function  

### buildWaterfallConfig(model, { settings, theme, animation, formatValue, formatTick, dataLabelsPlugin })

Chart.js v4 `bar` config of floating `[start, end]` bars, coloured increase / decrease / total.

**Kind**: global function  

### applyChartConfig(chart, config)

Mutates a live chart to a new config in place (labels, matching datasets, options) without recreating it.

**Kind**: global function

## Files

- `boardChartUtils.js`
- `boardChartUtils.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
