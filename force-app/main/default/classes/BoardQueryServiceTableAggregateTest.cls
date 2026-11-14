/**
 * Entry-point seam for Row grouping with Detail rows off (`queryTable` with `detailRows: false`): one `GROUP BY`
 * returns every Group row at once with its record count, column summaries and fields reached through the lookup
 * group field, ordered by value, by a field constant per group or by a summary, with "(Blank)" last.
 */
@IsTest
private class BoardQueryServiceTableAggregateTest {
    private static final String ALPHA = 'Board Aggregate Alpha';
    private static final String BETA = 'Board Aggregate Beta';
    private static final String GAMMA = 'Board Aggregate Gamma';

    /**
     * Data: Opportunities on Alpha (Banking, revenue 100; amounts 10, 20, 30), Beta (Energy, revenue 900; 5),
     * Gamma (no industry, revenue 500; 100, 200) and two without an Account (7, 8). 8 Opportunities, 380 in all.
     */
    @TestSetup
    static void setup() {
        Account alphaRow = new Account(Name = ALPHA, Industry = 'Banking', AnnualRevenue = 100);
        Account betaRow = new Account(Name = BETA, Industry = 'Energy', AnnualRevenue = 900);
        Account gammaRow = new Account(Name = GAMMA, AnnualRevenue = 500);
        insert new List<Account>{ alphaRow, betaRow, gammaRow };

        List<Opportunity> opportunities = new List<Opportunity>();
        addOpportunities(opportunities, alphaRow.Id, new List<Decimal>{ 10, 20, 30 });
        addOpportunities(opportunities, betaRow.Id, new List<Decimal>{ 5 });
        addOpportunities(opportunities, gammaRow.Id, new List<Decimal>{ 100, 200 });
        addOpportunities(opportunities, null, new List<Decimal>{ 7, 8 });
        insert opportunities;
    }

    private static void addOpportunities(List<Opportunity> opportunities, Id accountId, List<Decimal> amounts) {
        for (Decimal amount : amounts) {
            opportunities.add(
                new Opportunity(
                    Name = 'Board Aggregate ' + amount,
                    AccountId = accountId,
                    Amount = amount,
                    StageName = 'Prospecting',
                    CloseDate = Date.today()
                )
            );
        }
    }

