<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCursorProgress

<!-- LWC description -->

## JS Documentation

### formatCount(count)

A row or group count in the user's locale (e.g. `1,234`); one shared `Intl.NumberFormat`.

**Kind**: global function  

### buildCursorProgress(processedRows, totalRows)

`{ processedRows, totalRows, percent, label }` for the SLDS progress bar and its row counter.

**Kind**: global function  

### runCursorLoad({ first, fetchNext, isCurrent, merge, onProgress })

Drives a chunked cursor load. Each chunk is merged into the caller's accumulator via `merge`; `onProgress` fires
after every incomplete chunk. `isCurrent` gates every step so a superseded run stops fetching and never reports.
Resolves true only when the last chunk merged while still current (caller may then render the final result).

**Kind**: global function

## Files

- `boardCursorProgress.js`
- `boardCursorProgress.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
