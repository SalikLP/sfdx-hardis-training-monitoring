<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardChartUtils

<!-- LWC description -->

## JS Documentation

### PREFERS_DARK_QUERY

Shared Chart.js v4 engine for Board chart Widgets: singleton static resource loader, SLDS 1/2 theme sampler,
media query listeners, the SLDS Color-Safe categorical palette, and an inline bar data-label plugin.

**Kind**: global constant  
**Default**: <code>'(prefers-color-scheme: dark)'</code>  

### SLDS_COLOR_SAFE_PALETTE

6-color categorical palette: SLDS 2 mid-scale palette hooks `blue/teal/orange/pink/indigo/hot-orange-50`, constant in
light and dark mode (≥3:1 on both surfaces). Same values as the `--board-chart-palette-1..6` CSS fallbacks.

**Kind**: global constant  
**Default**: <code>['#0176d3', '#0b827c', '#a96404', '#e3066a', '#5867e8', '#d83a00']</code>  

### loadChartJs(component)

Loads the `chartjs` static resource (`chart.umd.min.js`) once per page and resolves to the `Chart` constructor.
A failed load is not cached, so a later call retries.

**Kind**: global function  

### resolveChartTheme(element)

Samples the `--board-chart-*` custom properties (backed by `--slds-g-*` styling hooks) declared on `element`, since
`<canvas>` drawing cannot resolve CSS `var()` references. SLDS 2 hooks may hold `light-dark(<light>, <dark>)`, which
canvas also cannot parse (it paints black), so each value is reduced to the branch for the element's color scheme.

**Kind**: global function  

### usesDarkColorScheme(style)

`light-dark()` follows the used color scheme: `dark` alone, or `light dark` while the OS prefers dark.

**Kind**: global function  

### resolveLightDark(value, dark)

Replaces every (possibly nested) `light-dark(a, b)` in `value` with `a` or `b`.

**Kind**: global function  

### watchMediaQuery(query, callback)

Calls `callback(matches)` whenever `query` changes; returns an unsubscribe function.

**Kind**: global function  

### watchColorScheme(callback)

Calls `callback()` when the page color scheme may have changed: the OS `prefers-color-scheme` media query, or a
`class`/`style`/`data-*` theme attribute change on `<html>`/`<body>` (in-app theme switches without a reload).
Callers compare the re-sampled theme before repainting. Returns an unsubscribe function.

**Kind**: global function  

### chartAnimation(reducedMotion)

In-place update animation: `300ms easeOutQuart`, or `0ms` when `prefers-reduced-motion: reduce` matches.

**Kind**: global function  

### createBarDataLabelsPlugin(formatValue)

Inline Chart.js plugin drawing formatted values at the end of each bar (or each stack total when
`options.stacked`). Enabled via `options.plugins.boardBarDataLabels.display`; `formatValue` stays in the closure
because Chart.js resolves plugin option functions as scriptable values.

**Kind**: global function

## Files

- `boardChartUtils.js`
- `boardChartUtils.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
