/**
 * Entry-point seam for a Row limit on a grouped Table (`queryTable` with `groupBy` and `rowLimit`): the limit counts
 * first-level groups ("Top 10 groups") in the group order. Detail rows on: a top-N group query first, then the record
 * stream filtered to those groups. Detail rows off: the top N Group rows. Totals are computed after the limit.
 */
@IsTest
private class BoardTableRowLimitGroupedTest {
    private static final String ALPHA = 'Board TopN Alpha';
    private static final String BETA = 'Board TopN Beta';
    private static final String GAMMA = 'Board TopN Gamma';

    /**
     * Data: Opportunities on Alpha (revenue 100; amounts 10, 20, 30), Beta (revenue 900; 5), Gamma (revenue 500;
     * 100, 200), all closing this year, and two without an Account (7, 8) closing next year. 8 Opportunities, 380.
     */
    @TestSetup
    static void setup() {
        Account alphaAccount = new Account(Name = ALPHA, AnnualRevenue = 100);
        Account betaAccount = new Account(Name = BETA, AnnualRevenue = 900);
        Account gammaAccount = new Account(Name = GAMMA, AnnualRevenue = 500);
        insert new List<Account>{ alphaAccount, betaAccount, gammaAccount };

        Date thisYear = Date.newInstance(Date.today().year(), 6, 15);
        List<Opportunity> opportunities = new List<Opportunity>();
        addOpportunities(opportunities, alphaAccount.Id, new List<Decimal>{ 10, 20, 30 }, thisYear);
        addOpportunities(opportunities, betaAccount.Id, new List<Decimal>{ 5 }, thisYear);
        addOpportunities(opportunities, gammaAccount.Id, new List<Decimal>{ 100, 200 }, thisYear);
        addOpportunities(opportunities, null, new List<Decimal>{ 7, 8 }, thisYear.addYears(1));
        insert opportunities;
    }

    private static void addOpportunities(
        List<Opportunity> opportunities,
        Id accountId,
        List<Decimal> amounts,
        Date closeDate
    ) {
        for (Decimal amount : amounts) {
            opportunities.add(
                new Opportunity(
                    Name = 'Board TopN ' + amount,
                    AccountId = accountId,
                    Amount = amount,
                    StageName = 'Prospecting',
                    CloseDate = closeDate
                )
            );
        }
    }

