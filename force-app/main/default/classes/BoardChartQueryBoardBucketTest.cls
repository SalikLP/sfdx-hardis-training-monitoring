/**
 * Entry-point seam for Board-level Bucket fields on the Chart query: a Bucket field the Board's Filter widget defines
 * reaches the query in `boardBucketFields` and is used by id like a Widget-level one (`bucketFields`), in the SOQL
 * tier and the cursor tier alike; a Widget-level Bucket field with the same id wins; an id defined in neither is a
 * config error.
 */
@IsTest
private class BoardChartQueryBoardBucketTest {
    /** Board Opp 1 (100) and 2 (200) on Board Alpha; Board Opp 3 (350) and 4 (no Amount) on Board Beta. */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = 'Board Alpha');
        Account beta = new Account(Name = 'Board Beta');
        insert new List<Account>{ alpha, beta };
        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        insert new List<Opportunity>{
            opportunity('Board Opp 1', alpha.Id, 100, stage),
            opportunity('Board Opp 2', alpha.Id, 200, stage),
            opportunity('Board Opp 3', beta.Id, 350, stage),
            opportunity('Board Opp 4', beta.Id, null, stage)
        };
    }

    @IsTest
    static void boardLevelBucketFieldGroupsTheChartById() {
        // The Widget has a Bucket field of its own; the Group by uses the Board's.
        Map<String, Object> request = chartRequest('bucket:size');
        request.put('bucketFields', new List<Object>{ bucketField('own', 'Own', 'Mine', 1) });
        request.put('boardBucketFields', new List<Object>{ bucketField('size', 'Size', 'Large', 300) });

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual('SINGLE', result.mode);
        Assert.areEqual('bucket:size', result.groupBy.fieldPath);
        Assert.areEqual('BUCKET', result.groupBy.dataType);
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(350, values.get('Large|0'), 'Opp 3');
        Assert.areEqual(1, values.get('Large|1'));
        Assert.areEqual(300, values.get('Other|0'), 'Opps 1 and 2 (Opp 4 has no Amount)');
        Assert.areEqual(3, values.get('Other|1'));
    }

    @IsTest
    static void boardLevelBucketFieldAsTheSeries() {
        Map<String, Object> request = chartRequest('AccountId');
        request.put('stackByField', 'bucket:size');
        request.put('measures', new List<Object>{ countMeasure() });
        request.put('boardBucketFields', new List<Object>{ bucketField('size', 'Size', 'Large', 300) });

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual('bucket:size', result.stackBy.fieldPath);
        Map<String, Decimal> cells = cellsByLabels(result);
        Assert.areEqual(2, cells.get('Board Alpha|Other'));
        Assert.areEqual(1, cells.get('Board Beta|Large'));
        Assert.areEqual(1, cells.get('Board Beta|Other'));
        Assert.areEqual(3, cells.size(), String.valueOf(cells));
    }

    @IsTest
    static void widgetLevelBucketFieldWithTheSameIdWins() {
        Map<String, Object> request = chartRequest('bucket:size');
        request.put('bucketFields', new List<Object>{ bucketField('size', 'Size', 'Widget large', 150) });
        request.put('boardBucketFields', new List<Object>{ bucketField('size', 'Size', 'Board large', 300) });

        Map<String, Decimal> values = valuesByLabel(query(request));

        Assert.areEqual(2, values.get('Widget large|1'), 'Opps 2 and 3');
        Assert.isFalse(values.containsKey('Board large|1'), String.valueOf(values));
    }

    @IsTest
    static void cursorTierGivesTheSameBucketsForABoardLevelBucketField() {
        Map<String, Object> request = chartRequest('bucket:size');
        request.put('boardBucketFields', new List<Object>{ bucketField('size', 'Size', 'Large', 300) });
        BoardChartQuery.ChartResult soql = query(request);
        Assert.areEqual('SINGLE', soql.mode);

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 1;
        BoardChartQuery.ChartResult cursor = query(request);
        Assert.areEqual('CURSOR', cursor.mode);
        while (!cursor.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', cursor.cursor);
            next.put('offset', cursor.nextOffset);
            next.put('partialState', cursor.partialState);
            cursor = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }

        Assert.areEqual(valuesByLabel(soql), valuesByLabel(cursor));
    }

    @IsTest
    static void missingBucketFieldIdIsAConfigErrorPointingToTheFilterWidget() {
        Map<String, Object> request = chartRequest('bucket:deleted');
        request.put('bucketFields', new List<Object>{ bucketField('own', 'Own', 'Mine', 1) });
        request.put('boardBucketFields', new List<Object>{ bucketField('size', 'Size', 'Large', 300) });

        try {
            query(request);
            Assert.fail('Expected a config error for an unknown Bucket field');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'));
            String message = (String) payload.get('message');
            Assert.isTrue(message.contains('deleted'), message);
            Assert.isTrue(message.contains('Filter widget'), message);
            Assert.areEqual('bucket:deleted', payload.get('fieldPath'));
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** One rule `ruleLabel` (Amount >= `minAmount`), fallback "Other". */
    private static Map<String, Object> bucketField(String id, String label, String ruleLabel, Decimal minAmount) {
        Map<String, Object> condition = new Map<String, Object>{
            'logic' => 'AND',
            'conditions' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'c1',
                    'fieldPath' => 'Amount',
                    'operator' => 'GTE',
                    'value' => minAmount
                }
            }
        };
        return new Map<String, Object>{
            'id' => id,
            'label' => label,
            'rules' => new List<Object>{ new Map<String, Object>{ 'label' => ruleLabel, 'condition' => condition } }
        };
    }

    private static Map<String, Object> chartRequest(String groupByField) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => groupByField,
            'baseFilters' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'bf1',
                    'fieldPath' => 'Name',
                    'operator' => 'LIKE',
                    'value' => 'Board Opp'
                }
            },
            'measures' => new List<Object>{
                new Map<String, Object>{ 'aggregateFunction' => 'SUM', 'valueFieldApiName' => 'Amount' },
                countMeasure()
            }
        };
    }

    private static Map<String, Object> countMeasure() {
        return new Map<String, Object>{ 'aggregateFunction' => 'COUNT' };
    }

    private static BoardChartQuery.ChartResult query(Map<String, Object> request) {
        return BoardChartQuery.queryChart(JSON.serialize(request));
    }

    /** Point values keyed `categoryLabel|measureIndex`. */
    private static Map<String, Decimal> valuesByLabel(BoardChartQuery.ChartResult result) {
        Map<String, String> labels = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            labels.put(category.key, category.label);
        }
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(
                labels.get(point.categoryKey) + '|' + point.measureIndex,
                point.value == null ? null : point.value.setScale(2)
            );
        }
        return values;
    }

    /** First-Measure point values keyed `categoryLabel|seriesLabel`. */
    private static Map<String, Decimal> cellsByLabels(BoardChartQuery.ChartResult result) {
        Map<String, String> labels = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            labels.put('c' + category.key, category.label);
        }
        for (BoardChartEngine.ChartKey series : result.series) {
            labels.put('s' + series.key, series.label);
        }
        Map<String, Decimal> cells = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            if (point.measureIndex == 0) {
                cells.put(labels.get('c' + point.categoryKey) + '|' + labels.get('s' + point.seriesKey), point.value);
            }
        }
        return cells;
    }

    private static Opportunity opportunity(String name, Id accountId, Decimal amount, String stage) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            Amount = amount,
            StageName = stage,
            CloseDate = Date.today()
        );
    }
}