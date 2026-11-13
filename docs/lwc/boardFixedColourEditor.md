<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardFixedColourEditor

<!-- LWC description -->

## JS Documentation

### BoardFixedColourEditor

Edits a Chart widget's fixed colours (`fixedColours`, see `c/boardChartColours`): each pins a colour to a stored
value (picklist API value or record Id). The colour is picked from the named SLDS colour set; a custom hex is the
advanced option, with a warning when its contrast is below 3:1 on the light or dark surface.

Fires `change` with `detail.value`, the whole edited list, after every edit.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### customRows

Rows switched to a custom hex while their colour is still a named one.

**Kind**: instance property of <code>BoardFixedColourEditor</code>  
**Default**: <code>new Set()</code>

## Files

- `boardFixedColourEditor.css`
- `boardFixedColourEditor.html`
- `boardFixedColourEditor.js`
- `boardFixedColourEditor.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
