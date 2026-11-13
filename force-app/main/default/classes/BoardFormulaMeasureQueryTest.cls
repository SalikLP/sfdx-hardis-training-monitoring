/**
 * Formula measures at the Chart (`BoardChartQuery.queryChart`) and Metric (`BoardQueryService.queryMetric`) query
 * entry points, with inserted Opportunities: win rate `A / B` over two hidden Measures with Measure conditions (Won,
 * Closed) per category and on a Metric, divide-by-zero, a constant target drawn as a Reference line, and readable
 * config errors.
 */
@IsTest
private class BoardFormulaMeasureQueryTest {
    /**
     * Formula Alpha: Won, Lost, Lost, Lost (win rate 0.25). Formula Beta: Won, Won, Won, Lost (0.75). Formula Gamma:
     * Open only (no closed deals: blank). Every Amount is 100. Overall: 4 Won of 8 Closed (0.5).
     */
    @TestSetup
    static void setup() {
        Account alpha = new Account(Name = 'Formula Alpha');
        Account beta = new Account(Name = 'Formula Beta');
        Account gamma = new Account(Name = 'Formula Gamma');
        insert new List<Account>{ alpha, beta, gamma };
        String won = wonStage();
        String lost = lostStage();
        insert new List<Opportunity>{
            opportunity('Formula Opp 1', alpha.Id, won),
            opportunity('Formula Opp 2', alpha.Id, lost),
            opportunity('Formula Opp 3', alpha.Id, lost),
            opportunity('Formula Opp 4', alpha.Id, lost),
            opportunity('Formula Opp 5', beta.Id, won),
            opportunity('Formula Opp 6', beta.Id, won),
            opportunity('Formula Opp 7', beta.Id, won),
            opportunity('Formula Opp 8', beta.Id, lost),
            opportunity('Formula Opp 9', gamma.Id, openStage())
        };
    }

    @IsTest
    static void chartWinRateIsEvaluatedPerCategory() {
        // A hidden all-rows count keeps Formula Gamma (open deals only) a category: every other Measure has a condition.
        List<Object> measures = winRate();
        measures.add(hidden(measure('COUNT', null)));
        BoardChartQuery.ChartResult result = BoardChartQuery.queryChart(JSON.serialize(chartRequest(measures)));

        Assert.areEqual(new List<String>{ 'COUNT', 'COUNT', 'FORMULA', 'COUNT' }, result.aggregateFunctions);
        Assert.isNull(result.currencyIsoCodes[2], 'A win rate is not an amount');
        Map<String, Decimal> values = valuesByLabel(result);
        Assert.areEqual(0.25, values.get('Formula Alpha|2'), '1 Won / 4 Closed');
        Assert.areEqual(0.75, values.get('Formula Beta|2'), '3 Won / 4 Closed');
        Assert.isTrue(values.containsKey('Formula Gamma|2'), 'The blank value is still a point');
        Assert.isNull(values.get('Formula Gamma|2'), 'No closed deals: division by zero is blank');
        Assert.areEqual(3, values.get('Formula Beta|0'), 'Hidden inputs are still returned');
        Assert.areEqual(4, values.get('Formula Beta|1'));
    }

    @IsTest
    static void chartConstantFormulaDrawsOneValuePerCategoryAndAsAReferenceLine() {
        Map<String, Object> target = formula('15000');
        BoardChartQuery.ChartResult perCategory = BoardChartQuery.queryChart(
            JSON.serialize(chartRequest(new List<Object>{ measure('SUM', 'Amount'), target }))
        );
        Map<String, Decimal> values = valuesByLabel(perCategory);
        Assert.areEqual(15000, values.get('Formula Alpha|1'));
        Assert.areEqual(15000, values.get('Formula Gamma|1'));

        target.put('render', BoardChartQuery.REFERENCE_LINE_RENDER);
        List<Object> measures = winRate();
        measures.add(target);
        BoardChartQuery.ChartResult referenceLines = BoardChartQuery.queryChart(JSON.serialize(chartRequest(measures)));
        Assert.areEqual(15000, referenceLines.overallValues[3], 'The constant target line');
        Assert.isNull(referenceLines.overallValues[2], 'The per-category win rate is not a Reference line');
    }

    @IsTest
    static void chartWinRateReferenceLineUsesTheOverallInputs() {
        List<Object> measures = winRate();
        ((Map<String, Object>) measures[2]).put('render', BoardChartQuery.REFERENCE_LINE_RENDER);

        BoardChartQuery.ChartResult result = BoardChartQuery.queryChart(JSON.serialize(chartRequest(measures)));

        Assert.areEqual(0.5, result.overallValues[2], '4 Won / 8 Closed overall, not a sum of category rates');
        Assert.isNull(result.overallValues[0], 'Hidden inputs are not drawn as Reference lines');
    }

