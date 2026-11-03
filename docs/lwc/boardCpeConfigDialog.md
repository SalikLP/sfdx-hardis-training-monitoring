<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeConfigDialog

<!-- LWC description -->

## JS Documentation

### BoardCpeConfigDialog

Config dialog (ticket 07 spike): a large `LightningModal` that edits a deep-copied draft of one part of a Widget
config and closes with `{ action: 'save', draft }` or `{ action: 'dismiss' }`. Open it through `openConfigDialog`
(`c/boardCpeUtils`), which also maps the header X / Escape (`undefined` result) to a dismiss.

The spike body edits the draft as JSON; a real Config dialog (e.g. Filter definitions) keeps this result contract
and footer but renders its own master-detail body.

**Kind**: global class  
**Extends**: <code>LightningModal</code>  

#### value

The Config part to edit (already deep-copied by `openConfigDialog`).

**Kind**: instance property of <code>BoardCpeConfigDialog</code>  
**Decorators**: <code>@api</code>  

#### validator

Optional `(draft) => errorString | null` check; Save stays disabled while it returns an error.

**Kind**: instance property of <code>BoardCpeConfigDialog</code>  
**Decorators**: <code>@api</code>

## Files

- `boardCpeConfigDialog.html`
- `boardCpeConfigDialog.js`
- `boardCpeConfigDialog.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
