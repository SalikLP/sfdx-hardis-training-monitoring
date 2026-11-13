/**
 * Formula measures over a Widget's Measures list (`BoardFormulaMeasures`), fed with in-memory grouped values:
 * config validation (nested Formula measures, series field, unknown slots), per-category evaluation on the Chart
 * widget's grouped rows, and the Metric widget's results.
 */
@IsTest
private class BoardFormulaMeasuresTest {
    @IsTest
    static void chartRowsGetOneFormulaValuePerCategory() {
        Map<String, Object> request = new Map<String, Object>{
            'measures' => new List<Object>{ measure('COUNT', null), formula('C / A'), hiddenMeasure('SUM', 'Amount') }
        };
        BoardFormulaMeasures.ChartPlan plan = BoardFormulaMeasures.forChart(request);
        List<Object> scanned = (List<Object>) request.get('measures');
        Assert.areEqual(2, scanned.size(), 'Only aggregate Measures are queried');

        BoardChartQuery.ChartResult result = new BoardChartQuery.ChartResult();
        result.aggregateFunctions = new List<String>{ 'COUNT', 'SUM' };
        result.valueTypes = new List<String>{ null, 'CURRENCY' };
        result.accumulator = new BoardChartEngine.Accumulator(2);
        result.accumulator.put('a', 'Acme', null, null, new List<Object>{ 4, 1000 });
        result.accumulator.put('g', 'Globex', null, null, new List<Object>{ 0, 0 });
        result.accumulator.put('i', 'Initech', null, null, new List<Object>{ 2, null });

        List<BoardChartEngine.GroupedRow> rows = plan.apply(result);

        Assert.areEqual(new List<String>{ 'COUNT', 'FORMULA', 'SUM' }, result.aggregateFunctions);
        Assert.areEqual(new List<String>{ null, null, 'CURRENCY' }, result.valueTypes);
        Assert.areEqual(3, rows.size());
        Assert.areEqual(250, rows[0].value(1, 'FORMULA'), 'Acme: 1000 / 4');
        Assert.areEqual(1000, rows[0].value(2, 'SUM'));
        Assert.isNull(rows[1].value(1, 'FORMULA'), 'Globex: division by zero is blank');
        Assert.isNull(rows[2].value(1, 'FORMULA'), 'Initech: blank input is blank');
        Assert.areEqual(2, result.accumulator.rows[0].values.size(), 'Cursor state keeps only the queried Measures');
    }

    @IsTest
    static void constantFormulaAloneStillGetsTheCategories() {
        Map<String, Object> request = new Map<String, Object>{ 'measures' => new List<Object>{ formula('15000') } };
        BoardFormulaMeasures.ChartPlan plan = BoardFormulaMeasures.forChart(request);
        List<Object> scanned = (List<Object>) request.get('measures');
        Assert.areEqual(1, scanned.size(), 'A record count is queried for the categories');

        BoardChartQuery.ChartResult result = new BoardChartQuery.ChartResult();
        result.aggregateFunctions = new List<String>{ 'COUNT' };
        result.valueTypes = new List<String>{ null };
        result.accumulator = new BoardChartEngine.Accumulator(1);
        result.accumulator.put('a', 'Acme', null, null, new List<Object>{ 4 });
        result.accumulator.put('g', 'Globex', null, null, new List<Object>{ 1 });

        List<BoardChartEngine.GroupedRow> rows = plan.apply(result);

        Assert.areEqual(new List<String>{ 'FORMULA' }, result.aggregateFunctions);
        Assert.areEqual(15000, rows[0].value(0, 'FORMULA'));
        Assert.areEqual(15000, rows[1].value(0, 'FORMULA'));
    }

    @IsTest
    static void chartWithoutFormulaMeasuresIsUnchanged() {
        List<Object> measures = new List<Object>{ measure('COUNT', null) };
        Map<String, Object> request = new Map<String, Object>{ 'measures' => measures };
        BoardFormulaMeasures.ChartPlan plan = BoardFormulaMeasures.forChart(request);

        BoardChartQuery.ChartResult result = new BoardChartQuery.ChartResult();
        result.aggregateFunctions = new List<String>{ 'COUNT' };
        result.accumulator = new BoardChartEngine.Accumulator(1);
        result.accumulator.put('a', 'Acme', null, null, new List<Object>{ 4 });

        Assert.areEqual(result.accumulator.rows, plan.apply(result));
        Assert.areEqual(new List<String>{ 'COUNT' }, result.aggregateFunctions);
        Assert.areEqual(measures, request.get('measures'));
    }

    @IsTest
    static void formulaMeasureCannotUseAnotherFormulaMeasureItselfOrAMissingMeasure() {
        assertConfigError(
            new List<Object>{ measure('COUNT', null), formula('A * 2'), formula('B / A') },
            'Measure 3 (C) formula can\'t use B: a Formula measure can\'t reference another Formula measure.'
        );
        assertConfigError(
            new List<Object>{ measure('COUNT', null), formula('A + b') },
            'Measure 2 (B) formula can\'t use itself (B).'
        );
        assertConfigError(
            new List<Object>{ measure('COUNT', null), formula('A / D') },
            'Measure 2 (B) formula uses D, but there is no Measure 4.'
        );
        assertConfigError(new List<Object>{ measure('COUNT', null), formula('A / ') }, 'Measure 2 (B) formula: Syntax');
    }

