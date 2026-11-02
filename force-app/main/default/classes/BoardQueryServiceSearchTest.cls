@IsTest
private class BoardQueryServiceSearchTest {
    /**
     * Data: Account `Gamma Corp`. Cases `Alpha widget` (Account Gamma Corp, Description `quasar notes`),
     * `Beta quasar` (no account), `Delta` (one CaseComment `zebra crossing`, one `plain note`, one FeedItem),
     * and `Promo 50% off`.
     */
    @TestSetup
    static void setup() {
        Account gamma = new Account(Name = 'Gamma Corp');
        insert gamma;
        Case alpha = new Case(Subject = 'Alpha widget', AccountId = gamma.Id, Description = 'quasar notes');
        Case beta = new Case(Subject = 'Beta quasar');
        Case delta = new Case(Subject = 'Delta');
        Case promo = new Case(Subject = 'Promo 50% off');
        insert new List<Case>{ alpha, beta, delta, promo };
        insert new List<CaseComment>{
            new CaseComment(ParentId = delta.Id, CommentBody = 'zebra crossing'),
            new CaseComment(ParentId = delta.Id, CommentBody = 'plain note')
        };
        insert new FeedItem(ParentId = delta.Id, Body = 'Escalated to the kraken team');
    }

    // ---------------------------------------------------------------------------------------------------------
    // CONTAINS / STARTS_WITH multi-field OR LIKE
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void containsAcrossAFieldListMatchesAnyListedField() {
        // `gamma` only appears on the parent Account name, `alpha` only in the Subject.
        Assert.areEqual(1, countCases(textFilter('CONTAINS', 'gamma', 'Subject, Account.Name')));
        Assert.areEqual(1, countCases(textFilter('CONTAINS', 'ALPHA', 'Subject, Account.Name')));
        // `ta` matches every Subject containing it (OR group, not AND): `Beta quasar`, `Delta`.
        Assert.areEqual(2, countCases(textFilter('CONTAINS', 'ta', 'Subject, Account.Name')));
    }

