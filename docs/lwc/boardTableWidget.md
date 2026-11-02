<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardTableWidget

<!-- LWC description -->

## JS Documentation

### MAX_TABLE_ROWS

Rows a `Database.PaginationCursor` spans at most; the count badge shows `100,000+` at the cap.

**Kind**: global constant  
**Default**: <code>100000</code>  

### SCROLL_THRESHOLD_PX

Distance (px) from the bottom of the scroll container that triggers the next page.

**Kind**: global constant  
**Default**: <code>48</code>  

### CURSOR_EXPIRED_PATH

`fieldPath` of the retryable `QUERY_ERROR` `fetchTablePage` raises when the held cursor expired.

**Kind**: global constant  
**Default**: <code>'paginationCursor'</code>  

### autoExpandedChildState(rows)

Child state of rows the server auto-expanded because the text search matched their child records. The seeded
rows are the matches only (`matchedOnly`); a manual re-expand fetches the full child list.

**Kind**: global function  

#### tableData

Loaded table: `{ columns, rows, paginationCursor, nextIndex, hasMore, totalCount, sortBy, sortDirection }`
(`BoardQueryService.TableResult` with later `fetchTablePage` rows appended).

**Kind**: global property  
**Default**: <code>null</code>  

#### _serverIgnoredIds

`ignoredFilterIds` of the last completed query; re-applied after every binding resolve.

**Kind**: global property  
**Default**: <code>[]</code>  

#### childState

Child sub-tables of the loaded query, keyed by parent row Id: `{ expanded, loading, result, error,
matchedOnly }` (`result` = `BoardQueryService.ChildRowsResult`). Cleared whenever `queryTable` loads a new
result, so filters, sorting, and refresh invalidate it.

**Kind**: global property  
**Default**: <code>{}</code>  

#### _sortOverride

End-user header sort (`{ sortBy, sortDirection }`); overrides the configured default until config changes.

**Kind**: global property  
**Default**: <code>null</code>  

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

#### loadMore()

Appends the next cursor page. An expired cursor is transparently re-opened by `queryTable` at the same
`start` (with a new `cursorGeneration` so the cacheable call is not served from cache).

**Kind**: global async function  

#### toggleChildRows(parentId)

Expands (lazily fetching once per loaded query) or collapses one parent row's child sub-table. Expanding a row
that holds only search-matched children (or a failed load) fetches the full child list.

**Kind**: global function  

#### fetchChildRows(parentId)

Fetches one parent row's full child list (expanded, with an inline spinner while loading).

**Kind**: global async function  

#### setChildRows(parentId, result)

Caches one parent row's full child rows for the loaded query (keeps its expanded state).

**Kind**: global function  

#### applyAutoExpanded(rows)

Expands rows whose child records matched the text search, with their batch-fetched matching children.

**Kind**: global function  

#### pageChildConfig(request)

`fetchTablePage` child config: the relationship plus search-matched child Ids so later pages auto-expand.

**Kind**: global function  

#### highlightPattern

`<mark>` pattern for the text search terms applied to this Table's loaded query.

**Kind**: instance property (getter)  

#### applyBindingResolution(resolution)

Header disclosure: client binding resolution plus the filters the last completed query ignored server-side.

**Kind**: global function  

#### childConfig

Normalized `childRelationship` sent to `queryTable`, `fetchTablePage`, and `queryChildRows`; null when the
Table has none or it is incomplete.

**Kind**: instance property (getter)  

#### requestedSort

Sort sent to `queryTable`: the end user's header choice, else the configured default.

**Kind**: instance property (getter)  

#### rowViews

Rendered rows: `{ key, id, cells[], hasChildren, child }`. With a child relationship, the first cell
renders the count badge + expand chevron, and an expanded row's `child` renders the sibling
`<tr colspan>` sub-row (`key: ${row.key}-children`).

**Kind**: instance property (getter)

## Files

- `boardTableWidget.css`
- `boardTableWidget.html`
- `boardTableWidget.js`
- `boardTableWidget.js-meta.xml`
- `tableCells.js`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
