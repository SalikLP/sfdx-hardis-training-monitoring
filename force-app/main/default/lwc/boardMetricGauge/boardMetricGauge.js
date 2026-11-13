/**
 * Metric widget Gauge: the pure model behind the Gauge display (no DOM, no Apex).
 *
 * Config (`display: 'gauge'` on the Metric widget):
 *   `gauge: { min?, minMeasure?, max?, maxMeasure?, bandsPercentOfMax?, targetMeasure? }`
 * - `min` / `max` are static numbers; `minMeasure` / `maxMeasure` are the 0-based position of a hidden Measure in the
 *   Measures list and win over the static number. `min` defaults to 0; `max` is required one way or the other.
 * - The Widget's Thresholds are the bands: each rule's value is absolute, or a percentage of max when
 *   `bandsPercentOfMax` is true. The scale is split at the rule limits and each part takes the status of the first
 *   rule matching it.
 * - `targetMeasure` is the position of a hidden Measure drawn as a marker.
 * - Currency: the static `min` / `max` and absolute bands are Admin amounts in the Board's Config currency. The request
 *   sends them (`gaugeConfigAmounts`, `thresholdAmounts`) and Apex returns them in the Display currency when the value
 *   is an amount; `gaugeConfigInDisplayCurrency` puts them back before `resolveGauge`. % of max bands never convert.
 */

export const DISPLAY_NUMBER = 'number';
export const DISPLAY_GAUGE = 'gauge';
export const DISPLAY_OPTIONS = [
    { label: 'Number', value: DISPLAY_NUMBER },
    { label: 'Gauge', value: DISPLAY_GAUGE }
];

const OPERATORS = {
    gt: (value, limit) => value > limit,
    gte: (value, limit) => value >= limit,
    lt: (value, limit) => value < limit,
    lte: (value, limit) => value <= limit
};
const VARIANTS = ['success', 'warning', 'error'];

function isObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isBlank(value) {
    return value === null || value === undefined || value === '';
}

function toNumber(value) {
    if (isBlank(value) || typeof value === 'boolean') {
        return null;
    }
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
}

/** Whether the Metric config asks for the Gauge. */
export function isGaugeDisplay(config) {
    return Boolean(config) && config.display === DISPLAY_GAUGE;
}

/** The Gauge settings with blanks as null. */
function gaugeSettings(config) {
    const gauge = isObject(config.gauge) ? config.gauge : {};
    const measureRef = (value) => (isBlank(value) ? null : Number(value));
    return {
        min: isBlank(gauge.min) ? null : gauge.min,
        minMeasure: measureRef(gauge.minMeasure),
        max: isBlank(gauge.max) ? null : gauge.max,
        maxMeasure: measureRef(gauge.maxMeasure),
        targetMeasure: measureRef(gauge.targetMeasure),
        bandsPercentOfMax: gauge.bandsPercentOfMax === true
    };
}

/**
 * The Gauge's static minimum and maximum, Admin amounts in the Config currency, for Apex to convert: `[min, max]`,
 * null for a blank one or one taken from a Measure.
 */
export function gaugeConfigAmounts(config) {
    const settings = gaugeSettings(config || {});
    return [
        settings.minMeasure === null ? toNumber(settings.min) : null,
        settings.maxMeasure === null ? toNumber(settings.max) : null
    ];
}

/**
 * The Metric config with the Gauge's static min / max (`gaugeAmounts`) and absolute bands (`thresholdAmounts`, one per
 * Threshold rule) replaced by the converted amounts Apex returned; null entries keep the amount as entered. Bands
 * read as % of max are percentages: never converted.
 */
export function gaugeConfigInDisplayCurrency(config, { gaugeAmounts, thresholdAmounts } = {}) {
    const converted = (list, index) => {
        const number = Array.isArray(list) ? toNumber(list[index]) : null;
        return number;
    };
    const gauge = isObject(config.gauge) ? { ...config.gauge } : {};
    const settings = gaugeSettings(config);
    [
        ['min', 0],
        ['max', 1]
    ].forEach(([key, index]) => {
        const number = converted(gaugeAmounts, index);
        if (settings[`${key}Measure`] === null && number !== null) {
            gauge[key] = number;
        }
    });
    let thresholds = config.thresholds;
    if (!settings.bandsPercentOfMax && Array.isArray(thresholds)) {
        thresholds = thresholds.map((rule, index) => {
            const number = converted(thresholdAmounts, index);
            return number === null || !isObject(rule) ? rule : { ...rule, value: number };
        });
    }
    return { ...config, gauge, thresholds };
}

function measureLabel(index) {
    return Number.isInteger(index) ? `Measure ${index + 1}` : 'that Measure';
}

/** Why Measure position `index` can't feed the Gauge as `role`, or '' when it can. */
function measureRefProblem(index, measures, role) {
    if (!Number.isInteger(index) || index < 0 || index >= measures.length) {
        return `Gauge ${role}: ${measureLabel(index)} does not exist. Choose a Hidden Measure from the list.`;
    }
    if (isObject(measures[index]) && measures[index].hidden !== true) {
        return `Gauge ${role}: Measure ${index + 1} is the visible Measure. Choose a Hidden Measure.`;
    }
    return '';
}

/**
 * Design-time problems of the Gauge settings as readable messages (`[]` when the config is valid or not a Gauge).
 * `measures` is the Metric's Measures list.
 */
