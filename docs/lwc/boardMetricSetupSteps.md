<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardMetricSetupSteps

<!-- LWC description -->

## JS Documentation

### DISPLAY_ILLUSTRATIONS

Number vs Gauge as picture tiles (`c-board-picture-tiles`).

**Kind**: global constant  
**Default**: <code>{ [DISPLAY_NUMBER]: 'displayNumber', [DISPLAY_GAUGE]: 'displayGauge' }</code>  

### BoardMetricSetupSteps

Step content of the Metric widget's Setup dialog (`c/boardSetupDialog`): the inputs of one step (`step`: `data`,
`measures`, `display`, `thresholds` or `filterBindings`, see `METRIC_STEPS` in `c/boardSetupSteps`) over the
dialog's draft (`config`).

- Data: the object and the Base filters (`c-board-setup-base-filters`).
- Measures: the Measures list (`c-board-cpe-measure-list`: up to 6, exactly one visible, the others Hidden; each
  with aggregate, field, label, number format, Measure condition, Formula or Cross-object measure).
- Display: number vs Gauge as picture tiles, the Gauge's minimum, maximum and target (static or a Hidden Measure),
  and the subtitle.
- Thresholds: ordered rules (drag or Move up / down to reorder); on a Gauge they are its bands.
- Filter bindings: `c-board-cpe-filter-bindings`.

Every edit fires `change` with `detail.patch` (merged into the draft by the dialog; null removes a key). Errors only
the server or the bindings editor knows (Formula build errors, a Filter binding switched to "Field path" without a
path) fire `steperrors` with `detail.step` and `detail.errors`.

`context`: `builderContext` and `elementInfo` (Filter widget discovery for the Filter bindings).

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### config

The Setup dialog's draft config.

**Kind**: instance property (getter) of <code>BoardMetricSetupSteps</code>  
**Decorators**: <code>@api</code>  

#### defaultNotation

Widget default notation, shown by the format editor.

**Kind**: instance property of <code>BoardMetricSetupSteps</code>  
**Default**: <code>defaultNotationFor('metric')</code>  

#### drag

Drag-to-reorder state of the threshold rules (see the drag helpers in c/boardCpeUtils).

**Kind**: instance property of <code>BoardMetricSetupSteps</code>  
**Default**: <code>NO_DRAG</code>  

#### measures

The Measures list; a single-aggregate config shows as its one visible Measure.

**Kind**: instance property (getter) of <code>BoardMetricSetupSteps</code>  

#### handleMeasuresChange(event)

Writes the Measures list; a single-aggregate config's keys move into it on the first Measure edit.

**Kind**: instance method of <code>BoardMetricSetupSteps</code>  

#### handleFormulaCheck(event)

FormulaEval build errors of the Formula measures, checked on the server by the Measures list.

**Kind**: instance method of <code>BoardMetricSetupSteps</code>  

#### hiddenMeasureOptions

Hidden Measures a Gauge can read, labelled by their position in the list.

**Kind**: instance property (getter) of <code>BoardMetricSetupSteps</code>  

#### updateGauge(patch)

Writes the Gauge settings, dropping unset keys (and the whole object when empty).

**Kind**: instance method of <code>BoardMetricSetupSteps</code>

## Files

- `boardMetricSetupSteps.css`
- `boardMetricSetupSteps.html`
- `boardMetricSetupSteps.js`
- `boardMetricSetupSteps.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
