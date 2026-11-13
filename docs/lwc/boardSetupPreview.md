<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardSetupPreview

<!-- LWC description -->

## JS Documentation

### PREVIEW_DEBOUNCE_MS

How long the draft has to stay unchanged before the preview Widget gets it.

**Kind**: global constant  
**Default**: <code>600</code>  

### BoardSetupPreview

Live preview pane of the Setup dialog (ADR 0002): renders the real Widget of `widgetType` (`chart`, `metric`,
`table`, `filter`) with the dialog's draft `config` and real data. The Filter widget shows its Filter bar with the
draft's defaults and `persistence` forced to `NONE`, publishing only on the preview Board id.

- The Widget gets a preview Board id unique to this pane and kept for its lifetime (one per dialog), so no Filter
  widget ever publishes on it: the Filter context is a fixed empty one and Base filters still apply. The Widget
  unsubscribes from the context store when it unmounts (pane hidden, dialog closed).
- `livePreview` forces *Wait for Filter widget* off, whatever the draft says.
- Draft changes reach the Widget once the draft has been unchanged for `PREVIEW_DEBOUNCE_MS`; the Widget stays
  mounted between updates and keeps showing its last result while it re-queries, so the pane doesn't flicker.
- Query errors render through the Widget's own error state.
- The pane is collapsible: hiding it unmounts the Widget, showing it remounts it with the latest draft (a fresh
  query). Each toggle fires `previewtoggle` with `detail.open`, so the host can resize its columns.

**Kind**: global class  
**Extends**: <code>LightningElement</code>

## Files

- `boardSetupPreview.css`
- `boardSetupPreview.html`
- `boardSetupPreview.js`
- `boardSetupPreview.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
