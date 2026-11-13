@IsTest
private class BoardChartPanelsTest {
    @IsTest
    static void onePanelPerValueSharingTheSameCategoriesInTheSameOrder() {
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.put('new', 'New Business', 'a', 'Acme', null, null, new List<Object>{ 10 });
        rows.put('new', 'New Business', 'g', 'Globex', null, null, new List<Object>{ 30 });
        rows.put('ext', 'Existing', 'a', 'Acme', null, null, new List<Object>{ 50 });

        BoardChartPanels.PanelShape shape = BoardChartPanels.shape(
            chart(new List<String>{ 'SUM' }),
            new BoardChartPanels.Settings(),
            rows.rows
        );

        Assert.areEqual(2, shape.panels.size());
        Assert.areEqual('Existing', shape.panels[0].label, 'Field order without picklist order: by label');
        Assert.areEqual('New Business', shape.panels[1].label);
        Assert.areEqual('ext', shape.panels[0].key);
        Assert.areEqual(2, shape.categories.size(), 'Every panel shows the same categories');
        Assert.areEqual('a', shape.categories[0].key, 'Acme 60 across all panels beats Globex 30');
        Assert.areEqual('g', shape.categories[1].key);
        Map<String, Decimal> values = values(shape);
        Assert.areEqual(10, values.get('new|a|__value__|0'));
        Assert.areEqual(30, values.get('new|g|__value__|0'));
        Assert.areEqual(50, values.get('ext|a|__value__|0'));
        Assert.isFalse(values.containsKey('ext|g|__value__|0'), 'A gap, not a zero, for an empty category');
        Assert.isFalse(shape.cutPanels);
        Assert.areEqual(0, shape.hiddenPanels);
    }

    @IsTest
    static void panelsBeyondMaxPanelsAreCutWithAFlag() {
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        for (Integer i = 1; i <= 5; i++) {
            rows.put('p' + i, 'Panel ' + i, 'a', 'A', null, null, new List<Object>{ i });
        }
        BoardChartPanels.Settings panels = new BoardChartPanels.Settings();
        panels.maxPanels = 3;
        panels.panelSort = 'VALUE_DESC';

        BoardChartPanels.PanelShape shape = BoardChartPanels.shape(
            chart(new List<String>{ 'COUNT' }),
            panels,
            rows.rows
        );

        Assert.areEqual(3, shape.panels.size());
        Assert.areEqual('p5', shape.panels[0].key, 'Sorted by the Measure total, high to low');
        Assert.areEqual('p4', shape.panels[1].key);
        Assert.areEqual('p3', shape.panels[2].key);
        Assert.isTrue(shape.cutPanels);
        Assert.areEqual(2, shape.hiddenPanels);
        Assert.areEqual(3, shape.points.size(), 'No points of cut panels');

        panels.panelSort = 'VALUE_ASC';
        shape = BoardChartPanels.shape(chart(new List<String>{ 'COUNT' }), panels, rows.rows);
        Assert.areEqual('p1', shape.panels[0].key, 'Low to high');
    }

    @IsTest
    static void panelSortByASecondMeasureAndByPicklistOrder() {
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(2);
        rows.put('x', 'X', 'a', 'A', null, null, new List<Object>{ 100, 1 });
        rows.put('y', 'Y', 'a', 'A', null, null, new List<Object>{ 1, 100 });
        BoardChartPanels.Settings panels = new BoardChartPanels.Settings();
        panels.panelSort = 'VALUE_DESC';
        panels.panelSortMeasure = 1;

        BoardChartPanels.PanelShape shape = BoardChartPanels.shape(
            chart(new List<String>{ 'SUM', 'COUNT' }),
            panels,
            rows.rows
        );
        Assert.areEqual('y', shape.panels[0].key, 'Sorted by the second Measure');

        panels.panelSort = null;
        panels.picklistOrder = new List<String>{ 'y', 'x' };
        shape = BoardChartPanels.shape(chart(new List<String>{ 'SUM', 'COUNT' }), panels, rows.rows);
        Assert.areEqual('y', shape.panels[0].key, 'Picklist order');
        Assert.areEqual('x', shape.panels[1].key);
    }

