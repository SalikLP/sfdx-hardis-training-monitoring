<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardPictureTiles

<!-- LWC description -->

## JS Documentation

### BoardPictureTiles

Picture tiles: a single choice shown as small pictures of what each option looks like (Setup dialog, ADR 0002).
A drop-in for a `lightning-radio-group`: a fieldset of native radios, so it is keyboard operable (Tab into the
group, arrow keys move the choice) and read as a radio group with the option labels as names.

- `label`: the group label (its legend); `fieldLevelHelp`: help text shown next to it
- `options`: `[{ label, value, illustration, disabled }]`; `illustration` is the name of a shipped illustration
  (see `illustrations.js`) or paths given as data, `[{ d, tone }]`; a tile without one shows its label only
- `value`: the selected option's value; `disabled`: disables every tile

Fires `change` with `detail.value` when the Admin picks a tile.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### name

One radio group per picker, so arrow keys stay inside it (the synthetic shadow shares the document).

**Kind**: instance property of <code>BoardPictureTiles</code>  
**Default**: <code>`c-picture-tiles-${++instanceCount}`</code>

## Files

- `boardPictureTiles.css`
- `boardPictureTiles.html`
- `boardPictureTiles.js`
- `boardPictureTiles.js-meta.xml`
- `illustrations.js`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
