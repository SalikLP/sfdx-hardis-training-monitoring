/**
 * Entry-point seam for Data bars on grouped Tables: with Detail rows on the scale spans the matching records; with
 * Detail rows off it spans the Group rows (a column's first summary, or its value through the lookup group field),
 * in the SOQL tier and the cursor tier alike.
 */
@IsTest
private class BoardQueryServiceTableGroupBarsTest {
    /**
     * Data: Opportunities on Alpha (revenue 100; amounts 10, 20, 30), Beta (revenue 900; 5), Gamma (revenue 500;
     * 100, 200) and two without an Account (7, 8). Group sums: Alpha 60, Beta 5, Gamma 300, "(Blank)" 15.
     */
    @TestSetup
    static void setup() {
        Account alphaRow = new Account(Name = 'Board Group Bars Alpha', AnnualRevenue = 100);
        Account betaRow = new Account(Name = 'Board Group Bars Beta', AnnualRevenue = 900);
        Account gammaRow = new Account(Name = 'Board Group Bars Gamma', AnnualRevenue = 500);
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
                    Name = 'Board Group Bars ' + amount,
                    AccountId = accountId,
                    Amount = amount,
                    StageName = 'Prospecting',
                    CloseDate = Date.today()
                )
            );
        }
    }

    /** Opportunities grouped by Account: Account name, revenue and Amount (Sum, Max), both numbers as Data bars. */
    private static Map<String, Object> groupedRequest(Boolean detailRows) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => new List<Object>{
                new Map<String, Object>{ 'id' => 'account', 'fieldPath' => 'Account.Name' },
                new Map<String, Object>{
                    'id' => 'revenue',
                    'fieldPath' => 'Account.AnnualRevenue',
                    'displayAs' => 'dataBar'
                },
                new Map<String, Object>{
                    'id' => 'amount',
                    'fieldPath' => 'Amount',
                    'displayAs' => 'dataBar',
                    'summaries' => new List<Object>{ 'SUM', 'MAX' }
                }
            },
            'pageSize' => 10,
            'detailRows' => detailRows,
            'groupBy' => new List<Object>{ new Map<String, Object>{ 'fieldPath' => 'AccountId' } }
        };
    }

    private static BoardQueryService.TableResult query(Map<String, Object> request) {
        return BoardQueryService.queryTable(JSON.serialize(request));
    }

    /** `queryTable`, then `fetchTableAggregateChunk` until a cursor-tier load completes. */
    private static BoardQueryService.TableResult loadAll(Map<String, Object> request) {
        BoardQueryService.TableResult result = query(request);
        Integer chunkCalls = 0;
        while (result.aggregateCursor != null && !result.aggregateCursor.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.aggregateCursor.cursor);
            next.put('offset', result.aggregateCursor.nextOffset);
            next.put('partialState', result.aggregateCursor.partialState);
            result = BoardQueryService.fetchTableAggregateChunk(JSON.serialize(next));
            Assert.isTrue(++chunkCalls < 10, 'The cursor load must finish');
        }
        return result;
    }

    private static BoardQueryService.BarScale scaleOf(BoardQueryService.TableResult result, String columnId) {
        for (BoardQueryService.BarScale scale : result.barScales) {
            if (scale.columnId == columnId) {
                return scale;
            }
        }
        Assert.fail('No Data bar scale for ' + columnId);
        return null;
    }

    private static void assertScale(BoardQueryService.BarScale scale, Decimal max, Decimal min, String message) {
        Assert.areEqual(max, scale.max, message + ' (max)');
        Assert.areEqual(min, scale.min, message + ' (min)');
    }

    @IsTest
    static void detailRowsOnScaleBarsOverTheMatchingRecords() {
        BoardQueryService.TableResult result = query(groupedRequest(true));

        Assert.isNull(result.aggregateGroups, 'Detail rows on: records under Group rows');
        assertScale(scaleOf(result, 'amount'), 200, 5, 'Largest and smallest Opportunity amount');
        assertScale(scaleOf(result, 'revenue'), 900, 100, 'Revenue over the records');
    }

    @IsTest
    static void detailRowsOffScaleBarsOverTheGroupsFirstSummary() {
        BoardQueryService.TableResult result = query(groupedRequest(false));

        Assert.areEqual(4, result.aggregateGroups.size());
        assertScale(scaleOf(result, 'amount'), 300, 5, 'Largest and smallest group Sum, not a record amount');
    }

    @IsTest
    static void detailRowsOffScaleAColumnWithoutSummariesOverItsGroupValues() {
        BoardQueryService.TableResult result = query(groupedRequest(false));

        assertScale(scaleOf(result, 'revenue'), 900, 100, 'Revenue through the group lookup; "(Blank)" has none');
    }

    @IsTest
    static void theCursorTierScalesBarsOverTheSameGroups() {
        BoardTableAggregate.MAX_GROUPS = 2;

        BoardQueryService.TableResult result = loadAll(groupedRequest(false));

        Assert.isNotNull(result.aggregateCursor, 'More groups than the SOQL tier holds: cursor tier');
        Assert.areEqual(4, result.aggregateGroups.size());
        assertScale(scaleOf(result, 'amount'), 300, 5, 'Group Sum in the cursor tier');
        assertScale(scaleOf(result, 'revenue'), 900, 100, 'Group value in the cursor tier');
    }

    @IsTest
    static void groupsWithoutValuesHaveAnEmptyScale() {
        Map<String, Object> request = groupedRequest(false);
        request.put(
            'baseFilters',
            new List<Object>{
                new Map<String, Object>{
                    'id' => 'none',
                    'fieldPath' => 'Name',
                    'operator' => 'LIKE',
                    'value' => 'No Opportunity is named like this%'
                }
            }
        );

        BoardQueryService.TableResult result = query(request);

        Assert.areEqual(0, result.aggregateGroups.size());
        assertScale(scaleOf(result, 'amount'), null, null, 'No groups, no scale');
    }
}