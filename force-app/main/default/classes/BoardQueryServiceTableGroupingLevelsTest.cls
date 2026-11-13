/**
 * Entry-point seam for Row grouping by two fields (`queryTable` + `fetchGroupedTablePage`): Opportunities grouped by
 * Account, ordered by a field constant per group (Account Annual Revenue), then by close month (date granularity).
 */
@IsTest
private class BoardQueryServiceTableGroupingLevelsTest {
    private static final String ZETA = 'Board Levels Zeta';
    private static final String ALPHA = 'Board Levels Alpha';

    /**
     * Data: Zeta (revenue 1,000) has 8 Opportunities closing in March 2026 and 4 in April; Alpha (revenue 100) has 1
     * in January and 2 in March; 2 Opportunities without an Account close in May (17 in all). With 10 rows per page
     * Zeta's April spans both pages.
     */
    @TestSetup
    static void setup() {
        Account zeta = new Account(Name = ZETA, AnnualRevenue = 1000);
        Account alpha = new Account(Name = ALPHA, AnnualRevenue = 100);
        insert new List<Account>{ zeta, alpha };

        List<Opportunity> opportunities = new List<Opportunity>();
        addOpportunities(opportunities, zeta.Id, Date.newInstance(2026, 3, 5), 8);
        addOpportunities(opportunities, zeta.Id, Date.newInstance(2026, 4, 10), 4);
        addOpportunities(opportunities, alpha.Id, Date.newInstance(2026, 1, 20), 1);
        addOpportunities(opportunities, alpha.Id, Date.newInstance(2026, 3, 20), 2);
        addOpportunities(opportunities, null, Date.newInstance(2026, 5, 1), 2);
        insert opportunities;
    }

    private static void addOpportunities(List<Opportunity> opportunities, Id accountId, Date closeDate, Integer count) {
        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        for (Integer i = 1; i <= count; i++) {
            opportunities.add(
                new Opportunity(
                    Name = 'Levels ' + closeDate.month() + ' ' + i,
                    AccountId = accountId,
                    CloseDate = closeDate.addDays(i - 1),
                    StageName = stage
                )
            );
        }
    }

    private static Map<String, Object> level(String fieldPath, String sortDirection) {
        return new Map<String, Object>{ 'fieldPath' => fieldPath, 'sortDirection' => sortDirection };
    }

