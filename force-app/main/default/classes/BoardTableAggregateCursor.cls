/**
 * Cursor tier of a Table with Detail rows off.
 *
 * A Table whose groups exceed what one `GROUP BY` returns (`BoardTableAggregate.MAX_GROUPS`), or whose scope exceeds
 * the single-aggregate row threshold, reads its scope through `Database.Cursor` chunks (up to the cursor cap; above it
 * the Table is blocked). Each chunk's records are flattened to the paths the aggregate needs, currency values
 * converted to the corporate currency (as SOQL aggregates return them), and folded by `BoardTableAggregateEngine`.
 * The first chunk comes from `queryTable`, the rest from `fetchTableAggregateChunk` with the previous response's
 * `cursor`, `nextOffset` and `partialState`; only the final chunk carries Group rows (final result only).
 */
public with sharing class BoardTableAggregateCursor {
    /** Where a cursor-tier load stands, returned as `TableResult.aggregateCursor`. */
    public class Progress {
        @AuraEnabled
        public Boolean isComplete = false;
        /** Records the scope matches. */
        @AuraEnabled
        public Integer totalRows;
        /** Records read so far. */
        @AuraEnabled
        public Integer processedRows;
        /** Handle, next offset and running groups to send back to `fetchTableAggregateChunk`. */
        @AuraEnabled
        public String cursor;
        @AuraEnabled
        public Integer nextOffset;
        @AuraEnabled
        public String partialState;
    }

    /** One chunk's records as flattened `path -> value` maps, and the load's progress after it. */
    public class Chunk {
        public List<Map<String, Object>> rows = new List<Map<String, Object>>();
        public Progress progress = new Progress();
    }

    /** True for a `fetchTableAggregateChunk` request (it carries the cursor of an earlier chunk). */
    public static Boolean isContinuation(Map<String, Object> request) {
        return BoardQueryService.getString(request, 'cursor') != null;
    }

    /** Records the scope matches; more than the cursor tier aggregates blocks the Table. */
    public static Integer countWithinCap(BoardQueryService.QueryScope scope) {
        Integer totalRows = BoardQueryService.countScopeRows(scope);
        Integer maxRows = BoardQueryService.cursorMaxRows();
        if (totalRows > maxRows) {
            throw BoardErrors.error(
                BoardErrors.LIMIT_EXCEEDED,
                'This Table spans ' +
                    totalRows.format() +
                    ' records, more than the ' +
                    maxRows.format() +
                    ' a Table with Detail rows off can aggregate. Narrow the filters to show it.',
                null,
                null
            );
        }
        return totalRows;
    }

    /** True when one SOQL aggregate cannot read `totalRows` records. */
    public static Boolean exceedsSingleAggregate(Integer totalRows) {
        return totalRows > BoardQueryService.cursorAggregateThreshold();
    }

    /**
     * Reads the next chunk: opens a cursor over the scope on the first call, else continues the request's `cursor`
     * at its `offset`. `isoPathByPath` lists every path to read, mapped to its `CurrencyIsoCode` path when the value
     * converts to the corporate currency (else null).
     */
    public static Chunk read(
        BoardQueryService.QueryScope scope,
        Map<String, Object> request,
        Map<String, String> isoPathByPath
    ) {
        Database.Cursor cursor;
        Integer offset = 0;
        if (isContinuation(request)) {
            cursor = BoardQueryService.restoreCursor(BoardQueryService.getString(request, 'cursor'));
            Integer requestedOffset = BoardQueryService.getInteger(request, 'offset');
            offset = requestedOffset == null ? 0 : requestedOffset;
        } else {
            cursor = Database.getCursorWithBinds(
                scope.buildSoql(selectList(isoPathByPath), null, ''),
                scope.binds,
                AccessLevel.USER_MODE
            );
        }
        BoardQueryService.CursorRows records = BoardQueryService.readCursorRows(cursor, offset);
        BoardCurrencyConverter converter = BoardCurrencyConverter.forRequest();
        Chunk chunk = new Chunk();
        for (SObject record : records.records) {
            Map<String, Object> values = new Map<String, Object>();
            for (String path : isoPathByPath.keySet()) {
                Object value = BoardQueryService.readPath(record, path);
                String isoPath = isoPathByPath.get(path);
                if (isoPath != null && value != null) {
                    value = converter.toCorporate(
                        BoardQueryService.toDecimal(value),
                        (String) BoardQueryService.readPath(record, isoPath)
                    );
                }
                values.put(path, value);
            }
            chunk.rows.add(values);
        }
        chunk.progress.cursor = JSON.serialize(cursor);
        chunk.progress.totalRows = records.totalRows;
        chunk.progress.processedRows = records.nextOffset;
        chunk.progress.nextOffset = records.nextOffset;
        chunk.progress.isComplete = records.nextOffset >= records.totalRows;
        return chunk;
    }

    /** Every path and `CurrencyIsoCode` path once (paths compare case-insensitively). */
    private static String selectList(Map<String, String> isoPathByPath) {
        List<String> paths = new List<String>();
        Set<String> seen = new Set<String>();
        List<String> candidates = new List<String>(isoPathByPath.keySet());
        candidates.addAll(isoPathByPath.values());
        for (String path : candidates) {
            if (path != null && seen.add(path.toLowerCase())) {
                paths.add(path);
            }
        }
        return String.join(paths, ', ');
    }
}