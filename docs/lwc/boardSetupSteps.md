<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardSetupSteps

<!-- LWC description -->

## JS Documentation

### isOnObject(path, objectFields)

True when `path`'s first segment is a field (or, for a parent path, a relationship) of the described object.

**Kind**: global function  

### fieldsOnObjectErrors(config, context, paths)

Errors for field paths of the draft that aren't on its object (`context.objectFields`), e.g. after the Admin
changed the object. `paths(config)` lists `{ key, label, path }`; Bucket field references are skipped.

**Kind**: global function  

### checkablePath(path)

Whether a path can be checked against the object's field describes: not a Bucket field reference, `SELF`, or a
child semi-join (`Child(ForeignKey).Path`, whose relationship isn't among the object's fields).

**Kind**: global function  

### conditionPaths(tree, key, label)

`{ key, label, path }` of every condition in a condition tree (a list of entries, or one group or condition).

**Kind**: global function  

### allPaths(...lists)

Combines several `paths(config)` lists into one.

**Kind**: global function  

### baseFilterPaths(config)

The Base filters' fields (Data step): a condition tree on the Widget's object.

**Kind**: global function  

### measureFieldPaths(measures)

The fields of a list of Measures read on the Widget's object: conditions and Average per record fields.

**Kind**: global function  

### bucketRulePaths(config)

The fields of the Widget's own Bucket field rules.

**Kind**: global function  

### filterBindingPaths(config)

The Filter binding paths set to a field path (each target of a multi-field binding).

**Kind**: global function  

### rowActionPaths(config)

The Table's Row action row fields: lookup targets, Create defaults' row fields and Screen Flow inputs.

**Kind**: global function  

### filterBindingsStep(widgetType)

The Filter bindings step, shared by every data Widget: binding paths must be on the Widget's object.

**Kind**: global function  

### step(widgetType, { extraErrors, ...descriptor })

A step descriptor of `widgetType`: `validate` keeps the `configErrors` of the whole draft that belong to the step
(`errorKeys`), plus the step's own `extraErrors(config, context)`.

**Kind**: global function  

### dataSummary(config, [context])

Data step summary: the object (or `No object`), plus the Base filter count (conditions inside groups too).

**Kind**: global function  

### dataStep(widgetType, [overrides])

The Data step of a data Widget (`widgetType`): the object and the Base filters (`c-board-setup-base-filters` in
the step content). Base filter errors make the step invalid. `overrides` sets e.g. the step's `intro` / `example`.

**Kind**: global function  

### filterBindingsSummary(bindingRows)

Filter bindings summary: `3 bound · 1 opted out`, or `None` without any Filter to bind.

**Kind**: global function  

### dimensionLabel(config, context, fieldReference)

A field path as is, or a Bucket field reference as its label (the Widget's own, else the Board's).

**Kind**: global function  

### showsGranularity(config, context)

Whether the chart groups by date: a date Group by field (once described) or a saved date granularity.

**Kind**: global function  

### chartDimensionsSummary(config, [context])

`CreatedDate · Calendar month · Stacked by Status`.

**Kind**: global function  

### chartSmallMultiplesSummary(config, [context])

`Panels by Type · Max 6` (a Bucket field Panel field by its label), or `Off` without a Panel field.

**Kind**: global function  

### chartDisplaySummary(config, [context])

`Value (high to low) · Max 10 bars`, plus the "Other" bar and data labels when on.

**Kind**: global function  

### chartGroupingPaths(config)

The Chart widget's field paths that must exist on its object, per step.

**Kind**: global function  

### chartMeasurePaths(config)

The Chart widget's Measure fields that must exist on its object (a Cross-object measure reads another object).

**Kind**: global function  

### CHART_STEPS

Chart widget steps, in order (chart type early, so the live preview starts early).

**Kind**: global constant  
**Default**: <code>[...]</code>  

### metricMeasurePaths(config)

The Metric widget's Measure fields that must exist on its object (a Cross-object measure reads another object).

**Kind**: global function  

### metricDisplaySummary(config)

`Gauge · Open pipeline`: Number or Gauge, plus the subtitle.

**Kind**: global function  

### metricThresholdsSummary(config)

`None` or the number of Threshold rules.

**Kind**: global function  

### METRIC_STEPS

Metric widget steps, in order.

**Kind**: global constant  
**Default**: <code>[...]</code>  

### tableHasDetailRows(config)

Row grouping with Detail rows on (the default): records under their Group rows.

**Kind**: global function  

### tableColumnsSummary(config)

`3 columns`, or `No columns`.

**Kind**: global function  

### tableGroupingSummary(config, [context])

`Grouped by StageName asc, then Deal size desc`, plus `Group rows only` with Detail rows off, or `No grouping`.

**Kind**: global function  

### tableSummariesSummary(config)

`Total row · Subtotals · 2 columns summarized`, or `None`.

**Kind**: global function  

### tableDisplaySummary(config)

`CloseDate desc · 50 per page · Top 10 · No row count`.

**Kind**: global function  

### tableRowActionsSummary(config)

`2 row actions`, or `No row actions`.

**Kind**: global function  

### TABLE_STEPS

Table widget steps, in order (mirrors a report builder).

**Kind**: global constant  
**Default**: <code>[...]</code>  

### filterItemsSummary(config)

`3 filters · 1 section · Currency picker`, or `None`. A saved Board-level `currencyPicker` counts as the item.

**Kind**: global function  

### boardBucketFieldsSummary(config)

`None`, `1 Bucket field`, or `N Bucket fields`.

**Kind**: global function  

### recordContextSummary(config)

The mode, plus the override filterId and host field path when set (`Locked · account · AccountId`).

**Kind**: global function  

### currencySummary(config)

`Config currency EUR`, or `Corporate currency`.

**Kind**: global function  

### FILTER_STEPS

Filter widget steps, in order. All are optional: a Filter widget without filters is valid (a Record context or
refresh-only bar), so Guided mode never blocks Next; Save still waits for every step to be valid.

**Kind**: global constant  
**Default**: <code>[...]</code>  

### stepsFor(widgetType)

The Setup dialog steps of `widgetType` (`[]` for an unknown type).

**Kind**: global function  

### stepSectionSummary(steps, sectionName, [config], [context])

The one-line summary of a panel Config section (`sectionName`), from the step that covers it, or null when no step
does.

**Kind**: global function

## Files

- `boardSetupSteps.js`
- `boardSetupSteps.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
