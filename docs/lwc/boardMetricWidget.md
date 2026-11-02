<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardMetricWidget

<!-- LWC description -->

## JS Documentation

#### metricResult

Last rendered aggregate: `{ aggregateFunction, value, valueType, isComplete, processedRows, totalRows }`.

**Kind**: instance property of <code>BoardMetricWidget</code>  
**Default**: <code>null</code>  

#### _serverIgnoredIds

`ignoredFilterIds` of the last completed query; re-applied after every binding resolve.

**Kind**: instance property of <code>BoardMetricWidget</code>  
**Default**: <code>[]</code>  

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

Tier 2: merges `Database.Cursor` chunks progressively; stops as soon as a newer request starts.

**Kind**: instance async method of <code>BoardMetricWidget</code>  

#### applyBindingResolution(resolution)

Header disclosure: client binding resolution plus the filters the last completed query ignored server-side.

**Kind**: instance method of <code>BoardMetricWidget</code>  

#### isNoMatchingRecords

`AVG`/`MIN`/`MAX` over zero rows render "—" with "No matching records" and no threshold.

**Kind**: instance property (getter) of <code>BoardMetricWidget</code>  

#### thresholdVariant

First matching ordered threshold rule's variant (`success` | `warning` | `error`), or null.

**Kind**: instance property (getter) of <code>BoardMetricWidget</code>  

#### temporalValue(value, valueType)

MIN/MAX over Date/DateTime fields; any other non-numeric value renders as text.

**Kind**: instance method of <code>BoardMetricWidget</code>

## Files

- `boardMetricWidget.css`
- `boardMetricWidget.html`
- `boardMetricWidget.js`
- `boardMetricWidget.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
