<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardVisibilityWatcher

<!-- LWC description -->

## JS Documentation

### POLL_INTERVAL_MS

Shared visibility watcher for Widget roots: tells a Widget when it goes from rendered to not rendered (0×0, e.g.
inside a hidden App page tab) and back. Scrolling off-screen is not "hidden" (IntersectionObserver is not used).

Under Locker there is no ResizeObserver (and MutationObserver can't see the tab panel), so one shared timer polls
every registered root's size, paused while the browser tab is hidden. Under LWS one shared ResizeObserver does the
same job behind the same API.

**Kind**: global constant  
**Default**: <code>400</code>  

### watched

element -> { callbacks: Set<Function>, visible: boolean }

**Kind**: global constant  
**Default**: <code>new Map()</code>  

### isRendered(element)

A root counts as rendered unless it has no layout box (0×0).

**Kind**: global function  

### handleDocumentVisibilityChange()

Stops the timer while the browser tab is hidden; checks every root at once when it comes back.

**Kind**: global function  

### createHiddenDeferral(element, onShowStale)

Hidden-Widget deferral for one Widget root (no Admin setting). The Widget calls `deferIfHidden()` right before it
would send a new query: while the root is 0×0 it returns true and marks the Widget stale, so the Widget skips the
query. When the root is shown again and the Widget is stale, `onShowStale()` runs once; the Widget drops its old
result (showing its loading state, never stale data) and queries with the current Filter context. A Widget whose
filters didn't change while hidden is never stale and doesn't re-query. `dispose()` unregisters the root.

**Kind**: global function  

### watchVisibility(element, callback)

Registers a Widget root; `callback(visible)` fires on each 0×0 ↔ rendered transition after registration.
Returns the unregister function.

**Kind**: global function

## Files

- `boardVisibilityWatcher.js`
- `boardVisibilityWatcher.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
