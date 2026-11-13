/**
 * A Formula measure's formula, built once with `FormulaEval` and evaluated per category (and per panel).
 *
 * The formula is Salesforce formula syntax over slots A–F (`BoardFormulaContext`): A is the Widget's first Measure,
 * B the second, and so on; slot names are case-insensitive. `build` validates the formula (syntax, unknown slot or
 * function, non-number result) and fails with an Admin-readable `CONFIG_ERROR`. `evaluate` never fails: a blank input
 * gives a blank result (`treatNumericNullAsZero` stays false) and a division by zero gives blank, never zero.
 */
public with sharing class BoardFormula {
    /** Slot names in Measure order. */
    public static final List<String> SLOTS = new List<String>{ 'A', 'B', 'C', 'D', 'E', 'F' };

    /** The Formula measure's currency flag (`isCurrency`): its result is an amount (`BoardFormulaCurrency`). */
    public Boolean isCurrency = false;

    private FormulaEval.FormulaInstance instance;
    private Set<Integer> inputs = new Set<Integer>();

    private BoardFormula(FormulaEval.FormulaInstance instance) {
        this.instance = instance;
        for (String field : instance.getReferencedFields()) {
            Integer position = SLOTS.indexOf(field == null ? '' : field.trim().toUpperCase());
            if (position >= 0) {
                inputs.add(position);
            }
        }
    }

    /** Validates and builds formula `text`; a bad formula fails with the `FormulaEval` message as a `CONFIG_ERROR`. */
    public static BoardFormula build(String text) {
        if (String.isBlank(text)) {
            throw configError('Enter a formula, e.g. A / B or 15000.');
        }
        FormulaEval.FormulaInstance instance;
        try {
            instance = Formula.builder()
                .withType(BoardFormulaContext.class)
                .withReturnType(FormulaEval.FormulaReturnType.DECIMAL)
                .withFormula(text)
                .treatNumericNullAsZero(false)
                .build();
        } catch (Exception invalid) {
            // FormulaValidationException: "Syntax error. Extra ')'", "Field Z does not exist. Check spelling."...
            throw configError(invalid.getMessage());
        }
        return new BoardFormula(instance);
    }

    /** Indexes (0 = A) of the slots the formula references. */
    public Set<Integer> inputIndexes() {
        return inputs.clone();
    }

    /** The result for one category: `values[i]` fills slot i (missing slots are blank); blank on any error. */
    public Decimal evaluate(List<Decimal> values) {
        BoardFormulaContext context = new BoardFormulaContext();
        context.A = slot(values, 0);
        context.B = slot(values, 1);
        context.C = slot(values, 2);
        context.D = slot(values, 3);
        context.E = slot(values, 4);
        context.F = slot(values, 5);
        Object result;
        try {
            result = instance.evaluate(context);
        } catch (Exception evaluationError) {
            // FormulaEvaluationException: "Division by zero" / "Division undefined" → blank, never an error.
            return null;
        }
        if (result == null) {
            return null;
        }
        return result instanceof Decimal ? (Decimal) result : Decimal.valueOf(String.valueOf(result));
    }

    private static Decimal slot(List<Decimal> values, Integer index) {
        return values == null || index >= values.size() ? null : values[index];
    }

    private static BoardErrors.BoardException configError(String message) {
        return BoardErrors.error(BoardErrors.CONFIG_ERROR, message, null, 'measures');
    }
}