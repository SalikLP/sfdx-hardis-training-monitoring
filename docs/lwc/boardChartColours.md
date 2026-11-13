<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardChartColours

<!-- LWC description -->

## JS Documentation

### LIGHT_SURFACE

Surfaces a chart colour must stand out on: the SLDS light and dark Widget backgrounds.

**Kind**: global constant  
**Default**: <code>'#ffffff'</code>  

### SLDS_NAMED_COLOURS

The named SLDS colour set a fixed colour is picked from: the SLDS mid-scale (50) palette hues, each ≥ 3:1 on the
light and dark surfaces. A custom hex outside this set is the advanced option.

**Kind**: global constant  
**Default**: <code>[...]</code>  

### namedColourOf(colour)

The named colour for a hex value, or undefined for a custom hex.

**Kind**: global function  

### contrastRatio(a, b)

WCAG contrast ratio of two hex colours.

**Kind**: global function  

### contrastWarning(colour)

A warning when a hex colour's contrast is below 3:1 on the light or the dark surface (ratio rounded down, so 2.96
reads 2.9:1), or null when it is readable on both or is not a hex colour.

**Kind**: global function  

### fixedColourErrors(fixedColours)

Design-time errors of a Widget's fixed colours (`[{ value, colour }]`).

**Kind**: global function  

### valueKey(value)

A record Id compares on its case-sensitive 15-character form; any other stored value compares as is.

**Kind**: global function  

### fixedColourLookup(fixedColours)

Lookup of a stored value's fixed colour: the first entry for a value wins.

**Kind**: global function  

### applyFixedColours(model, fixedColours)

The chart model with the Widget's fixed colours (`[{ value, colour }]`, keyed by stored value: picklist API value or
record Id) set as `color` on matching categories and, with a series field, series values. A fixed colour beats a
colour the value already carries; "Other", "(Blank)" and Measures are never pinned.

**Kind**: global function  

### bucketRuleLookup(bucketFields, reference)

Lookup of a Bucket field's bucket label to its rule colour: the first rule of a label with a colour wins.

**Kind**: global function  

### applyBucketRuleColours(model, config)

The chart model with Bucket rule colours set as `color` on the categories (grouped by a Bucket field) and series
values (split by one): a bucket's stored value is its label. Apply before `applyFixedColours`, so a Widget fixed
colour wins over a rule colour; "Other" and "(Blank)" are never coloured.

**Kind**: global function  

### resolveColours(items, theme)

Colour of each item in order: an item's own `color` wins; the others take palette colours in order, skipping the
palette colours that own colours in this list already use (so no two values share a colour while the palette lasts);
"Other" and "(Blank)" items get their greys and never use up a palette colour.

**Kind**: global function

## Files

- `boardChartColours.js`
- `boardChartColours.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
