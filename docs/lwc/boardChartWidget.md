<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardChartWidget

<!-- LWC description -->

## JS Documentation

### BUCKET_REFERENCE_LABELS

How a config key that may reference a Bucket field is named in messages.

**Kind**: global constant  
**Default**: <code>{ groupByField: 'Group by', stackByField: 'Stack by', panelField: 'Panel field' }</code>  

#### _pendingExternalJson

A Flow `filterContextJson` input received before connect; handed to the store in `connectedCallback`.

**Kind**: instance property of <code>BoardChartWidget</code>  
**Default**: <code>''</code>  

#### barData

Last server-shaped `BoardChartQuery.ChartResult` (categories, series, points, progress).

**Kind**: instance property of <code>BoardChartWidget</code>  
**Default**: <code>null</code>  

#### chartModel

Rendered model derived from `barData` and the display settings (see `chartModel.buildChartModel`).

**Kind**: instance property of <code>BoardChartWidget</code>  
**Default**: <code>null</code>  

#### panelModels

Small multiples: `[{ key, label, model }]`, one rendered model per Panel; null without a Panel field.

**Kind**: instance property of <code>BoardChartWidget</code>  
**Default**: <code>null</code>  

#### panelDrawVersion

Bumped whenever the Panels must be redrawn (data, display settings, theme).

**Kind**: instance property of <code>BoardChartWidget</code>  
**Default**: <code>0</code>  

#### _cursorProgress

Cursor-tier progress `{ percent, label, ... }` while a large scope loads; null otherwise.

**Kind**: instance property of <code>BoardChartWidget</code>  
**Default**: <code>null</code>  

#### _serverIgnoredIds

`ignoredFilterIds` of the last completed query, re-applied after every client-side binding resolve.

**Kind**: instance property of <code>BoardChartWidget</code>  
**Default**: <code>[]</code>  

#### _chartType

Chart type `_chart` was created with.

**Kind**: instance property of <code>BoardChartWidget</code>  
**Default**: <code>null</code>  

#### _scrollLayout

Scroll sizing of the bars (`boardChartUtils.computeScrollLayout`), measured from the rendered scroll container.

**Kind**: instance property of <code>BoardChartWidget</code>  
**Default**: <code>null</code>  

#### scrollAxis

Axis the bars scroll along (`x` vertical bars, `y` horizontal bars) or '' when everything fits.

**Kind**: instance property of <code>BoardChartWidget</code>  
**Default**: <code>''</code>  

#### livePreview

Setup dialog live preview: never waits for the Filter widget, whatever the config says.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  
**Decorators**: <code>@api</code>  

#### filterContextJson

Reactive Flow input: handed to the Board context store, which checks scope and precedence before publishing.
The widget's own `filterContext` only ever comes from the store subscription.

**Kind**: instance property (setter) of <code>BoardChartWidget</code>  

#### acceptExternalContext(json)

Hands a Flow input to the store; a rejected input re-echoes the Board's actual context to the Flow output.

**Kind**: instance method of <code>BoardChartWidget</code>  

#### syncContextOutput(ctx)

Echoes the Filter context to the Flow output `filterContextJson` when it changed.

**Kind**: instance method of <code>BoardChartWidget</code>  

#### loadFields(objectApiName, refreshToken)

Describe per object, re-fetched when the Board `refreshToken` changes (it busts the cacheable Apex result).

**Kind**: instance method of <code>BoardChartWidget</code>  

#### requestQuery()

Resolves bindings and fires `queryChart` unless the effective-query signature is unchanged.

**Kind**: instance async method of <code>BoardChartWidget</code>  

#### followCursorChunks(reqId, request, first)

Draws a server-shaped result. In the cursor tier, follows `fetchChartChunk` with a progress bar: each response
is already shaped from every row read so far (the client never merges), and only the final one is drawn.

**Kind**: instance async method of <code>BoardChartWidget</code>  

#### panelHeadline(result, panelKey)

Small multiples: the Panel headline, e.g. `Avg Days to Close: 12.3` (its Panel total); null without one.

**Kind**: instance method of <code>BoardChartWidget</code>  

#### buildPanelConfigs()

Small multiples: a fresh Chart.js config per Panel (the panel grid shares scales and lifts the legend).

**Kind**: instance method of <code>BoardChartWidget</code>  

#### updateScrollLayout()

Measures the scroll container and derives the scroll layout; updates the reactive scroll state if it changed.

**Kind**: instance method of <code>BoardChartWidget</code>  

#### handleChartScroll(event)

Moves the pinned chart's category window to the scroll offset; the value axis and legend never move.

**Kind**: instance method of <code>BoardChartWidget</code>  

#### syncChart()

Creates the chart once per mounted canvas container, then morphs it in place with `chart.update()`. The EMPTY
state keeps the container mounted (hidden), so zero rows morph the existing chart to no bars and back.

**Kind**: instance method of <code>BoardChartWidget</code>  

#### rethemeChart()

Re-samples `--board-chart-*` colors after a possible color-scheme switch; repaints only when they changed.

**Kind**: instance method of <code>BoardChartWidget</code>  

#### isUnconfigured

No object or no group-by field yet: render the setup placeholder rather than an error.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### measures

The Widget config's Measures list (a config without one counts records).

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### effectiveOrientation

Bar orientation; other chart types are always laid out vertically.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### waitingBoardId

Board id for the Wait for Filter widget hint card while this Widget waits, else empty.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### measureLabel(index)

Measure `index`'s label: the Admin's label, else e.g. `Record Count` or `Sum of Amount`.

**Kind**: instance method of <code>BoardChartWidget</code>  

#### measuresLabel

Every Measure's label, for the accessible chart description and table caption.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### showChartBody

READY and EMPTY keep the chart body (and its canvas) mounted; EMPTY only hides it behind the state card.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### isPanelled

Small multiples: the result carries Panels.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### hasCutPanels

Panels beyond max panels were cut by the server.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### hasPartialResults

The server capped the grouped query (`hasMoreGroups`): bars, "Other" and totals may miss groups.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### crossObjectNoticeRows

Cross-object measures that are blank (no access) or ignore some of the Board's filters.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### chartContainerStyle

Sets `--board-chart-height` so the narrow-card `@container` rule can still cap it.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### spacerStyle

Gives the scroll container its full length along the category axis; empty while everything fits.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### tableColumns

Column headers after the category column: one per series, plus a Total for stacked/grouped series when the
aggregate is additive (COUNT/SUM); summing averages, minimums or maximums across series would be wrong.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### cursorProgress

Progress bar state; only while the cursor tier of the latest run is loading.

**Kind**: instance property (getter) of <code>BoardChartWidget</code>  

#### formatMeasure(value, [notation], [measureIndex])

Formats a value with the number format, value type and returned currency of Measure `measureIndex`.

**Kind**: instance method of <code>BoardChartWidget</code>  

#### handleShownStale()

Shown again after a Filter change while hidden: loading state instead of stale data, then one query.

**Kind**: instance method of <code>BoardChartWidget</code>

## Files

- `boardChartWidget.css`
- `boardChartWidget.html`
- `boardChartWidget.js`
- `boardChartWidget.js-meta.xml`
- `chartModel.js`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
