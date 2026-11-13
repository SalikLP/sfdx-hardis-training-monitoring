/**
 * Entry-point seam for the cursor tier of a Table with Detail rows off: above `BoardTableAggregate.MAX_GROUPS` groups
 * (or above the single-aggregate row threshold) `queryTable` reads the scope through `Database.Cursor` chunks,
 * continued by `fetchTableAggregateChunk`, and the final chunk returns the same Group rows as the SOQL tier. Scopes
 * above `CURSOR_MAX_ROWS` rows are blocked. Thresholds are lowered so a few records reach every band.
 */
@IsTest
private class BoardTableAggregateCursorTest {
    private static final String ALPHA = 'Board Cursor Alpha';
    private static final String BETA = 'Board Cursor Beta';
    private static final String GAMMA = 'Board Cursor Gamma';

    /**
     * Data: Opportunities on Alpha (Banking, revenue 100; amounts 10, 20, 30), Beta (Energy, revenue 900; 5),
     * Gamma (no industry, revenue 500; 100, 200) and two without an Account (7, 8). 8 Opportunities, 380 in all.
     */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = ALPHA, Industry = 'Banking', AnnualRevenue = 100);
        Account beta = new Account(Name = BETA, Industry = 'Energy', AnnualRevenue = 900);
        Account gamma = new Account(Name = GAMMA, AnnualRevenue = 500);
        insert new List<Account>{ alpha, beta, gamma };

        List<Opportunity> opportunities = new List<Opportunity>();
        addOpportunities(opportunities, alpha.Id, new List<Decimal>{ 10, 20, 30 });
        addOpportunities(opportunities, beta.Id, new List<Decimal>{ 5 });
        addOpportunities(opportunities, gamma.Id, new List<Decimal>{ 100, 200 });
        addOpportunities(opportunities, null, new List<Decimal>{ 7, 8 });
        insert opportunities;
    }

    private static void addOpportunities(List<Opportunity> opportunities, Id accountId, List<Decimal> amounts) {
        for (Decimal amount : amounts) {
            opportunities.add(
                new Opportunity(
                    Name = 'Board Cursor ' + amount,
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
            'showTotalRow' => true,
            'groupBy' => new List<Object>{ entry }
        };
    }

    private static Map<String, Object> summaryOrder() {
        return new Map<String, Object>{
            'sortDirection' => 'DESC',
            'orderBySummary' => new Map<String, Object>{ 'columnId' => 'amount', 'summaryFunction' => 'SUM' }
        };
    }

    private static BoardQueryService.TableResult query(Map<String, Object> request) {
        return BoardQueryService.queryTable(JSON.serialize(request));
    }

    private static BoardQueryService.TableResult nextChunk(
        Map<String, Object> request,
        BoardQueryService.TableResult previous
    ) {
        Map<String, Object> next = request.clone();
        next.put('cursor', previous.aggregateCursor.cursor);
        next.put('offset', previous.aggregateCursor.nextOffset);
        next.put('partialState', previous.aggregateCursor.partialState);
        return BoardQueryService.fetchTableAggregateChunk(JSON.serialize(next));
    }

    /** `queryTable`, then `fetchTableAggregateChunk` until the load completes. */
    private static BoardQueryService.TableResult loadAll(Map<String, Object> request) {
        BoardQueryService.TableResult result = query(request);
        Integer chunkCalls = 0;
        while (result.aggregateCursor != null && !result.aggregateCursor.isComplete) {
            result = nextChunk(request, result);
            Assert.isTrue(++chunkCalls < 10, 'The cursor load must finish');
        }
        return result;
    }

    @IsTest
    static void aboveTheGroupCapTheCursorTierReturnsTheSoqlTiersGroupRows() {
        Map<String, Object> request = aggregateRequest(null);
        BoardQueryService.TableResult soqlTier = query(request);
        Assert.isNull(soqlTier.aggregateCursor, 'Few groups: one GROUP BY, no cursor');

        BoardTableAggregate.MAX_GROUPS = 2;
        BoardQueryService.TableResult cursorTier = loadAll(request);

        Assert.isNotNull(cursorTier.aggregateCursor, 'More groups than the SOQL tier holds: cursor tier');
        Assert.isTrue(cursorTier.aggregateCursor.isComplete);
        Assert.areEqual(new List<String>{ ALPHA, BETA, GAMMA, null }, labels(cursorTier), 'By name, "(Blank)" last');
        assertSameGroupRows(soqlTier, cursorTier);
        Assert.areEqual(8, cursorTier.totalCount, 'The badge counts records');
        Assert.isFalse(cursorTier.hasMore);
        Assert.areEqual(0, cursorTier.rows.size());
        assertSameTotals(soqlTier.totals, cursorTier.totals);
    }

    @IsTest
    static void chunksReportProgressAndOnlyTheLastCarriesGroupRows() {
        BoardQueryService.CURSOR_CHUNK_SIZE = 3;
        BoardQueryService.CURSOR_FETCH_SIZE = 2;
        BoardTableAggregate.MAX_GROUPS = 2;
        Map<String, Object> request = aggregateRequest(summaryOrder());

        BoardQueryService.TableResult first = query(request);

        Assert.isFalse(first.aggregateCursor.isComplete);
        Assert.areEqual(8, first.aggregateCursor.totalRows);
        Assert.areEqual(3, first.aggregateCursor.processedRows);
        Assert.areEqual(3, first.aggregateCursor.nextOffset);
        Assert.isNotNull(first.aggregateCursor.cursor);
        Assert.isNotNull(first.aggregateCursor.partialState);
        Assert.areEqual(0, first.aggregateGroups.size(), 'Final result only: no partial Group rows');
        Assert.isNull(first.totals, 'Final result only: no partial Total row');

        BoardQueryService.TableResult second = nextChunk(request, first);
        Assert.isFalse(second.aggregateCursor.isComplete);
        Assert.areEqual(6, second.aggregateCursor.processedRows);

        BoardQueryService.TableResult last = nextChunk(request, second);
        Assert.isTrue(last.aggregateCursor.isComplete);
        Assert.areEqual(8, last.aggregateCursor.processedRows);
        Assert.isNull(last.aggregateCursor.partialState);
        Assert.areEqual(new List<String>{ GAMMA, ALPHA, BETA, null }, labels(last), 'Sum of Amount desc');
        Assert.areEqual('Amount', last.sortBy);
        assertDecimal(300, last.aggregateGroups[0].summaries[0].summaries[0].value);
        assertDecimal(200, last.aggregateGroups[0].summaries[0].summaries[1].value);
        Assert.areEqual(2, last.aggregateGroups[3].count);
        assertDecimal(380, last.totals[0].summaries[0].value);
        assertDecimal(200, last.totals[0].summaries[1].value);
    }

    @IsTest
    static void scopesAboveTheSingleAggregateThresholdUseTheCursorTier() {
        Map<String, Object> request = aggregateRequest(
            new Map<String, Object>{ 'sortDirection' => 'DESC', 'orderBy' => 'Account.AnnualRevenue' }
        );
        BoardQueryService.TableResult soqlTier = query(request);

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 5;
        BoardQueryService.TableResult cursorTier = loadAll(request);

        Assert.isNotNull(cursorTier.aggregateCursor, '8 records > 5: cursor tier');
        Assert.areEqual(new List<String>{ BETA, GAMMA, ALPHA, null }, labels(cursorTier), 'Account revenue desc');
        assertSameGroupRows(soqlTier, cursorTier);
    }

    @IsTest
    static void aRowLimitKeepsTheTopGroupRowsAndTotalsThemInTheCursorTier() {
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 5;
        Map<String, Object> request = aggregateRequest(summaryOrder());
        request.put('rowLimit', 2);

        BoardQueryService.TableResult result = loadAll(request);

        Assert.isNotNull(result.aggregateCursor, '8 records > 5: cursor tier');
        Assert.areEqual(new List<String>{ GAMMA, ALPHA }, labels(result), 'Top 2 by Sum of Amount desc');
        Assert.areEqual(2, result.groupLimit);
        Assert.areEqual(5, result.totalCount, 'The badge counts the records of the Group rows shown');
        assertDecimal(360, result.totals[0].summaries[0].value);
        assertDecimal(200, result.totals[0].summaries[1].value);
    }

    @IsTest
    static void picklistGroupsKeepTheirLabelsInTheCursorTier() {
        BoardTableAggregate.MAX_GROUPS = 0;
        Map<String, Object> request = aggregateRequest(null);
        request.put('groupBy', new List<Object>{ new Map<String, Object>{ 'fieldPath' => 'StageName' } });
        request.put(
            'columns',
            new List<Object>{
                new Map<String, Object>{
                    'id' => 'amount',
                    'fieldPath' => 'Amount',
                    'summaries' => new List<Object>{ 'SUM' }
                }
            }
        );

        BoardQueryService.TableResult result = loadAll(request);

        Assert.areEqual(1, result.aggregateGroups.size());
        Assert.areEqual('Prospecting', result.aggregateGroups[0].key);
        Assert.isNotNull(result.aggregateGroups[0].label);
        Assert.isNull(result.aggregateGroups[0].recordId, 'Only lookup groups link');
        Assert.areEqual(8, result.aggregateGroups[0].count);
        assertDecimal(380, result.aggregateGroups[0].summaries[0].summaries[0].value);
    }

    @IsTest
    static void scopesAboveTheCursorTierCapAreBlocked() {
        BoardQueryService.CURSOR_MAX_ROWS = 7;
        try {
            query(aggregateRequest(null));
            Assert.fail('Expected LIMIT_EXCEEDED');
        } catch (AuraHandledException expected) {
            Assert.isTrue(expected.getMessage().contains('LIMIT_EXCEEDED'), expected.getMessage());
            Assert.isTrue(expected.getMessage().contains('Narrow the filters'), expected.getMessage());
        }
    }

    @IsTest
    static void aChunkCallWithoutACursorOrWithABrokenStateIsRetryable() {
        assertRetryable(aggregateRequest(null));

        BoardTableAggregate.MAX_GROUPS = 2;
        BoardQueryService.CURSOR_CHUNK_SIZE = 3;
        Map<String, Object> request = aggregateRequest(null);
        BoardQueryService.TableResult first = query(request);
        Map<String, Object> broken = request.clone();
        broken.put('cursor', first.aggregateCursor.cursor);
        broken.put('offset', first.aggregateCursor.nextOffset);
        broken.put('partialState', '{not json');
        assertRetryable(broken);
    }

    private static void assertRetryable(Map<String, Object> request) {
        try {
            BoardQueryService.fetchTableAggregateChunk(JSON.serialize(request));
            Assert.fail('Expected a retryable QUERY_ERROR');
        } catch (AuraHandledException expected) {
            Assert.isTrue(expected.getMessage().contains('QUERY_ERROR'), expected.getMessage());
            Assert.isTrue(expected.getMessage().contains('"retryable":true'), expected.getMessage());
        }
    }

    private static void assertSameGroupRows(
        BoardQueryService.TableResult expected,
        BoardQueryService.TableResult actual
    ) {
        Assert.areEqual(expected.aggregateGroups.size(), actual.aggregateGroups.size());
        for (Integer g = 0; g < expected.aggregateGroups.size(); g++) {
            BoardTableAggregate.GroupRow want = expected.aggregateGroups[g];
            BoardTableAggregate.GroupRow got = actual.aggregateGroups[g];
            Assert.areEqual(want.key, got.key);
            Assert.areEqual(want.label, got.label);
            Assert.areEqual(want.recordId, got.recordId);
            Assert.areEqual(want.count, got.count);
            Assert.areEqual(want.values.keySet(), got.values.keySet(), 'Same values constant per group');
            for (String path : want.values.keySet()) {
                Object wantValue = want.values.get(path);
                Object gotValue = got.values.get(path);
                if (wantValue instanceof Decimal) {
                    assertDecimal((Decimal) wantValue, gotValue);
                } else {
                    Assert.areEqual(wantValue, gotValue, path);
                }
            }
            assertSameTotals(want.summaries, got.summaries);
        }
    }

    private static void assertSameTotals(
        List<BoardTableEngine.ColumnTotal> expected,
        List<BoardTableEngine.ColumnTotal> actual
    ) {
        Assert.areEqual(expected.size(), actual.size());
        for (Integer c = 0; c < expected.size(); c++) {
            Assert.areEqual(expected[c].columnId, actual[c].columnId);
            Assert.areEqual(expected[c].summaries.size(), actual[c].summaries.size());
            for (Integer s = 0; s < expected[c].summaries.size(); s++) {
                Assert.areEqual(expected[c].summaries[s].summaryFunction, actual[c].summaries[s].summaryFunction);
                Decimal want = expected[c].summaries[s].value;
                Decimal got = actual[c].summaries[s].value;
                Assert.isTrue(want == got, 'Summary ' + s + ' of ' + expected[c].columnId + ': ' + want + ' vs ' + got);
            }
        }
    }

    private static List<String> labels(BoardQueryService.TableResult result) {
        List<String> labels = new List<String>();
        for (BoardTableAggregate.GroupRow groupRow : result.aggregateGroups) {
            labels.add(groupRow.label);
        }
        return labels;
    }

    private static void assertDecimal(Decimal expected, Object actual) {
        Decimal value = BoardQueryService.toDecimal(actual);
        Assert.isTrue(value != null && value == expected, 'Expected ' + expected + ', got ' + actual);
    }
}