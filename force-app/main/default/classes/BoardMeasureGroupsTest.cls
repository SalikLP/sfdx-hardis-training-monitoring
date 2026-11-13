/**
 * Engine-unit seam of Measure condition grouping and the Measure join, fed with in-memory grouped values (no SOQL).
 */
@IsTest
private class BoardMeasureGroupsTest {
    @IsTest
    static void measuresSharingAConditionFormOneGroupInFirstSeenOrder() {
        Map<String, Object> won = condition('IsWon', true);
        BoardMeasureGroups grouping = new BoardMeasureGroups(
            new List<Object>{
                measure('SUM', null),
                measure('SUM', won),
                measure('COUNT', null),
                measure('COUNT', condition('IsWon', true)),
                measure('COUNT', condition('IsClosed', true))
            }
        );

        Assert.areEqual(3, grouping.groups.size(), 'No condition, Won, Closed');
        Assert.areEqual(new List<Integer>{ 0, 2 }, grouping.groups[0].measureIndexes);
        Assert.isNull(grouping.groups[0].condition);
        Assert.areEqual(new List<Integer>{ 1, 3 }, grouping.groups[1].measureIndexes, 'Equal conditions share a group');
        Assert.areEqual(new List<Integer>{ 4 }, grouping.groups[2].measureIndexes);
        Assert.isTrue(grouping.hasConditions());
    }

    @IsTest
    static void blankConditionsCountAsNoCondition() {
        BoardMeasureGroups grouping = new BoardMeasureGroups(
            new List<Object>{
                measure('COUNT', null),
                measure('COUNT', new Map<String, Object>{ 'logic' => 'AND', 'conditions' => new List<Object>() }),
                measure('COUNT', new Map<String, Object>()),
                new Map<String, Object>{ 'aggregateFunction' => 'COUNT' }
            }
        );

        Assert.areEqual(1, grouping.groups.size());
        Assert.areEqual(new List<Integer>{ 0, 1, 2, 3 }, grouping.groups[0].measureIndexes);
        Assert.isFalse(grouping.hasConditions());
        Assert.isTrue(BoardMeasureGroups.isBlank(null));
        Assert.isFalse(BoardMeasureGroups.isBlank(condition('IsWon', true)));
    }

    @IsTest
    static void joinMergesEachGroupsValuesOnTheCategoryAndSeriesKey() {
        BoardMeasureGroups grouping = new BoardMeasureGroups(
            new List<Object>{
                measure('SUM', condition('IsWon', true)),
                measure('SUM', condition('IsClosed', true)),
                measure('COUNT', condition('IsWon', true))
            }
        );
        BoardMeasureGroups.MeasureGroup won = grouping.groups[0];
        BoardMeasureGroups.MeasureGroup closed = grouping.groups[1];
        BoardMeasureGroups.MeasureJoin measureJoin = new BoardMeasureGroups.MeasureJoin(
            new List<String>{ 'SUM', 'SUM', 'COUNT' }
        );

        // Won: Alpha only. Closed: Alpha and Beta (a category the first group never saw).
        measureJoin.put(won, 'a1', 'Alpha', null, null, new List<Object>{ 300, 2 });
        measureJoin.put(closed, 'a1', 'Alpha', null, null, new List<Object>{ 450.5 });
        measureJoin.put(closed, 'b1', 'Beta', null, null, new List<Object>{ 50 });

        List<BoardChartEngine.GroupedRow> rows = measureJoin.rows();
        Assert.areEqual(2, rows.size(), 'One joined row per category');
        Assert.areEqual('a1', rows[0].categoryValue);
        Assert.areEqual('Alpha', rows[0].categoryLabel);
        Assert.areEqual(new List<Decimal>{ 300, 450.5, 2 }, rows[0].values);
        Assert.areEqual('b1', rows[1].categoryValue);
        Assert.areEqual(
            new List<Decimal>{ null, 50, 0 },
            rows[1].values,
            'A category missing from a group: its SUM is blank, its COUNT is 0'
        );
    }

    @IsTest
    static void joinKeepsSeriesApartAndFeedsTheChartEngine() {
        BoardMeasureGroups grouping = new BoardMeasureGroups(
            new List<Object>{ measure('COUNT', condition('IsWon', true)) }
        );
        BoardMeasureGroups.MeasureJoin measureJoin = new BoardMeasureGroups.MeasureJoin(new List<String>{ 'COUNT' });
        measureJoin.put(grouping.groups[0], 'a1', 'Alpha', 'Web', 'Web', new List<Object>{ 3 });
        measureJoin.put(grouping.groups[0], 'a1', 'Alpha', 'Phone', 'Phone', new List<Object>{ 1 });
        measureJoin.put(grouping.groups[0], null, null, 'Web', 'Web', new List<Object>{ 2L });

        BoardChartEngine.Accumulator accumulator = new BoardChartEngine.Accumulator(1);
        measureJoin.putInto(accumulator);

        Assert.areEqual(3, accumulator.rows.size(), 'Same category, different series: separate rows');
        Assert.areEqual(2, accumulator.rows[2].value(0, 'COUNT'), 'Long values become Decimals');
        Assert.isNull(accumulator.rows[2].categoryValue, 'The (Blank) category joins like any other');
    }

    @IsTest
    static void spreadPlacesAGroupsPartialsAtItsMeasurePositions() {
        BoardMeasureGroups grouping = new BoardMeasureGroups(
            new List<Object>{
                measure('SUM', null),
                measure('SUM', condition('IsWon', true)),
                measure('COUNT', condition('IsWon', true))
            }
        );
        BoardChartEngine.Partial sum = new BoardChartEngine.Partial();
        sum.add(100);
        BoardChartEngine.Partial count = new BoardChartEngine.Partial();
        count.add(1);
        count.add(1);

        List<BoardChartEngine.Partial> spread = grouping.groups[1]
            .spread(new List<BoardChartEngine.Partial>{ sum, count }, 3);

        Assert.areEqual(3, spread.size());
        Assert.isNull(spread[0].value('SUM'), 'Measures of other groups get an empty partial');
        Assert.areEqual(100, spread[1].value('SUM'));
        Assert.areEqual(2, spread[2].value('COUNT'));
    }

    private static Map<String, Object> measure(String aggregateFunction, Map<String, Object> condition) {
        Map<String, Object> measure = new Map<String, Object>{ 'aggregateFunction' => aggregateFunction };
        if (aggregateFunction != 'COUNT') {
            measure.put('valueFieldApiName', 'Amount');
        }
        measure.put('condition', condition);
        return measure;
    }

    private static Map<String, Object> condition(String fieldPath, Object value) {
        return new Map<String, Object>{
            'logic' => 'AND',
            'conditions' => new List<Object>{
                new Map<String, Object>{ 'id' => 'mc1', 'fieldPath' => fieldPath, 'operator' => 'EQ', 'value' => value }
            }
        };
    }
}