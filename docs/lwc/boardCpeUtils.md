<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeUtils

<!-- LWC description -->

## JS Documentation

### MEASURE_AGGREGATE_OPTIONS

Aggregates of a Measures list (Chart and Metric widgets): the plain aggregates, Average per record (`AVG_PER`: one
value per record of a per-record lookup) and a Formula measure.

**Kind**: global constant  
**Default**: <code>[...]</code>  

### MEASURES_REPLACED_MESSAGE

The error of a Chart config still carrying the single aggregate of the old Bar widget (retired).

**Kind**: global constant  
**Default**: <code>'aggregateFunction and valueFieldApiName were replaced by the Measures list.'</code>  

### FORMULA_TOKEN

String literals (skipped) or identifiers not called as a function.

**Kind**: global constant  
**Default**: <code>/("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|(?&lt;![\w$.])([A-Za-z_]\w*)(?!\w|\s*\()/g</code>  

### PER_RECORD_INNER_OPTIONS

How an Average per record Measure takes each record's value (`inner`).

**Kind**: global constant  
**Default**: <code>[...]</code>  

### USER_MATCH_MODE_OPTIONS

User filter `matchMode`: the picked users only, or each picked user's Team.

**Kind**: global constant  
**Default**: <code>[...]</code>  

### PLAIN_NUMBER

A plain number as the Number range filter reads it (mirrors `filterPersistence` NUMBER_PATTERN).

**Kind**: global constant  
**Default**: <code>/^-?\d+(?:\.\d+)?$/</code>  

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

### teamBindingHopError(filterId, path)

Config-time error for an Include team binding (User filter in `usersAndTeam` mode): the Team condition reaches
`<path>.UserRoleId`, one relationship hop past the bound path (counted inside a child semi-join), and SOQL allows
at most 5. Null when the path is within the limit or isn't a single field path.

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

### containInnerChanges(component)

Keeps the `change` events of the base components inside `component` from reaching its host. `lightning-input`,
`lightning-combobox` and the like fire `change` bubbling and composed, so a keystroke inside an editor would
otherwise also arrive at the parent's `onchange` on the editor, looking like the editor's own `change` with the
wrong detail. Call from `connectedCallback`; the component's own `change`, fired on its host, is not affected.

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

### loadScreenFlows()

`BoardSchemaService.getScreenFlows`: the org's active Screen Flows (`[{ apiName, label }]`), shared by pickers.

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

### numberDefaultErrors(defaultValue, label)

NUMBER_RANGE `defaultValue { from?, to? }`: plain numbers (no grouping separators), min not above max.

**Kind**: global function  

### choiceDefaultErrors(filter, defaultValue, label)

PICKLIST / LOOKUP / USER `defaultValue { values?, token? }` (spec §5), checked as `buildFilterValue` reads it.

**Kind**: global function  

### sectionHeadingErrors(section, index)

A Section item (`{ type: 'section', label, startCollapsed }`) only needs a heading.

**Kind**: global function  

### recordContextErrors(recordContext, filterTypes)

Problems of a Filter widget's `recordContext` (`[{ key: 'recordContext', errorString }]`) given the filterId → type
map of its valid filters (`validateFilterDefinitions(filters).filterTypes`). Shared by `validateFilterConfig` and
the Setup dialog's Filters step.

**Kind**: global function  

### validateFilterDefinitions(filters, [bucketFields])

Problems of each filter definition, in list order (`[[message, …], …]`; an empty list means the filter is valid),
plus the filterId → type map of the valid ids. A repeated filterId flags the later filter. The rules behind the
Filter widget's `validate()` and the Filters step of its Setup dialog (master list error flags). With the
Filter widget's `bucketFields`, a Bucket filter must name one of them.

**Kind**: global function  

### compactRecordContext(recordContext)

`{ mode, overrideFilterId?, overrideFieldPath? }` of a Filter widget, or null for the default (IMPLICIT without
overrides), so an untouched Record context stays out of the config.

**Kind**: global function  

### validateFilterConfig(config)

Filter widget design-time errors: filter definitions, the recordContext override, and persistence.

**Kind**: global function  

### MAX_METRIC_MEASURES

Max Measures of one Metric widget.

**Kind**: global constant  
**Default**: <code>6</code>  

### validateMetricConfig(config)

Metric widget design-time errors. A Measures list needs exactly one visible Measure; a config without one is a
single-aggregate Metric (`aggregateFunction`, `valueFieldApiName`, `format`), checked as before.

**Kind**: global function  

### validateChartConfig(config, [context])

Chart widget design-time errors; max categories depends on the chart type. `context.boardBucketFields`: the
Board-level Bucket fields (of the Board's Filter widget) a `bucket:<id>` reference may also name.

**Kind**: global function  

### otherBarProblem(config)

Why the Chart's Measures can't have an "Other" bar, or null when they can. "Other" merges the rolled-up rows (AVG,
MIN, MAX, Average per record and Formula measures included, hidden ones too), except distinct counts, which never
merge; Small multiples panels can only sum their "Other". The Display step offers "Other" by the same rule.

**Kind**: global function  

### bucketReferenceErrors(config, key, label, [context])

A group or series field `bucket:<id>` must name one of the Widget's Bucket fields or the Board's.

**Kind**: global function  

### MAX_CHART_MEASURES

Max Measures of one Chart widget.

**Kind**: global constant  
**Default**: <code>6</code>  

### SHOW_AS_OPTIONS

Share of total modes of a Chart widget Measure (`showAs`; unset = its plain value). Only COUNT and SUM Measures add
up to a total; percent of category needs a series (Stack by) field or several Measures.

**Kind**: global constant  
**Default**: <code>[...]</code>  

### DEFAULT_MEASURE_SUMMARY

Measures step summary of a Widget without Measures: it counts records, the default.

**Kind**: global constant  
**Default**: <code>'Count of records (default)'</code>  

### chartMeasures(config)

A Chart widget's Measures list; a config without one counts records (`[{ aggregateFunction: 'COUNT' }]`).

**Kind**: global function  

### averagePerRecordErrors(measure, fn, label)

An Average per record Measure needs a per-record lookup path and takes each record's value as SUM or ONCE.

**Kind**: global function  

### formulaSlot(index)

Slot letter of Measure `index` (0 → A).

**Kind**: global function  

### measureTitle(index)

`Measure 2 (B)`: a Measure's title with its formula slot.

**Kind**: global function  

### mapFormulaSlots(text, rename)

Rewrites each slot reference of `text` through `rename(slotIndex)` (returns a slot index); strings untouched.

**Kind**: global function  

### formulaReferences(text)

Slot indexes (0 = A) a formula references, ascending.

**Kind**: global function  

### remapFormulaMeasures(measures, newIndexOf)

Keeps Formula measures pointing at the same Measures after the list is reordered or a Measure removed:
`newIndexOf(oldIndex)` is a Measure's new position (or -1 when removed; references to it are left as typed).

**Kind**: global function  

### MEASURE_POSITION_KEYS

Config keys holding a Measure's 0-based list position (besides Formula slots and the Gauge's).

**Kind**: global constant  
**Default**: <code>['panelHeadlineMeasure', 'panelSortMeasure']</code>  

### remapMeasureRefs(config, measures, mapping)

The patch that keeps every position-based Measure reference of `config` on the same Measure after its Measures list
became `measures` (reordered, or a Measure removed). `mapping[oldIndex]` is the Measure's new position, or -1 when
it was removed. Covers Formula slots (a removed slot is left as typed: the Formula reports it), the Gauge's
`minMeasure` / `maxMeasure` / `targetMeasure` and the Chart's `panelHeadlineMeasure` / `panelSortMeasure`; a
reference to a removed Measure is cleared, so the step's validation asks for a new one where one is required.

**Kind**: global function  

### formulaMeasureErrors(measures, index)

The Measure-reference errors of Formula measure `index` (the formula text itself is checked by the server).

**Kind**: global function  

### measureDisplayErrors(measure, label)

A Measure's combo chart settings: `render` (bar | line | referenceLine) and value `axis` (primary | secondary), both optional.

**Kind**: global function  

### columnErrors(rawColumns, key, prefix, messages, bucketFields)

`bucketFields`: the Widget's Bucket fields when its columns may show one (`fieldPath: 'bucket:<id>'`); a column
then must name one of them. Without it every column is a field path.

**Kind**: global function  

### validateTableConfig(config, [context])

Table widget design-time errors: columns, page size, and the and a leftover childRelationship (removed).

**Kind**: global function  

### bucketGroupErrors(config, bucketFields)

A Bucket field group (`bucket:<id>`): Detail rows off only, the only group field, the Widget's or the Board's.

**Kind**: global function  

### rowGroupingErrors(groupBy)

Row grouping (Detail rows on): up to two group field paths, each with an optional ASC / DESC group order, a date
granularity (the Chart widget's options) and an order field constant per group (`orderBy`, e.g. `Opportunity.Amount`).

**Kind**: global function  

### createActionErrors(action, label)

A Create action needs an object; each default maps a field of that object from a row field.

**Kind**: global function  

### flowActionErrors(action, label)

A Screen Flow action needs a flow API name; each input maps a flow variable from a row field.

**Kind**: global function  

### TABLE_SUMMARY_FUNCTIONS

Stacked summaries a numeric Table column can show, in the order they are offered.

**Kind**: global constant  
**Default**: <code>['SUM', 'AVG', 'MIN', 'MAX']</code>  

### columnSummaryErrors(rawColumns)

Column `summaries`: when set, a list of 1–4 distinct Sum/Average/Min/Max.

**Kind**: global function  

### lookupPrefix(groupPath)

Lower-cased path prefix of fields reached through a lookup group field (`AccountId` -> `account.`,
`Parent__c` -> `parent__r.`), or null when the path does not name a lookup.

**Kind**: global function  

### isDateGroup(entry, objectFields)

True when a group entry groups by a date: it has a granularity, or (Day, the default, is left out of the config)
its direct field is a Date or DateTime in the object's field describes (`objectFields`, when loaded).

**Kind**: global function  

### isConstantPerGroup(lowerPath, entry, objectFields)

True when `lowerPath` has one value per group of a group entry: the group field itself (not a date: its groups are
date buckets) or a field through a lookup group field.

**Kind**: global function  

### detailRowsErrors(config, objectFields)

Detail rows (Row grouping): off makes the Table an aggregated table, so it needs a group field and every column
must have one value per group of one of the (up to two) group fields: a group field, a field through a lookup
group field, or a column with summaries. Ordering groups by a summary (`orderBySummary`) needs Detail rows off and
a summary the Table shows.

**Kind**: global function  

### GROUPED_DETAIL_ROW_LIMIT_MAX

Most first-level groups a Row limit keeps with Detail rows on (the record stream is filtered by an IN-list).

**Kind**: global constant  
**Default**: <code>200</code>  

### ROW_LIMIT_MAX

Most rows (ungrouped) or Group rows (Detail rows off) a Row limit keeps.

**Kind**: global constant  
**Default**: <code>2000</code>  

### isGroupedTable(config)

True when the Table has Row grouping (a first group field).

**Kind**: global function  

### rowLimitMax(config)

Largest Row limit the config allows: 200 groups with Row grouping and Detail rows on, else 2,000.

**Kind**: global function  

### groupedRowLimitErrors(config)

Row limit on a grouped Table: counts first-level groups ("Top N groups"), ranked by the group order, so it needs
no default sort; 1-200 groups with Detail rows on, 1-2,000 with Detail rows off.

**Kind**: global function  

### rowLimitErrors(config)

Row limit (Top N): a whole number from 1 to 2,000 that needs a default sort to mean anything.

**Kind**: global function  

### rowActionErrors(rawActions)

Row actions: a list of `view` / `edit` / `create` / `flow` actions, each with a label and (when set) a lookup path target.

**Kind**: global function  

### WIDGET_SPECS

Per widget type: data widget (object, bindings, base filters), Widget-level Data provider, dual-written top-level
keys, widget rules.

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

### isConditionGroup(entry)

Whether a condition tree entry is an AND / OR group (`{ id, logic, conditions[] }`) rather than a condition.

**Kind**: global function  

### flattenConditions(entries)

Every entry of a list of condition tree entries (groups and their conditions), depth first.

**Kind**: global function  

### countConditions(entries)

Number of conditions in a list of condition tree entries, counting the conditions inside groups.

**Kind**: global function  

### withBaseFilterIds(entries)

Gives entries without an id, or with an id already used elsewhere in the tree (e.g. hand-edited JSON), a fresh
`bfN` id; group conditions get the same treatment.

**Kind**: global function  

### baseFiltersToTree(baseFilters)

A Widget's `baseFilters` as the condition tree the condition editor edits: `{ tree: { logic, conditions },
rootGroupId }`. The entries of `baseFilters` combine with AND, so a flat list loads as the AND top level; a single
stored OR group loads as the OR top level (`rootGroupId` is its id). Missing or duplicate ids get fresh `bfN` ids.

**Kind**: global function  

### baseFiltersFromTree(tree, [rootGroupId])

The `baseFilters` list of a condition tree (`baseFiltersToTree`'s inverse): an AND top level is the list itself;
OR at the top level is stored as one OR group entry `{ id, logic: 'OR', conditions }`, keeping `rootGroupId`.

**Kind**: global function  

### conditionGroupError(entry)

First problem with an AND / OR group itself (not its conditions), or null.

**Kind**: global function  

### baseFilterError(condition)

First problem with a condition tree entry (a Base filter condition, or an AND / OR group and its conditions), or
null when it compiles. Shared by Base filters and every other condition tree.

**Kind**: global function  

### baseFilterErrorsByIndex(baseFilters)

Messages per Base filter condition (`string[][]`, parallel to `baseFilters`): the condition's own problem
(`baseFilterError`) plus a missing or duplicate `id`. Shared by `configErrors` and the Base filters of the Setup dialog's Data step.

**Kind**: global function  

### conditionIdErrors(condition, ids)

Missing or duplicate `id`s of a condition tree entry and the conditions of a group (ids are unique per tree).

**Kind**: global function  

### baseFilterSummary(condition, index)

Read-only description of a Base filter condition: `{ label, operatorLabel, valueText }`, e.g.
`Status` · `Not in list` · `Closed, Duplicate`. `label` falls back to `Condition N` without a field.

**Kind**: global function  

### conditionGroupSummary(group)

Read-only description of an AND / OR group, e.g. `Any of 2 conditions` · `OR group` ·
`Status: New or (Priority: High and Origin: Web)`.

**Kind**: global function  

### configErrors(widgetType, config, [references], [context])

Design-time errors of a config envelope (`[{ key, errorString }]`): the rules behind both `validate()` and pasted
Config JSON. `references` holds top-level keys bound to Flow resources (they satisfy required values).

**Kind**: global function  

### APEX_CLASS_NAME

An Apex class name, optionally namespaced (`ns.ClassName`).

**Kind**: global constant  
**Default**: <code>/^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)?$/</code>  

### dataProviderErrors(dataProvider)

The Widget-level Data provider (Chart and Metric): an Apex class name. Whether the class exists and implements
`BoardDataProvider` is checked by the server at query time; its message shows in the Widget (and the preview).

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

### defaultNotationFor(widgetType)

The notation a Widget formats values with when `format.notation` is unset: Metric is compact, the rest standard.

**Kind**: global function  

### measureSummary(widgetType, config)

Measure section summary of the Metric and Chart Config editors: the aggregate and the value notation, e.g.
`Count of records · compact` or `Sum of Amount · standard`.

**Kind**: global function  

### chartMeasuresSummary(config)

Measures section summary of the Chart Config editor: one Measure reads like `measureSummary`
(`Sum of Amount · compact`); several list their labels (`2 Measures: Pipeline, Count of records`).

**Kind**: global function  

### metricMeasuresSummary(config)

Measure section summary of the Metric Config editor: the visible Measure like `measureSummary`, plus the Measure
count when there are several (`Sum of Amount · compact · 3 Measures (2 hidden)`).

**Kind**: global function  

### DIALOG_SAVE

How the Setup dialog (`c/boardSetupDialog`) closes: Save with the whole draft, or dismiss (Cancel, X, Escape).

**Kind**: global constant  
**Default**: <code>'save'</code>

## Files

- `boardCpeUtils.js`
- `boardCpeUtils.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
