<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardConfigUtils

<!-- LWC description -->

## JS Documentation

### FILTER_TYPES

`FilterEntry.type` values (spec §3).

**Kind**: global constant  
**Default**: <code>[...]</code>  

### CURRENCY_PICKER_ITEM

Item `type` of the Currency picker in a Filter widget's `filters` list (`{ type: 'currencyPicker', label? }`). Like
a Section item it is not a filter: never in the Filter context, never bound. At most one per Filter widget.

**Kind**: global constant  
**Default**: <code>'currencyPicker'</code>  

### filterItemsOf(config)

A Filter widget config's `filters` list, reading the older Board-level `currencyPicker: { label }` setting as a
Currency picker item at the end of the list (unless the list already has one).

**Kind**: global function  

### EMPTY_FILLED_OPERATORS

`EMPTY_FILLED` operators: `field = null` / `field != null`. All is the inactive filter (no condition).

**Kind**: global constant  
**Default**: <code>['EMPTY', 'FILLED']</code>  

### RECORD_CONTEXT_OVERRIDE_TYPES

Filter types a `LOCKED`/`DEFAULT` Record context override (`overrideFilterId`) can target.

**Kind**: global constant  
**Default**: <code>['PICKLIST', 'LOOKUP', 'USER']</code>  

### DATE_RANGE_OPERATORS

`DATE_RANGE` operators: relative literal or ISO bounds.

**Kind**: global constant  
**Default**: <code>['LITERAL', 'BETWEEN', 'GTE', 'LTE']</code>  

### NUMBER_RANGE_OPERATORS

`NUMBER_RANGE` operators: min and max (`BETWEEN`), min only (`GTE`) or max only (`LTE`).

**Kind**: global constant  
**Default**: <code>['BETWEEN', 'GTE', 'LTE']</code>  

### IGNORE_BINDING

`filterBindings` opt-out value.

**Kind**: global constant  
**Default**: <code>'IGNORE'</code>  

### DATE_PRESET_GROUPS

Grouped `DATE_RANGE` preset literals offered by the Filter bar and the Filter CPE (spec story 30).

**Kind**: global constant  
**Default**: <code>[...]</code>  

### DATE_PRESETS

Flat `{ value, label, group }` view of `DATE_PRESET_GROUPS`.