    private static Map<String, Object> request(List<Object> groupBy, Integer pageSize) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => new List<Object>{
                new Map<String, Object>{ 'id' => 'name', 'fieldPath' => 'Name', 'linkToRecord' => 'never' }
            },
            'pageSize' => pageSize,
            'groupBy' => groupBy
        };
    }

    /** Account by Annual Revenue (descending), then close month. */
    private static Map<String, Object> accountThenMonth(Integer pageSize) {
        Map<String, Object> account = level('AccountId', 'DESC');
        account.put('orderBy', 'Account.AnnualRevenue');
        Map<String, Object> month = level('CloseDate', null);
        month.put('dateGranularity', 'CALENDAR_MONTH');
        return request(new List<Object>{ account, month }, pageSize);
    }

    private static String accountId(String name) {
        return String.valueOf([SELECT Id FROM Account WHERE Name = :name].Id);
    }

    /** `level:parentKey/key=count` of each group, in row order. */
    private static List<String> outline(List<BoardTableEngine.TableGroup> groups) {
        List<String> lines = new List<String>();
        for (BoardTableEngine.TableGroup tableGroup : groups) {
            String prefix = tableGroup.level == 2 ? '2:' + tableGroup.parentKey + '/' : '1:';
            lines.add(prefix + tableGroup.key + '=' + tableGroup.count);
        }
        return lines;
    }

    @IsTest
    static void twoLevelsByMonthOrderedByAFieldCarryFullCountsPerLevelAcrossPages() {
        Map<String, Object> grouped = accountThenMonth(10);

        BoardQueryService.TableResult first = BoardQueryService.queryTable(JSON.serialize(grouped));
        BoardQueryService.TablePage second = BoardQueryService.fetchGroupedTablePage(
            JSON.serialize(grouped),
            first.paginationCursor,
            first.nextIndex
        );

        String zeta = accountId(ZETA);
        String alpha = accountId(ALPHA);
        Assert.areEqual(17, first.totalCount, 'The badge counts records');
        Assert.areEqual(
            new List<String>{ '1:' + zeta + '=12', '2:' + zeta + '/2026-03=8', '2:' + zeta + '/2026-04=4' },
            outline(first.groups),
            'Zeta (highest revenue) first; April counts all 4 records though 2 are on this page'
        );
        Assert.areEqual(
            new List<String>{
                '1:' +
                zeta +
                '=12',
                '2:' +
                zeta +
                '/2026-04=4',
                '1:' +
                alpha +
                '=3',
                '2:' +
                alpha +
                '/2026-01=1',
                '2:' +
                alpha +
                '/2026-03=2',
                '1:null=2',
                '2:null/2026-05=2'
            },
            outline(second.groups),
            'Alpha\'s March is its own group; blanks last'
        );

        BoardTableGrouping.GroupField groupField = first.groupField;
        Assert.areEqual('AccountId', groupField.fieldPath);
        Assert.areEqual('Account.AnnualRevenue', groupField.orderBy);
        Assert.areEqual('DESC', groupField.sortDirection);
        BoardTableGrouping.GroupField month = groupField.secondLevel;
        Assert.areEqual('CloseDate', month.fieldPath);
        Assert.areEqual('CALENDAR_MONTH', month.dateGranularity);
        Assert.areEqual('2026-03', first.rows[0].values.get(month.keyPath), 'Rows carry their month key');
        Assert.areEqual(zeta, String.valueOf(first.rows[0].values.get(groupField.keyPath)));
        Assert.isNotNull(first.groups[1].label, 'Month groups are labelled');
        Assert.isNull(first.groups[1].recordId, 'Only lookup groups link');
        Assert.areEqual(zeta, first.groups[0].recordId);
    }

    @IsTest
    static void groupsOrderByValueWithoutAnOrderField() {
        Map<String, Object> month = level('CloseDate', 'DESC');
        month.put('dateGranularity', 'CALENDAR_QUARTER');
        Map<String, Object> grouped = request(new List<Object>{ level('AccountId', null), month }, 100);

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(grouped));

        String zeta = accountId(ZETA);
        String alpha = accountId(ALPHA);
        Assert.areEqual(
            new List<String>{
                '1:' +
                alpha +
                '=3',
                '2:' +
                alpha +
                '/2026-Q1=3',
                '1:' +
                zeta +
                '=12',
                '2:' +
                zeta +
                '/2026-Q2=4',
                '2:' +
                zeta +
                '/2026-Q1=8',
                '1:null=2',
                '2:null/2026-Q2=2'
            },
            outline(result.groups),
            'Accounts by name ascending, quarters descending within each'
        );
        Assert.isNull(result.groupField.orderBy);
    }

    @IsTest
    static void rejectsGroupingsATableCannotRun() {
        Map<String, Object> threeLevels = accountThenMonth(10);
        ((List<Object>) threeLevels.get('groupBy')).add(level('StageName', null));
        assertGroupingError(threeLevels, 'two fields');

        Map<String, Object> notConstant = level('AccountId', null);
        notConstant.put('orderBy', 'Amount');
        assertGroupingError(request(new List<Object>{ notConstant }, 10), 'Amount');

        Map<String, Object> textByMonth = level('StageName', null);
        textByMonth.put('dateGranularity', 'CALENDAR_MONTH');
        assertGroupingError(request(new List<Object>{ textByMonth }, 10), 'StageName');

        assertGroupingError(request(new List<Object>{ level(null, null) }, 10), 'Choose a group field');
        assertGroupingError(
            request(new List<Object>{ level('AccountId', null), level('AccountId', 'DESC') }, 10),
            'two different fields'
        );

        Map<String, Object> byWeek = level('CloseDate', null);
        byWeek.put('dateGranularity', 'WEEK');
        assertGroupingError(request(new List<Object>{ byWeek }, 10), 'Unsupported date granularity');

        Map<String, Object> unsortableOrder = level('AccountId', null);
        unsortableOrder.put('orderBy', 'Account.Description');
        assertGroupingError(request(new List<Object>{ unsortableOrder }, 10), 'not sortable');
    }

    /**
     * A date as the first group field, for every granularity shared with the Chart widget (Date and DateTime fields):
     * each group's count is the number of its records, its rows are contiguous, and the page restriction (a bucket
     * range) loses no record. Fiscal buckets follow the org's fiscal settings, so only their shape is asserted.
     */
    @IsTest
    static void dateFirstLevelCountsEveryGranularity() {
        List<String> granularities = new List<String>{
            'DAY',
            'CALENDAR_MONTH',
            'CALENDAR_QUARTER',
            'CALENDAR_YEAR',
            'FISCAL_QUARTER',
            'FISCAL_YEAR'
        };
        Map<String, Integer> expectedGroups = new Map<String, Integer>{
            'CALENDAR_MONTH' => 4,
            'CALENDAR_QUARTER' => 2,
            'CALENDAR_YEAR' => 1
        };
        for (String granularity : granularities) {
            Map<String, Object> byDate = level('CloseDate', 'DESC');
            byDate.put('dateGranularity', granularity);
            BoardQueryService.TableResult result = BoardQueryService.queryTable(
                JSON.serialize(request(new List<Object>{ byDate }, 100))
            );
            assertCountsMatchRows(result, granularity);
            if (expectedGroups.containsKey(granularity)) {
                Assert.areEqual(expectedGroups.get(granularity), result.groups.size(), granularity);
            }
            if (granularity.startsWith('FISCAL')) {
                Assert.isTrue(result.groups[0].key.startsWith('FY'), result.groups[0].key);
            }
        }
        Assert.areEqual('2026', firstKey('CloseDate', 'CALENDAR_YEAR'));
        Assert.areEqual('2026-05-02', firstKey('CloseDate', 'DAY'), 'Latest close date first (descending)');

        for (String granularity : new List<String>{ 'DAY', 'CALENDAR_MONTH', 'FISCAL_YEAR' }) {
            Map<String, Object> byCreated = level('CreatedDate', null);
            byCreated.put('dateGranularity', granularity);
            BoardQueryService.TableResult result = BoardQueryService.queryTable(
                JSON.serialize(request(new List<Object>{ byCreated }, 100))
            );
            assertCountsMatchRows(result, 'CreatedDate ' + granularity);
            Assert.areEqual(1, result.groups.size(), 'All created today: one bucket');
        }
    }

    private static String firstKey(String fieldPath, String granularity) {
        Map<String, Object> byDate = level(fieldPath, 'DESC');
        byDate.put('dateGranularity', granularity);
        return BoardQueryService.queryTable(JSON.serialize(request(new List<Object>{ byDate }, 100))).groups[0].key;
    }

    @IsTest
    static void blankDatesUnderALookupFormTheirOwnSecondLevelGroup() {
        Map<String, Object> created = level('Account.CreatedDate', null);
        created.put('dateGranularity', 'DAY');
        BoardQueryService.TableResult result = BoardQueryService.queryTable(
            JSON.serialize(request(new List<Object>{ level('AccountId', null), created }, 100))
        );

        BoardTableEngine.TableGroup blankGroup = result.groups[result.groups.size() - 1];
        Assert.areEqual(2, blankGroup.level);
        Assert.isNull(blankGroup.parentKey, 'Under the "(Blank)" Account group');
        Assert.isNull(blankGroup.key, 'No Account, so no Account created date');
        Assert.areEqual(2, blankGroup.count);
        BoardTableEngine.TableGroup blankAccount = result.groups[result.groups.size() - 2];
        Assert.isNull(blankAccount.key);
        Assert.areEqual(1, blankAccount.level);
        Assert.areEqual(2, blankAccount.count);
        Assert.areEqual(12, result.groups[2].count, 'Zeta (after Alpha and its one day) keeps its full count');
        Assert.areEqual('Account.Name', result.groupField.labelPath);
        Assert.areEqual('DATETIME', result.groupField.secondLevel.dataType);
    }

    /**
     * Opportunities without an Account form one "(Blank)" group of a parent-path date level. The platform gives a
     * missing parent's date a placeholder value in `WHERE`/`GROUP BY`/`ORDER BY`, so the blank group's position is not
     * asserted; its count, and the dated group's, are.
     */
    @IsTest
    static void missingParentsFormOneBlankGroupOfAParentPathDateLevel() {
        Map<String, Object> created = level('Account.CreatedDate', null);
        created.put('dateGranularity', 'CALENDAR_MONTH');
        BoardQueryService.TableResult result = BoardQueryService.queryTable(
            JSON.serialize(request(new List<Object>{ created }, 100))
        );

        Assert.areEqual(2, result.groups.size(), 'Both Accounts created this month, and one "(Blank)" group');
        Map<String, BoardTableEngine.TableGroup> byKey = new Map<String, BoardTableEngine.TableGroup>();
        for (BoardTableEngine.TableGroup tableGroup : result.groups) {
            byKey.put(tableGroup.key == null ? '' : tableGroup.key, tableGroup);
        }
        String thisMonth = Datetime.now().format('yyyy-MM');
        Assert.areEqual(15, byKey.get(thisMonth).count, 'Opportunities with an Account');
        Assert.areEqual(2, byKey.get('').count, 'Opportunities without an Account');
    }

    @IsTest
    static void rowLimitOnAParentPathDateLevelCutsTheBlankGroupLast() {
        Map<String, Object> created = level('Account.CreatedDate', null);
        created.put('dateGranularity', 'CALENDAR_MONTH');
        Map<String, Object> limited = request(new List<Object>{ created }, 100);
        limited.put('rowLimit', 1);

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(limited));

        Assert.areEqual(1, result.groupLimit, 'The "(Blank)" group comes last in the group order, so it is cut');
        Assert.areEqual(1, result.groups.size());
        Assert.isNotNull(result.groups[0].key);
        Assert.areEqual(15, result.groups[0].count);
        Assert.areEqual(15, result.totalCount);
    }

    @IsTest
    static void anEmptyScopeHasNoGroups() {
        delete [SELECT Id FROM Opportunity];

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(accountThenMonth(10)));

        Assert.areEqual(0, result.rows.size());
        Assert.areEqual(0, result.groups.size());
        Assert.isNotNull(result.groupField.secondLevel, 'The group fields still resolve');
    }

    /** One first-level group per run of rows, each counting exactly its rows (all rows on one page). */
    private static void assertCountsMatchRows(BoardQueryService.TableResult result, String context) {
        String keyPath = result.groupField.keyPath;
        Map<String, Integer> rowsByKey = new Map<String, Integer>();
        List<String> runs = new List<String>();
        for (BoardQueryService.TableRow row : result.rows) {
            Object rawKey = row.values.get(keyPath);
            String key = rawKey == null ? null : String.valueOf(rawKey);
            if (runs.isEmpty() || runs[runs.size() - 1] != key) {
                Assert.isFalse(rowsByKey.containsKey(key), context + ': group ' + key + ' is split');
                runs.add(key);
            }
            rowsByKey.put(key, (rowsByKey.containsKey(key) ? rowsByKey.get(key) : 0) + 1);
        }
        Assert.areEqual(runs.size(), result.groups.size(), context);
        Integer total = 0;
        for (BoardTableEngine.TableGroup tableGroup : result.groups) {
            Assert.areEqual(rowsByKey.get(tableGroup.key), tableGroup.count, context + ': ' + tableGroup.key);
            Assert.isNotNull(tableGroup.label, context);
            total += tableGroup.count;
        }
        Assert.areEqual(17, total, context);
    }

    private static void assertGroupingError(Map<String, Object> grouped, String expectedFragment) {
        try {
            BoardQueryService.queryTable(JSON.serialize(grouped));
            Assert.fail('Expected a CONFIG_ERROR for ' + expectedFragment);
        } catch (AuraHandledException expected) {
            Assert.isTrue(expected.getMessage().contains('CONFIG_ERROR'), expected.getMessage());
            Assert.isTrue(expected.getMessage().contains(expectedFragment), expected.getMessage());
        }
    }
}