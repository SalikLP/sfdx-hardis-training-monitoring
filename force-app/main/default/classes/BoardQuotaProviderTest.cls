/**
 * Quota provider: a Data provider an Admin names on a ForecastingQuota Cross-object measure. Viewers with the custom
 * permission `Board_ViewAllQuotas` (permission set *Board Quota Viewer*) read in system mode, everyone else in
 * USER_MODE, with the Measure's request (bound filters, Team, Measure condition) passed on unchanged.
 *
 * The provider is driven with a recording quota query, so these tests pass in orgs without Forecasting; the engine's
 * query path with the system-mode executor is checked on Opportunity, and against ForecastingQuota itself only where
 * Forecasting is enabled (otherwise those assertions are skipped). Forecasting objects are only referenced
 * dynamically, so this class compiles in every org.
 */
@IsTest
private class BoardQuotaProviderTest {
    private static final String QUOTA_VIEWER = 'Board_Quota_Viewer';

    /** Records what the provider asked for and returns canned corporate-currency buckets. */
    private class RecordingQuery implements BoardQuotaProvider.QuotaQuery {
        List<Boolean> modes = new List<Boolean>();
        List<Map<String, Object>> queries = new List<Map<String, Object>>();
        List<BoardDataProviderResult.Bucket> buckets = new List<BoardDataProviderResult.Bucket>();

        public List<BoardDataProviderResult.Bucket> run(Map<String, Object> query, Boolean systemMode) {
            modes.add(systemMode);
            queries.add(query);
            return buckets;
        }
    }

    /** Records each statement and runs it in USER_MODE (an executor like the provider's system-mode one). */
    private class RecordingExecutor implements BoardQueryService.QueryExecutor {
        List<String> statements = new List<String>();

        public List<SObject> query(String soql, Map<String, Object> binds) {
            statements.add(soql);
            return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        }

        public Integer countQuery(String soql, Map<String, Object> binds) {
            statements.add(soql);
            return Database.countQueryWithBinds(soql, binds, AccessLevel.USER_MODE);
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Access mode: with and without the custom permission
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void viewerWithTheQuotaViewerPermissionSetReadsInSystemMode() {
        RecordingQuery recording = record();
        grantQuotaViewer();

        BoardDataProviderResult result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            result = new BoardQuotaProvider().provide(quotaRequest(sumOfQuotaAmount()));
        }

        Assert.areEqual(new List<Boolean>{ true }, recording.modes, 'Board_ViewAllQuotas reads in system mode');
        Assert.isTrue(result.rejectedMeasures.isEmpty());
    }

    @IsTest
    static void viewerWithoutThePermissionReadsInUserMode() {
        RecordingQuery recording = record();
        revokeQuotaViewer();

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Assert.isFalse(BoardQuotaProvider.canViewAllQuotas());
            new BoardQuotaProvider().provide(quotaRequest(sumOfQuotaAmount()));
        }

        Assert.areEqual(new List<Boolean>{ false }, recording.modes, 'Without the permission: exactly USER_MODE');
    }

    // ---------------------------------------------------------------------------------------------------------
    // The Measure's request reaches the query unchanged: bound filters (incl. Team), no role cap
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void boundFiltersIncludingTeamReachTheQueryUnchanged() {
        RecordingQuery recording = record();
        BoardDataProviderRequest request = quotaRequest(sumOfQuotaAmount());
        Map<String, Object> team = new Map<String, Object>{
            'filterId' => 'team',
            'fieldPath' => 'QuotaOwner.UserRoleId',
            'operator' => 'IN',
            'values' => new List<Object>{ 'role-a', 'role-b' }
        };
        request.query.put('filters', new List<Object>{ team });
        request.query.put('groupByField', 'ProductFamily');

        new BoardQuotaProvider().provide(request);

        Assert.areEqual(1, recording.queries.size(), 'One query for the Measure');
        Map<String, Object> sent = recording.queries[0];
        Assert.areEqual(new List<Object>{ team }, sent.get('filters'), 'The Team filter is kept, no role cap added');
        Assert.areEqual('ForecastingQuota', sent.get('objectApiName'));
        Assert.areEqual('ProductFamily', sent.get('groupByField'));
    }