    @IsTest
    static void termsShorterThanMinCharactersAreIgnored() {
        Map<String, Object> request = caseCount(textFilter('SOSL', 'q', null));
        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(request));
        Assert.areEqual(4, result.value, 'A one-character search never scans or filters');
        Assert.areEqual(new List<String>{ 'search' }, result.ignoredFilterIds);
        Assert.isTrue(result.appliedFilterIds.isEmpty());
    }

    @IsTest
    static void startsWithAcrossAFieldListAnchorsEachField() {
        Assert.areEqual(1, countCases(textFilter('STARTS_WITH', 'Gam', 'Subject, Account.Name')));
        Assert.areEqual(0, countCases(textFilter('STARTS_WITH', 'widget', 'Subject, Account.Name')));
    }

    @IsTest
    static void likeTermsAreEscaped() {
        // `%` is literal: only the Subject containing `50%` matches, not every Subject starting with `50`.
        Assert.areEqual(1, countCases(textFilter('CONTAINS', '50%', 'Subject, Account.Name')));
        Assert.areEqual(0, countCases(textFilter('CONTAINS', '__', 'Subject, Account.Name')));
    }

    @IsTest
    static void fieldListWithAnUnknownFieldFailsClosed() {
        Map<String, Object> payload = expectError(textFilter('CONTAINS', 'abc', 'Subject, NoSuchField__c'));
        Assert.areEqual('CONFIG_ERROR', payload.get('category'));
        Assert.areEqual('search', payload.get('filterId'));
    }

    // ---------------------------------------------------------------------------------------------------------
    // Hybrid SOSL + SOQL LIKE union
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void soslUnionsFullTextAndLikeMatches() {
        Id alphaId = caseId('Alpha widget');
        // SOSL (full-text index on the Long Text Area Description) finds Alpha; the synchronous LIKE leg finds Beta
        // by Subject before the index catches up.
        Test.setFixedSearchResults(new List<Id>{ alphaId });
        BoardQueryService.TableResult result = BoardQueryService.queryTable(
            JSON.serialize(caseTable(null, textFilter('SOSL', 'quasar', null)))
        );
        Assert.areEqual(
            new Set<String>{ 'Alpha widget', 'Beta quasar' },
            rowsBySubject(result.rows).keySet(),
            'SOSL and LIKE matches are unioned'
        );
        Assert.areEqual(new List<String>{ 'search' }, result.appliedFilterIds);
    }

    @IsTest
    static void soslWithoutMatchesReturnsNoRows() {
        Test.setFixedSearchResults(new List<Id>());
        Assert.areEqual(0, countCases(textFilter('SOSL', 'nothing-like-this', null)));
    }

    @IsTest
    static void soslTargetsMustBeSelfOrChildForeignKeys() {
        Map<String, Object> payload = expectError(textFilter('SOSL', 'quasar', 'SELF, Subject'));
        Assert.areEqual('CONFIG_ERROR', payload.get('category'));
        Assert.areEqual('search', payload.get('filterId'));

        payload = expectError(textFilter('SOSL', 'quasar', 'SELF, Opportunity(AccountId)'));
        Assert.areEqual('CONFIG_ERROR', payload.get('category'), 'Opportunity.AccountId does not reference Case');
    }

    @IsTest
    static void searchLegsOnlyCollectRecordsInsideTheOtherFilters() {
        BoardQueryService.SEARCH_SOSL_LIMIT = 2;
        BoardQueryService.SEARCH_LIKE_LIMIT = 2;
        Id gammaId = [SELECT Id FROM Account WHERE Name = 'Gamma Corp' LIMIT 1].Id;
        // More out-of-scope matches than either leg's cap, ahead of the in-scope ones in id and result order.
        List<Case> noise = new List<Case>();
        for (Integer i = 0; i < 4; i++) {
            noise.add(new Case(Subject = 'quasar noise ' + i));
        }
        insert noise;
        Case lateMatch = new Case(Subject = 'Late', Description = 'quasar', AccountId = gammaId);
        Case subjectMatch = new Case(Subject = 'Gamma quasar subject', AccountId = gammaId);
        insert new List<Case>{ lateMatch, subjectMatch };
        List<Id> fixedResults = new List<Id>();
        for (Case noiseCase : noise) {
            fixedResults.add(noiseCase.Id);
        }
        fixedResults.add(lateMatch.Id);
        fixedResults.add(caseId('Alpha widget'));
        Test.setFixedSearchResults(fixedResults);

        Map<String, Object> request = caseCount(textFilter('SOSL', 'quasar', null));
        addAccountFilter(request, gammaId);
        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(request));

        // SOSL (Description, not LIKE-searchable): Alpha + Late; LIKE (Subject): Gamma quasar subject.
        Assert.areEqual(3, result.value, 'In-scope matches are not crowded out by out-of-scope ones');
        Assert.areEqual(new Set<String>{ 'account', 'search' }, new Set<String>(result.appliedFilterIds));
    }

    @IsTest
    static void childSearchLegsAreRestrictedToInScopeParents() {
        BoardQueryService.SEARCH_LIKE_LIMIT = 1;
        Id gammaId = [SELECT Id FROM Account WHERE Name = 'Gamma Corp' LIMIT 1].Id;
        Id deltaId = caseId('Delta');
        insert new List<CaseComment>{
            new CaseComment(ParentId = deltaId, CommentBody = 'zebra two'),
            new CaseComment(ParentId = deltaId, CommentBody = 'zebra three')
        };
        CaseComment inScope = new CaseComment(ParentId = caseId('Alpha widget'), CommentBody = 'zebra in scope');
        insert inScope;
        Test.setFixedSearchResults(new List<Id>{ inScope.Id });

        Map<String, Object> request = caseCount(textFilter('SOSL', 'zebra', 'SELF, CaseComment(ParentId)'));
        addAccountFilter(request, gammaId);
        Assert.areEqual(1, Integer.valueOf(BoardQueryService.queryMetric(JSON.serialize(request)).value));
    }

    @IsTest
    static void soslSearchesCoverAtMostFiveObjects() {
        Map<String, Object> payload = expectError(
            textFilter(
                'SOSL',
                'quasar',
                'SELF, CaseComment(ParentId), FeedItem(ParentId), Task(WhatId), Event(WhatId), Note(ParentId)'
            )
        );
        Assert.areEqual('CONFIG_ERROR', payload.get('category'));
        Assert.areEqual('search', payload.get('filterId'));
    }

    // ---------------------------------------------------------------------------------------------------------
    // Child union, parent preservation, auto-expand
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void caseCommentMatchKeepsTheParentAndAutoExpandsItsMatchingChildren() {
        Test.setFixedSearchResults(new List<Id>());
        Map<String, Object> child = caseCommentConfig();
        BoardQueryService.TableResult result = BoardQueryService.queryTable(
            JSON.serialize(caseTable(child, textFilter('SOSL', 'zebra', null)))
        );

        Map<String, BoardQueryService.TableRow> bySubject = rowsBySubject(result.rows);
        Assert.areEqual(new Set<String>{ 'Delta' }, bySubject.keySet(), 'Only the comment matched; the parent stays');
        BoardQueryService.TableRow delta = bySubject.get('Delta');
        Assert.isTrue(delta.autoExpanded);
        Assert.areEqual(2, delta.childCount, 'The badge still counts every child');
        Assert.areEqual(1, delta.children.rows.size(), 'Only matching children are batch-fetched');
        Assert.areEqual('zebra crossing', delta.children.rows[0].values.get('CommentBody'));
        Assert.areEqual(1, result.searchChildIds.size());

        // Later cursor pages auto-expand with the matched child Ids handed back in childConfig.
        child.put('matchedChildIds', result.searchChildIds);
        BoardQueryService.TablePage page = BoardQueryService.fetchTablePage(
            result.paginationCursor,
            0,
            10,
            JSON.serialize(child)
        );
        Assert.isTrue(page.rows[0].autoExpanded);
        Assert.areEqual(1, page.rows[0].children.rows.size());

        // Manual expansion still lists every child.
        Assert.areEqual(2, BoardQueryService.queryChildRows(JSON.serialize(caseCommentConfig()), delta.id).rows.size());
    }

    @IsTest
    static void feedItemMatchedOnlyBySoslKeepsTheParentAndAutoExpands() {
        // FeedItem.Body is not filterable, so only the SOSL leg can match it.
        Id feedId = [SELECT Id FROM FeedItem LIMIT 1].Id;
        Test.setFixedSearchResults(new List<Id>{ feedId });
        Map<String, Object> child = new Map<String, Object>{
            'childObjectApiName' => 'FeedItem',
            'foreignKeyField' => 'ParentId',
            'limit' => 1,
            'columns' => new List<Object>{ new Map<String, Object>{ 'id' => 'body', 'fieldPath' => 'Body' } }
        };
        BoardQueryService.TableResult result = BoardQueryService.queryTable(
            JSON.serialize(caseTable(child, textFilter('SOSL', 'kraken', 'SELF, FeedItem(ParentId)')))
        );

        Assert.areEqual(1, result.rows.size());
        Assert.areEqual('Delta', result.rows[0].values.get('Subject'));
        Assert.isTrue(result.rows[0].autoExpanded);
        Assert.areEqual(feedId, result.rows[0].children.rows[0].id);
        Assert.isFalse(result.rows[0].children.hasMore);
    }

    @IsTest
    static void explicitChildTargetsPreserveParentsOnAnyWidget() {
        // A Metric has no childRelationship: the CaseComment target still unions its parent.
        Test.setFixedSearchResults(new List<Id>());
        Assert.areEqual(1, countCases(textFilter('SOSL', 'zebra', 'SELF, CaseComment(ParentId)')));
        Assert.areEqual(0, countCases(textFilter('SOSL', 'zebra', 'SELF')), 'SELF alone ignores child matches');
    }

    @IsTest
    static void rowsWithoutChildMatchesAreNotAutoExpanded() {
        Test.setFixedSearchResults(new List<Id>());
        BoardQueryService.TableResult result = BoardQueryService.queryTable(
            JSON.serialize(caseTable(caseCommentConfig(), textFilter('SOSL', 'quasar', null)))
        );
        Assert.areEqual(1, result.rows.size(), 'Beta matches by Subject (LIKE)');
        Assert.isNull(result.rows[0].autoExpanded);
        Assert.isNull(result.rows[0].children);
        Assert.isTrue(result.searchChildIds.isEmpty());
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    private static Map<String, Object> textFilter(String operator, String text, String fieldPath) {
        return new Map<String, Object>{
            'filterId' => 'search',
            'type' => 'TEXT',
            'fieldPath' => fieldPath,
            'explicit' => fieldPath != null,
            'operator' => operator,
            'text' => text
        };
    }

    private static Map<String, Object> caseCount(Map<String, Object> filter) {
        return new Map<String, Object>{
            'objectApiName' => 'Case',
            'aggregateFunction' => 'COUNT',
            'filters' => new List<Object>{ filter }
        };
    }

    private static void addAccountFilter(Map<String, Object> request, Id accountId) {
        ((List<Object>) request.get('filters'))
            .add(
                new Map<String, Object>{
                    'filterId' => 'account',
                    'type' => 'LOOKUP',
                    'fieldPath' => 'AccountId',
                    'explicit' => true,
                    'operator' => 'IN',
                    'values' => new List<Object>{ accountId },
                    'targetObjectApiName' => 'Account'
                }
            );
    }

    private static Integer countCases(Map<String, Object> filter) {
        return Integer.valueOf(BoardQueryService.queryMetric(JSON.serialize(caseCount(filter))).value);
    }

    private static Map<String, Object> expectError(Map<String, Object> filter) {
        try {
            countCases(filter);
        } catch (AuraHandledException error) {
            return (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
        }
        Assert.fail('Expected an error for ' + JSON.serialize(filter));
        return null;
    }

    private static Map<String, Object> caseCommentConfig() {
        return new Map<String, Object>{
            'childObjectApiName' => 'CaseComment',
            'foreignKeyField' => 'ParentId',
            'columns' => new List<Object>{ new Map<String, Object>{ 'id' => 'body', 'fieldPath' => 'CommentBody' } }
        };
    }

    private static Map<String, Object> caseTable(Map<String, Object> child, Map<String, Object> filter) {
        return new Map<String, Object>{
            'objectApiName' => 'Case',
            'columns' => new List<Object>{ new Map<String, Object>{ 'id' => 's', 'fieldPath' => 'Subject' } },
            'sortBy' => 'Subject',
            'childRelationship' => child,
            'filters' => new List<Object>{ filter }
        };
    }

    private static Id caseId(String subject) {
        return [SELECT Id FROM Case WHERE Subject = :subject LIMIT 1].Id;
    }

    private static Map<String, BoardQueryService.TableRow> rowsBySubject(List<BoardQueryService.TableRow> rows) {
        Map<String, BoardQueryService.TableRow> bySubject = new Map<String, BoardQueryService.TableRow>();
        for (BoardQueryService.TableRow row : rows) {
            bySubject.put(String.valueOf(row.values.get('Subject')), row);
        }
        return bySubject;
    }
}