<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeUtils

<!-- LWC description -->

## JS Documentation

### MIN_SEARCH_CHARACTERS

Mirrors BoardQueryService.MIN_SEARCH_CHARACTERS.

**Kind**: global constant  
**Default**: <code>2</code>  

### cleanString(value)

Trimmed non-empty string, else null.

**Kind**: global function  

### hasText(value)

True for a non-blank string, or any other value that is not null/undefined.

**Kind**: global function  

### deepCopy(value)

Deep copy of a JSON-compatible value (undefined stays undefined).

**Kind**: global function  

### applyPatch(target, patch)

Shallow copy of `target` with `patch` merged in; a null/undefined patch value deletes the key.

**Kind**: global function  

### isIgnoreBinding(binding)

True for `IGNORE` (any case) or null: the Widget opts out of the filter.

**Kind**: global function  

### isValidBindingPath(binding)

True for `IGNORE`, `null`, a direct/parent/child path, or a TEXT multi-field / SOSL target list.

**Kind**: global function  

### isValidFieldPath(path)

A direct field, 1–5 hop parent path, or `Child(ForeignKey).Path`.

**Kind**: global function  

### isParentFieldPath(path)

A direct field or 1–5 hop parent path (no child semi-join).

**Kind**: global function  

### isDatePreset(literal)

