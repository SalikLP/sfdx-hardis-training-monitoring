/**
 * Bucket fields in a Widget config: `bucketFields: [{ id, label, rules: [{ label, condition, colour }],
 * fallback: { label, exclude } }]`. Each rule's `condition` is a condition tree (`{ logic, conditions[] }`) edited with
 * the shared condition editor; the first matching rule labels a row, else the fallback bucket (or the row is left out).
 * A Widget uses a Bucket field by putting `bucket:<id>` where it takes a group or series field. The server
 * (`BoardBucketField`) applies the same rules.
 */

export const BUCKET_REFERENCE_PREFIX = 'bucket:';
export const MAX_BUCKET_RULES = 25;
export const DEFAULT_BUCKET_FALLBACK_LABEL = 'Other';
const ID_PREFIX = 'bucket';

function text(value) {
    return typeof value === 'string' ? value.trim() : '';
}

function isPlainObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

/** `bucket:<id>`: how a group or series field references a Bucket field. */
export function bucketReference(id) {
    return `${BUCKET_REFERENCE_PREFIX}${id}`;
}

/** The Bucket field id a group or series field references, or null for a plain field path. */
export function bucketIdOf(fieldReference) {
    const value = text(fieldReference);
    return value.startsWith(BUCKET_REFERENCE_PREFIX) ? value.slice(BUCKET_REFERENCE_PREFIX.length).trim() : null;
}

export function newBucketRule() {
    return { label: '', condition: { logic: 'AND', conditions: [] } };
}

/** A new Bucket field with one empty rule and the "Other" fallback; its id `bucketN` is unused in `existing`. */
export function newBucketField(existing) {
    const taken = (Array.isArray(existing) ? existing : [])
        .map((field) => (isPlainObject(field) ? text(field.id) : ''))
        .map((id) => (id.startsWith(ID_PREFIX) ? Number(id.slice(ID_PREFIX.length)) : NaN))
        .filter((n) => Number.isInteger(n));
    const next = taken.length ? Math.max(...taken) + 1 : 1;
    return {
        id: `${ID_PREFIX}${next}`,
        label: '',
        rules: [newBucketRule()],
        fallback: { label: DEFAULT_BUCKET_FALLBACK_LABEL, exclude: false }
    };
}

/** Combobox options of the Bucket fields: label (or id) and `bucket:<id>`. */
export function bucketFieldOptions(bucketFields) {
    return (Array.isArray(bucketFields) ? bucketFields : [])
        .filter((field) => isPlainObject(field) && text(field.id))
        .map((field) => ({ label: text(field.label) || field.id, value: bucketReference(text(field.id)) }));
}

/**
 * Combobox options of a Widget's own Bucket fields, then the Board's (labelled `(Board)`) not shadowed by an own one
 * with the same id.
 */
export function ownAndBoardBucketFieldOptions(bucketFields, boardBucketFields) {
    const own = bucketFieldOptions(bucketFields);
    const ownValues = new Set(own.map((option) => option.value));
    const board = bucketFieldOptions(boardBucketFields)
        .filter((option) => !ownValues.has(option.value))
        .map((option) => ({ ...option, label: `${option.label} (Board)` }));
    return [...own, ...board];
}

/** The Bucket fields that the config's `keys` (e.g. `groupByField`, `stackByField`) reference, once each. */
export function referencedBucketFields(config, keys) {
    const source = isPlainObject(config) ? config : {};
    const ids = new Set(keys.map((key) => bucketIdOf(source[key])).filter(Boolean));
    return (Array.isArray(source.bucketFields) ? source.bucketFields : []).filter(
        (field) => isPlainObject(field) && ids.has(text(field.id))
    );
}

/**
 * The Bucket fields that the config's `keys` reference, split by where they are defined: the Widget's own
 * `bucketFields` first, else the Board-level ones its Filter widget publishes (`boardBucketFields`). `missing` lists
 * `{ key, id }` of references defined in neither.
 */
