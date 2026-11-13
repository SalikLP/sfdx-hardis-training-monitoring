/**
 * Average per record (`aggregateFunction: 'AVG_PER'`): pure, in memory (no SOQL, no describes).
 *
 * A Measure `{ aggregateFunction: 'AVG_PER', perField, inner, valueFieldApiName }` averages one value per record of
 * its per-record lookup `perField` (e.g. `OpportunityId` on Opportunity Product) instead of one per row, so line items
 * don't skew the average. Each record's value is taken with `inner`: `SUM` (default) adds up its rows (deal size),
 * `ONCE` counts a value repeated on every row once (the `MAX` of its rows; days to close). Records whose value is null,
 * and rows without a record, are skipped like a normal average.
 *
 * SOQL tier: the query groups by category (+ series) + `perField` with `innerExpression`, and each returned row is one
 * record's value, averaged per category in Apex (`BoardChartEngine.Accumulator` with `AVG_PER` partials). Cursor tier:
 * the cursor is ordered by `perField`, `RecordFold` folds a chunk's rows into one value per record and category, and
 * `completeRecords` ends every chunk before the rows of its last record, which the next chunk re-reads, so each
 * record's rows are folded in one chunk and the running state stays a plain `{ sum, count }` per category.
 */
public with sharing class BoardAveragePerRecord {
    public static final String AGGREGATE_FUNCTION = 'AVG_PER';
    /** Each record's value is the sum of its rows. */
    public static final String INNER_SUM = 'SUM';
    /** Each record's value is repeated on every row: counted once (the largest of its rows). */
    public static final String INNER_ONCE = 'ONCE';
    private static final Set<String> INNER_MODES = new Set<String>{ INNER_SUM, INNER_ONCE };

    /** True for an Average per record Measure. */
    public static Boolean isPerRecord(Object rawMeasure) {
        if (!(rawMeasure instanceof Map<String, Object>)) {
            return false;
        }
        Object aggregateFunction = ((Map<String, Object>) rawMeasure).get('aggregateFunction');
        return aggregateFunction != null &&
            String.valueOf(aggregateFunction).trim().toUpperCase() == AGGREGATE_FUNCTION;
    }

    /** The Measure's per-record lookup path, trimmed; null when blank. */
    public static String perFieldOf(Object rawMeasure) {
        if (!(rawMeasure instanceof Map<String, Object>)) {
            return null;
        }
        Object perField = ((Map<String, Object>) rawMeasure).get('perField');
        return perField == null || String.isBlank(String.valueOf(perField)) ? null : String.valueOf(perField).trim();
    }

    /** The per-record lookup path of Measure `index` (0-based); a blank one is a config error. */
    public static String requirePerField(Object rawMeasure, Integer index) {
        String perField = perFieldOf(rawMeasure);
        if (perField == null) {
            throw configError(
                'Measure ' +
                    (index + 1) +
                    ': Average per record needs a per-record field (a lookup, e.g. OpportunityId).'
            );
        }
        return perField;
    }

    /** How Measure `index` takes each record's value: `SUM` (default) or `ONCE`; anything else is a config error. */
    public static String innerOf(Object rawMeasure, Integer index) {
        Object raw = rawMeasure instanceof Map<String, Object> ? ((Map<String, Object>) rawMeasure).get('inner') : null;
        if (raw == null || String.isBlank(String.valueOf(raw))) {
            return INNER_SUM;
        }
        String innerMode = String.valueOf(raw).trim().toUpperCase();
        if (!INNER_MODES.contains(innerMode)) {
            throw configError(
                'Measure ' + (index + 1) + ': each record\'s value must be taken as SUM or ONCE, not ' + raw + '.'
            );
        }
        return innerMode;
    }

    /**
     * Measure grouping key suffix: Average per record Measures query per record of their `perField`, so they never
     * share a query with plain Measures, and share one only with Measures of the same per-record field.
     */
    public static String groupKeySuffix(Object rawMeasure) {
        if (!isPerRecord(rawMeasure)) {
            return '';
        }
        String perField = perFieldOf(rawMeasure);
        return '|perRecord:' + (perField == null ? '' : perField.toLowerCase());
    }

    /** The `SOQL` aggregate giving one record's value: `SUM(path)`, or `MAX(path)` for `ONCE`. */
    public static String innerExpression(String innerMode, String valuePath) {
        return (innerMode == INNER_ONCE ? 'MAX(' : 'SUM(') + valuePath + ')';
    }

    /**
     * How many leading rows of a cursor chunk (ordered by the per-record field, one record key per row) to read now:
     * every row on the last chunk, else up to the first row of the chunk's last record, which the next chunk re-reads.
     * Rows without a record are never held back. A record spanning a whole chunk can't be folded: `LIMIT_EXCEEDED`.
     */
    public static Integer completeRecords(List<Object> recordKeys, Boolean isLastChunk) {
        Integer size = recordKeys.size();
        if (isLastChunk || size == 0 || recordKeys[size - 1] == null) {
            return size;
        }
        String last = String.valueOf(recordKeys[size - 1]);
        Integer endIndex = size;
        while (
            endIndex > 0 &&
            recordKeys[endIndex - 1] != null &&
            String.valueOf(recordKeys[endIndex - 1]).equals(last)
        ) {
            endIndex--;
        }
        if (endIndex == 0) {
            throw BoardErrors.error(
                BoardErrors.LIMIT_EXCEEDED,
                'One record has too many rows to average per record. Narrow the Date Range or add filters to view results.',
                null,
                null
            );
        }
        return endIndex;
    }

    /**
     * Folds cursor rows into one value per record, category and series for every Average per record Measure (`inners`:
     * one per Widget Measure, null for the other Measures, which are not folded).
     */
    public class RecordFold {
        private List<String> inners;
        private List<FoldedRecord> folded = new List<FoldedRecord>();
        private Map<String, FoldedRecord> index = new Map<String, FoldedRecord>();

        public RecordFold(List<String> inners) {
            this.inners = inners;
        }

        /** One row of record `recordKey` (null: no record, skipped): its value per Widget Measure. */
        public void add(
            String categoryValue,
            String categoryLabel,
            String seriesValue,
            String seriesLabel,
            Object recordKey,
            List<Object> rowValues
        ) {
            add(null, null, categoryValue, categoryLabel, seriesValue, seriesLabel, recordKey, rowValues);
        }

        /** `add` in the Panel of `panelValue` (Small multiples): records fold per Panel, category and series. */
        public void add(
            String panelValue,
            String panelLabel,
            String categoryValue,
            String categoryLabel,
            String seriesValue,
            String seriesLabel,
            Object recordKey,
            List<Object> rowValues
        ) {
            if (recordKey == null) {
                return;
            }
            String key = JSON.serialize(
                new List<String>{ panelValue, categoryValue, seriesValue, String.valueOf(recordKey) }
            );
            FoldedRecord record = index.get(key);
            if (record == null) {
                record = new FoldedRecord(categoryValue, categoryLabel, seriesValue, seriesLabel, inners.size());
                record.panelValue = panelValue;
                record.panelLabel = panelLabel;
                folded.add(record);
                index.put(key, record);
            }
            for (Integer i = 0; i < inners.size(); i++) {
                if (inners[i] != null) {
                    record.fold(i, inners[i], BoardQueryService.toDecimal(rowValues[i]));
                }
            }
        }

        /** Adds each folded record's value to its Panel / category / series row of `accumulator` (others: nothing). */
        public void putInto(BoardChartEngine.Accumulator accumulator) {
            for (FoldedRecord record : folded) {
                accumulator.add(
                    record.panelValue,
                    record.panelLabel,
                    record.categoryValue,
                    record.categoryLabel,
                    record.seriesValue,
                    record.seriesLabel,
                    record.values
                );
            }
        }
    }

    /** One record's folded value per Measure within one category / series. */
    private class FoldedRecord {
        String panelValue;
        String panelLabel;
        String categoryValue;
        String categoryLabel;
        String seriesValue;
        String seriesLabel;
        List<Object> values = new List<Object>();

        FoldedRecord(
            String categoryValue,
            String categoryLabel,
            String seriesValue,
            String seriesLabel,
            Integer measureCount
        ) {
            this.categoryValue = categoryValue;
            this.categoryLabel = categoryLabel;
            this.seriesValue = seriesValue;
            this.seriesLabel = seriesLabel;
            for (Integer i = 0; i < measureCount; i++) {
                values.add(null);
            }
        }

        void fold(Integer measureIndex, String innerMode, Decimal value) {
            if (value == null) {
                return;
            }
            Decimal current = (Decimal) values[measureIndex];
            if (current == null) {
                values[measureIndex] = value;
            } else if (innerMode == INNER_ONCE) {
                values[measureIndex] = Math.max(current, value);
            } else {
                values[measureIndex] = current + value;
            }
        }
    }

    private static BoardErrors.BoardException configError(String message) {
        return BoardErrors.error(BoardErrors.CONFIG_ERROR, message, null, 'measures');
    }
}