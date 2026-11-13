/**
 * Entry-point seam for Average per record: the Chart and Metric query entry points with inserted Opportunities and
 * line items. Average deal size per Opportunity by product family (a line-level field), both inner modes, nulls
 * skipped, a Measure condition, the cursor tier (chunks and a capped group query) and a Data provider's partials.
 *
 * Lines (TotalPrice) of Opportunity A (Probability 10): Hardware 100 + 50, Software 20. B (20): Hardware 300.
 * C (40): Software 40 + 60. D (40): no lines.
 */
@IsTest
private class BoardAveragePerRecordQueryTest {
    private static final String PROVIDER = 'BoardAveragePerRecordQueryTest.HardwareProvider';

    /** Test provider: the standard leg plus one more Opportunity's Hardware deal of 600. */
    public class HardwareProvider implements BoardDataProvider {
        public BoardDataProviderResult provide(BoardDataProviderRequest request) {
            BoardDataProviderResult result = new BoardDataProviderResult();
            result.includeStandardResult = true;
            BoardDataProviderResult.Bucket bucket = new BoardDataProviderResult.Bucket(
                'Hardware',
                'Hardware',
                null,
                null
            );
            bucket.measures.add(new BoardDataProviderResult.Partial(600, 1, 600, 600));
            result.buckets.add(bucket);
            return result;
        }
    }

    @TestSetup
    static void setup() {
        Id pricebookId = Test.getStandardPricebookId();
        Product2 hardwareOne = new Product2(Name = 'AP Server', Family = 'Hardware', IsActive = true);
        Product2 hardwareTwo = new Product2(Name = 'AP Rack', Family = 'Hardware', IsActive = true);
        Product2 software = new Product2(Name = 'AP Licence', Family = 'Software', IsActive = true);
        insert new List<Product2>{ hardwareOne, hardwareTwo, software };
        Map<Id, PricebookEntry> entries = new Map<Id, PricebookEntry>();
        for (Product2 product : new List<Product2>{ hardwareOne, hardwareTwo, software }) {
            entries.put(
                product.Id,
                new PricebookEntry(Pricebook2Id = pricebookId, Product2Id = product.Id, UnitPrice = 1, IsActive = true)
            );
        }
        insert entries.values();

        String stage = [SELECT ApiName FROM OpportunityStage WHERE IsActive = TRUE AND IsClosed = FALSE LIMIT 1]
        .ApiName;
        Opportunity a = opportunity('AP A', 10, stage, pricebookId);
        Opportunity b = opportunity('AP B', 20, stage, pricebookId);
        Opportunity c = opportunity('AP C', 40, stage, pricebookId);
        Opportunity d = opportunity('AP D', 40, stage, pricebookId);
        insert new List<Opportunity>{ a, b, c, d };
        insert new List<OpportunityLineItem>{
            line(a, entries.get(hardwareOne.Id), 100),
            line(a, entries.get(hardwareTwo.Id), 50),
            line(a, entries.get(software.Id), 20),
            line(b, entries.get(hardwareOne.Id), 300),
            line(c, entries.get(software.Id), 40),
            line(c, entries.get(software.Id), 60)
        };
    }

    @IsTest
    static void averageDealSizeByFamilyCountsEachOpportunityOnce() {
        BoardChartQuery.ChartResult result = query(
            chartRequest(
                new List<Object>{
                    perRecord('SUM', 'TotalPrice'),
                    measure('AVG', 'TotalPrice'),
                    withCondition(perRecord('SUM', 'TotalPrice'), probabilityAtLeast(20))
                }
            )
        );

        Assert.areEqual('SINGLE', result.mode);
        Assert.areEqual('AVG_PER', result.aggregateFunctions[0]);
        Assert.areEqual('CURRENCY', result.valueTypes[0]);
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(225.00, scaled(values.get('Hardware|0')), 'Deal sizes 150 (A) and 300 (B)');
        Assert.areEqual(60.00, scaled(values.get('Software|0')), 'Deal sizes 20 (A) and 100 (C)');
        Assert.areEqual(150.00, scaled(values.get('Hardware|1')), 'Per line it would be 450 / 3');
        Assert.areEqual(300.00, scaled(values.get('Hardware|2')), 'Condition: Probability >= 20 keeps B only');
        Assert.areEqual(100.00, scaled(values.get('Software|2')), 'Condition: C only');
    }

