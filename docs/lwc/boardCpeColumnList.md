<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeColumnList

<!-- LWC description -->

## JS Documentation

### DATA_BAR_TYPES

Field types a Data bar can draw (number, currency, percent).

**Kind**: global constant  
**Default**: <code>new Set(['INTEGER', 'LONG', 'DOUBLE', 'CURRENCY', 'PERCENT'])</code>  

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

#### bucketFields

The Widget's Bucket fields, offered as columns (`fieldPath: 'bucket:<id>'`).

**Kind**: instance property of <code>BoardCpeColumnList</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>[]</code>  

#### boardBucketFields

The Board's Bucket fields (of its Filter widget), offered too unless an own one has the same id.

**Kind**: instance property of <code>BoardCpeColumnList</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>[]</code>  

#### drag

Drag-to-reorder state (see the drag helpers in c/boardCpeUtils).

**Kind**: instance property of <code>BoardCpeColumnList</code>  
**Default**: <code>NO_DRAG</code>  

#### _typeByPath

Leaf field `dataType` per `object::path` (null when unknown), resolved lazily to offer Data bar.

**Kind**: instance property of <code>BoardCpeColumnList</code>  
**Default**: <code>{}</code>  

#### displayAsOptionsFor(column)

"Display as" options; Data bar only for number, currency and percent fields (or when already chosen).

**Kind**: instance method of <code>BoardCpeColumnList</code>  

#### bucketOptions

The Widget's own Bucket fields, then the Board's not shadowed by an own one with the same id.

**Kind**: instance property (getter) of <code>BoardCpeColumnList</code>  

#### bucketLabelOf(column)

A Bucket field column's Bucket field label (its id when unknown), or null for a field column.

**Kind**: instance method of <code>BoardCpeColumnList</code>  

#### handleAddBucket(event)

Adds a column showing a Bucket field's label per row.

**Kind**: instance method of <code>BoardCpeColumnList</code>

## Files

- `boardCpeColumnList.css`
- `boardCpeColumnList.html`
- `boardCpeColumnList.js`
- `boardCpeColumnList.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
