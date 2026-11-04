<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardMetricCpe

<!-- LWC description -->

## JS Documentation

### SECTIONS

Config sections of the Metric Config editor (see `sectionStates` in `c/boardCpeUtils`).

**Kind**: global constant  
**Default**: <code>[...]</code>  

### BoardMetricCpe

Flow Custom Property Editor for the Board Metric widget: aggregate function + capability-filtered value field,
value format, subtitle, and ordered thresholds, inside the shared `c-board-cpe-common` shell (Board, Object, Filter
bindings, Base filters, Config JSON). Its own Config sections are Measure and Thresholds.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### configLoaded

Set once the shell has sent its first `configchange`; section errors wait for it (no flash of errors).

**Kind**: instance property of <code>BoardMetricCpe</code>  
**Default**: <code>false</code>  

#### defaultNotation

Widget default notation, shown by the format editor.

**Kind**: instance property of <code>BoardMetricCpe</code>  
**Default**: <code>defaultNotationFor('metric')</code>  

#### sectionOpen

Open state of the Config sections: set once on load (a new Widget opens Measure), then by the Admin.

**Kind**: instance property of <code>BoardMetricCpe</code>  
**Default**: <code>null</code>  

#### drag

Drag-to-reorder state of the threshold rules (see the drag helpers in c/boardCpeUtils).

**Kind**: instance property of <code>BoardMetricCpe</code>  
**Default**: <code>NO_DRAG</code>

## Files

- `boardMetricCpe.css`
- `boardMetricCpe.html`
- `boardMetricCpe.js`
- `boardMetricCpe.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
