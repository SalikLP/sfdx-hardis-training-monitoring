<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardFilterWidget

<!-- LWC description -->

## JS Documentation

### describeDateLiteral(literal)

Preset label, or a readable label for any other relative literal (`NEXT_WEEK`, `LAST_N_DAYS:14`).

**Kind**: global function  

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

#### bodyError

Configuration or Record context error; the same payload is the scope error every Widget renders.

**Kind**: instance property (getter) of <code>BoardFilterWidget</code>  

#### showSetupPlaceholder

Non-error setup hint for a Filter widget without (valid) filter definitions (spec story 10).

**Kind**: instance property (getter) of <code>BoardFilterWidget</code>  

#### recordContextBadgeInfo

`🔒 <Label>: <Value>` badge, shown only while a LOCKED Record context override is applied (story 32).

**Kind**: instance property (getter) of <code>BoardFilterWidget</code>  

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