export function resolveReferencedBucketFields(config, keys, boardBucketFields) {
    const source = isPlainObject(config) ? config : {};
    const widgetFields = referencedBucketFields(source, keys);
    const widgetIds = new Set(widgetFields.map((field) => text(field.id)));
    const boardIds = new Set();
    const missing = [];
    keys.forEach((key) => {
        const id = bucketIdOf(source[key]);
        if (id === null || widgetIds.has(id)) {
            return;
        }
        if (findBucketField(boardBucketFields, id)) {
            boardIds.add(id);
        } else {
            missing.push({ key, id });
        }
    });
    return {
        bucketFields: widgetFields,
        boardBucketFields: (Array.isArray(boardBucketFields) ? boardBucketFields : []).filter(
            (field) => isPlainObject(field) && boardIds.has(text(field.id))
        ),
        missing
    };
}

/** Message of a Bucket field reference defined neither in the Widget nor on the Board. */
export function unknownBucketFieldMessage(label, id) {
    return `${label} uses an unknown Bucket field "${id}". Define it in this Widget or in the Board's Filter widget.`;
}

/** The Bucket fields that Table columns reference (`fieldPath: 'bucket:<id>'`), once each, in definition order. */
export function columnBucketFields(bucketFields, columns) {
    const ids = new Set(
        (Array.isArray(columns) ? columns : []).map((column) => bucketIdOf(column?.fieldPath)).filter(Boolean)
    );
    return (Array.isArray(bucketFields) ? bucketFields : []).filter(
        (field) => isPlainObject(field) && ids.has(text(field.id))
    );
}

/** The Bucket field `id` among `bucketFields`, or null. */
export function findBucketField(bucketFields, id) {
    return (
        (Array.isArray(bucketFields) ? bucketFields : []).find(
            (field) => isPlainObject(field) && id && text(field.id) === id
        ) || null
    );
}

/**
 * Every bucket label of a Bucket field once, in rule order, then the fallback label (default "Other") unless the
 * fallback excludes leftover rows: the options of a Bucket filter. Mirrors `BoardBucketField.labels()`.
 */
export function bucketLabels(bucketField) {
    if (!isPlainObject(bucketField)) {
        return [];
    }
    const labels = [];
    (Array.isArray(bucketField.rules) ? bucketField.rules : []).forEach((rule) => {
        const label = isPlainObject(rule) ? text(rule.label) : '';
        if (label && !labels.includes(label)) {
            labels.push(label);
        }
    });
    const fallback = isPlainObject(bucketField.fallback) ? bucketField.fallback : {};
    const fallbackLabel = text(fallback.label) || DEFAULT_BUCKET_FALLBACK_LABEL;
    if (fallback.exclude !== true && !labels.includes(fallbackLabel)) {
        labels.push(fallbackLabel);
    }
    return labels;
}

/**
 * Design-time problems of a `bucketFields` list (messages). `conditionError(tree)` returns the first problem of a
 * rule's condition tree, or null (the Config editor passes the shared Base filter validation).
 */
export function bucketFieldErrors(bucketFields, conditionError) {
    if (bucketFields === undefined || bucketFields === null) {
        return [];
    }
    if (!Array.isArray(bucketFields)) {
        return ['Bucket fields must be a list.'];
    }
    const errors = [];
    const ids = new Set();
    bucketFields.forEach((field, index) => {
        const safe = isPlainObject(field) ? field : {};
        const label = text(safe.label);
        const name = label ? `Bucket field "${label}"` : `Bucket field ${index + 1}`;
        const id = text(safe.id);
        if (!id) {
            errors.push(`${name}: id is required.`);
        } else if (ids.has(id)) {
            errors.push(`${name}: duplicate id "${id}".`);
        }
        ids.add(id);
        if (!label) {
            errors.push(`${name}: enter a label.`);
        }
        const rules = Array.isArray(safe.rules) ? safe.rules : [];
        if (!rules.length) {
            errors.push(`${name}: add at least one rule.`);
        } else if (rules.length > MAX_BUCKET_RULES) {
            errors.push(`${name}: at most ${MAX_BUCKET_RULES} rules.`);
            return;
        }
        rules.forEach((rule, ruleIndex) => {
            const safeRule = isPlainObject(rule) ? rule : {};
            const prefix = `${name}, rule ${ruleIndex + 1}`;
            if (!text(safeRule.label)) {
                errors.push(`${prefix}: enter a label.`);
            }
            const problem = isPlainObject(safeRule.condition)
                ? conditionError(safeRule.condition)
                : 'Add at least one condition.';
            if (problem) {
                errors.push(`${prefix}: ${problem}`);
            }
        });
    });
    return errors;
}