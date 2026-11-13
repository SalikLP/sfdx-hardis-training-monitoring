<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardSetupBaseFilters

<!-- LWC description -->

## JS Documentation

### BoardSetupBaseFilters

Base filters of a data Widget inside its Setup dialog's Data step (ADR 0002): the shared condition editor
(`c-board-condition-editor`) over the draft's `baseFilters`, inline in the step (no modal in the modal). Every
Widget's step content embeds it the same way:

  `<c-board-setup-base-filters value={config.baseFilters} object-api-name={objectApiName} onchange={...}>`

and patches its draft with `{ baseFilters: detail.baseFilters.length ? detail.baseFilters : null }`. The Data step
(`dataStep` in `c/boardSetupSteps`) validates the Base filters and counts them in its summary.

Fires `change` with `detail.baseFilters` (the whole list) after every edit. OR at the top level is stored as one
OR group entry (`baseFiltersFromTree`); the first edit gives entries with a missing or duplicate id a fresh one.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### objectApiName

Object the field pickers start from.

**Kind**: instance property of <code>BoardSetupBaseFilters</code>  
**Decorators**: <code>@api</code>  

#### _fired

The list last fired (JSON), so the draft echoing it back keeps the tree (e.g. OR with no conditions yet).

**Kind**: instance property of <code>BoardSetupBaseFilters</code>  
**Default**: <code>null</code>  

#### value

The draft's `baseFilters`.

**Kind**: instance property (getter) of <code>BoardSetupBaseFilters</code>  
**Decorators**: <code>@api</code>

## Files

- `boardSetupBaseFilters.html`
- `boardSetupBaseFilters.js`
- `boardSetupBaseFilters.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
