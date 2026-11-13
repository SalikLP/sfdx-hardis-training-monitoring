/**
 * ForecastingQuota as a Cross-object measure source: a Measure condition on `ForecastingType.DeveloperName` resolves to
 * `ForecastingTypeId` before the query runs. The resolution is driven with a fake ForecastingType lookup; the org's own
 * lookup and the Chart / Metric entry points run against real ForecastingQuota rows only where Collaborative Forecasts
 * is enabled and quotas are insertable (otherwise those assertions are skipped). Forecasting objects are only ever
 * referenced dynamically, so this class compiles in every org.
 */
@IsTest
private class BoardForecastingQuotaTest {
    private static final String REVENUE = 'OpportunityRevenue';
    private static final String LINE_ITEM_REVENUE = 'OpportunityLineItemRevenue';
    private static final String REVENUE_ID = '0Db000000000001AAA';
    private static final String LINE_ITEM_REVENUE_ID = '0Db000000000002AAA';

    // ---------------------------------------------------------------------------------------------------------
    // Engine unit: DeveloperName -> Id resolution with a fake lookup
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void developerNameConditionResolvesToForecastingTypeId() {
        FakeLookup lookup = new FakeLookup();
        Map<String, Object> condition = andOf(new List<Object>{ leaf('ForecastingType.DeveloperName', 'EQ', REVENUE) });

        Map<String, Object> resolved = (Map<String, Object>) BoardForecastingQuota.resolveCondition(condition, lookup);

        Map<String, Object> only = (Map<String, Object>) ((List<Object>) resolved.get('conditions'))[0];
        Assert.areEqual('ForecastingTypeId', only.get('fieldPath'));
        Assert.areEqual('EQ', only.get('operator'));
        Assert.areEqual(REVENUE_ID, only.get('value'));
        Map<String, Object> original = (Map<String, Object>) ((List<Object>) condition.get('conditions'))[0];
        Assert.areEqual('ForecastingType.DeveloperName', original.get('fieldPath'), 'The config is not changed');
        Assert.areEqual(REVENUE, original.get('value'));
    }

    @IsTest
    static void listsNestedGroupsAndOtherConditionsResolveWithOneLookup() {
        FakeLookup lookup = new FakeLookup();
        Map<String, Object> condition = andOf(
            new List<Object>{
                leaf('ProductFamily', 'EQ', 'Hardware'),
                new Map<String, Object>{
                    'logic' => 'OR',
                    'conditions' => new List<Object>{
                        leaf(
                            'forecastingtype.developername',
                            'IN',
                            new List<Object>{ 'opportunityrevenue', LINE_ITEM_REVENUE }
                        ),
                        leaf('ForecastingType.DeveloperName', 'NEQ', LINE_ITEM_REVENUE)
                    }
                }
            }
        );

        Map<String, Object> resolved = (Map<String, Object>) BoardForecastingQuota.resolveCondition(condition, lookup);

        Assert.areEqual(1, lookup.calls, 'Every DeveloperName of the condition in one lookup');
        List<Object> children = (List<Object>) resolved.get('conditions');
        Assert.areEqual(leaf('ProductFamily', 'EQ', 'Hardware'), children[0], 'Other conditions are kept as-is');
        List<Object> orChildren = (List<Object>) ((Map<String, Object>) children[1]).get('conditions');
        Map<String, Object> inList = (Map<String, Object>) orChildren[0];
        Assert.areEqual('ForecastingTypeId', inList.get('fieldPath'));
        Assert.areEqual('IN', inList.get('operator'));
        Assert.areEqual(
            new List<Object>{ REVENUE_ID, LINE_ITEM_REVENUE_ID },
            inList.get('value'),
            'DeveloperNames match case-insensitively'
        );
        Map<String, Object> notEqual = (Map<String, Object>) orChildren[1];
        Assert.areEqual('NEQ', notEqual.get('operator'));
        Assert.areEqual(LINE_ITEM_REVENUE_ID, notEqual.get('value'));
    }

