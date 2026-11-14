<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeFilterBindings

<!-- LWC description -->

## JS Documentation

### BoardCpeFilterBindings

Filter bindings editor of a data Widget: the Filters of the Board's discovered Filter widgets (`builderContext`)
with their convention binding on the config's object, a binding mode per Filter (convention, field path, ignore),
and Filter ids added by hand for Filter widgets outside this Flow. Used in the Config editor panel and in the
Filter bindings step of the Setup dialog.

Reads `config` (`boardId`, `objectApiName`, `filterBindings`); fires `change` with `detail.filterBindings` (the
new map, or null when empty) and `bindingstate` with `detail.rows` and `detail.errors` (`[{ key, errorString }]`)
whenever its rows or errors may have changed.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### validate()

Design-time errors of the rows (`[{ key: 'filterBindings', errorString }]`).

**Kind**: instance method of <code>BoardCpeFilterBindings</code>  
**Decorators**: <code>@api</code>  

#### disconnectedCallback()

A "Field path" row still waiting for a path lives only here, so it is dropped when the editor goes away (the
Admin leaves the Setup dialog step): report the state without it, so its error doesn't outlive the row.

**Kind**: instance method of <code>BoardCpeFilterBindings</code>

## Files

- `boardCpeFilterBindings.html`
- `boardCpeFilterBindings.js`
- `boardCpeFilterBindings.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
