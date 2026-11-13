/** Empty / Filled in filter conditions (`EMPTY` -> `field = null`, `FILLED` -> `field != null`) through `BoardQueryService`. */
@IsTest
private class BoardQueryServiceEmptyFilledTest {
    /**
     * Accounts: Parent (no parent), Child (ParentId = Parent). Opportunities: Opp 1-3 with Amount (Opp 3 on Child),
     * Opp 4 without Amount. Parent has one Case, Child none.
     */
    @TestSetup
    static void setup() {
        Account parent = new Account(Name = 'EF Parent');
        insert parent;
        Account child = new Account(Name = 'EF Child', ParentId = parent.Id);
        insert child;
        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        insert new List<Opportunity>{
            opportunity('EF Opp 1', parent.Id, 100, stage),
            opportunity('EF Opp 2', parent.Id, 200, stage),
            opportunity('EF Opp 3', child.Id, 300, stage),
            opportunity('EF Opp 4', parent.Id, null, stage)
        };
        insert new Case(Subject = 'EF Case', AccountId = parent.Id);
    }

    @IsTest
    static void emptyKeepsRowsWithoutAValueAndFilledKeepsRowsWithOne() {
        Assert.areEqual(1, count('Opportunity', filter('Amount', true, 'EMPTY')), 'Empty Amount');
        Assert.areEqual(3, count('Opportunity', filter('Amount', true, 'FILLED')), 'Filled in Amount');
    }

    @IsTest
    static void allAppliesNoCondition() {
        Map<String, Object> entry = filter('Amount', true, 'IN');
        Assert.areEqual(4, count('Opportunity', entry), 'No selection, no condition');
    }

    @IsTest
    static void bindsThroughParentPaths() {
        Assert.areEqual(3, count('Opportunity', filter('Account.ParentId', true, 'EMPTY')), 'Parent has no parent');
        Assert.areEqual(1, count('Opportunity', filter('Account.ParentId', true, 'FILLED')), 'Child has a parent');
    }

    @IsTest
    static void bindsThroughChildSemiJoinPaths() {
        Assert.areEqual(
            1,
            count('Account', filter('Case(AccountId).Subject', true, 'FILLED')),
            'Only the parent account has a Case with a subject'
        );
    }

    @IsTest
    static void longTextAreaFieldsFailClosedAsNotFilterable() {
        Map<String, Object> request = metricRequest('Opportunity');
        ((List<Object>) request.get('filters')).add(filter('Description', true, 'EMPTY'));
        try {
            BoardQueryService.queryMetric(JSON.serialize(request));
            Assert.fail('Long Text Area must not be filterable');
        } catch (AuraHandledException expected) {
            Assert.isTrue(expected.getMessage().contains('CONFIG_ERROR'), expected.getMessage());
        }
    }

    private static Integer count(String objectApiName, Map<String, Object> entry) {
        Map<String, Object> request = metricRequest(objectApiName);
        ((List<Object>) request.get('filters')).add(entry);
        return (Integer) BoardQueryService.queryMetric(JSON.serialize(request)).value;
    }

    private static Map<String, Object> filter(String fieldPath, Boolean explicit, String operator) {
        return new Map<String, Object>{
            'filterId' => 'emptyFilled',
            'type' => 'EMPTY_FILLED',
            'fieldPath' => fieldPath,
            'explicit' => explicit,
            'operator' => operator,
            'values' => new List<Object>()
        };
    }

    private static Map<String, Object> metricRequest(String objectApiName) {
        return new Map<String, Object>{
            'objectApiName' => objectApiName,
            'aggregateFunction' => 'COUNT',
            'valueFieldApiName' => null,
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'refreshToken' => 0
        };
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
}