    @IsTest
    static void unknownDeveloperNameIsAReadableConfigError() {
        Map<String, Object> condition = andOf(
            new List<Object>{ leaf('ForecastingType.DeveloperName', 'EQ', 'Board_No_Such_Type') }
        );
        try {
            BoardForecastingQuota.resolveCondition(condition, new FakeLookup());
            Assert.fail('Expected a config error for an unknown ForecastingType');
        } catch (BoardErrors.BoardException failure) {
            Assert.areEqual(BoardErrors.CONFIG_ERROR, failure.category);
            Assert.isTrue(failure.getMessage().contains('Board_No_Such_Type'), failure.getMessage());
            Assert.isTrue(failure.getMessage().contains('ForecastingType'), failure.getMessage());
        }
    }

    @IsTest
    static void unsupportedOperatorOrMissingValueIsAConfigError() {
        for (
            Map<String, Object> bad : new List<Map<String, Object>>{
                leaf('ForecastingType.DeveloperName', 'LIKE', 'Opportunity'),
                leaf('ForecastingType.DeveloperName', 'IN', new List<Object>()),
                leaf('ForecastingType.DeveloperName', 'EQ', null)
            }
        ) {
            try {
                BoardForecastingQuota.resolveCondition(andOf(new List<Object>{ bad }), new FakeLookup());
                Assert.fail('Expected a config error for ' + JSON.serialize(bad));
            } catch (BoardErrors.BoardException failure) {
                Assert.areEqual(BoardErrors.CONFIG_ERROR, failure.category);
                Assert.isTrue(failure.getMessage().contains('ForecastingType.DeveloperName'), failure.getMessage());
            }
        }
    }

    @IsTest
    static void conditionWithoutDeveloperNameNeedsNoLookup() {
        FakeLookup lookup = new FakeLookup();
        Map<String, Object> condition = andOf(new List<Object>{ leaf('ProductFamily', 'EQ', 'Hardware') });

        Object resolved = BoardForecastingQuota.resolveCondition(condition, lookup);

        Assert.areEqual(condition, resolved);
        Assert.areEqual(0, lookup.calls);
        Assert.isNull(BoardForecastingQuota.resolveCondition(null, lookup));
    }

    @IsTest
    static void onlyForecastingQuotaSourcesAreResolved() {
        FakeLookup lookup = new FakeLookup();
        BoardForecastingQuota.activeLookup = lookup;
        Map<String, Object> condition = andOf(new List<Object>{ leaf('ForecastingType.DeveloperName', 'EQ', REVENUE) });
        List<Object> contractMeasures = new List<Object>{ new Map<String, Object>{ 'condition' => condition } };
        List<Object> quotaMeasures = new List<Object>{
            new Map<String, Object>{ 'aggregateFunction' => 'COUNT' },
            new Map<String, Object>{ 'condition' => condition }
        };

        BoardForecastingQuota.resolveConditions('Contract', contractMeasures);
        BoardForecastingQuota.resolveConditions('forecastingquota', quotaMeasures);

        Assert.areEqual(condition, ((Map<String, Object>) contractMeasures[0]).get('condition'));
        Assert.isFalse(((Map<String, Object>) quotaMeasures[0]).containsKey('condition'));
        Map<String, Object> resolved = (Map<String, Object>) ((Map<String, Object>) quotaMeasures[1]).get('condition');
        Assert.areEqual(
            'ForecastingTypeId',
            ((Map<String, Object>) ((List<Object>) resolved.get('conditions'))[0]).get('fieldPath')
        );
        Assert.areEqual(1, lookup.calls);
        Assert.isTrue(BoardForecastingQuota.isForecastingQuota(' ForecastingQuota '));
        Assert.isFalse(BoardForecastingQuota.isForecastingQuota(null));
    }

    // ---------------------------------------------------------------------------------------------------------
    // The org's ForecastingType lookup
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void orgLookupRejectsAnUnknownDeveloperName() {
        // Forecasting disabled, or enabled without that type: either way a readable config error.
        try {
            BoardForecastingQuota.resolveCondition(
                andOf(new List<Object>{ leaf('ForecastingType.DeveloperName', 'EQ', 'Board_No_Such_Type_X') }),
                new BoardForecastingQuota.OrgTypeLookup()
            );
            Assert.fail('Expected a config error');
        } catch (BoardErrors.BoardException failure) {
            Assert.areEqual(BoardErrors.CONFIG_ERROR, failure.category, failure.getMessage());
        }
    }

