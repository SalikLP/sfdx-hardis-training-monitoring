<!-- This file is auto-generated. if you do not want it to be overwritten, set TRUE in the line below -->
<!-- DO_NOT_OVERWRITE_DOC=FALSE -->

# boardBucketFields

<!-- LWC description -->

## JS Documentation

### BUCKET_REFERENCE_PREFIX

Bucket fields in a Widget config: `bucketFields: [{ id, label, rules: [{ label, condition, colour }],
fallback: { label, exclude } }]`. Each rule's `condition` is a condition tree (`{ logic, conditions[] }`) edited with
the shared condition editor; the first matching rule labels a row, else the fallback bucket (or the row is left out).
A Widget uses a Bucket field by putting `bucket:<id>` where it takes a group or series field. The server
(`BoardBucketField`) applies the same rules.

**Kind**: global constant  
**Default**: <code>'bucket:'</code>  

### bucketReference(id)

`bucket:<id>`: how a group or series field references a Bucket field.

**Kind**: global function  

### bucketIdOf(fieldReference)

The Bucket field id a group or series field references, or null for a plain field path.

**Kind**: global function  

### newBucketField(existing)

A new Bucket field with one empty rule and the "Other" fallback; its id `bucketN` is unused in `existing`.

**Kind**: global function  

### bucketFieldOptions(bucketFields)

Combobox options of the Bucket fields: label (or id) and `bucket:<id>`.

**Kind**: global function  

### referencedBucketFields(config, keys)

The Bucket fields that the config's `keys` (e.g. `groupByField`, `stackByField`) reference, once each.

**Kind**: global function  

### resolveReferencedBucketFields(config, keys, boardBucketFields)

The Bucket fields that the config's `keys` reference, split by where they are defined: the Widget's own
`bucketFields` first, else the Board-level ones its Filter widget publishes (`boardBucketFields`). `missing` lists
`{ key, id }` of references defined in neither.

**Kind**: global function  

### unknownBucketFieldMessage(label, id)

Message of a Bucket field reference defined neither in the Widget nor on the Board.

**Kind**: global function  

### columnBucketFields(bucketFields, columns)

The Bucket fields that Table columns reference (`fieldPath: 'bucket:<id>'`), once each, in definition order.

**Kind**: global function  

### findBucketField(bucketFields, id)

The Bucket field `id` among `bucketFields`, or null.

**Kind**: global function  

### bucketLabels(bucketField)

Every bucket label of a Bucket field once, in rule order, then the fallback label (default "Other") unless the
fallback excludes leftover rows: the options of a Bucket filter. Mirrors `BoardBucketField.labels()`.

**Kind**: global function  

### bucketFieldErrors(bucketFields, conditionError)

Design-time problems of a `bucketFields` list (messages). `conditionError(tree)` returns the first problem of a
rule's condition tree, or null (the Config editor passes the shared Base filter validation).

**Kind**: global function

## Files

- `boardBucketFields.js`
- `boardBucketFields.js-meta.xml`



[![SFDX-Hardis is provided by Cloudity](https://raw.githubusercontent.com/hardisgroupcom/sfdx-hardis/refs/heads/main/docs/assets/images/cloudity-banner.png)](https://cloudity.com?ref=sfdxhardis)

_Documentation generated with [sfdx-hardis](https://sfdx-hardis.cloudity.com), by [Cloudity](https://www.cloudity.com/) & [friends](https://github.com/hardisgroupcom/sfdx-hardis/graphs/contributors)_
