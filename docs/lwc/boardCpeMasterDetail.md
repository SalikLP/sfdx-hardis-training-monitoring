<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeMasterDetail

<!-- LWC description -->

## JS Documentation

### BoardCpeMasterDetail

Master-detail editor inside a Setup dialog step (e.g. the Filter widget's Filters step): an ordered item list on the
left (select, move up/down, remove; an error icon on invalid items; rows reorder by drag handle too) and the selected
item's editor on the right (default slot). Add controls go in the `actions` slot under the list. The layout fills
the modal body's height; each pane scrolls on its own.

Stateless: the step owns the items and the selection and handles the non-bubbling events
`itemselect` (`{ key, index }`), `itemmove` (`{ index, offset }`, ±1 from the buttons or any offset from a drag), and `itemremove` (`{ index }`).

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### items

`[{ key, label, meta?, hasError? }]` in list order; `meta` shows as a badge (e.g. the filter type).

**Kind**: instance property of <code>BoardCpeMasterDetail</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>[]</code>  

#### selectedKey

Key of the selected item (highlighted, `aria-current`).

**Kind**: instance property of <code>BoardCpeMasterDetail</code>  
**Decorators**: <code>@api</code>  

#### listLabel

Accessible name of the list (e.g. "Filters").

**Kind**: instance property of <code>BoardCpeMasterDetail</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>''</code>  

#### emptyMessage

Shown instead of the list when there are no items.

**Kind**: instance property of <code>BoardCpeMasterDetail</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>''</code>  

#### drag

Drag-to-reorder state (see the drag helpers in c/boardCpeUtils).

**Kind**: instance property of <code>BoardCpeMasterDetail</code>  
**Default**: <code>NO_DRAG</code>  

#### focusSelected()

Moves focus to the selected item's select button (e.g. after a remove).

**Kind**: instance method of <code>BoardCpeMasterDetail</code>  
**Decorators**: <code>@api</code>

## Files

- `boardCpeMasterDetail.css`
- `boardCpeMasterDetail.html`
- `boardCpeMasterDetail.js`
- `boardCpeMasterDetail.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
