<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardMetricGauge

<!-- LWC description -->

## JS Documentation

### DISPLAY_NUMBER

Metric widget Gauge: the pure model behind the Gauge display (no DOM, no Apex).

Config (`display: 'gauge'` on the Metric widget):
  `gauge: { min?, minMeasure?, max?, maxMeasure?, bandsPercentOfMax?, targetMeasure? }`
- `min` / `max` are static numbers; `minMeasure` / `maxMeasure` are the 0-based position of a hidden Measure in the
  Measures list and win over the static number. `min` defaults to 0; `max` is required one way or the other.
- The Widget's Thresholds are the bands: each rule's value is absolute, or a percentage of max when
  `bandsPercentOfMax` is true. The scale is split at the rule limits and each part takes the status of the first
  rule matching it.
- `targetMeasure` is the position of a hidden Measure drawn as a marker.
- Currency: the static `min` / `max` and absolute bands are Admin amounts in the Board's Config currency. The request
  sends them (`gaugeConfigAmounts`, `thresholdAmounts`) and Apex returns them in the Display currency when the value
  is an amount; `gaugeConfigInDisplayCurrency` puts them back before `resolveGauge`. % of max bands never convert.

**Kind**: global constant  
**Default**: <code>'number'</code>  

### isGaugeDisplay(config)

Whether the Metric config asks for the Gauge.

**Kind**: global function  

### gaugeSettings(config)

The Gauge settings with blanks as null.

**Kind**: global function  

### gaugeConfigAmounts(config)

The Gauge's static minimum and maximum, Admin amounts in the Config currency, for Apex to convert: `[min, max]`,
null for a blank one or one taken from a Measure.

**Kind**: global function  

### gaugeConfigInDisplayCurrency(config, { gaugeAmounts, thresholdAmounts } = {})

The Metric config with the Gauge's static min / max (`gaugeAmounts`) and absolute bands (`thresholdAmounts`, one per
Threshold rule) replaced by the converted amounts Apex returned; null entries keep the amount as entered. Bands
read as % of max are percentages: never converted.

**Kind**: global function  

### measureRefProblem(index, measures, role)

Why Measure position `index` can't feed the Gauge as `role`, or '' when it can.

**Kind**: global function  

### gaugeConfigProblems(config, measures)

Design-time problems of the Gauge settings as readable messages (`[]` when the config is valid or not a Gauge).
`measures` is the Metric's Measures list.

**Kind**: global function  

### ruleLimit(rule, max, percentOfMax)

Absolute limit of a Threshold rule on the scale, or null for a rule that can't be drawn.

**Kind**: global function  

### buildBands(thresholds, min, max, percentOfMax)

The scale split at the rule limits: `[{ variant, startPct, widthPct }]`, consecutive equal statuses merged.

**Kind**: global function  

### resolveGauge({ config, value, measureValues, format })

Resolves the Gauge for one result.

`input`: `{ config, value, measureValues, format }` where `value` is the visible Measure's number (or null),
`measureValues` the raw value of every Measure in list order, `format(number)` the label formatter. Returns
`{ model }` or `{ error }` (a readable message; the Widget shows it instead of the Gauge).

`model`: `{ minLabel, maxLabel, valuePct (null without a value), valueLabel, bands: [{ key, variant, startPct,
widthPct }], target: { pct, label } | null }`, percentages 0–100 of the scale.

**Kind**: global function

## Files

- `boardMetricGauge.js`
- `boardMetricGauge.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
