/**
 * `BoardErrorPayload` contract shared by the Board Apex services.
 *
 * Services throw `BoardErrors.BoardException` (via `error(...)`) and convert every failure at the `@AuraEnabled`
 * boundary with `toAuraException`, whose message is the serialized payload
 * `{ category, message, filterId, fieldPath, retryable }`. Unknown exceptions get a generic retryable message; their
 * details (which may contain compiled SOQL/SOSL) are logged, never returned.
 */
public with sharing class BoardErrors {
    public static final String CONFIG_ERROR = 'CONFIG_ERROR';
    public static final String ACCESS_ERROR = 'ACCESS_ERROR';
    public static final String LIMIT_EXCEEDED = 'LIMIT_EXCEEDED';
    public static final String QUERY_ERROR = 'QUERY_ERROR';

    @TestVisible
    private static final String GENERIC_MESSAGE = 'The request failed. Retry, or contact your admin.';
    private static final String NON_SELECTIVE_MESSAGE = 'This view spans too many records for a selective query. Narrow the Date Range or add filters to view results.';

    /** Tests: the last unexpected (non-Board) failure turned into the generic message, to report its real cause. */
    @TestVisible
    private static Exception lastUnexpected;

    public static BoardException error(String category, String message, String filterId, String fieldPath) {
        return error(category, message, filterId, fieldPath, false);
    }

    public static BoardException error(
        String category,
        String message,
        String filterId,
        String fieldPath,
        Boolean retryable
    ) {
        BoardException boardError = new BoardException(message);
        boardError.category = category;
        boardError.filterId = filterId;
        boardError.fieldPath = fieldPath;
        boardError.retryable = retryable;
        return boardError;
    }

    /** Serializes any failure into a `BoardErrorPayload` `AuraHandledException`. */
    public static AuraHandledException toAuraException(Exception failure) {
        Map<String, Object> payload = new Map<String, Object>{
            'category' => QUERY_ERROR,
            'message' => GENERIC_MESSAGE,
            'filterId' => null,
            'fieldPath' => null,
            'retryable' => true
        };
        if (failure instanceof BoardException) {
            BoardException boardError = (BoardException) failure;
            payload.put('category', boardError.category);
            payload.put('message', boardError.getMessage());
            payload.put('filterId', boardError.filterId);
            payload.put('fieldPath', boardError.fieldPath);
            payload.put('retryable', boardError.retryable == true);
        } else if (failure instanceof QueryException && failure.getMessage().containsIgnoreCase('non-selective')) {
            payload.put('category', LIMIT_EXCEEDED);
            payload.put('message', NON_SELECTIVE_MESSAGE);
            payload.put('retryable', false);
        } else {
            lastUnexpected = failure;
            System.debug(
                LoggingLevel.ERROR,
                'Board request failed: ' +
                    failure.getTypeName() +
                    ': ' +
                    failure.getMessage() +
                    '\n' +
                    failure.getStackTraceString()
            );
        }
        String serialized = JSON.serialize(payload);
        AuraHandledException auraError = new AuraHandledException(serialized);
        auraError.setMessage(serialized);
        return auraError;
    }

    /** A classified Board failure (`category`, optional `filterId`/`fieldPath`, `retryable`). */
    public class BoardException extends Exception {
        public String category;
        public String filterId;
        public String fieldPath;
        public Boolean retryable;
    }
}