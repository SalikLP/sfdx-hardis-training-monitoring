<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardBarCpe

<!-- LWC description -->

## JS Documentation

### SECTIONS

Config sections of the Bar Config editor (see `sectionStates` in `c/boardCpeUtils`).

**Kind**: global constant  
**Default**: <code>[...]</code>  

### BoardBarCpe

Flow Custom Property Editor for the Board Bar Chart widget: Group by (+ date granularity for Date/DateTime fields),
optional Stack by, measure, sorting and overflow, legend, data labels, and value format, inside the shared
`c-board-cpe-common` shell (Board, Object, orientation, Filter bindings, Base filters, Config JSON).

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### configLoaded

Set once the shell has sent its first `configchange`; section errors wait for it (no flash of errors).

**Kind**: instance property of <code>BoardBarCpe</code>  
**Default**: <code>false</code>  

#### groupByType

`Schema.DisplayType` of the Group by leaf field, once known.

**Kind**: instance property of <code>BoardBarCpe</code>  
**Default**: <code>null</code>  

#### sectionOpen

Open state of the Config sections: set once on load (a new Widget opens Dimensions), then by the Admin.

**Kind**: instance property of <code>BoardBarCpe</code>  
**Default**: <code>null</code>  

#### resolveGroupByType()

Describes the saved Group by path (e.g. after reopening the editor) to decide which options apply.

**Kind**: instance method of <code>BoardBarCpe</code>  

#### dimensionsSummary

`CreatedDate · Calendar month · Stacked by Status`.

**Kind**: instance property (getter) of <code>BoardBarCpe</code>  

#### displaySummary

`Value (high to low) · Max 10 bars`, plus the "Other" bar and data labels when on.

**Kind**: instance property (getter) of <code>BoardBarCpe</code>

## Files

- `boardBarCpe.html`
- `boardBarCpe.js`
- `boardBarCpe.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
