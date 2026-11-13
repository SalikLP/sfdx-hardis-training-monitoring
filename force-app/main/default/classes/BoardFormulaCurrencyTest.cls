/**
 * Currency of Formula measures (currency/07) with injected rates, so it runs in any org: XXA is corporate (rate 1),
 * XXB has rate 0.9 (1,000 XXA = 900 XXB). A currency-flagged Formula measure reads its constants in the Config
 * currency and returns an amount in the Display currency; an unflagged one reads its inputs as shown and never
 * converts.
 */
@IsTest
private class BoardFormulaCurrencyTest {
    private static final Decimal TOLERANCE = 0.0001;

    private static BoardCurrencyConverter converter() {
        return BoardCurrencyConverter.fromRates(
            new List<BoardCurrencyConverter.Rate>{
                new BoardCurrencyConverter.Rate('XXA', 1, true),
                new BoardCurrencyConverter.Rate('XXB', 0.9, false)
            }
        );
    }

    private static BoardFormulaCurrency evaluator(String display, String config) {
        return new BoardFormulaCurrency(
            converter(),
            new Map<String, Object>{ 'displayCurrency' => display, 'configCurrency' => config }
        );
    }

    private static BoardFormula formula(String text, Boolean isCurrency) {
        BoardFormula built = BoardFormula.build(text);
        built.isCurrency = isCurrency;
        return built;
    }

    @IsTest
    static void currencyFormulaReadsItsConstantInTheConfigCurrency() {
        // Display XXB, Config XXA: A = 900 XXB = 1,000 XXA; 1,000 - 15,000 = -14,000 XXA = -12,600 XXB.
        Decimal result = evaluator('XXB', 'XXA')
            .evaluate(formula('A - 15000', true), new List<Decimal>{ 900 }, new List<Boolean>{ true }, 'XXB');
        assertClose(-12600, result, 'Gap to a Config currency target, in the Display currency');
    }

    @IsTest
    static void constantOnlyCurrencyFormulaIsConvertedToTheDisplayCurrency() {
        Decimal result = evaluator('XXB', 'XXA')
            .evaluate(formula('15000', true), new List<Decimal>(), new List<Boolean>(), 'XXB');
        assertClose(13500, result, '15,000 XXA target shown in XXB');
    }

    @IsTest
    static void countInputsAreNeverConverted() {
        // A: 900 XXB amount (1,000 XXA), B: a count of 4. (1,000 / 4 + 100) XXA = 350 XXA = 315 XXB.
        Decimal result = evaluator('XXB', 'XXA')
            .evaluate(
                formula('A / B + 100', true),
                new List<Decimal>{ 900, 4 },
                new List<Boolean>{ true, false },
                'XXB'
            );
        assertClose(315, result, 'Count input kept as is');
    }

    @IsTest
    static void corporateInputsComeBackInTheCorporateCurrency() {
        // Chart rows are corporate: A = 1,000 XXA; Config XXB: 900 - 100 = 800 XXB = 888.8889 XXA.
        Decimal result = evaluator('XXB', 'XXB')
            .evaluate(formula('A - 100', true), new List<Decimal>{ 1000 }, new List<Boolean>{ true }, 'XXA');
        assertClose(888.8889, result, 'Flagged result back in the inputs\' currency');
    }

    @IsTest
    static void unflaggedFormulaReadsItsInputsInTheDisplayCurrency() {
        // Corporate A = 1,000 XXA is 900 XXB as shown; A - 100 = 800 (not converted back, no currency).
        Decimal result = evaluator('XXB', 'XXA')
            .evaluate(formula('A - 100', false), new List<Decimal>{ 1000 }, new List<Boolean>{ true }, 'XXA');
        assertClose(800, result, 'Unflagged formula over Display currency inputs');
        Decimal shown = evaluator('XXB', 'XXA')
            .evaluate(formula('A - 100', false), new List<Decimal>{ 900 }, new List<Boolean>{ true }, 'XXB');
        assertClose(800, shown, 'Same result from inputs already in the Display currency');
    }

    @IsTest
    static void singleCurrencyOrgsEvaluateAsEntered() {
        BoardFormulaCurrency single = new BoardFormulaCurrency(
            BoardCurrencyConverter.singleCurrency(),
            new Map<String, Object>()
        );
        Decimal result = single.evaluate(
            formula('A - 15000', true),
            new List<Decimal>{ 900 },
            new List<Boolean>{ true },
            null
        );
        assertClose(-14100, result, 'No conversion in a single-currency org');
    }

    @IsTest
    static void blankInputsGiveABlankResult() {
        Decimal result = evaluator('XXB', 'XXA')
            .evaluate(formula('A - 100', true), new List<Decimal>{ null }, new List<Boolean>{ true }, 'XXB');
        Assert.isNull(result);
    }

    private static void assertClose(Decimal expected, Decimal actual, String message) {
        Assert.isNotNull(actual, message);
        Assert.isTrue(Math.abs(expected - actual) <= TOLERANCE, message + ': expected ' + expected + ', got ' + actual);
    }
}