    @IsTest
    static void returnsTheQueryBucketsInCorporateCurrencyUnconverted() {
        RecordingQuery recording = record();
        BoardDataProviderResult.Bucket hardware = new BoardDataProviderResult.Bucket(
            'Hardware',
            'Hardware',
            null,
            null
        );
        hardware.measures.add(new BoardDataProviderResult.Partial(1500, 3, 200, 800));
        recording.buckets.add(hardware);
        BoardDataProviderRequest request = quotaRequest(sumOfQuotaAmount());
        request.displayCurrency = 'EUR';

        BoardDataProviderResult result = new BoardQuotaProvider().provide(request);

        Assert.areEqual(1, result.buckets.size());
        Assert.areEqual(1500, result.buckets[0].measures[0].sum, 'Corporate amount; the engine converts it');
        Assert.areEqual(3, result.buckets[0].measures[0].count);
        Assert.isFalse(result.includeStandardResult, 'The provider replaces the source object query');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Only ForecastingQuota, SUM / COUNT of QuotaAmount
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void sumAndCountOfQuotaAmountAreAccepted() {
        RecordingQuery recording = record();
        BoardDataProviderRequest.Measure quotaCount = measure(1, 'COUNT', null);

        BoardDataProviderResult result = new BoardQuotaProvider()
            .provide(
                quotaRequest(new List<BoardDataProviderRequest.Measure>{ measure(0, 'sum', 'quotaamount'), quotaCount })
            );

        Assert.isTrue(result.rejectedMeasures.isEmpty(), String.valueOf(result.rejectedMeasures));
        Assert.areEqual(1, recording.modes.size());
    }

    @IsTest
    static void otherSourceObjectsAreRejectedWithoutQuerying() {
        RecordingQuery recording = record();
        BoardDataProviderRequest request = quotaRequest(sumOfQuotaAmount());
        request.objectApiName = 'Opportunity';

        BoardDataProviderResult result = new BoardQuotaProvider().provide(request);

        Assert.isTrue(result.rejectedMeasures.get(0).contains('only reads ForecastingQuota'));
        Assert.isTrue(recording.modes.isEmpty(), 'A rejected request runs no query');
    }

    @IsTest
    static void otherAggregatesAndValueFieldsAreRejected() {
        RecordingQuery recording = record();
        BoardDataProviderResult result = new BoardQuotaProvider()
            .provide(
                quotaRequest(
                    new List<BoardDataProviderRequest.Measure>{
                        measure(0, 'AVG', 'QuotaAmount'),
                        measure(1, 'SUM', 'QuotaQuantity'),
                        measure(2, 'MAX', 'QuotaAmount'),
                        measure(3, null, null)
                    }
                )
            );

        Assert.areEqual(new Set<Integer>{ 0, 1, 2, 3 }, result.rejectedMeasures.keySet());
        Assert.isTrue(result.rejectedMeasures.get(0).contains('only SUM or COUNT'));
        Assert.isTrue(result.rejectedMeasures.get(1).contains('can only sum QuotaAmount'));
        Assert.isTrue(recording.modes.isEmpty());
    }

    @IsTest
    static void aRejectedMeasureIsAConfigErrorOnTheWidget() {
        record();
        Map<String, Object> leg = new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'measures' => new List<Object>{
                new Map<String, Object>{ 'aggregateFunction' => 'SUM', 'valueFieldApiName' => 'Amount' }
            },
            'dataProvider' => 'BoardQuotaProvider'
        };
        try {
            BoardDataProviders.scanCrossObject(new BoardQueryService.QueryScope(leg), leg, 1);
            Assert.fail('Expected a config error');
        } catch (BoardErrors.BoardException failure) {
            Assert.areEqual(BoardErrors.CONFIG_ERROR, failure.category);
            Assert.isTrue(failure.getMessage().contains('BoardQuotaProvider'), failure.getMessage());
            Assert.isTrue(failure.getMessage().contains('Measure 2'), failure.getMessage());
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Engine query path with a query executor (system mode for the Quota provider)
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void standardBucketsRunEveryStatementThroughTheExecutorWithTheFilters() {
        Account account = new Account(Name = 'Quota Provider Account');
        insert account;
        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        insert new List<Opportunity>{
            new Opportunity(
                Name = 'Q1',
                AccountId = account.Id,
                Amount = 100,
                CloseDate = Date.today(),
                StageName = stage
            ),
            new Opportunity(
                Name = 'Q2',
                AccountId = account.Id,
                Amount = 250,
                CloseDate = Date.today(),
                StageName = stage
            )
        };
        Map<String, Object> query = new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'measures' => new List<Object>{
                new Map<String, Object>{ 'aggregateFunction' => 'SUM', 'valueFieldApiName' => 'Amount' }
            },
            'filters' => new List<Object>{
                new Map<String, Object>{
                    'filterId' => 'stage',
                    'type' => 'PICKLIST',
                    'fieldPath' => 'StageName',
                    'explicit' => true,
                    'operator' => 'IN',
                    'values' => new List<Object>{ stage }
                }
            },
            'dataProvider' => 'BoardQuotaProvider'
        };
        RecordingExecutor executor = new RecordingExecutor();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            grantQuotaViewer();
        }

        List<BoardDataProviderResult.Bucket> buckets = BoardDataProviders.standardBuckets(query, executor);
        List<BoardDataProviderResult.Bucket> systemBuckets;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            systemBuckets = BoardDataProviders.standardBuckets(query, new BoardQuotaProvider.SystemModeQueries());
        }

