/**
 * Engine-unit seam for Average per record: Measure settings, folding a record's rows (SUM | ONCE), averaging one value
 * per record, and where a cursor chunk may end (at a record boundary).
 */
@IsTest
private class BoardAveragePerRecordTest {
    @IsTest
    static void readsTheMeasureSettings() {
        Map<String, Object> measure = perRecord('OpportunityId', 'once', 'TotalPrice');

        Assert.isTrue(BoardAveragePerRecord.isPerRecord(measure));
        Assert.isFalse(BoardAveragePerRecord.isPerRecord(new Map<String, Object>{ 'aggregateFunction' => 'AVG' }));
        Assert.isFalse(BoardAveragePerRecord.isPerRecord('not a measure'));
        Assert.areEqual('OpportunityId', BoardAveragePerRecord.perFieldOf(measure));
        Assert.areEqual('ONCE', BoardAveragePerRecord.innerOf(measure, 0), 'Case-insensitive');
        Assert.areEqual(
            'SUM',
            BoardAveragePerRecord.innerOf(perRecord('OpportunityId', null, 'TotalPrice'), 0),
            'Sum of the rows by default'
        );
        Assert.areEqual('SUM(TotalPrice)', BoardAveragePerRecord.innerExpression('SUM', 'TotalPrice'));
        Assert.areEqual('MAX(TotalPrice)', BoardAveragePerRecord.innerExpression('ONCE', 'TotalPrice'));
    }

    @IsTest
    static void aMissingPerRecordFieldOrAnUnknownInnerModeIsAConfigError() {
        expectConfigError(perRecord(null, 'SUM', 'TotalPrice'), 'per-record');
        expectConfigError(perRecord('OpportunityId', 'MEDIAN', 'TotalPrice'), 'SUM or ONCE');
    }

    @IsTest
    static void perRecordMeasuresGroupApartFromPlainMeasuresAndByPerRecordField() {
        BoardMeasureGroups groups = new BoardMeasureGroups(
            new List<Object>{
                new Map<String, Object>{ 'aggregateFunction' => 'SUM', 'valueFieldApiName' => 'TotalPrice' },
                perRecord('OpportunityId', 'SUM', 'TotalPrice'),
                perRecord('opportunityid', 'ONCE', 'Quantity'),
                perRecord('Product2Id', 'SUM', 'TotalPrice')
            }
        );

        Assert.areEqual(3, groups.groups.size(), 'Plain, per Opportunity, per Product');
        Assert.isNull(groups.groups[0].perField);
        Assert.areEqual(new List<Integer>{ 1, 2 }, groups.groups[1].measureIndexes, 'One query per per-record field');
        Assert.areEqual('OpportunityId', groups.groups[1].perField);
        Assert.areEqual('Product2Id', groups.groups[2].perField);
    }

    @IsTest
    static void foldSumsOrTakesOneValuePerRecordThenAveragesPerCategory() {
        // Measure 0 plain (not folded), 1 SUM per record, 2 ONCE per record.
        BoardAveragePerRecord.RecordFold fold = new BoardAveragePerRecord.RecordFold(
            new List<String>{ null, 'SUM', 'ONCE' }
        );
        fold.add('Hardware', 'Hardware', null, null, 'opp1', values(9, 100, 30));
        fold.add('Hardware', 'Hardware', null, null, 'opp1', values(9, 50, 30));
        fold.add('Hardware', 'Hardware', null, null, 'opp2', values(9, 300, 10));
        fold.add('Hardware', 'Hardware', null, null, 'opp3', values(9, null, null));
        fold.add('Hardware', 'Hardware', null, null, null, values(9, 1000, 1000));
        fold.add('Software', 'Software', null, null, 'opp1', values(9, 20, 30));

        BoardChartEngine.Accumulator accumulator = new BoardChartEngine.Accumulator(3);
        fold.putInto(accumulator);

        Map<String, BoardChartEngine.GroupedRow> rows = byCategory(accumulator);
        BoardChartEngine.GroupedRow hardware = rows.get('Hardware');
        Assert.areEqual(
            225.00,
            hardware.value(1, 'AVG_PER').setScale(2),
            'Deal sizes 150 and 300; null record and no-record row skipped'
        );
        Assert.areEqual(20.00, hardware.value(2, 'AVG_PER').setScale(2), 'Once per record: 30 and 10');
        Assert.areEqual(0, hardware.partials[0].count, 'Plain Measures are not folded');
        Assert.areEqual(20.00, rows.get('Software').value(1, 'AVG_PER').setScale(2));
    }

    @IsTest
    static void aChunkEndsBeforeTheRowsOfItsLastRecord() {
        List<Object> keys = new List<Object>{ 'a', 'a', 'b', 'c', 'c' };

        Assert.areEqual(3, BoardAveragePerRecord.completeRecords(keys, false), 'c continues in the next chunk');
        Assert.areEqual(5, BoardAveragePerRecord.completeRecords(keys, true), 'Last chunk: every row');
        Assert.areEqual(
            3,
            BoardAveragePerRecord.completeRecords(new List<Object>{ null, 'a', null }, false),
            'Rows without a record are skipped, never held back'
        );
        Assert.areEqual(0, BoardAveragePerRecord.completeRecords(new List<Object>(), false));
        try {
            BoardAveragePerRecord.completeRecords(new List<Object>{ 'a', 'a' }, false);
            Assert.fail('A record spanning a whole chunk cannot be averaged');
        } catch (BoardErrors.BoardException error) {
            Assert.areEqual(BoardErrors.LIMIT_EXCEEDED, error.category);
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------

    private static Map<String, Object> perRecord(String perField, String innerMode, String valueField) {
        return new Map<String, Object>{
            'aggregateFunction' => 'AVG_PER',
            'perField' => perField,
            'inner' => innerMode,
            'valueFieldApiName' => valueField
        };
    }

    private static List<Object> values(Decimal plain, Decimal summed, Decimal once) {
        return new List<Object>{ plain, summed, once };
    }

    private static Map<String, BoardChartEngine.GroupedRow> byCategory(BoardChartEngine.Accumulator accumulator) {
        Map<String, BoardChartEngine.GroupedRow> rows = new Map<String, BoardChartEngine.GroupedRow>();
        for (BoardChartEngine.GroupedRow row : accumulator.rows) {
            rows.put(row.categoryValue, row);
        }
        return rows;
    }

    private static void expectConfigError(Map<String, Object> measure, String fragment) {
        try {
            BoardAveragePerRecord.requirePerField(measure, 0);
            BoardAveragePerRecord.innerOf(measure, 0);
            Assert.fail('Expected a config error');
        } catch (BoardErrors.BoardException error) {
            Assert.areEqual(BoardErrors.CONFIG_ERROR, error.category);
            Assert.isTrue(error.getMessage().contains(fragment), error.getMessage());
        }
    }
}