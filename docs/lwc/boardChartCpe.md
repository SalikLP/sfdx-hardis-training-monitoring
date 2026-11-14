<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardChartCpe

<!-- LWC description -->

## JS Documentation

### BoardChartCpe

Flow Custom Property Editor for the Board Chart widget (ADR 0002). The panel is an overview inside the shared
`c-board-cpe-common` shell: Board (Board id, title, *Wait for Filter widget*), one summary
line per step of the Chart widget's Setup dialog (Data, Chart type, Measures, Grouping, Display, Filter bindings)
with "Edit…" opening the dialog at that step, and Advanced: Config JSON. Every other setting (Base filters too, in
the Data step) is edited in the Setup dialog's steps (`c-board-chart-setup-steps`).

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### groupByType

`Schema.DisplayType` of the Group by leaf field, once known (the Grouping summary shows its granularity).

**Kind**: instance property of <code>BoardChartCpe</code>  
**Default**: <code>null</code>  

#### stepContext

What the step summaries can't read from the config: the Group by field type.

**Kind**: instance property (getter) of <code>BoardChartCpe</code>  

#### resolveGroupByType()

Describes the saved Group by path to decide whether the Grouping summary shows a date granularity.

**Kind**: instance method of <code>BoardChartCpe</code>

## Files

- `boardChartCpe.html`
- `boardChartCpe.js`
- `boardChartCpe.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
