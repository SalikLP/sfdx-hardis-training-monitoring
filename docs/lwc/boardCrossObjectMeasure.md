<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCrossObjectMeasure

<!-- LWC description -->

## JS Documentation

### isPlainObject(value)

Cross-object measures: a Chart or Metric Measure whose rows come from its own `sourceObject` (e.g. a target object)
instead of the Widget's object. Shape on top of a Measure: `{ sourceObject, categoryMapping, panelMapping,
filterBindings, dataProvider }`. `categoryMapping`: the field on the source object matching the Widget's category
(a date field groups at the Widget's date granularity); `panelMapping`: the field matching the Panel field (Small
multiples); `filterBindings`: `{ filterId: fieldPath | 'IGNORE' }`, the Measure's own Filter bindings (unbound
filters bind by convention only where the field exists on the source object); `dataProvider`: an Apex Data provider
class supplying this Measure's values instead of the source object's query. The server (`BoardCrossObjectMeasures`)
joins its values onto the Widget's categories and reports per Measure the filters it ignores and whether it is blank.

**Kind**: global function  

### isCrossObjectMeasure(measure)

True when `measure` is a Cross-object measure (a non-Formula Measure with a source object).

**Kind**: global function  

### cleanBindings(bindings)

The Measure's own Filter bindings without blank keys; null when it has none.

**Kind**: global function  

### crossObjectRequestFields(measure)

The Cross-object part of a Measure (`{}` for any other Measure), as the query request sends it.

**Kind**: global function  

### crossObjectMeasureErrors(config, widgetType)

Design-time errors (`[message]`) of a Widget config's Cross-object measures, mirroring the server's blocked
combinations: Average per record and COUNT_DISTINCT; on the Chart widget also a series (Stack by) field, a Bucket
field category, a missing category mapping, and Small multiples (`panelField`) without a panel mapping.

**Kind**: global function  

### crossObjectNotices(notices, [measureLabels], [filterLabels]) ⇒ <code>Array&lt;{ key: string, message: string, isBlank: boolean }&gt;</code>

Inline notices of a query result's `crossObjectNotices`: a blank Measure the viewer can't access, and the filters a
Cross-object measure ignores. `measureLabels[i]` names Measure i; `filterLabels` maps a filter id to its label.

**Kind**: global function  
**Returns**: <code>Array&lt;{ key: string, message: string, isBlank: boolean }&gt;</code>

## Files

- `boardCrossObjectMeasure.js`
- `boardCrossObjectMeasure.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
