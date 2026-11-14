<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardTableSetupSteps

<!-- LWC description -->

## JS Documentation

### DEFAULT_ROW_LIMIT

The Row limit a "Top N" tile starts with.

**Kind**: global constant  
**Default**: <code>10</code>  

### BoardTableSetupSteps

Step content of the Table widget's Setup dialog (`c/boardSetupDialog`): the inputs of one step (`step`: `data`,
`columns`, `grouping`, `summaries`, `display`, `rowActions` or `filterBindings`, see `TABLE_STEPS` in
`c/boardSetupSteps`) over the dialog's draft (`config`).

- Data: the object and the Base filters (`c-board-setup-base-filters`).
- Columns: the column list (`c-board-cpe-column-list`: field paths, Bucket columns, Data bars, link to record) and
  the Widget's Bucket fields.
- Grouping: Row grouping, one or two levels (date granularity, group order, order field), a Bucket field as group
  field with Detail rows off, Detail rows on / off and ordering groups by a summary.
- Summaries: the Total row with Stacked summaries (`c-board-cpe-total-row`) and Subtotals.
- Display: default sort, page size, Row limit and row count.
- Row actions: `c-board-cpe-row-action-list` (View, Edit, Create, Screen Flow).
- Filter bindings: `c-board-cpe-filter-bindings`.

Row limit, Detail rows and Subtotals are picture tiles (`c-board-picture-tiles`); every setting carries field-level
help. Every edit fires `change` with `detail.patch` (merged into the draft by the dialog; null removes a key). A
Filter binding switched to "Field path" without a path fires `steperrors` with `detail.step` and `detail.errors`.

`context`: `builderContext` and `elementInfo` (Filter widget discovery for the Filter bindings).

**Kind**: global class  
**Extends**: <code>SetupStepContent</code>  

#### config

The Setup dialog's draft config.

**Kind**: instance property (getter)  
**Decorators**: <code>@api</code>  

#### groupFieldTypes

`Schema.DisplayType` of each group field, by `Object::path`, once known (decides the date granularity box).

**Kind**: global property  
**Default**: <code>{}</code>  

#### boardBucketFields

Bucket fields of the Board's Filter widget, usable as columns by id.

**Kind**: instance property (getter)  

#### handleBucketFields(event)

Writes the Bucket fields; the columns and group field of a removed Bucket field go with it.

**Kind**: global function  

#### resolveGroupFieldTypes()

Describes saved group fields (e.g. after reopening the dialog) to know which are dates.

**Kind**: global function  

#### groupEntries

The configured group fields, first level first.

**Kind**: instance property (getter)  

#### groupLevels

One editor block per group level: the configured ones, plus an empty "Then group by" below a single level (none
below a Bucket field, which groups an aggregated table by itself).

**Kind**: instance property (getter)  

#### groupsByBucket

True when the first group field is a Bucket field (`bucket:<id>`).

**Kind**: instance property (getter)  

#### showBucketGroup

Offered with Detail rows off; kept visible while a flagged Bucket group (Detail rows on) is set.

**Kind**: instance property (getter)  

#### bucketGroupFieldOptions

The Widget's own Bucket fields, then the Board's not shadowed by an own one with the same id.

**Kind**: instance property (getter)  

#### handleBucketGroup(event)

Groups by a Bucket field (one level, no order field), or clears the group field when blank.

**Kind**: global function  

#### handleGroupField(event)

A new group field keeps the level's group order but drops its granularity and order field; blank removes it.

**Kind**: global function  

#### updateGroupEntries(entries)

Defaults (ascending order, Day granularity, order by group value) are left out of the config.

**Kind**: global function  

#### detailRows

Detail rows on (default): records under their Group rows; off: only Group rows, an aggregated table.

**Kind**: instance property (getter)  

#### showSummaryOrder

Summary group order: offered with Detail rows off, and kept visible while a flagged one is set.

**Kind**: instance property (getter)  

#### summaryOrder

`columnId:FUNCTION` of the summary groups are ordered by, or `''` for the group value.

**Kind**: instance property (getter)  

#### summaryOrderOptions

`Group value`, then one option per summary the columns show (`Sum of Amount`).

**Kind**: instance property (getter)  

#### handleSummaryOrder(event)

Orders the first-level groups by a summary (Detail rows off), or by the group value when blank.

**Kind**: global function  

#### showSubtotalsSetting

Subtotals close groups of records: offered with Row grouping and Detail rows on.

**Kind**: instance property (getter)  

#### rowLimitMax

Largest Row limit: 200 groups with Row grouping and Detail rows on, else 2,000 rows or Group rows.

**Kind**: instance property (getter)  

#### rowLimitHelp

With Row grouping a Row limit counts first-level groups in the group order.

**Kind**: instance property (getter)

## Files

- `boardTableSetupSteps.html`
- `boardTableSetupSteps.js`
- `boardTableSetupSteps.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
