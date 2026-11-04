<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardFilterCpe

<!-- LWC description -->

## JS Documentation

### SECTIONS

Config sections of the Filter Config editor (see `sectionStates` in `c/boardCpeUtils`).

**Kind**: global constant  
**Default**: <code>[...]</code>  

### BoardFilterCpe

Flow Custom Property Editor for the Board Filter widget, inside the shared `c-board-cpe-common` shell (Board,
Config JSON). The Filters section is a read-only list; filter definitions are edited in the Filter definitions
Config dialog (`c-board-filter-dialog`) and committed as one config change on Save. Record context and persistence
are edited inline.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### configLoaded

Set once the shell has sent its first `configchange`; section errors wait for it (no flash of errors).

**Kind**: instance property of <code>BoardFilterCpe</code>  
**Default**: <code>false</code>  

#### sectionOpen

Open state of the Config sections: set once on load (a new Widget opens Filters), then by the Admin.

**Kind**: instance property of <code>BoardFilterCpe</code>  
**Default**: <code>null</code>  

#### filtersSummary

`None`, `1 filter`, or `N filters`.

**Kind**: instance property (getter) of <code>BoardFilterCpe</code>  

#### recordContextSummary

The mode, plus the override filterId and host field path when set (e.g. `Locked · account · AccountId`).

**Kind**: instance property (getter) of <code>BoardFilterCpe</code>  

#### filterRows

Label (or filterId), type badge, and error indicator of each saved filter.

**Kind**: instance property (getter) of <code>BoardFilterCpe</code>  

#### handleEditFilters()

Opens the Filter definitions Config dialog on a draft of the filters. Save applies the draft as one config
change (plus the Record context override when the draft renamed, removed, or retyped its filter); Cancel,
Escape, and the header X change nothing. Focus then returns to "Edit filters…".

**Kind**: instance async method of <code>BoardFilterCpe</code>

## Files

- `boardFilterCpe.css`
- `boardFilterCpe.html`
- `boardFilterCpe.js`
- `boardFilterCpe.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
