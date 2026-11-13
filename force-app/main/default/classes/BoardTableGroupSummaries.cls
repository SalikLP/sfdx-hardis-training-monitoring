/**
 * Group summaries of a Table with Row grouping (Detail rows on): each group's Stacked summaries over the whole group,
 * read from the same page-scoped `GROUP BY` that counts the group, so Group and Subtotal rows show full-group figures
 * even when the group spans pages.
 *
 * For every summarized column the `GROUP BY` selects `SUM`, `COUNT`, `MIN` and `MAX` of the field; aggregate rows of
 * the same group key (text keys fold case) merge into one `BoardTableEngine.Summary`, which then yields the column's
 * configured summaries in order. Keyed by the caller's group key, so it serves any grouping level.
 */
public with sharing class BoardTableGroupSummaries {
    private final List<BoardTableEngine.SummarySpec> specs;
    private final Map<String, List<BoardTableEngine.Summary>> summariesByKey = new Map<String, List<BoardTableEngine.Summary>>();

    public BoardTableGroupSummaries(List<BoardTableEngine.SummarySpec> specs) {
        this.specs = specs == null ? new List<BoardTableEngine.SummarySpec>() : specs;
    }

    /** Extra `GROUP BY` select items (each starting with `, `), or `''` when no column is summarized. */
    public String aggregateSelect() {
        List<String> items = new List<String>();
        for (Integer c = 0; c < specs.size(); c++) {
            String path = specs[c].fieldPath;
            items.add('SUM(' + path + ') ' + alias(c, 'sum'));
            items.add('COUNT(' + path + ') ' + alias(c, 'cnt'));
            items.add('MIN(' + path + ') ' + alias(c, 'min'));
            items.add('MAX(' + path + ') ' + alias(c, 'max'));
        }
        return items.isEmpty() ? '' : ', ' + String.join(items, ', ');
    }

    /** Merges one aggregate row of the `GROUP BY` into the summaries of group `key`. */
    public void add(String key, AggregateResult aggregate) {
        if (specs.isEmpty()) {
            return;
        }
        List<BoardTableEngine.Summary> summaries = summariesByKey.get(key);
        if (summaries == null) {
            summaries = new List<BoardTableEngine.Summary>();
            for (Integer c = 0; c < specs.size(); c++) {
                summaries.add(new BoardTableEngine.Summary());
            }
            summariesByKey.put(key, summaries);
        }
        for (Integer c = 0; c < specs.size(); c++) {
            summaries[c]
                .addAggregate(
                    aggregate.get(alias(c, 'sum')),
                    aggregate.get(alias(c, 'cnt')),
                    aggregate.get(alias(c, 'min')),
                    aggregate.get(alias(c, 'max'))
                );
        }
    }

    /** Group `key`'s Stacked summaries, one entry per summarized column in column order (empty when none). */
    public List<BoardTableEngine.ColumnTotal> forKey(String key) {
        List<BoardTableEngine.ColumnTotal> totals = new List<BoardTableEngine.ColumnTotal>();
        List<BoardTableEngine.Summary> summaries = summariesByKey.get(key);
        for (Integer c = 0; c < specs.size(); c++) {
            BoardTableEngine.Summary summary = summaries == null ? new BoardTableEngine.Summary() : summaries[c];
            BoardTableEngine.ColumnTotal total = new BoardTableEngine.ColumnTotal(specs[c].columnId);
            for (String summaryFunction : specs[c].functions) {
                total.add(summaryFunction, summary.value(summaryFunction));
            }
            totals.add(total);
        }
        return totals;
    }

    private static String alias(Integer columnIndex, String part) {
        return 'gs' + columnIndex + '_' + part;
    }
}