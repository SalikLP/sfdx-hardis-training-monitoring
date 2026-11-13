<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardConditionEditor

<!-- LWC description -->

## JS Documentation

### BoardConditionEditor

The shared condition editor: edits one condition tree `{ logic: 'AND' | 'OR', conditions[] }`, where each entry is
a condition (`{ id, fieldPath, operator, value }`) or an AND / OR group (`{ id, logic, conditions[] }`) of
conditions. Base filters use it, and so can any other condition tree (e.g. Bucket rules).

Fires `conditionchange` with `detail.value`, the whole edited tree, after every edit. New entries get ids
`<idPrefix>N`, unique across the tree. Groups nested deeper than one level (hand-edited JSON) show read-only.

Top-level entries, and the conditions inside a group, reorder by dragging their handle (the shared drag helpers of
`c/boardCpeUtils`) or with Move up / Move down; an entry only moves within its own list.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### objectApiName

Object the field pickers start from.

**Kind**: instance property of <code>BoardConditionEditor</code>  
**Decorators**: <code>@api</code>  

#### idPrefix

Prefix of the ids of added conditions and groups.

**Kind**: instance property of <code>BoardConditionEditor</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>'c'</code>  

#### drag

Drag-to-reorder state; `scope` is the list being reordered (`root` or a group id).

**Kind**: instance property of <code>BoardConditionEditor</code>  
**Default**: <code>{ ...NO_DRAG, scope: null }</code>  

#### positionView(scope, baseClass, index, count)

Index, ends and row classes (drag markers) of entry `index` of the list `scope` (`count` entries).

**Kind**: instance method of <code>BoardConditionEditor</code>  

#### handleDragOver(event)

Rows only accept a drop from their own list (a group's condition never lands among the top-level entries).

**Kind**: instance method of <code>BoardConditionEditor</code>  

#### moveEntry(scope, index, offset)

Moves entry `index` of the list `scope` (`root` or a group id) by `offset`.

**Kind**: instance method of <code>BoardConditionEditor</code>  

#### updateEntry(id, update)

Replaces the entry `id` (top level or inside a group) with `update(entry)`.

**Kind**: instance method of <code>BoardConditionEditor</code>

## Files

- `boardConditionEditor.css`
- `boardConditionEditor.html`
- `boardConditionEditor.js`
- `boardConditionEditor.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
