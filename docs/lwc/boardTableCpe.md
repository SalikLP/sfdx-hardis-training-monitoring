<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardTableCpe

<!-- LWC description -->

## JS Documentation

### SECTIONS

Config sections of the Table Config editor (see `sectionStates` in `c/boardCpeUtils`).

**Kind**: global constant  
**Default**: <code>[...]</code>  

### BoardTableCpe

Flow Custom Property Editor for the Board Table widget: repeatable columns, default sort, page size, row count, and
the optional expandable `childRelationship` (relationship, child columns, sort, limit), inside the shared
`c-board-cpe-common` shell (Board, Object, Filter bindings, Base filters, Config JSON).

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### configLoaded

Set by the shell's first `configchange`; until then `config` is a placeholder and must not flag errors.

**Kind**: instance property of <code>BoardTableCpe</code>  
**Default**: <code>false</code>  

#### sectionOpen

Open state of the Config sections: set once on load (a new Widget opens Columns), then by the Admin.

**Kind**: instance property of <code>BoardTableCpe</code>  
**Default**: <code>null</code>  

#### columnsSummary

`3 columns`, or `No columns`.

**Kind**: instance property (getter) of <code>BoardTableCpe</code>  

#### sortingSummary

`CreatedDate desc · 50 per page`, plus `No row count` when hidden.

**Kind**: instance property (getter) of <code>BoardTableCpe</code>  

#### childSummary

`None`, or the child relationship and its column count (e.g. `CaseComments · 2 columns`).

**Kind**: instance property (getter) of <code>BoardTableCpe</code>

## Files

- `boardTableCpe.html`
- `boardTableCpe.js`
- `boardTableCpe.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
