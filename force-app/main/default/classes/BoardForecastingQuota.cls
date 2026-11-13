/**
 * ForecastingQuota as a Cross-object measure source (`BoardCrossObjectMeasures`).
 *
 * The Admin filters quotas on `ForecastingType.DeveloperName` in a Measure condition, so the config is portable and
 * never holds an org's Ids. ForecastingQuota has no ForecastingType relationship (that path fails to query) and the
 * semi-join `ForecastingTypeId IN (SELECT Id FROM ForecastingType WHERE ...)` silently returns no rows, so before the
 * query runs the engine looks the DeveloperNames up itself (one USER_MODE ForecastingType query per source) and turns
 * each such condition into `ForecastingTypeId` with the Ids. Operators: EQ, NEQ, IN, NOT_IN. An unknown DeveloperName,
 * or an org without Forecasting, is a readable config error. Family mapping (`ProductFamily`), month / quarter grouping
 * on `StartDate` and a role bind filter (`QuotaOwner.UserRoleId`) need nothing special.
 *
 * Visibility (the engine is always USER_MODE). ForecastingQuota rows follow the **forecast hierarchy**, which is set
 * per role (`UserRole.ForecastUserId`, the role's forecast manager) and is separate from the role hierarchy:
 * - A rep (or any user without View All Forecasts who isn't a forecast manager) sees only their own quotas. A manager
 *   above them in the role hierarchy does not see them either.
 * - A forecast manager sees their own quotas plus those of users in the direct child roles; grandchild roles only
 *   when every role in between also has a forecast manager. Peers in the manager's own role stay hidden.
 * - Users with View All Forecasts see every quota.
 * Hidden rows drop out silently (no access error), so team and Board totals can be too low. Routes to full totals: a
 * custom target object whose sharing the Admin controls, a set-up forecast hierarchy, or the Quota provider (`BoardQuotaProvider`, a Data
 * provider that reads in system mode for viewers with the custom permission). Granting View All Forecasts is the
 * org's own choice; it opens more than quotas.
 *
 * Forecasting may not be enabled in an org, so ForecastingQuota and ForecastingType are only referenced dynamically.
 */
