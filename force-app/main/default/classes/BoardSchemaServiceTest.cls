@IsTest
private class BoardSchemaServiceTest {
    private static final String RESTRICTED_ALIAS = 'brdrstr';
    private static final String SEARCH_TOKEN = 'Zyxwvboard';

    /**
     * Restricted user: `Minimum Access - Salesforce` profile plus a permission set granting Read on Account and Case
     * with field-level Read on `Account.Industry` and `Case.AccountId` only (plus non-FLS-controllable fields such as
     * `Case.Status`). No Contact or Opportunity access.
     */
    @TestSetup
    static void setup() {
        User restrictedUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            restrictedUser = buildUser('Minimum Access - Salesforce', RESTRICTED_ALIAS, SEARCH_TOKEN + ' Restricted');
            User inactiveUser = buildUser('Standard User', 'brdinac', SEARCH_TOKEN + ' Inactive');
            inactiveUser.IsActive = false;
            insert new List<User>{ restrictedUser, inactiveUser };

            PermissionSet permissionSet = new PermissionSet(
                Name = 'BoardSchemaTestAccess',
                Label = 'Board Schema Test'
            );
            insert permissionSet;
            insert new List<ObjectPermissions>{
                new ObjectPermissions(ParentId = permissionSet.Id, SobjectType = 'Account', PermissionsRead = true),
                new ObjectPermissions(ParentId = permissionSet.Id, SobjectType = 'Case', PermissionsRead = true)
            };
            insert new List<FieldPermissions>{
                readField(permissionSet.Id, 'Account', 'Account.Industry'),
                // Case.Status is not FLS-controllable, so Case Read alone makes it readable.
                readField(permissionSet.Id, 'Case', 'Case.AccountId')
            };
            insert new PermissionSetAssignment(AssigneeId = restrictedUser.Id, PermissionSetId = permissionSet.Id);

            insert new Group(Name = SEARCH_TOKEN + ' Queue', Type = 'Queue');
            insert new Group(Name = SEARCH_TOKEN + ' Public Group', Type = 'Regular');
        }

