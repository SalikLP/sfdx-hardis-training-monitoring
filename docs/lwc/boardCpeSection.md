<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeSection

<!-- LWC description -->

## JS Documentation

### BoardCpeSection

Config section: one collapsible group of settings in a Config editor, built on the SLDS expandable section
blueprint. The header is a real `<button>` (`aria-expanded` / `aria-controls`) showing the title, the one-line
`summary` while collapsed, and an error icon while `has-error` is set.

Open state is supplied by the parent (`open`) and changed by the Admin: each header click flips it and fires a
non-bubbling `toggle` event (`detail: { name, open }`) so a parent that tracks the state can mirror it. A section
with `has-error` is forced open and cannot be collapsed; once the error clears it stays open (no collapse while the
Admin is still fixing it) until the Admin collapses it.

The slotted content is always rendered and only hidden while collapsed, so control state survives a collapse.

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### label

Section title shown in the header.

**Kind**: instance property of <code>BoardCpeSection</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>''</code>  

#### summary

One-line summary shown in the header while the section is collapsed.

**Kind**: instance property of <code>BoardCpeSection</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>''</code>  

#### name

Identifies the section in `toggle` events.

**Kind**: instance property of <code>BoardCpeSection</code>  
**Decorators**: <code>@api</code>  

#### open

Whether the section is expanded. Always true while `hasError` is set.

**Kind**: instance property (getter) of <code>BoardCpeSection</code>  
**Decorators**: <code>@api</code>  

#### hasError

Shows the error indicator and forces the section open.

**Kind**: instance property (getter) of <code>BoardCpeSection</code>  
**Decorators**: <code>@api</code>

## Files

- `boardCpeSection.css`
- `boardCpeSection.html`
- `boardCpeSection.js`
- `boardCpeSection.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