    @IsTest
    static void datePanelsAreChronological() {
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.put('2026-03', 'Mar 2026', 'a', 'A', null, null, new List<Object>{ 1 });
        rows.put('2025-12', 'Dec 2025', 'a', 'A', null, null, new List<Object>{ 9 });
        BoardChartPanels.Settings panels = new BoardChartPanels.Settings();
        panels.isDatePanel = true;

        BoardChartPanels.PanelShape shape = BoardChartPanels.shape(chart(new List<String>{ 'SUM' }), panels, rows.rows);

        Assert.areEqual('2025-12', shape.panels[0].key);
        Assert.areEqual('Dec 2025', shape.panels[0].label);
        Assert.areEqual('2026-03', shape.panels[1].key);
    }

    @IsTest
    static void blankPanelOnlyWithIncludeBlankAndNoOtherPanel() {
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.put('p', 'P', 'a', 'A', null, null, new List<Object>{ 1 });
        rows.put(null, null, 'a', 'A', null, null, new List<Object>{ 2 });
        rows.put('q', 'Q', null, null, null, null, new List<Object>{ 3 });
        BoardChartPanels.Settings panels = new BoardChartPanels.Settings();
        panels.maxPanels = 2;

        BoardChartPanels.PanelShape shape = BoardChartPanels.shape(chart(new List<String>{ 'SUM' }), panels, rows.rows);
        Assert.areEqual(2, shape.panels.size(), 'Cut panels are not summed into an "Other" panel');
        Assert.areEqual('p', shape.panels[0].key);
        Assert.areEqual('q', shape.panels[1].key, '(Blank) sorts last');
        for (BoardChartEngine.ChartKey panel : shape.panels) {
            Assert.isFalse(panel.isOther);
        }

        BoardChartEngine.Settings noBlank = chart(new List<String>{ 'SUM' });
        noBlank.includeBlank = false;
        panels.maxPanels = 6;
        shape = BoardChartPanels.shape(noBlank, panels, rows.rows);
        Assert.areEqual(1, shape.panels.size(), 'No (Blank) panel, and no panel left empty by a blank category');
        Assert.areEqual('p', shape.panels[0].key);

        shape = BoardChartPanels.shape(chart(new List<String>{ 'SUM' }), panels, rows.rows);
        Assert.areEqual(3, shape.panels.size());
        BoardChartEngine.ChartKey blank = shape.panels[2];
        Assert.isTrue(blank.isBlank);
        Assert.areEqual('(Blank)', blank.label);
        Assert.areEqual(BoardChartEngine.BLANK_KEY, blank.key);
    }

    @IsTest
    static void topNAndOtherAreComputedAcrossAllPanels() {
        BoardChartEngine.Settings settings = chart(new List<String>{ 'SUM' });
        settings.maxCategories = 3;
        settings.overflowMode = 'OTHER';
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        // Across panels: c1 = 60, c2 = 50, c3 = 7, c4 = 4. Panel q alone would rank c3 first.
        rows.put('p', 'P', 'c1', 'One', null, null, new List<Object>{ 60 });
        rows.put('p', 'P', 'c2', 'Two', null, null, new List<Object>{ 50 });
        rows.put('p', 'P', 'c4', 'Four', null, null, new List<Object>{ 1 });
        rows.put('q', 'Q', 'c3', 'Three', null, null, new List<Object>{ 7 });
        rows.put('q', 'Q', 'c4', 'Four', null, null, new List<Object>{ 3 });

        BoardChartPanels.PanelShape shape = BoardChartPanels.shape(
            settings,
            new BoardChartPanels.Settings(),
            rows.rows
        );

        Assert.areEqual(3, shape.categories.size(), 'Every panel shows the same N');
        Assert.areEqual('c1', shape.categories[0].key);
        Assert.areEqual('c2', shape.categories[1].key);
        Assert.isTrue(shape.categories[2].isOther);
        Assert.isTrue(shape.truncatedCategories);
        Assert.areEqual(2, shape.hiddenCategories);
        Map<String, Decimal> values = values(shape);
        Assert.areEqual(1, values.get('p|__other__|__value__|0'), 'Panel p: c4');
        Assert.areEqual(10, values.get('q|__other__|__value__|0'), 'Panel q: c3 + c4');
        Assert.isFalse(values.containsKey('q|c1|__value__|0'));
    }

