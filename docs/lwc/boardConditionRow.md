<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardConditionRow

<!-- LWC description -->

## JS Documentation

### convertValue(operator, value)

Carries a condition's value over to a new operator (list ↔ scalar, null check, relative date).

**Kind**: global function  

### BoardConditionRow

One condition of a condition tree (`{ id, fieldPath, operator, value }`): field, operator, and value inputs plus
its validation messages. Fires `rowchange` (`detail.condition`, the edited condition) and `rowremove`.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### objectApiName

Object the field picker starts from.

**Kind**: instance property of <code>BoardConditionRow</code>  
**Decorators**: <code>@api</code>  

#### errors

Validation messages of this condition.

**Kind**: instance property of <code>BoardConditionRow</code>  
**Decorators**: <code>@api</code>  

#### customLiteral

True while the relative date is typed as a custom literal.

**Kind**: instance property of <code>BoardConditionRow</code>  
**Default**: <code>false</code>

## Files

- `boardConditionRow.html`
- `boardConditionRow.js`
- `boardConditionRow.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
