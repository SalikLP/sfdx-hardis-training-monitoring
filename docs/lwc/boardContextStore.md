<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardContextStore

<!-- LWC description -->

## JS Documentation

### displayCurrencies

Display currency per Board id (not persisted: a page load starts again from the viewer's currency).

**Kind**: global constant  
**Default**: <code>new Map()</code>  

### configCurrencies

Config currency per Board id, published by the Board's Filter widget (absent: the corporate currency).

**Kind**: global constant  
**Default**: <code>new Map()</code>  

### boardBucketFields

Board-level Bucket fields per Board id, published by the Board's Filter widget.

**Kind**: global constant  
**Default**: <code>new Map()</code>  

### waitingListeners

Filter context listeners subscribed with Wait for Filter widget on.

**Kind**: global constant  
**Default**: <code>new WeakSet()</code>  

### escapeBoardIdForScope(boardId)

`%` and `:` are escaped in the boardId part so a boardId containing `::` never collides with another scope.

**Kind**: global function  

### resolveWidgetScope(boardId, recordId)

Scope a Widget reads: its explicit recordId, else the recordId a Filter widget registered for the Board.

**Kind**: global function  

### commitState(entry, state, [isFallback])

`isFallback` marks the microtask fallback (no Filter widget, no explicit publish): Wait-for-Filter-widget
subscribers are not notified of it. Any explicit commit clears it.

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

### subscribeFilterContext(boardId, recordId, callback, { waitForFilterWidget = false } = {})

Subscribes `callback` to the caller's Board scope. With `waitForFilterWidget` on, the subscriber gets no `READY`
until a Filter widget registers on the Board id (or a Flow input / explicit publish sets the context): it never
falls back to an unfiltered context on its own, and never sees another subscriber's microtask fallback. With it
off, a scope without a Filter widget becomes `READY` (no filters) one microtask after subscribe, and a Filter
widget that registers later is still followed.

**Kind**: global function  

### getDisplayCurrency(boardId)

The Board's Display currency: the ISO code every Widget converts and formats currency amounts in. Defaults to the
viewer's own currency (the org currency in single-currency orgs). It never changes which records count.

**Kind**: global function  

### setDisplayCurrency(boardId, isoCode)

Sets the Board's Display currency (`null` or blank restores the viewer's currency). Published by the Filter
widget's Currency picker; not persisted. When it changes, every subscriber on the Board id is notified with its
unchanged Filter context, so Widgets re-query in the new Display currency (their query signature carries it).

**Kind**: global function  

### getConfigCurrency(boardId)

The Board's Config currency: the ISO code Admin-entered amounts (Metric thresholds, Base filter amounts) are written
in. Null means the org's corporate currency, which Apex resolves (a Board without a Filter widget, or a Filter widget
without the setting).

**Kind**: global function  

### setConfigCurrency(boardId, isoCode)

Publishes the Board's Config currency (`null` or blank: the corporate currency). Set by the Filter widget.

**Kind**: global function  

### getBoardBucketFields(boardId)

The Board-level Bucket fields (`[{ id, label, rules, fallback }]`, see `c/boardBucketFields`) a Widget can use by id
next to its own; a copy, empty when the Board's Filter widget defines none.

**Kind**: global function  

### setBoardBucketFields(boardId, bucketFields)

Publishes the Board-level Bucket fields (not a list, or empty: none). Set by the Filter widget.

**Kind**: global function

## Files

- `boardContextStore.js`
- `boardContextStore.js-meta.xml`
- `filterPersistence.js`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
