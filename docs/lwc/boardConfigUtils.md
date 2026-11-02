<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardConfigUtils

<!-- LWC description -->

## JS Documentation

### FILTER_TYPES

`FilterEntry.type` values (spec §3).

**Kind**: global constant  
**Default**: <code>['PICKLIST', 'LOOKUP', 'USER', 'DATE_RANGE', 'TEXT']</code>  

### RECORD_CONTEXT_OVERRIDE_TYPES

Filter types a `LOCKED`/`DEFAULT` Record context override (`overrideFilterId`) can target.

**Kind**: global constant  
**Default**: <code>['PICKLIST', 'LOOKUP', 'USER']</code>  

### DATE_RANGE_OPERATORS

`DATE_RANGE` operators: relative literal or ISO bounds.

**Kind**: global constant  
**Default**: <code>['LITERAL', 'BETWEEN', 'GTE', 'LTE']</code>  

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
**Default**: <code>{ boardId: 'default', orientation: 'vertical' }</code>  

### parseAndMergeConfig(widgetType, rawConfigJson, [topLevelProps])

Versioned configJson (version: 1) parser, validator, and top-level @api property precedence merger.

**Kind**: global function  

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
**Returns**: <code>{ filters: Array, applied: Array&lt;{filterId, label, fieldPath}&gt;, ignored: Array&lt;{filterId, label}&gt;, error: object</code> \| <code>null }</code> - `filters` is the `BoardQueryService` request payload (sorted by filterId). `error` is a `CONFIG_ERROR` BoardErrorPayload for the first malformed explicit binding; Widgets render it instead of querying (the payload still carries that filter as explicit without a path, which the server rejects).  

| Param | Type | Description |
| --- | --- | --- |
| params | <code>object</code> |  |
| params.objectApiName | <code>string</code> | Widget object |
| params.fields | <code>Array</code> | `BoardSchemaService.getObjectFields(objectApiName)` (readable fields only) |
| params.filterContext | <code>object</code> | Board FilterContext |
| [params.filterBindings] | <code>object</code> | Widget `filterBindings` |
| [params.widgetId] | <code>string</code> | Widget id used to skip its own cross filters |

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
