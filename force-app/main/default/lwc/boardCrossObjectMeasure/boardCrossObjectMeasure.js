/**
 * Cross-object measures: a Chart or Metric Measure whose rows come from its own `sourceObject` (e.g. a target object)
 * instead of the Widget's object. Shape on top of a Measure: `{ sourceObject, categoryMapping, panelMapping,
 * filterBindings, dataProvider }`. `categoryMapping`: the field on the source object matching the Widget's category
 * (a date field groups at the Widget's date granularity); `panelMapping`: the field matching the Panel field (Small
 * multiples); `filterBindings`: `{ filterId: fieldPath | 'IGNORE' }`, the Measure's own Filter bindings (unbound
 * filters bind by convention only where the field exists on the source object); `dataProvider`: an Apex Data provider
 * class supplying this Measure's values instead of the source object's query. The server (`BoardCrossObjectMeasures`)
 * joins its values onto the Widget's categories and reports per Measure the filters it ignores and whether it is blank.
 */

function isPlainObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function text(value) {
    return typeof value === 'string' && value.trim() ? value.trim() : null;
}

/** True when `measure` is a Cross-object measure (a non-Formula Measure with a source object). */
export function isCrossObjectMeasure(measure) {
    return (
        isPlainObject(measure) &&
        Boolean(text(measure.sourceObject)) &&
        String(measure.aggregateFunction || '').toUpperCase() !== 'FORMULA'
    );
}

/** The Measure's own Filter bindings without blank keys; null when it has none. */
function cleanBindings(bindings) {
    if (!isPlainObject(bindings)) {
        return null;
    }
    const entries = Object.entries(bindings).filter(([filterId]) => text(filterId));
    return entries.length ? Object.fromEntries(entries) : null;
}

/** The Cross-object part of a Measure (`{}` for any other Measure), as the query request sends it. */
export function crossObjectRequestFields(measure) {
    if (!isCrossObjectMeasure(measure)) {
        return {};
    }
    const fields = { sourceObject: text(measure.sourceObject) };
    ['categoryMapping', 'panelMapping'].forEach((key) => {
        if (text(measure[key])) {
            fields[key] = text(measure[key]);
        }
    });
    const bindings = cleanBindings(measure.filterBindings);
    if (bindings) {
        fields.filterBindings = bindings;
    }
    if (text(measure.dataProvider)) {
        fields.dataProvider = text(measure.dataProvider);
    }
    return fields;
}

/**
 * Design-time errors (`[message]`) of a Widget config's Cross-object measures, mirroring the server's blocked
 * combinations: Average per record and COUNT_DISTINCT; on the Chart widget also a series (Stack by) field, a Bucket
 * field category, a missing category mapping, and Small multiples (`panelField`) without a panel mapping.
 */
export function crossObjectMeasureErrors(config, widgetType) {
    const measures = Array.isArray(config && config.measures) ? config.measures : [];
    const errors = [];
    measures.forEach((measure, index) => {
        if (!isCrossObjectMeasure(measure)) {
            return;
        }
        const label = `Measure ${index + 1}`;
        const source = text(measure.sourceObject);
        const fn = String(measure.aggregateFunction || 'COUNT').toUpperCase();
        if (fn === 'AVG_PER' || fn === 'COUNT_DISTINCT') {
            const name = fn === 'AVG_PER' ? 'Average per record' : fn;
            errors.push(`${label}: ${name} isn't available on a Cross-object measure.`);
        }
        if (widgetType !== 'chart') {
            return;
        }
        if (text(config.stackByField)) {
            errors.push(
                `${label}: a Cross-object measure can't be used with a series field. Remove the Stack by field or the source object.`
            );
        }
        const groupByField = text(config.groupByField);
        if (groupByField && groupByField.toLowerCase().startsWith('bucket:')) {
            errors.push(
                `${label}: a Cross-object measure can't join on a Bucket field category. Group by a plain field, or supply this Widget's results from a Data provider.`
            );
        }
        if (!text(measure.categoryMapping)) {
            errors.push(
                `${label}: map a field on ${source} to the category (Group by field) so its rows line up with the chart.`
            );
        }
        if (text(config.panelField) && !text(measure.panelMapping)) {
            errors.push(
                `${label}: with Small multiples, map a field on ${source} to the Panel field too (panel mapping).`
            );
        }
    });
    return errors;
}

/**
 * Inline notices of a query result's `crossObjectNotices`: a blank Measure the viewer can't access, and the filters a
 * Cross-object measure ignores. `measureLabels[i]` names Measure i; `filterLabels` maps a filter id to its label.
 * @returns {Array<{ key: string, message: string, isBlank: boolean }>}
 */
export function crossObjectNotices(notices, measureLabels = [], filterLabels = new Map()) {
    if (!Array.isArray(notices)) {
        return [];
    }
    const result = [];
    notices.forEach((notice) => {
        if (!notice) {
            return;
        }
        const index = notice.measureIndex;
        const label = measureLabels[index] || `Measure ${index + 1}`;
        if (notice.isBlank) {
            result.push({
                key: `blank-${index}`,
                isBlank: true,
                message: `${label} is blank: you don't have access to its data (${notice.sourceObject}).`
            });
            return;
        }
        const ignored = Array.isArray(notice.ignoredFilterIds) ? notice.ignoredFilterIds : [];
        if (ignored.length) {
            const names = ignored.map((filterId) => filterLabels.get(filterId) || filterId).join(', ');
            result.push({
                key: `ignored-${index}`,
                isBlank: false,
                message: `${label} ignores these filters (not on ${notice.sourceObject}): ${names}.`
            });
        }
    });
    return result;
}