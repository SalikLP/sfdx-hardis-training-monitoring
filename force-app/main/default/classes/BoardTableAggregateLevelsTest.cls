/**
 * Entry-point seam for Row grouping with Detail rows off by two group fields or by a date group field (`queryTable`
 * with `detailRows: false`): first-level Group rows, each followed by its second-level Group rows, every one with its
 * record count and Stacked summaries; dates bucketed by every granularity Detail rows on supports; a parent date with
 * no parent in "(Blank)"; the cursor tier returning the same Group rows as the SOQL tier.
 */
@IsTest
private class BoardTableAggregateLevelsTest {
    private static final String ALPHA = 'Board Levels Alpha';
    private static final String BETA = 'Board Levels Beta';

    /**
     * Data: Alpha (Call 2025-01-15 10, Call 2025-01-20 20, Email 2025-03-10 30), Beta (Email 2025-03-12 5), no Account
     * (Call 2025-07-01 7, Email 2025-07-02 8). 6 Opportunities, 80 in all.
     */
    @TestSetup
    static void setup() {
        Account alphaRow = new Account(Name = ALPHA);
        Account betaRow = new Account(Name = BETA);
        insert new List<Account>{ alphaRow, betaRow };
        insert new List<Opportunity>{
            newOpportunity(alphaRow.Id, 'Call', Date.newInstance(2025, 1, 15), 10),
            newOpportunity(alphaRow.Id, 'Call', Date.newInstance(2025, 1, 20), 20),
            newOpportunity(alphaRow.Id, 'Email', Date.newInstance(2025, 3, 10), 30),
            newOpportunity(betaRow.Id, 'Email', Date.newInstance(2025, 3, 12), 5),
            newOpportunity(null, 'Call', Date.newInstance(2025, 7, 1), 7),
            newOpportunity(null, 'Email', Date.newInstance(2025, 7, 2), 8)
        };
    }

    private static Opportunity newOpportunity(Id accountId, String nextStep, Date closeDate, Decimal amount) {
        return new Opportunity(
            Name = 'Board Levels ' + amount,
            AccountId = accountId,
            NextStep = nextStep,
            Amount = amount,
            StageName = 'Prospecting',
            CloseDate = closeDate
        );
    }

