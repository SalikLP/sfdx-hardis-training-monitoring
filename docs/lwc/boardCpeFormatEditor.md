<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeFormatEditor

<!-- LWC description -->

## JS Documentation

### isCustomized(format, defaultNotation)

Explicit values equal to the default (`formatStyle: 'number'`, the Widget's own notation) don't count as custom.

**Kind**: global function  

### BoardCpeFormatEditor

ValueFormatConfig editor (`formatStyle`, `notation`, fraction digits, `prefix`, `suffix`) shared by the Metric,
Chart, and Table column CPEs. There is no currency code: currency amounts are shown in the Board's Display currency
(a `currencyCode` saved by an older version is kept; Widgets format with the ISO code Apex returns instead). Collapsed, it shows one summary line (`Number format: Default (compact)`)
with a "Customize" link that reveals the controls; it starts expanded when any setting differs from the default
(an explicit default such as the Widget's own notation does not count).
Fires a non-bubbling `change` event with `detail.value`: the edited format, or null once every setting is back to its
default.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### defaultNotation

Widget default notation shown in the Notation picker: `standard` (Bar/Table) or `compact` (Metric).

**Kind**: instance property of <code>BoardCpeFormatEditor</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>'standard'</code>  

#### _expandedChoice

Open state chosen by the Admin (toggle, or editing a control), or null while it still follows the value: then
the controls show whenever a setting differs from the default. Once set, value updates never override it.

**Kind**: instance property of <code>BoardCpeFormatEditor</code>  
**Default**: <code>null</code>  

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
