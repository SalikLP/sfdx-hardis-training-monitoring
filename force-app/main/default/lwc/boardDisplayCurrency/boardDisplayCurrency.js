/**
 * Display currency formatting shared by the Widgets. Apex converts every currency amount (SUM, AVG, MIN, MAX of a
 * currency field) to the Board's Display currency and returns its ISO code next to the value; counts, percentages
 * and other values come back without one. The client only formats.
 */

/**
 * The ValueFormatConfig to format one value with: a currency format follows the returned ISO code (a `currencyCode`
 * saved by an older format editor is ignored), and falls back to a plain number when the value carries no ISO code,
 * so a count or percentage is never shown as money.
 * @param {object} [format] ValueFormatConfig
 * @param {string} [currencyIsoCode] ISO code Apex returned with the value, or null when it is not a currency amount
 */
export function displayCurrencyFormat(format, currencyIsoCode) {
    const { currencyCode, ...rest } = format || {}; // eslint-disable-line no-unused-vars
    if (rest.formatStyle !== 'currency') {
        return rest;
    }
    return currencyIsoCode ? { ...rest, currencyCode: currencyIsoCode } : { ...rest, formatStyle: 'number' };
}

/**
 * Admin-entered amounts (in the Board's Config currency) a request sends for Apex to convert to the Display
 * currency: one number per rule, or null when the rule has no numeric value. Used for Metric thresholds.
 * @param {object[]} [rules] rules with a `value` (e.g. Metric thresholds)
 */
export function configAmounts(rules) {
    return (Array.isArray(rules) ? rules : []).map((rule) => {
        const raw = rule?.value;
        const amount = raw === '' || raw === null || raw === undefined ? NaN : Number(raw);
        return Number.isFinite(amount) ? amount : null;
    });
}

/**
 * A rule's amount in the Display currency: the converted amount Apex returned at the rule's index
 * (`displayAmounts`, present when the value is a currency amount), else the amount as entered.
 * @param {object} rule rule with a `value`
 * @param {number} index the rule's index in the list sent with `configAmounts`
 * @param {number[]} [displayAmounts] converted amounts returned by Apex
 */
export function displayAmount(rule, index, displayAmounts) {
    const converted = Array.isArray(displayAmounts) ? displayAmounts[index] : null;
    if (converted !== null && converted !== undefined && Number.isFinite(Number(converted))) {
        return Number(converted);
    }
    return Number(rule?.value);
}