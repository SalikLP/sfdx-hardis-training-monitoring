/**
 * Entry-point seam for Widget-level Bucket fields on the Chart query (SOQL tier): given a Bucket field and inserted
 * Opportunities, which bucket each aggregate lands in, as category or series; first match wins, fallback or excluded
 * rows; the group-by-formula error.
 */
@IsTest
private class BoardChartQueryBucketTest {
    /**
     * Opportunities: Bucket Opp 1 (100, Web) and 2 (200) on Bucket Alpha in the first stage; Bucket Opp 3 (350) and 4
     * (no Amount) on Bucket Beta in the second stage.
     */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = 'Bucket Alpha');
        Account beta = new Account(Name = 'Bucket Beta');
        insert new List<Account>{ alpha, beta };
        List<Schema.PicklistEntry> stages = Opportunity.StageName.getDescribe().getPicklistValues();
        Opportunity web = opportunity('Bucket Opp 1', alpha.Id, 100, stages[0].getValue());
        web.LeadSource = 'Web';
        insert new List<Opportunity>{
            web,
            opportunity('Bucket Opp 2', alpha.Id, 200, stages[0].getValue()),
            opportunity('Bucket Opp 3', beta.Id, 350, stages[1].getValue()),
            opportunity('Bucket Opp 4', beta.Id, null, stages[1].getValue())
        };
    }

    @IsTest
    static void eachAggregateLandsInTheFirstMatchingRulesBucketOrOther() {
        Map<String, Object> request = chartRequest('bucket:dealSize', dealSize(null));

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual('SINGLE', result.mode);
        Assert.areEqual('bucket:dealSize', result.groupBy.fieldPath);
        Assert.areEqual('BUCKET', result.groupBy.dataType);
        Assert.areEqual(new List<String>{ 'Large', 'Medium', 'Web', 'Other' }, result.groupBy.picklistOrder);
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(4, result.categories.size(), String.valueOf(values));
        Assert.areEqual(350, values.get('Large|0'), 'Opp 3 also matches Medium: the first rule wins');
        Assert.areEqual(1, values.get('Large|1'));
        Assert.areEqual(200, values.get('Medium|0'));
        Assert.areEqual(1, values.get('Medium|1'));
        Assert.areEqual(100, values.get('Web|0'), 'Opp 1 matches the OR group through its Lead source');
        Assert.areEqual(1, values.get('Web|1'));
        Assert.isNull(values.get('Other|0'), 'Opp 4 has no Amount');
        Assert.areEqual(1, values.get('Other|1'), 'Opp 4 matches no rule: the fallback bucket');
        Assert.areEqual(
            'Other',
            result.categories[3].value,
            'The fallback bucket is a category, not the "Other" roll-up'
        );
        Assert.isFalse(result.categories[3].isOther);
    }

    @IsTest
    static void excludedFallbackRowsAreLeftOutAndEveryAggregateStaysExact() {
        Map<String, Object> request = chartRequest(
            'bucket:dealSize',
            dealSize(new Map<String, Object>{ 'label' => 'Rest', 'exclude' => true })
        );
        request.put(
            'measures',
            new List<Object>{ measure('AVG', 'Amount'), measure('MIN', 'Amount'), measure('MAX', 'Amount') }
        );
        request.put('sortBy', 'PICKLIST_ORDER');

        BoardChartQuery.ChartResult result = query(request);

        List<String> labels = new List<String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            labels.add(category.label);
        }
        Assert.areEqual(new List<String>{ 'Large', 'Medium', 'Web' }, labels, 'Rule order; no fallback bucket');
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(350, values.get('Large|0'));
        Assert.areEqual(200, values.get('Medium|1'));
        Assert.areEqual(100, values.get('Web|2'));
    }

    @IsTest
    static void bucketFieldAsTheSeriesSplitsEachCategory() {
        Map<String, Object> request = chartRequest('AccountId', dealSize(null));
        request.put('stackByField', 'bucket:dealSize');
        request.put('measures', new List<Object>{ countMeasure() });

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual('bucket:dealSize', result.stackBy.fieldPath);
        Assert.areEqual(2, result.categories.size());
        Map<String, Decimal> cells = cellsByLabels(result);
        Assert.areEqual(1, cells.get('Bucket Alpha|Medium'));
        Assert.areEqual(1, cells.get('Bucket Alpha|Web'));
        Assert.areEqual(1, cells.get('Bucket Beta|Large'));
        Assert.areEqual(1, cells.get('Bucket Beta|Other'));
        Assert.areEqual(4, cells.size(), String.valueOf(cells));
    }

    @IsTest
    static void bucketCategoryWithAPlainSeriesField() {
        Map<String, Object> request = chartRequest('bucket:dealSize', dealSize(null));
        request.put('stackByField', 'AccountId');
        request.put('measures', new List<Object>{ measure('SUM', 'Amount') });

        Map<String, Decimal> cells = cellsByLabels(query(request));

        Assert.areEqual(350, cells.get('Large|Bucket Beta'));
        Assert.areEqual(200, cells.get('Medium|Bucket Alpha'));
        Assert.areEqual(100, cells.get('Web|Bucket Alpha'));
        Assert.isTrue(cells.containsKey('Other|Bucket Beta'));
        Assert.areEqual(4, cells.size(), String.valueOf(cells));
    }

    @IsTest
    static void rulesFollowTheWidgetScopeAndRulesSharingALabelShareABucket() {
        List<Object> rules = new List<Object>{
            rule('Picked', condition('LeadSource', 'EQ', 'web')),
            rule('Picked', condition('Amount', 'GTE', 300))
        };
        Map<String, Object> request = chartRequest('bucket:picked', bucketField('picked', rules, null));
        request.put(
            'baseFilters',
            new List<Object>{
                new Map<String, Object>{ 'id' => 'bf1', 'fieldPath' => 'Amount', 'operator' => 'GT', 'value' => 0 }
            }
        );

        Map<String, Decimal> values = valuesByLabel(query(request));

        Assert.areEqual(450, values.get('Picked|0'), 'Opp 1 (case-insensitive Web) and Opp 3');
        Assert.areEqual(2, values.get('Picked|1'));
        Assert.areEqual(1, values.get('Other|1'), 'Only Opp 2: the Base filter drops Opp 4');
    }

    @IsTest
    static void shareOfTotalOfABucketCategoryIsAgainstTheBucketedRows() {
        Map<String, Object> share = countMeasure();
        share.put('showAs', 'percentOfTotal');
        Map<String, Object> request = chartRequest('bucket:dealSize', dealSize(null));
        request.put('measures', new List<Object>{ share });

        Assert.areEqual(0.25, valuesByLabel(query(request)).get('Large|0'), '1 of 4 Opportunities');

        request.put('bucketFields', dealSize(new Map<String, Object>{ 'label' => 'Rest', 'exclude' => true }));
        Map<String, Decimal> values = valuesByLabel(query(request));
        Assert.areEqual(0.3333, values.get('Large|0').setScale(4), '1 of the 3 bucketed: excluded rows never count');
    }

    @IsTest
    static void shareOfTotalOfACappedBucketSeriesUsesOneUngroupedTotal() {
        // Picked = Opp 1 (Alpha) and Opp 3 (Beta); Other = Opp 2 (Alpha) and Opp 4 (Beta). A cap of 1 group per bucket
        // drops one Account from each bucket; above the cursor-tier row cap it can't re-run through cursor chunks.
        List<Object> rules = new List<Object>{
            rule('Picked', condition('LeadSource', 'EQ', 'Web')),
            rule('Picked', condition('Amount', 'GTE', 300))
        };
        Map<String, Object> share = countMeasure();
        share.put('showAs', 'percentOfTotal');
        Map<String, Object> request = chartRequest('AccountId', bucketField('picked', rules, null));
        request.put('stackByField', 'bucket:picked');
        request.put('measures', new List<Object>{ share });
        BoardQueryService.CHART_GROUP_LIMIT = 1;
        BoardQueryService.CURSOR_MAX_ROWS = 3;

        BoardChartQuery.ChartResult result = query(request);

        Assert.isTrue(result.hasMoreGroups);
        Map<String, Decimal> cells = cellsByLabels(result);
        Assert.areEqual(2, cells.size(), String.valueOf(cells));
        for (Decimal value : cells.values()) {
            Assert.areEqual(0.25, value, '1 of all 4 bucketed Opportunities, not of the 2 returned');
        }
    }

    @IsTest
    static void ruleCanReferenceACheckboxField() {
        // An Admin formula checkbox compiles like any filterable checkbox; use one when the org has it.
        String checkbox = formulaField(Schema.DisplayType.BOOLEAN);
        if (checkbox == null) {
            checkbox = 'IsClosed';
        }
        List<Object> rules = new List<Object>{ rule('Flagged', condition(checkbox, 'EQ', true)) };
        Map<String, Object> request = chartRequest('bucket:flag', bucketField('flag', rules, null));

        Map<String, Decimal> values = valuesByLabel(query(request));

        Decimal flagged = values.get('Flagged|1') == null ? 0 : values.get('Flagged|1');
        Decimal other = values.get('Other|1') == null ? 0 : values.get('Other|1');
        Assert.areEqual(4, flagged + other, 'Every Opportunity lands in exactly one bucket');
    }

    @IsTest
    static void cursorTierGivesTheSameBucketsAsTheSoqlTier() {
        // Bucket as category with every mergeable Measure; fallback "Other" holds Opp 4 (null Amount).
        Map<String, Object> category = chartRequest('bucket:dealSize', dealSize(null));
        category.put(
            'measures',
            new List<Object>{
                measure('SUM', 'Amount'),
                countMeasure(),
                measure('AVG', 'Amount'),
                measure('MIN', 'Amount'),
                measure('MAX', 'Amount')
            }
        );
        assertParity(category);

        // Excluded fallback rows are left out in both tiers.
        assertParity(
            chartRequest('bucket:dealSize', dealSize(new Map<String, Object>{ 'label' => 'Rest', 'exclude' => true }))
        );

        // Bucket as series under a plain category field.
        Map<String, Object> series = chartRequest('AccountId', dealSize(null));
        series.put('stackByField', 'bucket:dealSize');
        series.put('measures', new List<Object>{ measure('SUM', 'Amount') });
        assertParity(series);

        // Bucket as category under a plain series field.
        Map<String, Object> split = chartRequest('bucket:dealSize', dealSize(null));
        split.put('stackByField', 'AccountId');
        split.put('measures', new List<Object>{ measure('SUM', 'Amount') });
        assertParity(split);

        // Case-insensitive text, a not-equal rule that keeps empty fields, a null check, and a Base filter.
        List<Object> rules = new List<Object>{
            rule('Web', condition('LeadSource', 'EQ', 'wEB')),
            rule('No amount', condition('Amount', 'IS_NULL', true)),
            rule('Not web', condition('LeadSource', 'NEQ', 'web'))
        };
        Map<String, Object> semantics = chartRequest('bucket:sem', bucketField('sem', rules, null));
        semantics.put(
            'baseFilters',
            new List<Object>{
                new Map<String, Object>{
                    'id' => 'bf1',
                    'fieldPath' => 'Name',
                    'operator' => 'LIKE',
                    'value' => 'Bucket'
                }
            }
        );
        Map<String, Decimal> values = assertParity(semantics);
        Assert.areEqual(1, values.get('Web||1'), 'Opp 1: wEB matches Web');
        Assert.areEqual(1, values.get('No amount||1'), 'Opp 4');
        Assert.areEqual(2, values.get('Not web||1'), 'Opps 2 and 3: an empty Lead source is not web');
        Assert.isFalse(values.containsKey('Other||1'), 'Every row matched a rule');
    }

    @IsTest
    static void cursorTierRejectsCountDistinctMeasures() {
        Map<String, Object> request = chartRequest('bucket:dealSize', dealSize(null));
        request.put('measures', new List<Object>{ measure('COUNT_DISTINCT', 'Name') });
        Assert.areEqual('SINGLE', query(request).mode, 'Below the threshold COUNT_DISTINCT runs in SOQL');

        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        expectError(request, 'LIMIT_EXCEEDED');
    }

    @IsTest
    static void rejectsInvalidBucketUsage() {
        Map<String, Object> both = chartRequest('bucket:dealSize', dealSize(null));
        both.put('stackByField', 'bucket:dealSize');
        expectError(both, 'CONFIG_ERROR');

        expectError(chartRequest('bucket:missing', dealSize(null)), 'CONFIG_ERROR');

        Map<String, Object> severalMeasuresAndSeries = chartRequest('AccountId', dealSize(null));
        severalMeasuresAndSeries.put('stackByField', 'bucket:dealSize');
        expectError(severalMeasuresAndSeries, 'CONFIG_ERROR');

        List<Object> childRule = new List<Object>{
            rule('Has line', condition('OpportunityLineItems(OpportunityId).Quantity', 'GT', 0))
        };
        expectError(chartRequest('bucket:child', bucketField('child', childRule, null)), 'CONFIG_ERROR');
    }

    @IsTest
    static void groupingByAFormulaFieldPointsToBucketFields() {
        String formula = formulaField(null);
        if (formula == null) {
            // No formula field on Opportunity in this org: the message itself is covered by BoardBucketFieldTest.
            return;
        }
        Map<String, Object> payload = expectError(chartRequest(formula, new List<Object>()), 'CONFIG_ERROR');
        String message = (String) payload.get('message');
        Assert.isTrue(message.contains('Bucket field'), message);
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** Large (Amount >= 300), Medium (Amount >= 150), Web (Lead source Web OR Amount >= 1,000,000). */
    private static List<Object> dealSize(Map<String, Object> fallback) {
        Map<String, Object> webOrHuge = new Map<String, Object>{
            'logic' => 'OR',
            'conditions' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'c1',
                    'fieldPath' => 'LeadSource',
                    'operator' => 'EQ',
                    'value' => 'Web'
                },
                new Map<String, Object>{
                    'id' => 'c2',
                    'fieldPath' => 'Amount',
                    'operator' => 'GTE',
                    'value' => 1000000
                }
            }
        };
        return bucketField(
            'dealSize',
            new List<Object>{
                rule('Large', condition('Amount', 'GTE', 300)),
                rule('Medium', condition('Amount', 'GTE', 150)),
                rule('Web', webOrHuge)
            },
            fallback
        );
    }

    private static List<Object> bucketField(String id, List<Object> rules, Map<String, Object> fallback) {
        Map<String, Object> config = new Map<String, Object>{ 'id' => id, 'label' => id, 'rules' => rules };
        if (fallback != null) {
            config.put('fallback', fallback);
        }
        return new List<Object>{ config };
    }

    private static Map<String, Object> rule(String label, Map<String, Object> condition) {
        return new Map<String, Object>{ 'label' => label, 'condition' => condition };
    }

    /** A one-condition AND group, as the condition editor saves it. */
    private static Map<String, Object> condition(String fieldPath, String operator, Object value) {
        return new Map<String, Object>{
            'logic' => 'AND',
            'conditions' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'c1',
                    'fieldPath' => fieldPath,
                    'operator' => operator,
                    'value' => value
                }
            }
        };
    }

    private static Map<String, Object> chartRequest(String groupByField, List<Object> bucketFields) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => groupByField,
            'bucketFields' => bucketFields,
            'measures' => new List<Object>{ measure('SUM', 'Amount'), countMeasure() }
        };
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        return new Map<String, Object>{ 'aggregateFunction' => aggregateFunction, 'valueFieldApiName' => valueField };
    }

    private static Map<String, Object> countMeasure() {
        return new Map<String, Object>{ 'aggregateFunction' => 'COUNT' };
    }

    private static BoardChartQuery.ChartResult query(Map<String, Object> request) {
        return BoardChartQuery.queryChart(JSON.serialize(request));
    }

    /**
     * Runs `request` once through SOQL and once forced through the cursor tier (one row per chunk) and asserts the
     * same categories, series and point values; returns the points keyed `categoryLabel|seriesLabel|measureIndex`.
     */
    private static Map<String, Decimal> assertParity(Map<String, Object> request) {
        BoardChartQuery.ChartResult soql = query(request);
        Assert.areEqual('SINGLE', soql.mode);

        Integer threshold = BoardQueryService.CURSOR_AGGREGATE_THRESHOLD;
        Integer chunkSize = BoardQueryService.CURSOR_CHUNK_SIZE;
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 1;
        BoardChartQuery.ChartResult cursor = query(request);
        Assert.areEqual('CURSOR', cursor.mode);
        Assert.areEqual(soql.groupBy.fieldPath, cursor.groupBy.fieldPath);
        while (!cursor.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', cursor.cursor);
            next.put('offset', cursor.nextOffset);
            next.put('partialState', cursor.partialState);
            cursor = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = threshold;
        BoardQueryService.CURSOR_CHUNK_SIZE = chunkSize;

        Assert.areEqual(keyLabels(soql.categories), keyLabels(cursor.categories), 'Same categories in the same order');
        Assert.areEqual(keyLabels(soql.series), keyLabels(cursor.series), 'Same series in the same order');
        Map<String, Decimal> expected = pointsByLabels(soql);
        Assert.areEqual(expected, pointsByLabels(cursor), 'Cursor tier matches SOQL for ' + JSON.serialize(request));
        return expected;
    }

    private static List<String> keyLabels(List<BoardChartEngine.ChartKey> keys) {
        List<String> labels = new List<String>();
        for (BoardChartEngine.ChartKey key : keys) {
            labels.add(key.key + '=' + key.label);
        }
        return labels;
    }

    /** Point values (2 decimals) keyed `categoryLabel|seriesLabel|measureIndex`. */
    private static Map<String, Decimal> pointsByLabels(BoardChartQuery.ChartResult result) {
        Map<String, String> labels = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            labels.put('c' + category.key, category.label);
        }
        for (BoardChartEngine.ChartKey series : result.series) {
            labels.put('s' + series.key, series.label);
        }
        Map<String, Decimal> points = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            String seriesLabel = point.seriesKey == BoardChartEngine.VALUE_KEY ? '' : labels.get('s' + point.seriesKey);
            points.put(
                labels.get('c' + point.categoryKey) + '|' + seriesLabel + '|' + point.measureIndex,
                point.value == null ? null : point.value.setScale(2)
            );
        }
        return points;
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

    /** A formula field on Opportunity (of `type`, or any type when null), or null when the org has none. */
    private static String formulaField(Schema.DisplayType type) {
        for (Schema.SObjectField field : Schema.SObjectType.Opportunity.fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (
                describe.isCalculated() &&
                describe.isAccessible() &&
                describe.isFilterable() &&
                (type == null ? !describe.isGroupable() : describe.getType() == type)
            ) {
                return describe.getName();
            }
        }
        return null;
    }

    private static Map<String, Object> expectError(Map<String, Object> request, String category) {
        try {
            query(request);
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual(category, payload.get('category'), String.valueOf(payload));
            return payload;
        }
        Assert.fail('Expected ' + category + ' for ' + JSON.serialize(request));
        return null;
    }

    private static Opportunity opportunity(String name, Id accountId, Decimal amount, String stage) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            Amount = amount,
            CloseDate = Date.today(),
            StageName = stage
        );
    }
}