    @IsTest
    static void seriesAreCappedAcrossPanelsWithOneColourKeyPerValue() {
        BoardChartEngine.Settings settings = chart(new List<String>{ 'COUNT' });
        settings.hasSeries = true;
        settings.maxSeries = 2;
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.put('p', 'P', 'a', 'A', 'won', 'Won', new List<Object>{ 5 });
        rows.put('p', 'P', 'a', 'A', 'lost', 'Lost', new List<Object>{ 2 });
        rows.put('q', 'Q', 'a', 'A', 'won', 'Won', new List<Object>{ 4 });
        rows.put('q', 'Q', 'a', 'A', 'open', 'Open', new List<Object>{ 1 });

        BoardChartPanels.PanelShape shape = BoardChartPanels.shape(
            settings,
            new BoardChartPanels.Settings(),
            rows.rows
        );

        Assert.areEqual(2, shape.series.size());
        Assert.areEqual('won', shape.series[0].key);
        Assert.isTrue(shape.series[1].isOther);
        Assert.isTrue(shape.truncatedSeries);
        Map<String, Decimal> values = values(shape);
        Assert.areEqual(2, values.get('p|a|__other__|0'));
        Assert.areEqual(1, values.get('q|a|__other__|0'));
        for (BoardChartEngine.ChartPoint point : shape.points) {
            Assert.areEqual(point.seriesKey, point.colourKey, 'Same colour key for a value in every panel');
        }
    }

    @IsTest
    static void shareOfTotalIsAShareOfThePanelTotal() {
        BoardChartEngine.Settings settings = chart(new List<String>{ 'SUM' });
        settings.showAs = new List<String>{ BoardChartEngine.SHOW_AS_PERCENT_OF_TOTAL };
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.put('p', 'P', 'a', 'A', null, null, new List<Object>{ 1 });
        rows.put('p', 'P', 'b', 'B', null, null, new List<Object>{ 3 });
        rows.put('q', 'Q', 'a', 'A', null, null, new List<Object>{ 10 });

        Map<String, Decimal> values = values(
            BoardChartPanels.shape(settings, new BoardChartPanels.Settings(), rows.rows)
        );

        Assert.areEqual(0.25, values.get('p|a|__value__|0'));
        Assert.areEqual(0.75, values.get('p|b|__value__|0'));
        Assert.areEqual(1, values.get('q|a|__value__|0'));
    }

    @IsTest
    static void cursorPartialsArePanelledToo() {
        BoardChartEngine.Accumulator rows = new BoardChartEngine.Accumulator(1);
        rows.add('p', 'P', 'a', 'A', null, null, new List<Object>{ 2 });
        rows.add('p', 'P', 'a', 'A', null, null, new List<Object>{ 3 });
        rows.add('q', 'Q', 'a', 'A', null, null, new List<Object>{ 4 });
        BoardChartEngine.Accumulator restored = new BoardChartEngine.Accumulator(1).restore(rows.state());
        restored.add('q', 'Q', 'a', 'A', null, null, new List<Object>{ 1 });

        Map<String, Decimal> values = values(
            BoardChartPanels.shape(chart(new List<String>{ 'SUM' }), new BoardChartPanels.Settings(), restored.rows)
        );

        Assert.areEqual(5, values.get('p|a|__value__|0'));
        Assert.areEqual(5, values.get('q|a|__value__|0'), 'Restored partials keep their panel');
    }

    private static BoardChartEngine.Settings chart(List<String> functions) {
        BoardChartEngine.Settings settings = new BoardChartEngine.Settings();
        settings.aggregateFunctions = functions;
        return settings;
    }

    /** Point values keyed `panel|category|series|measureIndex`. */
    private static Map<String, Decimal> values(BoardChartPanels.PanelShape shape) {
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (BoardChartEngine.ChartPoint point : shape.points) {
            values.put(
                point.panelKey + '|' + point.categoryKey + '|' + point.seriesKey + '|' + point.measureIndex,
                point.value
            );
        }
        return values;
    }
}