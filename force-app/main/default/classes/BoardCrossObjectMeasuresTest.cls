/**
 * Cross-object measures through the Chart and Metric query entry points. The library ships no custom objects, so the
 * standard Contract object stands in for a custom target object: pipeline (Opportunity Amount) per Account next to a
 * target per Account (Contract term).
 */
@IsTest
private class BoardCrossObjectMeasuresTest {
    private static final String RESTRICTED_ALIAS = 'brdxobj';
    private static final String RESTRICTED_LAST_NAME = 'Boardcross Restricted';
    private static final String TARGETS = 'Contract';

    /**
     * Accounts (owned by the restricted user): Alpha (Banking), Beta (Energy), Gamma (Retail).
     * Opportunities (closing today): Alpha 100 and 200, Beta 300; none on Gamma.
     * Contracts (targets): Alpha term 12 and Beta term 6 (starting today), Gamma term 24 (started 30 days ago).
     * Restricted user: `Minimum Access - Salesforce` + Read on Account (FLS: Industry); no access to Contract.
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
                    '@board-cross.test',
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            );
            insert restrictedUser;
            PermissionSet permissionSet = new PermissionSet(Name = 'BoardCrossTestAccess', Label = 'Board Cross Test');
            insert permissionSet;
            insert new ObjectPermissions(ParentId = permissionSet.Id, SobjectType = 'Account', PermissionsRead = true);
            insert new FieldPermissions(
                ParentId = permissionSet.Id,
                SobjectType = 'Account',
                Field = 'Account.Industry',
                PermissionsRead = true
            );
            insert new PermissionSetAssignment(AssigneeId = restrictedUser.Id, PermissionSetId = permissionSet.Id);
        }

        Account alpha = new Account(Name = 'Cross Alpha', Industry = 'Banking', OwnerId = restrictedUser.Id);
        Account beta = new Account(Name = 'Cross Beta', Industry = 'Energy', OwnerId = restrictedUser.Id);
        Account gamma = new Account(Name = 'Cross Gamma', Industry = 'Retail', OwnerId = restrictedUser.Id);
        insert new List<Account>{ alpha, beta, gamma };
        String stage = firstStage();
        insert new List<Opportunity>{
            opportunity('Cross Opp 1', alpha.Id, 100, stage),
            opportunity('Cross Opp 2', alpha.Id, 200, stage),
            opportunity('Cross Opp 3', beta.Id, 300, stage)
        };
        insert new List<Contract>{
            target(alpha.Id, 12, Date.today()),
            target(beta.Id, 6, Date.today()),
            target(gamma.Id, 24, Date.today().addDays(-30))
        };
    }

    // ---------------------------------------------------------------------------------------------------------
    // Chart widget
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void fullOuterJoinKeepsACategoryWithATargetButNoPipeline() {
        BoardChartQuery.ChartResult result = query(
            chartRequest(new List<Object>{ measure('SUM', 'Amount'), crossMeasure('SUM', 'ContractTerm') })
        );

        Assert.areEqual(new List<String>{ 'SUM', 'SUM' }, result.aggregateFunctions);
        Assert.areEqual(3, result.categories.size(), 'Gamma has a target but no pipeline: it still shows');
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(300, values.get('Cross Alpha|0'));
        Assert.areEqual(12, values.get('Cross Alpha|1'));
        Assert.areEqual(300, values.get('Cross Beta|0'));
        Assert.areEqual(6, values.get('Cross Beta|1'));
        Assert.isNull(values.get('Cross Gamma|0'), 'No pipeline on Gamma');
        Assert.areEqual(24, values.get('Cross Gamma|1'));
        Assert.areEqual(1, result.crossObjectNotices.size());
        BoardCrossObjectMeasures.Notice notice = result.crossObjectNotices[0];
        Assert.areEqual(1, notice.measureIndex);
        Assert.areEqual(TARGETS, notice.sourceObject);
        Assert.isFalse(notice.isBlank);
    }

    @IsTest
    static void ownFilterBindingsApplyAndUnboundFiltersAreListed() {
        Map<String, Object> request = chartRequest(
            new List<Object>{ measure('SUM', 'Amount'), crossMeasure('SUM', 'ContractTerm') }
        );
        ((Map<String, Object>) ((List<Object>) request.get('measures'))[1])
            .put('filterBindings', new Map<String, Object>{ 'closeDate' => 'StartDate' });
        Map<String, Object> owner = filter('owner', 'USER', 'OwnerId', null, 'IN');
        owner.put('values', new List<Object>{ UserInfo.getUserId() });
        Map<String, Object> stage = filter('stage', 'PICKLIST', 'StageName', 'StageName', 'IN');
        stage.put('values', new List<Object>{ firstStage() });
        Map<String, Object> closeDate = filter('closeDate', 'DATE_RANGE', 'CloseDate', 'CloseDate', 'BETWEEN');
        closeDate.put('from', String.valueOf(Date.today().addDays(-1)));
        closeDate.put('to', String.valueOf(Date.today()));
        request.put('filters', new List<Object>{ closeDate, owner, stage });

        BoardChartQuery.ChartResult result = query(request);

        BoardCrossObjectMeasures.Notice notice = result.crossObjectNotices[0];
        Assert.areEqual(
            new Set<String>{ 'closeDate', 'owner' },
            new Set<String>(notice.appliedFilterIds),
            'Close date through its own binding (StartDate), owner by convention (OwnerId)'
        );
        Assert.areEqual(new List<String>{ 'stage' }, notice.ignoredFilterIds, 'Contract has no StageName');
        Assert.isTrue(new Set<String>(result.appliedFilterIds).contains('stage'), 'The Widget itself applies it');
        Assert.areEqual(2, result.categories.size(), 'Gamma\'s target started 30 days ago: outside the close dates');
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(12, values.get('Cross Alpha|1'));
        Assert.areEqual(6, values.get('Cross Beta|1'));
    }

    @IsTest
    static void ignoreBindingLeavesAFilterOffTheCrossObjectMeasure() {
        Map<String, Object> request = chartRequest(new List<Object>{ crossMeasure('COUNT', null) });
        ((Map<String, Object>) ((List<Object>) request.get('measures'))[0])
            .put('filterBindings', new Map<String, Object>{ 'owner' => 'IGNORE' });
        Map<String, Object> owner = filter('owner', 'USER', 'OwnerId', null, 'IN');
        owner.put('values', new List<Object>{ UserInfo.getUserId() });
        request.put('filters', new List<Object>{ owner });

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual(new List<String>{ 'owner' }, result.crossObjectNotices[0].ignoredFilterIds);
        Assert.areEqual(new List<String>{ 'COUNT' }, result.aggregateFunctions, 'Only the Cross-object measure');
        Assert.areEqual(3, result.categories.size(), 'Every target, plus the Widget\'s own categories');
    }

    @IsTest
    static void crossObjectMeasureWithAMeasureCondition() {
        BoardChartQuery.ChartResult result = query(
            chartRequest(new List<Object>{ measure('SUM', 'Amount'), termAtLeast12(crossMeasure('COUNT', null)) })
        );
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(1, values.get('Cross Alpha|1'), 'Measure condition: term >= 12');
        Assert.areEqual(0, values.get('Cross Beta|1'));
        Assert.areEqual(1, values.get('Cross Gamma|1'));
    }

    @IsTest
    static void crossObjectMeasureWithADecimalMeasureCondition() {
        Map<String, Object> conditioned = termAtLeast12(crossMeasure('COUNT', null));
        Map<String, Object> rule = (Map<String, Object>) ((List<Object>) ((Map<String, Object>) conditioned.get(
                'condition'
            ))
            .get('conditions'))[0];
        rule.put('value', 11.5);
        Map<String, Decimal> values = valuesByLabel(
            query(chartRequest(new List<Object>{ measure('SUM', 'Amount'), conditioned }))
        );
        Assert.areEqual(1, values.get('Cross Alpha|1'), 'On an Integer field, term >= 11.5 runs as term >= 12');
        Assert.areEqual(0, values.get('Cross Beta|1'));
        Assert.areEqual(1, values.get('Cross Gamma|1'));
    }

    @IsTest
    static void crossObjectMeasureAsAFormulaInput() {
        Map<String, Decimal> values = valuesByLabel(
            query(
                chartRequest(
                    new List<Object>{
                        measure('SUM', 'Amount'),
                        crossMeasure('SUM', 'ContractTerm'),
                        new Map<String, Object>{ 'aggregateFunction' => 'FORMULA', 'formula' => 'A - B' }
                    }
                )
            )
        );
        Assert.areEqual(288, values.get('Cross Alpha|2'), 'Formula: 300 - 12');
        Assert.areEqual(294, values.get('Cross Beta|2'));
        Assert.isNull(values.get('Cross Gamma|2'), 'No pipeline on Gamma: blank input, blank result');
    }

    @IsTest
    static void crossObjectMeasureAsAReferenceLine() {
        Map<String, Object> referenceLine = crossMeasure('SUM', 'ContractTerm');
        referenceLine.put('render', 'referenceLine');
        BoardChartQuery.ChartResult result = query(
            chartRequest(new List<Object>{ measure('SUM', 'Amount'), referenceLine })
        );
        Assert.isNull(result.overallValues[0]);
        Assert.areEqual(42, result.overallValues[1], 'Reference line: every target');
    }

    @IsTest
    static void crossObjectMeasureAsAShareOfTotal() {
        Map<String, Object> share = crossMeasure('SUM', 'ContractTerm');
        share.put('showAs', 'percentOfTotal');
        BoardChartQuery.ChartResult result = query(chartRequest(new List<Object>{ measure('SUM', 'Amount'), share }));
        Assert.areEqual(0.2857, valuesByLabel(result).get('Cross Alpha|1').setScale(4), 'Share of total: 12 / 42');
        Assert.isNull(result.currencyIsoCodes[1], 'A Share of total is never an amount');
    }

    @IsTest
    static void worksWithMeasureConditionFormulaReferenceLineAndShareOfTotal() {
        Map<String, Object> conditioned = termAtLeast12(crossMeasure('COUNT', null));
        Map<String, Object> share = crossMeasure('SUM', 'ContractTerm');
        share.put('showAs', 'percentOfTotal');
        Map<String, Object> referenceLine = crossMeasure('SUM', 'ContractTerm');
        referenceLine.put('render', 'referenceLine');
        Map<String, Object> gap = new Map<String, Object>{ 'aggregateFunction' => 'FORMULA', 'formula' => 'A - B' };
        BoardChartQuery.ChartResult result = query(
            chartRequest(
                new List<Object>{
                    measure('SUM', 'Amount'),
                    crossMeasure('SUM', 'ContractTerm'),
                    conditioned,
                    share,
                    referenceLine,
                    gap
                }
            )
        );

        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(1, values.get('Cross Alpha|2'), 'Measure condition: term >= 12');
        Assert.areEqual(0, values.get('Cross Beta|2'));
        Assert.areEqual(1, values.get('Cross Gamma|2'));
        Assert.areEqual(0.2857, values.get('Cross Alpha|3').setScale(4), 'Share of total: 12 / 42');
        Assert.areEqual(42, result.overallValues[4], 'Reference line: every target');
        Assert.areEqual(288, values.get('Cross Alpha|5'), 'Formula: 300 - 12');
        Assert.areEqual(294, values.get('Cross Beta|5'));
        Assert.isNull(values.get('Cross Gamma|5'), 'No pipeline on Gamma: blank input, blank result');
        Assert.isNull(result.currencyIsoCodes[3], 'A Share of total is never an amount');
        Assert.areEqual(4, result.crossObjectNotices.size(), 'One Notice per Cross-object measure');
        Assert.areEqual(4, result.crossObjectNotices[3].measureIndex, 'Indexes in the Widget\'s Measures list');
    }

    @IsTest
    static void smallMultiplesJoinOnPanelAndCategory() {
        Map<String, Object> target = crossMeasure('SUM', 'ContractTerm');
        target.put('panelMapping', 'Account.Industry');
        Map<String, Object> request = chartRequest(new List<Object>{ measure('SUM', 'Amount'), target });
        request.put('panelField', 'Account.Industry');

        BoardChartQuery.ChartResult result = query(request);

        Map<String, String> panelLabels = new Map<String, String>();
        for (BoardChartEngine.ChartKey panel : result.panels) {
            panelLabels.put(panel.key, panel.label);
        }
        Assert.isTrue(new Set<String>(panelLabels.values()).contains('Retail'), 'Gamma\'s panel has only a target');
        Map<String, String> categoryLabels = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            categoryLabels.put(category.key, category.label);
        }
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(
                panelLabels.get(point.panelKey) +
                    '|' +
                    categoryLabels.get(point.categoryKey) +
                    '|' +
                    point.measureIndex,
                point.value
            );
        }
        Assert.areEqual(12, values.get('Banking|Cross Alpha|1'));
        Assert.areEqual(300, values.get('Energy|Cross Beta|0'));
        Assert.areEqual(24, values.get('Retail|Cross Gamma|1'));

        target.put('hidden', true);
        request.put('panelHeadlineMeasure', 1);
        Map<String, Decimal> headlines = new Map<String, Decimal>();
        for (BoardChartPanelTotals.PanelTotal total : query(request).panelTotals) {
            headlines.put(panelLabels.get(total.panelKey), total.values[1]);
        }
        Assert.areEqual(24, headlines.get('Retail'), 'Panel headline from the Cross-object measure');
        Assert.areEqual(12, headlines.get('Banking'));

        target.remove('panelMapping');
        Assert.isTrue(messageOf(request).contains('Panel field'));
    }

    @IsTest
    static void measuresOfOneSourceRunAsOneQuery() {
        // Warm-up: per-transaction lookups (e.g. currency rates) are cached after the first call.
        query(chartRequest(new List<Object>{ crossMeasure('SUM', 'ContractTerm') }));
        Integer before = Limits.getQueries();
        query(chartRequest(new List<Object>{ measure('SUM', 'Amount'), crossMeasure('SUM', 'ContractTerm') }));
        Integer oneMeasure = Limits.getQueries() - before;

        before = Limits.getQueries();
        query(
            chartRequest(
                new List<Object>{
                    measure('SUM', 'Amount'),
                    crossMeasure('SUM', 'ContractTerm'),
                    crossMeasure('MAX', 'ContractTerm')
                }
            )
        );
        Assert.areEqual(oneMeasure, Limits.getQueries() - before, 'Same source and condition: one query');
    }

    @IsTest
    static void blockedCombinationsAreReadableConfigErrors() {
        Map<String, Object> series = chartRequest(new List<Object>{ crossMeasure('SUM', 'ContractTerm') });
        series.put('stackByField', 'StageName');
        Assert.isTrue(messageOf(series).contains('series field'));

        Map<String, Object> bucket = chartRequest(new List<Object>{ crossMeasure('SUM', 'ContractTerm') });
        bucket.put('groupByField', 'bucket:dealSize');
        Assert.isTrue(messageOf(bucket).contains('Bucket field'));

        Map<String, Object> panels = chartRequest(new List<Object>{ crossMeasure('SUM', 'ContractTerm') });
        panels.put('panelField', 'Type');
        Assert.isTrue(messageOf(panels).contains('Panel field'));

        Map<String, Object> averagePerRecord = chartRequest(
            new List<Object>{ crossMeasure('AVG_PER', 'ContractTerm') }
        );
        Assert.isTrue(messageOf(averagePerRecord).contains('Average per record'));

        Map<String, Object> unmapped = crossMeasure('SUM', 'ContractTerm');
        unmapped.remove('categoryMapping');
        Assert.isTrue(messageOf(chartRequest(new List<Object>{ unmapped })).contains('map a field on Contract'));
    }

    @IsTest
    static void inaccessibleSourceIsBlankWithANoticeAndTheRestRenders() {
        Map<String, Object> request = new Map<String, Object>{
            'objectApiName' => 'Account',
            'groupByField' => 'Industry',
            'measures' => new List<Object>{
                new Map<String, Object>{ 'aggregateFunction' => 'COUNT' },
                crossMeasure('SUM', 'ContractTerm', 'Account.Industry'),
                new Map<String, Object>{ 'aggregateFunction' => 'FORMULA', 'formula' => 'IF(ISBLANK(B), 5, B)' }
            }
        };
        BoardChartQuery.ChartResult result;
        System.runAs(restrictedUser()) {
            result = query(request);
        }

        Assert.areEqual(3, result.categories.size(), 'The Account count still renders');
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(1, values.get('Banking|0'));
        Assert.isNull(values.get('Banking|1'), 'No access to Contract: blank');
        Assert.isNull(values.get('Banking|2'), 'A Formula measure using it is blank too');
        BoardCrossObjectMeasures.Notice notice = result.crossObjectNotices[0];
        Assert.isTrue(notice.isBlank);
        Assert.isTrue(notice.message.contains(TARGETS), notice.message);
    }

    // ---------------------------------------------------------------------------------------------------------
    // Metric widget
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void metricFormulaComparesPipelineWithTargets() {
        Map<String, Object> pipeline = measure('SUM', 'Amount');
        pipeline.put('hidden', true);
        Map<String, Object> targets = crossMeasure('SUM', 'ContractTerm');
        targets.put('hidden', true);
        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(
            JSON.serialize(
                new Map<String, Object>{
                    'objectApiName' => 'Opportunity',
                    'measures' => new List<Object>{
                        pipeline,
                        targets,
                        new Map<String, Object>{ 'aggregateFunction' => 'FORMULA', 'formula' => 'A - B' }
                    }
                }
            )
        );

        Assert.areEqual(558, toDecimal(result.value), '600 pipeline - 42 targets');
        Assert.areEqual(42, toDecimal(result.measures[1].value));
        Assert.areEqual(1, result.crossObjectNotices.size());
        Assert.areEqual(1, result.crossObjectNotices[0].measureIndex);
    }

    @IsTest
    static void metricWithAnInaccessibleSourceBlanksItsFormula() {
        Map<String, Object> accounts = new Map<String, Object>{ 'aggregateFunction' => 'COUNT', 'hidden' => true };
        Map<String, Object> targets = crossMeasure('SUM', 'ContractTerm');
        targets.put('hidden', true);
        BoardQueryService.MetricResult result;
        System.runAs(restrictedUser()) {
            result = BoardQueryService.queryMetric(
                JSON.serialize(
                    new Map<String, Object>{
                        'objectApiName' => 'Account',
                        'measures' => new List<Object>{
                            accounts,
                            targets,
                            new Map<String, Object>{
                                'aggregateFunction' => 'FORMULA',
                                'formula' => 'IF(ISBLANK(B), 5, A)'
                            }
                        }
                    }
                )
            );
        }

        Assert.areEqual(3, toDecimal(result.measures[0].value), 'The Account count still renders');
        Assert.isNull(result.measures[1].value);
        Assert.isNull(result.value, 'The visible Formula measure uses the blank Measure');
        Assert.isTrue(result.crossObjectNotices[0].isBlank);
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    private static Map<String, Object> chartRequest(List<Object> measures) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => 'AccountId',
            'measures' => measures
        };
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        return new Map<String, Object>{ 'aggregateFunction' => aggregateFunction, 'valueFieldApiName' => valueField };
    }

    private static Map<String, Object> crossMeasure(String aggregateFunction, String valueField) {
        return crossMeasure(aggregateFunction, valueField, 'AccountId');
    }

    private static Map<String, Object> crossMeasure(String aggregateFunction, String valueField, String mapping) {
        Map<String, Object> cross = measure(aggregateFunction, valueField);
        cross.put('sourceObject', TARGETS);
        cross.put('categoryMapping', mapping);
        return cross;
    }

    /** `measure` with the Measure condition ContractTerm >= 12. */
    private static Map<String, Object> termAtLeast12(Map<String, Object> measure) {
        measure.put(
            'condition',
            new Map<String, Object>{
                'logic' => 'AND',
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'mc1',
                        'fieldPath' => 'ContractTerm',
                        'operator' => 'GTE',
                        'value' => 12
                    }
                }
            }
        );
        return measure;
    }

    private static Map<String, Object> filter(
        String filterId,
        String type,
        String fieldPath,
        String fieldApiName,
        String operator
    ) {
        return new Map<String, Object>{
            'filterId' => filterId,
            'type' => type,
            'fieldPath' => fieldPath,
            'fieldApiName' => fieldApiName,
            'explicit' => false,
            'operator' => operator,
            'values' => new List<Object>()
        };
    }

    /** The Chart query; an unexpected failure (generic `QUERY_ERROR`) fails the test with its real cause. */
    private static BoardChartQuery.ChartResult query(Map<String, Object> request) {
        try {
            return BoardChartQuery.queryChart(JSON.serialize(request));
        } catch (AuraHandledException error) {
            failOnUnexpected(error);
            throw error;
        }
    }

    private static void failOnUnexpected(AuraHandledException error) {
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
        if (payload.get('category') == BoardErrors.QUERY_ERROR && BoardErrors.lastUnexpected != null) {
            Assert.fail(
                'Unexpected ' +
                    String.valueOf(BoardErrors.lastUnexpected) +
                    '\n' +
                    BoardErrors.lastUnexpected.getStackTraceString()
            );
        }
    }

    private static String messageOf(Map<String, Object> request) {
        try {
            query(request);
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), String.valueOf(payload));
            return String.valueOf(payload.get('message'));
        }
        Assert.fail('Expected a CONFIG_ERROR for ' + JSON.serialize(request));
        return null;
    }

    /** Point values keyed `categoryLabel|measureIndex`. */
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

    private static Decimal toDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }

    private static String firstStage() {
        return Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
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

    private static Contract target(Id accountId, Integer term, Date startDate) {
        return new Contract(AccountId = accountId, Status = 'Draft', StartDate = startDate, ContractTerm = term);
    }

    private static User restrictedUser() {
        return [SELECT Id FROM User WHERE Alias = :RESTRICTED_ALIAS AND LastName = :RESTRICTED_LAST_NAME LIMIT 1];
    }
}