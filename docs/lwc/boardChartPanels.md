<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardChartPanels

<!-- LWC description -->

## JS Documentation

### MAX_PANEL_CATEGORIES

Small multiples settings of the Chart widget: a Panel field turns the Widget into a grid of Panels, one per Panel
field value (shaped by the server, `BoardChartPanels`). Pure: the Widget config's Panel settings with defaults, the
request keys they add to the Chart query, one Panel's slice of a result, and design-time validation.

**Kind**: global constant  
**Default**: <code>50</code>  

### PANEL_KEYS

Every Widget config key of Small multiples, cleared together with the Panel field.

**Kind**: global constant  
**Default**: <code>[...]</code>  

### hasPanelField([config])

Whether the Widget config sets a Panel field (Small multiples).

**Kind**: global function  

### normalizePanelSettings([config])

The Widget config's Small multiples settings with defaults: max panels 2–12 (6), panels per row 1–6 (3), panel
height 150–600 px (250), Panel sort (`FIELD_ORDER` unless a Measure's total), Independent scales off, Panel headline
Measure index (null without one).

**Kind**: global function  

### panelHeadlineIndex([config])

Index of the Measure shown as the Panel headline (a hidden Measure, one number per Panel header), or null without a
Panel field or headline.

**Kind**: global function  

### panelRequestFields([config])

Chart query request keys of the Panel field and its settings; none without a Panel field.

**Kind**: global function  

### isPanelResult(result)

Whether a Chart query result is Small multiples (it carries Panels).

**Kind**: global function  

### panelTotalsOf(result, panelKey)

One Panel's total per Measure (`panelTotals` of the result), or null when the server returned none.

**Kind**: global function  

### panelSlice(result, panelKey)

One Panel's slice of a Small multiples result: the shared categories and series, only that Panel's points, and its
Panel totals as the overall values, so its Reference lines sit at the Panel's value.

**Kind**: global function  

### isBucketReference(value)

A Bucket field reference (`bucket:<id>`) rather than a field path.

**Kind**: global function  

### smallMultiplesErrors([config])

Design-time errors `{ key, message }` of the Small multiples settings.

**Kind**: global function

## Files

- `boardChartPanels.js`
- `boardChartPanels.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
