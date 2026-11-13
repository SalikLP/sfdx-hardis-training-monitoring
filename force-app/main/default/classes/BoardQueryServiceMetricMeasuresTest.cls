/**
 * Metric widget Measures list at the Metric query entry point (`BoardQueryService.queryMetric`): one value per
 * Measure (hidden included), exactly one visible Measure, and legacy single-aggregate requests.
 */
@IsTest
private class BoardQueryServiceMetricMeasuresTest {
    /** Opportunities with Amounts 100, 200, 350 and null: SUM 650, MAX 350, COUNT 4. */
    @TestSetup
    static void setup() {
        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        insert new List<Opportunity>{
            opportunity('Metric Opp 1', 100, stage),
            opportunity('Metric Opp 2', 200, stage),
            opportunity('Metric Opp 3', 350, stage),
            opportunity('Metric Opp 4', null, stage)
        };
    }

    @IsTest
    static void returnsOneValuePerMeasureHiddenIncludedAndShowsTheVisibleOne() {
        BoardQueryService.MetricResult result = run(
            metricRequest(
                new List<Object>{
                    hidden(measure('SUM', 'Amount')),
                    measure('COUNT', null),
                    hidden(measure('MAX', 'Amount'))
                }
            )
        );

        Assert.areEqual(3, result.measures.size(), 'One result per Measure, hidden included');
        Assert.areEqual('SUM', result.measures[0].aggregateFunction);
        Assert.areEqual(650, toDecimal(result.measures[0].value));
        Assert.areEqual('CURRENCY', result.measures[0].valueType);
        Assert.areEqual(4, toDecimal(result.measures[1].value));
        Assert.areEqual(350, toDecimal(result.measures[2].value));
        Assert.areEqual(1, result.visibleIndex);
        Assert.areEqual('COUNT', result.aggregateFunction, 'The Widget result is the visible Measure');
        Assert.areEqual(4, toDecimal(result.value));
        Assert.areEqual('SINGLE', result.mode);
        Assert.isNull(result.measures[0].measures, 'Measure results do not nest');
    }

    @IsTest
    static void requiresExactlyOneVisibleMeasureAndAtMostSix() {
        Map<String, Object> noneVisible = expectError(
            metricRequest(new List<Object>{ hidden(measure('COUNT', null)), hidden(measure('SUM', 'Amount')) })
        );
        Assert.areEqual('measures', noneVisible.get('fieldPath'));
        Assert.isTrue(String.valueOf(noneVisible.get('message')).contains('exactly one'), noneVisible.toString());

        Map<String, Object> twoVisible = expectError(
            metricRequest(new List<Object>{ measure('COUNT', null), measure('SUM', 'Amount') })
        );
        Assert.areEqual('measures', twoVisible.get('fieldPath'));
        Assert.isTrue(String.valueOf(twoVisible.get('message')).contains('exactly one'), twoVisible.toString());

        List<Object> seven = new List<Object>{ measure('COUNT', null) };
        for (Integer i = 0; i < 6; i++) {
            seven.add(hidden(measure('COUNT', null)));
        }
        Assert.areEqual('measures', expectError(metricRequest(seven)).get('fieldPath'), 'Max 6 Measures');
        Assert.areEqual('measures', expectError(metricRequest(new List<Object>())).get('fieldPath'));
        Map<String, Object> notObject = metricRequest(new List<Object>{ 'COUNT' });
        Assert.areEqual('measures', expectError(notObject).get('fieldPath'));
    }

    @IsTest
    static void rejectsShareOfTotalWhichIsChartOnly() {
        Map<String, Object> share = measure('SUM', 'Amount');
        share.put('showAs', 'percentOfTotal');
        Assert.areEqual('measures', expectError(metricRequest(new List<Object>{ share })).get('fieldPath'));
    }

