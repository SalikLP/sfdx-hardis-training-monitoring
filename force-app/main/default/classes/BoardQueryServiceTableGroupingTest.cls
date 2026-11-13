/**
 * Entry-point seam for Row grouping with Detail rows on (`queryTable` + `fetchGroupedTablePage`): a group-sorted
 * record stream whose pages carry full-group counts, lookup groups keyed by Id, and one "(Blank)" group last.
 */
@IsTest
private class BoardQueryServiceTableGroupingTest {
    private static final String ALPHA = 'Board Group Alpha';
    private static final String TWIN = 'Board Group Twin';

    /**
     * Data: Accounts Alpha and two Accounts both named Twin. Cases: 3 on Alpha, 12 on the first Twin, 2 on the second
     * Twin, 2 without an Account (19 in all). With 10 rows per page, the 12-Case Twin group spans both pages.
     */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = ALPHA);
        Account bigTwin = new Account(Name = TWIN);
        Account smallTwin = new Account(Name = TWIN);
        // Same-named Accounts are the point of the test: save them past any duplicate-rule alert.
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.insert(new List<Account>{ alpha, bigTwin, smallTwin }, options);

        List<Case> cases = new List<Case>();
        addCases(cases, alpha.Id, 'Alpha', 3);
        addCases(cases, bigTwin.Id, 'Big twin', 12);
        addCases(cases, smallTwin.Id, 'Small twin', 2);
        addCases(cases, null, 'No account', 2);
        insert cases;
    }

    private static void addCases(List<Case> cases, Id accountId, String prefix, Integer count) {
        for (Integer i = 1; i <= count; i++) {
            cases.add(
                new Case(
                    Subject = prefix + ' ' + String.valueOf(i).leftPad(2, '0'),
                    AccountId = accountId,
                    Priority = Math.mod(i, 2) == 1 ? 'High' : 'Low'
                )
            );
        }
    }

    private static Map<String, Object> groupedRequest(String groupField, String groupDirection, Integer pageSize) {
        return new Map<String, Object>{
            'objectApiName' => 'Case',
            'columns' => new List<Object>{
                new Map<String, Object>{ 'id' => 'subject', 'fieldPath' => 'Subject', 'linkToRecord' => 'never' }
            },
            'pageSize' => pageSize,
            'groupBy' => new List<Object>{
                new Map<String, Object>{ 'fieldPath' => groupField, 'sortDirection' => groupDirection }
            }
        };
    }

    private static Id bigTwinId() {
        return [SELECT AccountId FROM Case WHERE Subject = 'Big twin 01'].AccountId;
    }

    private static Id smallTwinId() {
        return [SELECT AccountId FROM Case WHERE Subject = 'Small twin 01'].AccountId;
    }

    @IsTest
    static void groupSpanningPagesCarriesTheFullCountOnEveryPageAndBlanksComeLast() {
        Map<String, Object> request = groupedRequest('AccountId', null, 10);

        BoardQueryService.TableResult first = BoardQueryService.queryTable(JSON.serialize(request));
        BoardQueryService.TablePage second = BoardQueryService.fetchGroupedTablePage(
            JSON.serialize(request),
            first.paginationCursor,
            first.nextIndex
        );

        Assert.areEqual(19, first.totalCount, 'The badge counts records, not groups');
        Assert.areEqual('AccountId', first.groupField.fieldPath);
        Assert.areEqual('Account.Name', first.groupField.labelPath, 'Lookups are labelled by the record name');
        Assert.areEqual('ASC', first.groupField.sortDirection);
        Assert.areEqual(10, first.rows.size());
        Assert.areEqual(9, second.rows.size());
        Assert.isFalse(second.hasMore);

        Map<String, BoardTableEngine.TableGroup> firstByKey = byKey(first.groups);
        Map<String, BoardTableEngine.TableGroup> secondByKey = byKey(second.groups);
        String bigTwin = String.valueOf(bigTwinId());
        Assert.isTrue(firstByKey.containsKey(bigTwin), 'The 12-Case group starts on the first page');
        Assert.isTrue(secondByKey.containsKey(bigTwin), 'and continues on the second page');
        Assert.areEqual(12, firstByKey.get(bigTwin).count, 'Full-group count on the first page');
        Assert.areEqual(12, secondByKey.get(bigTwin).count, 'Full-group count on the second page');

        Assert.areEqual(ALPHA, first.groups[0].label, 'Groups ordered by record name');
        Assert.areEqual(3, first.groups[0].count);
        Assert.areEqual(first.groups[0].key, first.groups[0].recordId, 'Lookup groups link to their record');

        BoardTableEngine.TableGroup blank = second.groups[second.groups.size() - 1];
        Assert.isNull(blank.key, 'Blanks form the last group');
        Assert.isNull(blank.recordId);
        Assert.areEqual(2, blank.count);
        Assert.isNull(second.rows[second.rows.size() - 1].values.get('AccountId'));
    }

    @IsTest
    static void sameNamedLookupRecordsStaySeparateGroups() {
        BoardQueryService.TableResult result = BoardQueryService.queryTable(
            JSON.serialize(groupedRequest('AccountId', null, 100))
        );

        List<BoardTableEngine.TableGroup> twins = new List<BoardTableEngine.TableGroup>();
        for (BoardTableEngine.TableGroup tableGroup : result.groups) {
            if (tableGroup.label == TWIN) {
                twins.add(tableGroup);
            }
        }
        Assert.areEqual(2, twins.size(), 'One group per record, not per name');
        Map<String, BoardTableEngine.TableGroup> twinsByKey = byKey(twins);
        Assert.areEqual(12, twinsByKey.get(String.valueOf(bigTwinId())).count);
        Assert.areEqual(2, twinsByKey.get(String.valueOf(smallTwinId())).count);
        assertContiguousGroups(result.rows, 'AccountId', 4);
    }

    @IsTest
    static void descendingGroupOrderKeepsBlanksLastAndSortsRecordsWithinGroups() {
        Map<String, Object> request = groupedRequest('AccountId', 'DESC', 100);
        request.put('sortBy', 'Subject');
        request.put('sortDirection', 'DESC');

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        Assert.areEqual('DESC', result.groupField.sortDirection);
        Assert.areEqual(4, result.groups.size());
        Assert.areEqual(TWIN, result.groups[0].label, 'Twin sorts before Alpha descending');
        Assert.areEqual(TWIN, result.groups[1].label);
        Assert.areEqual(ALPHA, result.groups[2].label);
        Assert.isNull(result.groups[3].key, 'Blanks stay last in descending order');

        List<String> alphaSubjects = new List<String>();
        for (BoardQueryService.TableRow row : result.rows) {
            String subject = (String) row.values.get('Subject');
            if (subject.startsWith('Alpha')) {
                alphaSubjects.add(subject);
            }
        }
        Assert.areEqual(new List<String>{ 'Alpha 03', 'Alpha 02', 'Alpha 01' }, alphaSubjects, 'Within-group sort');
    }

    @IsTest
    static void picklistGroupsAreLabelledByThePicklistLabel() {
        BoardQueryService.TableResult result = BoardQueryService.queryTable(
            JSON.serialize(groupedRequest('Priority', null, 100))
        );

        Map<String, String> labels = new Map<String, String>();
        for (Schema.PicklistEntry entry : Case.Priority.getDescribe().getPicklistValues()) {
            labels.put(entry.getValue(), entry.getLabel());
        }
        Map<String, BoardTableEngine.TableGroup> groups = byKey(result.groups);
        Assert.areEqual(2, groups.size());
        Assert.areEqual(10, groups.get('High').count, 'Odd-numbered Cases are High');
        Assert.areEqual(9, groups.get('Low').count);
        Assert.areEqual(labels.get('High'), groups.get('High').label);
        Assert.isNull(groups.get('High').recordId, 'Only lookup groups link');
        assertContiguousGroups(result.rows, 'Priority', 2);
    }

    @IsTest
    static void rejectsGroupFieldsATableCannotGroupBy() {
        assertGroupingError(groupedRequest('Description', null, 10), 'Description');
        Map<String, Object> threeLevels = groupedRequest('AccountId', null, 10);
        ((List<Object>) threeLevels.get('groupBy')).add(new Map<String, Object>{ 'fieldPath' => 'Priority' });
        ((List<Object>) threeLevels.get('groupBy')).add(new Map<String, Object>{ 'fieldPath' => 'Status' });
        assertGroupingError(threeLevels, 'two fields');
    }

    private static void assertGroupingError(Map<String, Object> request, String expectedFragment) {
        try {
            BoardQueryService.queryTable(JSON.serialize(request));
            Assert.fail('Expected a CONFIG_ERROR for ' + expectedFragment);
        } catch (AuraHandledException expected) {
            Assert.isTrue(expected.getMessage().contains('CONFIG_ERROR'), expected.getMessage());
            Assert.isTrue(expected.getMessage().contains(expectedFragment), expected.getMessage());
        }
    }

    private static Map<String, BoardTableEngine.TableGroup> byKey(List<BoardTableEngine.TableGroup> groups) {
        Map<String, BoardTableEngine.TableGroup> groupsByKey = new Map<String, BoardTableEngine.TableGroup>();
        for (BoardTableEngine.TableGroup tableGroup : groups) {
            groupsByKey.put(tableGroup.key, tableGroup);
        }
        return groupsByKey;
    }

    /** Each group's rows form one run in the stream (`expectedRuns` runs in all). */
    private static void assertContiguousGroups(
        List<BoardQueryService.TableRow> rows,
        String keyPath,
        Integer expectedRuns
    ) {
        Set<Object> finished = new Set<Object>();
        Object current;
        Integer runs = 0;
        for (Integer i = 0; i < rows.size(); i++) {
            Object key = rows[i].values.get(keyPath);
            if (i == 0 || key != current) {
                Assert.isFalse(finished.contains(key), 'Group ' + key + ' is split in the stream');
                if (i > 0) {
                    finished.add(current);
                }
                current = key;
                runs++;
            }
        }
        Assert.areEqual(expectedRuns, runs);
    }
}