    /** Opportunities grouped by `groupEntry`, Detail rows on, with an Amount Total row and no default sort. */
    private static Map<String, Object> detailRequest(Map<String, Object> groupEntry, Integer rowLimit) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => new List<Object>{
                new Map<String, Object>{ 'id' => 'name', 'fieldPath' => 'Name' },
                new Map<String, Object>{
                    'id' => 'amount',
                    'fieldPath' => 'Amount',
                    'summaries' => new List<Object>{ 'SUM', 'MAX' }
                }
            },
            'pageSize' => 10,
            'showTotalRow' => true,
            'rowLimit' => rowLimit,
            'groupBy' => new List<Object>{ groupEntry }
        };
    }

    /** Opportunities grouped by Account, Detail rows off, ordered by Sum of Amount descending. */
    private static Map<String, Object> aggregateRequest(Object rowLimit) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => new List<Object>{
                new Map<String, Object>{ 'id' => 'account', 'fieldPath' => 'Account.Name' },
                new Map<String, Object>{
                    'id' => 'amount',
                    'fieldPath' => 'Amount',
                    'summaries' => new List<Object>{ 'SUM', 'MAX' }
                }
            },
            'detailRows' => false,
            'showTotalRow' => true,
            'rowLimit' => rowLimit,
            'groupBy' => new List<Object>{
                new Map<String, Object>{
                    'fieldPath' => 'AccountId',
                    'sortDirection' => 'DESC',
                    'orderBySummary' => new Map<String, Object>{ 'columnId' => 'amount', 'summaryFunction' => 'SUM' }
                }
            }
        };
    }

    private static BoardQueryService.TableResult query(Map<String, Object> request) {
        return BoardQueryService.queryTable(JSON.serialize(request));
    }

    @IsTest
    static void detailRowsOnStreamsOnlyTheTopGroupsInTheGroupOrder() {
        Map<String, Object> request = detailRequest(
            new Map<String, Object>{
                'fieldPath' => 'AccountId',
                'sortDirection' => 'DESC',
                'orderBy' => 'Account.AnnualRevenue'
            },
            2
        );

        BoardQueryService.TableResult result = query(request);

        Assert.areEqual(2, result.groupLimit, 'The limit cut groups: "Top 2 groups"');
        Assert.isNull(result.rowLimit, 'A grouped Row limit counts groups, not records');
        Assert.areEqual(new List<String>{ BETA, GAMMA }, groupLabels(result), 'Top 2 by Account revenue');
        Assert.areEqual(3, result.totalCount, 'The badge counts the records of the top groups');
        Assert.areEqual(3, result.rows.size());
        Assert.isFalse(result.hasMore);
        Assert.areEqual(1, result.groups[0].count);
        Assert.areEqual(2, result.groups[1].count);
        assertTotals(result, 305, 200);
    }

    @IsTest
    static void detailRowsOnByValueKeepsTheBlankGroupLast() {
        BoardQueryService.TableResult result = query(
            detailRequest(new Map<String, Object>{ 'fieldPath' => 'AccountId' }, 3)
        );

        Assert.areEqual(3, result.groupLimit);
        Assert.areEqual(new List<String>{ ALPHA, BETA, GAMMA }, groupLabels(result), 'By name; "(Blank)" is last');
        Assert.areEqual(6, result.totalCount);
        assertTotals(result, 365, 200);
    }

    @IsTest
    static void detailRowsOnWithEveryGroupUnderTheLimitShowsAll() {
        BoardQueryService.TableResult result = query(
            detailRequest(new Map<String, Object>{ 'fieldPath' => 'AccountId' }, 4)
        );

        Assert.isNull(result.groupLimit, 'Nothing was cut');
        Assert.areEqual(8, result.totalCount);
        Assert.areEqual(4, result.groups.size());
        assertTotals(result, 380, 200);
    }

    @IsTest
    static void detailRowsOnLimitsDateBuckets() {
        BoardQueryService.TableResult result = query(
            detailRequest(
                new Map<String, Object>{ 'fieldPath' => 'CloseDate', 'dateGranularity' => 'CALENDAR_YEAR' },
                1
            )
        );

        Assert.areEqual(1, result.groupLimit);
        Assert.areEqual(1, result.groups.size());
        Assert.areEqual(String.valueOf(Date.today().year()), result.groups[0].key, 'The earliest year');
        Assert.areEqual(6, result.totalCount);
        assertTotals(result, 365, 200);
    }

    @IsTest
    static void detailRowsOffShowsTheTopGroupRowsAndTotalsThem() {
        BoardQueryService.TableResult result = query(aggregateRequest(2));

        Assert.areEqual(2, result.groupLimit);
        List<String> labels = new List<String>();
        for (BoardTableAggregate.GroupRow groupRow : result.aggregateGroups) {
            labels.add(groupRow.label);
        }
        Assert.areEqual(new List<String>{ GAMMA, ALPHA }, labels, 'Top 2 by Sum of Amount');
        Assert.areEqual(5, result.totalCount, 'The badge counts the records of the top groups');
        assertTotals(result, 360, 200);
    }

    @IsTest
    static void detailRowsOffWithEveryGroupUnderTheLimitShowsAll() {
        BoardQueryService.TableResult result = query(aggregateRequest(2000));

        Assert.isNull(result.groupLimit);
        Assert.areEqual(4, result.aggregateGroups.size());
        assertTotals(result, 380, 200);
    }

    @IsTest
    static void groupLimitsAreBoundedByDetailRows() {
        assertConfigError(detailRequest(new Map<String, Object>{ 'fieldPath' => 'AccountId' }, 201), '200');
        assertConfigError(aggregateRequest(2001), '2,000');
        assertConfigError(aggregateRequest('ten'), '2,000');
        assertConfigError(aggregateRequest(1.5), '2,000');
    }

    private static List<String> groupLabels(BoardQueryService.TableResult result) {
        List<String> labels = new List<String>();
        for (BoardTableEngine.TableGroup tableGroup : result.groups) {
            labels.add(tableGroup.label);
        }
        return labels;
    }

    private static void assertTotals(BoardQueryService.TableResult result, Decimal expectedSum, Decimal expectedMax) {
        Assert.areEqual(1, result.totals.size(), 'One Total row cell');
        BoardTableEngine.ColumnTotal total = result.totals[0];
        Assert.areEqual('amount', total.columnId);
        assertDecimal(expectedSum, total.summaries[0].value);
        assertDecimal(expectedMax, total.summaries[1].value);
    }

    private static void assertDecimal(Decimal expected, Decimal actual) {
        Assert.isTrue(actual != null && actual == expected, 'Expected ' + expected + ', got ' + actual);
    }

    private static void assertConfigError(Map<String, Object> request, String expectedFragment) {
        try {
            query(request);
            Assert.fail('Expected CONFIG_ERROR mentioning ' + expectedFragment);
        } catch (AuraHandledException expected) {
            Assert.isTrue(expected.getMessage().contains('CONFIG_ERROR'), expected.getMessage());
            Assert.isTrue(expected.getMessage().contains(expectedFragment), expected.getMessage());
        }
    }
}