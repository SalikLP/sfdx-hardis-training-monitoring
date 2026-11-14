<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeCommon

<!-- LWC description -->

## JS Documentation

### SECTIONS

The shell's own Config sections (see `sectionStates` in `c/boardCpeUtils`).

**Kind**: global constant  
**Default**: <code>[...]</code>  

### BoardCpeCommon

Shared Flow Custom Property Editor shell composed by every Board CPE (ADR 0002). The panel is an overview: Board
(Board id, title, *Wait for Filter widget* for data Widgets), one summary line per Setup dialog step with "Edit…"
opening the dialog (`c/boardSetupDialog`) at that step, and Advanced: Config JSON. Everything else (object,
orientation, Filter bindings, Base filters, ...) is edited only in the dialog's steps; a Save there applies the
whole draft as one config change. Board and Advanced are `c-board-cpe-section`s: Board starts open for a new Widget,
Advanced collapsed, and a section with a validation error is forced open.

Every edit dispatches `configuration_editor_input_value_changed` (or `..._deleted` for cleared values) for the
serialized `configJson`, and also for the discrete top-level property when `boardId`, `title`, or `objectApiName`
changes. A non-bubbling `configchange` event (`detail.config`) reports the current config.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### sectionOpen

Open state of the shell's Config sections: set once on load (a new Widget opens Board), then by the Admin.

**Kind**: instance property of <code>BoardCpeCommon</code>  
**Default**: <code>null</code>  

#### widgetType

`filter` | `metric` | `chart` | `table`

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  
**Decorators**: <code>@api</code>  

#### stepContext

What the step summaries can't read from the config (e.g. the Group by field type), from the Widget's CPE.

**Kind**: instance property of <code>BoardCpeCommon</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>{}</code>  

#### inputVariables

Flow Builder `inputVariables` (`[{ name, value, valueDataType }]`) passed through by the CPE.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  
**Decorators**: <code>@api</code>  

#### builderContext

Flow Builder `builderContext` (`screens -> fields`) used to discover the Filter widget.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  
**Decorators**: <code>@api</code>  

#### elementInfo

Flow Builder `elementInfo` (`{ apiName, type }`) identifying the screen component being edited.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  
**Decorators**: <code>@api</code>  

#### getConfig()

Current config (version 1 envelope) as a plain object.

**Kind**: instance method of <code>BoardCpeCommon</code>  
**Decorators**: <code>@api</code>  

#### updateConfig(patch)

Shallow-merges `patch` into the config (null/undefined removes a key), then emits `configJson` and, for
`boardId`/`title`/`objectApiName` keys, the top-level property.

**Kind**: instance method of <code>BoardCpeCommon</code>  
**Decorators**: <code>@api</code>  

#### validate()

Design-time errors (`[{ key, errorString }]`): the Config JSON draft or saved JSON, the shared envelope rules and
the widget's own rules (`configErrors`).

**Kind**: instance method of <code>BoardCpeCommon</code>  
**Decorators**: <code>@api</code>  

#### commit(nextConfig, [topLevelKeys])

Applies one config change: one `configJson` event, plus one per changed top-level property. The top-level
events are required, not duplicates: `boardId`, `title` and `objectApiName` are separate Flow inputs in the
Widget's meta, and Flow Builder keeps their last value. `readCpeState` lets a stored top-level value override
`configJson` when the editor reopens, so a Setup dialog Save that changes the object without also writing
`objectApiName` would reopen on the old object.

**Kind**: instance method of <code>BoardCpeCommon</code>  

#### notifyConfig()

`configchange` detail: the config, plus the Board-level Bucket fields (`boardBucketFields`) of the discovered
Filter widgets on this Board, which a data Widget can use by id.

**Kind**: instance method of <code>BoardCpeCommon</code>  

#### boardBucketFields

Bucket fields of the Filter widgets discovered on this Board (`builderContext`).

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  

#### boardSummary

`default · Account`; the object part only for data Widgets.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  

#### waitForFilterWidgetValue

Wait for Filter widget: on unless the config says `false`.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  

#### handleWaitForFilterWidgetChange(event)

Off writes `waitForFilterWidget: false`; on removes the key (missing = on).

**Kind**: instance method of <code>BoardCpeCommon</code>  

#### bindingRows

The Filter binding rows of the config, for the Filter bindings step summary.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  

#### stepSummaryContext

What the step summaries and validators read besides the config.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  

#### setupSteps

One line per Setup dialog step: label, summary of the config, error flag.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  

#### handleEditStep(event)

Opens the Setup dialog at the step whose "Edit…" was clicked, on a copy of the config. Save applies the
returned draft as one config change (plus the top-level properties it changed); Cancel changes nothing.
Focus then returns to the "Edit…" button.

**Kind**: instance async method of <code>BoardCpeCommon</code>  

#### keptReferences(text)

Flow resource references the pasted JSON does not set; applying keeps them bound.

**Kind**: instance method of <code>BoardCpeCommon</code>

## Files

- `boardCpeCommon.css`
- `boardCpeCommon.html`
- `boardCpeCommon.js`
- `boardCpeCommon.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
