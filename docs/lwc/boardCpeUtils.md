<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeUtils

<!-- LWC description -->

## JS Documentation

### cleanString(value)

Trimmed non-empty string, else null.

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

## Files

- `boardCpeUtils.js`
- `boardCpeUtils.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
