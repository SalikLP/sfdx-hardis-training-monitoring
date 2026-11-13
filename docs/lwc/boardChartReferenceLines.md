<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardChartReferenceLines

<!-- LWC description -->

## JS Documentation

### REFERENCE_LINE_RENDER

Reference lines of the Chart widget: a Measure drawn as a Reference line (`render: 'referenceLine'`, bar and line
charts) is one flat line across the plot at the Measure's overall value (`overallValues` of the Chart query),
labelled at its end, on the Measure's value axis. It is not a series: it draws no dataset, takes no palette colour
(its own colour, else the theme's neutral text colour) and stays out of the legend. Pure: no canvas, so the
model, the Chart.js config and the drawing are unit tested with fakes.

**Kind**: global constant  
**Default**: <code>'referenceLine'</code>  

### referenceLinesPlugin

Inline Chart.js plugin drawing `options.lines` after the datasets: a dashed line across the plot at each value
(horizontal on vertical charts, vertical on horizontal bars), its text at the end (right end above the line, or
top end right of it).

**Kind**: global constant  
**Default**: <code>{...}</code>  

### splitReferenceLines(model, { result, measures, measureLabels })

Moves the Reference line Measures of a chart model out of its `series` into `referenceLines`
(`{ measureIndex, label, value, axis, color }` each, `value` null when the query returned none).

**Kind**: global function  

### withReferenceLines(config, model, { theme, formatValue, formatTick })

Adds the model's Reference lines to a bar or line Chart.js config: the drawing plugin (always, so a live chart
updated in place picks up lines added later), each line's axis grown to include its value, and the secondary
value axis when only a Reference line uses it. `formatValue(value, measureIndex)` labels the line,
`formatTick(value, measureIndex)` ticks a secondary axis it adds.

**Kind**: global function

## Files

- `boardChartReferenceLines.js`
- `boardChartReferenceLines.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
