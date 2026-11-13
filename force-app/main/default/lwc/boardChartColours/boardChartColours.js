/**
 * Pure colour resolution of the Chart widget. Colour precedence for a coloured value (a series value, or a category
 * when colouring by category): the Widget's fixed colour for its stored value, then its Bucket rule colour
 * (`applyBucketRuleColours`, or any colour the value already carries), then the palette in order, skipping palette colours already taken by fixed colours in
 * that chart. "Other" and "(Blank)" stay grey.
 */

import { bucketIdOf, findBucketField } from 'c/boardBucketFields';

const OTHER_GREY = '#747474';
const BLANK_GREY = '#9a9a9a';

const same = (a, b) => String(a).toLowerCase() === String(b).toLowerCase();

/** Surfaces a chart colour must stand out on: the SLDS light and dark Widget backgrounds. */
const LIGHT_SURFACE = '#ffffff';
const DARK_SURFACE = '#181818';
const MIN_CONTRAST = 3;
const HEX_COLOUR = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i;

/**
 * The named SLDS colour set a fixed colour is picked from: the SLDS mid-scale (50) palette hues, each ≥ 3:1 on the
 * light and dark surfaces. A custom hex outside this set is the advanced option.
 */
export const SLDS_NAMED_COLOURS = [
    { label: 'Blue', value: '#0176d3' },
    { label: 'Teal', value: '#0b827c' },
    { label: 'Orange', value: '#a96404' },
    { label: 'Pink', value: '#e3066a' },
    { label: 'Indigo', value: '#5867e8' },
    { label: 'Hot orange', value: '#d83a00' },
    { label: 'Green', value: '#2e844a' },
    { label: 'Purple', value: '#9050e9' },
    { label: 'Yellow', value: '#8a6d00' },
    { label: 'Violet', value: '#b0409a' },
    { label: 'Cloud blue', value: '#2f8fa0' },
    { label: 'Red', value: '#c23934' }
];

/** The named colour for a hex value, or undefined for a custom hex. */
export function namedColourOf(colour) {
    return SLDS_NAMED_COLOURS.find((option) => same(option.value, colour || ''));
}

