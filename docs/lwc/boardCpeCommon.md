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

Shared Flow Custom Property Editor shell composed by every Board CPE.

Renders the Board Config section (Board id/title, plus the Object Picker for data Widgets and orientation for Bar),
a default slot for widget-specific Config sections, the Filter bindings (`builderContext` Filter widget discovery +
`filterBindings` overrides) and Base filters Config sections (data Widgets), and the "Advanced: Config JSON"
portability section. Each is a `c-board-cpe-section`: Board starts open for a new Widget, everything else starts
collapsed, and a section with a validation error is forced open.

Every edit dispatches `configuration_editor_input_value_changed` (or `..._deleted` for cleared values) for the
serialized `configJson`, and also for the discrete top-level property when `boardId`, `title`, `objectApiName`,
or `orientation` changes. A non-bubbling `configchange` event (`detail.config`) reports the current config.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### sectionOpen

Open state of the shell's Config sections: set once on load (a new Widget opens Board), then by the Admin.

**Kind**: instance property of <code>BoardCpeCommon</code>  
**Default**: <code>null</code>  

#### widgetType

`filter` | `metric` | `bar` | `table`

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  
**Decorators**: <code>@api</code>  

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
`boardId`/`title`/`objectApiName`/`orientation` keys, the top-level property.

**Kind**: instance method of <code>BoardCpeCommon</code>  
**Decorators**: <code>@api</code>  

#### validate()

Design-time errors (`[{ key, errorString }]`): the Config JSON draft or saved JSON, the shared envelope rules,
the widget's own rules (`configErrors`), and Filter bindings switched to "Field path" without a path.

**Kind**: instance method of <code>BoardCpeCommon</code>  
**Decorators**: <code>@api</code>  

#### hasBindingDraftErrors

Filter bindings switched to "Field path" without a path, or binding rows with an invalid path.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  

#### boardSummary

`default · Account`; the object part only for data Widgets.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  

#### bindingsSummary

`3 bound · 1 opted out`, or `None` without any Filter to bind.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  

#### baseFiltersSummary

`None` or the number of conditions.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  

#### hasPathBinding(filterId)

True when `filterId` has a non-IGNORE path binding.

**Kind**: instance method of <code>BoardCpeCommon</code>  

#### baseFilterRows

Read-only list: `Status · Closed, Duplicate`, operator badge, and error indicator of each saved condition.

**Kind**: instance property (getter) of <code>BoardCpeCommon</code>  

#### handleEditBaseFilters()

Opens the Base filters Config dialog on a draft of the conditions. Save applies the draft as one config change;
Cancel, Escape, and the header X change nothing. Focus then returns to "Edit base filters…".

**Kind**: instance async method of <code>BoardCpeCommon</code>  

#### keptReferences(text)

Flow resource references the pasted JSON does not set; applying keeps them bound.

**Kind**: instance method of <code>BoardCpeCommon</code>

## Files

- `boardCpeCommon.css`
- `boardCpeCommon.html`
- `boardCpeCommon.js`
- `boardCpeCommon.js-meta.xml`
- `cpeConfig.js`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
