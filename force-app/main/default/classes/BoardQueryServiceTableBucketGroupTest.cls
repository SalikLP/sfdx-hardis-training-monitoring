/**
 * Entry-point seam for a Bucket field as Table group field (`queryTable` with `detailRows: false` and
 * `groupBy: [{ fieldPath: 'bucket:<id>' }]`): one Group row per bucket, in rule order, with the same record counts and
 * sums as the Chart widget grouped by the same Bucket field; the cursor tier returns the same Group rows; Detail rows
 * on, other columns and a second group field are config errors.
 */
@IsTest
private class BoardQueryServiceTableBucketGroupTest {
    private static final String BUCKET_PATH = 'bucket:dealSize';

    /**
     * Bucket Group 1 (quantity 10, Web, 100), 2 (20; 200), 3 (35; 350), 4 (40; 400), 5 (no quantity, no Amount).
     * Buckets: Large = 3 and 4 (750), Medium = 2 (200), Web = 1 (100), Other = 5.
     */
    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Bucket Group Account');
        insert account;
        Opportunity web = opportunity('Bucket Group 1', account.Id, 10, 100);
        web.LeadSource = 'Web';
        insert new List<Opportunity>{
            web,
            opportunity('Bucket Group 2', account.Id, 20, 200),
            opportunity('Bucket Group 3', account.Id, 35, 350),
            opportunity('Bucket Group 4', account.Id, 40, 400),
            opportunity('Bucket Group 5', account.Id, null, null)
        };
    }

    @IsTest
    static void groupRowsPerBucketMatchTheChartWidgetsBuckets() {
        BoardQueryService.TableResult table = query(tableRequest(null));
        BoardChartQuery.ChartResult chart = BoardChartQuery.queryChart(JSON.serialize(chartRequest()));

        Assert.isNull(table.aggregateCursor, 'Few records: the SOQL tier');
        Assert.areEqual(BUCKET_PATH, table.groupField.fieldPath);
        Assert.areEqual('Deal size', table.groupField.label);
        Assert.areEqual('BUCKET', table.groupField.dataType);
        Assert.areEqual(new List<String>{ 'Large', 'Medium', 'Web', 'Other' }, labels(table), 'Rule order');
        Map<String, Decimal> chartValues = chartValuesByLabel(chart);
        for (BoardTableAggregate.GroupRow groupRow : table.aggregateGroups) {
            Assert.areEqual(groupRow.label, groupRow.key);
            Assert.areEqual(groupRow.label, groupRow.values.get(BUCKET_PATH), 'The Bucket column shows the bucket');
            Assert.areEqual(
                scaled(chartValues.get(groupRow.label + '|1')),
                scaled(Decimal.valueOf(groupRow.count)),
                'Count of ' + groupRow.label
            );
            Assert.areEqual(
                scaled(chartValues.get(groupRow.label + '|0')),
                scaled(sumOf(groupRow)),
                'Sum of Amount of ' + groupRow.label
            );
        }
        assertDecimal(750, sumOf(table.aggregateGroups[0]));
        assertDecimal(400, table.aggregateGroups[0].summaries[0].summaries[1].value);
        Assert.areEqual(2, table.aggregateGroups[0].count);
        Assert.isNull(sumOf(table.aggregateGroups[3]), 'Other has no Amount');
        Assert.areEqual(5, table.totalCount);
        Assert.areEqual(0, table.rows.size(), 'Detail rows off: Group rows only');
        Assert.isFalse(table.hasMore);
        assertDecimal(1050, table.totals[0].summaries[0].value);
    }

    @IsTest
    static void boardLevelBucketFieldInDescendingRuleOrder() {
        Map<String, Object> request = tableRequest(null);
        request.put('boardBucketFields', request.remove('bucketFields'));
        Map<String, Object> entry = (Map<String, Object>) ((List<Object>) request.get('groupBy'))[0];
        entry.put('sortDirection', 'DESC');

        BoardQueryService.TableResult table = query(request);

        Assert.areEqual(new List<String>{ 'Other', 'Web', 'Medium', 'Large' }, labels(table));
        Assert.areEqual('DESC', table.groupField.sortDirection);
    }

    @IsTest
    static void cursorTierGivesTheSameGroupRowsAsTheSoqlTier() {
        Map<String, Object> request = tableRequest(null);
        BoardQueryService.TableResult soqlTier = query(request);

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 2;
        BoardQueryService.CURSOR_FETCH_SIZE = 1;
        BoardQueryService.TableResult first = query(request);
        Assert.isFalse(first.aggregateCursor.isComplete, 'Five records in chunks of two');
        Assert.areEqual(0, first.aggregateGroups.size(), 'Final result only');
        BoardQueryService.TableResult cursorTier = first;
        Integer chunkCalls = 0;
        while (!cursorTier.aggregateCursor.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', cursorTier.aggregateCursor.cursor);
            next.put('offset', cursorTier.aggregateCursor.nextOffset);
            next.put('partialState', cursorTier.aggregateCursor.partialState);
            cursorTier = BoardQueryService.fetchTableAggregateChunk(JSON.serialize(next));
            Assert.isTrue(++chunkCalls < 10, 'The cursor load must finish');
        }

        Assert.areEqual(labels(soqlTier), labels(cursorTier));
        for (Integer g = 0; g < soqlTier.aggregateGroups.size(); g++) {
            BoardTableAggregate.GroupRow want = soqlTier.aggregateGroups[g];
            BoardTableAggregate.GroupRow got = cursorTier.aggregateGroups[g];
            Assert.areEqual(want.count, got.count, want.label);
            Assert.areEqual(want.values.get(BUCKET_PATH), got.values.get(BUCKET_PATH));
            for (Integer s = 0; s < 2; s++) {
                Assert.areEqual(
                    scaled(want.summaries[0].summaries[s].value),
                    scaled(got.summaries[0].summaries[s].value),
                    want.label + ' summary ' + s
                );
            }
        }
        Assert.areEqual(soqlTier.totalCount, cursorTier.totalCount);
        assertDecimal(1050, cursorTier.totals[0].summaries[0].value);
    }

    @IsTest
    static void excludedFallbackWithSummaryOrderAndRowLimit() {
        Map<String, Object> request = tableRequest(new Map<String, Object>{ 'label' => 'Rest', 'exclude' => true });
        Map<String, Object> entry = (Map<String, Object>) ((List<Object>) request.get('groupBy'))[0];
        entry.put('sortDirection', 'DESC');
        entry.put('orderBySummary', new Map<String, Object>{ 'columnId' => 'amount', 'summaryFunction' => 'SUM' });
        request.put('rowLimit', 2);

        BoardQueryService.TableResult table = query(request);

        Assert.areEqual(new List<String>{ 'Large', 'Medium' }, labels(table), 'Top two by Sum of Amount');
        Assert.areEqual(2, table.groupLimit);
        Assert.areEqual(3, table.totalCount, 'Records in the Group rows shown');
        Assert.areEqual('Amount', table.sortBy);
        Assert.areEqual('DESC', table.sortDirection);
        assertDecimal(950, table.totals[0].summaries[0].value);
    }

    @IsTest
    static void rejectsBucketGroupWithDetailRowsOnAndColumnsWithoutOneValuePerBucket() {
        Map<String, Object> detailRowsOn = tableRequest(null);
        detailRowsOn.remove('detailRows');
        Map<String, Object> payload = expectError(detailRowsOn);
        Assert.isTrue(((String) payload.get('message')).contains('Detail rows off'), String.valueOf(payload));

        Map<String, Object> nameColumn = tableRequest(null);
        ((List<Object>) nameColumn.get('columns'))
            .add(new Map<String, Object>{ 'id' => 'name', 'fieldPath' => 'Name' });
        expectError(nameColumn);

        Map<String, Object> twoLevels = tableRequest(null);
        ((List<Object>) twoLevels.get('groupBy')).add(new Map<String, Object>{ 'fieldPath' => 'StageName' });
        expectError(twoLevels);

        Map<String, Object> orderByField = tableRequest(null);
        ((Map<String, Object>) ((List<Object>) orderByField.get('groupBy'))[0]).put('orderBy', 'Account.Name');
        expectError(orderByField);

        Map<String, Object> unknownSummary = tableRequest(null);
        ((Map<String, Object>) ((List<Object>) unknownSummary.get('groupBy'))[0])
            .put('orderBySummary', new Map<String, Object>{ 'columnId' => 'amount', 'summaryFunction' => 'AVG' });
        expectError(unknownSummary);
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** `dealSize`: Large (quantity >= 30), Medium (>= 15), Web (Lead source Web), then the fallback. */
    private static List<Object> dealSize(Map<String, Object> fallback) {
        Map<String, Object> bucketField = new Map<String, Object>{
            'id' => 'dealSize',
            'label' => 'Deal size',
            'rules' => new List<Object>{
                rule('Large', 'TotalOpportunityQuantity', 'GTE', 30),
                rule('Medium', 'TotalOpportunityQuantity', 'GTE', 15),
                rule('Web', 'LeadSource', 'EQ', 'web')
            }
        };
        if (fallback != null) {
            bucketField.put('fallback', fallback);
        }
        return new List<Object>{ bucketField };
    }

    /** Grouped by `dealSize`, Detail rows off: the Bucket column and Amount with Sum and Max, Total row on. */
    private static Map<String, Object> tableRequest(Map<String, Object> fallback) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => new List<Object>{
                new Map<String, Object>{ 'id' => 'size', 'fieldPath' => BUCKET_PATH },
                new Map<String, Object>{
                    'id' => 'amount',
                    'fieldPath' => 'Amount',
                    'summaries' => new List<Object>{ 'SUM', 'MAX' }
                }
            },
            'detailRows' => false,
            'showTotalRow' => true,
            'groupBy' => new List<Object>{ new Map<String, Object>{ 'fieldPath' => BUCKET_PATH } },
            'bucketFields' => dealSize(fallback)
        };
    }

    /** The Chart widget grouped by the same Bucket field: Sum of Amount and Count. */
    private static Map<String, Object> chartRequest() {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => BUCKET_PATH,
            'bucketFields' => dealSize(null),
            'measures' => new List<Object>{
                new Map<String, Object>{ 'aggregateFunction' => 'SUM', 'valueFieldApiName' => 'Amount' },
                new Map<String, Object>{ 'aggregateFunction' => 'COUNT' }
            }
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

    private static BoardQueryService.TableResult query(Map<String, Object> request) {
        return BoardQueryService.queryTable(JSON.serialize(request));
    }

    private static List<String> labels(BoardQueryService.TableResult result) {
        List<String> groupLabels = new List<String>();
        for (BoardTableAggregate.GroupRow groupRow : result.aggregateGroups) {
            groupLabels.add(groupRow.label);
        }
        return groupLabels;
    }

    /** Chart point values keyed `categoryLabel|measureIndex`. */
    private static Map<String, Decimal> chartValuesByLabel(BoardChartQuery.ChartResult result) {
        Map<String, String> categoryLabels = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            categoryLabels.put(category.key, category.label);
        }
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(categoryLabels.get(point.categoryKey) + '|' + point.measureIndex, point.value);
        }
        return values;
    }

    private static Decimal sumOf(BoardTableAggregate.GroupRow groupRow) {
        return groupRow.summaries[0].summaries[0].value;
    }

    /** A number at two decimals (null stays null), so SOQL and in-memory results compare by value. */
    private static Decimal scaled(Decimal value) {
        return value == null ? null : value.setScale(2);
    }

    private static void assertDecimal(Decimal expected, Object actual) {
        Decimal value = BoardQueryService.toDecimal(actual);
        Assert.isTrue(value != null && value == expected, 'Expected ' + expected + ', got ' + actual);
    }

    private static Map<String, Object> expectError(Map<String, Object> request) {
        try {
            query(request);
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), String.valueOf(payload));
            return payload;
        }
        Assert.fail('Expected CONFIG_ERROR for ' + JSON.serialize(request));
        return null;
    }

    private static Opportunity opportunity(String name, Id accountId, Decimal quantity, Decimal amount) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            TotalOpportunityQuantity = quantity,
            Amount = amount,
            CloseDate = Date.today(),
            StageName = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue()
        );
    }
}