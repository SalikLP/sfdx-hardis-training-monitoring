/**
 * `BoardCondition.wholeNumberField`: conditions on Integer / Long fields bind whole numbers only (SOQL rejects a
 * Decimal bind there), translating a non-whole value into the equivalent whole-number condition. Pure: the compiled
 * SOQL with its binds, and the in-memory evaluation over rows with values 11, 12 and null.
 */
@IsTest
private class BoardConditionWholeNumberTest {
    private static final String PATH = 'ContractTerm';

    @IsTest
    static void wholeValuesBindAsIntegerOrLong() {
        Binder binder = new Binder();
        String soql = BoardCondition.wholeNumberField(
                'f',
                PATH,
                'GTE',
                new List<Object>{ Decimal.valueOf('12.0') },
                false
            )
            .toSoql(binder);
        Assert.areEqual('ContractTerm >= :b0', soql);
        Assert.isTrue(binder.binds.get('b0') instanceof Integer, 'Integer bind: ' + binder.binds.get('b0'));

        binder = new Binder();
        BoardCondition.wholeNumberField('f', PATH, 'EQ', new List<Object>{ Decimal.valueOf(12) }, true).toSoql(binder);
        Assert.isTrue(binder.binds.get('b0') instanceof Long, 'Long bind: ' + binder.binds.get('b0'));
    }

    @IsTest
    static void nonWholeComparisonsBecomeTheEquivalentWholeNumberComparison() {
        assertCondition('GTE', 11.5, 'ContractTerm >= :b0', 12, new List<Boolean>{ false, true, false });
        assertCondition('GT', 11.5, 'ContractTerm >= :b0', 12, new List<Boolean>{ false, true, false });
        assertCondition('LTE', 11.5, 'ContractTerm <= :b0', 11, new List<Boolean>{ true, false, false });
        assertCondition('LT', 11.5, 'ContractTerm <= :b0', 11, new List<Boolean>{ true, false, false });
        assertCondition('LT', -0.5, 'ContractTerm <= :b0', -1, new List<Boolean>{ false, false, false });
    }

    @IsTest
    static void nonWholeEqualityMatchesNothingAndInequalityEverything() {
        BoardCondition.Node equal = node('EQ', new List<Object>{ 11.5 });
        Assert.areEqual('(ContractTerm = null) AND (ContractTerm != null)', stripped(equal));
        Assert.areEqual(new List<Boolean>{ false, false, false }, evaluateAll(equal));

        BoardCondition.Node notEqual = node('NEQ', new List<Object>{ 11.5 });
        Assert.areEqual('(ContractTerm = null) OR (ContractTerm != null)', stripped(notEqual));
        Assert.areEqual(new List<Boolean>{ true, true, true }, evaluateAll(notEqual), 'SOQL != keeps empty rows too');
    }

    @IsTest
    static void inListsDropNonWholeValues() {
        Binder binder = new Binder();
        BoardCondition.Node inList = node('IN', new List<Object>{ 11.5, 12, Decimal.valueOf('11.0') });
        Assert.areEqual('ContractTerm IN :b0', inList.toSoql(binder));
        Assert.areEqual(new List<Integer>{ 12, 11 }, (List<Integer>) binder.binds.get('b0'));
        Assert.areEqual(new List<Boolean>{ true, true, false }, evaluateAll(inList));

        Assert.areEqual(new List<Boolean>{ false, false, false }, evaluateAll(node('IN', new List<Object>{ 11.5 })));
        Assert.areEqual(
            new List<Boolean>{ true, true, true },
            evaluateAll(node('NOT_IN', new List<Object>{ 11.5 })),
            'Nothing left to exclude'
        );
        Assert.areEqual(new List<Boolean>{ true, false, true }, evaluateAll(node('NOT_IN', new List<Object>{ 12 })));
    }

    @IsTest
    static void nullsAndOtherOperatorsAreUnchanged() {
        Assert.areEqual('ContractTerm = null', node('EQ', new List<Object>{ null }).toSoql(new Binder()));
    }

    private static void assertCondition(
        String operator,
        Decimal value,
        String expectedSoql,
        Integer expectedBind,
        List<Boolean> expectedMatches
    ) {
        BoardCondition.Node condition = node(operator, new List<Object>{ value });
        Binder binder = new Binder();
        Assert.areEqual(expectedSoql, condition.toSoql(binder), operator + ' ' + value);
        Assert.areEqual(expectedBind, binder.binds.get('b0'), operator + ' ' + value);
        Assert.areEqual(expectedMatches, evaluateAll(condition), operator + ' ' + value);
    }

    private static BoardCondition.Node node(String operator, List<Object> values) {
        return BoardCondition.wholeNumberField('f', PATH, operator, values, false);
    }

    /** SOQL with bind names left out, so `= null` / `!= null` read as written. */
    private static String stripped(BoardCondition.Node condition) {
        return condition.toSoql(new Binder());
    }

    /** Matches for rows with the field 11, 12 and empty. */
    private static List<Boolean> evaluateAll(BoardCondition.Node condition) {
        List<Boolean> matches = new List<Boolean>();
        for (Object value : new List<Object>{ 11, 12, null }) {
            matches.add(condition.evaluate(new Map<String, Object>{ PATH => value }));
        }
        return matches;
    }

    private class Binder implements BoardCondition.Binder {
        Map<String, Object> binds = new Map<String, Object>();

        public String bind(Object value, Boolean isLikePattern) {
            String name = 'b' + binds.size();
            binds.put(name, value);
            return ':' + name;
        }
    }
}