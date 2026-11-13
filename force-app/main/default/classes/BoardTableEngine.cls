/**
 * Pure in-memory Table engine: summary computation over rows already in memory, with no SOQL and no describes.
 *
 * The seam the SOQL tier and the cursor tier of the Table share, so Total rows, Group rows and Subtotal rows compute
 * their summaries (and, with Row grouping, order their groups) the same way whichever tier read the rows. Rows are
 * flattened `path -> value` maps (`BoardQueryService.TableRow.values`).
 */
public with sharing class BoardTableEngine {
    /** Table summaries a numeric column can stack (no Count: the badge carries it). */
    public static final Set<String> SUMMARY_FUNCTIONS = new Set<String>{ 'SUM', 'AVG', 'MIN', 'MAX' };

    /** `Schema.DisplayType` names of fields a Data bar can draw: number, currency and percent. */
    private static final Set<String> DATA_BAR_TYPES = new Set<String>{
        'INTEGER',
        'LONG',
        'DOUBLE',
        'CURRENCY',
        'PERCENT'
    };

    public static Boolean isDataBarType(String dataType) {
        return dataType != null && DATA_BAR_TYPES.contains(dataType.toUpperCase());
    }

    /** Max records an ungrouped Table with a Row limit returns. */
    public static final Integer MAX_ROW_LIMIT = 2000;

    /**
     * Validated Row limit: null when unset, else a whole number from 1 to `MAX_ROW_LIMIT`. A Row limit needs a sort,
     * so "Top N" always means something.
     */
    public static Integer resolveRowLimit(Object rawLimit, String sortBy) {
        if (rawLimit == null || (rawLimit instanceof String && String.isBlank((String) rawLimit))) {
            return null;
        }
        Decimal parsed = BoardQueryService.toDecimalOrNull(rawLimit);
        if (parsed == null || parsed != parsed.setScale(0) || parsed < 1 || parsed > MAX_ROW_LIMIT) {
            throw BoardErrors.error(
                BoardErrors.CONFIG_ERROR,
                'Row limit must be a whole number from 1 to 2,000.',
                null,
                'rowLimit'
            );
        }
        if (String.isBlank(sortBy)) {
            throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'A Row limit needs a sort.', null, 'rowLimit');
        }
        return parsed.intValue();
    }

    /** Most summaries one numeric column can stack. */
    public static final Integer MAX_STACKED_SUMMARIES = 4;

    /**
     * A column's ordered Stacked summaries: blank for none, else a list of 1-4 distinct `SUM`/`AVG`/`MIN`/`MAX`
     * (case-insensitive), normalized to upper case in the configured order.
     */
    public static List<String> resolveSummaryFunctions(Object rawSummaries, String columnId) {
        List<String> functions = new List<String>();
        if (rawSummaries == null) {
            return functions;
        }
        if (!(rawSummaries instanceof List<Object>)) {
            throw summariesError(columnId, 'must be a list');
        }
        for (Object rawFunction : (List<Object>) rawSummaries) {
            String name = rawFunction == null ? '' : String.valueOf(rawFunction).trim().toUpperCase();
            if (!SUMMARY_FUNCTIONS.contains(name)) {
                throw summariesError(columnId, 'Sum, Average, Min or Max only (got ' + rawFunction + ')');
            }
            if (functions.contains(name)) {
                throw summariesError(columnId, 'lists ' + name + ' twice');
            }
            functions.add(name);
        }
        if (functions.size() > MAX_STACKED_SUMMARIES) {
            throw summariesError(columnId, 'at most 4');
        }
        return functions;
    }

    private static BoardErrors.BoardException summariesError(String columnId, String problem) {
        return BoardErrors.error(
            BoardErrors.CONFIG_ERROR,
            'Summaries of column ' + columnId + ': ' + problem + '.',
            null,
            'columns'
        );
    }

    /** Total row over in-memory rows: one `ColumnTotal` per spec, its summaries in the spec's order. */
    public static List<ColumnTotal> totalsOverRows(List<Map<String, Object>> rows, List<SummarySpec> specs) {
        List<ColumnTotal> totals = new List<ColumnTotal>();
        for (SummarySpec spec : specs) {
            Summary summary = summarize(rows, spec.fieldPath);
            ColumnTotal total = new ColumnTotal(spec.columnId);
            for (String summaryFunction : spec.functions) {
                total.add(summaryFunction, summary.value(summaryFunction));
            }
            totals.add(total);
        }
        return totals;
    }

    /** One numeric column's Stacked summaries to compute: column id, row value path, ordered functions. */
    public class SummarySpec {
        public String columnId;
        public String fieldPath;
        public List<String> functions;

        public SummarySpec(String columnId, String fieldPath, List<String> functions) {
            this.columnId = columnId;
            this.fieldPath = fieldPath;
            this.functions = functions;
        }
    }

    /** One column's cell in the Total row: its Stacked summaries in the configured order. */
    public class ColumnTotal {
        @AuraEnabled
        public String columnId;
        @AuraEnabled
        public List<SummaryValue> summaries = new List<SummaryValue>();

        public ColumnTotal(String columnId) {
            this.columnId = columnId;
        }

        /** Appends one summary; `rawValue` is any number (or null when no cell had a value). */
        public void add(String summaryFunction, Object rawValue) {
            SummaryValue summary = new SummaryValue();
            summary.summaryFunction = summaryFunction;
            summary.value = BoardQueryService.toDecimal(rawValue);
            summaries.add(summary);
        }
    }

    /** One summary of a column: `SUM`, `AVG`, `MIN` or `MAX` and its value (null when blank). */
    public class SummaryValue {
        @AuraEnabled
        public String summaryFunction;
        @AuraEnabled
        public Decimal value;
    }

    /** Summary of one column over `rows`; blank cells are skipped. */
    public static Summary summarize(List<Map<String, Object>> rows, String fieldPath) {
        Summary summary = new Summary();
        for (Map<String, Object> row : rows) {
            summary.add(row.get(fieldPath));
        }
        return summary;
    }

    /**
     * The distinct groups of group-sorted rows, in row order: one per `keyPath` value (lookups by record Id, so
     * same-named records stay separate; blanks form one group with a null key), labelled by `labelPath` (a lookup's
     * record name) or else by the key. Counts are left to the caller: they cover the whole group, not these rows.
     */
    public static List<TableGroup> groupsInRowOrder(List<Map<String, Object>> rows, String keyPath, String labelPath) {
        List<TableGroup> groups = new List<TableGroup>();
        Set<String> seenKeys = new Set<String>();
        Boolean seenBlank = false;
        for (Map<String, Object> row : rows) {
            Object rawKey = row.get(keyPath);
            String key = rawKey == null ? null : String.valueOf(rawKey);
            if (String.isBlank(key)) {
                if (seenBlank) {
                    continue;
                }
                seenBlank = true;
                key = null;
            } else if (!seenKeys.add(key)) {
                continue;
            }
            TableGroup tableGroup = new TableGroup();
            tableGroup.key = key;
            if (key != null) {
                Object rawLabel = labelPath == null ? rawKey : row.get(labelPath);
                tableGroup.label = rawLabel == null ? key : String.valueOf(rawLabel);
            }
            groups.add(tableGroup);
        }
        return groups;
    }

    /** One group of a Table with Row grouping, as its Group row shows it. */
    public class TableGroup {
        /** Row grouping level: 1 for the first group field, 2 for groups nested under a first-level group. */
        @AuraEnabled
        public Integer level = 1;
        /** Second-level groups: the `key` of the first-level group they are nested under. */
        @AuraEnabled
        public String parentKey;
        /** Group value (record Id for lookups, API value for picklists); null for the "(Blank)" group. */
        @AuraEnabled
        public String key;
        /** Display value (lookup record name, picklist label); null for the "(Blank)" group. */
        @AuraEnabled
        public String label;
        /** Record the Group row links to (lookup groups only). */
        @AuraEnabled
        public String recordId;
        /** Records in the whole group, not only the loaded page. */
        @AuraEnabled
        public Integer count;
        /** Stacked summaries of the whole group (Group and Subtotal rows), one per summarized column; empty when none. */
        @AuraEnabled
        public List<ColumnTotal> summaries = new List<ColumnTotal>();
    }

    /** Running `{ sum, count, min, max }` of one numeric column; mergeable chunk by chunk. */
    public class Summary {
        public Decimal sum = 0;
        public Integer count = 0;
        public Decimal min;
        public Decimal max;

        public void add(Object rawValue) {
            Decimal value = BoardQueryService.toDecimal(rawValue);
            if (value == null) {
                return;
            }
            sum += value;
            count++;
            min = (min == null || value < min) ? value : min;
            max = (max == null || value > max) ? value : max;
        }

        /**
         * Merges a pre-aggregated chunk (`SUM`, `COUNT`, `MIN`, `MAX` of the non-blank cells, e.g. one `GROUP BY`
         * row); a chunk with no non-blank cells changes nothing.
         */
        public void addAggregate(Object rawSum, Object rawCount, Object rawMin, Object rawMax) {
            Decimal chunkCount = BoardQueryService.toDecimal(rawCount);
            if (chunkCount == null || chunkCount == 0) {
                return;
            }
            Decimal chunkSum = BoardQueryService.toDecimal(rawSum);
            Decimal chunkMin = BoardQueryService.toDecimal(rawMin);
            Decimal chunkMax = BoardQueryService.toDecimal(rawMax);
            if (chunkSum != null) {
                sum += chunkSum;
            }
            count += chunkCount.intValue();
            min = (min == null || (chunkMin != null && chunkMin < min)) ? chunkMin : min;
            max = (max == null || (chunkMax != null && chunkMax > max)) ? chunkMax : max;
        }

        /** `SUM`, `AVG`, `MIN` or `MAX`; null when no cell had a value. */
        public Decimal value(String summaryFunction) {
            String name = summaryFunction == null ? null : summaryFunction.trim().toUpperCase();
            if (!SUMMARY_FUNCTIONS.contains(name)) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Unsupported table summary: ' + summaryFunction,
                    null,
                    null
                );
            }
            if (count == 0) {
                return null;
            }
            switch on name {
                when 'SUM' {
                    return sum;
                }
                when 'AVG' {
                    return sum / count;
                }
                when 'MIN' {
                    return min;
                }
                when else {
                    return max;
                }
            }
        }
    }
}