<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardSetupFilterDefinitions

<!-- LWC description -->

## JS Documentation

### BoardSetupFilterDefinitions

Filters step of the Filter widget's Setup dialog (ADR 0002): the Filter definitions as master-detail inside the
step (the ordered list of filters, Filter sections and the Currency picker item on the left, the selected item's
settings on the right). It edits the dialog's draft (`config`): the list is `filters` (a saved Board-level
`currencyPicker` setting reads as the Currency picker item at the end, `filterItemsOf`), Bucket filters pick one of
the draft's Board-level `bucketFields`, and the Record context override follows filterId renames, removals and
type changes.

Every edit fires `change` with `detail.patch`: `{ filters, currencyPicker: null }` (null `filters` for an empty
list; the older `currencyPicker` key is dropped once the list is written), plus `recordContext` when the override
had to follow. The Filters step (`FILTER_STEPS` in `c/boardSetupSteps`) validates the list
(`validateFilterDefinitions`), the Record context step the override (`recordContextErrors`, also shown here).

The list keeps stable row keys while the Admin types (labels and ids change); a draft with a different list
rebuilds them.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### picklistOptions

`Object.Field` → `{ loading, options, error }` for FIELD_DESCRIBE picklist defaults.

**Kind**: instance property of <code>BoardSetupFilterDefinitions</code>  
**Default**: <code>{}</code>  

#### recordLabels

Record Id → name of LOOKUP/USER default values.

**Kind**: instance property of <code>BoardSetupFilterDefinitions</code>  
**Default**: <code>{}</code>  

#### userSearches

Row key → `{ term, results }` of the USER default search.

**Kind**: instance property of <code>BoardSetupFilterDefinitions</code>  
**Default**: <code>{}</code>  

#### _dateModes

Row key → date default mode chosen before any value is entered.

**Kind**: instance property of <code>BoardSetupFilterDefinitions</code>  
**Default**: <code>{}</code>  

#### _rowKeys

Stable keys parallel to `filters`.

**Kind**: instance property of <code>BoardSetupFilterDefinitions</code>  
**Default**: <code>[]</code>  

#### currencyOptions

The org's currency setup (`getCurrencyOptions`); a single-currency org has no Currency picker.

**Kind**: instance property of <code>BoardSetupFilterDefinitions</code>  
**Default**: <code>null</code>  

#### config

The Setup dialog's draft config.

**Kind**: instance property (getter) of <code>BoardSetupFilterDefinitions</code>  
**Decorators**: <code>@api</code>  

#### isCurrencyUnavailable

Known to be a single-currency org: the Currency picker is unavailable (unknown while loading).

**Kind**: instance property (getter) of <code>BoardSetupFilterDefinitions</code>  

#### isAddCurrencyPickerDisabled

At most one Currency picker per Filter widget, and none in a single-currency org.

**Kind**: instance property (getter) of <code>BoardSetupFilterDefinitions</code>  

#### recordContext

The draft's Record context; its override follows the filters edited here.

**Kind**: instance property (getter) of <code>BoardSetupFilterDefinitions</code>  

#### bucketFields

The Board-level Bucket fields a Bucket filter can use (edited in the Bucket fields step).

**Kind**: instance property (getter) of <code>BoardSetupFilterDefinitions</code>  

#### addItem(item)

Appends `item` to the list and selects it.

**Kind**: instance method of <code>BoardSetupFilterDefinitions</code>  

#### handleItemRemove(event)

A removed filter also drops the Record context override that pointed at it.

**Kind**: instance method of <code>BoardSetupFilterDefinitions</code>  

#### validation

The Filter widget's own validation rules applied to the draft filters.

**Kind**: instance property (getter) of <code>BoardSetupFilterDefinitions</code>  

#### errorsByIndex

Messages per draft filter.

**Kind**: instance property (getter) of <code>BoardSetupFilterDefinitions</code>  

#### recordContextErrors

Problems of the carried Record context against the draft filters (e.g. its override filter was renamed onto a
duplicate id or now resolves to a filter of the wrong type). Same rule as the Filter widget's `validate()`.

**Kind**: instance property (getter) of <code>BoardSetupFilterDefinitions</code>  

#### picklistDefault(filter, optionsSource)

Choices of the PICKLIST default editor: custom options or the described picklist values.

**Kind**: instance method of <code>BoardSetupFilterDefinitions</code>  

#### loadDefaultSupport()

Loads described picklist values and record names the default-value editors display.

**Kind**: instance method of <code>BoardSetupFilterDefinitions</code>  

#### update(patch)

Applies `{ filters?, recordContext? }` to the list and fires it as one draft change (`detail.patch`). The older
Board-level `currencyPicker` key is dropped: the Currency picker lives in `filters`.

**Kind**: instance method of <code>BoardSetupFilterDefinitions</code>  

#### handleNumberField(event)

A Number range's field; a currency field is marked so the bar names the Display currency its bounds use.

**Kind**: instance method of <code>BoardSetupFilterDefinitions</code>  

#### handleNumberDefault(event)

Default min (`from`) or max (`to`) of a Number range; no default when both are blank.

**Kind**: instance method of <code>BoardSetupFilterDefinitions</code>  

#### addDefaultValue(index, value)

Adds a default value (replacing the current one, including Me, on single-select filters).

**Kind**: instance method of <code>BoardSetupFilterDefinitions</code>  

#### bucketFieldOptions

Combobox options of the Board-level Bucket fields, by id.

**Kind**: instance property (getter) of <code>BoardSetupFilterDefinitions</code>  

#### retargetRecordContext(patch, fromId, toId)

Keeps the Record context override pointing at a renamed filter (or clears it when removed / retyped).

**Kind**: instance method of <code>BoardSetupFilterDefinitions</code>

## Files

- `boardSetupFilterDefinitions.css`
- `boardSetupFilterDefinitions.html`
- `boardSetupFilterDefinitions.js`
- `boardSetupFilterDefinitions.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
