<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardContextStore

<!-- LWC description -->

## JS Documentation

### escapeBoardIdForScope(boardId)

`%` and `:` are escaped in the boardId part so a boardId containing `::` never collides with another scope.

**Kind**: global function  

### resolveWidgetScope(boardId, recordId)

Scope a Widget reads: its explicit recordId, else the recordId a Filter widget registered for the Board.

**Kind**: global function  

### registerFilterWidget(boardId, recordId, [initialContextOverride], { definitions, userId } = {})

Marks the scope as owned by a Filter widget and sets the `INITIALIZING` barrier (clearing any previous scope
error). `definitions` (normalized FilterDefinitions) and `userId` let `acceptExternalFilterContext` validate
external filter entries against the Filter widget's configuration.

**Kind**: global function  

### updateFilterContext(boardId, recordId, partialUpdate)

Test seam: merges a partial update into a scope (defaults `recordId` to the Board's Filter widget recordId).

**Kind**: global function  

### setScopeWidgetError(boardId, recordId, errorPayload)

Sets (or clears, with `null`) a scope-wide error every Widget renders instead of data. The status is kept, so an
error raised during the `INITIALIZING` barrier keeps Widgets from ever querying the unscoped object.

**Kind**: global function  

### acceptExternalFilterContext(boardId, recordId, filterContextJson)

Applies a reactive Flow `filterContextJson` input to the caller's Board scope (`boardId` + `recordId`, defaulting
to the Board's Filter widget recordId). Returns true when the input was applied (or queued behind the Filter
widget's `INITIALIZING` barrier), false when rejected:
- malformed JSON, `version` other than 1, or a `status` other than `READY`;
- another scope: `boardId`, `scopeKey`, or `recordContext.recordId` differing from the caller's scope;
- stale or echoed: `updatedAt` not newer than the latest `READY` state since the Filter widget registered, or
  equal to the current state's `updatedAt`.
Accepted input merges `filters` per entry (validated against the Filter widget's definitions when one is
registered; `LOCKED` entries are never replaced), replaces `crossFilters`, and adopts a higher `refreshToken`.
`recordContext`, `error`, and `status` are never taken from the input; a scope without a Filter widget becomes
`READY`.

**Kind**: global function

## Files

- `boardContextStore.js`
- `boardContextStore.js-meta.xml`
- `filterPersistence.js`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