        Account account = new Account(Name = 'Board Account', OwnerId = restrictedUser.Id);
        insert account;
        insert new Contact(FirstName = 'Board', LastName = 'Contact', AccountId = account.Id);
        insert new Opportunity(
            Name = 'Board Opportunity',
            AccountId = account.Id,
            StageName = Opportunity.StageName.getDescribe().getPicklistValues()[0].getValue(),
            CloseDate = Date.today()
        );
        Case supportCase = new Case(Subject = 'Board Case', AccountId = account.Id, OwnerId = restrictedUser.Id);
        insert supportCase;
        insert new CaseComment(ParentId = supportCase.Id, CommentBody = 'Board comment');
        insert new FeedItem(ParentId = supportCase.Id, Body = 'Board feed post');
    }

    @IsTest
    static void restrictedUserSeesOnlyAccessibleObjectsIncludingNonUiApiObjects() {
        List<BoardSchemaService.ObjectInfo> objects;
        System.runAs(restrictedUser()) {
            objects = BoardSchemaService.getQueryableObjects(null);
        }

        Map<String, BoardSchemaService.ObjectInfo> byName = indexObjects(objects);
        Assert.isTrue(byName.containsKey('Account'), 'Account is granted to the restricted user');
        Assert.isTrue(byName.containsKey('Case'), 'Case is granted to the restricted user');
        Assert.isTrue(byName.containsKey('CaseComment'), 'CaseComment inherits access from Case');
        Assert.isTrue(byName.containsKey('FeedItem'), 'FeedItem is a queryable non-UI-API object');
        Assert.isFalse(byName.containsKey('Opportunity'), 'Opportunity is not granted to the restricted user');
        Assert.isFalse(byName.containsKey('Contact'), 'Contact is not granted to the restricted user');

        for (Integer i = 1; i < objects.size(); i++) {
            Assert.isTrue(
                objects[i - 1].label.toLowerCase().compareTo(objects[i].label.toLowerCase()) <= 0,
                'Objects are sorted by label: ' + objects[i - 1].label + ' > ' + objects[i].label
            );
        }
    }

    @IsTest
    static void adminSeesObjectsThatRestrictedUserCannot() {
        Map<String, BoardSchemaService.ObjectInfo> byName = indexObjects(BoardSchemaService.getQueryableObjects(null));

        Assert.isTrue(byName.containsKey('Opportunity'));
        Assert.isTrue(byName.containsKey('Contact'));
        Assert.isFalse(byName.get('Opportunity').isCustom);
    }

    @IsTest
    static void objectFieldsRespectFieldLevelSecurity() {
        Map<String, BoardSchemaService.FieldInfo> accountFields;
        Map<String, BoardSchemaService.FieldInfo> caseFields;
        System.runAs(restrictedUser()) {
            accountFields = indexFields(BoardSchemaService.getObjectFields('Account', 0));
            caseFields = indexFields(BoardSchemaService.getObjectFields('Case', 0));
        }

        Assert.isTrue(accountFields.containsKey('Industry'), 'Industry FLS is granted');
        Assert.isTrue(accountFields.containsKey('Name'), 'Name is always readable');
        Assert.isFalse(accountFields.containsKey('AnnualRevenue'), 'AnnualRevenue FLS is not granted');
        Assert.isTrue(caseFields.containsKey('Status'), 'Case.Status FLS is granted');
        Assert.isFalse(caseFields.containsKey('Priority'), 'Case.Priority FLS is not granted');
    }

    @IsTest
    static void objectFieldsExposeCapabilitiesAndParentHops() {
        Map<String, BoardSchemaService.FieldInfo> contactFields = indexFields(
            BoardSchemaService.getObjectFields('contact', 0)
        );
        Map<String, BoardSchemaService.FieldInfo> accountFields = indexFields(
            BoardSchemaService.getObjectFields('Account', 0)
        );
        Map<String, BoardSchemaService.FieldInfo> caseFields = indexFields(
            BoardSchemaService.getObjectFields('Case', 0)
        );

        // Contact.Account.Parent.Owner.Name hop chain
        Assert.areEqual(new List<String>{ 'Account' }, contactFields.get('AccountId').referenceTo);
        Assert.areEqual('Account', contactFields.get('AccountId').relationshipName);
        Assert.areEqual(new List<String>{ 'Account' }, accountFields.get('ParentId').referenceTo);
        Assert.areEqual('Parent', accountFields.get('ParentId').relationshipName);
        Assert.areEqual('Owner', accountFields.get('OwnerId').relationshipName);
        Assert.isTrue(accountFields.get('OwnerId').referenceTo.contains('User'));
        Assert.isTrue(
            caseFields.get('OwnerId').referenceTo.contains('Group'),
            'Polymorphic Case.OwnerId references Queues (Group)'
        );

        BoardSchemaService.FieldInfo annualRevenue = accountFields.get('AnnualRevenue');
        Assert.areEqual('CURRENCY', annualRevenue.dataType);
        Assert.isTrue(annualRevenue.isNumeric);
        Assert.isFalse(accountFields.get('Industry').isNumeric);
        Assert.isTrue(accountFields.get('Industry').isGroupable);
        Assert.isTrue(accountFields.get('Industry').isFilterable);
        Assert.isFalse(accountFields.get('Description').isFilterable, 'Long text areas are not filterable');
        Assert.isFalse(accountFields.get('Description').isSortable, 'Long text areas are not sortable');
        Assert.isTrue(accountFields.get('Name').isNameField);
        Assert.isFalse(accountFields.get('Industry').isNameField);
        Assert.isTrue(caseFields.get('CaseNumber').isNameField);
        Assert.isNull(accountFields.get('Name').relationshipName);
        Assert.isTrue(accountFields.get('Name').referenceTo.isEmpty());
    }

    @IsTest
    static void inaccessibleOrUnknownObjectsFailClosed() {
        System.runAs(restrictedUser()) {
            try {
                BoardSchemaService.getObjectFields('Opportunity', 0);
                Assert.fail('Expected ACCESS_ERROR for an object without Read access');
            } catch (AuraHandledException e) {
                assertBoardError(e, 'ACCESS_ERROR', 'Opportunity');
            }
            try {
                BoardSchemaService.getChildRelationships('Contact', 0);
                Assert.fail('Expected ACCESS_ERROR for an object without Read access');
            } catch (AuraHandledException e) {
                assertBoardError(e, 'ACCESS_ERROR', 'Contact');
            }
        }
        try {
            BoardSchemaService.getObjectFields('NotARealBoardObject__c', 0);
            Assert.fail('Expected CONFIG_ERROR for an unknown object');
        } catch (AuraHandledException e) {
            assertBoardError(e, 'CONFIG_ERROR', 'NotARealBoardObject__c');
        }
        try {
            BoardSchemaService.getObjectFields(' ', 0);
            Assert.fail('Expected CONFIG_ERROR for a blank object');
        } catch (AuraHandledException e) {
            assertBoardError(e, 'CONFIG_ERROR', null);
        }
    }

    @IsTest
    static void childRelationshipsIncludeCaseCommentsAndFeedItems() {
        List<BoardSchemaService.ChildRelationshipInfo> relationships = BoardSchemaService.getChildRelationships(
            'Case',
            0
        );

        BoardSchemaService.ChildRelationshipInfo comments = findChild(relationships, 'CaseComment', 'ParentId');
        Assert.isNotNull(comments, 'CaseComment child relationship is listed');
        Assert.areEqual('CaseComments', comments.relationshipName);
        BoardSchemaService.ChildRelationshipInfo feedItems = findChild(relationships, 'FeedItem', 'ParentId');
        Assert.isNotNull(feedItems, 'FeedItem child relationship is listed for sub-rows and semi-joins');
    }

    @IsTest
    static void childRelationshipsRespectChildObjectAndForeignKeyAccess() {
        List<BoardSchemaService.ChildRelationshipInfo> relationships;
        System.runAs(restrictedUser()) {
            relationships = BoardSchemaService.getChildRelationships('Account', 0);
        }

        BoardSchemaService.ChildRelationshipInfo cases = findChild(relationships, 'Case', 'AccountId');
        Assert.isNotNull(cases, 'Case is readable and Case.AccountId FLS is granted');
        Assert.areEqual('Cases', cases.relationshipName);
        Assert.isNull(findChild(relationships, 'Opportunity', 'AccountId'), 'Opportunity is not readable');
        Assert.isNull(findChild(relationships, 'Contact', 'AccountId'), 'Contact is not readable');
    }

    @IsTest
    static void picklistOptionsReturnActiveEntries() {
        List<String> expectedValues = new List<String>();
        for (Schema.PicklistEntry entry : Case.Status.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                expectedValues.add(entry.getValue());
            }
        }

        List<BoardSchemaService.PicklistOption> options;
        System.runAs(restrictedUser()) {
            options = BoardSchemaService.getPicklistOptions('Case', 'Status', 0);
        }

        List<String> actualValues = new List<String>();
        for (BoardSchemaService.PicklistOption option : options) {
            Assert.isNotNull(option.label);
            actualValues.add(option.value);
        }
        Assert.isFalse(actualValues.isEmpty());
        Assert.areEqual(expectedValues, actualValues, 'Only active Case.Status entries, in describe order');
    }

    @IsTest
    static void picklistOptionsFailClosedForInaccessibleOrInvalidFields() {
        System.runAs(restrictedUser()) {
            try {
                BoardSchemaService.getPicklistOptions('Case', 'Priority', 0);
                Assert.fail('Expected ACCESS_ERROR for a field without FLS Read');
            } catch (AuraHandledException e) {
                assertBoardError(e, 'ACCESS_ERROR', 'Case.Priority');
            }
            try {
                BoardSchemaService.getPicklistOptions('Opportunity', 'StageName', 0);
                Assert.fail('Expected ACCESS_ERROR for an object without Read access');
            } catch (AuraHandledException e) {
                assertBoardError(e, 'ACCESS_ERROR', 'Opportunity');
            }
        }
        try {
            BoardSchemaService.getPicklistOptions('Account', 'NotARealField__c', 0);
            Assert.fail('Expected CONFIG_ERROR for an unknown field');
        } catch (AuraHandledException e) {
            assertBoardError(e, 'CONFIG_ERROR', 'Account.NotARealField__c');
        }
        try {
            BoardSchemaService.getPicklistOptions('Account', 'Name', 0);
            Assert.fail('Expected CONFIG_ERROR for a non-picklist field');
        } catch (AuraHandledException e) {
            assertBoardError(e, 'CONFIG_ERROR', 'Account.Name');
        }
    }

    @IsTest
    static void recordLabelsResolveAcrossObjects() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];
        Case supportCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        String accountId15 = String.valueOf(account.Id).left(15);

        Map<String, String> labels = BoardSchemaService.resolveRecordLabels(
            new List<String>{
                accountId15,
                contact.Id,
                opportunity.Id,
                supportCase.Id,
                UserInfo.getUserId(),
                'not-an-id',
                null
            },
            0
        );

        Assert.areEqual('Board Account', labels.get(accountId15), 'Keys echo the supplied 15-character ID');
        Assert.areEqual('Board Contact', labels.get(contact.Id));
        Assert.areEqual('Board Opportunity', labels.get(opportunity.Id));
        Assert.areEqual(supportCase.CaseNumber, labels.get(supportCase.Id), 'Case resolves to CaseNumber');
        Assert.areEqual(UserInfo.getName(), labels.get(UserInfo.getUserId()));
        Assert.areEqual(5, labels.size(), 'Malformed IDs are ignored');
        Assert.isTrue(BoardSchemaService.resolveRecordLabels(null, 0).isEmpty());
    }

    @IsTest
    static void recordLabelsOmitObjectsTheUserCannotRead() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id FROM Contact LIMIT 1];
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];
        Case supportCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];

        Map<String, String> labels;
        System.runAs(restrictedUser()) {
            labels = BoardSchemaService.resolveRecordLabels(
                new List<String>{ account.Id, contact.Id, opportunity.Id, supportCase.Id },
                0
            );
        }

        Assert.areEqual('Board Account', labels.get(account.Id));
        Assert.areEqual(supportCase.CaseNumber, labels.get(supportCase.Id));
        Assert.isFalse(labels.containsKey(contact.Id), 'Contact is not readable');
        Assert.isFalse(labels.containsKey(opportunity.Id), 'Opportunity is not readable');
    }

    @IsTest
    static void searchReturnsActiveUsersOnlyByDefault() {
        List<BoardSchemaService.UserQueueOption> options;
        System.runAs(restrictedUser()) {
            options = BoardSchemaService.searchUsersAndQueues(SEARCH_TOKEN.toLowerCase(), false, 0);
        }

        Assert.areEqual(1, options.size(), 'Inactive users and queues are excluded: ' + JSON.serialize(options));
        Assert.areEqual(SEARCH_TOKEN + ' Restricted', options[0].label);
        Assert.areEqual('User', options[0].entityType);
        Assert.isTrue(options[0].id.startsWith('005'));
    }

    @IsTest
    static void searchIncludesQueuesWhenRequested() {
        List<BoardSchemaService.UserQueueOption> options;
        System.runAs(restrictedUser()) {
            options = BoardSchemaService.searchUsersAndQueues('  ' + SEARCH_TOKEN + '  ', true, 0);
        }

        Assert.areEqual(2, options.size(), 'Public groups are excluded: ' + JSON.serialize(options));
        Assert.areEqual(SEARCH_TOKEN + ' Queue', options[0].label, 'Options are sorted by label');
        Assert.areEqual('Queue', options[0].entityType);
        Assert.isTrue(options[0].id.startsWith('00G'));
        Assert.areEqual('User', options[1].entityType);
    }

    @IsTest
    static void searchTreatsLikeWildcardsAsLiterals() {
        List<BoardSchemaService.UserQueueOption> options = BoardSchemaService.searchUsersAndQueues('%_%', true, 0);

        Assert.isTrue(options.isEmpty(), 'Wildcards must not match every name: ' + JSON.serialize(options));
        Assert.isFalse(
            BoardSchemaService.searchUsersAndQueues(null, false, 0).isEmpty(),
            'A blank term lists active users'
        );
    }

    private static User restrictedUser() {
        return [SELECT Id FROM User WHERE Alias = :RESTRICTED_ALIAS AND LastName LIKE :SEARCH_TOKEN + '%' LIMIT 1];
    }

    private static User buildUser(String profileName, String alias, String lastName) {
        String uniqueSuffix = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        return new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1]
            .Id,
            Alias = alias,
            LastName = lastName,
            Email = alias + '@example.com',
            Username = alias + uniqueSuffix + '@board-schema.test',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static FieldPermissions readField(Id permissionSetId, String objectName, String fieldName) {
        return new FieldPermissions(
            ParentId = permissionSetId,
            SobjectType = objectName,
            Field = fieldName,
            PermissionsRead = true
        );
    }

    private static Map<String, BoardSchemaService.ObjectInfo> indexObjects(
        List<BoardSchemaService.ObjectInfo> objects
    ) {
        Map<String, BoardSchemaService.ObjectInfo> byName = new Map<String, BoardSchemaService.ObjectInfo>();
        for (BoardSchemaService.ObjectInfo info : objects) {
            byName.put(info.apiName, info);
        }
        return byName;
    }

    private static Map<String, BoardSchemaService.FieldInfo> indexFields(List<BoardSchemaService.FieldInfo> fields) {
        Map<String, BoardSchemaService.FieldInfo> byName = new Map<String, BoardSchemaService.FieldInfo>();
        for (BoardSchemaService.FieldInfo info : fields) {
            byName.put(info.apiName, info);
        }
        return byName;
    }

    private static BoardSchemaService.ChildRelationshipInfo findChild(
        List<BoardSchemaService.ChildRelationshipInfo> relationships,
        String childObjectApiName,
        String foreignKeyField
    ) {
        for (BoardSchemaService.ChildRelationshipInfo info : relationships) {
            if (info.childObjectApiName == childObjectApiName && info.foreignKeyField == foreignKeyField) {
                return info;
            }
        }
        return null;
    }

    private static void assertBoardError(AuraHandledException error, String category, String fieldPath) {
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
        Assert.areEqual(category, payload.get('category'), error.getMessage());
        Assert.areEqual(fieldPath, payload.get('fieldPath'), error.getMessage());
        Assert.areEqual(false, payload.get('retryable'));
        Assert.isNotNull(payload.get('message'));
    }
}