<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardChartPanelSettings

<!-- LWC description -->

## JS Documentation

### BoardChartPanelSettings

Small multiples settings of the Chart Config editor: the Panel field (+ date granularity for a Date/DateTime field),
max panels, panel sort (by a Measure's total when there are several), panels per row, panel height, Independent
scales and the Panel headline (one of the Measures, hidden from the chart and shown as a number in each Panel header). Reads the Widget config and fires `change` with `detail.patch`, the config keys to update.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### measureLabels

Labels of the Chart widget's Measures, in Measure order.

**Kind**: instance property of <code>BoardChartPanelSettings</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>[]</code>  

#### bucketOptions

Bucket field options (`None` first) of the Widget and its Board; the Bucket field picker shows with any.

**Kind**: instance property of <code>BoardChartPanelSettings</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>[]</code>  

#### panelFieldType

`Schema.DisplayType` of the Panel field, once known.

**Kind**: instance property of <code>BoardChartPanelSettings</code>  
**Default**: <code>null</code>  

#### panelPickerValue

The Panel field picker shows nothing while a Bucket field is the Panel field.

**Kind**: instance property (getter) of <code>BoardChartPanelSettings</code>  

#### headlineOptions

`None`, then every Measure.

**Kind**: instance property (getter) of <code>BoardChartPanelSettings</code>  

#### resolvePanelFieldType()

Describes a saved Panel field (e.g. on reopening the editor) to know whether it takes a date granularity.

**Kind**: instance method of <code>BoardChartPanelSettings</code>  

#### handlePanelBucket(event)

A Bucket field as the Panel field: one Panel per bucket, no date granularity.

**Kind**: instance method of <code>BoardChartPanelSettings</code>  

#### handleHeadline(event)

Picks the Panel headline Measure and hides it from the chart (it stays one of the max 6 Measures).

**Kind**: instance method of <code>BoardChartPanelSettings</code>

## Files

- `boardChartPanelSettings.html`
- `boardChartPanelSettings.js`
- `boardChartPanelSettings.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
