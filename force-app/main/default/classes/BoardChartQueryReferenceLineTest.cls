/**
 * Reference lines on the Chart query: a Measure drawn as a Reference line (`render: 'referenceLine'`) gets its
 * overall value (`overallValues`, one per Measure) over every row of the Widget's scope, whatever max categories,
 * "Other" or the query tier cut. Entry-point seam with inserted Opportunities, plus the pure engine merge.
 */
@IsTest
private class BoardChartQueryReferenceLineTest {
    private static final String REFERENCE_LINE = 'referenceLine';

    /** Opportunities: Ref Opp 1 (100, Web), 2 (200), 3 (350) and 4 (no Amount). */
    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Ref Account');
        insert account;
        String stage = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue();
        Opportunity web = opportunity('Ref Opp 1', account.Id, 100, stage);
        web.LeadSource = 'Web';
        insert new List<Opportunity>{
            web,
            opportunity('Ref Opp 2', account.Id, 200, stage),
            opportunity('Ref Opp 3', account.Id, 350, stage),
            opportunity('Ref Opp 4', account.Id, null, stage)
        };
    }

    @IsTest
    static void referenceLineGetsItsMeasureOverallValueOverEveryRowNotJustTheShownCategories() {
        Map<String, Object> request = chartRequest(
            'Name',
            new List<Object>{
                measure('SUM', 'Amount', null),
                measure('AVG', 'Amount', REFERENCE_LINE),
                measure('SUM', 'Amount', REFERENCE_LINE)
            }
        );
        request.put('maxCategories', 3);

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual('SINGLE', result.mode);
        Assert.isTrue(result.truncatedCategories, 'Only 3 of 4 categories are shown');
        Assert.areEqual(3, result.overallValues.size(), 'One per Measure');
        Assert.isNull(result.overallValues[0], 'A Measure drawn as bars has no overall value');
        Assert.areEqual(216.67, result.overallValues[1].setScale(2), 'AVG over every Amount: 650 / 3');
        Assert.areEqual(650, result.overallValues[2], 'SUM over every row, including the hidden category');
    }

    @IsTest
    static void aShareOfTotalMeasureCannotBeDrawnAsAReferenceLine() {
        Map<String, Object> share = measure('SUM', 'Amount', REFERENCE_LINE);
        share.put('showAs', 'percentOfTotal');
        Map<String, Object> request = chartRequest('Name', new List<Object>{ measure('SUM', 'Amount', null), share });
        try {
            query(request);
            Assert.fail('Expected a config error');
        } catch (AuraHandledException failure) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(failure.getMessage());
            Assert.areEqual(BoardErrors.CONFIG_ERROR, payload.get('category'));
            Assert.areEqual(
                'Measure 2: a Reference line shows the overall value, not a percentage.',
                payload.get('message')
            );
        }
    }

    @IsTest
    static void chartWithoutReferenceLinesReturnsNoOverallValues() {
        BoardChartQuery.ChartResult result = query(
            chartRequest('Name', new List<Object>{ measure('SUM', 'Amount', 'line') })
        );
        Assert.isNull(result.overallValues);
    }

    @IsTest
    static void cursorTierGivesTheSameOverallValues() {
        Map<String, Object> request = chartRequest(
            'Name',
            new List<Object>{
                measure('SUM', 'Amount', null),
                measure('AVG', 'Amount', REFERENCE_LINE),
                measure('MAX', 'Amount', REFERENCE_LINE)
            }
        );
        request.put('maxCategories', 3);
        BoardQueryService.CURSOR_AGGREGATE_THRESHOLD = 1;
        BoardQueryService.CURSOR_CHUNK_SIZE = 1;

        BoardChartQuery.ChartResult result = query(request);
        Assert.areEqual('CURSOR', result.mode);
        while (!result.isComplete) {
            Map<String, Object> next = request.clone();
            next.put('cursor', result.cursor);
            next.put('offset', result.nextOffset);
            next.put('partialState', result.partialState);
            result = BoardChartQuery.fetchChartChunk(JSON.serialize(next));
        }

        Assert.isNull(result.overallValues[0]);
        Assert.areEqual(216.67, result.overallValues[1].setScale(2), 'AVG merged from every row read');
        Assert.areEqual(350, result.overallValues[2]);
    }

    @IsTest
    static void bucketFieldChartLeavesExcludedRowsOutOfTheOverallValue() {
        Map<String, Object> request = chartRequest(
            'bucket:dealSize',
            new List<Object>{ measure('SUM', 'Amount', null), measure('COUNT', null, REFERENCE_LINE) }
        );
        request.put(
            'bucketFields',
            new List<Object>{
                new Map<String, Object>{
                    'id' => 'dealSize',
                    'label' => 'Deal size',
                    'rules' => new List<Object>{
                        rule('Large', 'Amount', 'GTE', 300),
                        rule('Small', 'Amount', 'LT', 300)
                    },
                    'fallback' => new Map<String, Object>{ 'label' => 'Rest', 'exclude' => true }
                }
            }
        );

        BoardChartQuery.ChartResult result = query(request);

        Assert.areEqual(2, result.categories.size());
        Assert.areEqual(3, result.overallValues[1], 'Ref Opp 4 has no Amount: excluded fallback, not counted');
    }

    @IsTest
    static void engineMergesOverallValuesFromGroupedRows() {
        BoardChartEngine.Accumulator values = new BoardChartEngine.Accumulator(4);
        values.put('a', 'A', null, null, new List<Object>{ 10, 2, 5, 7 });
        values.put('b', 'B', null, null, new List<Object>{ 30, 3, 1, 9 });
        values.put(null, null, null, null, new List<Object>{ 100, 1, 0, 100 });
        List<String> functions = new List<String>{ 'SUM', 'COUNT', 'MIN', 'MAX' };

        Assert.areEqual(
            new List<Decimal>{ 140, 6, 0, 100 },
            BoardChartEngine.overallValues(functions, values.rows, true)
        );
        Assert.areEqual(
            new List<Decimal>{ 40, 5, 1, 9 },
            BoardChartEngine.overallValues(functions, values.rows, false),
            'Without the (Blank) category its row stays out'
        );
        Assert.areEqual(
            new List<Decimal>{ null },
            BoardChartEngine.overallValues(new List<String>{ 'AVG' }, values.rows, true),
            'An average of final group averages cannot be merged'
        );

        BoardChartEngine.Accumulator partials = new BoardChartEngine.Accumulator(1);
        partials.add('a', 'A', null, null, new List<Object>{ 10 });
        partials.add('a', 'A', null, null, new List<Object>{ 20 });
        partials.add('b', 'B', null, null, new List<Object>{ 60 });
        Assert.areEqual(
            30.00,
            BoardChartEngine.overallValues(new List<String>{ 'AVG' }, partials.rows, true)[0].setScale(2),
            'Cursor partials merge into the overall average: (10 + 20 + 60) / 3'
        );
    }

    private static Map<String, Object> chartRequest(String groupByField, List<Object> measures) {
        return new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'groupByField' => groupByField,
            'measures' => measures
        };
    }

    private static Map<String, Object> measure(String aggregateFunction, String valueField, String render) {
        Map<String, Object> result = new Map<String, Object>{ 'aggregateFunction' => aggregateFunction };
        if (valueField != null) {
            result.put('valueFieldApiName', valueField);
        }
        if (render != null) {
            result.put('render', render);
        }
        return result;
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

    private static BoardChartQuery.ChartResult query(Map<String, Object> request) {
        return BoardChartQuery.queryChart(JSON.serialize(request));
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