    @IsTest
    static void orgLookupResolvesAnExistingForecastingType() {
        SObject forecastingType = anyForecastingType(false);
        if (forecastingType == null) {
            return; // Forecasting isn't enabled here (or has no types): covered by the fake lookup tests.
        }
        String developerName = (String) forecastingType.get('DeveloperName');

        Map<String, Object> resolved = (Map<String, Object>) BoardForecastingQuota.resolveCondition(
            andOf(new List<Object>{ leaf('ForecastingType.DeveloperName', 'EQ', developerName.toUpperCase()) }),
            new BoardForecastingQuota.OrgTypeLookup()
        );

        Map<String, Object> only = (Map<String, Object>) ((List<Object>) resolved.get('conditions'))[0];
        Assert.areEqual(String.valueOf(forecastingType.Id), only.get('value'));
    }

    // ---------------------------------------------------------------------------------------------------------
    // Entry points with real quotas (only where Forecasting is enabled and quotas are insertable)
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void chartJoinsQuotaByMonthAndQuarterFilteredOnDeveloperName() {
        QuotaFixture fixture = createQuotaFixture();
        if (fixture == null) {
            return;
        }
        insert new Opportunity(
            Name = 'Quota Opp',
            Amount = 100,
            CloseDate = fixture.startDate.addDays(3),
            StageName = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue()
        );
        for (String granularity : new List<String>{ 'CALENDAR_MONTH', 'CALENDAR_QUARTER' }) {
            BoardChartQuery.ChartResult result = BoardChartQuery.queryChart(
                JSON.serialize(
                    new Map<String, Object>{
                        'objectApiName' => 'Opportunity',
                        'groupByField' => 'CloseDate',
                        'dateGranularity' => granularity,
                        'measures' => new List<Object>{
                            new Map<String, Object>{ 'aggregateFunction' => 'SUM', 'valueFieldApiName' => 'Amount' },
                            fixture.quotaMeasure('StartDate', fixture.developerName)
                        }
                    }
                )
            );

            Assert.areEqual(1, result.categories.size(), granularity + ': pipeline and quota share one period');
            Map<Integer, Decimal> values = new Map<Integer, Decimal>();
            for (BoardChartEngine.ChartPoint point : result.points) {
                values.put(point.measureIndex, point.value);
            }
            Assert.areEqual(100, values.get(0));
            Assert.areEqual(fixture.amount, values.get(1), granularity + ': only the named ForecastingType');
            Assert.isFalse(result.crossObjectNotices[0].isBlank);
        }
    }

    @IsTest
    static void metricSumsQuotaOfTheNamedForecastingType() {
        QuotaFixture fixture = createQuotaFixture();
        if (fixture == null) {
            return;
        }
        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(
            JSON.serialize(
                new Map<String, Object>{
                    'objectApiName' => 'Opportunity',
                    'measures' => new List<Object>{ fixture.quotaMeasure(null, fixture.developerName) }
                }
            )
        );

        Assert.areEqual(fixture.amount, Decimal.valueOf(String.valueOf(result.value)));
    }

    @IsTest
    static void chartWithAnUnknownDeveloperNameIsAReadableConfigError() {
        if (!BoardForecastingQuota.isAvailable()) {
            return;
        }
        try {
            BoardChartQuery.queryChart(
                JSON.serialize(
                    new Map<String, Object>{
                        'objectApiName' => 'Opportunity',
                        'groupByField' => 'CloseDate',
                        'dateGranularity' => 'CALENDAR_MONTH',
                        'measures' => new List<Object>{
                            new Map<String, Object>{ 'aggregateFunction' => 'COUNT' },
                            new QuotaFixture().quotaMeasure('StartDate', 'Board_No_Such_Type_Y')
                        }
                    }
                )
            );
            Assert.fail('Expected a config error');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), String.valueOf(payload));
            Assert.isTrue(String.valueOf(payload.get('message')).contains('Board_No_Such_Type_Y'));
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    private static Map<String, Object> andOf(List<Object> conditions) {
        return new Map<String, Object>{ 'logic' => 'AND', 'conditions' => conditions };
    }