    @IsTest
    static void chartFormulaErrorsAreReadableConfigErrors() {
        Map<String, Object> series = chartRequest(new List<Object>{ formula('15000') });
        series.put('stackByField', 'StageName');
        Assert.isTrue(chartError(series).contains('series field'));

        String nested = chartError(
            chartRequest(new List<Object>{ measure('COUNT', null), formula('A * 2'), formula('B + 1') })
        );
        Assert.isTrue(nested.contains('another Formula measure'), nested);

        String syntax = chartError(chartRequest(new List<Object>{ measure('COUNT', null), formula('A / ') }));
        Assert.isTrue(syntax.startsWith('Measure 2 (B) formula: '), syntax);
    }

    @IsTest
    static void metricWinRateOverHiddenMeasures() {
        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(metricRequest(winRate())));

        Assert.areEqual('FORMULA', result.aggregateFunction);
        Assert.areEqual(0.5, toDecimal(result.value), '4 Won / 8 Closed');
        Assert.isTrue(result.isComplete);
        Assert.areEqual(2, result.visibleIndex);
        Assert.areEqual(4, toDecimal(result.measures[0].value));
        Assert.areEqual(8, toDecimal(result.measures[1].value));
    }

    @IsTest
    static void metricFormulaWithCursorInputIsFinishedByTheClient() {
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 2;
        // Won share of the closed amount: both inputs are SUMs, so both use the cursor tier.
        List<Object> measures = new List<Object>{
            hidden(withCondition(measure('SUM', 'Amount'), condition('IsWon'))),
            hidden(withCondition(measure('SUM', 'Amount'), condition('IsClosed'))),
            formula('A / B')
        };

        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(JSON.serialize(metricRequest(measures)));

        Assert.areEqual('CURSOR', result.measures[0].mode, 'The hidden Won input is on the cursor tier');
        Assert.isFalse(result.isComplete, 'The formula waits for its cursor inputs');
        Assert.isNull(result.value);

        Map<String, Object> evaluate = metricRequest(measures);
        evaluate.put('values', new List<Object>{ 400, 800, null });
        Assert.areEqual(0.5, BoardFormulaMeasures.evaluateMetric(JSON.serialize(evaluate)));
    }

    @IsTest
    static void metricConstantFormulaNeedsNoInputs() {
        BoardQueryService.MetricResult result = BoardQueryService.queryMetric(
            JSON.serialize(metricRequest(new List<Object>{ formula('15000') }))
        );

        Assert.areEqual(15000, toDecimal(result.value));
        Assert.isNotNull(result.appliedFilterIds);
    }

    /** Hidden Won count (A), hidden Closed count (B), visible `A / B`. */
    private static List<Object> winRate() {
        return new List<Object>{
            hidden(withCondition(measure('COUNT', null), condition('IsWon'))),
            hidden(withCondition(measure('COUNT', null), condition('IsClosed'))),
            formula('A / B')
        };
    }

    private static Map<String, Object> chartRequest(List<Object> measures) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => 'AccountId',
            'measures' => measures
        };
    }

    private static Map<String, Object> metricRequest(List<Object> measures) {
        return new Map<String, Object>{ 'objectApiName' => 'Opportunity', 'measures' => measures };
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        return new Map<String, Object>{ 'aggregateFunction' => aggregateFunction, 'valueFieldApiName' => valueField };
    }

    private static Map<String, Object> hidden(Map<String, Object> measure) {
        measure.put('hidden', true);
        return measure;
    }

    private static Map<String, Object> withCondition(Map<String, Object> measure, Map<String, Object> tree) {
        measure.put('condition', tree);
        return measure;
    }

    /** A Measure condition `<checkbox field> = true`. */
    private static Map<String, Object> condition(String fieldPath) {
        return new Map<String, Object>{
            'logic' => 'AND',
            'conditions' => new List<Object>{
                new Map<String, Object>{
                    'id' => 'fm-' + fieldPath,
                    'fieldPath' => fieldPath,
                    'operator' => 'EQ',
                    'value' => true
                }
            }
        };
    }

    private static Map<String, Object> formula(String text) {
        return new Map<String, Object>{ 'aggregateFunction' => 'FORMULA', 'formula' => text };
    }

    private static String chartError(Map<String, Object> request) {
        try {
            BoardChartQuery.queryChart(JSON.serialize(request));
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual(BoardErrors.CONFIG_ERROR, payload.get('category'), String.valueOf(payload));
            return String.valueOf(payload.get('message'));
        }
        Assert.fail('Expected a config error for ' + JSON.serialize(request));
        return null;
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

    private static Decimal toDecimal(Object value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
    }

    private static String wonStage() {
        return [SELECT ApiName FROM OpportunityStage WHERE IsActive = TRUE AND IsClosed = TRUE AND IsWon = TRUE LIMIT 1]
        .ApiName;
    }

    private static String lostStage() {
        return [
            SELECT ApiName
            FROM OpportunityStage
            WHERE IsActive = TRUE AND IsClosed = TRUE AND IsWon = FALSE
            LIMIT 1
        ]
        .ApiName;
    }

    private static String openStage() {
        return [SELECT ApiName FROM OpportunityStage WHERE IsActive = TRUE AND IsClosed = FALSE LIMIT 1].ApiName;
    }

    private static Opportunity opportunity(String name, Id accountId, String stage) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            Amount = 100,
            CloseDate = Date.today(),
            StageName = stage
        );
    }
}