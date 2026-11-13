<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardChartPanelGrid

<!-- LWC description -->

## JS Documentation

### BoardChartPanelGrid

Small multiples grid of the Chart widget: one titled Chart.js chart per Panel, laid out `panelsPerRow` per row
(fewer when a Panel would get narrower than ~200 px) at `panelHeight` px each, so the Widget grows with its rows and
never scrolls inside. The Panels share one value axis unless `independentScales`, and the grid draws one legend for
all of them (each chart's own legend is off).

The Widget hands in the Chart.js constructor (`chartLibrary`) and `buildConfigs()`, returning a fresh
`Map<panelKey, config>`; the grid calls it whenever `drawVersion` changes or its Panels change, then creates, morphs
in place, or destroys each Panel's chart.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### panels

`[{ key, label, headline }]`, in order (`headline`: the Panel headline text right of the title, or null).

**Kind**: instance property of <code>BoardChartPanelGrid</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>[]</code>  

#### legend

The one legend `{ position, items }`, or null.

**Kind**: instance property of <code>BoardChartPanelGrid</code>  
**Default**: <code>null</code>  

#### drawVersion

Bumped by the Widget when the Panels' data, settings or theme changed.

**Kind**: instance property (getter) of <code>BoardChartPanelGrid</code>  
**Decorators**: <code>@api</code>  

#### draw()

Draws every rendered Panel container once per `drawVersion` and set of containers.

**Kind**: instance method of <code>BoardChartPanelGrid</code>

## Files

- `boardChartPanelGrid.css`
- `boardChartPanelGrid.html`
- `boardChartPanelGrid.js`
- `boardChartPanelGrid.js-meta.xml`
- `panelLayout.js`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
