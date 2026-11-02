/**
 * User Mode org schema describe and lookup service for Board Flow CPEs and runtime Filter widgets.
 *
 * Every entrypoint enforces the running user's object (CRUD) and field (FLS) visibility via describe checks,
 * `AccessLevel.USER_MODE` queries, and `Security.stripInaccessible(AccessType.READABLE, ...)`. Every failure is thrown
 * as an `AuraHandledException` whose message is a serialized `BoardErrorPayload`
 * (`{ category, message, filterId, fieldPath, retryable }`, see `BoardErrors`).
 *
 * Every method accepts a trailing `refreshToken` that is ignored by the implementation; callers pass the Board's
 * current token so a Board Refresh varies the `cacheable=true` cache key.
 */
public with sharing class BoardSchemaService {
    @TestVisible
    private static final Integer MAX_SEARCH_RESULTS = 20;
    /** Max distinct object types `resolveRecordLabels` queries (one SOQL each). */
    @TestVisible
    private static final Integer MAX_LABEL_OBJECT_TYPES = 20;
    private static final String ENTITY_TYPE_USER = 'User';
    private static final String ENTITY_TYPE_QUEUE = 'Queue';
    private static final Set<Schema.DisplayType> PICKLIST_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.MULTIPICKLIST
    };

    // Transaction-scoped name field cache (keys are lower-cased API names).
    private static final Map<String, String> NAME_FIELD_CACHE = new Map<String, String>();

    /**
     * Lists every object the running user can read and query (including non-UI-API objects such as `CaseComment`
     * and `FeedItem`), sorted by label. Uses deferred describes only (no field maps), so it stays cheap in orgs with
     * thousands of objects; name fields come from `getObjectFields` (`isNameField`).
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectInfo> getQueryableObjects(Integer refreshToken) {
        try {
            List<ObjectInfo> objects = new List<ObjectInfo>();
            for (Schema.SObjectType objectType : BoardDescribe.getGlobalDescribe().values()) {
                Schema.DescribeSObjectResult objectDescribe = BoardDescribe.describeObject(objectType);
                if (!BoardDescribe.isReadableObject(objectDescribe) || objectDescribe.isDeprecatedAndHidden()) {
                    continue;
                }
                objects.add(new ObjectInfo(objectDescribe));
            }
            objects.sort();
            return objects;
        } catch (Exception failure) {
            throw BoardErrors.toAuraException(failure);
        }
    }

    /**
     * Lists the fields of `objectApiName` readable by the running user, with capability flags for the CPE field
     * picker. Parent hops are traversed by calling this method again with a field's `referenceTo` object.
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getObjectFields(String objectApiName, Integer refreshToken) {
        try {
            Schema.DescribeSObjectResult objectDescribe = BoardDescribe.requireReadableObject(objectApiName);
            List<FieldInfo> fields = new List<FieldInfo>();
            for (Schema.SObjectField field : objectDescribe.fields.getMap().values()) {
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                if (fieldDescribe.isAccessible()) {
                    fields.add(new FieldInfo(fieldDescribe, getReferenceTo(fieldDescribe)));
                }
            }
            fields.sort();
            return fields;
        } catch (Exception failure) {
            throw BoardErrors.toAuraException(failure);
        }
    }

    /**
     * Lists child relationships of `objectApiName` whose child object is readable and queryable and whose foreign
     * key field is readable and filterable by the running user. `relationshipName` is null for relationships that
     * cannot be used as SOQL subqueries (e.g. `Case` -> `FeedItem.ParentId`); those remain usable through
     * `childObjectApiName` + `foreignKeyField` (sub-row fetches and `Child(FK).Field` semi-joins).
     */
    @AuraEnabled(cacheable=true)
    public static List<ChildRelationshipInfo> getChildRelationships(String objectApiName, Integer refreshToken) {
        try {
            Schema.DescribeSObjectResult objectDescribe = BoardDescribe.requireReadableObject(objectApiName);
            List<ChildRelationshipInfo> relationships = new List<ChildRelationshipInfo>();
            for (Schema.ChildRelationship relationship : objectDescribe.getChildRelationships()) {
                if (relationship.getField() == null) {
                    continue;
                }
                Schema.DescribeSObjectResult childDescribe = BoardDescribe.describeObject(
                    relationship.getChildSObject()
                );
                if (!BoardDescribe.isReadableObject(childDescribe)) {
                    continue;
                }
                Schema.DescribeFieldResult foreignKeyDescribe = relationship.getField().getDescribe();
                if (!foreignKeyDescribe.isAccessible() || !foreignKeyDescribe.isFilterable()) {
                    continue;
                }
                relationships.add(new ChildRelationshipInfo(relationship, childDescribe, foreignKeyDescribe));
            }
            relationships.sort();
            return relationships;
        } catch (Exception failure) {
            throw BoardErrors.toAuraException(failure);
        }
    }

    /**
     * Returns the active, user-locale-translated entries of a `Picklist` or `MultiPicklist` field, failing closed
     * with `ACCESS_ERROR` when the object or field is not readable by the running user.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getPicklistOptions(
        String objectApiName,
        String fieldApiName,
        Integer refreshToken
    ) {
        try {
            Schema.DescribeSObjectResult objectDescribe = BoardDescribe.requireReadableObject(objectApiName);
            Schema.SObjectField field = String.isBlank(fieldApiName)
                ? null
                : objectDescribe.fields.getMap().get(fieldApiName.trim());
            String fieldPath = objectApiName + '.' + fieldApiName;
            if (field == null) {
                throw BoardErrors.error(BoardErrors.CONFIG_ERROR, 'Unknown field: ' + fieldPath, null, fieldPath);
            }
            Schema.DescribeFieldResult fieldDescribe = BoardDescribe.requireReadableField(
                objectDescribe.getName(),
                field.getDescribe(),
                null,
                fieldPath
            );
            if (!PICKLIST_TYPES.contains(fieldDescribe.getType())) {
                throw BoardErrors.error(
                    BoardErrors.CONFIG_ERROR,
                    'Field is not a picklist: ' + fieldPath,
                    null,
                    fieldPath
                );
            }
            List<PicklistOption> options = new List<PicklistOption>();
            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                if (entry.isActive()) {
                    options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
                }
            }
            return options;
        } catch (Exception failure) {
            throw BoardErrors.toAuraException(failure);
        }
    }

    /**
     * Resolves 15/18-character record IDs (across any mix of objects) to their primary name field value. Records,
     * objects, and name fields not readable in User Mode are omitted, as are malformed IDs, objects without a name
     * field, objects whose query fails (e.g. objects requiring a mandatory filter), and object types beyond the first
     * `MAX_LABEL_OBJECT_TYPES`. Result keys echo the IDs exactly as supplied.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> resolveRecordLabels(List<String> recordIds, Integer refreshToken) {
        try {
            Map<String, String> labels = new Map<String, String>();
            if (recordIds == null || recordIds.isEmpty()) {
                return labels;
            }
            Map<Schema.SObjectType, Map<Id, List<String>>> idsByType = groupIdsByType(recordIds);
            Integer queriedTypes = 0;
            for (Schema.SObjectType objectType : idsByType.keySet()) {
                if (queriedTypes >= MAX_LABEL_OBJECT_TYPES) {
                    break;
                }
                Schema.DescribeSObjectResult objectDescribe = BoardDescribe.describeObject(objectType);
                if (!BoardDescribe.isReadableObject(objectDescribe)) {
                    continue;
                }
                String nameField = getNameField(objectDescribe);
                if (nameField == null || !objectDescribe.fields.getMap().get(nameField).getDescribe().isAccessible()) {
                    continue;
                }
                queriedTypes++;
                Map<Id, List<String>> requestedIds = idsByType.get(objectType);
                Set<Id> ids = requestedIds.keySet();
                List<SObject> records;
                try {
                    records = Database.queryWithBinds(
                        'SELECT Id, ' + nameField + ' FROM ' + objectDescribe.getName() + ' WHERE Id IN :ids',
                        new Map<String, Object>{ 'ids' => ids },
                        AccessLevel.USER_MODE
                    );
                } catch (QueryException unqueryable) {
                    continue;
                }
                for (SObject record : Security.stripInaccessible(AccessType.READABLE, records).getRecords()) {
                    if (!record.isSet(nameField) || record.get(nameField) == null) {
                        continue;
                    }
                    String label = String.valueOf(record.get(nameField));
                    for (String requestedId : requestedIds.get(record.Id)) {
                        labels.put(requestedId, label);
                    }
                }
            }
            return labels;
        } catch (Exception failure) {
            throw BoardErrors.toAuraException(failure);
        }
    }

    /**
     * Searches active Users (and optionally Queues) by name in User Mode. A blank term returns the first
     * alphabetical matches. Results are sorted by label.
     */
    @AuraEnabled(cacheable=true)
    public static List<UserQueueOption> searchUsersAndQueues(
        String searchTerm,
        Boolean includeQueues,
        Integer refreshToken
    ) {
        try {
            String term = searchTerm == null ? '' : searchTerm.trim();
            Map<String, Object> binds = new Map<String, Object>{
                'namePattern' => '%' +
                BoardDescribe.escapeLike(term) +
                '%'
            };
            List<UserQueueOption> options = new List<UserQueueOption>();
            String userQuery =
                'SELECT Id, Name FROM User WHERE IsActive = true AND Name LIKE :namePattern ORDER BY Name LIMIT ' +
                MAX_SEARCH_RESULTS;
            addOptions(options, Database.queryWithBinds(userQuery, binds, AccessLevel.USER_MODE), ENTITY_TYPE_USER);
            if (includeQueues == true) {
                String queueQuery =
                    'SELECT Id, Name FROM Group WHERE Type = \'Queue\' AND Name LIKE :namePattern ORDER BY Name LIMIT ' +
                    MAX_SEARCH_RESULTS;
                addOptions(
                    options,
                    Database.queryWithBinds(queueQuery, binds, AccessLevel.USER_MODE),
                    ENTITY_TYPE_QUEUE
                );
            }
            options.sort();
            return options;
        } catch (Exception failure) {
            throw BoardErrors.toAuraException(failure);
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Describe helpers
    // ---------------------------------------------------------------------------------------------------------

    /** Returns the namespace-safe API name of the object's primary name field, or null when it has none. */
    private static String getNameField(Schema.DescribeSObjectResult objectDescribe) {
        String cacheKey = objectDescribe.getName().toLowerCase();
        if (NAME_FIELD_CACHE.containsKey(cacheKey)) {
            return NAME_FIELD_CACHE.get(cacheKey);
        }
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        String nameField = null;
        Schema.SObjectField conventionalNameField = fieldMap.get('Name');
        if (conventionalNameField != null && conventionalNameField.getDescribe().isNameField()) {
            nameField = conventionalNameField.getDescribe().getName();
        } else {
            for (Schema.SObjectField field : fieldMap.values()) {
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                if (fieldDescribe.isNameField()) {
                    nameField = fieldDescribe.getName();
                    break;
                }
            }
        }
        NAME_FIELD_CACHE.put(cacheKey, nameField);
        return nameField;
    }

    private static List<String> getReferenceTo(Schema.DescribeFieldResult fieldDescribe) {
        List<String> referenceTo = new List<String>();
        for (Schema.SObjectType targetType : fieldDescribe.getReferenceTo()) {
            referenceTo.add(BoardDescribe.describeObject(targetType).getName());
        }
        return referenceTo;
    }

    // ---------------------------------------------------------------------------------------------------------
    // Lookup helpers
    // ---------------------------------------------------------------------------------------------------------

    /** Groups valid IDs by object type, keeping every supplied spelling (15 or 18 chars) of each record ID. */
    private static Map<Schema.SObjectType, Map<Id, List<String>>> groupIdsByType(List<String> recordIds) {
        Map<Schema.SObjectType, Map<Id, List<String>>> idsByType = new Map<Schema.SObjectType, Map<Id, List<String>>>();
        for (String rawId : recordIds) {
            Id recordId = BoardDescribe.toId(rawId);
            Schema.SObjectType objectType = recordId == null ? null : recordId.getSObjectType();
            if (objectType == null) {
                continue;
            }
            if (!idsByType.containsKey(objectType)) {
                idsByType.put(objectType, new Map<Id, List<String>>());
            }
            Map<Id, List<String>> requestedIds = idsByType.get(objectType);
            if (!requestedIds.containsKey(recordId)) {
                requestedIds.put(recordId, new List<String>());
            }
            requestedIds.get(recordId).add(rawId);
        }
        return idsByType;
    }

    private static void addOptions(List<UserQueueOption> options, List<SObject> records, String entityType) {
        for (SObject record : Security.stripInaccessible(AccessType.READABLE, records).getRecords()) {
            options.add(new UserQueueOption(String.valueOf(record.Id), (String) record.get('Name'), entityType));
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // DTOs
    // ---------------------------------------------------------------------------------------------------------

    public class ObjectInfo implements Comparable {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String pluralLabel;
        @AuraEnabled
        public Boolean isCustom;

        ObjectInfo(Schema.DescribeSObjectResult objectDescribe) {
            this.apiName = objectDescribe.getName();
            this.label = objectDescribe.getLabel();
            this.pluralLabel = objectDescribe.getLabelPlural();
            this.isCustom = objectDescribe.isCustom();
        }

        public Integer compareTo(Object other) {
            ObjectInfo that = (ObjectInfo) other;
            return compareByLabel(label, apiName, that.label, that.apiName);
        }
    }

    public class FieldInfo implements Comparable {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String dataType;
        @AuraEnabled
        public Boolean isFilterable;
        @AuraEnabled
        public Boolean isGroupable;
        @AuraEnabled
        public Boolean isSortable;
        @AuraEnabled
        public Boolean isNumeric;
        @AuraEnabled
        public Boolean isNameField;
        @AuraEnabled
        public List<String> referenceTo;
        @AuraEnabled
        public String relationshipName;

        FieldInfo(Schema.DescribeFieldResult fieldDescribe, List<String> referenceTo) {
            this.apiName = fieldDescribe.getName();
            this.label = fieldDescribe.getLabel();
            this.dataType = fieldDescribe.getType().name();
            this.isFilterable = fieldDescribe.isFilterable();
            this.isGroupable = fieldDescribe.isGroupable();
            this.isSortable = fieldDescribe.isSortable();
            this.isNumeric = BoardDescribe.NUMERIC_TYPES.contains(fieldDescribe.getType());
            this.isNameField = fieldDescribe.isNameField();
            this.referenceTo = referenceTo;
            this.relationshipName = fieldDescribe.getRelationshipName();
        }

        public Integer compareTo(Object other) {
            FieldInfo that = (FieldInfo) other;
            return compareByLabel(label, apiName, that.label, that.apiName);
        }
    }

    public class ChildRelationshipInfo implements Comparable {
        @AuraEnabled
        public String relationshipName;
        @AuraEnabled
        public String childObjectApiName;
        @AuraEnabled
        public String childObjectLabel;
        @AuraEnabled
        public String foreignKeyField;

        ChildRelationshipInfo(
            Schema.ChildRelationship relationship,
            Schema.DescribeSObjectResult childDescribe,
            Schema.DescribeFieldResult foreignKeyDescribe
        ) {
            this.relationshipName = relationship.getRelationshipName();
            this.childObjectApiName = childDescribe.getName();
            this.childObjectLabel = childDescribe.getLabel();
            this.foreignKeyField = foreignKeyDescribe.getName();
        }

        public Integer compareTo(Object other) {
            ChildRelationshipInfo that = (ChildRelationshipInfo) other;
            return compareByLabel(
                childObjectLabel,
                childObjectApiName + '.' + foreignKeyField,
                that.childObjectLabel,
                that.childObjectApiName + '.' + that.foreignKeyField
            );
        }
    }

    public class PicklistOption {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;

        PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class UserQueueOption implements Comparable {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String entityType;

        UserQueueOption(String recordId, String label, String entityType) {
            this.id = recordId;
            this.label = label;
            this.entityType = entityType;
        }

        public Integer compareTo(Object other) {
            UserQueueOption that = (UserQueueOption) other;
            return compareByLabel(label, id, that.label, that.id);
        }
    }

    private static Integer compareByLabel(String label, String tieBreaker, String otherLabel, String otherTieBreaker) {
        Integer byLabel = (label == null ? '' : label.toLowerCase())
            .compareTo(otherLabel == null ? '' : otherLabel.toLowerCase());
        return byLabel != 0 ? byLabel : tieBreaker.compareTo(otherTieBreaker);
    }
}