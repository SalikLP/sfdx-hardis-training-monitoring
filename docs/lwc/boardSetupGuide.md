<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardSetupGuide

<!-- LWC description -->

## JS Documentation

### NON_CONTENT_KEYS

Keys that don't count as Widget content: the envelope, the title (set in the panel) and the Board-level settings
(Board id, which Flow Builder pre-fills with its meta default "default"; Wait for Filter widget; Config currency).

**Kind**: global constant  
**Default**: <code>['version', 'widgetType', 'title', 'boardId', 'waitForFilterWidget', 'configCurrency']</code>  

### DEFAULT_VALUES

Defaults the config envelope writes for a Widget nobody has set up yet (`orderConfig` in `c/boardCpeUtils`).

**Kind**: global constant  
**Default**: <code>{ chartType: 'bar' }</code>  

### opensGuided(config, [references])

True when the Setup dialog opens in Guided mode: the Widget has no Data / Measures / Columns / Filters content
(only the envelope, Board-level settings and defaults) and no content key bound to a Flow resource (`references`).

**Kind**: global function  

### guidedNav(steps, current, [invalidSteps])

Guided mode navigation from step `current` over `steps`, given the names of the currently invalid steps:
`{ backStep, nextStep, canNext, lockedSteps }`. A step is locked (can't be reached yet) while a required step
before it is invalid; Next goes to the next step when it isn't locked. Back is always available on any step but
the first.

**Kind**: global function

## Files

- `boardSetupGuide.js`
- `boardSetupGuide.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
