/**
 * Entry-point seam for the Bucket filter: a Filter widget filter over a Bucket field's labels. Selecting bucket `i`
 * keeps `rule_i AND NOT(earlier rules)`, OR'd across selections; the fallback ("Other") keeps `NOT(every rule)`. So
 * filtering by buckets keeps exactly the rows grouping by the Bucket field puts in them, in the SOQL tier and the cursor
 * tier alike. Filter bindings map the filter per Widget to a Bucket field (`bucket:<id>`) that fits its object.
 *
 * Rules use non-currency fields (text and a parent path), so their meaning doesn't depend on currency conversion.
 */
@IsTest
private class BoardQueryServiceBucketFilterTest {
    private static final String PREFIX = 'BktF ';

    /**
     * Opp 1: Alpha, Call -> Call; Opp 2: Alpha, no next step -> Other; Opp 3: Beta, Call -> Call (first rule wins);
     * Opp 4: Beta, no next step -> Beta; Opp 5: Alpha, Email -> Other.
     */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = PREFIX + 'Alpha');
        Account beta = new Account(Name = PREFIX + 'Beta');
        insert new List<Account>{ alpha, beta };
        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        insert new List<Opportunity>{
            opportunity('Opp 1', alpha.Id, 'Call', stage),
            opportunity('Opp 2', alpha.Id, null, stage),
            opportunity('Opp 3', beta.Id, 'Call', stage),
            opportunity('Opp 4', beta.Id, null, stage),
            opportunity('Opp 5', alpha.Id, 'Email', stage)
        };
    }

    @IsTest
    static void eachBucketSelectionKeepsTheRowsGroupingPutsInThatBucket() {
        Map<String, Decimal> grouped = countsByCategory(query(chartRequest('bucket:next', null)));
        Assert.areEqual(new Map<String, Decimal>{ 'Call' => 2, 'Beta' => 1, 'Other' => 2 }, grouped);

        for (String bucketLabel : grouped.keySet()) {
            Map<String, Object> request = chartRequest('bucket:next', bucketFilter(new List<String>{ bucketLabel }));
            BoardChartQuery.ChartResult result = query(request);
            Assert.areEqual(new List<String>{ 'size' }, result.appliedFilterIds);
            Assert.areEqual(
                new Map<String, Decimal>{ bucketLabel => grouped.get(bucketLabel) },
                countsByCategory(result),
                bucketLabel
            );
        }
    }

    @IsTest
    static void selectingABucketKeepsItsRowsOnly() {
        Assert.areEqual(new Set<String>{ 'Opp 1', 'Opp 3' }, names(new List<String>{ 'Call' }));
        Assert.areEqual(new Set<String>{ 'Opp 4' }, names(new List<String>{ 'Beta' }), 'Opp 3 matched Call first');
        Assert.areEqual(
            new Set<String>{ 'Opp 2', 'Opp 5' },
            names(new List<String>{ 'Other' }),
            'Other: no rule matches, including a row with no next step'
        );
    }

    @IsTest
    static void severalSelectedBucketsOrTogether() {
        Assert.areEqual(new Set<String>{ 'Opp 2', 'Opp 4', 'Opp 5' }, names(new List<String>{ 'Beta', 'Other' }));
    }

    @IsTest
    static void aLabelTheBucketFieldNoLongerHasKeepsNoRows() {
        Assert.areEqual(new Set<String>(), names(new List<String>{ 'Renamed' }));
    }

    @IsTest
    static void excludedFallbackLeavesOtherRowsOutOfEverySelection() {
        Map<String, Object> filter = bucketFilter(new List<String>{ 'Call', 'Beta', 'Other' });
        ((Map<String, Object>) filter.get('bucketField')).put('fallback', new Map<String, Object>{ 'exclude' => true });

        Assert.areEqual(
            new Set<String>{ PREFIX + 'Opp 1', PREFIX + 'Opp 3', PREFIX + 'Opp 4' },
            categoryLabels(query(chartRequest('Name', filter)))
        );
    }

    @IsTest
    static void cursorTierKeepsTheSameRows() {
        Map<String, Object> request = chartRequest('bucket:next', bucketFilter(new List<String>{ 'Beta', 'Other' }));
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

        Assert.areEqual(new Map<String, Decimal>{ 'Beta' => 1, 'Other' => 2 }, countsByCategory(soql));
        Assert.areEqual(countsByCategory(soql), countsByCategory(cursor));
        Assert.areEqual(sumsByCategory(soql), sumsByCategory(cursor));
    }

    @IsTest
    static void conventionBindingOnAWidgetWhoseObjectTheRulesDontFitIsIgnored() {
        Map<String, Object> request = accountRequest(bucketFilter(new List<String>{ 'Beta' }));

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual(new List<String>{ 'size' }, result.ignoredFilterIds);
        Assert.areEqual(new Set<String>{ PREFIX + 'Alpha', PREFIX + 'Beta' }, categoryLabels(result));
    }

    @IsTest
    static void filterBindingMapsTheFilterToABucketFieldOfTheWidgetsObject() {
        // The Account Widget binds the filter to a Bucket field with the same labels over Account fields.
        Map<String, Object> filter = bucketFilter(new List<String>{ 'Other' });
        filter.put('fieldPath', 'bucket:accountNext');
        filter.put('explicit', true);
        filter.put(
            'bucketField',
            bucketField('accountNext', new List<Object>{ rule('Beta', 'Name', 'EQ', PREFIX + 'Beta') })
        );

        BoardChartQuery.ChartResult result = query(accountRequest(filter));

        Assert.areEqual(new List<String>{ 'size' }, result.appliedFilterIds);
        Assert.areEqual(new Set<String>{ PREFIX + 'Alpha' }, categoryLabels(result));
    }

    @IsTest
    static void explicitBindingWhoseRulesDontFitTheWidgetIsAConfigError() {
        Map<String, Object> filter = bucketFilter(new List<String>{ 'Beta' });
        filter.put('explicit', true);

        try {
            query(accountRequest(filter));
            Assert.fail('Expected a config error for Bucket rules on fields the Account Widget lacks');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), error.getMessage());
        }
    }

    @IsTest
    static void bucketFilterWithoutItsBucketFieldIsAConfigErrorWhenExplicit() {
        Map<String, Object> filter = bucketFilter(new List<String>{ 'Beta' });
        filter.remove('bucketField');
        filter.put('explicit', true);

        try {
            query(chartRequest('Name', filter));
            Assert.fail('Expected a config error for a Bucket filter without its Bucket field');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), error.getMessage());
            Assert.areEqual('size', payload.get('filterId'));
        }
    }

    @IsTest
    static void metricCountsTheSelectedBucketsRows() {
        Map<String, Object> request = new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'aggregateFunction' => 'COUNT',
            'baseFilters' => nameBaseFilter(),
            'filters' => new List<Object>{ bucketFilter(new List<String>{ 'Other' }) }
        };

        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(request));

        Assert.areEqual(2, Integer.valueOf(result.value));
    }

    @IsTest
    static void selectionEvaluatesInMemoryWithTheSameBuckets() {
        BoardBucketField nextBucket = new BoardBucketField(
            'next',
            'Next',
            new List<BoardBucketField.Rule>{
                new BoardBucketField.Rule(
                    'Call',
                    BoardCondition.field('r1', 'NextStep', 'EQ', new List<Object>{ 'Call' })
                ),
                new BoardBucketField.Rule(
                    'Beta',
                    BoardCondition.field('r2', 'Account.Name', 'EQ', new List<Object>{ PREFIX + 'Beta' })
                )
            },
            null,
            false
        );
        BoardBucketField.Selection other = nextBucket.selection('size', new Set<String>{ 'Other', 'Renamed' });

        Assert.areEqual(new List<String>{ 'Other' }, other.labels());
        Assert.isTrue(
            other.evaluate(new Map<String, Object>{ 'NextStep' => null, 'Account.Name' => PREFIX + 'Alpha' })
        );
        Assert.isFalse(
            other.evaluate(new Map<String, Object>{ 'NextStep' => 'call', 'Account.Name' => PREFIX + 'Beta' })
        );
        BoardBucketField.Selection beta = nextBucket.selection('size', new Set<String>{ 'Beta' });
        Assert.isTrue(
            beta.evaluate(new Map<String, Object>{ 'NextStep' => 'Email', 'Account.Name' => PREFIX + 'Beta' })
        );
        Assert.isFalse(
            beta.evaluate(new Map<String, Object>{ 'NextStep' => 'Call', 'Account.Name' => PREFIX + 'Beta' })
        );
        Assert.areEqual('Id = null', nextBucket.selection('size', new Set<String>{ 'Renamed' }).toSoql(null));
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    /** "Call" (next step is Call), then "Beta" (Account Beta), fallback "Other". */
    private static Map<String, Object> bucketFilter(List<String> selectedLabels) {
        return new Map<String, Object>{
            'filterId' => 'size',
            'type' => 'BUCKET',
            'fieldPath' => 'bucket:next',
            'explicit' => false,
            'operator' => 'IN',
            'values' => selectedLabels,
            'bucketField' => bucketField(
                'next',
                new List<Object>{
                    rule('Call', 'NextStep', 'EQ', 'call'),
                    rule('Beta', 'Account.Name', 'EQ', PREFIX + 'Beta')
                }
            )
        };
    }

    private static Map<String, Object> bucketField(String id, List<Object> rules) {
        return new Map<String, Object>{ 'id' => id, 'label' => 'Next', 'rules' => rules };
    }

    private static Map<String, Object> rule(String ruleLabel, String fieldPath, String operator, Object value) {
        return new Map<String, Object>{
            'label' => ruleLabel,
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

    private static List<Object> nameBaseFilter() {
        return new List<Object>{
            new Map<String, Object>{ 'id' => 'bf1', 'fieldPath' => 'Name', 'operator' => 'LIKE', 'value' => PREFIX }
        };
    }

    /** Opportunities grouped by `groupByField` (a field, or `bucket:next`): Count, then Sum of Probability (every Opp has 10). */
    private static Map<String, Object> chartRequest(String groupByField, Map<String, Object> filter) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => groupByField,
            'baseFilters' => nameBaseFilter(),
            'filters' => filter == null ? new List<Object>() : new List<Object>{ filter },
            // The Board-level Bucket field a `bucket:next` Group by uses (the filter's own, as the Filter widget has it).
            'boardBucketFields' => new List<Object>{ bucketFilter(new List<String>()).get('bucketField') },
            'measures' => new List<Object>{
                new Map<String, Object>{ 'aggregateFunction' => 'COUNT' },
                new Map<String, Object>{ 'aggregateFunction' => 'SUM', 'valueFieldApiName' => 'Probability' }
            }
        };
    }

    /** Accounts grouped by Name. */
    private static Map<String, Object> accountRequest(Map<String, Object> filter) {
        return new Map<String, Object>{
            'objectApiName' => 'Account',
            'groupByField' => 'Name',
            'baseFilters' => nameBaseFilter(),
            'filters' => new List<Object>{ filter },
            'measures' => new List<Object>{ new Map<String, Object>{ 'aggregateFunction' => 'COUNT' } }
        };
    }

    private static Set<String> names(List<String> selectedLabels) {
        Set<String> found = new Set<String>();
        for (String category : categoryLabels(query(chartRequest('Name', bucketFilter(selectedLabels))))) {
            found.add(category.removeStart(PREFIX));
        }
        return found;
    }

    private static BoardChartQuery.ChartResult query(Map<String, Object> request) {
        return BoardChartQuery.queryChart(JSON.serialize(request));
    }

    private static Set<String> categoryLabels(BoardChartQuery.ChartResult result) {
        Set<String> labels = new Set<String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            labels.add(category.label);
        }
        return labels;
    }

    private static Map<String, Decimal> countsByCategory(BoardChartQuery.ChartResult result) {
        return valuesByCategory(result, 0);
    }

    private static Map<String, Decimal> sumsByCategory(BoardChartQuery.ChartResult result) {
        return valuesByCategory(result, 1);
    }

    /** Measure `measureIndex`'s non-empty point values keyed by category label. */
    private static Map<String, Decimal> valuesByCategory(BoardChartQuery.ChartResult result, Integer measureIndex) {
        Map<String, String> labels = new Map<String, String>();
        for (BoardChartEngine.ChartKey category : result.categories) {
            labels.put(category.key, category.label);
        }
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : result.points) {
            if (point.measureIndex == measureIndex && point.value != null && point.value != 0) {
                values.put(labels.get(point.categoryKey), point.value.setScale(0));
            }
        }
        return values;
    }

    private static Opportunity opportunity(String name, Id accountId, String nextStep, String stage) {
        return new Opportunity(
            Name = PREFIX + name,
            AccountId = accountId,
            NextStep = nextStep,
            StageName = stage,
            Probability = 10,
            CloseDate = Date.today()
        );
    }
}