<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardBarWidget

<!-- LWC description -->

## JS Documentation

#### _pendingExternalJson

A Flow `filterContextJson` input received before connect; handed to the store in `connectedCallback`.

**Kind**: instance property of <code>BoardBarWidget</code>  
**Default**: <code>''</code>  

#### barData

Last server result: `{ buckets, aggregateFunction, valueType, groupBy, stackBy, isComplete, ... }`.

**Kind**: instance property of <code>BoardBarWidget</code>  
**Default**: <code>null</code>  

#### chartModel

Rendered model derived from `barData` and the display settings (see `barModel.buildBarModel`).

**Kind**: instance property of <code>BoardBarWidget</code>  
**Default**: <code>null</code>  

#### _serverIgnoredIds

`ignoredFilterIds` of the last completed query, re-applied after every client-side binding resolve.

**Kind**: instance property of <code>BoardBarWidget</code>  
**Default**: <code>[]</code>  

#### filterContextJson

Reactive Flow input: handed to the Board context store, which checks scope and precedence before publishing.
The widget's own `filterContext` only ever comes from the store subscription.

**Kind**: instance property (setter) of <code>BoardBarWidget</code>  

#### acceptExternalContext(json)

Hands a Flow input to the store; a rejected input re-echoes the Board's actual context to the Flow output.

**Kind**: instance method of <code>BoardBarWidget</code>  

#### syncContextOutput(ctx)

Echoes the Filter context to the Flow output `filterContextJson` when it changed.

**Kind**: instance method of <code>BoardBarWidget</code>  

#### loadFields(objectApiName, refreshToken)

Describe per object, re-fetched when the Board `refreshToken` changes (it busts the cacheable Apex result).

**Kind**: instance method of <code>BoardBarWidget</code>  

#### requestQuery()

Resolves bindings and fires `queryBar` unless the effective-query signature is unchanged.

**Kind**: instance async method of <code>BoardBarWidget</code>  

#### aggregateCursorChunks(reqId, request, result)

Tier 2: merges grouped `Database.Cursor` chunks progressively; stops once a newer request starts.

**Kind**: instance async method of <code>BoardBarWidget</code>  

#### syncChart()

Creates the chart once per mounted canvas container, then morphs it in place with `chart.update()`. The EMPTY
state keeps the container mounted (hidden), so zero rows morph the existing chart to no bars and back.

**Kind**: instance method of <code>BoardBarWidget</code>  

#### rethemeChart()

Re-samples `--board-chart-*` colors after a possible color-scheme switch; repaints only when they changed.

**Kind**: instance method of <code>BoardBarWidget</code>  

#### isUnconfigured

No object or no group-by field yet: render the setup placeholder rather than an error.

**Kind**: instance property (getter) of <code>BoardBarWidget</code>  

#### showChartBody

READY and EMPTY keep the chart body (and its canvas) mounted; EMPTY only hides it behind the state card.

**Kind**: instance property (getter) of <code>BoardBarWidget</code>  

#### hasPartialResults

The server capped the grouped query (`hasMoreGroups`): bars, "Other" and totals may miss groups.

**Kind**: instance property (getter) of <code>BoardBarWidget</code>  

#### chartContainerStyle

Sets `--board-chart-height` so the narrow-card `@container` rule can still cap it.

**Kind**: instance property (getter) of <code>BoardBarWidget</code>  

#### tableColumns

Column headers after the category column: one per series, plus a Total for stacked/grouped series when the
aggregate is additive (COUNT/SUM); summing averages, minimums or maximums across series would be wrong.

**Kind**: instance property (getter) of <code>BoardBarWidget</code>

## Files

- `barModel.js`
- `boardBarWidget.css`
- `boardBarWidget.html`
- `boardBarWidget.js`
- `boardBarWidget.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