    @IsTest
    static void onceTakesAValueRepeatedOnEveryRowOncePerRecord() {
        Map<String, Decimal> values = valuesByLabel(
            query(chartRequest(new List<Object>{ perRecord('ONCE', 'Opportunity.Probability') }))
        );

        Assert.areEqual(15.00, scaled(values.get('Hardware|0')), 'A 10 and B 20, not 10, 10, 20');
        Assert.areEqual(25.00, scaled(values.get('Software|0')), 'A 10 and C 40, not 10, 40, 40');
    }

    @IsTest
    static void recordsWithoutAValueAreSkippedLikeANormalAverage() {
        // Opportunities per Account: X 10 + 20, Y two without an Amount, Z 40 + one without an Amount.
        Account x = new Account(Name = 'AP X');
        Account y = new Account(Name = 'AP Y');
        Account z = new Account(Name = 'AP Z');
        insert new List<Account>{ x, y, z };
        String stage = [SELECT ApiName FROM OpportunityStage WHERE IsActive = TRUE AND IsClosed = FALSE LIMIT 1]
        .ApiName;
        insert new List<Opportunity>{
            accountOpportunity('AP X1', x.Id, 10, stage),
            accountOpportunity('AP X2', x.Id, 20, stage),
            accountOpportunity('AP Y1', y.Id, null, stage),
            accountOpportunity('AP Y2', y.Id, null, stage),
            accountOpportunity('AP Z1', z.Id, 40, stage),
            accountOpportunity('AP Z2', z.Id, null, stage)
        };
        Map<String, Object> request = new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            // One category: every Opportunity is open. AP A-D have no Account, so no record: skipped.
            'groupByField' => 'IsClosed',
            'measures' => new List<Object>{ perAccount('SUM'), perAccount('ONCE') }
        };

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual(1, result.categories.size());
        Map<Integer, Decimal> values = new Map<Integer, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(point.measureIndex, point.value);
        }
        Assert.areEqual(35.00, scaled(values.get(0)), 'X 30 and Z 40; Y has no value and is skipped, not 0');
        Assert.areEqual(30.00, scaled(values.get(1)), 'Once: X 20 and Z 40; Y skipped');
    }

    @IsTest
    static void cursorTierMatchesTheSoqlTier() {
        List<Object> measures = new List<Object>{
            perRecord('SUM', 'TotalPrice'),
            perRecord('ONCE', 'Opportunity.Probability'),
            withCondition(perRecord('SUM', 'TotalPrice'), probabilityAtLeast(20)),
            measure('SUM', 'TotalPrice')
        };
        Map<String, Decimal> expected = valuesByLabel(query(chartRequest(measures)));

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 4;
        Map<String, Object> request = chartRequest(measures);
        BoardChartQuery.ChartResult result = query(request);
        Assert.areEqual('CURSOR', result.mode);
        Integer chunks = 1;
        while (!result.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.cursor);
            next.put('offset', result.nextOffset);
            next.put('partialState', result.partialState);
            result = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
            chunks++;
        }
        Assert.isTrue(chunks > 1, 'Several chunks, each ending at an Opportunity boundary');
        assertSameValues(expected, valuesByLabel(result));
        Assert.areEqual(225.00, scaled(valuesByLabel(result).get('Hardware|0')));
    }

    @IsTest
    static void aCappedGroupQueryReRunsThroughTheCursorTier() {
        BoardQueryService.CHART_GROUP_LIMIT = 2;
        BoardChartQuery.ChartResult result = query(chartRequest(new List<Object>{ perRecord('SUM', 'TotalPrice') }));

        Assert.areEqual('CURSOR', result.mode, 'More (family, Opportunity) groups than one query returns');
        Assert.isTrue(result.isComplete);
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(225.00, scaled(values.get('Hardware|0')));
        Assert.areEqual(60.00, scaled(values.get('Software|0')));
    }

    @IsTest
    static void smallMultiplesAveragePerRecordWithinEachPanel() {
        Map<String, Object> request = chartRequest(new List<Object>{ perRecord('SUM', 'TotalPrice') });
        request.put('groupByField', 'Product2.IsActive');
        request.put('panelField', 'Product2.Family');
        Map<String, Decimal> expected = valuesByPanel(query(request));

        Assert.areEqual(225.00, scaled(expected.get('Hardware')), 'Hardware panel: deal sizes 150 (A) and 300 (B)');
        Assert.areEqual(60.00, scaled(expected.get('Software')), 'Software panel: deal sizes 20 (A) and 100 (C)');

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 4;
        BoardChartQuery.ChartResult result = query(request);
        Assert.areEqual('CURSOR', result.mode);
        while (!result.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.cursor);
            next.put('offset', result.nextOffset);
            next.put('partialState', result.partialState);
            result = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }
        assertSameValues(expected, valuesByPanel(result));
    }
    @IsTest
    static void metricAveragesPerRecordWithAndWithoutACondition() {
        Map<String, Object> request = new Map<String, Object>{
            'objectApiName' => 'OpportunityLineItem',
            'measures' => new List<Object>{
                perRecord('SUM', 'TotalPrice'),
                hidden(withCondition(perRecord('SUM', 'TotalPrice'), familyIs('Hardware')))
            }
        };

        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(request));

        Assert.areEqual('AVG_PER', result.aggregateFunction);
        Assert.areEqual(190.00, scaled((Decimal) result.value), 'Deal sizes 170, 300 and 100');
        Assert.areEqual(225.00, scaled((Decimal) result.measures[1].value), 'Hardware lines: 150 and 300');
    }

    @IsTest
    static void metricCursorChunksMergeIntoTheSameAverage() {
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 4;
        Map<String, Object> measure = perRecord('SUM', 'TotalPrice');
        Map<String, Object> request = new Map<String, Object>{
            'objectApiName' => 'OpportunityLineItem',
            'measures' => new List<Object>{ measure }
        };

        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(request));
        Assert.areEqual('CURSOR', result.mode);
        BoardQueryService.AggregateChunk chunk = result.chunk;
        Decimal sum = 0;
        Integer count = 0;
        while (true) {
            for (BoardChartEngine.Partial bucket : chunk.buckets) {
                sum += bucket.sum;
                count += bucket.count;
            }
            if (chunk.isComplete) {
                break;
            }
            Map<String, Object> next = measure.clone();
            next.put('objectApiName', 'OpportunityLineItem');
            next.put('cursor', chunk.cursor);
            next.put('offset', chunk.nextOffset);
            chunk = BoardQueryService.fetchAggregateChunk(JSON.serialize(next));
        }
        Assert.areEqual(3, count, 'One value per Opportunity with lines');
        Assert.areEqual(190.00, scaled(sum / count));
    }

    @IsTest
    static void dataProviderPartialsMergeAsOneValuePerRecord() {
        Map<String, Object> request = chartRequest(new List<Object>{ perRecord('SUM', 'TotalPrice') });
        request.put('dataProvider', PROVIDER);

        Map<String, Decimal> values = valuesByLabel(query(request));

        Assert.areEqual(
            350,
            scaled(values.get('Hardware|0')),
            '(150 + 300 + 600) / 3 records, not an average of averages'
        );
        Assert.areEqual(60.00, scaled(values.get('Software|0')));
    }

    @IsTest
    static void configErrorsAreReadable() {
        Map<String, Object> noPerField = perRecord('SUM', 'TotalPrice');
        noPerField.remove('perField');
        expectConfigError(chartRequest(new List<Object>{ noPerField }), 'per-record field');

        Map<String, Object> notALookup = perRecord('SUM', 'TotalPrice');
        notALookup.put('perField', 'Quantity');
        expectConfigError(chartRequest(new List<Object>{ notALookup }), 'lookup');

        Map<String, Object> otherRecord = perRecord('SUM', 'TotalPrice');
        otherRecord.put('perField', 'Product2Id');
        expectConfigError(
            chartRequest(new List<Object>{ perRecord('SUM', 'TotalPrice'), otherRecord }),
            'same per-record field'
        );

        Map<String, Object> bucketed = chartRequest(new List<Object>{ perRecord('SUM', 'TotalPrice') });
        bucketed.put('groupByField', 'bucket:size');
        bucketed.put(
            'bucketFields',
            new List<Object>{
                new Map<String, Object>{
                    'id' => 'size',
                    'label' => 'Size',
                    'rules' => new List<Object>{
                        new Map<String, Object>{
                            'label' => 'Large',
                            'condition' => new Map<String, Object>{
                                'id' => 'large',
                                'fieldPath' => 'TotalPrice',
                                'operator' => 'GTE',
                                'value' => 100
                            }
                        }
                    }
                }
            }
        );
        expectConfigError(bucketed, 'Bucket field');
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    private static Map<String, Object> chartRequest(List<Object> measures) {
        return new Map<String, Object>{
            'objectApiName' => 'OpportunityLineItem',
            'groupByField' => 'Product2.Family',
            'measures' => measures
        };
    }

    private static Map<String, Object> perRecord(String innerMode, String valueField) {
        return new Map<String, Object>{
            'aggregateFunction' => 'AVG_PER',
            'perField' => 'OpportunityId',
            'inner' => innerMode,
            'valueFieldApiName' => valueField
        };
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        return new Map<String, Object>{ 'aggregateFunction' => aggregateFunction, 'valueFieldApiName' => valueField };
    }

    private static Map<String, Object> withCondition(Map<String, Object> measure, Map<String, Object> condition) {
        measure.put('condition', condition);
        return measure;
    }

    private static Map<String, Object> hidden(Map<String, Object> measure) {
        measure.put('hidden', true);
        return measure;
    }

    private static Map<String, Object> probabilityAtLeast(Decimal probability) {
        return tree('Opportunity.Probability', 'GTE', probability);
    }

    private static Map<String, Object> familyIs(String family) {
        return tree('Product2.Family', 'EQ', family);
    }

    private static Map<String, Object> tree(String fieldPath, String operator, Object value) {
        return new Map<String, Object>{
            'logic' => 'AND',
            'conditions' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'ap-' + fieldPath,
                    'fieldPath' => fieldPath,
                    'operator' => operator,
                    'value' => value
                }
            }
        };
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
            values.put(labels.get(point.categoryKey) + '|' + point.measureIndex, point.value);
        }
        return values;
    }

    /** Point values keyed by Panel (one category per Panel). */
    private static Map<String, Decimal> valuesByPanel(BoardChartQuery.ChartResult result) {
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            values.put(point.panelKey, point.value);
        }
        return values;
    }
    private static void assertSameValues(Map<String, Decimal> expected, Map<String, Decimal> actual) {
        Assert.areEqual(expected.keySet(), actual.keySet());
        for (String key : expected.keySet()) {
            Assert.areEqual(scaled(expected.get(key)), scaled(actual.get(key)), 'Cursor matches SOQL: ' + key);
        }
    }

    private static Decimal scaled(Decimal value) {
        return value == null ? null : value.setScale(2);
    }

    private static void expectConfigError(Map<String, Object> request, String fragment) {
        try {
            query(request);
            Assert.fail('Expected a config error');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), String.valueOf(payload));
            Assert.isTrue(String.valueOf(payload.get('message')).contains(fragment), String.valueOf(payload));
        }
    }

    private static Opportunity opportunity(String name, Decimal probability, String stage, Id pricebookId) {
        return new Opportunity(
            Name = name,
            CloseDate = Date.today(),
            StageName = stage,
            Probability = probability,
            Pricebook2Id = pricebookId
        );
    }

    private static Map<String, Object> perAccount(String innerMode) {
        return new Map<String, Object>{
            'aggregateFunction' => 'AVG_PER',
            'perField' => 'AccountId',
            'inner' => innerMode,
            'valueFieldApiName' => 'Amount'
        };
    }

    private static Opportunity accountOpportunity(String name, Id accountId, Decimal amount, String stage) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            Amount = amount,
            CloseDate = Date.today(),
            StageName = stage
        );
    }

    private static OpportunityLineItem line(Opportunity opportunity, PricebookEntry entry, Decimal totalPrice) {
        return new OpportunityLineItem(
            OpportunityId = opportunity.Id,
            PricebookEntryId = entry.Id,
            Quantity = 1,
            TotalPrice = totalPrice
        );
    }
}