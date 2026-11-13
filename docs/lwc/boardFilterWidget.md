<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardFilterWidget

<!-- LWC description -->

## JS Documentation

### PICKLIST_BUTTONS_CAP

Buttons display falls back to the dropdown above this many values.

**Kind**: global constant  
**Default**: <code>5</code>  

### isPicklistStyle(def)

Picklist and Bucket filters share the picklist controls (a Bucket filter's options are its bucket labels).

**Kind**: global function  

### describeDateLiteral(literal)

Preset label, or a readable label for any other relative literal (`NEXT_WEEK`, `LAST_N_DAYS:14`).

**Kind**: global function  

#### _layout

Bar Filter sections (`normalizeFilterLayout`); Section items live only here, never in `_defs` or the Filter context.

**Kind**: instance property of <code>BoardFilterWidget</code>  
**Default**: <code>[]</code>  

#### _sectionExpanded

Section key -> user-toggled expanded state; never persisted, so a reload restores the configured state.

**Kind**: instance property of <code>BoardFilterWidget</code>  
**Default**: <code>{}</code>  

#### _multiCurrency

Whether the org has more than one currency (null until known); a single-currency org shows no Currency picker.

**Kind**: instance property of <code>BoardFilterWidget</code>  
**Default**: <code>null</code>  

#### _userHasNoRole

Picked user Id -> true when the user has no role, false when they have one (Team match mode only).

**Kind**: instance property of <code>BoardFilterWidget</code>  
**Default**: <code>{}</code>  

#### _textInput

Raw text typed into each `TEXT` control (may be shorter than `minCharacters`, so not yet published).

**Kind**: instance property of <code>BoardFilterWidget</code>  
**Default**: <code>{}</code>  

#### _scopeError

Configuration or Record context failure this Filter widget raised as the scope-wide Widget error.

**Kind**: instance property of <code>BoardFilterWidget</code>  
**Default**: <code>null</code>  

#### acceptExternalContext(raw)

Hands a reactive Flow input to the store; a rejected input is answered by echoing the actual context.

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### recordContextFailure(recordContext)

Fail-closed check of a resolved Record context: an `overrideFieldPath` that yields no value cannot scope the
Board (except a `DEFAULT` override, which only pre-fills a user-editable filter).

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### resolveRecordContextValue(resolvedValue)

First host-record read completes initialization; later reads (record edits, refresh) re-apply the value.

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### failRecordContext(error)

A host record that cannot be read never drops or substitutes the configured Record context scope.

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### prunePicklistSelection(def)

Config-drift sanitization for described picklists: once the field's options load, selections that are no
longer valid values (stale storage, renamed values, another Board sharing the storage key) are dropped,
republished, and re-persisted.

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### resolveUsersWithoutRole()

Asks Apex which users picked on Team match mode filters have no role (their Team is only themselves).

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### bodyError

Configuration or Record context error; the same payload is the scope error every Widget renders.

**Kind**: instance property (getter) of <code>BoardFilterWidget</code>  

#### showSetupPlaceholder

Non-error setup hint for a Filter widget without (valid) filter definitions (spec story 10).

**Kind**: instance property (getter) of <code>BoardFilterWidget</code>  

#### hasCurrencyPickerItem

Whether the Admin placed a Currency picker item in the bar.

**Kind**: instance property (getter) of <code>BoardFilterWidget</code>  

#### hasCurrencyPicker

Whether the bar shows a Currency picker: placed by the Admin, and not known to be a single-currency org.

**Kind**: instance property (getter) of <code>BoardFilterWidget</code>  

#### loadCurrencyAvailability()

Asks once whether the org has several currencies, when the bar has a Currency picker item.

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### filterSections

Bar Filter sections with their filter views; a collapsed Section shows its heading and active-filter count only.

**Kind**: instance property (getter) of <code>BoardFilterWidget</code>  

#### showsAsButtons(def)

Buttons display, unless the picklist has more values than the cap (then the dropdown).

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### teamNoticesFor(def, value)

"<name> has no role; showing only their records." per picked user without a role (never names a role).

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### buildNumberRangeView(def, value)

Min / max inputs; a currency field names the Display currency its bounds are read in.

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### displayCurrency

The Board's Display currency, which currency Number range bounds are typed in.

**Kind**: instance property (getter) of <code>BoardFilterWidget</code>  

#### userLabelFor(def, entry, value)

A picked user's pill text: their name, or "<name>'s team" in Team match mode (never a role).

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### describeNumberRange(def, entry)

Pill text of a Number range: `5,000 – 10,000`, `≥ 5,000` or `≤ 10,000`, plus the Display currency code.

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### recordContextBadgeInfo

`🔒 <Label>: <Value>` badge, shown only while a LOCKED Record context override is applied (story 32).

**Kind**: instance property (getter) of <code>BoardFilterWidget</code>  

#### handleNumberInputChange(event)

Typing a min or max: `GTE` / `LTE` with one bound, `BETWEEN` with both; debounced like a search.

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### effectiveSearchText(def, raw)

Published search term for typed text: blank until it reaches `minCharacters`.

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### handleTextSearchChange(event)

Debounces typing by 300ms; clearing the input applies immediately. Input shorter than `minCharacters`
never activates the filter (an already active search is cleared after the debounce).

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### handleTextSearchKeydown(event)

`Enter` flushes the pending search immediately.

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### reconcileTextInput(ctx)

Drops typed text that no longer matches the published search (a Flow input or another Widget changed it),
so the box never shows a term other than the active one. A pending debounce keeps its text: it is about
to publish it.

**Kind**: instance method of <code>BoardFilterWidget</code>  

#### handlePageRefresh()

lightning/refresh handler (page-action edits, Board Refresh): renews the "Updated" timestamp and re-reads the
host record so an `overrideFieldPath` lock follows the edited record. Widgets refresh their own data.

**Kind**: instance method of <code>BoardFilterWidget</code>

## Files

- `boardFilterWidget.css`
- `boardFilterWidget.html`
- `boardFilterWidget.js`
- `boardFilterWidget.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