    @IsTest
    static void validatesHiddenMeasuresLikeVisibleOnes() {
        expectError(metricRequest(new List<Object>{ measure('COUNT', null), hidden(measure('SUM', 'Name')) }));
        expectError(metricRequest(new List<Object>{ measure('COUNT', null), hidden(measure('MEDIAN', 'Amount')) }));
        expectError(metricRequest(new List<Object>{ measure('COUNT', null), hidden(measure('SUM', null)) }));
    }

    @IsTest
    static void legacySingleAggregateRequestKeepsRenderingTheSameNumber() {
        Map<String, Object> request = new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'aggregateFunction' => 'SUM',
            'valueFieldApiName' => 'Amount'
        };

        BoardQueryService.MetricResult result = run(request);

        Assert.areEqual('SUM', result.aggregateFunction);
        Assert.areEqual(650, toDecimal(result.value));
        Assert.areEqual(1, result.measures.size());
        Assert.areEqual(0, result.visibleIndex);
    }

    @IsTest
    static void eachMeasureUsesItsOwnTierAndTheWidgetResultFollowsTheVisibleOne() {
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;

        BoardQueryService.MetricResult countVisible = run(
            metricRequest(new List<Object>{ hidden(measure('SUM', 'Amount')), measure('COUNT', null) })
        );
        Assert.areEqual('CURSOR', countVisible.measures[0].mode, 'A large hidden SUM opens its own cursor');
        Assert.isNotNull(countVisible.measures[0].chunk);
        Assert.areEqual('SINGLE', countVisible.mode);
        Assert.areEqual(4, toDecimal(countVisible.value));

        BoardQueryService.MetricResult sumVisible = run(
            metricRequest(new List<Object>{ measure('SUM', 'Amount'), hidden(measure('COUNT', null)) })
        );
        Assert.areEqual('CURSOR', sumVisible.mode, 'The client continues the visible Measure cursor');
        Assert.isTrue(sumVisible.isComplete, 'The first chunk already holds every row');
        Assert.areEqual(4, sumVisible.chunk.totalRows);
        Assert.areEqual(4, toDecimal(sumVisible.measures[1].value));
    }

    @IsTest
    static void bindingOutcomeIsReportedOnce() {
        Map<String, Object> request = metricRequest(
            new List<Object>{ measure('COUNT', null), hidden(measure('SUM', 'Amount')) }
        );
        request.put(
            'filters',
            new List<Object>{
                new Map<String, Object>{
                    'filterId' => 'region',
                    'type' => 'PICKLIST',
                    'fieldPath' => 'IGNORE',
                    'operator' => 'IN',
                    'values' => new List<Object>{ 'EMEA' },
                    'explicit' => true
                }
            }
        );

        BoardQueryService.MetricResult result = run(request);

        Assert.areEqual(new List<String>{ 'region' }, result.ignoredFilterIds);
        Assert.areEqual(4, toDecimal(result.value));
    }

    private static Map<String, Object> metricRequest(List<Object> measures) {
        return new Map<String, Object>{ 'objectApiName' => 'Opportunity', 'measures' => measures };
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        Map<String, Object> measure = new Map<String, Object>{ 'aggregateFunction' => aggregateFunction };
        if (valueField != null) {
            measure.put('valueFieldApiName', valueField);
        }
        return measure;
    }

    private static Map<String, Object> hidden(Map<String, Object> measure) {
        measure.put('hidden', true);
        return measure;
    }

    private static BoardQueryService.MetricResult run(Map<String, Object> request) {
        return BoardQueryService.queryMetric(JSON.serialize(request));
    }

    private static Decimal toDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }

    private static Map<String, Object> expectError(Map<String, Object> request) {
        try {
            run(request);
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), String.valueOf(payload));
            return payload;
        }
        Assert.fail('Expected CONFIG_ERROR for ' + JSON.serialize(request));
        return null;
    }

    private static Opportunity opportunity(String name, Decimal amount, String stage) {
        return new Opportunity(Name = name, Amount = amount, CloseDate = Date.today(), StageName = stage);
    }
}