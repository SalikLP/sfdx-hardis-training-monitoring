/**
 * Entry-point seam for a Bucket field as Table column (`queryTable`, `fetchGroupedTablePage`): each fetched record
 * shows its bucket label, evaluated in memory; the fields the rules read are fetched but shown in no column; the
 * column is not sortable.
 */
@IsTest
private class BoardQueryServiceTableBucketTest {
    private static final String BUCKET_PATH = 'bucket:dealSize';

    /** Bucket Row 1 (100, Web), 2 (200), 3 (350), 4 (no Amount). */
    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Bucket Table Account');
        insert account;
        Opportunity web = opportunity('Bucket Row 1', account.Id, 100);
        web.LeadSource = 'Web';
        insert new List<Opportunity>{
            web,
            opportunity('Bucket Row 2', account.Id, 200),
            opportunity('Bucket Row 3', account.Id, 350),
            opportunity('Bucket Row 4', account.Id, null)
        };
    }

    @IsTest
    static void eachRowShowsItsBucketLabelAndTheRuleFieldsAreNoColumn() {
        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(tableRequest(null)));

        Assert.areEqual(2, result.columns.size(), 'Amount and Lead source are fetched, not shown');
        BoardQueryService.TableColumn bucketColumn = result.columns[1];
        Assert.areEqual('size', bucketColumn.id);
        Assert.areEqual(BUCKET_PATH, bucketColumn.fieldPath);
        Assert.areEqual('Deal size', bucketColumn.label);
        Assert.areEqual('STRING', bucketColumn.dataType);
        Assert.isFalse(bucketColumn.isSortable, 'A Bucket field column is not sortable');
        Assert.isNull(bucketColumn.linkPath);
        Assert.areEqual(
            new Map<String, Object>{
                'Bucket Row 1' => 'Web',
                'Bucket Row 2' => 'Medium',
                'Bucket Row 3' => 'Large',
                'Bucket Row 4' => 'Other'
            },
            bucketsByName(result.rows),
            'First matching rule wins (Row 3 also matches Medium); no match gets the fallback label'
        );
    }

    @IsTest
    static void excludedFallbackLeavesTheCellBlank() {
        Map<String, Object> request = tableRequest(new Map<String, Object>{ 'label' => 'Rest', 'exclude' => true });

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        Map<String, Object> buckets = bucketsByName(result.rows);
        Assert.areEqual(4, result.rows.size(), 'The Table still shows every record');
        Assert.isNull(buckets.get('Bucket Row 4'), 'Excluded leftovers get no label');
        Assert.areEqual('Large', buckets.get('Bucket Row 3'));
    }

    @IsTest
    static void laterPagesAndRowLimitedTablesAreLabelledToo() {
        Account account = [SELECT Id FROM Account WHERE Name = 'Bucket Table Account'];
        List<Opportunity> more = new List<Opportunity>();
        for (Integer i = 5; i <= 12; i++) {
            more.add(opportunity('Bucket Row ' + String.valueOf(i).leftPad(2, '0'), account.Id, 500));
        }
        insert more;
        Map<String, Object> request = tableRequest(null);
        request.put('pageSize', 10);

        BoardQueryService.TableResult first = BoardQueryService.queryTable(JSON.serialize(request));
        BoardQueryService.TablePage second = BoardQueryService.fetchGroupedTablePage(
            JSON.serialize(request),
            first.paginationCursor,
            first.nextIndex
        );

        Assert.areEqual(10, first.rows.size());
        Assert.areEqual(2, second.rows.size());
        for (BoardQueryService.TableRow row : second.rows) {
            Assert.areEqual('Large', row.values.get(BUCKET_PATH), String.valueOf(row.values));
        }

        request.remove('pageSize');
        request.put('sortBy', 'Name');
        request.put('rowLimit', 3);
        BoardQueryService.TableResult limited = BoardQueryService.queryTable(JSON.serialize(request));
        Assert.areEqual(3, limited.rows.size());
        Assert.areEqual(
            new Map<String, Object>{
                'Bucket Row 05' => 'Large',
                'Bucket Row 06' => 'Large',
                'Bucket Row 07' => 'Large'
            },
            bucketsByName(limited.rows),
            'Row limit: the first three by Name, labelled'
        );
    }

    @IsTest
    static void boardLevelBucketFieldAsColumn() {
        Map<String, Object> request = tableRequest(null);
        request.put('boardBucketFields', request.remove('bucketFields'));

        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        Assert.areEqual('Deal size', result.columns[1].label);
        Assert.areEqual(
            'Web',
            bucketsByName(result.rows).get('Bucket Row 1'),
            'The Board-level Bucket field labels rows'
        );
    }

    @IsTest
    static void rejectsSortingByABucketColumnAndAnUnknownBucketField() {
        Map<String, Object> sorted = tableRequest(null);
        sorted.put('sortBy', BUCKET_PATH);
        Map<String, Object> payload = expectError(sorted, 'CONFIG_ERROR');
        Assert.isTrue(((String) payload.get('message')).contains('not sortable'), String.valueOf(payload));

        Map<String, Object> unknown = tableRequest(null);
        unknown.put('bucketFields', new List<Object>());
        expectError(unknown, 'CONFIG_ERROR');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** Columns Name and the `dealSize` Bucket field: Large (Amount >= 300), Medium (>= 150), Web (Lead source Web). */
    private static Map<String, Object> tableRequest(Map<String, Object> fallback) {
        Map<String, Object> bucketField = new Map<String, Object>{
            'id' => 'dealSize',
            'label' => 'Deal size',
            'rules' => new List<Object>{
                rule('Large', 'Amount', 'GTE', 300),
                rule('Medium', 'Amount', 'GTE', 150),
                rule('Web', 'LeadSource', 'EQ', 'web')
            }
        };
        if (fallback != null) {
            bucketField.put('fallback', fallback);
        }
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => new List<Object>{
                new Map<String, Object>{ 'id' => 'name', 'fieldPath' => 'Name' },
                new Map<String, Object>{ 'id' => 'size', 'fieldPath' => BUCKET_PATH }
            },
            'bucketFields' => new List<Object>{ bucketField }
        };
    }

    private static Map<String, Object> rule(String label, String fieldPath, String operator, Object value) {
        return new Map<String, Object>{
            'label' => label,
            'condition' => new Map<String, Object>{
                'logic' => 'AND',
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 'c1',
                        'fieldPath' => fieldPath,
                        'operator' => operator,
                        'value' => value
                    }
                }
            }
        };
    }

    private static Map<String, Object> bucketsByName(List<BoardQueryService.TableRow> rows) {
        Map<String, Object> buckets = new Map<String, Object>();
        for (BoardQueryService.TableRow row : rows) {
            buckets.put((String) row.values.get('Name'), row.values.get(BUCKET_PATH));
        }
        return buckets;
    }

    private static Map<String, Object> expectError(Map<String, Object> request, String category) {
        try {
            BoardQueryService.queryTable(JSON.serialize(request));
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual(category, payload.get('category'), String.valueOf(payload));
            return payload;
        }
        Assert.fail('Expected ' + category + ' for ' + JSON.serialize(request));
        return null;
    }

    private static Opportunity opportunity(String name, Id accountId, Decimal amount) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            Amount = amount,
            CloseDate = Date.today(),
            StageName = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue()
        );
    }
}