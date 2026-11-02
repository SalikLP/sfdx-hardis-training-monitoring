<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeFormatEditor

<!-- LWC description -->

## JS Documentation

### BoardCpeFormatEditor

ValueFormatConfig editor (`formatStyle`, `notation`, fraction digits, `currencyCode`, `prefix`, `suffix`) shared by
the Metric, Bar Chart, and Table column CPEs. Fires a non-bubbling `change` event with `detail.value`: the edited
format, or null once every setting is back to its default.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### defaultNotation

Widget default notation shown in the Notation picker: `standard` (Bar/Table) or `compact` (Metric).

**Kind**: instance property of <code>BoardCpeFormatEditor</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>'standard'</code>  

#### value

Current ValueFormatConfig (null/undefined = defaults).

**Kind**: instance property (getter) of <code>BoardCpeFormatEditor</code>  
**Decorators**: <code>@api</code>

## Files

- `boardCpeFormatEditor.html`
- `boardCpeFormatEditor.js`
- `boardCpeFormatEditor.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
