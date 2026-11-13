/**
 * Engine-unit seam of the Formula measure evaluator (`BoardFormula`): Measures in slots A–F, null propagation,
 * division by zero and Admin-readable build errors. No data, no SOQL.
 */
@IsTest
private class BoardFormulaTest {
    @IsTest
    static void evaluatesSlotsInMeasureOrder() {
        BoardFormula winRate = BoardFormula.build('A / B');

        Assert.areEqual(0.25, winRate.evaluate(new List<Decimal>{ 1, 4 }));
        Assert.areEqual(
            40,
            BoardFormula.build('IF(B < C, (C - A) * 4, C)').evaluate(new List<Decimal>{ 10, 5, 20 }),
            'Gap formula over three Measures'
        );
        Assert.areEqual(
            -6,
            BoardFormula.build('F - E').evaluate(new List<Decimal>{ null, null, null, null, 7, 1 }),
            'Slot F is the sixth Measure'
        );
    }

    @IsTest
    static void slotReferencesAreCaseInsensitive() {
        BoardFormula formula = BoardFormula.build('a / B');

        Assert.areEqual(2, formula.evaluate(new List<Decimal>{ 8, 4 }));
        Assert.areEqual(new Set<Integer>{ 0, 1 }, formula.inputIndexes());
    }

    @IsTest
    static void constantFormulaHasNoInputs() {
        BoardFormula target = BoardFormula.build('15000');

        Assert.areEqual(15000, target.evaluate(new List<Decimal>()));
        Assert.isTrue(target.inputIndexes().isEmpty());
    }

    @IsTest
    static void blankInputGivesBlankResultNotZero() {
        Assert.isNull(BoardFormula.build('A + B').evaluate(new List<Decimal>{ 10, null }));
        Assert.isNull(BoardFormula.build('A / B').evaluate(new List<Decimal>{ 10, null }));
        Assert.isNull(BoardFormula.build('A / B').evaluate(new List<Decimal>{ 10 }), 'A missing slot is blank');
    }

    @IsTest
    static void divisionByZeroGivesBlankResultNotAnError() {
        Assert.isNull(BoardFormula.build('A / B').evaluate(new List<Decimal>{ 10, 0 }));
        Assert.isNull(BoardFormula.build('A / B').evaluate(new List<Decimal>{ 0, 0 }));
    }

    @IsTest
    static void buildErrorsAreAdminReadable() {
        assertBuildError('A / ', 'Syntax');
        assertBuildError('A / Z', 'Z');
        assertBuildError('FOO(A)', 'FOO');
        assertBuildError('"text"', 'Decimal');
        assertBuildError('   ', 'Enter a formula');
        assertBuildError(null, 'Enter a formula');
    }

    private static void assertBuildError(String formula, String expectedFragment) {
        try {
            BoardFormula.build(formula);
        } catch (BoardErrors.BoardException error) {
            Assert.areEqual(BoardErrors.CONFIG_ERROR, error.category);
            Assert.isTrue(
                error.getMessage().containsIgnoreCase(expectedFragment),
                'Formula "' + formula + '": ' + error.getMessage()
            );
            return;
        }
        Assert.fail('Expected a build error for "' + formula + '"');
    }
}