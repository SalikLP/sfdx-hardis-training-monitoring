<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeRowActionList

<!-- LWC description -->

## JS Documentation

### BoardCpeRowActionList

Repeatable Table Row action editor (`id`, `label`, `icon`, `type`, `target`, `placement`, `columnLabel`).
Create actions use `object`, `recordTypeId` and `defaults` (`[{ field, rowField }]`) instead of `target`.
Screen Flow actions use `flowApiName` and `inputs` (`[{ name, rowField }]`, default `recordId` from `Id`).
`target` is blank for the row's own record, else a lookup field path. Fires a non-bubbling `change` event with
`detail.rowActions` (the full, re-ordered/edited array).

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### drag

Drag-to-reorder state (see the drag helpers in c/boardCpeUtils).

**Kind**: instance property of <code>BoardCpeRowActionList</code>  
**Default**: <code>NO_DRAG</code>  

#### handleType(event)

Create and Screen Flow actions have no lookup target; each type drops the other types' settings.

**Kind**: instance method of <code>BoardCpeRowActionList</code>  

#### patchInput(event, patch)

Patches (or, with a null patch, removes) one input of a Screen Flow action; an emptied list is dropped.

**Kind**: instance method of <code>BoardCpeRowActionList</code>  

#### patchDefault(event, patch)

Patches (or, with a null patch, removes) one default of an action; an emptied list is dropped.

**Kind**: instance method of <code>BoardCpeRowActionList</code>

## Files

- `boardCpeRowActionList.css`
- `boardCpeRowActionList.html`
- `boardCpeRowActionList.js`
- `boardCpeRowActionList.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
