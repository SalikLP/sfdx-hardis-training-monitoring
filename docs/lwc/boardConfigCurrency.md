<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardConfigCurrency

<!-- LWC description -->

## JS Documentation

### BoardConfigCurrency

Config currency setting of the Filter widget's Setup dialog (its Currency step): a combobox of the org's active
currencies. Blank (the default) means the corporate currency. In a single-currency org it explains that there is
nothing to set.

Fires `change` (`detail: { value }`, an ISO code or null for the corporate default).

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### value

The saved Config currency ISO code; blank for the corporate currency.

**Kind**: instance property of <code>BoardConfigCurrency</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>''</code>  

#### isSingleCurrency

Known to be a single-currency org (unknown while loading).

**Kind**: instance property (getter) of <code>BoardConfigCurrency</code>

## Files

- `boardConfigCurrency.html`
- `boardConfigCurrency.js`
- `boardConfigCurrency.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
