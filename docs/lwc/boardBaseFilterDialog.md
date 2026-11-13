<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardBaseFilterDialog

<!-- LWC description -->

## JS Documentation

### BoardBaseFilterDialog

Base filters Config dialog: a large `LightningModal` that edits a draft of a data Widget's `baseFilters` with the
shared condition editor (`c-board-condition-editor`): conditions and AND / OR groups of conditions, matched with
AND or OR at the top level. Open it with
`openConfigDialog(BoardBaseFilterDialog, { label, description, value: baseFilters, objectApiName })`.
Widgets with a Setup dialog edit their Base filters in its Data step instead (`c-board-setup-base-filters`).

`baseFilters` stays a list whose entries combine with AND (so existing flat lists load as one AND group); OR at the
top level is stored as a single OR group entry `{ id, logic: 'OR', conditions }` (`baseFiltersToTree` /
`baseFiltersFromTree`).

Closes with `{ action: 'save', draft: baseFilters }` or `{ action: 'dismiss' }`. Save stays disabled while any
draft entry breaks the Base filter validation rules (`baseFilterErrorsByIndex`).

**Kind**: global class  
**Extends**: <code>ConfigDialogMixin</code>  

#### value

The Widget's `baseFilters`, already deep-copied by `openConfigDialog`.

**Kind**: global property  
**Decorators**: <code>@api</code>  

#### objectApiName

Object the field pickers start from.

**Kind**: global property  
**Decorators**: <code>@api</code>  

#### tree

The condition tree being edited: `{ logic, conditions }`.

**Kind**: global property  
**Default**: <code>{ logic: 'AND', conditions: [] }</code>  

#### rootGroupId

Id of the stored top-level OR group, kept when it is saved again.

**Kind**: global property  
**Default**: <code>null</code>  

#### draftItems

The dialog has no master list: the condition editor edits the whole tree.

**Kind**: instance property (getter)

## Files

- `boardBaseFilterDialog.css`
- `boardBaseFilterDialog.html`
- `boardBaseFilterDialog.js`
- `boardBaseFilterDialog.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