    @IsTest
    static void formulaMeasureCannotBeUsedWithASeriesField() {
        Map<String, Object> request = new Map<String, Object>{
            'measures' => new List<Object>{ formula('15000') },
            'stackByField' => 'StageName'
        };
        try {
            BoardFormulaMeasures.forChart(request);
        } catch (BoardErrors.BoardException error) {
            Assert.areEqual(BoardErrors.CONFIG_ERROR, error.category);
            Assert.isTrue(error.getMessage().contains('series field'), error.getMessage());
            return;
        }
        Assert.fail('Expected a series field error');
    }

    @IsTest
    static void metricFormulaUsesCompleteInputsAndWaitsForCursorInputs() {
        List<Map<String, Object>> measures = new List<Map<String, Object>>{
            hiddenMeasure('SUM', 'Amount'),
            hiddenMeasure('COUNT', null),
            formula('A / B')
        };
        Map<Integer, BoardFormula> formulas = BoardFormulaMeasures.build(measures, false);
        Assert.areEqual(new Set<Integer>{ 2 }, formulas.keySet());

        List<BoardQueryService.MetricResult> results = new List<BoardQueryService.MetricResult>{
            metricResult(900),
            metricResult(3),
            BoardFormulaMeasures.formulaResult(null)
        };
        BoardFormulaMeasures.applyToMetric(formulas, results);
        Assert.areEqual('FORMULA', results[2].aggregateFunction);
        Assert.areEqual(300, (Decimal) results[2].value);
        Assert.isTrue(results[2].isComplete);

        results = new List<BoardQueryService.MetricResult>{
            metricResult(null),
            metricResult(3),
            BoardFormulaMeasures.formulaResult(null)
        };
        results[0].mode = 'CURSOR';
        BoardFormulaMeasures.applyToMetric(formulas, results);
        Assert.isFalse(results[2].isComplete, 'Waits until the client finishes the cursor input');
        Assert.isNull(results[2].value);
    }

    @IsTest
    static void metricFormulaIsEvaluatedFromClientCompletedInputs() {
        Map<String, Object> request = new Map<String, Object>{
            'measures' => new List<Object>{
                hiddenMeasure('SUM', 'Amount'),
                hiddenMeasure('COUNT', null),
                formula('A / B')
            },
            'values' => new List<Object>{ 900, 3, null }
        };

        Assert.areEqual(300, BoardFormulaMeasures.evaluateMetric(JSON.serialize(request)));

        request.put('values', new List<Object>{ 900, 0, null });
        Assert.isNull(BoardFormulaMeasures.evaluateMetric(JSON.serialize(request)), 'Division by zero is blank');
    }

    @IsTest
    static void evaluateMetricReportsConfigErrorsReadably() {
        try {
            BoardFormulaMeasures.evaluateMetric('{"measures": [{"aggregateFunction": "COUNT"}]}');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual(BoardErrors.CONFIG_ERROR, payload.get('category'), String.valueOf(payload));
            return;
        }
        Assert.fail('Expected a config error: the visible Measure is not a Formula measure');
    }

    @IsTest
    static void checkFormulasReturnsOneBuildMessagePerFormula() {
        List<String> messages = BoardFormulaMeasures.checkFormulas(new List<String>{ 'a / b', 'A / ', '15000' });

        Assert.areEqual(3, messages.size());
        Assert.isNull(messages[0]);
        Assert.isTrue(messages[1].containsIgnoreCase('Syntax'), messages[1]);
        Assert.isNull(messages[2]);
    }

    @IsTest
    static void aMalformedMetricRequestIsAConfigError() {
        for (String malformed : new List<String>{ '[1, 2]', '{"measures": [1]}', 'not json' }) {
            try {
                BoardFormulaMeasures.evaluateMetric(malformed);
                Assert.fail('Expected a config error for ' + malformed);
            } catch (AuraHandledException failure) {
                Assert.isTrue(failure.getMessage().contains(BoardErrors.CONFIG_ERROR), failure.getMessage());
            }
        }
    }

    private static void assertConfigError(List<Object> measures, String expectedStart) {
        try {
            BoardFormulaMeasures.forChart(new Map<String, Object>{ 'measures' => measures });
        } catch (BoardErrors.BoardException error) {
            Assert.areEqual(BoardErrors.CONFIG_ERROR, error.category);
            Assert.isTrue(error.getMessage().startsWith(expectedStart), error.getMessage());
            return;
        }
        Assert.fail('Expected "' + expectedStart + '"');
    }

    private static BoardQueryService.MetricResult metricResult(Object value) {
        BoardQueryService.MetricResult result = new BoardQueryService.MetricResult();
        result.value = value;
        return result;
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField) {
        return new Map<String, Object>{ 'aggregateFunction' => aggregateFunction, 'valueFieldApiName' => valueField };
    }

    private static Map<String, Object> hiddenMeasure(String aggregateFunction, String valueField) {
        Map<String, Object> hidden = measure(aggregateFunction, valueField);
        hidden.put('hidden', true);
        return hidden;
    }

    private static Map<String, Object> formula(String text) {
        return new Map<String, Object>{ 'aggregateFunction' => 'FORMULA', 'formula' => text };
    }
}