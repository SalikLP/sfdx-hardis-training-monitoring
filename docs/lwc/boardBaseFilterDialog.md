<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardBaseFilterDialog

<!-- LWC description -->

## JS Documentation

### convertValue(operator, value)

Carries a condition's value over to a new operator (list ↔ scalar, null check, relative date).

**Kind**: global function  

### BoardBaseFilterDialog

Base filters Config dialog: a large `LightningModal` that edits a draft of a data Widget's `baseFilters`
(master-detail: ordered conditions on the left, the selected condition's field, operator, and value on the right).
Open it with `openConfigDialog(BoardBaseFilterDialog, { label, description, value: baseFilters, objectApiName })`.

Closes with `{ action: 'save', draft: baseFilters }` or `{ action: 'dismiss' }`. Save stays disabled while any
draft condition breaks the Base filter validation rules (`baseFilterErrorsByIndex`).

**Kind**: global class  
**Extends**: <code>ConfigDialogMixin</code>  

#### value

The Widget's `baseFilters`, already deep-copied by `openConfigDialog`.

**Kind**: global property  
**Decorators**: <code>@api</code>  

#### objectApiName

Object the field picker starts from.

**Kind**: global property  
**Decorators**: <code>@api</code>  

#### _customLiteralKeys

Row keys whose relative date is being typed as a custom literal.

**Kind**: global property  
**Default**: <code>[]</code>  

#### withIds(conditions)

Gives conditions without an id (or with a duplicate one, e.g. hand-edited JSON) a fresh `bfN` id.

**Kind**: global function  

#### errorsByIndex

Messages per draft condition, from the shared Base filter validation rules.

**Kind**: instance property (getter)

## Files

- `boardBaseFilterDialog.css`
- `boardBaseFilterDialog.html`
- `boardBaseFilterDialog.js`
- `boardBaseFilterDialog.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
