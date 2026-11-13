/**
 * Entry-point seam for Group summaries with Detail rows on (`queryTable` + `fetchGroupedTablePage`): every Group row
 * carries its whole group's Stacked summaries even when the group spans pages, and the Total row stays the grand total
 * of the grouped Table.
 */
@IsTest
private class BoardQueryServiceTableGroupSummariesTest {
    private static final String ALPHA = 'Board Summary Alpha';
    private static final String BIG = 'Board Summary Big';

    /**
     * Opportunities: Alpha 100, 200, 300; Big 100, 200, ... 1,200 (12); without an Account 50 and one with no Amount.
     * With 10 rows per page, Big's 12 Opportunities span both pages.
     */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = ALPHA);
        Account big = new Account(Name = BIG);
        insert new List<Account>{ alpha, big };

        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 1; i <= 3; i++) {
            opportunities.add(opportunity('Alpha ' + i, alpha.Id, i * 100));
        }
        for (Integer i = 1; i <= 12; i++) {
            opportunities.add(opportunity('Big ' + String.valueOf(i).leftPad(2, '0'), big.Id, i * 100));
        }
        opportunities.add(opportunity('Loose 1', null, 50));
        opportunities.add(opportunity('Loose 2', null, null));
        insert opportunities;
    }

    private static Opportunity opportunity(String name, Id accountId, Decimal amount) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today(),
            Amount = amount
        );
    }

    private static Map<String, Object> groupedRequest(List<Object> amountSummaries) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => new List<Object>{
                new Map<String, Object>{ 'id' => 'name', 'fieldPath' => 'Name', 'linkToRecord' => 'never' },
                new Map<String, Object>{ 'id' => 'amount', 'fieldPath' => 'Amount', 'summaries' => amountSummaries }
            },
            'pageSize' => 10,
            'groupBy' => new List<Object>{ new Map<String, Object>{ 'fieldPath' => 'AccountId' } },
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'refreshToken' => 0
        };
    }

    @IsTest
    static void groupSpanningPagesCarriesItsWholeGroupSummariesOnEveryPage() {
        Map<String, Object> request = groupedRequest(new List<Object>{ 'SUM', 'AVG', 'MIN', 'MAX' });

        BoardQueryService.TableResult first = BoardQueryService.queryTable(JSON.serialize(request));
        BoardQueryService.TablePage second = BoardQueryService.fetchGroupedTablePage(
            JSON.serialize(request),
            first.paginationCursor,
            first.nextIndex
        );

        Assert.areEqual(10, first.rows.size());
        Assert.areEqual(7, second.rows.size());
        BoardTableEngine.TableGroup bigOnFirst = groupLabelled(first.groups, BIG);
        BoardTableEngine.TableGroup bigOnSecond = groupLabelled(second.groups, BIG);
        List<String> functions = new List<String>{ 'SUM', 'AVG', 'MIN', 'MAX' };
        List<Decimal> bigValues = new List<Decimal>{ 7800, 650, 100, 1200 };
        assertAmountSummaries(bigOnFirst, functions, bigValues);
        assertAmountSummaries(bigOnSecond, functions, bigValues);

        assertAmountSummaries(groupLabelled(first.groups, ALPHA), functions, new List<Decimal>{ 600, 200, 100, 300 });
        BoardTableEngine.TableGroup blank = second.groups[second.groups.size() - 1];
        Assert.isNull(blank.key, 'Blanks form the last group');
        assertAmountSummaries(blank, functions, new List<Decimal>{ 50, 50, 50, 50 });
    }

    @IsTest
    static void groupSummariesFollowTheConfiguredOrderWithoutATotalRow() {
        BoardQueryService.TableResult result = BoardQueryService.queryTable(
            JSON.serialize(groupedRequest(new List<Object>{ 'max', 'SUM' }))
        );

        Assert.isNull(result.totals, 'The Total row is off');
        assertAmountSummaries(
            groupLabelled(result.groups, ALPHA),
            new List<String>{ 'MAX', 'SUM' },
            new List<Decimal>{ 300, 600 }
        );
    }

    @IsTest
    static void groupsWithoutSummariesCarryNone() {
        Map<String, Object> request = groupedRequest(null);
        ((Map<String, Object>) ((List<Object>) request.get('columns'))[1]).remove('summaries');

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        Assert.areEqual(2, result.groups.size(), 'The first page of 10 rows reaches Alpha and Big');
        for (BoardTableEngine.TableGroup tableGroup : result.groups) {
            Assert.isTrue(tableGroup.summaries.isEmpty(), 'No summaries configured');
        }
    }

    @IsTest
    static void eachGroupingLevelCarriesItsOwnSummaries() {
        Map<String, Object> request = groupedRequest(new List<Object>{ 'SUM', 'AVG', 'MAX' });
        ((List<Object>) request.get('groupBy')).add(new Map<String, Object>{ 'fieldPath' => 'Name' });
        request.put('pageSize', 100);

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        List<String> functions = new List<String>{ 'SUM', 'AVG', 'MAX' };
        BoardTableEngine.TableGroup alpha = groupLabelled(result.groups, ALPHA);
        Assert.areEqual(1, alpha.level);
        assertAmountSummaries(alpha, functions, new List<Decimal>{ 600, 200, 300 });
        BoardTableEngine.TableGroup alphaTwo = groupLabelled(result.groups, 'Alpha 2');
        Assert.areEqual(2, alphaTwo.level);
        Assert.areEqual(alpha.key, alphaTwo.parentKey);
        assertAmountSummaries(alphaTwo, functions, new List<Decimal>{ 200, 200, 200 });
    }

    @IsTest
    static void totalRowIsTheGrandTotalOfTheGroupedTable() {
        Map<String, Object> request = groupedRequest(new List<Object>{ 'SUM', 'MAX' });
        request.put('showTotalRow', true);

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        Assert.areEqual(1, result.totals.size());
        List<BoardTableEngine.SummaryValue> grand = result.totals[0].summaries;
        Assert.areEqual('SUM', grand[0].summaryFunction);
        Assert.isTrue(grand[0].value == 8450, 'All groups, all pages, blanks included: got ' + grand[0].value);
        Assert.areEqual('MAX', grand[1].summaryFunction);
        Assert.isTrue(grand[1].value == 1200, 'Grand max: got ' + grand[1].value);
    }

    private static BoardTableEngine.TableGroup groupLabelled(List<BoardTableEngine.TableGroup> groups, String label) {
        for (BoardTableEngine.TableGroup tableGroup : groups) {
            if (tableGroup.label == label) {
                return tableGroup;
            }
        }
        Assert.fail('No group labelled ' + label);
        return null;
    }

    private static void assertAmountSummaries(
        BoardTableEngine.TableGroup tableGroup,
        List<String> expectedFunctions,
        List<Decimal> expectedValues
    ) {
        Assert.areEqual(1, tableGroup.summaries.size(), 'Only the Amount column is summarized');
        BoardTableEngine.ColumnTotal amount = tableGroup.summaries[0];
        Assert.areEqual('amount', amount.columnId);
        Assert.areEqual(expectedFunctions.size(), amount.summaries.size(), 'Stacked summaries');
        for (Integer i = 0; i < expectedFunctions.size(); i++) {
            BoardTableEngine.SummaryValue summary = amount.summaries[i];
            Assert.areEqual(expectedFunctions[i], summary.summaryFunction, 'Configured order');
            Assert.isTrue(
                summary.value != null && summary.value == expectedValues[i],
                tableGroup.label +
                    ' ' +
                    summary.summaryFunction +
                    ': expected ' +
                    expectedValues[i] +
                    ', got ' +
                    summary.value
            );
        }
    }
}