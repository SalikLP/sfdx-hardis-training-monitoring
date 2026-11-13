<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardBucketFieldEditor

<!-- LWC description -->

## JS Documentation

### BoardBucketFieldEditor

Edits a Widget's Bucket fields (`bucketFields`, see `c/boardBucketFields`): each Bucket field's label, its ordered
rules (label, optional colour, and a condition tree in the shared condition editor; at most 25 rules, first match
wins) and its fallback bucket (label, default "Other", or leave rows matching no rule out).

Fires `change` with `detail.value`, the whole edited list, after every edit.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### objectApiName

Object the rule conditions' field pickers start from.

**Kind**: instance property of <code>BoardBucketFieldEditor</code>  
**Decorators**: <code>@api</code>  

#### customColourRules

Rules (`fieldIndex-ruleIndex`) switched to a custom hex while their colour is empty or a named one.

**Kind**: instance property of <code>BoardBucketFieldEditor</code>  
**Default**: <code>new Set()</code>

## Files

- `boardBucketFieldEditor.html`
- `boardBucketFieldEditor.js`
- `boardBucketFieldEditor.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