    /** Opportunities grouped by `groupBy`, Detail rows off, with the Total row and Amount Sum and Max. */
    private static Map<String, Object> aggregateRequest(List<Object> groupBy, List<Object> extraColumns) {
        List<Object> columns = new List<Object>{
            new Map<String, Object>{
                'id' => 'amount',
                'fieldPath' => 'Amount',
                'summaries' => new List<Object>{ 'SUM', 'MAX' }
            }
        };
        if (extraColumns != null) {
            columns.addAll(extraColumns);
        }
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => columns,
            'pageSize' => 10,
            'detailRows' => false,
            'showTotalRow' => true,
            'groupBy' => groupBy
        };
    }

    /** Grouped by Account, then by Next Step; the Account name shown. */
    private static Map<String, Object> twoLevelRequest() {
        return aggregateRequest(
            new List<Object>{
                new Map<String, Object>{ 'fieldPath' => 'AccountId' },
                new Map<String, Object>{ 'fieldPath' => 'NextStep' }
            },
            new List<Object>{ new Map<String, Object>{ 'id' => 'account', 'fieldPath' => 'Account.Name' } }
        );
    }

    private static Map<String, Object> dateRequest(String fieldPath, String granularity) {
        return aggregateRequest(
            new List<Object>{ new Map<String, Object>{ 'fieldPath' => fieldPath, 'dateGranularity' => granularity } },
            null
        );
    }

    private static BoardQueryService.TableResult query(Map<String, Object> request) {
        return BoardQueryService.queryTable(JSON.serialize(request));
    }

    /** `queryTable`, then `fetchTableAggregateChunk` until the load completes. */
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

    @IsTest
    static void twoLevelsNestSecondLevelGroupRowsUnderEachFirstLevelGroupRow() {
        BoardQueryService.TableResult result = query(twoLevelRequest());

        Assert.isNull(result.aggregateCursor, 'Few groups: the SOQL tier');
        Assert.areEqual('NextStep', result.groupField.secondLevel.fieldPath);
        Assert.areEqual(
            new List<String>{
                '1 ' + ALPHA,
                '2 Call',
                '2 Email',
                '1 ' + BETA,
                '2 Email',
                '1 null',
                '2 Call',
                '2 Email'
            },
            outline(result),
            'First-level Group rows by name, each followed by its subgroups by value; "(Blank)" last'
        );
        Id alphaId = [SELECT Id FROM Account WHERE Name = :ALPHA].Id;
        BoardTableAggregate.GroupRow alphaRow = result.aggregateGroups[0];
        Assert.areEqual(String.valueOf(alphaId), alphaRow.recordId);
        Assert.areEqual(3, alphaRow.count);
        Assert.areEqual(ALPHA, alphaRow.values.get('Account.Name'));
        assertSummaries(alphaRow, 60, 30);
        BoardTableAggregate.GroupRow alphaCall = result.aggregateGroups[1];
        Assert.areEqual(String.valueOf(alphaId), alphaCall.parentKey);
        Assert.areEqual(2, alphaCall.count);
        Assert.isNull(alphaCall.recordId, 'Only lookup groups link');
        assertSummaries(alphaCall, 30, 20);
        BoardTableAggregate.GroupRow blank = result.aggregateGroups[5];
        Assert.areEqual(2, blank.count);
        assertSummaries(blank, 15, 8);
        Assert.isNull(result.aggregateGroups[6].parentKey);
        assertSummaries(result.aggregateGroups[7], 8, 8);

        Assert.areEqual(6, result.totalCount, 'The badge counts records');
        assertDecimal(80, result.totals[0].summaries[0].value);
        assertDecimal(30, result.totals[0].summaries[1].value);
    }

    @IsTest
    static void theCursorTierReturnsTheSameTwoLevelGroupRows() {
        BoardQueryService.TableResult soqlTier = query(twoLevelRequest());

        BoardTableAggregate.MAX_GROUPS = 2;
        BoardQueryService.TableResult cursorTier = loadAll(twoLevelRequest());

        Assert.isNotNull(cursorTier.aggregateCursor, 'More groups than the SOQL tier holds: cursor tier');
        assertSameGroupRows(soqlTier, cursorTier);
        assertDecimal(80, cursorTier.totals[0].summaries[0].value);
    }

    @IsTest
    static void aRowLimitKeepsTheTopFirstLevelGroupsWithTheirSubgroups() {
        Map<String, Object> request = twoLevelRequest();
        request.put('rowLimit', 1);

        BoardQueryService.TableResult result = query(request);

        Assert.areEqual(new List<String>{ '1 ' + ALPHA, '2 Call', '2 Email' }, outline(result));
        Assert.areEqual(1, result.groupLimit);
        Assert.areEqual(3, result.totalCount, 'Records of the groups shown');
        assertDecimal(60, result.totals[0].summaries[0].value, 'Totals after the limit');

        BoardTableAggregate.MAX_GROUPS = 2;
        BoardQueryService.TableResult cursorTier = loadAll(request);
        assertSameGroupRows(result, cursorTier);
        Assert.areEqual(1, cursorTier.groupLimit);
    }

    @IsTest
    static void firstLevelGroupsOrderByASummaryWithTheirSubgroupsByValue() {
        Map<String, Object> request = twoLevelRequest();
        Map<String, Object> first = (Map<String, Object>) ((List<Object>) request.get('groupBy'))[0];
        first.put('sortDirection', 'DESC');
        first.put('orderBySummary', new Map<String, Object>{ 'columnId' => 'amount', 'summaryFunction' => 'SUM' });

        BoardQueryService.TableResult result = query(request);

        Assert.areEqual(
            new List<String>{
                '1 ' + ALPHA,
                '2 Call',
                '2 Email',
                '1 ' + BETA,
                '2 Email',
                '1 null',
                '2 Call',
                '2 Email'
            },
            outline(result),
            'Sum desc (60, 5), "(Blank)" last'
        );
        Assert.areEqual('Amount', result.sortBy);
        Assert.areEqual('DESC', result.sortDirection);
    }

    @IsTest
    static void aColumnThroughTheSecondLevelLookupShowsOnItsGroupRows() {
        Map<String, Object> request = aggregateRequest(
            new List<Object>{
                new Map<String, Object>{ 'fieldPath' => 'NextStep' },
                new Map<String, Object>{ 'fieldPath' => 'AccountId' }
            },
            new List<Object>{ new Map<String, Object>{ 'id' => 'account', 'fieldPath' => 'Account.Name' } }
        );

        BoardQueryService.TableResult result = query(request);

        Assert.areEqual(
            new List<String>{ '1 Call', '2 ' + ALPHA, '2 null', '1 Email', '2 ' + ALPHA, '2 ' + BETA, '2 null' },
            outline(result)
        );
        Assert.isNull(result.aggregateGroups[0].values.get('Account.Name'), 'Not one value per first-level group');
        Assert.areEqual(ALPHA, result.aggregateGroups[1].values.get('Account.Name'));
    }

    @IsTest
    static void dateGroupsBucketByEveryGranularity() {
        Map<String, Integer> groupCounts = new Map<String, Integer>{
            'DAY' => 6,
            'CALENDAR_MONTH' => 3,
            'CALENDAR_QUARTER' => 2,
            'CALENDAR_YEAR' => 1
        };
        for (String granularity : groupCounts.keySet()) {
            BoardQueryService.TableResult result = query(dateRequest('CloseDate', granularity));
            Assert.areEqual(groupCounts.get(granularity), result.aggregateGroups.size(), granularity);
            Assert.areEqual(granularity, result.groupField.dateGranularity);
        }
        BoardQueryService.TableResult months = query(dateRequest('CloseDate', 'CALENDAR_MONTH'));
        Assert.areEqual(new List<String>{ '2025-01', '2025-03', '2025-07' }, keys(months));
        Assert.areEqual(2, months.aggregateGroups[0].count);
        assertSummaries(months.aggregateGroups[0], 30, 20);
        Assert.areEqual(
            Datetime.newInstance(2025, 1, 1).format('MMM yyyy'),
            months.aggregateGroups[0].label,
            'Labelled like the Chart widget'
        );
        Assert.areEqual(
            new List<String>{ '2025-Q1', '2025-Q3' },
            keys(query(dateRequest('CloseDate', 'CALENDAR_QUARTER')))
        );
        Assert.areEqual(new List<String>{ '2025' }, keys(query(dateRequest('CloseDate', 'CALENDAR_YEAR'))));
        Assert.areEqual('2025-01-15', query(dateRequest('CloseDate', null)).aggregateGroups[0].key, 'Day by default');

        for (String fiscal : new List<String>{ 'FISCAL_QUARTER', 'FISCAL_YEAR' }) {
            BoardQueryService.TableResult result = query(dateRequest('CloseDate', fiscal));
            Integer records = 0;
            for (BoardTableAggregate.GroupRow groupRow : result.aggregateGroups) {
                Assert.isTrue(groupRow.key.startsWith('FY'), fiscal + ': ' + groupRow.key);
                records += groupRow.count;
            }
            Assert.areEqual(6, records, fiscal);
        }

        BoardTableAggregate.MAX_GROUPS = 1;
        assertSameGroupRows(months, loadAll(dateRequest('CloseDate', 'CALENDAR_MONTH')));
    }

    @IsTest
    static void dateTimeGroupsBucketInTheUsersTimeZone() {
        BoardQueryService.TableResult result = query(dateRequest('CreatedDate', 'DAY'));

        Assert.areEqual(new List<String>{ String.valueOf(Date.today()) }, keys(result));
        Assert.areEqual(6, result.aggregateGroups[0].count);
    }

    @IsTest
    static void aParentDateWithoutAParentFallsInTheBlankGroup() {
        Map<String, Object> request = dateRequest('Account.CreatedDate', 'DAY');

        BoardQueryService.TableResult result = query(request);

        Assert.areEqual(new List<String>{ String.valueOf(Date.today()), null }, keys(result));
        Assert.areEqual(4, result.aggregateGroups[0].count);
        Assert.areEqual(2, result.aggregateGroups[1].count, 'Opportunities without an Account');
        assertSummaries(result.aggregateGroups[1], 15, 8);
        assertDecimal(80, result.totals[0].summaries[0].value);

        BoardTableAggregate.MAX_GROUPS = 1;
        assertSameGroupRows(result, loadAll(request));
    }

    @IsTest
    static void aParentDateUnderALookupKeepsMissingParentsInTheBlankSubgroup() {
        Map<String, Object> request = aggregateRequest(
            new List<Object>{
                new Map<String, Object>{ 'fieldPath' => 'NextStep' },
                new Map<String, Object>{ 'fieldPath' => 'Account.CreatedDate', 'dateGranularity' => 'CALENDAR_YEAR' }
            },
            null
        );

        BoardQueryService.TableResult result = query(request);

        String year = String.valueOf(Date.today().year());
        Assert.areEqual(
            new List<String>{ '1 Call', '2 ' + year, '2 null', '1 Email', '2 ' + year, '2 null' },
            outlineByKey(result)
        );
        Assert.areEqual(2, result.aggregateGroups[1].count);
        Assert.areEqual(1, result.aggregateGroups[2].count);
    }

    @IsTest
    static void aDateGroupFieldIsNotAColumnWithOneValuePerGroup() {
        Map<String, Object> request = dateRequest('CloseDate', 'CALENDAR_MONTH');
        ((List<Object>) request.get('columns'))
            .add(new Map<String, Object>{ 'id' => 'close', 'fieldPath' => 'CloseDate' });

        try {
            query(request);
            Assert.fail('Expected a config error');
        } catch (AuraHandledException expected) {
            Assert.isTrue(expected.getMessage().contains('CONFIG_ERROR'), expected.getMessage());
            Assert.isTrue(expected.getMessage().contains('CloseDate'), expected.getMessage());
        }
    }

    /** `<level> <label>` of each Group row, in order. */
    private static List<String> outline(BoardQueryService.TableResult result) {
        List<String> lines = new List<String>();
        for (BoardTableAggregate.GroupRow groupRow : result.aggregateGroups) {
            lines.add(groupRow.level + ' ' + groupRow.label);
        }
        return lines;
    }

    /** `<level> <key>` of each Group row, in order. */
    private static List<String> outlineByKey(BoardQueryService.TableResult result) {
        List<String> lines = new List<String>();
        for (BoardTableAggregate.GroupRow groupRow : result.aggregateGroups) {
            lines.add(groupRow.level + ' ' + groupRow.key);
        }
        return lines;
    }

    private static List<String> keys(BoardQueryService.TableResult result) {
        List<String> keys = new List<String>();
        for (BoardTableAggregate.GroupRow groupRow : result.aggregateGroups) {
            keys.add(groupRow.key);
        }
        return keys;
    }

    private static void assertSameGroupRows(
        BoardQueryService.TableResult expected,
        BoardQueryService.TableResult actual
    ) {
        Assert.areEqual(outlineByKey(expected), outlineByKey(actual));
        for (Integer g = 0; g < expected.aggregateGroups.size(); g++) {
            BoardTableAggregate.GroupRow want = expected.aggregateGroups[g];
            BoardTableAggregate.GroupRow got = actual.aggregateGroups[g];
            Assert.areEqual(want.label, got.label);
            Assert.areEqual(want.parentKey, got.parentKey);
            Assert.areEqual(want.recordId, got.recordId);
            Assert.areEqual(want.count, got.count);
            Assert.areEqual(want.summaries.size(), got.summaries.size());
            for (Integer c = 0; c < want.summaries.size(); c++) {
                for (Integer s = 0; s < want.summaries[c].summaries.size(); s++) {
                    Decimal wantValue = want.summaries[c].summaries[s].value;
                    Decimal gotValue = got.summaries[c].summaries[s].value;
                    Assert.isTrue(wantValue == gotValue, 'Summary ' + s + ': ' + wantValue + ' vs ' + gotValue);
                }
            }
        }
        Assert.areEqual(expected.totalCount, actual.totalCount);
    }

    private static void assertSummaries(BoardTableAggregate.GroupRow groupRow, Decimal sum, Decimal max) {
        Assert.areEqual('amount', groupRow.summaries[0].columnId);
        assertDecimal(sum, groupRow.summaries[0].summaries[0].value);
        assertDecimal(max, groupRow.summaries[0].summaries[1].value);
    }

    private static void assertDecimal(Decimal expected, Object actual) {
        assertDecimal(expected, actual, '');
    }

    private static void assertDecimal(Decimal expected, Object actual, String message) {
        Decimal value = BoardQueryService.toDecimal(actual);
        Assert.isTrue(value != null && value == expected, message + ' Expected ' + expected + ', got ' + actual);
    }
}