    /** Opportunities grouped by Account, Detail rows off: Account name, industry and revenue, and Amount summaries. */
    private static Map<String, Object> aggregateRequest(Map<String, Object> groupEntry) {
        Map<String, Object> entry = new Map<String, Object>{ 'fieldPath' => 'AccountId' };
        if (groupEntry != null) {
            entry.putAll(groupEntry);
        }
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => new List<Object>{
                new Map<String, Object>{ 'id' => 'account', 'fieldPath' => 'Account.Name' },
                new Map<String, Object>{ 'id' => 'industry', 'fieldPath' => 'Account.Industry' },
                new Map<String, Object>{ 'id' => 'revenue', 'fieldPath' => 'Account.AnnualRevenue' },
                new Map<String, Object>{
                    'id' => 'amount',
                    'fieldPath' => 'Amount',
                    'summaries' => new List<Object>{ 'SUM', 'MAX' }
                }
            },
            'pageSize' => 10,
            'detailRows' => false,
            'groupBy' => new List<Object>{ entry }
        };
    }

    private static BoardQueryService.TableResult query(Map<String, Object> request) {
        return BoardQueryService.queryTable(JSON.serialize(request));
    }

    @IsTest
    static void oneAggregateReturnsEveryGroupRowWithSummariesAndFieldsThroughTheLookup() {
        BoardQueryService.TableResult result = query(aggregateRequest(null));

        Assert.areEqual(0, result.rows.size(), 'Detail rows off: no records');
        Assert.isFalse(result.hasMore, 'All Group rows at once, no infinite scroll');
        Assert.isNull(result.paginationCursor);
        Assert.areEqual(8, result.totalCount, 'The badge counts records');
        Assert.areEqual('AccountId', result.groupField.fieldPath);
        Assert.areEqual(4, result.aggregateGroups.size());
        Assert.areEqual(new List<String>{ ALPHA, BETA, GAMMA, null }, labels(result), 'By name, "(Blank)" last');

        BoardTableAggregate.GroupRow alphaRow = result.aggregateGroups[0];
        Id alphaId = [SELECT Id FROM Account WHERE Name = :ALPHA].Id;
        Assert.areEqual(String.valueOf(alphaId), alphaRow.key);
        Assert.areEqual(alphaRow.key, alphaRow.recordId, 'Lookup groups link to their record');
        Assert.areEqual(3, alphaRow.count);
        Assert.areEqual('Banking', alphaRow.values.get('Account.Industry'), 'Picklist reached through the lookup');
        assertDecimal(100, alphaRow.values.get('Account.AnnualRevenue'));
        Assert.areEqual(ALPHA, alphaRow.values.get('Account.Name'));
        assertSummaries(alphaRow, 'amount', 60, 30);

        BoardTableAggregate.GroupRow gammaRow = result.aggregateGroups[2];
        Assert.isNull(gammaRow.values.get('Account.Industry'));
        assertSummaries(gammaRow, 'amount', 300, 200);

        BoardTableAggregate.GroupRow blank = result.aggregateGroups[3];
        Assert.isNull(blank.key);
        Assert.isNull(blank.recordId);
        Assert.areEqual(2, blank.count);
        assertSummaries(blank, 'amount', 15, 8);
    }

    @IsTest
    static void groupsOrderBySummaryWithBlanksLast() {
        Map<String, Object> request = aggregateRequest(
            new Map<String, Object>{
                'sortDirection' => 'DESC',
                'orderBySummary' => new Map<String, Object>{ 'columnId' => 'amount', 'summaryFunction' => 'SUM' }
            }
        );

        BoardQueryService.TableResult result = query(request);

        Assert.areEqual(new List<String>{ GAMMA, ALPHA, BETA, null }, labels(result), 'Sum of Amount desc');
        Assert.areEqual('Amount', result.sortBy, 'The ordering column shows as sorted');
        Assert.areEqual('DESC', result.sortDirection);
    }

    @IsTest
    static void groupsOrderByAFieldConstantPerGroup() {
        Map<String, Object> request = aggregateRequest(
            new Map<String, Object>{ 'sortDirection' => 'DESC', 'orderBy' => 'Account.AnnualRevenue' }
        );

        BoardQueryService.TableResult result = query(request);

        Assert.areEqual(new List<String>{ BETA, GAMMA, ALPHA, null }, labels(result), 'Account revenue desc');
        Assert.areEqual('Account.AnnualRevenue', result.sortBy);
    }

    @IsTest
    static void totalRowIsTheGrandTotal() {
        Map<String, Object> request = aggregateRequest(null);
        request.put('showTotalRow', true);

        BoardQueryService.TableResult result = query(request);

        Assert.areEqual(1, result.totals.size());
        Assert.areEqual('amount', result.totals[0].columnId);
        assertDecimal(380, result.totals[0].summaries[0].value);
        assertDecimal(200, result.totals[0].summaries[1].value);
    }

    @IsTest
    static void totalRowComesFromTheGroupRowsWithoutReadingTheScopeAgain() {
        Map<String, Object> request = aggregateRequest(null);
        Map<String, Object> amount = (Map<String, Object>) ((List<Object>) request.get('columns'))[3];
        amount.put('summaries', new List<Object>{ 'AVG', 'MIN' });
        // Warm-up: transaction-cached reads (e.g. currency setup) cost rows on the first call only.
        query(request);
        Integer before = Limits.getQueryRows();
        query(request);
        Integer withoutTotals = Limits.getQueryRows() - before;
        request.put('showTotalRow', true);

        before = Limits.getQueryRows();
        BoardQueryService.TableResult result = query(request);
        Integer withTotals = Limits.getQueryRows() - before;

        assertDecimal(47.5, result.totals[0].summaries[0].value);
        assertDecimal(5, result.totals[0].summaries[1].value);
        // A second read of the scope would add its 8 records; merging the Group rows adds none.
        Assert.isTrue(
            withTotals <= withoutTotals,
            'The grand total merges the Group rows, no second scope read: ' + withTotals + ' vs ' + withoutTotals
        );
    }

    @IsTest
    static void columnsWithoutOneMeaningPerGroupAreConfigErrors() {
        Map<String, Object> request = aggregateRequest(null);
        ((List<Object>) request.get('columns')).add(new Map<String, Object>{ 'id' => 'name', 'fieldPath' => 'Name' });
        assertError(request, 'CONFIG_ERROR', 'Name');

        Map<String, Object> noSummaries = aggregateRequest(null);
        ((List<Object>) noSummaries.get('columns'))
            .add(new Map<String, Object>{ 'id' => 'probability', 'fieldPath' => 'Probability' });
        assertError(noSummaries, 'CONFIG_ERROR', 'Probability');

        Map<String, Object> notConstant = aggregateRequest(new Map<String, Object>{ 'orderBy' => 'CloseDate' });
        assertError(notConstant, 'CONFIG_ERROR', 'CloseDate');

        Map<String, Object> unknownSummary = aggregateRequest(
            new Map<String, Object>{
                'orderBySummary' => new Map<String, Object>{ 'columnId' => 'amount', 'summaryFunction' => 'AVG' }
            }
        );
        assertError(unknownSummary, 'CONFIG_ERROR', 'AVG');
    }

    @IsTest
    static void picklistGroupsAreLabelledByThePicklistLabel() {
        Map<String, Object> request = aggregateRequest(null);
        request.put('groupBy', new List<Object>{ new Map<String, Object>{ 'fieldPath' => 'StageName' } });
        request.put(
            'columns',
            new List<Object>{
                new Map<String, Object>{ 'id' => 'stage', 'fieldPath' => 'StageName' },
                new Map<String, Object>{
                    'id' => 'amount',
                    'fieldPath' => 'Amount',
                    'summaries' => new List<Object>{ 'SUM' }
                }
            }
        );

        BoardQueryService.TableResult result = query(request);

        String label;
        for (Schema.PicklistEntry entry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (entry.getValue() == 'Prospecting') {
                label = entry.getLabel();
            }
        }
        Assert.areEqual(1, result.aggregateGroups.size());
        BoardTableAggregate.GroupRow prospecting = result.aggregateGroups[0];
        Assert.areEqual('Prospecting', prospecting.key);
        Assert.areEqual(label, prospecting.label);
        Assert.isNull(prospecting.recordId, 'Only lookup groups link');
        Assert.areEqual(8, prospecting.count);
        assertDecimal(380, prospecting.summaries[0].summaries[0].value);
    }

    @IsTest
    static void columnsTheAggregateCannotShowAreConfigErrors() {
        Map<String, Object> longText = aggregateRequest(null);
        ((List<Object>) longText.get('columns'))
            .add(new Map<String, Object>{ 'id' => 'description', 'fieldPath' => 'Account.Description' });
        assertError(longText, 'CONFIG_ERROR', 'Account.Description');
    }

    @IsTest
    static void summaryOrderNeedsDetailRowsOff() {
        Map<String, Object> request = aggregateRequest(
            new Map<String, Object>{
                'orderBySummary' => new Map<String, Object>{ 'columnId' => 'amount', 'summaryFunction' => 'SUM' }
            }
        );
        request.remove('detailRows');
        assertError(request, 'CONFIG_ERROR', 'Detail rows off');
    }

    private static List<String> labels(BoardQueryService.TableResult result) {
        List<String> labels = new List<String>();
        for (BoardTableAggregate.GroupRow groupRow : result.aggregateGroups) {
            labels.add(groupRow.label);
        }
        return labels;
    }

    private static void assertSummaries(
        BoardTableAggregate.GroupRow groupRow,
        String columnId,
        Decimal expectedSum,
        Decimal expectedMax
    ) {
        Assert.areEqual(1, groupRow.summaries.size());
        BoardTableEngine.ColumnTotal column = groupRow.summaries[0];
        Assert.areEqual(columnId, column.columnId);
        Assert.areEqual('SUM', column.summaries[0].summaryFunction);
        assertDecimal(expectedSum, column.summaries[0].value);
        Assert.areEqual('MAX', column.summaries[1].summaryFunction);
        assertDecimal(expectedMax, column.summaries[1].value);
    }

    private static void assertDecimal(Decimal expected, Object actual) {
        Decimal value = BoardQueryService.toDecimal(actual);
        Assert.isTrue(value != null && value == expected, 'Expected ' + expected + ', got ' + actual);
    }

    private static void assertError(Map<String, Object> request, String category, String expectedFragment) {
        try {
            query(request);
            Assert.fail('Expected ' + category + ' for ' + expectedFragment);
        } catch (AuraHandledException expected) {
            Assert.isTrue(expected.getMessage().contains(category), expected.getMessage());
            Assert.isTrue(expected.getMessage().contains(expectedFragment), expected.getMessage());
        }
    }
}