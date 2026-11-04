<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardFilterDialog

<!-- LWC description -->

## JS Documentation

### BoardFilterDialog

Filter definitions Config dialog: a large `LightningModal` that edits a draft of the Filter widget's `filters`
(master-detail: ordered list on the left, the selected filter's settings on the right). Open it with
`openConfigDialog(BoardFilterDialog, { label, description, value: { filters, recordContext } })`.

Closes with `{ action: 'save', draft: { filters, recordContext } }` or `{ action: 'dismiss' }`. `recordContext` is
carried only so its override follows filterId renames, removals, and type changes made in the draft. Save stays
disabled while any draft filter breaks the Filter widget's validation rules (`validateFilterDefinitions`), or while
the Record context no longer matches the draft filters (`recordContextErrors`).

**Kind**: global class  
**Extends**: <code>ConfigDialogMixin</code>  

#### value

`{ filters, recordContext }`, already deep-copied by `openConfigDialog`.

**Kind**: global property  
**Decorators**: <code>@api</code>  

#### picklistOptions

`Object.Field` → `{ loading, options, error }` for FIELD_DESCRIBE picklist defaults.

**Kind**: global property  
**Default**: <code>{}</code>  

#### recordLabels

Record Id → name of LOOKUP/USER default values.

**Kind**: global property  
**Default**: <code>{}</code>  

#### userSearches

Row key → `{ term, results }` of the USER default search.

**Kind**: global property  
**Default**: <code>{}</code>  

#### _dateModes

Row key → date default mode chosen before any value is entered.

**Kind**: global property  
**Default**: <code>{}</code>  

#### setDraftItems(filters, change)

A removed filter also drops the Record context override that pointed at it.

**Kind**: global function  

#### validation

The Filter widget's own validation rules applied to the draft filters.

**Kind**: instance property (getter)  

#### errorsByIndex

Messages per draft filter.

**Kind**: instance property (getter)  

#### recordContextErrors

Problems of the carried Record context against the draft filters (e.g. its override filter was renamed onto a
duplicate id or now resolves to a filter of the wrong type). Same rule as the Filter widget's `validate()`.

**Kind**: instance property (getter)  

#### picklistDefault(filter, optionsSource)

Choices of the PICKLIST default editor: custom options or the described picklist values.

**Kind**: global function  

#### loadDefaultSupport()

Loads described picklist values and record names the default-value editors display.

**Kind**: global function  

#### update(patch)

Applies `{ filters?, recordContext? }` to the draft (never to the Widget config).

**Kind**: global function  

#### addDefaultValue(index, value)

Adds a default value (replacing the current one, including Me, on single-select filters).

**Kind**: global function  

#### retargetRecordContext(patch, fromId, toId)

Keeps the Record context override pointing at a renamed filter (or clears it when removed / retyped).

**Kind**: global function

## Files

- `boardFilterDialog.css`
- `boardFilterDialog.html`
- `boardFilterDialog.js`
- `boardFilterDialog.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
