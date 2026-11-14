<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardSetupDialog

<!-- LWC description -->

## JS Documentation

### BODY_PADDING_PX

The modal body's top and bottom padding (1rem each), when it can't be measured.

**Kind**: global constant  
**Default**: <code>32</code>  

### BoardSetupDialog

Setup dialog of one Widget (ADR 0002): a full-size `LightningModal` with a vertical step nav on the left and the
current step's content in the middle and a collapsible live preview of the draft on the right
(`c-board-setup-preview`, the width the step content leaves when open). The steps are the Widget's step descriptors
(`c/boardSetupSteps`); the content of each step comes from the Widget's step editor (`c-board-chart-setup-steps`,
`c-board-metric-setup-steps`, `c-board-table-setup-steps`, `c-board-filter-setup-steps`).

Open with `BoardSetupDialog.open({ size: 'full', label, widgetType, config, context, startStep })`:
- `config`: the Widget config; the dialog edits one deep-copied draft of it across all steps
- `context`: what the step validators and step content read besides the config (`references`,
  `boardBucketFields`, `bindingRows`, `builderContext`, `elementInfo`)
- `startStep`: the step to open at (the first step when unknown)

Each step opens with its descriptor's intro and worked example, above the step content.

The nav shows each step as done (visited and valid), invalid (its validator over the whole draft, or errors its
content reports through `steperrors`, fails) or not visited. Save is disabled while any step is invalid and
resolves `{ action: 'save', config }` with the whole draft; Cancel, Escape and the header X resolve
`{ action: 'dismiss' }` and discard the draft.

A step editor gets `step`, `config` (the draft) and `context`, and fires `change` with `detail.patch` (shallow
merged into the draft; null removes a key) and `steperrors` with `detail.step` and `detail.errors` (messages).

A Widget with no config yet opens in Guided mode (`c/boardSetupGuide`) at the first step: Back / Next walk the
steps in order, Next is blocked while a required step is invalid and the steps after it are locked in the nav;
optional steps can be skipped. Otherwise the Admin moves freely between steps.

The dialog describes the draft's object (`context.objectFields`), so an upstream change (a different object)
flags the later steps whose fields aren't on it invalid; their settings are kept.

**Kind**: global class  
**Extends**: <code>LightningModal</code>  

#### reportedErrors

Errors reported by the step content (`steperrors`) per step name, e.g. a Formula the server rejects.

**Kind**: instance property of <code>BoardSetupDialog</code>  
**Default**: <code>{}</code>  

#### previewOpen

Whether the live preview pane (`c-board-setup-preview`) is shown; collapsed it keeps only its toggle.

**Kind**: instance property of <code>BoardSetupDialog</code>  
**Default**: <code>true</code>  

#### guided

Guided mode: linear Back / Next (a Widget with no config yet).

**Kind**: instance property of <code>BoardSetupDialog</code>  
**Default**: <code>false</code>  

#### objectDescribe

Field describes of the draft's object, once loaded: `{ objectApiName, fields }`.

**Kind**: instance property of <code>BoardSetupDialog</code>  
**Default**: <code>null</code>  

#### describeDraftObject()

Loads the field describes of the draft's object, for the validators' `context.objectFields`.

**Kind**: instance method of <code>BoardSetupDialog</code>  

#### errorsOf(step)

The step's errors over the whole draft, plus the ones its content reported.

**Kind**: instance method of <code>BoardSetupDialog</code>  

#### guide

Guided mode navigation from the current step (`c/boardSetupGuide`), or null with free navigation.

**Kind**: instance property (getter) of <code>BoardSetupDialog</code>  

#### currentErrors

The current step's errors; one of a retired setting (`step.retired`) carries the keys that remove it.

**Kind**: instance property (getter) of <code>BoardSetupDialog</code>  

#### handleRemoveRetired(event)

"Remove retired setting": drops the retired keys of that error from the draft.

**Kind**: instance method of <code>BoardSetupDialog</code>  

#### observeLayout()

Measures again whenever the modal body or the step column (its intro wrapping, its errors) changes size.

**Kind**: instance method of <code>BoardSetupDialog</code>  

#### measureFillHeight()

Fits the dialog's content to the visible modal body, so the body itself never scrolls: the columns get that
height (`--c-setup-visible-height`) and scroll on their own. Also publishes the height left under the step's
title, intro and errors (`--c-setup-fill-height`) for a step that fills the dialog (the Filter definitions
list). Without a laid-out modal nothing is set: the body scrolls and such a step keeps its own estimate.

**Kind**: instance method of <code>BoardSetupDialog</code>  

#### visibleBodyHeight(setupTop)

The height the dialog's content can take without the modal body scrolling, or null when it can't be measured.
Read from the modal body when it is the scroll container (its client height minus the gap above the content,
taken again below it); otherwise from the space between the modal header and footer.

**Kind**: instance method of <code>BoardSetupDialog</code>

## Files

- `boardSetupDialog.css`
- `boardSetupDialog.html`
- `boardSetupDialog.js`
- `boardSetupDialog.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
