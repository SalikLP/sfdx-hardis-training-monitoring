/**
 * Engine-unit seam for the condition model: every case compiles a `BoardCondition` tree to `SOQL` and evaluates it in
 * memory against the same rows, and both must return exactly the expected records (SOQL semantics: case-insensitive
 * text, null handling, AND/OR, IN/NOT IN, ranges, absolute and relative dates).
 */
@IsTest
private class BoardConditionTest {
    private static final String FIELDS = 'Id, Name, Amount, LeadSource, NextStep, CloseDate, CreatedDate';

    @TestSetup
    static void insertOpportunities() {
        Date today = Date.today();
        insert new List<Opportunity>{
            new Opportunity(
                Name = 'Acme Deal',
                StageName = 'Prospecting',
                Amount = 100,
                LeadSource = 'Web',
                NextStep = 'Call back',
                CloseDate = today
            ),
            new Opportunity(
                Name = 'Beta Deal',
                StageName = 'Prospecting',
                Amount = 250,
                CloseDate = today.addDays(-10)
            ),
            new Opportunity(
                Name = 'gamma deal',
                StageName = 'Prospecting',
                LeadSource = 'Phone Inquiry',
                NextStep = 'call later',
                CloseDate = today.addDays(-100)
            ),
            new Opportunity(
                Name = 'Delta Big',
                StageName = 'Prospecting',
                Amount = 1000,
                LeadSource = 'Web',
                CloseDate = today.addDays(40)
            )
        };
    }

    /** One table row: a condition and the Opportunity names it must keep. */
    private class ConditionCase {
        String name;
        BoardCondition.Node condition;
        Set<String> expected;

        ConditionCase(String name, BoardCondition.Node condition, List<String> expected) {
            this.name = name;
            this.condition = condition;
            this.expected = new Set<String>(expected);
        }
    }

    /** Collects binds the way a query scope does, so the compiled clause runs through `queryWithBinds`. */
    private class MapBinder implements BoardCondition.Binder {
        Map<String, Object> binds = new Map<String, Object>();
        Set<String> likePatterns = new Set<String>();

        public String bind(Object value, Boolean isLikePattern) {
            String name = 'b' + binds.size();
            binds.put(name, value);
            if (isLikePattern) {
                likePatterns.add(name);
            }
            return ':' + name;
        }
    }

    private static BoardCondition.Node leaf(String path, String operator, Object value) {
        return BoardCondition.field('f', path, operator, new List<Object>{ value });
    }

    private static BoardCondition.Node leafList(String path, String operator, List<Object> values) {
        return BoardCondition.field('f', path, operator, values);
    }

