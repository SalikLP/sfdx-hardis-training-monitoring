/**
 * Formula measure evaluation context: one slot per Measure of a Widget, A = Measure 1 … F = Measure 6.
 *
 * `FormulaEval` only evaluates against a deployed `global` Apex class with `global` members (a `public` class fails
 * to build, verified in an org), so this class is `global`. Its shape is fixed: Measures are mapped to slots by
 * position, never by name. Used only by `BoardFormula`.
 */
global class BoardFormulaContext {
    global Decimal A;
    global Decimal B;
    global Decimal C;
    global Decimal D;
    global Decimal E;
    global Decimal F;
}