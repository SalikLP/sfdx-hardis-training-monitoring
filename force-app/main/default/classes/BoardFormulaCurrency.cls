/**
 * Currency of a Formula measure's evaluation (currency.md, measures.md).
 *
 * - An unflagged Formula measure reads its amount inputs as the viewer sees them, in the Display currency, and its
 *   result is never converted (no ISO code): a ratio or a percentage stays the same in every Display currency.
 * - A Formula measure flagged `isCurrency` returns an amount. Its constants (a target such as `15000`) are written in
 *   the Config currency, so it is evaluated in the Config currency: amount inputs are converted to it, the formula
 *   runs, and the result is converted back to the currency the inputs came in (the Display currency on the Metric
 *   widget, corporate on the Chart widget, where every amount is converted to the Display currency after shaping).
 * - Counts and other non-amount inputs never convert. Single-currency orgs: evaluated as entered.
 */
public with sharing class BoardFormulaCurrency {
    private final BoardCurrencyConverter converter;
    /** The request's Display currency; null in single-currency orgs (nothing converts). */
    private final String displayIsoCode;
    private final String configIsoCode;

    public BoardFormulaCurrency(BoardCurrencyConverter converter, Map<String, Object> request) {
        this.converter = converter;
        this.displayIsoCode = converter.isMultiCurrency() ? converter.displayIsoCode(request) : null;
        this.configIsoCode = converter.configIsoCode(request);
    }

    /**
     * `formula` over `values`, where `amounts[i]` marks the inputs that are amounts in `valuesIsoCode`. A flagged
     * formula's result is an amount in `valuesIsoCode`; an unflagged one's is a plain number.
     */
    public Decimal evaluate(BoardFormula formula, List<Decimal> values, List<Boolean> amounts, String valuesIsoCode) {
        if (displayIsoCode == null || valuesIsoCode == null || values == null) {
            return formula.evaluate(values);
        }
        String evaluationIsoCode = formula.isCurrency == true ? configIsoCode : displayIsoCode;
        List<Decimal> inputs = new List<Decimal>();
        for (Integer i = 0; i < values.size(); i++) {
            Boolean amount = amounts != null && i < amounts.size() && amounts[i] == true;
            inputs.add(amount ? converter.convert(values[i], valuesIsoCode, evaluationIsoCode) : values[i]);
        }
        Decimal result = formula.evaluate(inputs);
        return formula.isCurrency == true ? converter.convert(result, configIsoCode, valuesIsoCode) : result;
    }
}