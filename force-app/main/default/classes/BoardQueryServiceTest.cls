@IsTest
private class BoardQueryServiceTest {
    private static final String RESTRICTED_ALIAS = 'brdqry';
    private static final String RESTRICTED_LAST_NAME = 'Boardquery Restricted';

    /**
     * Data: Alpha (Banking) <- Alpha Child (Energy, ParentId = Alpha), Beta (Energy).
     * Opportunities: Alpha 100 & 200, Beta 300 & null (closed two years ago), Alpha Child 400.
     * Cases: two on Alpha (High, Low), one on Beta (Low). Alpha's High case has a CaseComment; Beta's case a FeedItem.
     *
     * Restricted user: `Minimum Access - Salesforce` + Read on Account (FLS: Industry), Case (FLS: AccountId), and
     * Asset (FLS: AccountId, but not the other Account references AssetProvidedById / AssetServicedById).
     */
    @TestSetup
    static void setup() {
        User restrictedUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            restrictedUser = new User(
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1]
                .Id,
                Alias = RESTRICTED_ALIAS,
                LastName = RESTRICTED_LAST_NAME,
                Email = RESTRICTED_ALIAS + '@example.com',
                Username = RESTRICTED_ALIAS +
                    String.valueOf(Crypto.getRandomInteger()).replace('-', '') +
                    '@board-query.test',
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            );
            insert restrictedUser;
            PermissionSet permissionSet = new PermissionSet(Name = 'BoardQueryTestAccess', Label = 'Board Query Test');
            insert permissionSet;
            insert new List<ObjectPermissions>{
                new ObjectPermissions(ParentId = permissionSet.Id, SobjectType = 'Account', PermissionsRead = true),
                new ObjectPermissions(ParentId = permissionSet.Id, SobjectType = 'Case', PermissionsRead = true),
                new ObjectPermissions(ParentId = permissionSet.Id, SobjectType = 'Asset', PermissionsRead = true)
            };
            insert new List<FieldPermissions>{
                new FieldPermissions(
                    ParentId = permissionSet.Id,
                    SobjectType = 'Account',
                    Field = 'Account.Industry',
                    PermissionsRead = true
                ),
                new FieldPermissions(
                    ParentId = permissionSet.Id,
                    SobjectType = 'Case',
                    Field = 'Case.AccountId',
                    PermissionsRead = true
                ),
                new FieldPermissions(
                    ParentId = permissionSet.Id,
                    SobjectType = 'Asset',
                    Field = 'Asset.AccountId',
                    PermissionsRead = true
                )
            };
            insert new PermissionSetAssignment(AssigneeId = restrictedUser.Id, PermissionSetId = permissionSet.Id);
        }

        Account alpha = new Account(
            Name = 'Board Alpha',
            Industry = 'Banking',
            AnnualRevenue = 1000,
            OwnerId = restrictedUser.Id
        );
        Account beta = new Account(
            Name = 'Board Beta',
            Industry = 'Energy',
            AnnualRevenue = 500,
            OwnerId = restrictedUser.Id
        );
        insert new List<Account>{ alpha, beta };
        Account alphaChild = new Account(
            Name = 'Board Alpha Child',
            Industry = 'Energy',
            ParentId = alpha.Id,
            OwnerId = restrictedUser.Id
        );
        insert alphaChild;

        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        insert new List<Opportunity>{
            opportunity('Board Opp 1', alpha.Id, 100, Date.today(), stage),
            opportunity('Board Opp 2', alpha.Id, 200, Date.today(), stage),
            opportunity('Board Opp 3', beta.Id, 300, Date.today(), stage),
            opportunity('Board Opp 4', alphaChild.Id, 400, Date.today(), stage),
            opportunity('Board Opp 5', beta.Id, null, Date.today().addYears(-2), stage)
        };

        Case highCase = new Case(Subject = 'Board High', AccountId = alpha.Id, Priority = 'High');
        Case lowCase = new Case(Subject = 'Board Low', AccountId = alpha.Id, Priority = 'Low');
        Case betaCase = new Case(Subject = 'Board Beta', AccountId = beta.Id, Priority = 'Low');
        for (Case supportCase : new List<Case>{ highCase, lowCase, betaCase }) {
            supportCase.OwnerId = restrictedUser.Id;
        }
        insert new List<Case>{ highCase, lowCase, betaCase };
        insert new CaseComment(ParentId = highCase.Id, CommentBody = 'Board comment');
        insert new FeedItem(ParentId = betaCase.Id, Body = 'Board feed post');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Filter bindings
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void explicitBindingsSupportDirectFieldsAndParentDotPaths() {
        Map<String, Object> byAccount = metricRequest('Opportunity', 'COUNT', null);
        addFilter(byAccount, lookup('account', 'AccountId', true, accountId('Board Alpha')));
        BoardQueryService.MetricResult direct = run(byAccount);
        Assert.areEqual(2, direct.value, 'Direct AccountId binding');
        Assert.areEqual(new List<String>{ 'account' }, direct.appliedFilterIds);
        Assert.areEqual('SINGLE', direct.mode);
        Assert.isTrue(direct.isComplete);

        Map<String, Object> byIndustry = metricRequest('Opportunity', 'COUNT', null);
        addFilter(byIndustry, picklist('industry', 'Account.Industry', true, new List<String>{ 'Energy' }));
        Assert.areEqual(3, run(byIndustry).value, 'One-hop parent path: Beta x2 + Alpha Child');

        Map<String, Object> byParent = metricRequest('Opportunity', 'COUNT', null);
        addFilter(byParent, lookup('parent', 'Account.ParentId', true, accountId('Board Alpha')));
        Assert.areEqual(1, run(byParent).value, 'Parent hop to Account.ParentId');

        Map<String, Object> byGrandParent = metricRequest('Opportunity', 'COUNT', null);
        addFilter(
            byGrandParent,
            picklist('grandIndustry', 'Account.Parent.Industry', true, new List<String>{ 'Banking' })
        );
        Assert.areEqual(1, run(byGrandParent).value, 'Two-hop parent path');
    }

    @IsTest
    static void explicitChildSemiJoinsFilterParentsByChildRecords() {
        Map<String, Object> commented = metricRequest('Case', 'COUNT', null);
        Map<String, Object> commenter = filter('commenter', 'USER', 'CaseComment(ParentId).CreatedById', true, 'IN');
        commenter.put('token', 'ME');
        addFilter(commented, commenter);
        Assert.areEqual(1, run(commented).value, 'Only the High case has a CaseComment');

        Map<String, Object> posted = metricRequest('Case', 'COUNT', null);
        addFilter(posted, picklist('feedType', 'FeedItem(ParentId).Type', true, new List<String>{ 'TextPost' }));
        Assert.areEqual(1, run(posted).value, 'Polymorphic FeedItem.ParentId semi-join');

        Map<String, Object> accountsWithBigDeals = metricRequest('Account', 'COUNT', null);
        Map<String, Object> bigDeal = filter('bigDeal', 'DATE_RANGE', 'Opportunity(AccountId).CloseDate', true, 'GTE');
        bigDeal.put('from', String.valueOf(Date.today().addDays(-1)));
        addFilter(accountsWithBigDeals, bigDeal);
        Assert.areEqual(3, run(accountsWithBigDeals).value, 'Every account has a current opportunity');
    }

    @IsTest
    static void conventionBindingsResolveRecordContextOrSkipSilently() {
        Id alphaId = accountId('Board Alpha');

        Map<String, Object> cases = metricRequest('Case', 'COUNT', null);
        addFilter(cases, recordContext(alphaId));
        BoardQueryService.MetricResult caseResult = run(cases);
        Assert.areEqual(2, caseResult.value, 'Single Case.AccountId reference binds by convention');
        Assert.areEqual(new List<String>{ '$recordContext' }, caseResult.appliedFilterIds);

        Map<String, Object> accounts = metricRequest('Account', 'COUNT', null);
        addFilter(accounts, recordContext(alphaId));
        Assert.areEqual(1, run(accounts).value, 'Same object binds to Id');

        Map<String, Object> tasks = metricRequest('Task', 'COUNT', null);
        addFilter(tasks, recordContext(alphaId));
        BoardQueryService.MetricResult ambiguous = run(tasks);
        Assert.areEqual(new List<String>{ '$recordContext' }, ambiguous.ignoredFilterIds, 'AccountId + WhatId');
        Assert.isTrue(ambiguous.appliedFilterIds.isEmpty());

        Map<String, Object> opportunities = metricRequest('Opportunity', 'COUNT', null);
        addFilter(opportunities, recordContext([SELECT Id FROM Case LIMIT 1].Id));
        Map<String, Object> mine = filter('owner', 'USER', null, false, 'IN');
        mine.put('token', 'ME');
        addFilter(opportunities, mine);
        Map<String, Object> ignored = picklist('stage', 'IGNORE', true, new List<String>{ 'Anything' });
        addFilter(opportunities, ignored);
        BoardQueryService.MetricResult partial = run(opportunities);
        Assert.areEqual(5, partial.value, 'Opportunity has no Case reference; owner binds to OwnerId');
        Assert.areEqual(new List<String>{ 'owner' }, partial.appliedFilterIds);
        Assert.areEqual(new List<String>{ '$recordContext', 'stage' }, partial.ignoredFilterIds);
    }

    @IsTest
    static void restrictedUserFailsClosedOnExplicitInaccessibleFieldsButSkipsConventionFields() {
        Map<String, Object> explicitPriority = metricRequest('Case', 'COUNT', null);
        addFilter(explicitPriority, picklist('priority', 'Priority', true, new List<String>{ 'High' }));
        Map<String, Object> conventionPriority = metricRequest('Case', 'COUNT', null);
        addFilter(conventionPriority, picklist('priority', 'Priority', false, new List<String>{ 'High' }));
        Map<String, Object> industry = metricRequest('Case', 'COUNT', null);
        addFilter(industry, picklist('industry', 'Account.Industry', true, new List<String>{ 'Banking' }));
        Map<String, Object> revenue = metricRequest('Account', 'SUM', 'AnnualRevenue');

        Map<String, Object> explicitError;
        BoardQueryService.MetricResult skipped;
        Integer industryCount;
        Map<String, Object> objectError;
        Map<String, Object> valueFieldError;
        System.runAs(restrictedUser()) {
            explicitError = expectError(explicitPriority, 'ACCESS_ERROR');
            skipped = run(conventionPriority);
            industryCount = (Integer) run(industry).value;
            objectError = expectError(metricRequest('Opportunity', 'COUNT', null), 'ACCESS_ERROR');
            valueFieldError = expectError(revenue, 'ACCESS_ERROR');
        }

        Assert.areEqual('priority', explicitError.get('filterId'));
        Assert.areEqual('Priority', explicitError.get('fieldPath'));
        Assert.areEqual(false, explicitError.get('retryable'));
        Assert.areEqual(3, skipped.value, 'Unviewable convention field is skipped, not applied');
        Assert.areEqual(new List<String>{ 'priority' }, skipped.ignoredFilterIds);
        Assert.areEqual(2, industryCount, 'Readable parent path applies for the restricted user');
        Assert.areEqual('Opportunity', objectError.get('fieldPath'));
        Assert.areEqual('AnnualRevenue', valueFieldError.get('fieldPath'));
    }

    @IsTest
    static void stepTwoAmbiguityIgnoresFieldLevelSecurity() {
        // Asset has three Account references; the restricted user can read only AccountId.
        Id alphaId = accountId('Board Alpha');
        Map<String, Object> serverConvention = metricRequest('Asset', 'COUNT', null);
        addFilter(serverConvention, recordContext(alphaId));
        Map<String, Object> widgetConvention = metricRequest('Asset', 'COUNT', null);
        addFilter(widgetConvention, lookup('account', 'AccountId', false, alphaId));
        Map<String, Object> stepOne = metricRequest('Asset', 'COUNT', null);
        Map<String, Object> hinted = lookup('account', 'AccountId', false, alphaId);
        hinted.put('fieldApiName', 'AccountId');
        addFilter(stepOne, hinted);

        BoardQueryService.MetricResult serverResult;
        BoardQueryService.MetricResult widgetResult;
        BoardQueryService.MetricResult stepOneResult;
        System.runAs(restrictedUser()) {
            serverResult = run(serverConvention);
            widgetResult = run(widgetConvention);
            stepOneResult = run(stepOne);
        }

        Assert.areEqual(new List<String>{ '$recordContext' }, serverResult.ignoredFilterIds, 'Never binds AccountId');
        Assert.areEqual(
            new List<String>{ 'account' },
            widgetResult.ignoredFilterIds,
            'A Step 2 path resolved from readable fields only is re-checked'
        );
        Assert.areEqual(new List<String>{ 'account' }, stepOneResult.appliedFilterIds, 'Step 1 hint match applies');
    }

    @IsTest
    static void brokenExplicitBindingsAndBaseFiltersFailClosedWithConfigError() {
        assertBindingError(picklist('account', 'Account.Nope__c', true, new List<String>{ 'x' }), 'account');
        assertBindingError(lookup('child', 'Nope__c(ParentId).Id', true, accountId('Board Alpha')), 'child');
        assertBindingError(
            picklist('wrongFk', 'Contact(AccountId).LastName', true, new List<String>{ 'x' }),
            'wrongFk'
        );
        assertBindingError(
            picklist('deep', 'Account.Parent.Parent.Parent.Parent.Parent.Name', true, new List<String>{ 'x' }),
            'deep'
        );
        assertBindingError(picklist('relation', 'Nope.Name', true, new List<String>{ 'x' }), 'relation');
        assertBindingError(picklist('longText', 'Description', true, new List<String>{ 'x' }), 'longText');
        assertBindingError(lookup('badId', 'AccountId', true, 'not-an-id'), 'badId');
        assertBindingError(picklist('empty', ' ', true, new List<String>{ 'x' }), 'empty');

        Map<String, Object> wrongType = filter('closeDate', 'DATE_RANGE', 'StageName', true, 'LITERAL');
        wrongType.put('literal', 'TODAY');
        assertBindingError(wrongType, 'closeDate');
        Map<String, Object> badLiteral = filter('closeDate', 'DATE_RANGE', 'CloseDate', true, 'LITERAL');
        badLiteral.put('literal', 'TODAY OR Name != null');
        assertBindingError(badLiteral, 'closeDate');
        Map<String, Object> badDate = filter('closeDate', 'DATE_RANGE', 'CloseDate', true, 'BETWEEN');
        badDate.put('from', '2026-13-45');
        assertBindingError(badDate, 'closeDate');
        Map<String, Object> sosl = filter('search', 'TEXT', 'Name', true, 'SOSL');
        sosl.put('text', 'Board');
        assertBindingError(sosl, 'search');

        Map<String, Object> tooManyJoins = metricRequest('Case', 'COUNT', null);
        for (String filterId : new List<String>{ 'one', 'two', 'three' }) {
            Map<String, Object> semiJoin = filter(filterId, 'USER', 'CaseComment(ParentId).CreatedById', true, 'IN');
            semiJoin.put('token', 'ME');
            addFilter(tooManyJoins, semiJoin);
        }
        Assert.areEqual('three', expectError(tooManyJoins, 'CONFIG_ERROR').get('filterId'));

        Map<String, Object> conventionWrongType = metricRequest('Opportunity', 'COUNT', null);
        Map<String, Object> conventionDate = filter('closeDate', 'DATE_RANGE', 'StageName', false, 'LITERAL');
        conventionDate.put('literal', 'TODAY');
        addFilter(conventionWrongType, conventionDate);
        Assert.areEqual(5, run(conventionWrongType).value, 'Incompatible convention binding is skipped');

        assertBaseFilterError(baseFilter('bf1', 'Bogus__c', 'EQ', 'x'), 'bf1');
        assertBaseFilterError(baseFilter('bf2', 'Amount', 'GT', 'abc'), 'bf2');
        assertBaseFilterError(baseFilter('bf3', 'CloseDate', 'LITERAL', 'NOT_A_LITERAL'), 'bf3');
        assertBaseFilterError(baseFilter('bf4', 'Amount', 'LITERAL', 'TODAY'), 'bf4');
        assertBaseFilterError(baseFilter('bf5', 'Amount', 'LIKE', '1'), 'bf5');
        assertBaseFilterError(baseFilter('bf6', 'Amount', 'BETWEEN', '1'), 'bf6');
        assertBaseFilterError(baseFilter('bf7', 'Amount', 'GT', null), 'bf7');
        assertBaseFilterError(baseFilter('bf8', 'StageName', 'IN', new List<Object>()), 'bf8');
        assertBaseFilterError(baseFilter('bf9', '', 'EQ', 'x'), 'bf9');
    }

    @IsTest
    static void malformedRequestsAndValueFieldsFailClosedWithConfigError() {
        expectRawError('{ not json', 'CONFIG_ERROR');
        expectRawError('[1, 2]', 'CONFIG_ERROR');
        expectError(metricRequest('Nope__c', 'COUNT', null), 'CONFIG_ERROR');
        expectError(metricRequest('Opportunity', 'MEDIAN', 'Amount'), 'CONFIG_ERROR');
        expectError(metricRequest('Opportunity', 'SUM', null), 'CONFIG_ERROR');
        expectError(metricRequest('Opportunity', 'SUM', 'Name'), 'CONFIG_ERROR');
        expectError(metricRequest('Opportunity', 'SUM', 'Account.Nope__c'), 'CONFIG_ERROR');
        expectError(metricRequest('Opportunity', 'SUM', 'Account.Name'), 'CONFIG_ERROR');
        expectError(metricRequest('Account', 'SUM', 'Opportunity(AccountId).Amount'), 'CONFIG_ERROR');
        expectError(metricRequest('Opportunity', 'AVG', 'Nope__c'), 'CONFIG_ERROR');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Parent-path value fields
    // ---------------------------------------------------------------------------------------------------------

    // Opportunities: Alpha x2 (revenue 1000), Beta x2 (500), Alpha Child x1 (no revenue).

    @IsTest
    static void metricAggregatesParentPathValueFields() {
        BoardQueryService.MetricResult sum = run(metricRequest('Opportunity', 'SUM', 'Account.AnnualRevenue'));
        Assert.areEqual(3000, sum.value);
        Assert.areEqual('CURRENCY', sum.valueType);
        Assert.areEqual(750, run(metricRequest('Opportunity', 'AVG', 'Account.AnnualRevenue')).value);
        Assert.areEqual(500, run(metricRequest('Opportunity', 'MIN', 'account.annualrevenue')).value);
        Assert.areEqual(1000, run(metricRequest('Opportunity', 'MAX', 'Account.AnnualRevenue')).value);
        Assert.areEqual(2, run(metricRequest('Opportunity', 'COUNT_DISTINCT', 'Account.AnnualRevenue')).value);
        Assert.areEqual(
            1,
            run(metricRequest('Opportunity', 'COUNT_DISTINCT', 'Account.Parent.Industry')).value,
            'Two-hop path: only Alpha Child has a parent account'
        );
    }

    @IsTest
    static void cursorChunksReadParentPathValueFields() {
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
        BoardQueryService.CURSOR_CHUNK_SIZE = 2;
        Map<String, Object> request = metricRequest('Opportunity', 'SUM', 'Account.AnnualRevenue');
        BoardQueryService.MetricResult first = run(request);
        Assert.areEqual('CURSOR', first.mode);

        Decimal sum = 0;
        Integer count = 0;
        BoardQueryService.AggregateChunk chunk = first.chunk;
        while (true) {
            sum += chunk.buckets[0].sum;
            count += chunk.buckets[0].count;
            if (chunk.isComplete) {
                break;
            }
            Map<String, Object> next = request.clone();
            next.put('cursor', chunk.cursor);
            next.put('offset', chunk.nextOffset);
            chunk = BoardQueryService.fetchAggregateChunk(JSON.serialize(next));
        }
        Assert.areEqual(3000, sum);
        Assert.areEqual(4, count, 'Alpha Child has no revenue');
    }

    @IsTest
    static void cursorChunksSpanMultipleFetchCalls() {
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
        BoardQueryService.CURSOR_CHUNK_SIZE = 4;
        BoardQueryService.CURSOR_FETCH_SIZE = 3;
        Map<String, Object> request = metricRequest('Opportunity', 'SUM', 'Amount');
        BoardQueryService.MetricResult first = run(request);
        Assert.areEqual('CURSOR', first.mode);
        Assert.areEqual(4, first.chunk.nextOffset, 'Chunk of 4 read as fetches of 3 + 1');
        Assert.isFalse(first.chunk.isComplete);

        Map<String, Object> next = request.clone();
        next.put('cursor', first.chunk.cursor);
        next.put('offset', first.chunk.nextOffset);
        BoardQueryService.AggregateChunk last = BoardQueryService.fetchAggregateChunk(JSON.serialize(next));
        Assert.isTrue(last.isComplete);
        Assert.areEqual(5, last.nextOffset);
        Assert.areEqual(1000, first.chunk.buckets[0].sum + last.buckets[0].sum);
        Assert.areEqual(4, first.chunk.buckets[0].count + last.buckets[0].count, 'Board Opp 5 has no Amount');
    }

    @IsTest
    static void cursorFetchErrorsAreNotReportedAsExpiredCursors() {
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
        // An invalid fetch size (like the original 40,000 > 2,000 platform cap) throws InvalidParameterValueException;
        // it must surface as a real failure, not the retryable "cursor no longer available".
        BoardQueryService.CURSOR_FETCH_SIZE = -1;
        Map<String, Object> request = metricRequest('Opportunity', 'SUM', 'Amount');
        Map<String, Object> payload = expectError(request, 'QUERY_ERROR');
        Assert.areEqual(BoardErrors.GENERIC_MESSAGE, payload.get('message'));
    }

    @IsTest
    static void chartAggregatesParentPathValueFieldsInBothTiers() {
        Map<String, Object> request = chartRequest('Opportunity', 'SUM', 'Account.AnnualRevenue', 'AccountId');
        Map<String, Decimal> single = valuesByLabel(chart(request));
        Assert.areEqual(2000, single.get('Board Alpha'));
        Assert.areEqual(1000, single.get('Board Beta'));

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
        BoardQueryService.CURSOR_CHUNK_SIZE = 2;
        BoardChartQuery.ChartResult first = BoardChartQuery.queryChart(JSON.serialize(request));
        Assert.areEqual('CURSOR', first.mode);
        Map<String, Decimal> merged = valuesByLabel(chart(request));
        Assert.areEqual(2000, merged.get('Board Alpha'));
        Assert.areEqual(1000, merged.get('Board Beta'));
        Assert.isTrue(
            merged.get('Board Alpha Child') == null || merged.get('Board Alpha Child') == 0,
            'No parent revenue: ' + merged.get('Board Alpha Child')
        );
    }

    @IsTest
    static void parentPathValueFieldsRequireFieldAccessOnEveryHop() {
        Map<String, Object> payload;
        System.runAs(restrictedUser()) {
            // The restricted user reads Case, Case.AccountId, and Account.Industry, but not Account.AnnualRevenue.
            payload = expectError(metricRequest('Case', 'SUM', 'Account.AnnualRevenue'), 'ACCESS_ERROR');
        }
        Assert.areEqual('Account.AnnualRevenue', payload.get('fieldPath'));
    }

    @IsTest
    static void dateRangesPassLiteralsAndExpandIsoDatesToDayBoundaries() {
        String today = String.valueOf(Date.today());
        Assert.areEqual(4, countWith(dateFilter('CloseDate', 'LITERAL', 'last_n_days:30', null, null)));
        Assert.areEqual(
            4,
            countWith(dateFilter('CloseDate', 'BETWEEN', null, String.valueOf(Date.today().addDays(-1)), today))
        );
        Assert.areEqual(5, countWith(dateFilter('CreatedDate', 'BETWEEN', null, today, today)), 'Whole user day');
        Assert.areEqual(
            0,
            countWith(dateFilter('CreatedDate', 'GTE', null, String.valueOf(Date.today().addDays(1)), null))
        );
        Assert.areEqual(
            0,
            countWith(dateFilter('CreatedDate', 'LTE', null, null, String.valueOf(Date.today().addDays(-1))))
        );
        Assert.areEqual(5, countWith(dateFilter('CreatedDate', 'LTE', null, null, today)), 'End of day inclusive');
    }

    @IsTest
    static void picklistAndTextFiltersAdaptToFieldTypes() {
        Assert.areEqual(5, countWith(picklist('private', 'IsPrivate', true, new List<String>{ 'false' })));
        Map<String, Object> contains = filter('search', 'TEXT', 'Name', true, 'CONTAINS');
        contains.put('text', 'Opp');
        Assert.areEqual(5, countWith(contains));
        Map<String, Object> startsWith = filter('search', 'TEXT', 'Name', true, 'STARTS_WITH');
        startsWith.put('text', 'Opp');
        Assert.areEqual(0, countWith(startsWith));
        Map<String, Object> wildcard = filter('search', 'TEXT', 'Name', true, 'CONTAINS');
        wildcard.put('text', '%%');
        Assert.areEqual(0, countWith(wildcard), 'LIKE wildcards are escaped');

        Map<String, Object> tooShort = metricRequest('Opportunity', 'COUNT', null);
        Map<String, Object> oneCharacter = filter('search', 'TEXT', 'Name', true, 'CONTAINS');
        oneCharacter.put('text', 'x');
        addFilter(tooShort, oneCharacter);
        BoardQueryService.MetricResult shortResult = run(tooShort);
        Assert.areEqual(5, shortResult.value, 'One character never filters (minCharacters floor of 2)');
        Assert.areEqual(new List<String>{ 'search' }, shortResult.ignoredFilterIds);
        Map<String, Object> belowMinimum = filter('search', 'TEXT', 'Name', true, 'CONTAINS');
        belowMinimum.put('text', 'Opp 9');
        belowMinimum.put('minCharacters', 6);
        Assert.areEqual(5, countWith(belowMinimum), 'The filter minCharacters raises the floor');

        List<Schema.PicklistEntry> channels = QuickText.Channel.getDescribe().getPicklistValues();
        insert new List<QuickText>{
            new QuickText(Name = 'Board QT 1', Message = 'One', Channel = channels[0].getValue()),
            new QuickText(
                Name = 'Board QT 2',
                Message = 'Two',
                Channel = channels[0].getValue() + ';' + channels[1].getValue()
            ),
            new QuickText(Name = 'Board QT 3', Message = 'Three', Channel = channels[1].getValue())
        };
        Map<String, Object> multi = metricRequest('QuickText', 'COUNT', null);
        addFilter(multi, picklist('channel', 'Channel', true, new List<String>{ channels[0].getValue() }));
        Assert.areEqual(2, run(multi).value, 'IN adapts to INCLUDES on MultiPicklist');
        Map<String, Object> excludes = metricRequest('QuickText', 'COUNT', null);
        addBaseFilter(excludes, baseFilter('bf', 'Channel', 'NOT_IN', new List<Object>{ channels[0].getValue() }));
        Assert.areEqual(1, run(excludes).value, 'NOT_IN adapts to EXCLUDES on MultiPicklist');
    }

    @IsTest
    static void baseFiltersCombineWithBoardFiltersUsingAnd() {
        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        String today = String.valueOf(Date.today());
        Assert.areEqual(3, countWithBase(baseFilter('min', 'Amount', 'GTE', 200)));
        Assert.areEqual(1, countWithBase(baseFilter('max', 'Amount', 'LT', '200')));
        Assert.areEqual(1, countWithBase(baseFilter('blank', 'Amount', 'IS_NULL', true)));
        Assert.areEqual(4, countWithBase(baseFilter('present', 'Amount', 'IS_NULL', false)));
        Assert.areEqual(4, countWithBase(baseFilter('notNull', 'Amount', 'NEQ', null)));
        Assert.areEqual(1, countWithBase(baseFilter('eq', 'Amount', 'EQ', 300)));
        Assert.areEqual(5, countWithBase(baseFilter('stage', 'StageName', 'IN', new List<Object>{ stage })));
        Assert.areEqual(0, countWithBase(baseFilter('notStage', 'StageName', 'NOT_IN', stage)));
        Assert.areEqual(5, countWithBase(baseFilter('like', 'Name', 'LIKE', 'Opp')));
        Assert.areEqual(5, countWithBase(baseFilter('likeRaw', 'Name', 'LIKE', 'Board%')));
        Assert.areEqual(4, countWithBase(baseFilter('quarter', 'CloseDate', 'LITERAL', 'THIS_FISCAL_YEAR')));
        Assert.areEqual(4, countWithBase(baseFilter('closeDate', 'CloseDate', 'EQ', today)));
        Assert.areEqual(5, countWithBase(baseFilter('createdDay', 'CreatedDate', 'EQ', today)));
        Assert.areEqual(0, countWithBase(baseFilter('notCreatedDay', 'CreatedDate', 'NEQ', today)));
        Assert.areEqual(0, countWithBase(baseFilter('createdAfter', 'CreatedDate', 'GT', today)));
        Assert.areEqual(5, countWithBase(baseFilter('createdFrom', 'CreatedDate', 'GTE', today)));
        Assert.areEqual(0, countWithBase(baseFilter('createdBefore', 'CreatedDate', 'LT', today)));
        Assert.areEqual(5, countWithBase(baseFilter('createdUntil', 'CreatedDate', 'LTE', today)));
        Assert.areEqual(
            5,
            countWithBase(
                baseFilter(
                    'createdBy',
                    'CreatedDate',
                    'LT',
                    Datetime.now().addDays(1).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                )
            )
        );
        Assert.areEqual(5, countWithBase(baseFilter('private', 'IsPrivate', 'NOT_IN', new List<Object>{ true })));
        Assert.areEqual(1, countWithBase(baseFilter('parent', 'Account.ParentId', 'EQ', accountId('Board Alpha'))));

        Map<String, Object> combined = metricRequest('Opportunity', 'COUNT', null);
        addFilter(combined, lookup('account', 'AccountId', true, accountId('Board Beta')));
        addBaseFilter(combined, baseFilter('min', 'Amount', 'GTE', 200));
        Assert.areEqual(1, run(combined).value, 'Beta 300 only');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Aggregation tiers
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void tierOneComputesEveryAggregateInASingleCall() {
        Assert.areEqual(5, run(metricRequest('Opportunity', 'COUNT', null)).value);
        Assert.areEqual(1000, (Decimal) run(metricRequest('Opportunity', 'SUM', 'Amount')).value);
        Assert.areEqual(250, (Decimal) run(metricRequest('Opportunity', 'AVG', 'Amount')).value, 'Nulls ignored');
        Assert.areEqual(3, run(metricRequest('Opportunity', 'COUNT_DISTINCT', 'AccountId')).value);

        BoardQueryService.MetricResult min = run(metricRequest('Opportunity', 'MIN', 'Amount'));
        Assert.areEqual(100, (Decimal) min.value);
        Assert.areEqual('CURRENCY', min.valueType);
        Assert.isNull(min.totalRows, 'MIN/MAX use ORDER BY ... LIMIT 1 without counting');
        Assert.areEqual(400, (Decimal) run(metricRequest('Opportunity', 'MAX', 'Amount')).value);

        BoardQueryService.MetricResult earliest = run(metricRequest('Opportunity', 'MIN', 'CloseDate'));
        Assert.areEqual(Date.today().addYears(-2), earliest.value);
        Assert.areEqual('DATE', earliest.valueType);

        BoardQueryService.MetricResult sum = run(metricRequest('Opportunity', 'SUM', 'Amount'));
        Assert.areEqual(5, sum.totalRows);
        Assert.areEqual('SINGLE', sum.mode);
    }

    @IsTest
    static void zeroMatchingRowsReturnNullForValueAggregates() {
        for (String aggregateFunction : new List<String>{ 'SUM', 'AVG', 'MIN', 'MAX', 'COUNT_DISTINCT', 'COUNT' }) {
            Map<String, Object> request = metricRequest('Opportunity', aggregateFunction, 'Amount');
            addFilter(request, picklist('industry', 'Account.Industry', true, new List<String>{ 'Nope' }));
            BoardQueryService.MetricResult result = run(request);
            if (aggregateFunction == 'COUNT' || aggregateFunction == 'COUNT_DISTINCT') {
                Assert.areEqual(0, result.value, aggregateFunction);
            } else {
                Assert.isNull(result.value, aggregateFunction + ' over zero rows');
            }
        }
    }

    @IsTest
    static void tierTwoChunksSumAndAvgThroughDatabaseCursor() {
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
        BoardQueryService.CURSOR_CHUNK_SIZE = 2;

        Map<String, Object> request = metricRequest('Opportunity', 'AVG', 'Amount');
        BoardQueryService.MetricResult first = run(request);
        Assert.areEqual('CURSOR', first.mode);
        Assert.isFalse(first.isComplete);
        Assert.isNull(first.value);
        Assert.areEqual(5, first.totalRows);
        Assert.areEqual(5, first.chunk.totalRows);
        Assert.areEqual(2, first.chunk.nextOffset);
        Assert.isNotNull(first.chunk.cursor);

        Decimal sum = 0;
        Integer count = 0;
        Decimal min;
        Decimal max;
        Integer calls = 1;
        BoardQueryService.AggregateChunk chunk = first.chunk;
        while (true) {
            BoardChartEngine.Partial bucket = chunk.buckets[0];
            Assert.areEqual(1, chunk.buckets.size(), 'One ungrouped bucket per chunk');
            sum += bucket.sum;
            count += bucket.count;
            min = min == null || (bucket.min != null && bucket.min < min) ? bucket.min : min;
            max = max == null || (bucket.max != null && bucket.max > max) ? bucket.max : max;
            if (chunk.isComplete) {
                break;
            }
            Map<String, Object> next = request.clone();
            next.put('cursor', chunk.cursor);
            next.put('offset', chunk.nextOffset);
            chunk = BoardQueryService.fetchAggregateChunk(JSON.serialize(next));
            calls++;
        }
        Assert.areEqual(3, calls, '5 rows in chunks of 2');
        Assert.areEqual(1000, sum);
        Assert.areEqual(4, count, 'Null amounts are not counted');
        Assert.areEqual(100, min);
        Assert.areEqual(400, max);
    }

    @IsTest
    static void tierThreeFailsWithLimitExceeded() {
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
        BoardQueryService.CURSOR_MAX_ROWS = 4;

        Map<String, Object> sumError = expectError(metricRequest('Opportunity', 'SUM', 'Amount'), 'LIMIT_EXCEEDED');
        Assert.isTrue(((String) sumError.get('message')).contains('5 records'), (String) sumError.get('message'));
        Assert.areEqual(false, sumError.get('retryable'));

        BoardQueryService.CURSOR_MAX_ROWS = 200000;
        expectError(metricRequest('Opportunity', 'COUNT_DISTINCT', 'AccountId'), 'LIMIT_EXCEEDED');
        Assert.areEqual(5, run(metricRequest('Opportunity', 'COUNT', null)).value, 'COUNT is never limited');
    }

    @IsTest
    static void expiredOrInvalidCursorIsRetryableQueryError() {
        Map<String, Object> request = metricRequest('Opportunity', 'SUM', 'Amount');
        // A syntactically valid but unknown queryId raises an uncatchable platform error; use a corrupt handle.
        request.put('cursor', 'not-a-cursor-handle');
        request.put('offset', 0);
        try {
            BoardQueryService.fetchAggregateChunk(JSON.serialize(request));
            Assert.fail('Expected a cursor error');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('QUERY_ERROR', payload.get('category'));
            Assert.areEqual(true, payload.get('retryable'));
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Chart dimensions (category / series fields of `scanChart`)
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void chartReferenceGroupsDisplayRelatedRecordNames() {
        BoardChartQuery.ChartResult byAccount = chart(chartRequest('Opportunity', 'COUNT', null, 'AccountId'));
        Assert.areEqual('SINGLE', byAccount.mode);
        Assert.areEqual('Account.Name', byAccount.groupBy.labelFieldPath);
        Assert.areEqual('REFERENCE', byAccount.groupBy.dataType);
        Assert.isNull(byAccount.stackBy);
        Map<String, Decimal> accounts = valuesByLabel(byAccount);
        Assert.areEqual(new Set<String>{ 'Board Alpha', 'Board Beta', 'Board Alpha Child' }, accounts.keySet());
        Assert.areEqual(2, accounts.get('Board Alpha'));
        Assert.areEqual(
            String.valueOf(accountId('Board Alpha')),
            categoriesByLabel(byAccount).get('Board Alpha').value
        );

        BoardChartQuery.ChartResult byOwner = chart(chartRequest('Case', 'COUNT', null, 'OwnerId'));
        Assert.areEqual('Owner.Name', byOwner.groupBy.labelFieldPath, 'Polymorphic owner resolves the User name');
        Assert.areEqual(new Map<String, Decimal>{ RESTRICTED_LAST_NAME => 3 }, valuesByLabel(byOwner));

        BoardChartQuery.ChartResult byIndustry = chart(
            chartRequest('Opportunity', 'SUM', 'Amount', 'Account.Industry')
        );
        Map<String, Decimal> industries = valuesByLabel(byIndustry);
        Assert.areEqual(300, industries.get('Banking'));
        Assert.areEqual(700, industries.get('Energy'), 'Parent dot-path: Beta 300 + Alpha Child 400');
        Assert.areEqual(5, byIndustry.totalRows);
        Assert.areEqual('CURRENCY', byIndustry.valueTypes[0]);
    }

    @IsTest
    static void chartBlankCategoriesAreKeptByDefaultAndExcludedOnRequest() {
        Map<String, Object> request = chartRequest('Opportunity', 'COUNT', null, 'Account.ParentId');
        BoardChartQuery.ChartResult withBlank = chart(request);
        Map<String, BoardChartEngine.ChartKey> categories = categoriesByLabel(withBlank);
        Assert.areEqual(2, categories.size());
        Assert.isTrue(categories.get(BoardChartEngine.BLANK_LABEL).isBlank, 'Null parent category (4 rows)');
        Assert.areEqual(4, valuesByLabel(withBlank).get(BoardChartEngine.BLANK_LABEL));
        Assert.isTrue(categories.containsKey('Board Alpha'), 'Account.Parent.Name label');

        request.put('includeNullBucket', false);
        Assert.areEqual(new Set<String>{ 'Board Alpha' }, valuesByLabel(chart(request)).keySet());
    }

    @IsTest
    static void chartDateGroupsBucketByGranularityWithSortableKeys() {
        Date today = Date.today();
        Date older = today.addYears(-2);
        String year = String.valueOf(today.year());
        String month = year + '-' + String.valueOf(today.month()).leftPad(2, '0');
        String quarter = year + '-Q' + ((today.month() - 1) / 3 + 1);

        BoardChartQuery.ChartResult years = chart(dateChartRequest('CloseDate', 'CALENDAR_YEAR'));
        Assert.areEqual(4, valuesByValue(years).get(year));
        Assert.areEqual(1, valuesByValue(years).get(String.valueOf(older.year())));
        Assert.areEqual(year, categoriesByValue(years).get(year).label);

        BoardChartQuery.ChartResult months = chart(dateChartRequest('CloseDate', 'CALENDAR_MONTH'));
        Assert.areEqual(4, valuesByValue(months).get(month));
        Assert.areEqual(
            Datetime.newInstance(today.year(), today.month(), 1).format('MMM yyyy'),
            categoriesByValue(months).get(month).label
        );

        BoardChartQuery.ChartResult quarters = chart(dateChartRequest('CloseDate', 'CALENDAR_QUARTER'));
        Assert.areEqual('CALENDAR_QUARTER', quarters.groupBy.dateGranularity);
        Assert.areEqual(4, valuesByValue(quarters).get(quarter));

        BoardChartQuery.ChartResult days = chart(dateChartRequest('CloseDate', null));
        Assert.areEqual('DAY', days.groupBy.dateGranularity, 'Date fields default to DAY buckets');
        Assert.areEqual(today.format(), categoriesByValue(days).get(String.valueOf(today)).label);

        BoardChartQuery.ChartResult created = chart(dateChartRequest('CreatedDate', 'CALENDAR_MONTH'));
        Assert.areEqual(5, valuesByValue(created).get(month), 'DateTime buckets in the user time zone');
        Assert.areEqual(5, valuesByValue(chart(dateChartRequest('CreatedDate', 'DAY'))).get(String.valueOf(today)));

        BoardChartQuery.ChartResult fiscalYears = chart(dateChartRequest('CloseDate', 'FISCAL_YEAR'));
        Assert.areEqual(2, fiscalYears.categories.size());
        for (BoardChartEngine.ChartKey category : fiscalYears.categories) {
            Assert.isTrue(Pattern.matches('FY\\d{4}', category.value), category.value);
            Assert.areEqual(category.value, category.label);
        }
        for (BoardChartEngine.ChartKey category : chart(dateChartRequest('CloseDate', 'FISCAL_QUARTER')).categories) {
            Assert.isTrue(Pattern.matches('FY\\d{4}-Q[1-4]', category.value), category.value);
            Assert.isTrue(Pattern.matches('Q[1-4] FY\\d{4}', category.label), category.label);
        }

        expectChartError(dateChartRequest('StageName', 'CALENDAR_MONTH'), 'CONFIG_ERROR');
        expectChartError(dateChartRequest('CloseDate', 'WEEK'), 'CONFIG_ERROR');
    }

    @IsTest
    static void chartPicklistGroupsReturnDescribeOrderAndSeries() {
        List<String> activePriorities = new List<String>();
        Map<String, String> priorityLabels = new Map<String, String>();
        for (Schema.PicklistEntry entry : Case.Priority.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                activePriorities.add(entry.getValue());
                priorityLabels.put(entry.getValue(), entry.getLabel());
            }
        }
        BoardChartQuery.ChartResult byPriority = chart(chartRequest('Case', 'COUNT', null, 'Priority'));
        Assert.areEqual(activePriorities, byPriority.groupBy.picklistOrder);
        Assert.areEqual(2, valuesByValue(byPriority).get('Low'));
        Assert.areEqual(
            priorityLabels.get('High'),
            categoriesByValue(byPriority).get('High').label,
            'Translated picklist label'
        );

        Map<String, Object> split = chartRequest('Case', 'COUNT', null, 'AccountId');
        split.put('stackByField', 'Priority');
        BoardChartQuery.ChartResult series = chart(split);
        Assert.areEqual('Priority', series.stackBy.fieldPath);
        Assert.areEqual(activePriorities, series.stackBy.picklistOrder);
        Map<String, String> categoryLabels = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : series.categories) {
            categoryLabels.put(category.key, category.label);
        }
        Map<String, String> seriesValues = new Map<String, String>();
        for (BoardChartEngine.ChartKey entry : series.series) {
            seriesValues.put(entry.key, entry.value);
        }
        Map<String, Decimal> counts = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : series.points) {
            if (point.value != null && point.value != 0) {
                counts.put(
                    categoryLabels.get(point.categoryKey) + '|' + seriesValues.get(point.seriesKey),
                    point.value
                );
            }
        }
        Assert.areEqual(
            new Map<String, Decimal>{ 'Board Alpha|High' => 1, 'Board Alpha|Low' => 1, 'Board Beta|Low' => 1 },
            counts
        );
    }

    @IsTest
    static void chartValueAggregatesRunPerGroup() {
        Map<String, Decimal> averages = valuesByLabel(chart(chartRequest('Opportunity', 'AVG', 'Amount', 'AccountId')));
        Assert.areEqual(150, averages.get('Board Alpha'));
        Assert.areEqual(300, averages.get('Board Beta'), 'Null amounts ignored');
        Map<String, Decimal> minimums = valuesByLabel(chart(chartRequest('Opportunity', 'MIN', 'Amount', 'AccountId')));
        Assert.areEqual(100, minimums.get('Board Alpha'));
        Map<String, Decimal> distinct = valuesByLabel(
            chart(chartRequest('Opportunity', 'COUNT_DISTINCT', 'AccountId', 'Account.Industry'))
        );
        Assert.areEqual(2, distinct.get('Energy'));
    }

    @IsTest
    static void unexpectedFailuresReturnAGenericRetryableMessage() {
        Map<String, Object> request = metricRequest('Opportunity', 'SUM', 'Amount');
        request.put('cursor', 'not-a-cursor-handle');
        request.put('offset', 'not-a-number');
        try {
            BoardQueryService.fetchAggregateChunk(JSON.serialize(request));
            Assert.fail('Expected an error');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('QUERY_ERROR', payload.get('category'));
            Assert.areEqual(BoardErrors.GENERIC_MESSAGE, payload.get('message'), 'Platform details are not returned');
            Assert.areEqual(true, payload.get('retryable'));
        }
    }

    @IsTest
    static void chartCursorTierGroupsLikeTheSoqlDateFunctions() {
        Map<String, Object> request = dateChartRequest('CloseDate', 'FISCAL_QUARTER');
        request.put('measures', new List<Object>{ measure('SUM', 'Amount') });
        request.put('stackByField', 'AccountId');
        Map<String, Decimal> single = valuesBySeries(chart(request));

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
        BoardQueryService.CURSOR_CHUNK_SIZE = 2;
        BoardChartQuery.ChartResult first = BoardChartQuery.queryChart(JSON.serialize(request));
        Assert.areEqual('CURSOR', first.mode);
        Assert.isFalse(first.isComplete);
        Assert.areEqual(5, first.totalRows);
        Map<String, Decimal> merged = valuesBySeries(chart(request));
        Assert.areEqual(single.keySet(), merged.keySet(), 'Cursor groups match SOQL fiscal date functions');
        for (String key : single.keySet()) {
            Decimal expected = single.get(key) == null ? 0 : single.get(key);
            Decimal actual = merged.get(key) == null ? 0 : merged.get(key);
            Assert.areEqual(expected, actual, key);
        }

        Map<String, Object> created = dateChartRequest('CreatedDate', 'CALENDAR_MONTH');
        created.put('measures', new List<Object>{ measure('MAX', 'Amount') });
        BoardQueryService.CURSOR_CHUNK_SIZE = 10;
        Date today = Date.today();
        String month = String.valueOf(today.year()) + '-' + String.valueOf(today.month()).leftPad(2, '0');
        Assert.areEqual(400, valuesByValue(chart(created)).get(month), 'DateTime cursor rows in the user time zone');

        for (String granularity : new List<String>{ 'DAY', 'CALENDAR_QUARTER', 'CALENDAR_YEAR', 'FISCAL_YEAR' }) {
            Map<String, Object> bucketed = dateChartRequest('CloseDate', granularity);
            bucketed.put('measures', new List<Object>{ measure('AVG', 'Amount') });
            Set<String> cursorKeys = valuesByValue(chart(bucketed)).keySet();
            BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 49900;
            Set<String> singleKeys = valuesByValue(chart(bucketed)).keySet();
            BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
            Assert.areEqual(singleKeys, cursorKeys, granularity);
        }
    }

    @IsTest
    static void chartFailsClosedOnLimitsInvalidDimensionsAndInaccessibleFields() {
        expectChartError(chartRequest('Opportunity', 'COUNT', null, null), 'CONFIG_ERROR');
        expectChartError(chartRequest('Opportunity', 'COUNT', null, 'Description'), 'CONFIG_ERROR');
        expectChartError(
            chartRequest('Opportunity', 'COUNT', null, 'OpportunityLineItem(OpportunityId).Quantity'),
            'CONFIG_ERROR'
        );
        expectChartError(chartRequest('Opportunity', 'SUM', 'Name', 'StageName'), 'CONFIG_ERROR');
        expectChartError(chartRequest('Opportunity', 'MEDIAN', 'Amount', 'StageName'), 'CONFIG_ERROR');
        Map<String, Object> badSeries = chartRequest('Opportunity', 'COUNT', null, 'StageName');
        badSeries.put('stackByField', 'Nope__c');
        Assert.areEqual('Nope__c', expectChartError(badSeries, 'CONFIG_ERROR').get('fieldPath'));

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
        expectChartError(chartRequest('Opportunity', 'COUNT_DISTINCT', 'AccountId', 'StageName'), 'LIMIT_EXCEEDED');
        BoardQueryService.CURSOR_MAX_ROWS = 4;
        expectChartError(chartRequest('Opportunity', 'SUM', 'Amount', 'StageName'), 'LIMIT_EXCEEDED');
        Assert.areEqual(
            'SINGLE',
            BoardChartQuery.queryChart(JSON.serialize(chartRequest('Opportunity', 'COUNT', null, 'StageName'))).mode,
            'Grouped COUNT is never limited'
        );

        Map<String, Object> accessError;
        System.runAs(restrictedUser()) {
            accessError = expectChartError(chartRequest('Case', 'COUNT', null, 'Priority'), 'ACCESS_ERROR');
        }
        Assert.areEqual('Priority', accessError.get('fieldPath'));
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** A Chart widget request with one Measure (all categories kept, so every group is visible). */
    private static Map<String, Object> chartRequest(
        String objectApiName,
        String aggregateFunction,
        String valueField,
        String groupByField
    ) {
        Map<String, Object> request = metricRequest(objectApiName, aggregateFunction, valueField);
        request.remove('aggregateFunction');
        request.remove('valueFieldApiName');
        request.put('measures', new List<Object>{ measure(aggregateFunction, valueField) });
        request.put('groupByField', groupByField);
        request.put('maxCategories', 200);
        return request;
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        Map<String, Object> entry = new Map<String, Object>{ 'aggregateFunction' => aggregateFunction };
        if (valueField != null) {
            entry.put('valueFieldApiName', valueField);
        }
        return entry;
    }

    private static Map<String, Object> dateChartRequest(String groupByField, String dateGranularity) {
        Map<String, Object> request = chartRequest('Opportunity', 'COUNT', null, groupByField);
        request.put('dateGranularity', dateGranularity);
        return request;
    }

    /** The complete chart: the first call, then every cursor chunk until `isComplete`. */
    private static BoardChartQuery.ChartResult chart(Map<String, Object> request) {
        BoardChartQuery.ChartResult result = BoardChartQuery.queryChart(JSON.serialize(request));
        while (!result.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.cursor);
            next.put('offset', result.nextOffset);
            next.put('partialState', result.partialState);
            result = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }
        return result;
    }

    private static Map<String, BoardChartEngine.ChartKey> categoriesByLabel(BoardChartQuery.ChartResult result) {
        Map<String, BoardChartEngine.ChartKey> categories = new Map<String, BoardChartEngine.ChartKey>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            categories.put(category.label, category);
        }
        return categories;
    }

    private static Map<String, BoardChartEngine.ChartKey> categoriesByValue(BoardChartQuery.ChartResult result) {
        Map<String, BoardChartEngine.ChartKey> categories = new Map<String, BoardChartEngine.ChartKey>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            categories.put(category.value, category);
        }
        return categories;
    }

    /** The first Measure's value per category label (charts without a series field). */
    private static Map<String, Decimal> valuesByLabel(BoardChartQuery.ChartResult result) {
        return valuesBy(result, false);
    }

    /** The first Measure's value per category stored value (charts without a series field). */
    private static Map<String, Decimal> valuesByValue(BoardChartQuery.ChartResult result) {
        return valuesBy(result, true);
    }

    private static Map<String, Decimal> valuesBy(BoardChartQuery.ChartResult result, Boolean byValue) {
        Map<String, String> names = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            names.put(category.key, byValue ? category.value : category.label);
        }
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            if (point.measureIndex == 0) {
                values.put(names.get(point.categoryKey), point.value);
            }
        }
        return values;
    }

    /** Values keyed `categoryValue|seriesLabel`. */
    private static Map<String, Decimal> valuesBySeries(BoardChartQuery.ChartResult result) {
        Map<String, String> categories = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            categories.put(category.key, category.value);
        }
        Map<String, String> series = new Map<String, String>();
        for (BoardChartEngine.ChartKey entry : result.series) {
            series.put(entry.key, entry.label);
        }
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(categories.get(point.categoryKey) + '|' + series.get(point.seriesKey), point.value);
        }
        return values;
    }

    private static Map<String, Object> expectChartError(Map<String, Object> request, String category) {
        try {
            chart(request);
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual(category, payload.get('category'), String.valueOf(payload));
            return payload;
        }
        Assert.fail('Expected ' + category + ' for ' + JSON.serialize(request));
        return null;
    }

    private static Opportunity opportunity(String name, Id accountId, Decimal amount, Date closeDate, String stage) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            Amount = amount,
            CloseDate = closeDate,
            StageName = stage
        );
    }

    private static User restrictedUser() {
        return [SELECT Id FROM User WHERE Alias = :RESTRICTED_ALIAS AND LastName = :RESTRICTED_LAST_NAME LIMIT 1];
    }

    private static Id accountId(String name) {
        return [SELECT Id FROM Account WHERE Name = :name LIMIT 1].Id;
    }

    private static Map<String, Object> metricRequest(
        String objectApiName,
        String aggregateFunction,
        String valueField
    ) {
        return new Map<String, Object>{
            'objectApiName' => objectApiName,
            'aggregateFunction' => aggregateFunction,
            'valueFieldApiName' => valueField,
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'refreshToken' => 0
        };
    }

    private static Map<String, Object> filter(
        String filterId,
        String type,
        String fieldPath,
        Boolean explicit,
        String operator
    ) {
        return new Map<String, Object>{
            'filterId' => filterId,
            'type' => type,
            'fieldPath' => fieldPath,
            'explicit' => explicit,
            'operator' => operator,
            'values' => new List<Object>()
        };
    }

    private static Map<String, Object> picklist(
        String filterId,
        String fieldPath,
        Boolean explicit,
        List<String> values
    ) {
        Map<String, Object> entry = filter(filterId, 'PICKLIST', fieldPath, explicit, 'IN');
        entry.put('values', values);
        return entry;
    }

    private static Map<String, Object> lookup(String filterId, String fieldPath, Boolean explicit, String recordId) {
        Map<String, Object> entry = filter(filterId, 'LOOKUP', fieldPath, explicit, 'IN');
        entry.put('values', new List<Object>{ recordId });
        entry.put('targetObjectApiName', 'Account');
        return entry;
    }

    private static Map<String, Object> recordContext(Id recordId) {
        Map<String, Object> entry = filter('$recordContext', 'RECORD_CONTEXT', null, false, 'IN');
        entry.put('values', new List<Object>{ recordId });
        return entry;
    }

    private static Map<String, Object> dateFilter(
        String fieldPath,
        String operator,
        String literal,
        String fromValue,
        String toValue
    ) {
        Map<String, Object> entry = filter('dates', 'DATE_RANGE', fieldPath, true, operator);
        entry.put('literal', literal);
        entry.put('from', fromValue);
        entry.put('to', toValue);
        return entry;
    }

    private static Map<String, Object> baseFilter(String id, String fieldPath, String operator, Object value) {
        return new Map<String, Object>{
            'id' => id,
            'fieldPath' => fieldPath,
            'operator' => operator,
            'value' => value
        };
    }

    private static void addFilter(Map<String, Object> request, Map<String, Object> entry) {
        ((List<Object>) request.get('filters')).add(entry);
    }

    private static void addBaseFilter(Map<String, Object> request, Map<String, Object> condition) {
        ((List<Object>) request.get('baseFilters')).add(condition);
    }

    private static Integer countWith(Map<String, Object> entry) {
        Map<String, Object> request = metricRequest('Opportunity', 'COUNT', null);
        addFilter(request, entry);
        return (Integer) run(request).value;
    }

    private static Integer countWithBase(Map<String, Object> condition) {
        Map<String, Object> request = metricRequest('Opportunity', 'COUNT', null);
        addBaseFilter(request, condition);
        return (Integer) run(request).value;
    }

    private static BoardQueryService.MetricResult run(Map<String, Object> request) {
        return BoardQueryService.queryMetric(JSON.serialize(request));
    }

    private static Map<String, Object> expectError(Map<String, Object> request, String category) {
        return expectRawError(JSON.serialize(request), category);
    }

    private static Map<String, Object> expectRawError(String requestJson, String category) {
        try {
            BoardQueryService.queryMetric(requestJson);
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual(category, payload.get('category'), String.valueOf(payload));
            return payload;
        }
        Assert.fail('Expected ' + category + ' for ' + requestJson);
        return null;
    }

    private static void assertBindingError(Map<String, Object> entry, String filterId) {
        Map<String, Object> request = metricRequest('Opportunity', 'COUNT', null);
        addFilter(request, entry);
        Map<String, Object> payload = expectError(request, 'CONFIG_ERROR');
        Assert.areEqual(filterId, payload.get('filterId'), String.valueOf(payload));
    }

    private static void assertBaseFilterError(Map<String, Object> condition, String id) {
        Map<String, Object> request = metricRequest('Opportunity', 'COUNT', null);
        addBaseFilter(request, condition);
        Map<String, Object> payload = expectError(request, 'CONFIG_ERROR');
        Assert.areEqual(id, payload.get('filterId'), String.valueOf(payload));
    }
}