    private static List<ConditionCase> cases() {
        Date today = Date.today();
        Datetime startOfToday = Datetime.newInstance(today, Time.newInstance(0, 0, 0, 0));
        return new List<ConditionCase>{
            // Case-insensitive text
            new ConditionCase('text EQ ignores case', leaf('Name', 'EQ', 'acme deal'), new List<String>{ 'Acme Deal' }),
            new ConditionCase(
                'text IN ignores case',
                leafList('Name', 'IN', new List<String>{ 'BETA DEAL', 'Gamma Deal' }),
                new List<String>{ 'Beta Deal', 'gamma deal' }
            ),
            new ConditionCase(
                'LIKE prefix ignores case',
                leaf('Name', 'LIKE', 'ACME%'),
                new List<String>{ 'Acme Deal' }
            ),
            new ConditionCase(
                'LIKE suffix ignores case',
                leaf('Name', 'LIKE', '%DEAL'),
                new List<String>{ 'Acme Deal', 'Beta Deal', 'gamma deal' }
            ),
            new ConditionCase(
                'LIKE single-character wildcard',
                leaf('Name', 'LIKE', '_eta%'),
                new List<String>{ 'Beta Deal' }
            ),
            new ConditionCase(
                'LIKE never matches null',
                leaf('NextStep', 'LIKE', 'call%'),
                new List<String>{ 'Acme Deal', 'gamma deal' }
            ),
            // Nulls
            new ConditionCase(
                'EQ null keeps empty values',
                leaf('NextStep', 'EQ', null),
                new List<String>{ 'Beta Deal', 'Delta Big' }
            ),
            new ConditionCase(
                'NEQ null keeps filled values',
                leaf('Amount', 'NEQ', null),
                new List<String>{ 'Acme Deal', 'Beta Deal', 'Delta Big' }
            ),
            new ConditionCase(
                'NEQ value keeps nulls and ignores case',
                leaf('NextStep', 'NEQ', 'CALL BACK'),
                new List<String>{ 'Beta Deal', 'gamma deal', 'Delta Big' }
            ),
            new ConditionCase(
                'GT never matches null',
                leaf('Amount', 'GT', 100),
                new List<String>{ 'Beta Deal', 'Delta Big' }
            ),
            new ConditionCase(
                'LTE never matches null',
                leaf('Amount', 'LTE', 250),
                new List<String>{ 'Acme Deal', 'Beta Deal' }
            ),
            // IN / NOT IN
            new ConditionCase(
                'picklist IN ignores case',
                leafList('LeadSource', 'IN', new List<String>{ 'web' }),
                new List<String>{ 'Acme Deal', 'Delta Big' }
            ),
            new ConditionCase(
                'NOT IN keeps nulls',
                leafList('LeadSource', 'NOT_IN', new List<String>{ 'WEB' }),
                new List<String>{ 'Beta Deal', 'gamma deal' }
            ),
            new ConditionCase(
                'number IN',
                leafList('Amount', 'IN', new List<Decimal>{ 100, 1000 }),
                new List<String>{ 'Acme Deal', 'Delta Big' }
            ),
            // AND / OR
            new ConditionCase(
                'range as AND',
                BoardCondition.allOf(
                    new List<BoardCondition.Node>{ leaf('Amount', 'GTE', 100), leaf('Amount', 'LTE', 250) }
                ),
                new List<String>{ 'Acme Deal', 'Beta Deal' }
            ),
            new ConditionCase(
                'OR across fields',
                BoardCondition.anyOf(
                    new List<BoardCondition.Node>{ leaf('Name', 'EQ', 'ACME DEAL'), leaf('Amount', 'GT', 500) }
                ),
                new List<String>{ 'Acme Deal', 'Delta Big' }
            ),
            new ConditionCase(
                'AND of OR',
                BoardCondition.allOf(
                    new List<BoardCondition.Node>{
                        leaf('LeadSource', 'EQ', 'web'),
                        BoardCondition.anyOf(
                            new List<BoardCondition.Node>{ leaf('Amount', 'LT', 200), leaf('NextStep', 'EQ', null) }
                        )
                    }
                ),
                new List<String>{ 'Acme Deal', 'Delta Big' }
            ),
            // Absolute dates
            new ConditionCase(
                'date range',
                BoardCondition.allOf(
                    new List<BoardCondition.Node>{
                        leaf('CloseDate', 'GTE', today.addDays(-10)),
                        leaf('CloseDate', 'LTE', today)
                    }
                ),
                new List<String>{ 'Acme Deal', 'Beta Deal' }
            ),
            new ConditionCase(
                'date EQ',
                leaf('CloseDate', 'EQ', today.addDays(-100)),
                new List<String>{ 'gamma deal' }
            ),
            new ConditionCase(
                'datetime GTE start of today',
                leaf('CreatedDate', 'GTE', startOfToday),
                new List<String>{ 'Acme Deal', 'Beta Deal', 'gamma deal', 'Delta Big' }
            ),
            // Relative dates
            new ConditionCase(
                'relative TODAY on a date',
                leaf('CloseDate', 'RELATIVE_DATE', 'TODAY'),
                new List<String>{ 'Acme Deal' }
            ),
            new ConditionCase(
                'relative LAST_N_DAYS',
                leaf('CloseDate', 'RELATIVE_DATE', 'LAST_N_DAYS:30'),
                new List<String>{ 'Acme Deal', 'Beta Deal' }
            ),
            new ConditionCase(
                'relative NEXT_N_DAYS',
                leaf('CloseDate', 'RELATIVE_DATE', 'NEXT_N_DAYS:60'),
                new List<String>{ 'Delta Big' }
            ),
            new ConditionCase(
                'relative N_DAYS_AGO',
                leaf('CloseDate', 'RELATIVE_DATE', 'N_DAYS_AGO:10'),
                new List<String>{ 'Beta Deal' }
            ),
            new ConditionCase(
                'relative TODAY on a datetime',
                leaf('CreatedDate', 'RELATIVE_DATE', 'TODAY'),
                new List<String>{ 'Acme Deal', 'Beta Deal', 'gamma deal', 'Delta Big' }
            ),
            new ConditionCase(
                'relative YESTERDAY on a datetime',
                leaf('CreatedDate', 'RELATIVE_DATE', 'YESTERDAY'),
                new List<String>()
            )
        };
    }

