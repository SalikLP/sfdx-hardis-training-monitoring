<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeCrossObjectMeasure

<!-- LWC description -->

## JS Documentation

### BoardCpeCrossObjectMeasure

Cross-object measure settings of one Measure in the Measures list: whether its rows come from another object, that
source object, the field on it matching the Widget's category (`showCategoryMapping`, Chart widget) and Panel field
(`panelField`, Small multiples), its own Filter bindings (`filterBindings`: filter id → field path or IGNORE), and
the Data provider class supplying its values instead of the source object's query (`dataProvider`).
Fires a non-bubbling `change` event whose `detail.value` is a Measure patch (null removes a key); switching it off
removes every Cross-object key.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### measure

The Measure being edited.

**Kind**: instance property of <code>BoardCpeCrossObjectMeasure</code>  
**Decorators**: <code>@api</code>  

#### showCategoryMapping

Chart widget: the source object needs a field matching the category.

**Kind**: instance property of <code>BoardCpeCrossObjectMeasure</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>false</code>  

#### panelField

The Widget's Panel field (Small multiples), when it has one.

**Kind**: instance property of <code>BoardCpeCrossObjectMeasure</code>  
**Decorators**: <code>@api</code>  

#### isOpen

Toggled on before a source object is chosen.

**Kind**: instance property of <code>BoardCpeCrossObjectMeasure</code>  
**Default**: <code>false</code>  

#### showQuotaNote

ForecastingQuota read by the engine (no Data provider) follows the forecast hierarchy in USER_MODE: a static
note, with no runtime permission check.

**Kind**: instance property (getter) of <code>BoardCpeCrossObjectMeasure</code>

## Files

- `boardCpeCrossObjectMeasure.html`
- `boardCpeCrossObjectMeasure.js`
- `boardCpeCrossObjectMeasure.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