True when `literal` is one of the shared `DATE_PRESETS` (the Filter bar's preset list).

**Kind**: global function  

### toCamelCase(label)

`"Account Owner"` → `accountOwner`; identifiers always start with a letter.

**Kind**: global function  

### uniqueId(base, takenIds)

`base`, or `base2`, `base3`, … when taken.

**Kind**: global function  

### isDerivedId(filterId, label)

True when `filterId` was derived from `label` (optionally de-duplicated with a numeric suffix).

**Kind**: global function  

### nextSequentialId(items, prefix)

Next `<prefix>N` id (max + 1) over items' `id`s.

**Kind**: global function  

### parseNumber(value)

Number input value → number, or null when empty / not numeric.

**Kind**: global function  

### moveItem(items, index, offset)

Moves `items[index]` by `offset`, returning a new array (or the same array when out of range).

**Kind**: global function  

### NO_DRAG

Idle drag state: `{ from, over }` are row indexes, or null.

**Kind**: global constant  
**Default**: <code>Object.freeze({ from: null, over: null })</code>  

### startRowDrag(event)

`dragstart` on a row handle: starts a move of that row, using the whole row as the drag image.

**Kind**: global function  

### overRowDrag(event, drag)

`dragover` on a row: accepts the drop while a row of this list is being dragged; returns the next state.

**Kind**: global function  

### dropRowDrag(event, drag)

`drop` on a row: the `{ index, offset }` move to apply (see `moveItem`), or null when nothing moves.

**Kind**: global function  

### dragRowClass(drag, index)

Extra row classes: the dragged row is dimmed; the hovered row shows a marker on the side the row will land.

**Kind**: global function  

### loadQueryableObjects()

`BoardSchemaService.getQueryableObjects` (slow on a cold cache, so shared by every picker).

**Kind**: global function  

### loadObjectFields(objectApiName)

`BoardSchemaService.getObjectFields` for `objectApiName`.

**Kind**: global function  

### loadChildRelationships(objectApiName)

`BoardSchemaService.getChildRelationships` for `objectApiName`.

**Kind**: global function  

### resolveFieldDescribe(objectApiName, path)

Leaf field describe (`BoardSchemaService.FieldInfo`) of a direct or 1–5 hop parent `path` on `objectApiName`,
traversing polymorphic lookups to `User` like `BoardQueryService`. Resolves null when the path does not resolve.

**Kind**: global function  

### formatErrors(format, key, label)

Problems with a ValueFormatConfig, prefixed by `label`.

**Kind**: global function  

### filterSelectionMode(filter)

Effective selection mode, matching `normalizeFilterDefinitions`.

**Kind**: global function  

### filterOptionsSource(filter)

Effective PICKLIST options source, matching `normalizeFilterDefinitions` (options imply CUSTOM).

**Kind**: global function  

### choiceDefaultErrors(filter, defaultValue, label)

PICKLIST / LOOKUP / USER `defaultValue { values?, token? }` (spec §5), checked as `buildFilterValue` reads it.

**Kind**: global function  

### recordContextErrors(recordContext, filterTypes)

Problems of a Filter widget's `recordContext` (`[{ key: 'recordContext', errorString }]`) given the filterId → type
map of its valid filters (`validateFilterDefinitions(filters).filterTypes`). Shared by `validateFilterConfig` and
the Filter definitions Config dialog's Save check.

**Kind**: global function  

### validateFilterDefinitions(filters)

Problems of each filter definition, in list order (`[[message, …], …]`; an empty list means the filter is valid),
plus the filterId → type map of the valid ids. A repeated filterId flags the later filter. The rules behind the
Filter widget's `validate()`, its read-only filter list, and the Filter definitions Config dialog.

**Kind**: global function  

### compactRecordContext(recordContext)

`{ mode, overrideFilterId?, overrideFieldPath? }` of a Filter widget, or null for the default (IMPLICIT without
overrides), so an untouched Record context stays out of the config.

**Kind**: global function  

### validateFilterConfig(config)

Filter widget design-time errors: filter definitions, the recordContext override, and persistence.

**Kind**: global function  

### validateMetricConfig(config)

Metric widget design-time errors.

**Kind**: global function  

### validateBarConfig(config)

Bar Chart widget design-time errors.

**Kind**: global function  

### validateTableConfig(config)

Table widget design-time errors: columns, page size, and the optional childRelationship.

**Kind**: global function  

### WIDGET_SPECS

Per widget type: data widget (object, bindings, base filters), dual-written top-level keys, widget rules.

**Kind**: global constant  
**Default**: <code>{...}</code>  

### topLevelKeysFor(widgetType)

Top-level `@api` properties the CPE dual-writes to both the component property and `configJson`.

**Kind**: global function  

### orderConfig(widgetType, raw)

Canonical key order: `version`, `widgetType`, top-level keys, then the rest.

**Kind**: global function  

### readCpeState(widgetType, inputVariables)

Reads the CPE config from Flow `inputVariables`: `configJson` merged with non-empty top-level literals (top-level
wins, matching runtime precedence). Top-level values bound to Flow resources (`valueDataType: 'reference'`) are
returned in `references` and never copied into `configJson`.

**Kind**: global function  

### baseFilterError(condition)

First problem with a Base filter condition, or null when it compiles.

**Kind**: global function  

### baseFilterErrorsByIndex(baseFilters)

Messages per Base filter condition (`string[][]`, parallel to `baseFilters`): the condition's own problem
(`baseFilterError`) plus a missing or duplicate `id`. Shared by `configErrors` and the Base filters Config dialog.

**Kind**: global function  

### baseFilterSummary(condition, index)

Read-only description of a Base filter condition: `{ label, operatorLabel, valueText }`, e.g.
`Status` · `Not in list` · `Closed, Duplicate`. `label` falls back to `Condition N` without a field.

**Kind**: global function  

### configErrors(widgetType, config, [references])

Design-time errors of a config envelope (`[{ key, errorString }]`): the rules behind both `validate()` and pasted
Config JSON. `references` holds top-level keys bound to Flow resources (they satisfy required values).

**Kind**: global function  

### validateConfigText(widgetType, text, [references]) ⇒ <code>{ config: object</code> \| <code>null, errors: string[] }</code>

Parses pasted `configJson` text and checks it with the same rules as `validate()` (`configErrors`).

**Kind**: global function  
**Returns**: <code>{ config: object</code> \| <code>null, errors: string[] }</code>  

### validateCpe(shell, widgetType, inputVariables)

`validate()` of an exposed CPE: the mounted shell's errors, or (fail-closed, before the shell renders) the errors
of the config read straight from Flow `inputVariables`.

**Kind**: global function  

### isNewWidget(widgetType, inputVariables)

True when the Widget being edited counts as new for the Config sections' default open state: its config is empty,
or it has no object (data Widgets, unless `objectApiName` is bound to a Flow resource) / no filters (Filter widget).
Call once on load (e.g. `connectedCallback`); open state must not follow later edits.

**Kind**: global function  

### hasErrorFor(errors, keys)

True when any `[{ key, errorString }]` error belongs to one of `keys` (a Config section's config keys).

**Kind**: global function  

### SUMMARY_SEPARATOR

Separator between the parts of a Config section summary (`default · Account`).

**Kind**: global constant  
**Default**: <code>' · '</code>  

### joinSummary(parts)

Joins the non-empty parts of a Config section summary.

**Kind**: global function  

### countLabel(count, noun, [plural])

`1 rule`, `3 rules` (`plural` for irregular nouns).

**Kind**: global function  

### initialSectionOpen(sections, widgetType, inputVariables)

Default open state of a Config editor's sections (`{ [name]: boolean }`): a new Widget (`isNewWidget`) opens the
`openWhenNew` sections, an existing one starts collapsed. Call once on load; open state must not follow edits.

**Kind**: global function  

### toggleSectionOpen(sectionOpen, event)

The open state after a `c-board-cpe-section` `toggle` event (`detail: { name, open }`).

**Kind**: global function  

### sectionStates(sections, cpe, sectionOpen, errors)

Header state of each Config section, keyed by name: `{ name, open, hasError, summary }`. The values are lazy, so a
template binding only computes what it reads. `errors()` returns the `validate()`-style errors the sections check.

**Kind**: global function  

### widgetSectionStates(widgetType, sections, cpe)

`sectionStates` of a widget Config editor (`cpe` with `sectionOpen`, `config`, and `configLoaded`). Errors wait for
the shell's first `configchange` (`configLoaded`), so the placeholder config never flashes errors on first render.

**Kind**: global function  

### defaultNotationFor(widgetType)

The notation a Widget formats values with when `format.notation` is unset: Metric is compact, the rest standard.

**Kind**: global function  

### measureSummary(widgetType, config)

Measure section summary of the Metric and Bar Config editors: the aggregate and the value notation, e.g.
`Count of records · compact` or `Sum of Amount · standard`.

**Kind**: global function  

### openConfigDialog(Dialog, { value, ...props } = {})

Opens a Config dialog (a `LightningModal` subclass such as `c/boardFilterDialog`) at size large with a deep copy of
`value`, and resolves with `{ action: 'save', draft }` or `{ action: 'dismiss' }` (Cancel, header X, Escape).
The caller applies a saved draft as exactly one config change and does nothing on dismiss.

**Kind**: global function  

### ConfigDialogMixin(Base)

Keyed draft list shared by the Config dialogs: `class MyDialog extends ConfigDialogMixin(LightningModal)`.

Owns the stable row keys parallel to the draft items (`_rowKeys`, `nextRowKey()`), the selection (`selectedKey`,
`selectedIndex`), one-time draft initialization in `connectedCallback`, the master-detail event handlers
(`handleItemSelect`, `handleItemMove`, `handleItemRemove`, plus `addDraftItem(item)`), focus after a remove, and
the Cancel / Save footer handlers (`handleCancel`, `handleSave`).

The dialog provides:
- `rowKeyPrefix`: prefix of the row keys (e.g. `filter`)
- `initDraft(value)`: sets up its draft from the deep copy of `@api value`
- `draftItems` / `setDraftItems(items, change)`: the master list and its replacement; `change` is
  `{ removed, removedKey }` after a remove, so dependent draft state can follow
- `errorsByIndex`: messages per draft item; Save stays disabled while any item has one (override `isSaveDisabled`
  to add draft-level checks)
- `draft`: what Save resolves with (deep-copied)

**Kind**: global function  

#### _rowKeys

Stable keys parallel to `draftItems` (labels and ids change while the Admin types).

**Kind**: global property  
**Default**: <code>[]</code>  

#### addDraftItem(item)

Appends `item` to the draft and selects it.

**Kind**: global function

## Files

- `boardCpeUtils.js`
- `boardCpeUtils.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
