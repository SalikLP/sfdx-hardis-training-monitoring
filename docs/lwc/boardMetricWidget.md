<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardMetricWidget

<!-- LWC description -->

## JS Documentation

### NUMERIC_VALUE_TYPES

Schema.DisplayType names whose aggregate may arrive as a numeric string (high-precision Decimal).

**Kind**: global constant  
**Default**: <code>new Set(['CURRENCY', 'DOUBLE', 'INTEGER', 'LONG', 'PERCENT'])</code>  

### requestMeasure(measure)

A Measure as the Metric query sends it: `{ aggregateFunction, valueFieldApiName, perField?, inner?, hidden?,
condition?, formula? }` (`perField` / `inner`: Average per record).

**Kind**: global function  

#### metricResult

Last rendered aggregate: `{ aggregateFunction, value, valueType, isComplete, processedRows, totalRows }`.

**Kind**: instance property of <code>BoardMetricWidget</code>  
**Default**: <code>null</code>  

#### _cursorProgress

Cursor-tier progress `{ percent, label, ... }` while a large scope loads; null otherwise.

**Kind**: instance property of <code>BoardMetricWidget</code>  
**Default**: <code>null</code>  

#### crossObjectNoticeData

The last result's `crossObjectNotices` (one per Cross-object measure).

**Kind**: instance property of <code>BoardMetricWidget</code>  
**Default**: <code>[]</code>  

#### _serverIgnoredIds

`ignoredFilterIds` of the last completed query; re-applied after every binding resolve.

**Kind**: instance property of <code>BoardMetricWidget</code>  
**Default**: <code>[]</code>  

#### livePreview

Setup dialog live preview: never waits for the Filter widget, whatever the config says.

**Kind**: instance property (getter) of <code>BoardMetricWidget</code>  
**Decorators**: <code>@api</code>  

#### acceptExternalContext(json)

Hands a reactive Flow `filterContextJson` input to the store, which scope- and precedence-checks it; the
subscription delivers accepted state. A rejected input is answered by echoing the actual context.

**Kind**: instance method of <code>BoardMetricWidget</code>  

#### syncContextOutput(ctx)

Echoes the Filter context to the Flow output `filterContextJson` when it changed.

**Kind**: instance method of <code>BoardMetricWidget</code>  

#### loadFields(objectApiName, refreshToken)

Describe per object, re-fetched when the Board `refreshToken` changes (busts the cacheable Apex result).

**Kind**: instance method of <code>BoardMetricWidget</code>  

#### requestQuery()

Resolves bindings and fires `queryMetric` unless the effective-query signature is unchanged.

**Kind**: instance async method of <code>BoardMetricWidget</code>  

#### aggregateCursorChunks(reqId, request, result)

Tier 2: merges `Database.Cursor` chunks; shows progress only and renders the final number once.

**Kind**: instance async method of <code>BoardMetricWidget</code>  

#### finishFormulaInputs(reqId, request, result)

A visible Formula measure whose inputs are still on the cursor tier: finishes each such input, then has the
server evaluate the formula from the completed input values (in the Display currency, with each input's ISO
code so a currency Formula measure reads its constants in the Config currency).

**Kind**: instance async method of <code>BoardMetricWidget</code>  

#### loadCursorValue(reqId, request, measure, firstChunk)

Merges the cursor chunks of one Measure; its final value, or undefined when the run was superseded.

**Kind**: instance async method of <code>BoardMetricWidget</code>  

#### applyBindingResolution(resolution)

Header disclosure: client binding resolution plus the filters the last completed query ignored server-side.

**Kind**: instance method of <code>BoardMetricWidget</code>  

#### waitingBoardId

Board id for the Wait for Filter widget hint card while this Widget waits, else empty.

**Kind**: instance property (getter) of <code>BoardMetricWidget</code>  

#### measures

The Measures list (a single-aggregate config is its one visible Measure).

**Kind**: instance property (getter) of <code>BoardMetricWidget</code>  

#### visibleMeasure

The one Measure the Metric shows; the others are hidden (fetched, not shown).

**Kind**: instance property (getter) of <code>BoardMetricWidget</code>  

#### crossObjectNoticeRows

Cross-object measures that are blank (no access) or ignore some of the Board's filters.

**Kind**: instance property (getter) of <code>BoardMetricWidget</code>  

#### isNoMatchingRecords

`AVG`/`MIN`/`MAX` over zero rows render "—" with "No matching records" and no threshold.

**Kind**: instance property (getter) of <code>BoardMetricWidget</code>  

#### gaugeResult

The Gauge of a `display: 'gauge'` Metric: `{ model }` or `{ error }`; null for the number display.

**Kind**: instance property (getter) of <code>BoardMetricWidget</code>  

#### cursorProgress

Progress bar state; only while the cursor tier of the latest run is loading.

**Kind**: instance property (getter) of <code>BoardMetricWidget</code>  

#### thresholdVariant

First matching ordered threshold rule's variant (amounts converted Config → Display currency), or null.

**Kind**: instance property (getter) of <code>BoardMetricWidget</code>  

#### temporalValue(value, valueType)

MIN/MAX over Date/DateTime fields; any other non-numeric value renders as text.

**Kind**: instance method of <code>BoardMetricWidget</code>  

#### handleShownStale()

Shown again after a Filter change while hidden: loading state instead of stale data, then one query.

**Kind**: instance method of <code>BoardMetricWidget</code>

## Files

- `boardMetricWidget.css`
- `boardMetricWidget.html`
- `boardMetricWidget.js`
- `boardMetricWidget.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
