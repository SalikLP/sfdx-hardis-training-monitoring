<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeObjectFieldPicker

<!-- LWC description -->

## JS Documentation

### traversalTarget(field)

Polymorphic lookups traverse to `User` when possible, matching `BoardQueryService` path resolution.

**Kind**: global function  

### BoardCpeObjectFieldPicker

Searchable object picker (`mode="object"`), capability-filtered field picker with 1–5 hop parent dot-path and
`Child(ForeignKey).Field` builder (`mode="field"`), and child relationship selector (`mode="childRelationship"`),
backed by `BoardSchemaService`.

Fires a non-bubbling `change` event: `{ value, object }` (object), `{ value, field, objectApiName }` (field, where
`objectApiName` is the leaf field's object), `{ value: 'Child(FK)', childRelationship }` (childRelationship), or
`{ value: null }` when cleared.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### fieldLevelHelp

Help text shown next to the label.

**Kind**: instance property of <code>BoardCpeObjectFieldPicker</code>  
**Decorators**: <code>@api</code>  

#### capability

Comma-separated capabilities every selectable field must have: filterable, groupable, sortable, numeric, date
(Date/DateTime/Time), picklist (Picklist/Multi-Select Picklist). `|` joins alternatives within one entry, e.g. `numeric|date`.

**Kind**: instance property of <code>BoardCpeObjectFieldPicker</code>  
**Decorators**: <code>@api</code>  

#### maxHops

Parent relationship hops allowed in a field path (0–5, default 5).

**Kind**: instance property (getter) of <code>BoardCpeObjectFieldPicker</code>  
**Decorators**: <code>@api</code>  

#### requiredTests

One predicate per comma entry; each entry passes when any of its `|` alternatives does.

**Kind**: instance property (getter) of <code>BoardCpeObjectFieldPicker</code>

## Files

- `boardCpeObjectFieldPicker.css`
- `boardCpeObjectFieldPicker.html`
- `boardCpeObjectFieldPicker.js`
- `boardCpeObjectFieldPicker.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
