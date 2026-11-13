<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardCpeTotalRow

<!-- LWC description -->

## JS Documentation

### DEFAULT_SUMMARIES

Columns with no summaries get Sum when the Admin turns the Total row on.

**Kind**: global constant  
**Default**: <code>['SUM']</code>  

### BoardCpeTotalRow

Total row editor of the Table Config editor: the Total row on/off and, per numeric column, an ordered list of 1–4
Stacked summaries (Sum, Average, Min, Max). Numeric columns are found from the field describe of each column path.
Fires a non-bubbling `change` event with `detail.showTotalRow` (true or null) and `detail.columns` (the full
column array with `summaries` set or removed).

**Kind**: global class  
**Extends**: <code>LightningElement</code>  

#### grouped

Row grouping is on: Group and Subtotal rows show the summaries, so the pickers show with the Total row off.

**Kind**: instance property of <code>BoardCpeTotalRow</code>  
**Decorators**: <code>@api</code>  
**Default**: <code>false</code>  

#### numericByPath

Lower-cased field path -> true when the column's field is numeric.

**Kind**: instance property of <code>BoardCpeTotalRow</code>  
**Default**: <code>{}</code>  

#### resolveNumericColumns()

Looks up which column paths are numeric (describes are memoized per object).

**Kind**: instance async method of <code>BoardCpeTotalRow</code>  

#### summaryRows

One summary picker per numeric column.

**Kind**: instance property (getter) of <code>BoardCpeTotalRow</code>

## Files

- `boardCpeTotalRow.html`
- `boardCpeTotalRow.js`
- `boardCpeTotalRow.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
