<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeMeasureList

<!-- LWC description -->

## JS Documentation

### movedIndexes(length, index, offset)

Old index → new index of every item after `moveItem(items, index, offset)`.

**Kind**: global function  

### SHOW_AS_ILLUSTRATIONS

Picture tile illustration (`c-board-picture-tiles`) of each Show as and Draw as choice.

**Kind**: global constant  
**Default**: <code>{...}</code>  

### BoardCpeMeasureList

Measures list editor shared by the Chart and Metric Config editors: up to `maxMeasures` Measures, each with
aggregate, value field, label, number format and an optional Measure condition (`condition`, edited with the shared
condition editor), plus an optional colour (`showColor`, Chart widget) and hidden flag (`showHidden`), and a Share
of total "Show as" choice for COUNT and SUM Measures (`showShareOfTotal`, Chart widget only; never on the Metric
widget). A Formula measure (`FORMULA`) takes formula text over the other Measures by slot (Measure 1 is A);
reordering or removing Measures keeps its references on the same Measures. Rows reorder by arrows or drag. Fires a
non-bubbling `change` event with `detail.measures` (the full edited list), and `formulacheck` with `detail.errors`
(the server's FormulaEval build errors, `Measure 2 (B) formula: …`) whenever they change. An Average per record
(`AVG_PER`) Measure adds its per-record lookup `perField` and how each record's value is taken, `inner`.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### addBlockedReason

Why no Measure can be added right now (e.g. a Stack by field is set); empty when adding is allowed.

**Kind**: instance property of <code>BoardCpeMeasureList</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>''</code>  

#### showHidden

A Hidden checkbox per Measure (fetched for calculations such as a Formula measure, not shown).

**Kind**: instance property of <code>BoardCpeMeasureList</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>false</code>  

#### singleVisible

Metric widget: exactly one Measure is visible, so added Measures start hidden.

**Kind**: instance property of <code>BoardCpeMeasureList</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>false</code>  

#### dateMinMax

MIN and MAX may also aggregate date and time fields (Metric widget).

**Kind**: instance property of <code>BoardCpeMeasureList</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>false</code>  

#### showShareOfTotal

Chart widget: a "Show as" (Share of total) choice per COUNT or SUM Measure.

**Kind**: instance property of <code>BoardCpeMeasureList</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>false</code>  

#### canShareCategory

Percent of category is offered: the chart has a series (Stack by) field or several Measures.

**Kind**: instance property of <code>BoardCpeMeasureList</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>false</code>  

#### defaultNotation

Notation the Widget uses when a Measure format leaves it unset, shown by the format editor.

**Kind**: instance property of <code>BoardCpeMeasureList</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>'standard'</code>  

#### chartType

Chart widget: its chart type; bar and line charts show Draw as and Value axis per Measure.

**Kind**: instance property of <code>BoardCpeMeasureList</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>''</code>  

#### showCategoryMapping

Chart widget: a Cross-object measure maps a field of its source object to the category.

**Kind**: instance property of <code>BoardCpeMeasureList</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>false</code>  

#### panelField

The Widget's Panel field (Small multiples): a Cross-object measure maps a field to it too.

**Kind**: instance property of <code>BoardCpeMeasureList</code>  
**Decorators**: <code>@api</code>  

#### _formulaMessages

Server build message per formula text (null: it builds).

**Kind**: instance property of <code>BoardCpeMeasureList</code>  
**Default**: <code>new Map()</code>  

#### drag

Drag-to-reorder state of the Measures list (see the drag helpers in c/boardCpeUtils).

**Kind**: instance property of <code>BoardCpeMeasureList</code>  
**Default**: <code>NO_DRAG</code>  

#### checkFormulas()

Builds new formula texts on the server (FormulaEval), then reports the current Measures' build errors.

**Kind**: instance async method of <code>BoardCpeMeasureList</code>  

#### moveMeasure(index, offset)

Moves a Measure; Formula measures keep pointing at the same Measures.

**Kind**: instance method of <code>BoardCpeMeasureList</code>  

#### handleMeasureCurrency(event)

A currency Formula measure returns an amount: converted to the Display currency, constants in Config currency.

**Kind**: instance method of <code>BoardCpeMeasureList</code>  

#### handleMeasureFormula(event)

`input` of the native Formula textarea (`event.target.value`).

**Kind**: instance method of <code>BoardCpeMeasureList</code>  

#### measureDisplayRow(measure)

Draw as (bars or line) and value axis of a Measure, shown only for chart types that draw combo charts.

**Kind**: instance method of <code>BoardCpeMeasureList</code>  

#### handleMeasureAxis(event)

The primary axis is the default, so it is not written.

**Kind**: instance method of <code>BoardCpeMeasureList</code>  

#### handleMeasureCrossObject(event)

Cross-object measure settings (`c-board-cpe-cross-object-measure` patch).

**Kind**: instance method of <code>BoardCpeMeasureList</code>  

#### handleMeasureCondition(event)

Measure condition from the shared condition editor; an emptied tree removes it.

**Kind**: instance method of <code>BoardCpeMeasureList</code>

## Files

- `boardCpeMeasureList.css`
- `boardCpeMeasureList.html`
- `boardCpeMeasureList.js`
- `boardCpeMeasureList.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