    private static Map<String, Object> leaf(String fieldPath, String operator, Object value) {
        return new Map<String, Object>{
            'id' => 'mc',
            'fieldPath' => fieldPath,
            'operator' => operator,
            'value' => value
        };
    }

    /** An (active, when `activeOnly`) ForecastingType the running user can read; null without Forecasting. */
    private static SObject anyForecastingType(Boolean activeOnly) {
        if (!BoardForecastingQuota.isAvailable()) {
            return null;
        }
        List<SObject> types = Database.query(
            'SELECT Id, DeveloperName FROM ForecastingType' + (activeOnly ? ' WHERE IsActive = true' : '') + ' LIMIT 1'
        );
        return types.isEmpty() ? null : types[0];
    }

    /** Fake ForecastingType lookup: two known types, counts its calls. */
    private class FakeLookup implements BoardForecastingQuota.TypeLookup {
        Integer calls = 0;

        public Map<String, String> idsByDeveloperName(Set<String> developerNames) {
            calls++;
            Map<String, String> known = new Map<String, String>{
                REVENUE.toLowerCase() => REVENUE_ID,
                LINE_ITEM_REVENUE.toLowerCase() => LINE_ITEM_REVENUE_ID
            };
            Map<String, String> found = new Map<String, String>();
            for (String developerName : developerNames) {
                if (known.containsKey(developerName.toLowerCase())) {
                    found.put(developerName.toLowerCase(), known.get(developerName.toLowerCase()));
                }
            }
            return found;
        }
    }

    /** A quota of the running user: its ForecastingType, period start and amount. */
    private class QuotaFixture {
        String developerName;
        Date startDate = Date.today().toStartOfMonth();
        Decimal amount = 1234;

        Map<String, Object> quotaMeasure(String categoryMapping, String typeDeveloperName) {
            Map<String, Object> measure = new Map<String, Object>{
                'aggregateFunction' => 'SUM',
                'valueFieldApiName' => 'QuotaAmount',
                'sourceObject' => BoardForecastingQuota.OBJECT_NAME
            };
            if (categoryMapping != null) {
                measure.put('categoryMapping', categoryMapping);
            }
            if (typeDeveloperName != null) {
                measure.put(
                    'condition',
                    andOf(new List<Object>{ leaf('ForecastingType.DeveloperName', 'EQ', typeDeveloperName) })
                );
            }
            return measure;
        }
    }

    /** One quota of the running user in an active ForecastingType this month; null when the org can't insert it. */
    private static QuotaFixture createQuotaFixture() {
        SObject forecastingType = anyForecastingType(true);
        Schema.SObjectType quotaType = Schema.getGlobalDescribe().get(BoardForecastingQuota.OBJECT_NAME);
        if (forecastingType == null || quotaType == null || !quotaType.getDescribe().isCreateable()) {
            return null;
        }
        QuotaFixture fixture = new QuotaFixture();
        fixture.developerName = (String) forecastingType.get('DeveloperName');
        SObject quota = quotaType.newSObject();
        quota.put('QuotaOwnerId', UserInfo.getUserId());
        quota.put('ForecastingTypeId', forecastingType.Id);
        quota.put('StartDate', fixture.startDate);
        quota.put('QuotaAmount', fixture.amount);
        try {
            if (Schema.SObjectType.User.fields.getMap().containsKey('forecastenabled')) {
                User self = new User(Id = UserInfo.getUserId());
                self.put('ForecastEnabled', true);
                System.runAs(new User(Id = UserInfo.getUserId())) {
                    update self;
                }
            }
            insert quota;
        } catch (DmlException notInsertable) {
            // E.g. a product-family type needs a family, or the period isn't set up: nothing to assert here.
            return null;
        }
        return fixture;
    }
}