public with sharing class BoardForecastingQuota {
    public static final String OBJECT_NAME = 'ForecastingQuota';
    public static final String DEVELOPER_NAME_PATH = 'ForecastingType.DeveloperName';
    public static final String TYPE_ID_FIELD = 'ForecastingTypeId';
    private static final String TYPE_OBJECT = 'ForecastingType';
    private static final Set<String> SINGLE_OPERATORS = new Set<String>{ 'EQ', 'NEQ' };
    private static final Set<String> LIST_OPERATORS = new Set<String>{ 'IN', 'NOT_IN' };

    /** Finds ForecastingType Ids by DeveloperName: lower-cased DeveloperName -> Id, only for the names that exist. */
    public interface TypeLookup {
        Map<String, String> idsByDeveloperName(Set<String> developerNames);
    }

    @TestVisible
    private static TypeLookup activeLookup = new OrgTypeLookup();

    /** True when `sourceObject` names ForecastingQuota. */
    public static Boolean isForecastingQuota(String sourceObject) {
        return sourceObject != null && sourceObject.trim().equalsIgnoreCase(OBJECT_NAME);
    }

    /** True when the org has Forecasting (the ForecastingType object exists). */
    public static Boolean isAvailable() {
        return BoardDescribe.getGlobalDescribe().containsKey(TYPE_OBJECT.toLowerCase());
    }

    /**
     * Resolves, in place, the `ForecastingType.DeveloperName` conditions of a Cross-object source's queried Measures
     * (maps with an optional `condition`) when the source is ForecastingQuota; other sources are left alone.
     */
    public static void resolveConditions(String sourceObject, List<Object> measures) {
        if (!isForecastingQuota(sourceObject) || measures == null) {
            return;
        }
        for (Object raw : measures) {
            if (raw instanceof Map<String, Object> && ((Map<String, Object>) raw).get('condition') != null) {
                Map<String, Object> measure = (Map<String, Object>) raw;
                measure.put('condition', resolveCondition(measure.get('condition'), activeLookup));
            }
        }
    }

    /**
     * A copy of a Measure condition tree (`{ logic, conditions[] }` / `{ fieldPath, operator, value }`) with every
     * `ForecastingType.DeveloperName` condition turned into a `ForecastingTypeId` condition on the looked-up Ids. The
     * condition itself when it has none. All DeveloperNames go to `lookup` at once.
     */
    public static Object resolveCondition(Object rawCondition, TypeLookup lookup) {
        Set<String> developerNames = new Set<String>();
        collect(rawCondition, developerNames);
        if (developerNames.isEmpty()) {
            return rawCondition;
        }
        Map<String, String> idsByName = lookup.idsByDeveloperName(developerNames);
        return rewrite(rawCondition, idsByName == null ? new Map<String, String>() : idsByName);
    }

    private static Boolean isDeveloperNameLeaf(Map<String, Object> node) {
        Object path = node.get('fieldPath');
        return !node.containsKey('conditions') &&
            path != null &&
            String.valueOf(path).trim().equalsIgnoreCase(DEVELOPER_NAME_PATH);
    }

    /** Collects the DeveloperNames of the tree's DeveloperName conditions, validating their operators and values. */
    private static void collect(Object raw, Set<String> developerNames) {
        if (!(raw instanceof Map<String, Object>)) {
            return;
        }
        Map<String, Object> node = (Map<String, Object>) raw;
        if (node.get('conditions') instanceof List<Object>) {
            for (Object child : (List<Object>) node.get('conditions')) {
                collect(child, developerNames);
            }
            return;
        }
        if (isDeveloperNameLeaf(node)) {
            developerNames.addAll(namesOf(node));
        }
    }

    /** The DeveloperNames of one condition; a config error for an operator or value the lookup can't serve. */
    private static List<String> namesOf(Map<String, Object> node) {
        String operator = node.get('operator') == null ? '' : String.valueOf(node.get('operator')).trim().toUpperCase();
        Object value = node.get('value');
        List<String> names = new List<String>();
        if (SINGLE_OPERATORS.contains(operator) && !(value instanceof List<Object>)) {
            addName(names, value);
        } else if (LIST_OPERATORS.contains(operator)) {
            for (Object item : value instanceof List<Object> ? (List<Object>) value : new List<Object>{ value }) {
                addName(names, item);
            }
        } else {
            throw configError(
                'A condition on ' + DEVELOPER_NAME_PATH + ' can only use equals, not equals, in or not in.'
            );
        }
        if (names.isEmpty()) {
            throw configError(
                'A condition on ' +
                    DEVELOPER_NAME_PATH +
                    ' needs a ForecastingType DeveloperName (e.g. ' +
                    'OpportunityRevenue).'
            );
        }
        return names;
    }

    private static void addName(List<String> names, Object value) {
        if (value != null && String.isNotBlank(String.valueOf(value))) {
            names.add(String.valueOf(value).trim());
        }
    }

    private static Object rewrite(Object raw, Map<String, String> idsByName) {
        if (!(raw instanceof Map<String, Object>)) {
            return raw;
        }
        Map<String, Object> node = new Map<String, Object>((Map<String, Object>) raw);
        if (node.get('conditions') instanceof List<Object>) {
            List<Object> children = new List<Object>();
            for (Object child : (List<Object>) node.get('conditions')) {
                children.add(rewrite(child, idsByName));
            }
            node.put('conditions', children);
            return node;
        }
        if (!isDeveloperNameLeaf(node)) {
            return node;
        }
        List<Object> typeIds = new List<Object>();
        for (String developerName : namesOf(node)) {
            String typeId = idsByName.get(developerName.toLowerCase());
            if (typeId == null) {
                throw configError(
                    'No ForecastingType with the DeveloperName "' +
                        developerName +
                        '" exists in this org. Check the Measure condition on ' +
                        DEVELOPER_NAME_PATH +
                        ' (e.g. OpportunityRevenue, OpportunityLineItemRevenue).'
                );
            }
            typeIds.add(typeId);
        }
        node.put('fieldPath', TYPE_ID_FIELD);
        node.put('value', node.get('value') instanceof List<Object> ? (Object) typeIds : typeIds[0]);
        return node;
    }

    private static BoardErrors.BoardException configError(String message) {
        return BoardErrors.error(BoardErrors.CONFIG_ERROR, message, null, 'measures');
    }

    /** The org's ForecastingTypes, read in USER_MODE; a config error when the org has no Forecasting. */
    public class OrgTypeLookup implements TypeLookup {
        public Map<String, String> idsByDeveloperName(Set<String> developerNames) {
            if (!isAvailable()) {
                throw configError(
                    'Forecasting isn\'t enabled in this org, so ' +
                        DEVELOPER_NAME_PATH +
                        ' "' +
                        String.join(new List<String>(developerNames), '", "') +
                        '" can\'t be found.'
                );
            }
            Map<String, String> idsByName = new Map<String, String>();
            List<SObject> rows;
            try {
                rows = Database.queryWithBinds(
                    'SELECT Id, DeveloperName FROM ' + TYPE_OBJECT + ' WHERE DeveloperName IN :developerNames',
                    new Map<String, Object>{ 'developerNames' => new List<String>(developerNames) },
                    AccessLevel.USER_MODE
                );
            } catch (System.QueryException failure) {
                throw BoardErrors.error(
                    BoardErrors.ACCESS_ERROR,
                    'You do not have access to ' + TYPE_OBJECT + '.',
                    null,
                    TYPE_OBJECT
                );
            }
            for (SObject row : rows) {
                idsByName.put(String.valueOf(row.get('DeveloperName')).toLowerCase(), String.valueOf(row.Id));
            }
            return idsByName;
        }
    }
}