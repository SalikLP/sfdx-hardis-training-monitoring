@IsTest
private class BoardQueryServiceRowActionsTest {
    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Row Action Account');
        insert account;
        insert new List<Case>{
            new Case(Subject = 'Row Action With Account', AccountId = account.Id),
            new Case(Subject = 'Row Action Without Account')
        };
    }

    @IsTest
    static void polymorphicRowActionTargetHasNoSingleObject() {
        Map<String, Object> request = tableRequest();
        request.put(
            'rowActions',
            new List<Object>{ new Map<String, Object>{ 'id' => 'viewOwner', 'type' => 'view', 'target' => 'OwnerId' } }
        );
        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        Assert.areEqual('OwnerId', result.rowActions[0].targetPath);
        Assert.isNull(result.rowActions[0].targetObjectApiName, 'Case owner is a User or a Queue');
    }

    @IsTest
    static void rowActionTargetLookupIdsAreReturnedWithTheRowsWithoutBeingColumns() {
        Map<String, Object> request = tableRequest();
        request.put(
            'rowActions',
            new List<Object>{
                new Map<String, Object>{ 'id' => 'viewCase', 'type' => 'view' },
                new Map<String, Object>{ 'id' => 'viewAccount', 'type' => 'view', 'target' => 'AccountId' },
                new Map<String, Object>{ 'id' => 'editOwner', 'type' => 'edit', 'target' => 'Account.OwnerId' }
            }
        );
        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        Assert.areEqual(1, result.columns.size(), 'Targets are not columns');
        Assert.areEqual(3, result.rowActions.size());
        Assert.areEqual('Id', result.rowActions[0].targetPath);
        Assert.areEqual('Case', result.rowActions[0].targetObjectApiName);
        Assert.areEqual('AccountId', result.rowActions[1].targetPath);
        Assert.areEqual('Account', result.rowActions[1].targetObjectApiName);
        Assert.areEqual('Account.OwnerId', result.rowActions[2].targetPath);
        Assert.areEqual('User', result.rowActions[2].targetObjectApiName);

        Account account = [SELECT Id, OwnerId FROM Account WHERE Name = 'Row Action Account'];
        Map<String, BoardQueryService.TableRow> bySubject = new Map<String, BoardQueryService.TableRow>();
        for (BoardQueryService.TableRow row : result.rows) {
            bySubject.put(String.valueOf(row.values.get('Subject')), row);
        }
        BoardQueryService.TableRow withAccount = bySubject.get('Row Action With Account');
        Assert.areEqual(withAccount.id, withAccount.values.get('Id'));
        Assert.areEqual(account.Id, withAccount.values.get('AccountId'));
        Assert.areEqual(account.OwnerId, withAccount.values.get('Account.OwnerId'));
        Assert.isNull(
            bySubject.get('Row Action Without Account').values.get('AccountId'),
            'Empty lookup is returned as null so the action can hide'
        );
    }

    @IsTest
    static void rowActionTargetMustBeALookupField() {
        Map<String, Object> request = tableRequest();
        request.put(
            'rowActions',
            new List<Object>{ new Map<String, Object>{ 'id' => 'bad', 'type' => 'view', 'target' => 'Subject' } }
        );
        try {
            BoardQueryService.queryTable(JSON.serialize(request));
            Assert.fail('Expected CONFIG_ERROR');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), String.valueOf(payload));
        }
    }

    @IsTest
    static void createActionReturnsTheCreateObjectAndFetchesTheMappedRowFields() {
        Map<String, Object> request = tableRequest();
        request.put(
            'rowActions',
            new List<Object>{
                new Map<String, Object>{
                    'id' => 'newCase',
                    'type' => 'create',
                    'object' => 'Case',
                    'fields' => new List<Object>{ 'AccountId', 'Account.Name' }
                }
            }
        );
        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        Assert.areEqual(1, result.rowActions.size());
        Assert.areEqual('Id', result.rowActions[0].targetPath);
        Assert.areEqual('Case', result.rowActions[0].targetObjectApiName);
        Assert.areEqual(new List<String>{ 'AccountId', 'Account.Name' }, result.rowActions[0].fieldPaths);
        for (BoardQueryService.TableRow row : result.rows) {
            if (row.values.get('Subject') == 'Row Action With Account') {
                Assert.areEqual('Row Action Account', row.values.get('Account.Name'));
                Assert.isNotNull(row.values.get('AccountId'));
            }
        }
    }

    @IsTest
    static void flowActionTargetsTheRowAndFetchesTheMappedRowFields() {
        Map<String, Object> request = tableRequest();
        request.put(
            'rowActions',
            new List<Object>{
                new Map<String, Object>{
                    'id' => 'runFlow',
                    'type' => 'flow',
                    'fields' => new List<Object>{ 'Id', 'Account.Name' }
                }
            }
        );
        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(request));

        Assert.areEqual(1, result.rowActions.size());
        Assert.areEqual('Id', result.rowActions[0].targetPath);
        Assert.areEqual('Case', result.rowActions[0].targetObjectApiName);
        Assert.areEqual(new List<String>{ 'Id', 'Account.Name' }, result.rowActions[0].fieldPaths);
        for (BoardQueryService.TableRow row : result.rows) {
            if (row.values.get('Subject') == 'Row Action With Account') {
                Assert.areEqual('Row Action Account', row.values.get('Account.Name'));
            }
        }
    }

    @IsTest
    static void createActionNeedsAnExistingObject() {
        Map<String, Object> request = tableRequest();
        request.put(
            'rowActions',
            new List<Object>{ new Map<String, Object>{ 'id' => 'bad', 'type' => 'create', 'object' => 'Nope__x' } }
        );
        try {
            BoardQueryService.queryTable(JSON.serialize(request));
            Assert.fail('Expected CONFIG_ERROR');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual('CONFIG_ERROR', payload.get('category'), String.valueOf(payload));
        }
    }

    private static Map<String, Object> tableRequest() {
        return new Map<String, Object>{
            'objectApiName' => 'Case',
            'columns' => new List<Object>{ new Map<String, Object>{ 'id' => 'subject', 'fieldPath' => 'Subject' } },
            'filters' => new List<Object>(),
            'baseFilters' => new List<Object>(),
            'refreshToken' => 0
        };
    }
}