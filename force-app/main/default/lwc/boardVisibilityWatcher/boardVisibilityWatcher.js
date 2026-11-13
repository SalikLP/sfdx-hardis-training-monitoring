/**
 * Shared visibility watcher for Widget roots: tells a Widget when it goes from rendered to not rendered (0×0, e.g.
 * inside a hidden App page tab) and back. Scrolling off-screen is not "hidden" (IntersectionObserver is not used).
 *
 * Under Locker there is no ResizeObserver (and MutationObserver can't see the tab panel), so one shared timer polls
 * every registered root's size, paused while the browser tab is hidden. Under LWS one shared ResizeObserver does the
 * same job behind the same API.
 */

const POLL_INTERVAL_MS = 400;

/** element -> { callbacks: Set<Function>, visible: boolean } */
const watched = new Map();
let pollTimer = null;
let resizeObserver = null;
let visibilityListener = null;

/** A root counts as rendered unless it has no layout box (0×0). */
export function isRendered(element) {
    return Boolean(element) && (element.offsetWidth > 0 || element.offsetHeight > 0);
}

function documentHidden() {
    return typeof document !== 'undefined' && document.hidden === true;
}

function hasResizeObserver() {
    return typeof window !== 'undefined' && typeof window.ResizeObserver === 'function';
}

function check(element) {
    const entry = watched.get(element);
    if (!entry) {
        return;
    }
    const visible = isRendered(element);
    if (visible === entry.visible) {
        return;
    }
    entry.visible = visible;
    [...entry.callbacks].forEach((callback) => callback(visible));
}

function poll() {
    [...watched.keys()].forEach(check);
}

function startPolling() {
    if (pollTimer || resizeObserver || !watched.size || documentHidden()) {
        return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- Locker has no ResizeObserver; poll root sizes instead
    pollTimer = setInterval(poll, POLL_INTERVAL_MS);
}

function stopPolling() {
    if (pollTimer) {
        clearInterval(pollTimer);
        pollTimer = null;
    }
}

/** Stops the timer while the browser tab is hidden; checks every root at once when it comes back. */
function handleDocumentVisibilityChange() {
    if (documentHidden()) {
        stopPolling();
        return;
    }
    poll();
    startPolling();
}

function listenToDocumentVisibility(listen) {
    if (typeof document === 'undefined' || Boolean(visibilityListener) === listen) {
        return;
    }
    if (listen) {
        visibilityListener = handleDocumentVisibilityChange;
        document.addEventListener('visibilitychange', visibilityListener);
    } else {
        document.removeEventListener('visibilitychange', visibilityListener);
        visibilityListener = null;
    }
}

function observe(element) {
    if (!resizeObserver && !pollTimer && hasResizeObserver()) {
        resizeObserver = new window.ResizeObserver((entries) => {
            entries.forEach((entry) => check(entry.target));
        });
    }
    if (resizeObserver) {
        resizeObserver.observe(element);
        return;
    }
    listenToDocumentVisibility(true);
    startPolling();
}

function unobserve(element) {
    if (resizeObserver) {
        resizeObserver.unobserve(element);
    }
    if (watched.size) {
        return;
    }
    stopPolling();
    listenToDocumentVisibility(false);
    if (resizeObserver) {
        resizeObserver.disconnect();
        resizeObserver = null;
    }
}

/**
 * Hidden-Widget deferral for one Widget root (no Admin setting). The Widget calls `deferIfHidden()` right before it
 * would send a new query: while the root is 0×0 it returns true and marks the Widget stale, so the Widget skips the
 * query. When the root is shown again and the Widget is stale, `onShowStale()` runs once; the Widget drops its old
 * result (showing its loading state, never stale data) and queries with the current Filter context. A Widget whose
 * filters didn't change while hidden is never stale and doesn't re-query. `dispose()` unregisters the root.
 */
export function createHiddenDeferral(element, onShowStale) {
    let stale = false;
    const unwatch = watchVisibility(element, (visible) => {
        if (visible && stale && isRendered(element)) {
            stale = false;
            onShowStale();
        }
    });
    return {
        deferIfHidden() {
            if (isRendered(element)) {
                return false;
            }
            stale = true;
            // Record the hidden state now, so a show before the next poll is still a transition.
            check(element);
            return true;
        },
        dispose() {
            stale = false;
            unwatch();
        }
    };
}

/**
 * Registers a Widget root; `callback(visible)` fires on each 0×0 ↔ rendered transition after registration.
 * Returns the unregister function.
 */
export function watchVisibility(element, callback) {
    if (!element || typeof callback !== 'function') {
        return () => {};
    }
    let entry = watched.get(element);
    if (!entry) {
        entry = { callbacks: new Set(), visible: isRendered(element) };
        watched.set(element, entry);
        observe(element);
    }
    entry.callbacks.add(callback);
    return () => {
        const current = watched.get(element);
        if (!current || !current.callbacks.delete(callback) || current.callbacks.size) {
            return;
        }
        watched.delete(element);
        unobserve(element);
    };
}