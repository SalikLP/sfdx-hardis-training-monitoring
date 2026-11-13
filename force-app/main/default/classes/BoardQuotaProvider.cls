/**
 * Quota provider: the Data provider shipped with the product that supplies quota amounts as a Cross-object measure.
 * An Admin names it (`dataProvider: 'BoardQuotaProvider'`) on a Cross-object measure whose source object is
 * ForecastingQuota.
 *
 * - Viewers with the custom permission `Board_ViewAllQuotas` (permission set *Board Quota Viewer*) read in system mode
 *   without sharing: every quota the Filter context allows.
 * - Everyone else reads in USER_MODE: exactly the quotas Salesforce already shows them (their own, plus their team's
 *   when they're a forecast manager in the forecast hierarchy).
 * - No role cap of its own: the Measure's request runs as the engine compiled it, so bound filters (including Team,
 *   `QuotaOwner.UserRoleId`) and the Measure condition (`ForecastingType.DeveloperName`, already turned into
 *   `ForecastingTypeId`) still apply.
 * - ForecastingQuota only, SUM or COUNT of `QuotaAmount`; any other request is rejected as a config error.
 * - Returns corporate amounts (like the standard query); the engine converts them to the Display currency.
 *
 * ForecastingQuota is only referenced dynamically, so this class compiles in orgs without Forecasting.
 */
global with sharing class BoardQuotaProvider implements BoardDataProvider {
    /** Custom permission granting system-mode quota reads (permission set *Board Quota Viewer*). */
    public static final String VIEW_ALL_PERMISSION = 'Board_ViewAllQuotas';
    private static final String AMOUNT_FIELD = 'QuotaAmount';

    /** Runs the Measure's standard query (`request.query`) in system mode or USER_MODE; buckets in corporate currency. */
    public interface QuotaQuery {
        List<BoardDataProviderResult.Bucket> run(Map<String, Object> query, Boolean systemMode);
    }

    @TestVisible
    private static QuotaQuery activeQuery = new EngineQuery();

    global BoardQuotaProvider() {
    }

    global BoardDataProviderResult provide(BoardDataProviderRequest request) {
        BoardDataProviderResult result = new BoardDataProviderResult();
        Boolean isQuotaSource = BoardForecastingQuota.isForecastingQuota(request.objectApiName);
        for (BoardDataProviderRequest.Measure measure : request.measures) {
            String reason = isQuotaSource
                ? measureProblem(measure)
                : 'The Quota provider only reads ForecastingQuota, not ' + request.objectApiName + '.';
            if (reason != null) {
                result.rejectMeasure(measure.index, reason);
            }
        }
        if (!result.rejectedMeasures.isEmpty()) {
            return result;
        }
        result.buckets = activeQuery.run(request.query, canViewAllQuotas());
        return result;
    }

    /** True when the running user has the custom permission `Board_ViewAllQuotas`. */
    public static Boolean canViewAllQuotas() {
        return FeatureManagement.checkPermission(VIEW_ALL_PERMISSION);
    }

    /** Why the Quota provider can't supply `measure` (null when it can: SUM or COUNT of QuotaAmount). */
    private static String measureProblem(BoardDataProviderRequest.Measure measure) {
        String aggregateFunction = measure.aggregateFunction == null ? '' : measure.aggregateFunction.toUpperCase();
        if (aggregateFunction == 'COUNT') {
            return null;
        }
        if (aggregateFunction != 'SUM') {
            return 'The Quota provider supports only SUM or COUNT of ' +
                AMOUNT_FIELD +
                ', not ' +
                aggregateFunction +
                '.';
        }
        String valueField = measure.valueFieldApiName == null ? '' : measure.valueFieldApiName.trim();
        if (!valueField.equalsIgnoreCase(AMOUNT_FIELD)) {
            return 'The Quota provider can only sum ' + AMOUNT_FIELD + ', not ' + valueField + '.';
        }
        return null;
    }

    /** The engine's standard query for the Measure's request, read in the chosen mode. */
    public class EngineQuery implements QuotaQuery {
        public List<BoardDataProviderResult.Bucket> run(Map<String, Object> query, Boolean systemMode) {
            return BoardDataProviders.standardBuckets(query, systemMode ? new SystemModeQueries() : null);
        }
    }

    /**
     * Reads in system mode without sharing: object, field and record access are all ignored. Private, and it checks
     * `Board_ViewAllQuotas` itself on every statement, so no other code path can use it to read in system mode.
     */
    @TestVisible
    private without sharing class SystemModeQueries implements BoardQueryService.QueryExecutor {
        public List<SObject> query(String soql, Map<String, Object> binds) {
            requireViewAll();
            return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
        }

        public Integer countQuery(String soql, Map<String, Object> binds) {
            requireViewAll();
            return Database.countQueryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
        }

        private void requireViewAll() {
            if (!canViewAllQuotas()) {
                throw BoardErrors.error(
                    BoardErrors.ACCESS_ERROR,
                    'Reading all quotas needs the ' + VIEW_ALL_PERMISSION + ' permission.',
                    null,
                    null
                );
            }
        }
    }
}