export function gaugeConfigProblems(config, measures) {
    const problems = [];
    if (!isBlank(config.display) && config.display !== DISPLAY_NUMBER && config.display !== DISPLAY_GAUGE) {
        problems.push('Display must be number or gauge.');
    }
    if (!isGaugeDisplay(config)) {
        return problems;
    }
    const list = Array.isArray(measures) ? measures : [];
    const settings = gaugeSettings(config);
    [
        ['minimum', 'min', 'minMeasure'],
        ['maximum', 'max', 'maxMeasure']
    ].forEach(([role, staticKey, measureKey]) => {
        if (settings[measureKey] !== null) {
            const problem = measureRefProblem(settings[measureKey], list, role);
            if (problem) {
                problems.push(problem);
            }
        } else if (settings[staticKey] !== null) {
            if (toNumber(settings[staticKey]) === null) {
                problems.push(`Gauge ${role}: enter a number.`);
            }
        } else if (role === 'maximum') {
            problems.push('Gauge maximum: enter a number or choose a Hidden Measure.');
        }
    });
    if (settings.targetMeasure !== null) {
        const problem = measureRefProblem(settings.targetMeasure, list, 'target');
        if (problem) {
            problems.push(problem);
        }
    }
    const min = settings.minMeasure === null ? (settings.min === null ? 0 : toNumber(settings.min)) : null;
    const max = settings.maxMeasure === null ? toNumber(settings.max) : null;
    if (min !== null && max !== null && min >= max) {
        problems.push(`Gauge minimum (${min}) must be below the maximum (${max}).`);
    }
    return problems;
}

/** Absolute limit of a Threshold rule on the scale, or null for a rule that can't be drawn. */
function ruleLimit(rule, max, percentOfMax) {
    const limit = toNumber(rule && rule.value);
    if (limit === null || !OPERATORS[rule.operator] || !VARIANTS.includes(rule.variant)) {
        return null;
    }
    return percentOfMax ? (limit / 100) * max : limit;
}

/** The scale split at the rule limits: `[{ variant, startPct, widthPct }]`, consecutive equal statuses merged. */
function buildBands(thresholds, min, max, percentOfMax) {
    const rules = (Array.isArray(thresholds) ? thresholds : [])
        .map((rule) => ({ ...rule, limit: ruleLimit(rule, max, percentOfMax) }))
        .filter((rule) => rule.limit !== null);
    const cuts = [...new Set(rules.map((rule) => rule.limit).filter((limit) => limit > min && limit < max))].sort(
        (a, b) => a - b
    );
    const edges = [min, ...cuts, max];
    const bands = [];
    for (let i = 0; i < edges.length - 1; i++) {
        const middle = (edges[i] + edges[i + 1]) / 2;
        const match = rules.find((rule) => OPERATORS[rule.operator](middle, rule.limit));
        const variant = match ? match.variant : 'neutral';
        const widthPct = ((edges[i + 1] - edges[i]) / (max - min)) * 100;
        const previous = bands[bands.length - 1];
        if (previous && previous.variant === variant) {
            previous.widthPct += widthPct;
        } else {
            bands.push({ variant, startPct: ((edges[i] - min) / (max - min)) * 100, widthPct });
        }
    }
    return bands;
}

function clampPct(value, min, max) {
    return Math.min(100, Math.max(0, ((value - min) / (max - min)) * 100));
}

/**
 * Resolves the Gauge for one result.
 *
 * `input`: `{ config, value, measureValues, format }` where `value` is the visible Measure's number (or null),
 * `measureValues` the raw value of every Measure in list order, `format(number)` the label formatter. Returns
 * `{ model }` or `{ error }` (a readable message; the Widget shows it instead of the Gauge).
 *
 * `model`: `{ minLabel, maxLabel, valuePct (null without a value), valueLabel, bands: [{ key, variant, startPct,
 * widthPct }], target: { pct, label } | null }`, percentages 0–100 of the scale.
 */
export function resolveGauge({ config, value, measureValues, format }) {
    const values = Array.isArray(measureValues) ? measureValues : [];
    const settings = gaugeSettings(config);
    const fromMeasure = (index, role) => {
        const problem = measureRefProblem(index, values, role);
        if (problem) {
            return { error: problem };
        }
        const number = toNumber(values[index]);
        return number === null ? { error: `Gauge ${role}: Measure ${index + 1} has no value.` } : { number };
    };
    const edge = (role, staticKey, measureKey, fallback) => {
        if (settings[measureKey] !== null) {
            return fromMeasure(settings[measureKey], role);
        }
        const number = settings[staticKey] === null ? fallback : toNumber(settings[staticKey]);
        return number === null ? { error: `Gauge ${role}: enter a number or choose a Hidden Measure.` } : { number };
    };
    const min = edge('minimum', 'min', 'minMeasure', 0);
    const max = edge('maximum', 'max', 'maxMeasure', null);
    if (min.error || max.error) {
        return { error: min.error || max.error };
    }
    if (min.number >= max.number) {
        return { error: `Gauge minimum (${min.number}) must be below the maximum (${max.number}).` };
    }
    let target = null;
    if (settings.targetMeasure !== null) {
        const resolved = fromMeasure(settings.targetMeasure, 'target');
        if (resolved.error) {
            return { error: resolved.error };
        }
        target = { pct: clampPct(resolved.number, min.number, max.number), label: format(resolved.number) };
    }
    const hasValue = value !== null && value !== undefined;
    return {
        model: {
            minLabel: format(min.number),
            maxLabel: format(max.number),
            valuePct: hasValue ? clampPct(value, min.number, max.number) : null,
            valueLabel: hasValue ? format(value) : '',
            bands: buildBands(config.thresholds, min.number, max.number, settings.bandsPercentOfMax).map(
                (band, index) => ({ ...band, key: `band-${index}` })
            ),
            target
        }
    };
}