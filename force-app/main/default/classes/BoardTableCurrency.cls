/**
 * Display currency in Table features: Data bar scales and Total, Group and Subtotal summaries of currency columns
 * (columns with a `currencyIsoCode`) come back in the Display currency, consistent with the converted cells.
 *
 * - `SUM`/`AVG` aggregates, every `GROUP BY` summary and the cursor tier are in the corporate currency (SOQL converts
 *   each record to corporate before it aggregates; the cursor tier via `BoardCurrencyConverter.toCorporate`). They are
 *   converted corporate -> Display once, at the end; a positive rate keeps MIN/MAX and summary order.
 * - Ungrouped MIN/MAX over the whole scope (Total row, record-level Data bar scale) come from the record that wins the
 *   currency-aware `ORDER BY <field> ASC/DESC LIMIT 1`, its own amount converted record -> Display (as the Metric's
 *   MIN/MAX), never from a raw MIN/MAX that could mix record currencies.
 * - Record counts and non-currency columns never convert. Single-currency orgs: unchanged.
 */
public with sharing class BoardTableCurrency {
    private BoardTableCurrency() {
    }

    /**
     * Record-level Data bar scales: each Data bar column's max and min over every record the scope matches, a currency
     * column's converted record -> Display. Each extreme is one `ORDER BY ... LIMIT 1` query reading one row, so a
     * scope of any size stays within the query-row limit (a `MAX`/`MIN` aggregate reads every record).
     */
    public static List<BoardQueryService.BarScale> recordBarScales(
        BoardQueryService.QueryScope scope,
        List<BoardQueryService.TableColumn> barColumns
    ) {
        List<BoardQueryService.BarScale> scales = new List<BoardQueryService.BarScale>();
        for (BoardQueryService.TableColumn column : barColumns) {
            String isoPath = convertingIsoPath(column);
            BoardQueryService.BarScale scale = new BoardQueryService.BarScale();
            scale.columnId = column.id;
            scale.max = extremeToDisplay(scope, column, isoPath, 'MAX');
            scale.min = extremeToDisplay(scope, column, isoPath, 'MIN');
            scales.add(scale);
        }
        return scales;
    }

    /**
     * Whole-scope Total row: replaces the MIN and MAX of each currency column with the extreme record's amount
     * converted record -> Display. `totals` are index-aligned with `specs`; the other summaries are left as they are.
     */
    public static List<BoardTableEngine.ColumnTotal> scopeExtremesToDisplay(
        BoardQueryService.QueryScope scope,
        List<BoardTableEngine.ColumnTotal> totals,
        List<BoardTableEngine.SummarySpec> specs,
        List<BoardQueryService.TableColumn> columns
    ) {
        if (totals == null) {
            return totals;
        }
        Map<String, BoardQueryService.TableColumn> columnsById = new Map<String, BoardQueryService.TableColumn>();
        for (BoardQueryService.TableColumn column : columns) {
            columnsById.put(column.id, column);
        }
        for (Integer c = 0; c < totals.size() && c < specs.size(); c++) {
            BoardQueryService.TableColumn column = columnsById.get(specs[c].columnId);
            String isoPath = column == null ? null : convertingIsoPath(column);
            if (isoPath == null) {
                continue;
            }
            for (BoardTableEngine.SummaryValue summary : totals[c].summaries) {
                if (summary.summaryFunction == 'MIN' || summary.summaryFunction == 'MAX') {
                    summary.value = extremeToDisplay(scope, column, isoPath, summary.summaryFunction);
                }
            }
        }
        return totals;
    }

    /**
     * Group rows of an aggregated table (Detail rows off): each currency column's summaries and its value through the
     * group lookup, corporate -> Display. Counts stay as they are.
     */
    public static BoardQueryService.TableResult groupRowsToDisplay(BoardQueryService.TableResult result) {
        if (result.aggregateGroups == null) {
            return result;
        }
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        for (BoardTableAggregate.GroupRow groupRow : result.aggregateGroups) {
            converter.totalsToDisplay(groupRow.summaries, result.columns);
            for (BoardQueryService.TableColumn column : result.columns) {
                if (
                    column.currencyIsoCode != null &&
                    groupRow.values != null &&
                    groupRow.values.containsKey(column.fieldPath)
                ) {
                    groupRow.values.put(
                        column.fieldPath,
                        converter.fromCorporate(groupRow.values.get(column.fieldPath), column.currencyIsoCode)
                    );
                }
            }
        }
        return result;
    }

    /** Group and Subtotal summaries of a grouped page (Detail rows on): currency columns' corporate -> Display. */
    public static List<BoardTableEngine.TableGroup> groupsToDisplay(
        List<BoardTableEngine.TableGroup> groups,
        List<BoardQueryService.TableColumn> columns
    ) {
        if (groups == null) {
            return groups;
        }
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        for (BoardTableEngine.TableGroup tableGroup : groups) {
            converter.totalsToDisplay(tableGroup.summaries, columns);
        }
        return groups;
    }

    /** `CurrencyIsoCode` path of a currency column whose values convert; null otherwise (and in single-currency orgs). */
    private static String convertingIsoPath(BoardQueryService.TableColumn column) {
        return column.currencyIsoCode == null ? null : BoardCurrencyConverter.forRequest().tableIsoCodePath(column);
    }

    /**
     * The largest (`MAX`) or smallest (`MIN`) value of `column` over the scope; with an `isoPath` (a converting currency
     * column) in the Display currency: `ORDER BY` on a currency field compares converted amounts, so the winning record
     * is right; its own amount is then converted.
     */
    private static Decimal extremeToDisplay(
        BoardQueryService.QueryScope scope,
        BoardQueryService.TableColumn column,
        String isoPath,
        String extreme
    ) {
        String direction = extreme == 'MIN' ? ' ASC' : ' DESC';
        List<SObject> records = Database.queryWithBinds(
            scope.buildSoql(
                column.fieldPath + (isoPath == null ? '' : ', ' + isoPath),
                new List<String>{ column.fieldPath + ' != null' },
                'ORDER BY ' + column.fieldPath + direction + ' LIMIT 1'
            ),
            scope.binds,
            AccessLevel.USER_MODE
        );
        if (records.isEmpty()) {
            return null;
        }
        Decimal amount = BoardQueryService.toDecimal(BoardQueryService.readPath(records[0], column.fieldPath));
        if (isoPath == null) {
            return amount;
        }
        String recordIsoCode = (String) BoardQueryService.readPath(records[0], isoPath);
        if (amount == null || recordIsoCode == null) {
            return amount;
        }
        return BoardCurrencyConverter.forRequest().convert(amount, recordIsoCode, column.currencyIsoCode);
    }
}