    @IsTest
    static void compiledSoqlAndInMemoryEvaluationAgree() {
        List<Opportunity> rows = Database.query('SELECT ' + FIELDS + ' FROM Opportunity');
        Test.startTest();
        for (ConditionCase conditionCase : cases()) {
            MapBinder binder = new MapBinder();
            String whereClause = conditionCase.condition.toSoql(binder);
            Set<String> fromSoql = new Set<String>();
            for (
                Opportunity row : (List<Opportunity>) Database.queryWithBinds(
                    'SELECT ' + FIELDS + ' FROM Opportunity WHERE ' + whereClause,
                    binder.binds,
                    AccessLevel.SYSTEM_MODE
                )
            ) {
                fromSoql.add(row.Name);
            }
            Set<String> inMemory = new Set<String>();
            for (Opportunity row : rows) {
                if (conditionCase.condition.evaluate(row.getPopulatedFieldsAsMap())) {
                    inMemory.add(row.Name);
                }
            }
            Assert.areEqual(conditionCase.expected, fromSoql, conditionCase.name + ' (SOQL: ' + whereClause + ')');
            Assert.areEqual(conditionCase.expected, inMemory, conditionCase.name + ' (in memory)');
        }
        Test.stopTest();
    }

    @IsTest
    static void escapedLikePatternsAreBoundAsLikePatterns() {
        BoardCondition.Predicate condition = (BoardCondition.Predicate) leaf('Name', 'LIKE', '50\\%%');
        condition.escapedPattern = true;
        MapBinder binder = new MapBinder();

        String whereClause = condition.toSoql(binder);

        Assert.areEqual('Name LIKE :b0', whereClause);
        Assert.isTrue(binder.likePatterns.contains('b0'));
        Assert.isTrue(condition.evaluate(new Map<String, Object>{ 'Name' => '50% off' }));
        Assert.isFalse(condition.evaluate(new Map<String, Object>{ 'Name' => '500 off' }));
    }

    @IsTest
    static void multiselectIncludesEveryValueOfAToken() {
        BoardCondition.Node includes = leafList('Tags__c', 'INCLUDES', new List<String>{ 'red;BLUE', 'green' });
        BoardCondition.Node excludes = leafList('Tags__c', 'EXCLUDES', new List<String>{ 'green' });
        MapBinder binder = new MapBinder();

        Assert.areEqual('Tags__c INCLUDES (:b0, :b1)', includes.toSoql(binder));
        Assert.isTrue(includes.evaluate(new Map<String, Object>{ 'Tags__c' => 'Blue;Red;Yellow' }));
        Assert.isFalse(includes.evaluate(new Map<String, Object>{ 'Tags__c' => 'red' }));
        Assert.isFalse(includes.evaluate(new Map<String, Object>{ 'Tags__c' => null }));
        Assert.isTrue(excludes.evaluate(new Map<String, Object>{ 'Tags__c' => 'red' }));
        Assert.isTrue(excludes.evaluate(new Map<String, Object>{ 'Tags__c' => null }));
    }

    @IsTest
    static void relativeDateRangesFollowCalendarAndFiscalPeriods() {
        Date today = Date.newInstance(2026, 11, 12);

        assertRange('LAST_N_DAYS:3', today, Date.newInstance(2026, 11, 9), today);
        assertRange('NEXT_90_DAYS', today, Date.newInstance(2026, 11, 13), Date.newInstance(2027, 2, 10));
        assertRange('THIS_MONTH', today, Date.newInstance(2026, 11, 1), Date.newInstance(2026, 11, 30));
        assertRange('LAST_QUARTER', today, Date.newInstance(2026, 7, 1), Date.newInstance(2026, 9, 30));
        assertRange('NEXT_YEAR', today, Date.newInstance(2027, 1, 1), Date.newInstance(2027, 12, 31));
        assertRange('LAST_N_MONTHS:2', today, Date.newInstance(2026, 9, 1), Date.newInstance(2026, 10, 31));
        assertRange('NEXT_N_QUARTERS:2', today, Date.newInstance(2027, 1, 1), Date.newInstance(2027, 6, 30));
        assertRange('N_YEARS_AGO:2', today, Date.newInstance(2024, 1, 1), Date.newInstance(2024, 12, 31));
        Date weekStart = today.toStartOfWeek();
        assertRange('LAST_WEEK', today, weekStart.addDays(-7), weekStart.addDays(-1));
    }

    @IsTest
    static void rejectsUnknownRelativeDateLiterals() {
        try {
            leaf('CloseDate', 'RELATIVE_DATE', 'TODAY OR Name != null').toSoql(new MapBinder());
            Assert.fail('Expected an invalid relative date literal to be rejected.');
        } catch (BoardErrors.BoardException expected) {
            Assert.areEqual(BoardErrors.CONFIG_ERROR, expected.category);
            Assert.isTrue(expected.getMessage().contains('relative date'), expected.getMessage());
        }
    }

    private static void assertRange(String literal, Date today, Date expectedStart, Date expectedEnd) {
        List<Date> range = BoardCondition.relativeRange(literal, today);
        Assert.areEqual(expectedStart, range[0], literal + ' start');
        Assert.areEqual(expectedEnd, range[1], literal + ' end');
    }
}