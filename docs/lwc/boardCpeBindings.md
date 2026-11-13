<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeBindings

<!-- LWC description -->

## JS Documentation

### parameterValue(field, name)

Literal string value of a screen field input parameter (`{ value }` or metadata `{ value: { stringValue } }`).

**Kind**: global function  

### discoverFilterWidgets(builderContext, elementInfo, boardId)

Finds `boardFilterWidget` screen fields with a matching Board id in Flow Builder's `builderContext`
(`screens -> fields`, recursing into Section regions). Scans the screen holding `elementInfo.apiName`; when that
screen cannot be located (e.g. an unsaved screen), scans every screen.

**Kind**: global function  

### previewConventionBindings({ objectApiName, fields, filters, includeRecordContext, bucketFields, boardBucketFields }) ⇒ <code>Map&lt;string, {status: 'BOUND'</code> \| <code>'RUNTIME'</code> \| <code>'SOSL'</code> \| <code>'BUCKET'</code> \| <code>'UNBOUND', fieldPath: string</code> \| <code>null, bucketLabel?: string}&gt;</code>

Convention binding (no `filterBindings` overrides) of each discovered filter on `objectApiName`. A Bucket filter
binds to its Bucket field (the Widget's own `bucketFields` first, else the Board's `boardBucketFields`).

**Kind**: global function  
**Returns**: <code>Map&lt;string, {status: 'BOUND'</code> \| <code>'RUNTIME'</code> \| <code>'SOSL'</code> \| <code>'BUCKET'</code> \| <code>'UNBOUND', fieldPath: string</code> \| <code>null, bucketLabel?: string}&gt;</code>  

### bindingsOf(config)

The `filterBindings` of a config, or `{}`.

**Kind**: global function  

### hasPathBinding(bindings, filterId)

True when `filterId` has a non-IGNORE path binding in `bindings`.

**Kind**: global function  

### discoveryMessage(discovery, boardId, objectApiName)

The Admin-facing note on which Filter widgets were found for `boardId`.

**Kind**: global function  

### bindingRows(state)

The Filter binding rows of a data Widget: every Filter of the discovered Filter widgets (plus Record context when
one scopes it), then the bound or manually added filter ids. Each row carries its mode, path, convention preview,
effective binding, `status` (`bound` / `unbound` / `ignored`) and `error`.

`state`: `{ discovery, bindings, objectApiName, previewFields, previewLoading, previewError, pendingPathIds,
manualFilterIds, bucketFields }`; `pendingPathIds` are rows switched to "Field path" without a path yet;
`bucketFields` are the Widget's own Bucket fields (the Board's come from the discovered Filter widgets).

**Kind**: global function  

### bindingRowErrors(rows, bindings, [pendingPathIds])

Design-time errors of the binding rows: a "Field path" without a path, or a Team filter bound too deep.

**Kind**: global function

## Files

- `boardCpeBindings.js`
- `boardCpeBindings.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
