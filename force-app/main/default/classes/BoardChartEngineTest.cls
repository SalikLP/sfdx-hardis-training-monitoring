@IsTest
private class BoardChartEngineTest {
    @IsTest
    static void measuresShareOneSeriesAndKeepTheirOwnValues() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'SUM', 'COUNT' });
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(2);
        rows.put('a', 'Acme', null, null, new List<Object>{ 300, 2 });
        rows.put('g', 'Globex', null, null, new List<Object>{ 500, 1 });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);

        Assert.areEqual('Globex', shape.categories[0].label, 'Sorted by the first Measure, high to low');
        Assert.areEqual('Acme', shape.categories[1].label);
        Assert.areEqual(1, shape.series.size(), 'No series field: one series');
        Assert.areEqual(BoardChartEngine.VALUE_KEY, shape.series[0].key);
        Assert.areEqual(4, shape.points.size(), 'One point per Measure per category');
        Map<String, BoardChartEngine.ChartPoint> points = pointsByKey(shape);
        Assert.areEqual(500, points.get('g|__value__|0').value);
        Assert.areEqual(1, points.get('g|__value__|1').value);
        Assert.areEqual('measure:0', points.get('a|__value__|0').colourKey);
        Assert.areEqual('measure:1', points.get('a|__value__|1').colourKey);
        Assert.isFalse(shape.truncatedCategories);
    }

    @IsTest
    static void topNRollsTheRestIntoOtherPerSeriesForAdditiveMeasures() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'SUM' });
        settings.hasSeries = true;
        settings.maxCategories = 3;
        settings.overflowMode = 'OTHER';
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.put('c1', 'One', 'won', 'Won', new List<Object>{ 50 });
        rows.put('c1', 'One', 'lost', 'Lost', new List<Object>{ 10 });
        rows.put('c2', 'Two', 'won', 'Won', new List<Object>{ 40 });
        rows.put('c3', 'Three', 'won', 'Won', new List<Object>{ 5 });
        rows.put('c3', 'Three', 'lost', 'Lost', new List<Object>{ 1 });
        rows.put('c4', 'Four', 'lost', 'Lost', new List<Object>{ 3 });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);

        Assert.areEqual(3, shape.categories.size());
        Assert.areEqual('c1', shape.categories[0].key);
        Assert.areEqual('c2', shape.categories[1].key);
        BoardChartEngine.ChartKey other = shape.categories[2];
        Assert.areEqual(BoardChartEngine.OTHER_KEY, other.key);
        Assert.areEqual('Other', other.label);
        Assert.isTrue(other.isOther);
        Assert.isNull(other.value);
        Assert.areEqual(BoardChartEngine.OTHER_KEY, other.colourKey);
        Assert.isTrue(shape.truncatedCategories);
        Assert.areEqual(2, shape.hiddenCategories, 'Three and Four rolled into Other');
        Map<String, BoardChartEngine.ChartPoint> points = pointsByKey(shape);
        Assert.areEqual(5, points.get('__other__|won|0').value);
        Assert.areEqual(4, points.get('__other__|lost|0').value);
        Assert.areEqual('won', points.get('c1|won|0').colourKey, 'Series values are their own colour key');
    }

    @IsTest
    static void nonAdditiveMeasuresTruncateInsteadOfOther() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'SUM', 'AVG' });
        settings.maxCategories = 2;
        settings.overflowMode = 'OTHER';
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(2);
        rows.put('a', 'A', null, null, new List<Object>{ 3, 1 });
        rows.put('b', 'B', null, null, new List<Object>{ 2, 1 });
        rows.put('c', 'C', null, null, new List<Object>{ 1, 1 });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);

        Assert.areEqual(2, shape.categories.size());
        Assert.areEqual('a', shape.categories[0].key);
        Assert.areEqual('b', shape.categories[1].key);
        Assert.isTrue(shape.truncatedCategories);
        Assert.areEqual(1, shape.hiddenCategories);
    }

    @IsTest
    static void otherMergesThePartialsOfMeasuresThatDoNotAddUp() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'SUM', 'AVG', 'MIN', 'MAX' });
        settings.maxCategories = 2;
        settings.overflowMode = 'OTHER';
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(4);
        rows.add('a', 'A', null, null, new List<Object>{ 50, 50, 50, 50 });
        rows.add('b', 'B', null, null, new List<Object>{ 10, 10, 10, 10 });
        rows.add('b', 'B', null, null, new List<Object>{ 20, 20, 20, 20 });
        rows.add('c', 'C', null, null, new List<Object>{ 6, 6, 6, 6 });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);

        Assert.areEqual(2, shape.categories.size());
        Assert.isTrue(shape.categories[1].isOther, 'A kept, B and C rolled into "Other"');
        Assert.areEqual(2, shape.hiddenCategories);
        Map<String, BoardChartEngine.ChartPoint> points = pointsByKey(shape);
        Assert.areEqual(36, points.get('__other__|__value__|0').value, 'SUM: 10 + 20 + 6');
        Assert.areEqual(12, points.get('__other__|__value__|1').value, 'AVG over the rolled-up rows: 36 / 3');
        Assert.areEqual(6, points.get('__other__|__value__|2').value);
        Assert.areEqual(20, points.get('__other__|__value__|3').value);
        Assert.areEqual(50, points.get('a|__value__|1').value, 'Kept categories keep their own values');
    }

    @IsTest
    static void otherComputesFormulaMeasuresFromTheMergedInputs() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'SUM', 'SUM', 'FORMULA' });
        settings.maxCategories = 2;
        settings.overflowMode = 'OTHER';
        settings.otherValues = new RatioOfFirstTwo();
        List<BoardChartEngine.GroupedRow> rows = new List<BoardChartEngine.GroupedRow>{
            formulaRow('a', 8, 10),
            formulaRow('b', 1, 4),
            formulaRow('c', 2, 6)
        };

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows);

        Map<String, BoardChartEngine.ChartPoint> points = pointsByKey(shape);
        Assert.areEqual(3, points.get('__other__|__value__|0').value);
        Assert.areEqual(10, points.get('__other__|__value__|1').value);
        Assert.areEqual(0.3, points.get('__other__|__value__|2').value, 'A / B of the merged inputs: 3 / 10');
    }

    @IsTest
    static void countDistinctAndFinalValuesStillTruncate() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'SUM', 'COUNT_DISTINCT' });
        settings.maxCategories = 2;
        settings.overflowMode = 'OTHER';
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(2);
        rows.add('a', 'A', null, null, new List<Object>{ 3, 1 });
        rows.add('b', 'B', null, null, new List<Object>{ 2, 1 });
        rows.add('c', 'C', null, null, new List<Object>{ 1, 1 });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);

        Assert.areEqual('b', shape.categories[1].key, 'Distinct counts never merge: truncated');
        Assert.isTrue(shape.truncatedCategories);
    }

    @IsTest
    static void seriesCapRollsMeasuresThatDoNotAddUpIntoOther() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'MAX' });
        settings.hasSeries = true;
        settings.maxSeries = 2;
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.add('c', 'C', 'x', 'X', new List<Object>{ 5 });
        rows.add('c', 'C', 'y', 'Y', new List<Object>{ 2 });
        rows.add('c', 'C', null, null, new List<Object>{ 4 });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);

        Assert.isTrue(shape.series[1].isOther);
        Assert.areEqual(4, pointsByKey(shape).get('c|__other__|0').value, 'MAX of Y and (Blank)');
    }

    /** A Formula measure `A / B` over two SUM Measures (test `OtherValues`). */
    private class RatioOfFirstTwo implements BoardChartEngine.OtherValues {
        public List<Decimal> valuesOf(List<BoardChartEngine.Partial> merged) {
            Decimal a = merged[0].value('SUM');
            Decimal b = merged[1].value('SUM');
            return new List<Decimal>{ a, b, a == null || b == null || b == 0 ? null : a.divide(b, 10) };
        }
    }

    /** A widened Formula row: SUM inputs `a`, `b` and the formula `a / b`, with its inputs' partials. */
    private static BoardChartEngine.GroupedRow formulaRow(String key, Decimal a, Decimal b) {
        BoardChartEngine.GroupedRow row = new BoardChartEngine.GroupedRow(key, key.toUpperCase(), null, null);
        row.values = new List<Decimal>{ a, b, a.divide(b, 10) };
        row.otherInputs = new List<BoardChartEngine.Partial>{ partials(a, 1, a, a, 1)[0], partials(b, 1, b, b, 1)[0] };
        return row;
    }

    @IsTest
    static void topNAtTwoHundredCategoriesKeepsTheLargest() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'COUNT' });
        settings.maxCategories = 200;
        settings.overflowMode = 'OTHER';
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        for (Integer i = 1; i <= 250; i++) {
            rows.put('owner' + i, 'Owner ' + i, null, null, new List<Object>{ i });
        }

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);

        Assert.areEqual(200, shape.categories.size());
        Assert.areEqual('owner250', shape.categories[0].key);
        Assert.areEqual('owner52', shape.categories[198].key, '199 largest kept');
        Assert.isTrue(shape.categories[199].isOther);
        // Owners 1..51 sum to 1326.
        Assert.areEqual(1326, pointsByKey(shape).get('__other__|__value__|0').value);
        Assert.areEqual(51, shape.hiddenCategories);
    }

    @IsTest
    static void dateAxisAlwaysTruncatesEvenWhenOtherIsRequested() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'COUNT' });
        settings.isDateAxis = true;
        settings.maxCategories = 3;
        settings.overflowMode = 'OTHER';
        BoardChartEngine.Accumulator months = new BoardChartEngine.Accumulator(1);
        for (Integer month = 1; month <= 6; month++) {
            String key = '2026-0' + month;
            months.put(key, key, null, null, new List<Object>{ month });
        }

        settings.sortBy = 'CHRONOLOGICAL_ASC';
        BoardChartEngine.ChartShape earliest = BoardChartEngine.shape(settings, months.rows);
        Assert.areEqual(3, earliest.categories.size());
        Assert.areEqual('2026-01', earliest.categories[0].key, 'Ascending keeps the earliest N');
        Assert.areEqual('2026-03', earliest.categories[2].key);
        Assert.isFalse(earliest.categories[2].isOther, 'A date axis never gets an Other point');
        Assert.isTrue(earliest.truncatedCategories);
        Assert.areEqual(3, earliest.hiddenCategories);

        settings.sortBy = 'CHRONOLOGICAL_DESC';
        BoardChartEngine.ChartShape latest = BoardChartEngine.shape(settings, months.rows);
        Assert.areEqual('2026-06', latest.categories[0].key, 'Descending keeps the latest N');
        Assert.areEqual('2026-04', latest.categories[2].key);
        Assert.isFalse(latest.categories[2].isOther);
    }

    @IsTest
    static void blankCategoriesAreLabelledAndCanBeExcluded() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'COUNT' });
        settings.sortBy = 'LABEL_ASC';
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.put(null, null, null, null, new List<Object>{ 9 });
        rows.put('b', 'Beta', null, null, new List<Object>{ 1 });
        rows.put('a', 'alpha', null, null, new List<Object>{ 2 });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);
        Assert.areEqual('alpha', shape.categories[0].label, 'Label order ignores case');
        Assert.areEqual('Beta', shape.categories[1].label);
        BoardChartEngine.ChartKey blank = shape.categories[2];
        Assert.areEqual('(Blank)', blank.label, 'Blank sorts last');
        Assert.areEqual(BoardChartEngine.BLANK_KEY, blank.key);
        Assert.areEqual(BoardChartEngine.BLANK_KEY, blank.colourKey);
        Assert.isTrue(blank.isBlank);

        settings.includeBlank = false;
        Assert.areEqual(2, BoardChartEngine.shape(settings, rows.rows).categories.size());
    }

    @IsTest
    static void sortsByPicklistOrderAndChronologically() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'COUNT' });
        settings.sortBy = 'PICKLIST_ORDER';
        settings.picklistOrder = new List<String>{ 'Prospecting', 'Closed Won' };
        BoardChartEngine.Accumulator stages = new BoardChartEngine.Accumulator(1);
        stages.put('Closed Won', 'Closed Won', null, null, new List<Object>{ 9 });
        stages.put('Prospecting', 'Prospecting', null, null, new List<Object>{ 1 });
        Assert.areEqual('Prospecting', BoardChartEngine.shape(settings, stages.rows).categories[0].key);

        BoardChartEngine.Settings dates = settings(new List<String>{ 'COUNT' });
        dates.isDateAxis = true;
        BoardChartEngine.Accumulator months = new BoardChartEngine.Accumulator(1);
        months.put('2026-03', 'Mar 2026', null, null, new List<Object>{ 1 });
        months.put('2025-12', 'Dec 2025', null, null, new List<Object>{ 5 });
        months.put('2026-01', 'Jan 2026', null, null, new List<Object>{ 3 });
        BoardChartEngine.ChartShape ascending = BoardChartEngine.shape(dates, months.rows);
        Assert.areEqual('2025-12', ascending.categories[0].key, 'A date axis defaults to chronological');
        Assert.areEqual('2026-03', ascending.categories[2].key);
        dates.sortBy = 'CHRONOLOGICAL_DESC';
        Assert.areEqual('2026-03', BoardChartEngine.shape(dates, months.rows).categories[0].key);
    }

    @IsTest
    static void seriesBeyondMaxSeriesRollIntoOther() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'COUNT' });
        settings.hasSeries = true;
        settings.maxSeries = 2;
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.put('c', 'C', 'x', 'X', new List<Object>{ 5 });
        rows.put('c', 'C', 'y', 'Y', new List<Object>{ 2 });
        rows.put('c', 'C', null, null, new List<Object>{ 1 });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);

        Assert.areEqual(2, shape.series.size());
        Assert.areEqual('x', shape.series[0].key);
        Assert.isTrue(shape.series[1].isOther);
        Assert.isTrue(shape.truncatedSeries);
        Assert.areEqual(3, pointsByKey(shape).get('c|__other__|0').value, 'Y and (Blank) rolled up');

        settings.aggregateFunctions = new List<String>{ 'MAX' };
        BoardChartEngine.ChartShape truncated = BoardChartEngine.shape(settings, rows.rows);
        Assert.areEqual('y', truncated.series[1].key, 'MAX cannot be summed: extra series are hidden');
    }

    @IsTest
    static void cursorPartialsMergeAcrossChunkStates() {
        List<String> functions = new List<String>{ 'COUNT', 'SUM', 'AVG', 'MIN', 'MAX' };
        BoardChartEngine.Accumulator first = new BoardChartEngine.Accumulator(5);
        first.add('a', 'Acme', null, null, new List<Object>{ 1, 100, 100, 100, 100 });
        first.add('a', 'Acme', null, null, new List<Object>{ 1, null, null, null, null });

        BoardChartEngine.Accumulator second = new BoardChartEngine.Accumulator(5).restore(first.state());
        second.add('a', 'Acme', null, null, new List<Object>{ 1, 300, 300, 300, 300 });
        second.add('b', 'Beta', null, null, new List<Object>{ 1, null, null, null, null });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings(functions), second.rows);
        Map<String, BoardChartEngine.ChartPoint> points = pointsByKey(shape);
        Assert.areEqual(3, points.get('a|__value__|0').value, 'COUNT counts rows');
        Assert.areEqual(400, points.get('a|__value__|1').value);
        Assert.areEqual(200, points.get('a|__value__|2').value, 'AVG ignores null values');
        Assert.areEqual(100, points.get('a|__value__|3').value);
        Assert.areEqual(300, points.get('a|__value__|4').value);
        Assert.areEqual(1, points.get('b|__value__|0').value);
        Assert.isNull(points.get('b|__value__|1').value, 'SUM of only null values is null');
    }

    @IsTest
    static void mergedPartialBucketsCombineSumsCountsAndAveragesAcrossLegs() {
        List<String> functions = new List<String>{ 'SUM', 'AVG', 'COUNT', 'MIN', 'MAX' };
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(5);
        // Standard leg: Acme rows 100 and 200; provider leg: one more Acme row of 600 and a provider-only category.
        rows.addPartials('a', 'Acme', null, null, partials(300, 2, 100, 200, 5));
        rows.addPartials('a', 'Ignored label', null, null, partials(600, 1, 600, 600, 5));
        rows.addPartials('e', 'Estimates', null, null, partials(50, 1, 50, 50, 5));

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings(functions), rows.rows);

        Assert.areEqual(2, shape.categories.size());
        Assert.areEqual('Acme', shape.categories[0].label, 'The first leg names the category');
        Map<String, BoardChartEngine.ChartPoint> points = pointsByKey(shape);
        Assert.areEqual(900, points.get('a|__value__|0').value);
        Assert.areEqual(300, points.get('a|__value__|1').value, 'AVG over both legs: 900 / 3, not avg of averages');
        Assert.areEqual(3, points.get('a|__value__|2').value);
        Assert.areEqual(100, points.get('a|__value__|3').value);
        Assert.areEqual(600, points.get('a|__value__|4').value);
        Assert.areEqual(50, points.get('e|__value__|1').value);
    }

    @IsTest
    static void malformedCursorStateIsARetryableError() {
        try {
            new BoardChartEngine.Accumulator(1).restore('not json');
            Assert.fail('Expected an error');
        } catch (BoardErrors.BoardException error) {
            Assert.areEqual(BoardErrors.QUERY_ERROR, error.category);
            Assert.isTrue(error.retryable);
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Share of total
    // ---------------------------------------------------------------------------------------------------------

    @IsTest
    static void percentOfTotalIsAgainstEveryCategoryIncludingHiddenOnes() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'SUM', 'COUNT' });
        settings.showAs = new List<String>{ BoardChartEngine.SHOW_AS_PERCENT_OF_TOTAL, null };
        settings.maxCategories = 2;
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(2);
        rows.put('a', 'A', null, null, new List<Object>{ 50, 4 });
        rows.put('b', 'B', null, null, new List<Object>{ 30, 3 });
        rows.put('c', 'C', null, null, new List<Object>{ 20, 1 });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);

        Assert.areEqual(2, shape.categories.size(), 'C is hidden by max categories');
        Assert.areEqual('a', shape.categories[0].key, 'Sorted by the plain value');
        Map<String, BoardChartEngine.ChartPoint> points = pointsByKey(shape);
        Assert.areEqual(0.5, points.get('a|__value__|0').value, '50 of 100, the hidden C included');
        Assert.areEqual(0.3, points.get('b|__value__|0').value);
        Assert.areEqual(4, points.get('a|__value__|1').value, 'A plain Measure keeps its value');
    }

    @IsTest
    static void percentOfTotalUsesGrandTotalsFromTheUngroupedQueryWhenGiven() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'SUM' });
        settings.showAs = new List<String>{ BoardChartEngine.SHOW_AS_PERCENT_OF_TOTAL };
        settings.grandTotals = new List<Decimal>{ 200 };
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.put('a', 'A', null, null, new List<Object>{ 50 });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);

        Assert.areEqual(0.25, pointsByKey(shape).get('a|__value__|0').value, 'Groups the capped query dropped count');
    }

    @IsTest
    static void percentOfCategoryWithASeriesFieldIsTheShareWithinItsCategory() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'SUM' });
        settings.showAs = new List<String>{ BoardChartEngine.SHOW_AS_PERCENT_OF_CATEGORY };
        settings.hasSeries = true;
        settings.maxSeries = 2;
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.put('f1', 'Family 1', 'p1', 'Product 1', new List<Object>{ 30 });
        rows.put('f1', 'Family 1', 'p2', 'Product 2', new List<Object>{ 10 });
        rows.put('f1', 'Family 1', 'p3', 'Product 3', new List<Object>{ 10 });
        rows.put('f2', 'Family 2', 'p1', 'Product 1', new List<Object>{ 20 });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);

        Map<String, BoardChartEngine.ChartPoint> points = pointsByKey(shape);
        Assert.areEqual(0.6, points.get('f1|p1|0').value, '30 of Family 1 (50)');
        Assert.areEqual(0.4, points.get('f1|__other__|0').value, 'Products 2 and 3 rolled into the "Other" series');
        Assert.areEqual(1, points.get('f2|p1|0').value);

        settings.showAs = new List<String>{ BoardChartEngine.SHOW_AS_PERCENT_OF_TOTAL };
        points = pointsByKey(BoardChartEngine.shape(settings, rows.rows));
        Assert.areEqual(0.4286, points.get('f1|p1|0').value.setScale(4), '30 of every cell in every category (70)');
        Assert.areEqual(0.2857, points.get('f1|__other__|0').value.setScale(4), 'The "Other" series: 20 of 70');
        Assert.areEqual(0.2857, points.get('f2|p1|0').value.setScale(4));
    }

    @IsTest
    static void percentOfCategoryWithSeveralMeasuresSharesTheMeasuresShownThatWay() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'SUM', 'SUM', 'COUNT' });
        settings.showAs = new List<String>{
            BoardChartEngine.SHOW_AS_PERCENT_OF_CATEGORY,
            BoardChartEngine.SHOW_AS_PERCENT_OF_CATEGORY,
            BoardChartEngine.SHOW_AS_VALUE
        };
        settings.maxCategories = 3;
        settings.overflowMode = 'OTHER';
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(3);
        rows.put('a', 'A', null, null, new List<Object>{ 30, 10, 5 });
        rows.put('b', 'B', null, null, new List<Object>{ 20, 20, 4 });
        rows.put('c', 'C', null, null, new List<Object>{ 6, 2, 3 });
        rows.put('d', 'D', null, null, new List<Object>{ 0, 2, 1 });

        BoardChartEngine.ChartShape shape = BoardChartEngine.shape(settings, rows.rows);

        Map<String, BoardChartEngine.ChartPoint> points = pointsByKey(shape);
        Assert.areEqual(0.75, points.get('a|__value__|0').value, 'Won 30 of Won + Lost (40)');
        Assert.areEqual(0.25, points.get('a|__value__|1').value);
        Assert.areEqual(5, points.get('a|__value__|2').value, 'The plain Measure is not part of the category total');
        Assert.areEqual(0.6, points.get('__other__|__value__|0').value, 'Other = C + D: 6 of 10');
        Assert.areEqual(0.4, points.get('__other__|__value__|1').value);
    }

    @IsTest
    static void shareOfAZeroTotalOrABlankValueIsBlank() {
        BoardChartEngine.Settings settings = settings(new List<String>{ 'SUM' });
        settings.showAs = new List<String>{ BoardChartEngine.SHOW_AS_PERCENT_OF_TOTAL };
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.put('a', 'A', null, null, new List<Object>{ 0 });
        rows.put('b', 'B', null, null, new List<Object>{ null });

        Map<String, BoardChartEngine.ChartPoint> points = pointsByKey(BoardChartEngine.shape(settings, rows.rows));

        Assert.isNull(points.get('a|__value__|0').value, 'No total to divide by');
        Assert.isNull(points.get('b|__value__|0').value);
    }

    private static BoardChartEngine.Settings settings(List<String> functions) {
        BoardChartEngine.Settings settings = new BoardChartEngine.Settings();
        settings.aggregateFunctions = functions;
        return settings;
    }

    /** `size` copies of one `{ sum, count, min, max }` partial. */
    private static List<BoardChartEngine.Partial> partials(
        Decimal sum,
        Integer count,
        Decimal min,
        Decimal max,
        Integer size
    ) {
        List<BoardChartEngine.Partial> result = new List<BoardChartEngine.Partial>();
        for (Integer i = 0; i < size; i++) {
            BoardChartEngine.Partial partial = new BoardChartEngine.Partial();
            partial.sum = sum;
            partial.count = count;
            partial.min = min;
            partial.max = max;
            result.add(partial);
        }
        return result;
    }

    /** Points keyed `category|series|measureIndex`. */
    private static Map<String, BoardChartEngine.ChartPoint> pointsByKey(BoardChartEngine.ChartShape shape) {
        Map<String, BoardChartEngine.ChartPoint> points = new Map<String, BoardChartEngine.ChartPoint>();
        for (BoardChartEngine.ChartPoint point : shape.points) {
            points.put(point.categoryKey + '|' + point.seriesKey + '|' + point.measureIndex, point);
        }
        return points;
    }
}