**Kind**: global constant  
**Default**: <code>DATE_PRESET_GROUPS.flatMap((group) =&gt;</code>  

### applyServerIgnoredFilters([applied], [ignored], [serverIgnoredIds]) ⇒ <code>{ applied: Array, ignored: Array }</code>

Moves binding-resolution entries the server reported in `ignoredFilterIds` from `applied` to `ignored`.
Widgets keep the ids from their last completed query and re-apply them after every client-side resolve, so the
header helptext stays correct when an unchanged query signature skips the Apex call.

**Kind**: global function  
**Returns**: <code>{ applied: Array, ignored: Array }</code>  

### METADATA_DEFAULTS

Top-level property values the `.js-meta.xml` design attributes pre-fill (`default="default"` /
`default="vertical"`). They don't count as explicit, so a pasted `configJson` can still set them. The defaults stay
in the metadata because the platform refuses to remove a property default that Flow versions reference.

**Kind**: global constant  
**Default**: <code>{ boardId: 'default' }</code>  

### metricMeasures(config)

A Metric widget's Measures list. A config without one (a single-aggregate Metric saved before the Measures list) is
one visible Measure built from its `aggregateFunction`, `valueFieldApiName` and `format` (default: count records).

**Kind**: global function  

### perRecordSettings(measure)

The Average per record settings a Measure sends to Apex: for an `AVG_PER` Measure its per-record lookup `perField`
and how each record's value is taken, `inner` (`SUM` of its rows, the default, or `ONCE`); none for other Measures.

**Kind**: global function  

### waitsForFilterWidget(config, [livePreview])

Whether a Widget waits for the Board's Filter widget before its first query: the `waitForFilterWidget` config key,
on unless explicitly `false`. The Setup dialog's live preview (`livePreview`) never waits.

**Kind**: global function  

### waitingForBoardId(config, livePreview, filterContext)

Board id a waiting Widget shows in its Wait for Filter widget hint card: set while the Widget waits and has no
Filter context yet, else empty.

**Kind**: global function  

### CHILD_ROWS_REMOVED_MESSAGE

Child rows were removed from the Table; a saved `childRelationship` is rejected, not migrated.

**Kind**: global constant  

### RECORD_CONTEXT_FILTER_ID

Filter binding resolution

Resolves every active Board filter (IMPLICIT Record context, `filters`, and `crossFilters` not published by this
Widget) against a Widget's `filterBindings` and object describe (`BoardSchemaService.getObjectFields`):
1. Explicit path (`"AccountId"`, `"Account.ParentId"`, `"CaseComment(ParentId).CreatedById"`) → bound, explicit.
2. `"IGNORE"` / `null` → ignored.
3. Convention: Step 1 exact `fieldApiName` (USER defaults to `OwnerId`); Step 2 (LOOKUP, USER, Record context)
   `Id` on the target object or the single filterable reference field to the target (excluding audit fields).
   Record context with an unknown object is sent without a path so `BoardQueryService` resolves Step 2 from the ID.
Any other explicit binding value (blank, non-string) fails closed with a `CONFIG_ERROR`.

**Kind**: global constant  
**Default**: <code>'$recordContext'</code>  

### collectActiveFilters(filterContext, [widgetId])

Active filter entries of a FilterContext that apply to the Widget identified by `widgetId`.

**Kind**: global function  

### resolveFilterBindings(params) ⇒ <code>{ filters: Array, applied: Array&lt;{filterId, label, fieldPath}&gt;, ignored: Array&lt;{filterId, label}&gt;, error: object</code> \| <code>null }</code>

**Kind**: global function  
**Returns**: <code>{ filters: Array, applied: Array&lt;{filterId, label, fieldPath}&gt;, ignored: Array&lt;{filterId, label}&gt;, error: object</code> \| <code>null }</code> - `filters` is the `BoardQueryService` request payload (sorted by filterId). `error` is a `CONFIG_ERROR` BoardErrorPayload for the first malformed explicit binding; Widgets render it instead of querying (the payload still carries that filter as explicit without a path, which the server rejects). A `BUCKET` filter binds to a Bucket field (`bucket:<id>`, by convention the filter's own): the Widget's own first, else the Board's. Its payload carries that Bucket field's config as `bucketField`; an unknown id is ignored by convention and a `CONFIG_ERROR` when explicit.  

| Param | Type | Description |
| --- | --- | --- |
| params | <code>object</code> |  |
| params.objectApiName | <code>string</code> | Widget object |
| params.fields | <code>Array</code> | `BoardSchemaService.getObjectFields(objectApiName)` (readable fields only) |
| params.filterContext | <code>object</code> | Board FilterContext |
| [params.filterBindings] | <code>object</code> | Widget `filterBindings` |
| [params.widgetId] | <code>string</code> | Widget id used to skip its own cross filters |
| [params.bucketFields] | <code>Array</code> | the Widget's own Bucket fields |
| [params.boardBucketFields] | <code>Array</code> | the Board-level Bucket fields (`getBoardBucketFields`) |

### buildFilterBindingSummary([applied], [ignored])

Header `<lightning-helptext>` text, or null when every active filter applies to the Widget.

**Kind**: global function  

### buildQuerySignature(request)

Canonical effective-query signature (key-order independent) used to skip redundant Apex calls.

**Kind**: global function  

### formatValue(value, [format], [options])

`Intl.NumberFormat` value formatter for `ValueFormatConfig`.

**Kind**: global function  

| Param | Type | Description |
| --- | --- | --- |
| value | <code>number</code> |  |
| [format] | <code>object</code> | ValueFormatConfig |
| [options] | <code>object</code> | `{ notation }` widget default, `{ valueType }` source `Schema.DisplayType` name (`PERCENT` field values are stored as whole percentages and are divided by 100 for `formatStyle: 'percent'`). |

### formatTemporal(value, displayAs)

Locale-formats a Date or DateTime value. An ISO `yyyy-mm-dd` Date renders in UTC so it never shifts a day; other
values render in the user's time zone. Returns the raw value as text when it cannot be parsed.

**Kind**: global function  

| Param | Type | Description |
| --- | --- | --- |
| value | <code>string</code> | non-empty Date/DateTime value |
| displayAs | <code>'date'</code> \| <code>'datetime'</code> |  |

## Files

- `boardConfigUtils.js`
- `boardConfigUtils.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
