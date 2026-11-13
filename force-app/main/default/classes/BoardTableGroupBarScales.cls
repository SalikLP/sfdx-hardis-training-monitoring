/**
 * Data bar scales of an aggregated table (Row grouping with Detail rows off): bars sit on Group rows, so each Data bar
 * column is scaled over the Group rows rather than the records. A column with summaries is scaled over its first
 * summary (the value its Group-row bar shows); any other Data bar column (a number reached through the lookup group
 * field) over its value per group. Groups without a value are skipped; no values leave the scale's max and min null.
 */
public with sharing class BoardTableGroupBarScales {
    private BoardTableGroupBarScales() {
    }

    /** One scale per Data bar column (in column order) over `groupRows`. */
    public static List<BoardQueryService.BarScale> overGroups(
        List<BoardQueryService.TableColumn> barColumns,
        List<BoardTableAggregate.GroupRow> groupRows
    ) {
        List<BoardQueryService.BarScale> scales = new List<BoardQueryService.BarScale>();
        List<BoardTableAggregate.GroupRow> scaledRows = groupRows == null
            ? new List<BoardTableAggregate.GroupRow>()
            : groupRows;
        for (BoardQueryService.TableColumn barColumn : barColumns) {
            BoardQueryService.BarScale scale = new BoardQueryService.BarScale();
            scale.columnId = barColumn.id;
            for (BoardTableAggregate.GroupRow groupRow : scaledRows) {
                Decimal value = barValue(barColumn, groupRow);
                if (value != null) {
                    scale.max = scale.max == null ? value : Math.max(scale.max, value);
                    scale.min = scale.min == null ? value : Math.min(scale.min, value);
                }
            }
            scales.add(scale);
        }
        return scales;
    }

    /** The number a Group row's bar shows: the column's first summary, else its value through the group lookup. */
    private static Decimal barValue(BoardQueryService.TableColumn barColumn, BoardTableAggregate.GroupRow groupRow) {
        for (BoardTableEngine.ColumnTotal columnSummaries : groupRow.summaries) {
            if (columnSummaries.columnId == barColumn.id) {
                return columnSummaries.summaries.isEmpty() ? null : columnSummaries.summaries[0].value;
            }
        }
        return groupRow.values == null ? null : BoardQueryService.toDecimal(groupRow.values.get(barColumn.fieldPath));
    }
}