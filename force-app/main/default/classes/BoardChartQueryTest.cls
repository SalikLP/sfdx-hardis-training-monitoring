@IsTest
private class BoardChartQueryTest {
    private static final String RESTRICTED_ALIAS = 'brdchrt';
    private static final String RESTRICTED_LAST_NAME = 'Boardchart Restricted';

    /**
     * Opportunities: Board Alpha 100 & 200 (first stage, one with Lead source Web), Board Beta 350 & null (second
     * stage). Restricted user: `Minimum Access - Salesforce` with Read on Account only (no Opportunity access).
     */
    @TestSetup
    static void setup() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User restrictedUser = new User(
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1]
                .Id,
                Alias = RESTRICTED_ALIAS,
                LastName = RESTRICTED_LAST_NAME,
                Email = RESTRICTED_ALIAS + '@example.com',
                Username = RESTRICTED_ALIAS +
                    String.valueOf(Crypto.getRandomInteger()).replace('-', '') +
                    '@board-chart.test',
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            );
            insert restrictedUser;
            PermissionSet permissionSet = new PermissionSet(Name = 'BoardChartTestAccess', Label = 'Board Chart Test');
            insert permissionSet;
            insert new ObjectPermissions(ParentId = permissionSet.Id, SobjectType = 'Account', PermissionsRead = true);
            insert new PermissionSetAssignment(AssigneeId = restrictedUser.Id, PermissionSetId = permissionSet.Id);
        }

        Account alpha = new Account(Name = 'Board Alpha');
        Account beta = new Account(Name = 'Board Beta');
        insert new List<Account>{ alpha, beta };
        List<Schema.PicklistEntry> stages = Opportunity.StageName.getDescribe().getPicklistValues();
        String firstStage = stages[0].getValue();
        String secondStage = stages[1].getValue();
        Opportunity web = opportunity('Board Opp 1', alpha.Id, 100, firstStage);
        web.LeadSource = 'Web';
        insert new List<Opportunity>{
            web,
            opportunity('Board Opp 2', alpha.Id, 200, firstStage),
            opportunity('Board Opp 3', beta.Id, 350, secondStage),
            opportunity('Board Opp 4', beta.Id, null, secondStage)
        };
    }

    @IsTest
    static void measuresListReturnsOneValuePerMeasurePerCategory() {
        Map<String, Object> request = chartRequest(
            'AccountId',
            new List<Object>{ measure('SUM', 'Amount'), countMeasure() }
        );

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual('SINGLE', result.mode);
        Assert.isTrue(result.isComplete);
        Assert.areEqual(new List<String>{ 'SUM', 'COUNT' }, result.aggregateFunctions);
        Assert.areEqual(new List<String>{ 'CURRENCY', null }, result.valueTypes);
        Assert.areEqual(2, result.categories.size());
        Assert.areEqual('Board Beta', result.categories[0].label, 'Largest first Measure first: 350 > 300');
        Assert.areEqual('Board Alpha', result.categories[1].label);
        Assert.areEqual(1, result.series.size(), 'No series field');
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(350, values.get('Board Beta|0'));
        Assert.areEqual(2, values.get('Board Beta|1'));
        Assert.areEqual(300, values.get('Board Alpha|0'));
        Assert.areEqual(2, values.get('Board Alpha|1'));
        Assert.areEqual('measure:1', result.points[1].colourKey);
        Assert.isFalse(result.truncatedCategories);
        Assert.isNull(result.partialState, 'Complete results carry no cursor state');
    }

    @IsTest
    static void oneMeasureSplitBySeriesFieldButNeverSeveralMeasuresWithOne() {
        Map<String, Object> request = chartRequest('AccountId', new List<Object>{ countMeasure() });
        request.put('stackByField', 'StageName');
        BoardChartQuery.ChartResult result = query(request);
        Assert.areEqual(2, result.series.size());
        Assert.isNotNull(result.stackBy);
        String firstStage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        Boolean found = false;
        for (BoardChartEngine.ChartKey series : result.series) {
            found = found || series.colourKey == firstStage;
        }
        Assert.isTrue(found, 'Series colour keys are the stored picklist values');

        request.put('measures', new List<Object>{ countMeasure(), measure('SUM', 'Amount') });
        Assert.areEqual('stackByField', expectError(request, 'CONFIG_ERROR').get('fieldPath'));

        List<Object> seven = new List<Object>();
        for (Integer i = 0; i < 7; i++) {
            seven.add(countMeasure());
        }
        Assert.areEqual(
            'measures',
            expectError(chartRequest('AccountId', seven), 'CONFIG_ERROR').get('fieldPath'),
            'Max 6 Measures'
        );
        expectError(chartRequest('AccountId', new List<Object>()), 'CONFIG_ERROR');
        expectError(chartRequest('AccountId', new List<Object>{ measure('SUM', 'Name') }), 'CONFIG_ERROR');
        expectError(chartRequest('AccountId', new List<Object>{ measure('MEDIAN', 'Amount') }), 'CONFIG_ERROR');
    }

    @IsTest
    static void otherAveragesAndFormulasOverTheRolledUpRows() {
        Map<String, Object> request = chartRequest(
            'Name',
            new List<Object>{
                measure('SUM', 'Amount'),
                measure('AVG', 'Amount'),
                countMeasure(),
                new Map<String, Object>{ 'aggregateFunction' => 'FORMULA', 'formula' => 'A / C' }
            }
        );
        request.put('maxCategories', 3);
        request.put('overflowMode', 'OTHER');

        BoardChartQuery.ChartResult result = query(request);

        Assert.isTrue(result.categories[2].isOther, 'AVG and a Formula measure no longer block "Other"');
        Assert.areEqual(2, result.hiddenCategories);
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(100, values.get('Other|0'), 'Opp 1 (100) + Opp 4 (no amount)');
        Assert.areEqual(100, values.get('Other|1'), 'AVG over the rolled-up rows with an amount');
        Assert.areEqual(2, values.get('Other|2'));
        Assert.areEqual(50, values.get('Other|3'), 'Formula on the merged inputs: 100 / 2');
        Assert.areEqual(350, values.get('Board Opp 3|1'), 'Kept categories keep their own values');
    }

    @IsTest
    static void topNRollsTheRestIntoOtherAndFlagsBlankAndTruncatedCategories() {
        Map<String, Object> request = chartRequest('Name', new List<Object>{ measure('SUM', 'Amount') });
        request.put('maxCategories', 3);
        request.put('overflowMode', 'OTHER');

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual(3, result.categories.size());
        Assert.areEqual('Board Opp 3', result.categories[0].label);
        Assert.areEqual('Board Opp 2', result.categories[1].label);
        Assert.isTrue(result.categories[2].isOther);
        Assert.areEqual('Other', result.categories[2].label);
        Assert.isTrue(result.truncatedCategories);
        Assert.areEqual(2, result.hiddenCategories);
        Assert.areEqual(100, valuesByLabel(result).get('Other|0'), 'Opp 1 (100) + Opp 4 (no amount)');

        Map<String, Object> blanks = chartRequest('LeadSource', new List<Object>{ countMeasure() });
        BoardChartQuery.ChartResult withBlank = query(blanks);
        Assert.areEqual(2, withBlank.categories.size());
        Assert.isTrue(withBlank.categories[0].isBlank, '3 blank rows outnumber 1 Web row');
        Assert.areEqual('(Blank)', withBlank.categories[0].label);
        Assert.areEqual(BoardChartEngine.BLANK_KEY, withBlank.categories[0].colourKey);
        blanks.put('includeNullBucket', false);
        Assert.areEqual(1, query(blanks).categories.size());
    }

    @IsTest
    static void cursorTierReturnsCompleteResultsAcrossChunks() {
        List<Object> measures = new List<Object>{ measure('SUM', 'Amount'), measure('AVG', 'Amount'), countMeasure() };
        Map<String, Decimal> expected = valuesByLabel(query(chartRequest('AccountId', measures)));

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 1;
        Map<String, Object> request = chartRequest('AccountId', measures);
        BoardChartQuery.ChartResult result = query(request);
        Assert.areEqual('CURSOR', result.mode);
        Assert.isFalse(result.isComplete);
        Assert.areEqual(4, result.totalRows);
        Assert.areEqual(1, result.processedRows);
        Assert.isNotNull(result.partialState);
        Integer calls = 1;
        while (!result.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.cursor);
            next.put('offset', result.nextOffset);
            next.put('partialState', result.partialState);
            result = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
            calls++;
        }
        Assert.areEqual(4, calls);
        Assert.areEqual(4, result.processedRows);
        Map<String, Decimal> merged = valuesByLabel(result);
        Assert.areEqual(expected.keySet(), merged.keySet());
        for (String key : expected.keySet()) {
            Assert.areEqual(expected.get(key).setScale(2), merged.get(key).setScale(2), 'Cursor matches SOQL: ' + key);
        }
        Assert.isNull(result.partialState);
    }

    @IsTest
    static void groupCapFallsBackToTheCursorTierOrReportsMissingGroups() {
        BoardQueryService.CHART_GROUP_LIMIT = 1;
        BoardChartQuery.ChartResult counts = query(chartRequest('AccountId', new List<Object>{ countMeasure() }));
        Assert.areEqual('CURSOR', counts.mode, 'Capped GROUP BY re-runs through cursor chunks');
        Assert.isTrue(counts.isComplete);
        Assert.areEqual(2, counts.categories.size(), 'Every group, not just the largest');
        Assert.isFalse(counts.hasMoreGroups);

        BoardChartQuery.ChartResult distinct = query(
            chartRequest('AccountId', new List<Object>{ measure('COUNT_DISTINCT', 'Name') })
        );
        Assert.areEqual('SINGLE', distinct.mode, 'COUNT_DISTINCT cannot merge cursor chunks');
        Assert.isTrue(distinct.hasMoreGroups);

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_MAX_ROWS = 3;
        expectError(chartRequest('AccountId', new List<Object>{ measure('SUM', 'Amount') }), 'LIMIT_EXCEEDED');
    }

    @IsTest
    static void shareOfTotalIsAgainstTheFullTotalWhenCategoriesAreCapped() {
        // Opportunities with no amount, 100, 200 and 350 (650), smallest first: max categories hides Opp 3 (350).
        Map<String, Object> request = chartRequest(
            'Name',
            new List<Object>{ shareMeasure('SUM', 'Amount', 'percentOfTotal'), countMeasure() }
        );
        request.put('maxCategories', 3);
        request.put('sortBy', 'VALUE_ASC');
        BoardChartQuery.ChartResult truncated = query(request);
        Assert.isTrue(truncated.truncatedCategories);
        Map<String, Decimal> values = valuesByLabel(truncated);
        Assert.isFalse(values.containsKey('Board Opp 3|0'), 'Opp 3 is hidden');
        Assert.areEqual(0.3077, values.get('Board Opp 2|0').setScale(4), '200 of 650, the hidden Opp 3 included');
        Assert.areEqual(0.1538, values.get('Board Opp 1|0').setScale(4));
        Assert.areEqual(1, values.get('Board Opp 2|1'), 'A plain Measure keeps its value');

        // A capped GROUP BY that can't fall back to cursor chunks drops groups: one ungrouped query gives the total.
        BoardQueryService.CHART_GROUP_LIMIT = 1;
        BoardQueryService.CURSOR_MAX_ROWS = 3;
        BoardChartQuery.ChartResult capped = query(
            chartRequest('AccountId', new List<Object>{ shareMeasure('SUM', 'Amount', 'percentOfTotal') })
        );
        Assert.isTrue(capped.hasMoreGroups);
        Assert.areEqual(1, capped.categories.size(), 'Only the largest group came back');
        Assert.areEqual(0.5385, valuesByLabel(capped).get('Board Beta|0').setScale(4), '350 of 650, not of 350');
    }

    @IsTest
    static void percentOfCategoryNeedsASeriesFieldOrSeveralMeasures() {
        Map<String, Object> request = chartRequest(
            'AccountId',
            new List<Object>{ shareMeasure('COUNT', null, 'percentOfCategory') }
        );
        Map<String, Object> error = expectError(request, 'CONFIG_ERROR');
        Assert.areEqual('measures', error.get('fieldPath'));

        // Product penetration within a family: each stage's share of its Account's Opportunities.
        request.put('stackByField', 'StageName');
        BoardChartQuery.ChartResult bySeries = query(request);
        Decimal alpha = 0;
        for (BoardChartEngine.ChartPoint point : bySeries.points) {
            if (point.categoryKey == bySeries.categories[0].key) {
                alpha += point.value;
            }
        }
        Assert.areEqual(1, alpha.setScale(4), 'The series of one category add up to 100%');

        BoardChartQuery.ChartResult byMeasures = query(
            chartRequest(
                'AccountId',
                new List<Object>{
                    shareMeasure('SUM', 'Amount', 'percentOfCategory'),
                    shareMeasure('COUNT', null, 'percentOfCategory')
                }
            )
        );
        Map<String, Decimal> values = valuesByLabel(byMeasures);
        Assert.areEqual(0.9934, values.get('Board Alpha|0').setScale(4), '300 of 300 + 2 records');
        Assert.areEqual(0.0066, values.get('Board Alpha|1').setScale(4));
    }

    @IsTest
    static void shareOfTotalRejectsUnknownModesAndMeasuresThatDoNotAddUp() {
        expectError(
            chartRequest('AccountId', new List<Object>{ shareMeasure('SUM', 'Amount', 'percentOfEverything') }),
            'CONFIG_ERROR'
        );
        Map<String, Object> error = expectError(
            chartRequest('AccountId', new List<Object>{ shareMeasure('AVG', 'Amount', 'percentOfTotal') }),
            'CONFIG_ERROR'
        );
        Assert.areEqual('measures', error.get('fieldPath'));
    }

    @IsTest
    static void restrictedUserFailsClosedAndCursorErrorsAreRetryable() {
        Map<String, Object> accessError;
        System.runAs(restrictedUser()) {
            accessError = expectError(chartRequest('AccountId', new List<Object>{ countMeasure() }), 'ACCESS_ERROR');
        }
        Assert.isNotNull(accessError);

        Map<String, Object> request = chartRequest('AccountId', new List<Object>{ countMeasure() });
        try {
            BoardChartQuery.fetchChartChunk(JSON.serialize(request));
            Assert.fail('Expected an error without a cursor');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual(true, payload.get('retryable'));
        }
        try {
            BoardChartQuery.queryChart('not json');
            Assert.fail('Expected an error');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'));
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    private static Map<String, Object> chartRequest(String groupByField, List<Object> measures) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => groupByField,
            'measures' => measures
        };
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        return new Map<String, Object>{ 'aggregateFunction' => aggregateFunction, 'valueFieldApiName' => valueField };
    }

    private static Map<String, Object> shareMeasure(String aggregateFunction, String valueField, String showAs) {
        Map<String, Object> share = measure(aggregateFunction, valueField);
        share.put('showAs', showAs);
        return share;
    }

    private static Map<String, Object> countMeasure() {
        return new Map<String, Object>{ 'aggregateFunction' => 'COUNT' };
    }

    private static BoardChartQuery.ChartResult query(Map<String, Object> request) {
        return BoardChartQuery.queryChart(JSON.serialize(request));
    }

    /** Point values keyed `categoryLabel|measureIndex` (single-series charts). */
    private static Map<String, Decimal> valuesByLabel(BoardChartQuery.ChartResult result) {
        Map<String, String> labels = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            labels.put(category.key, category.label);
        }
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(labels.get(point.categoryKey) + '|' + point.measureIndex, point.value);
        }
        return values;
    }

    private static Map<String, Object> expectError(Map<String, Object> request, String category) {
        try {
            query(request);
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual(category, payload.get('category'), String.valueOf(payload));
            return payload;
        }
        Assert.fail('Expected ' + category + ' for ' + JSON.serialize(request));
        return null;
    }

    private static Opportunity opportunity(String name, Id accountId, Decimal amount, String stage) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            Amount = amount,
            CloseDate = Date.today(),
            StageName = stage
        );
    }

    private static User restrictedUser() {
        return [SELECT Id FROM User WHERE Alias = :RESTRICTED_ALIAS AND LastName = :RESTRICTED_LAST_NAME LIMIT 1];
    }
}