        Assert.areEqual(1, buckets.size());
        Assert.areEqual(350, buckets[0].measures[0].sum);
        Assert.isFalse(executor.statements.isEmpty(), 'The count and the aggregate go through the executor');
        for (String statement : executor.statements) {
            Assert.isTrue(statement.contains('StageName'), 'Filters apply: ' + statement);
        }
        Assert.areEqual(350, systemBuckets[0].measures[0].sum, 'System mode reads the same records for an admin');
    }

    @IsTest
    static void systemModeReadsAreRefusedWithoutThePermission() {
        revokeQuotaViewer();
        Map<String, Object> query = new Map<String, Object>{
            'objectApiName' => 'Account',
            'measures' => new List<Object>{ new Map<String, Object>{ 'aggregateFunction' => 'COUNT' } },
            'filters' => new List<Object>()
        };

        System.runAs(new User(Id = UserInfo.getUserId())) {
            try {
                new BoardQuotaProvider.EngineQuery().run(query, true);
                Assert.fail('System mode without Board_ViewAllQuotas must be refused');
            } catch (BoardErrors.BoardException failure) {
                Assert.areEqual(BoardErrors.ACCESS_ERROR, failure.category);
                Assert.isTrue(failure.getMessage().contains('Board_ViewAllQuotas'), failure.getMessage());
            }
        }
    }

    @IsTest
    static void quotaQueryRunsAgainstForecastingQuotaWhereForecastingIsEnabled() {
        Schema.SObjectType quotaType = Schema.getGlobalDescribe().get('forecastingquota');
        if (!BoardForecastingQuota.isAvailable() || quotaType == null || !quotaType.getDescribe().isAccessible()) {
            return; // No Forecasting in this org (or for this user): covered by the org verification.
        }
        Map<String, Object> query = new Map<String, Object>{
            'objectApiName' => 'ForecastingQuota',
            'groupByField' => 'StartDate',
            'dateGranularity' => 'CALENDAR_MONTH',
            'measures' => new List<Object>{
                new Map<String, Object>{ 'aggregateFunction' => 'SUM', 'valueFieldApiName' => 'QuotaAmount' }
            },
            'filters' => new List<Object>()
        };
        BoardQuotaProvider.EngineQuery engine = new BoardQuotaProvider.EngineQuery();

        List<BoardDataProviderResult.Bucket> userMode = engine.run(query, false);
        List<BoardDataProviderResult.Bucket> systemMode = engine.run(query, true);

        Assert.isNotNull(userMode);
        Assert.isTrue(systemMode.size() >= userMode.size(), 'System mode sees at least what the viewer sees');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    private static RecordingQuery record() {
        RecordingQuery recording = new RecordingQuery();
        BoardQuotaProvider.activeQuery = recording;
        return recording;
    }

    private static List<BoardDataProviderRequest.Measure> sumOfQuotaAmount() {
        return new List<BoardDataProviderRequest.Measure>{ measure(0, 'SUM', 'QuotaAmount') };
    }

    private static BoardDataProviderRequest.Measure measure(Integer index, String aggregateFunction, String field) {
        BoardDataProviderRequest.Measure measure = new BoardDataProviderRequest.Measure();
        measure.index = index;
        measure.aggregateFunction = aggregateFunction;
        measure.valueFieldApiName = field;
        return measure;
    }

    /** A Cross-object measure's request on ForecastingQuota, as the engine sends it. */
    private static BoardDataProviderRequest quotaRequest(List<BoardDataProviderRequest.Measure> measures) {
        BoardDataProviderRequest request = new BoardDataProviderRequest();
        request.widgetType = 'chart';
        request.objectApiName = 'ForecastingQuota';
        request.measures = measures;
        request.query = new Map<String, Object>{
            'objectApiName' => 'ForecastingQuota',
            'filters' => new List<Object>(),
            'dataProvider' => 'BoardQuotaProvider'
        };
        return request;
    }

    private static Id quotaViewerId() {
        return [SELECT Id FROM PermissionSet WHERE Name = :QUOTA_VIEWER LIMIT 1].Id;
    }

    private static void grantQuotaViewer() {
        Id permissionSetId = quotaViewerId();
        Id me = UserInfo.getUserId();
        if (
            [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE AssigneeId = :me AND PermissionSetId = :permissionSetId
            ] == 0
        ) {
            insert new PermissionSetAssignment(AssigneeId = me, PermissionSetId = permissionSetId);
        }
    }

    private static void revokeQuotaViewer() {
        Id permissionSetId = quotaViewerId();
        Id me = UserInfo.getUserId();
        delete [SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :me AND PermissionSetId = :permissionSetId];
    }
}