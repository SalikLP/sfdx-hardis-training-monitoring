<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardFilterCpe

<!-- LWC description -->

## JS Documentation

### BoardFilterCpe

Flow Custom Property Editor for the Board Filter widget: ordered filter definitions (auto-derived, editable
camelCase `filterId`s and per-type settings for PICKLIST, LOOKUP, USER, DATE_RANGE, and TEXT), Record context, and
persistence, inside the shared `c-board-cpe-common` shell (Board, Config JSON).

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### picklistOptions

`Object.Field` → `{ loading, options, error }` for FIELD_DESCRIBE picklist defaults.

**Kind**: instance property of <code>BoardFilterCpe</code>  
**Default**: <code>{}</code>  

#### recordLabels

Record Id → name of LOOKUP/USER default values.

**Kind**: instance property of <code>BoardFilterCpe</code>  
**Default**: <code>{}</code>  

#### userSearches

Row key → `{ term, results }` of the USER default search.

**Kind**: instance property of <code>BoardFilterCpe</code>  
**Default**: <code>{}</code>  

#### _rowKeys

Stable template keys parallel to `filters` (filterIds change while typing).

**Kind**: instance property of <code>BoardFilterCpe</code>  
**Default**: <code>[]</code>  

#### _dateModes

Row key → date default mode chosen before any value is entered.

**Kind**: instance property of <code>BoardFilterCpe</code>  
**Default**: <code>{}</code>  

#### loadDefaultSupport()

Loads described picklist values and record names the default-value editors display.

**Kind**: instance method of <code>BoardFilterCpe</code>  

#### picklistDefault(filter, optionsSource)

Choices of the PICKLIST default editor: custom options or the described picklist values.

**Kind**: instance method of <code>BoardFilterCpe</code>  

#### addDefaultValue(index, value)

Adds a default value (replacing the current one, including Me, on single-select filters).

**Kind**: instance method of <code>BoardFilterCpe</code>  

#### retargetRecordContext(patch, fromId, toId)

Keeps `recordContext.overrideFilterId` pointing at a renamed filter (or clears it when removed).

**Kind**: instance method of <code>BoardFilterCpe</code>  

#### compactRecordContext(recordContext)

`{ mode, overrideFilterId?, overrideFieldPath? }`, or null for the default (IMPLICIT without overrides).

**Kind**: instance method of <code>BoardFilterCpe</code>

## Files

- `boardFilterCpe.css`
- `boardFilterCpe.html`
- `boardFilterCpe.js`
- `boardFilterCpe.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
