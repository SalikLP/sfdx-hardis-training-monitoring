<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardDisplayCurrency

<!-- LWC description -->

## JS Documentation

### displayCurrencyFormat([format], [currencyIsoCode])

The ValueFormatConfig to format one value with: a currency format follows the returned ISO code (a `currencyCode`
saved by an older format editor is ignored), and falls back to a plain number when the value carries no ISO code,
so a count or percentage is never shown as money.

**Kind**: global function  

| Param | Type | Description |
| --- | --- | --- |
| [format] | <code>object</code> | ValueFormatConfig |
| [currencyIsoCode] | <code>string</code> | ISO code Apex returned with the value, or null when it is not a currency amount |

### configAmounts([rules])

Admin-entered amounts (in the Board's Config currency) a request sends for Apex to convert to the Display
currency: one number per rule, or null when the rule has no numeric value. Used for Metric thresholds.

**Kind**: global function  

| Param | Type | Description |
| --- | --- | --- |
| [rules] | <code>object[]</code> | rules with a `value` (e.g. Metric thresholds) |

### displayAmount(rule, index, [displayAmounts])

A rule's amount in the Display currency: the converted amount Apex returned at the rule's index
(`displayAmounts`, present when the value is a currency amount), else the amount as entered.

**Kind**: global function  

| Param | Type | Description |
| --- | --- | --- |
| rule | <code>object</code> | rule with a `value` |
| index | <code>number</code> | the rule's index in the list sent with `configAmounts` |
| [displayAmounts] | <code>number[]</code> | converted amounts returned by Apex |

## Files

- `boardDisplayCurrency.js`
- `boardDisplayCurrency.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