function relativeLuminance(hex) {
    const digits = hex.slice(1);
    const full = digits.length === 3 ? [...digits].map((digit) => digit + digit).join('') : digits;
    const [r, g, b] = [0, 2, 4].map((offset) => {
        const channel = parseInt(full.slice(offset, offset + 2), 16) / 255;
        return channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG contrast ratio of two hex colours. */
function contrastRatio(a, b) {
    const [high, low] = [relativeLuminance(a), relativeLuminance(b)].sort((x, y) => y - x);
    return (high + 0.05) / (low + 0.05);
}

/**
 * A warning when a hex colour's contrast is below 3:1 on the light or the dark surface (ratio rounded down, so 2.96
 * reads 2.9:1), or null when it is readable on both or is not a hex colour.
 */
export function contrastWarning(colour) {
    const hex = typeof colour === 'string' ? colour.trim() : '';
    if (!HEX_COLOUR.test(hex)) {
        return null;
    }
    const low = [
        { name: 'light', ratio: contrastRatio(hex, LIGHT_SURFACE) },
        { name: 'dark', ratio: contrastRatio(hex, DARK_SURFACE) }
    ].filter((surface) => surface.ratio < MIN_CONTRAST);
    if (!low.length) {
        return null;
    }
    const parts = low.map(
        (surface) => `${(Math.floor(surface.ratio * 10) / 10).toFixed(1)}:1 on the ${surface.name} surface`
    );
    return `Low contrast: ${parts.join(' and ')} (below 3:1). The colour may be hard to see.`;
}

/** Design-time errors of a Widget's fixed colours (`[{ value, colour }]`). */
export function fixedColourErrors(fixedColours) {
    if (fixedColours === undefined || fixedColours === null) {
        return [];
    }
    if (!Array.isArray(fixedColours)) {
        return ['Fixed colours must be a list.'];
    }
    const errors = [];
    const values = new Set();
    const colours = new Map();
    fixedColours.forEach((entry, index) => {
        const label = `Fixed colour ${index + 1}`;
        const safe = entry && typeof entry === 'object' ? entry : {};
        const value = safe.value === undefined || safe.value === null ? '' : String(safe.value).trim();
        const colour = typeof safe.colour === 'string' ? safe.colour.trim() : '';
        if (!value) {
            errors.push(`${label}: enter the stored value (picklist API value or record Id).`);
        } else if (values.has(valueKey(value))) {
            errors.push(`${label}: "${value}" already has a fixed colour.`);
            return;
        }
        if (!HEX_COLOUR.test(colour)) {
            errors.push(`${label}: colour must be a hex colour such as #0176d3.`);
            return;
        }
        if (!value) {
            return;
        }
        values.add(valueKey(value));
        const owner = colours.get(colour.toLowerCase());
        if (owner !== undefined) {
            errors.push(`${label}: ${colour} is already used by "${owner}"; no two values share a colour.`);
            return;
        }
        colours.set(colour.toLowerCase(), value);
    });
    return errors;
}

const SALESFORCE_ID = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;

/** A record Id compares on its case-sensitive 15-character form; any other stored value compares as is. */
function valueKey(value) {
    const text = String(value);
    return SALESFORCE_ID.test(text) && /\d/.test(text) ? text.slice(0, 15) : text;
}

/** Lookup of a stored value's fixed colour: the first entry for a value wins. */
function fixedColourLookup(fixedColours) {
    const lookup = new Map();
    (Array.isArray(fixedColours) ? fixedColours : []).forEach((entry) => {
        if (entry && entry.value !== undefined && entry.value !== null && entry.value !== '' && entry.colour) {
            const key = valueKey(entry.value);
            if (!lookup.has(key)) {
                lookup.set(key, entry.colour);
            }
        }
    });
    return lookup;
}

/**
 * The chart model with the Widget's fixed colours (`[{ value, colour }]`, keyed by stored value: picklist API value or
 * record Id) set as `color` on matching categories and, with a series field, series values. A fixed colour beats a
 * colour the value already carries; "Other", "(Blank)" and Measures are never pinned.
 */
export function applyFixedColours(model, fixedColours) {
    const lookup = fixedColourLookup(fixedColours);
    if (!model || !lookup.size) {
        return model;
    }
    const pin = (item, storedValue) => {
        if (item.isOther || item.isBlank || storedValue === null || storedValue === undefined) {
            return item;
        }
        const colour = lookup.get(valueKey(storedValue));
        return colour ? { ...item, color: colour } : item;
    };
    return {
        ...model,
        categories: model.categories.map((category) => pin(category, category.value)),
        series: model.hasSeries ? model.series.map((entry) => pin(entry, entry.colourKey)) : model.series
    };
}

/** Lookup of a Bucket field's bucket label to its rule colour: the first rule of a label with a colour wins. */
function bucketRuleLookup(bucketFields, reference) {
    const id = bucketIdOf(reference);
    const field = id === null ? null : findBucketField(bucketFields, id);
    const lookup = new Map();
    ((field && Array.isArray(field.rules) && field.rules) || []).forEach((rule) => {
        const colour = rule && typeof rule.colour === 'string' ? rule.colour.trim() : '';
        if (colour && rule.label !== undefined && rule.label !== null && !lookup.has(String(rule.label))) {
            lookup.set(String(rule.label), colour);
        }
    });
    return lookup;
}

/**
 * The chart model with Bucket rule colours set as `color` on the categories (grouped by a Bucket field) and series
 * values (split by one): a bucket's stored value is its label. Apply before `applyFixedColours`, so a Widget fixed
 * colour wins over a rule colour; "Other" and "(Blank)" are never coloured.
 */
export function applyBucketRuleColours(model, config) {
    const safe = config || {};
    const categoryRules = bucketRuleLookup(safe.bucketFields, safe.groupByField);
    const seriesRules = model && model.hasSeries ? bucketRuleLookup(safe.bucketFields, safe.stackByField) : new Map();
    if (!model || (!categoryRules.size && !seriesRules.size)) {
        return model;
    }
    const paint = (items, rules, storedValueOf) => {
        if (!rules.size) {
            return items;
        }
        return items.map((item) => {
            const stored = storedValueOf(item);
            if (item.isOther || item.isBlank || stored === null || stored === undefined) {
                return item;
            }
            const colour = rules.get(String(stored));
            return colour ? { ...item, color: colour } : item;
        });
    };
    return {
        ...model,
        categories: paint(model.categories, categoryRules, (category) => category.value),
        series: paint(model.series, seriesRules, (entry) => entry.colourKey)
    };
}

/**
 * Colour of each item in order: an item's own `color` wins; the others take palette colours in order, skipping the
 * palette colours that own colours in this list already use (so no two values share a colour while the palette lasts);
 * "Other" and "(Blank)" items get their greys and never use up a palette colour.
 */
export function resolveColours(items, theme) {
    const taken = items.filter((item) => item.color).map((item) => item.color);
    const free = theme.palette.filter((color) => !taken.some((fixed) => same(fixed, color)));
    const palette = free.length ? free : theme.palette;
    let next = 0;
    return items.map((item) => {
        if (item.color) {
            return item.color;
        }
        if (item.isOther) {
            return theme.otherColor || OTHER_GREY;
        }
        if (item.isBlank) {
            return theme.blankColor || BLANK_GREY;
        }
        const color = palette[next % palette.length];
        next += 1;
        return color;
    });
}