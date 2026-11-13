<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardTableWidget

<!-- LWC description -->

## JS Documentation

### MAX_TABLE_ROWS

Rows a `Database.PaginationCursor` spans at most; the count badge shows `100,000+` at the cap.

**Kind**: global constant  
**Default**: <code>100000</code>  

### MAX_ROW_LIMIT

Largest Row limit (Top N) a Table accepts.

**Kind**: global constant  
**Default**: <code>2000</code>  

### SCROLL_THRESHOLD_PX

Distance (px) from the bottom of the scroll container that triggers the next page.

**Kind**: global constant  
**Default**: <code>48</code>  

### CURSOR_EXPIRED_PATH

`fieldPath` of the retryable `QUERY_ERROR` `fetchTablePage` raises when the held cursor expired.

**Kind**: global constant  
**Default**: <code>'paginationCursor'</code>  

### validRowLimit(value)

Row limit from config: a whole number from 1 to 2,000, else null (no limit).

**Kind**: global function  

### sortRowsClientSide(rows, fieldPath, sortDirection)

Stable client-side sort of loaded rows by one field; blank values sort last in either direction.

**Kind**: global function  

### bucketColumnRequestFields(config, columns)

`{ bucketFields }` with the Bucket fields the columns show or the Table groups by (`bucket:<id>`), or `{}` when
there are none.

**Kind**: global function  

#### tableData

Loaded table: `{ columns, rows, paginationCursor, nextIndex, hasMore, totalCount, sortBy, sortDirection }`
(`BoardQueryService.TableResult` with later `fetchTablePage` rows appended).

**Kind**: global property  
**Default**: <code>null</code>  

#### _cursorProgress

Detail rows off, cursor tier: progress `{ percent, label, ... }` while chunks load; null otherwise.

**Kind**: global property  
**Default**: <code>null</code>  

#### _serverIgnoredIds

`ignoredFilterIds` of the last completed query; re-applied after every binding resolve.

**Kind**: global property  
**Default**: <code>[]</code>  

#### _sortOverride

End-user header sort (`{ sortBy, sortDirection }`); overrides the configured default until config changes.

**Kind**: global property  
**Default**: <code>null</code>  

#### _groupDirectionOverride

End-user group order from the group column header; overrides the configured one until config changes.

**Kind**: global property  
**Default**: <code>null</code>  

#### _collapseAllGroups

Row grouping collapse: every group follows `_collapseAllGroups` except the toggled ones.

**Kind**: global property  
**Default**: <code>false</code>  

#### livePreview

Setup dialog live preview: never waits for the Filter widget, whatever the config says.

**Kind**: instance property (getter)  
**Decorators**: <code>@api</code>  

#### permissionsByObject

`{ updateable, createable }` per object API name, from `getObjectInfos` for the Edit targets and Create objects.

**Kind**: global property  
**Default**: <code>new Map()</code>  

#### acceptExternalContext(json)

Hands a reactive Flow `filterContextJson` input to the store, which scope- and precedence-checks it; the
subscription delivers accepted state. A rejected input is answered by echoing the actual context.

**Kind**: global function  

#### syncContextOutput(ctx)

Echoes the Filter context to the Flow output `filterContextJson` when it changed.

**Kind**: global function  

#### loadFields(objectApiName, refreshToken)

Describe per object, re-fetched when the Board `refreshToken` changes (busts the cacheable Apex result).

**Kind**: global function  

#### requestQuery()

Resolves bindings and opens a new cursor via `queryTable` unless the effective-query signature is unchanged.

**Kind**: global async function  

#### followAggregateChunks(reqId, request, first)

Detail rows off, cursor tier: reads every chunk with a progress bar; null when a newer run superseded it.

**Kind**: global function  

#### loadMore()

Appends the next cursor page. An expired cursor is transparently re-opened by `queryTable` at the same
`start` (with a new `cursorGeneration` so the cacheable call is not served from cache).

**Kind**: global async function  

#### fetchNextPage(request, data)

Next cursor page; a grouped Table's page also carries the full-group counts of its groups, and a Table with
Bucket field columns needs the request so the server can label the page's rows.

**Kind**: global function  

#### highlightPattern

`<mark>` pattern for the text search terms applied to this Table's loaded query.

**Kind**: instance property (getter)  

#### applyBindingResolution(resolution)

Header disclosure: client binding resolution plus the filters the last completed query ignored server-side.

**Kind**: global function  

#### rowActionsDisabled

Row actions show in the Setup dialog's Live preview but are disabled there (no navigation, no flow modal).

**Kind**: instance property (getter)  

#### rowActions

Configured Row actions the Table can run (view / edit / create / flow).

**Kind**: instance property (getter)  

#### permissionObjectApiNames

Objects whose Edit/Create permission the Row actions need, or `undefined` (wire idle) when there are none.

**Kind**: instance property (getter)  

#### rowLimit

Configured Row limit (Top N), or null; a limited Table is one bounded page that header clicks re-sort locally.

**Kind**: instance property (getter)  

#### requestedSort

Sort sent to `queryTable`: the end user's header choice, else the configured default (always, when limited).

**Kind**: instance property (getter)  

#### waitingBoardId

Board id for the Wait for Filter widget hint card while this Widget waits, else empty.

**Kind**: instance property (getter)  

#### cursorProgress

Cursor-tier progress of the latest run while it loads; null otherwise.

**Kind**: instance property (getter)  

#### isGroupedConfig

Row grouping configured: a Row limit then counts first-level groups, and header clicks re-query.

**Kind**: instance property (getter)  

#### headerViews

Column headers: the group column (Row grouping), the data columns, then the Row action columns.

**Kind**: instance property (getter)  

#### groupField

Resolved group field of a grouped Table (`{ fieldPath, labelPath, label, sortDirection }`), else null.

**Kind**: instance property (getter)  

#### isAggregate

Detail rows off: the Table shows only its Group rows (an aggregated table).

**Kind**: instance property (getter)  

#### showGroupCollapse

Collapse all / Expand all: grouped Tables with Detail rows on.

**Kind**: instance property (getter)  

#### rowViews

Rendered rows: `{ key, id, cells[] }` (data cells, then action cells).

**Kind**: instance property (getter)  

#### withGroupRowActions(views)

Group rows offer only the Row actions acting on the group's lookup record (`groupRowActions`).

**Kind**: global function  

#### totalRowView

Total row (sticky footer), or null when the Total row is off.

**Kind**: instance property (getter)  

#### toggleGroupOrder()

Group column header: flips the group order and keeps the within-group sort.

**Kind**: global function  

#### runRowAction(rowId, actionId)

View / Edit open the target record's standard page; Create opens the standard create modal pre-filled from the
row. The platform enforces CRUD/FLS. The Setup dialog's Live preview is inert: no action runs.

**Kind**: global function  

#### handleShownStale()

Shown again after a Filter change while hidden: loading state instead of stale data, then one query.

**Kind**: global function  

#### runFlowAction(action, row)

Opens the Screen Flow in a modal with the mapped row values; refreshes the Table only when the flow finishes.

**Kind**: global async function

## Files

- `aggregateCursor.js`
- `aggregateTable.js`
- `boardTableWidget.css`
- `boardTableWidget.html`
- `boardTableWidget.js`
- `boardTableWidget.js-meta.xml`
- `groupRowActions.js`
- `groupSummaries.js`
- `rowActions.js`
- `rowGrouping.js`
- `tableCells.js`
- `totalRow.js`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
