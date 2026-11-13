<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardChartSetupSteps

<!-- LWC description -->

## JS Documentation

### CHART_TYPE_TILES

Chart types as picture tiles (`c-board-picture-tiles`), each drawn by its own illustration.

**Kind**: global constant  
**Default**: <code>CHART_TYPE_OPTIONS.map((option) =&gt; ({ ...option, illustration: option.value }))</code>  

### BoardChartSetupSteps

Step content of the Chart widget's Setup dialog (`c/boardSetupDialog`): the inputs of one step (`step`: `data`,
`chartType`, `measures`, `grouping`, `display` or `filterBindings`, see `CHART_STEPS` in `c/boardSetupSteps`) over
the dialog's draft (`config`).

- Data: the object and the Base filters (`c-board-setup-base-filters`).
- Chart type: the chart type (only its own settings are shown in later steps; the other types' settings are kept
  for a switch back) and the bar orientation.
- Measures: the Measures list (`c-board-cpe-measure-list`: up to 6, each with aggregate, field, label, number
  format and optional colour; several Measures or a Stack by field, never both).
- Grouping: Group by (+ date granularity for Date/DateTime fields), optional Stack by (series field), Bucket
  fields and Small multiples.
- Display: subtitle, sorting and overflow, legend and labels, and fixed colours.
- Filter bindings: `c-board-cpe-filter-bindings`.

Discrete choices (chart type, orientation, series layout, overflow) are picture tiles (`c-board-picture-tiles`);
every setting carries field-level help. The step's intro and worked example come from its descriptor and are shown
by the dialog.

Every edit fires `change` with `detail.patch` (merged into the draft by the dialog; null removes a key). Errors only
the server or the bindings editor knows (Formula build errors, a Filter binding switched to "Field path" without a
path) fire `steperrors` with `detail.step` and `detail.errors`.

`context`: `boardBucketFields` (the Board's Bucket fields, usable by id), `builderContext` and `elementInfo`
(Filter widget discovery for the Filter bindings).

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### config

The Setup dialog's draft config.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  
**Decorators**: <code>@api</code>  

#### groupByType

`Schema.DisplayType` of the Group by leaf field, once known.

**Kind**: instance property of <code>BoardChartSetupSteps</code>  
**Default**: <code>null</code>  

#### boardBucketFields

Bucket fields of the Board's Filter widget, usable by id.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### handleFormulaCheck(event)

FormulaEval build errors of the Formula measures, checked on the server by the Measures list.

**Kind**: instance method of <code>BoardChartSetupSteps</code>  

#### resolveGroupByType()

Describes the saved Group by path (e.g. after reopening the editor) to decide which options apply.

**Kind**: instance method of <code>BoardChartSetupSteps</code>  

#### panelField

The Panel field (Small multiples): a Cross-object measure maps a field of its source object to it too.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### handleChartType(event)

Only `chartType` changes: the other types' settings stay in the config, so switching back restores them.

**Kind**: instance method of <code>BoardChartSetupSteps</code>  

#### showBarSettings

Bar-only settings: stack mode and colour by category (orientation is in the shell).

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### isSingleMeasureType

Pie, donut and polarArea: one Measure, no series field, always coloured by category.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### showStackBy

Stack by is hidden for one-Measure types, unless a leftover value needs clearing.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### handleWaterfallColor(event)

A colour equal to its default is not stored, so the default keeps following the code.

**Kind**: instance method of <code>BoardChartSetupSteps</code>  

#### maxCategories

Max categories of the chart type; Small multiples show at most 50 per Panel.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### measureLabels

Each Measure's label for the panel sort: the Admin's label, else e.g. `Record Count` or `SUM of Amount`.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### categoryNoun

What a category is drawn as: `bars` on a bar chart, else `categories`.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### groupByPickerValue

The Group by field picker shows nothing while a Bucket field is the Group by.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### hasBucketFields

The Widget's own Bucket fields or the Board's (its Filter widget's), so the Bucket field pickers show.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### bucketOptions

The Widget's own Bucket fields, then the Board's not shadowed by an own one with the same id.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### handleBucketFields(event)

Writes the Bucket fields; a Group by, Stack by or Panel field on a removed Bucket field is cleared.

**Kind**: instance method of <code>BoardChartSetupSteps</code>  

#### stackByDisabled

Several Measures disable the Stack by field: a chart shows several Measures or one split by series.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### canShareCategory

Percent of category shares a category between its series or between several Measures.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>  

#### updateMeasures(measures)

Writes the Measures list; turning a Measure non-additive turns an "Other" bar into truncation.

**Kind**: instance method of <code>BoardChartSetupSteps</code>  

#### nonAdditiveFunction

The first Measure that can't be summed into "Other" (not COUNT or SUM), or null.

**Kind**: instance property (getter) of <code>BoardChartSetupSteps</code>

## Files

- `boardChartSetupSteps.html`
- `boardChartSetupSteps.js`
- `boardChartSetupSteps.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
