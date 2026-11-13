<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardFilterSetupSteps

<!-- LWC description -->

## JS Documentation

### BoardFilterSetupSteps

Step content of the Filter widget's Setup dialog (`c/boardSetupDialog`): the inputs of one step (`step`: `filters`,
`bucketFields`, `recordContext`, `persistence` or `currency`, see `FILTER_STEPS` in `c/boardSetupSteps`) over the
dialog's draft (`config`).

- Filters: the Filter definitions, Filter sections and the Currency picker item, master-detail inside the step
  (`c-board-setup-filter-definitions`).
- Bucket fields: the Board-level Bucket fields (`c-board-bucket-field-editor`) and the object their rule fields are
  picked from (`bucketObjectApiName`, design time only).
- Record context: the mode, the filter the record feeds into, the host record field path and the locked badge.
- Remember selections: the persistence of the viewer's selections.
- Currency: the Board's Config currency (`c-board-config-currency`).

Every edit fires `change` with `detail.patch` (merged into the draft by the dialog; null removes a key).

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### context

Not read by the Filter widget's steps; part of the step content seam.

**Kind**: instance property of <code>BoardFilterSetupSteps</code>  
**Decorators**: <code>@api</code>  

#### config

The Setup dialog's draft config.

**Kind**: instance property (getter) of <code>BoardFilterSetupSteps</code>  
**Decorators**: <code>@api</code>  

#### bucketObjectApiName

Object the rule conditions' field pickers start from (design time only; Widgets read their own object).

**Kind**: instance property (getter) of <code>BoardFilterSetupSteps</code>  

#### configCurrency

The Board's Config currency (blank: corporate).

**Kind**: instance property (getter) of <code>BoardFilterSetupSteps</code>

## Files

- `boardFilterSetupSteps.html`
- `boardFilterSetupSteps.js`
- `boardFilterSetupSteps.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
