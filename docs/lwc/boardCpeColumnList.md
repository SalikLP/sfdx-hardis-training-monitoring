<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeColumnList

<!-- LWC description -->

## JS Documentation

### BoardCpeColumnList

Repeatable Table column editor (`fieldPath` with 1–5 hop parent paths, `label`, `displayAs`, `linkToRecord`,
`align`, `wrapText`, `width`, `hideOnNarrow`, `format`) used for Table columns and child-relationship columns.
Fires a non-bubbling `change` event with `detail.columns` (the full, re-ordered/edited array).

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### idPrefix

Prefix of generated column ids (`col1`, `col2`, …).

**Kind**: instance property of <code>BoardCpeColumnList</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>'col'</code>  

#### drag

Drag-to-reorder state (see the drag helpers in c/boardCpeUtils).

**Kind**: instance property of <code>BoardCpeColumnList</code>  
**Default**: <code>NO_DRAG</code>

## Files

- `boardCpeColumnList.css`
- `boardCpeColumnList.html`
- `boardCpeColumnList.js`
- `boardCpeColumnList.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
