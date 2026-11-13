/**
 * Entry-point tests of User filters in Team match mode (`usersAndTeam`) bound to `OwnerId` by convention.
 *
 * Roles: Board Team VP
 *        ├── Board Team Manager (Anna, Peer) ── Board Team Rep (Rex) ── Board Team Junior (Jun)
 *        └── Board Team Other (Olga, also the viewer outside Anna's branch)
 * One Opportunity per user. Anna's Team is Anna + Rex + Jun; Peer shares Anna's role and stays out.
 * Edge cases reuse these users (no extra licences): a test clears a role or deactivates a user in its own transaction.
 */
@IsTest
private class BoardQueryServiceTeamTest {
    private static final String ALIAS_PREFIX = 'brdtm';

    @TestSetup
    static void setup() {
        Map<String, User> users = new Map<String, User>();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            UserRole vp = role('Vp', null);
            insert vp;
            UserRole manager = role('Manager', vp.Id);
            UserRole other = role('Other', vp.Id);
            insert new List<UserRole>{ manager, other };
            UserRole rep = role('Rep', manager.Id);
            insert rep;
            UserRole junior = role('Junior', rep.Id);
            insert junior;

            Id profileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;
            users.put('anna', teamUser('anna', 'Hansen', profileId, manager.Id));
            users.put('peer', teamUser('peer', 'Peer', profileId, manager.Id));
            users.put('rex', teamUser('rex', 'Rep', profileId, rep.Id));
            users.put('jun', teamUser('jun', 'Junior', profileId, junior.Id));
            users.put('olga', teamUser('olga', 'Other', profileId, other.Id));
            insert users.values();
        }
        List<Opportunity> opportunities = new List<Opportunity>();
        for (String key : new List<String>{ 'anna', 'peer', 'rex', 'jun', 'olga' }) {
            opportunities.add(
                new Opportunity(
                    Name = 'Board Team ' + key,
                    StageName = 'Prospecting',
                    CloseDate = Date.today(),
                    OwnerId = users.get(key).Id
                )
            );
        }
        insert opportunities;
    }

    @IsTest
    static void teamOnOwnerIdMatchesTheUserAndEveryoneInRolesBelowButNotPeers() {
        BoardQueryService.MetricResult result = run(ownerFilter('usersAndTeam', new List<Id>{ userId('anna') }));

        Assert.areEqual(3, result.value, 'Anna + Rex + Jun; Peer (same role) and Olga left out');
        Assert.areEqual(new List<String>{ 'owner' }, result.appliedFilterIds);
        Assert.areEqual(
            new Set<String>{ 'Board Team anna', 'Board Team rex', 'Board Team jun' },
            namesOf(ownerFilter('usersAndTeam', new List<Id>{ userId('anna') }))
        );
    }

    @IsTest
    static void selectedUsersModeMatchesOnlyThePickedUsers() {
        Assert.areEqual(1, run(ownerFilter('users', new List<Id>{ userId('anna') })).value);
        Assert.areEqual(1, run(ownerFilter(null, new List<Id>{ userId('anna') })).value, 'users is the default');
    }

    @IsTest
    static void aPickedUserWithoutRolesBelowMatchesOnlyTheirOwnRecords() {
        Assert.areEqual(1, run(ownerFilter('usersAndTeam', new List<Id>{ userId('jun') })).value);
    }

    @IsTest
    static void severalPickedUsersMatchTheUnionOfTheirTeams() {
        Map<String, Object> owners = ownerFilter('usersAndTeam', new List<Id>{ userId('anna'), userId('olga') });
        Assert.areEqual(4, run(owners).value, 'Anna, Rex, Jun + Olga');

        Map<String, Object> nested = ownerFilter('usersAndTeam', new List<Id>{ userId('anna'), userId('rex') });
        Assert.areEqual(3, run(nested).value, 'Rex is already in Anna\'s Team');
    }

    @IsTest
    static void meMatchesTheViewersTeam() {
        Map<String, Object> mine = ownerFilter('usersAndTeam', new List<Id>());
        mine.put('token', 'ME');
        Set<String> names;
        System.runAs(new User(Id = userId('anna'))) {
            names = namesOf(mine);
        }
        Assert.areEqual(new Set<String>{ 'Board Team anna', 'Board Team rex', 'Board Team jun' }, names);
    }

    @IsTest
    static void noSelectionAppliesNoCondition() {
        BoardQueryService.MetricResult result = run(ownerFilter('usersAndTeam', new List<Id>()));

        Assert.areEqual(5, result.value);
        Assert.isTrue(result.appliedFilterIds.isEmpty());
    }

    @IsTest
    static void aViewerCountsOnlyTeamRecordsSharedWithThem() {
        Map<String, Object> annasTeam = ownerFilter('usersAndTeam', new List<Id>{ userId('anna') });
        Integer counted;
        Integer visible;
        System.runAs(new User(Id = userId('olga'))) {
            counted = (Integer) run(annasTeam).value;
            Set<Id> teamOwners = new Set<Id>{ userId('anna'), userId('rex'), userId('jun') };
            visible = [SELECT COUNT() FROM Opportunity WHERE OwnerId IN :teamOwners WITH USER_MODE];
        }

        Assert.areEqual(visible, counted, 'Team totals respect the viewer\'s sharing');
        Assert.isTrue(counted <= 3);
    }

    @IsTest
    static void aPickedUserWithoutARoleMatchesOnlyTheirOwnRecordsAndIsNoticed() {
        removeRole('peer');
        String peerId = String.valueOf(userId('peer'));

        Assert.areEqual(1, run(ownerFilter('usersAndTeam', new List<Id>{ userId('peer') })).value);
        Assert.areEqual(
            new List<String>{ peerId },
            BoardSchemaService.findUsersWithoutRole(new List<String>{ peerId }, 0),
            'The notice names only the person; nothing about roles is returned'
        );
    }

    @IsTest
    static void aMixedSelectionUnionsTheTeamsAndNoticesEachUserWithoutARole() {
        removeRole('peer');
        removeRole('olga');
        String annaId = String.valueOf(userId('anna'));
        String peerId = String.valueOf(userId('peer'));
        String olgaId = String.valueOf(userId('olga'));

        Map<String, Object> mixed = ownerFilter(
            'usersAndTeam',
            new List<Id>{ userId('anna'), userId('peer'), userId('olga') }
        );
        Assert.areEqual(5, run(mixed).value, 'Anna, Rex, Jun + Peer\'s and Olga\'s own records');
        Assert.areEqual(
            new List<String>{ peerId, olgaId },
            BoardSchemaService.findUsersWithoutRole(new List<String>{ annaId, peerId, olgaId }, 0)
        );
    }

    @IsTest
    static void usersWithARoleAndNonUserIdsAreNotNoticed() {
        Assert.isTrue(
            BoardSchemaService.findUsersWithoutRole(
                    new List<String>{ String.valueOf(userId('anna')), 'not-an-id', null },
                    0
                )
                .isEmpty()
        );
        Assert.isTrue(BoardSchemaService.findUsersWithoutRole(null, 0).isEmpty());
    }

    @IsTest
    static void tooManyPickedUsersAreAConfigError() {
        String annaId = String.valueOf(userId('anna'));
        List<String> picked = new List<String>();
        for (Integer i = 0; i <= BoardSchemaService.MAX_TEAM_NOTICE_USERS; i++) {
            picked.add(annaId);
        }
        try {
            BoardSchemaService.findUsersWithoutRole(picked, 0);
            Assert.fail('Expected a config error');
        } catch (AuraHandledException failure) {
            Assert.isTrue(failure.getMessage().contains(BoardErrors.CONFIG_ERROR), failure.getMessage());
        }
    }

    @IsTest
    static void recordsOfAnInactiveOwnerWithARoleInsideTheTeamAreIncluded() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = userId('rex'), IsActive = false);
        }

        Assert.areEqual(
            new Set<String>{ 'Board Team anna', 'Board Team rex', 'Board Team jun' },
            namesOf(ownerFilter('usersAndTeam', new List<Id>{ userId('anna') }))
        );
    }

    @IsTest
    static void queueOwnedRecordsAreLeftOut() {
        Group queue = new Group(Name = 'Board Team Queue', DeveloperName = 'BoardTeamTestQueue', Type = 'Queue');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert queue;
            insert new QueueSobject(QueueId = queue.Id, SobjectType = 'Case');
        }
        insert new List<Case>{
            new Case(Subject = 'Board Team anna', OwnerId = userId('anna')),
            new Case(Subject = 'Board Team rex', OwnerId = userId('rex')),
            new Case(Subject = 'Board Team queue', OwnerId = queue.Id)
        };

        Map<String, Object> annasTeam = ownerFilter('usersAndTeam', new List<Id>{ userId('anna') });
        Assert.areEqual(2, run('Case', annasTeam).value, 'Anna + Rex; the queue-owned Case stays out');
        Assert.areEqual(3, run('Case', ownerFilter('usersAndTeam', new List<Id>())).value);
    }

    @IsTest
    static void teamOnAParentPathMatchesRecordsWhoseParentOwnerIsInTheTeam() {
        Map<String, Account> accounts = accountsOwnedBy(new List<String>{ 'anna', 'rex', 'peer', 'olga' });
        List<Opportunity> opportunities = new List<Opportunity>();
        for (String key : accounts.keySet()) {
            opportunities.add(
                new Opportunity(
                    Name = 'Board Team account ' + key,
                    StageName = 'Prospecting',
                    CloseDate = Date.today(),
                    AccountId = accounts.get(key).Id,
                    OwnerId = userId('olga')
                )
            );
        }
        insert opportunities;

        Map<String, Object> annasTeam = pathFilter('Account.OwnerId', new List<Id>{ userId('anna') });
        Assert.areEqual(2, run(annasTeam).value, 'Opportunities on Anna\'s and Rex\'s Accounts; owners don\'t matter');
    }

    @IsTest
    static void teamOnAUserLookupOtherThanOwnerMatchesTheTeam() {
        Account account = accountsOwnedBy(new List<String>{ 'olga' }).get('olga');
        List<Contract> contracts = new List<Contract>();
        for (String key : new List<String>{ 'anna', 'jun', 'peer', null }) {
            contracts.add(
                new Contract(
                    AccountId = account.Id,
                    Status = 'Draft',
                    CompanySignedId = key == null ? null : userId(key)
                )
            );
        }
        insert contracts;

        Map<String, Object> annasTeam = pathFilter('CompanySignedId', new List<Id>{ userId('anna') });
        Assert.areEqual(2, run('Contract', annasTeam).value, 'Signed by Anna or Jun; Peer and unsigned left out');
    }

    @IsTest
    static void teamOnAChildSemiJoinPathMatchesParentsWithAChildInTheTeam() {
        Map<String, Account> accounts = accountsOwnedBy(new List<String>{ 'rex', 'peer', 'olga' });
        List<Opportunity> opportunities = new List<Opportunity>();
        for (String key : new List<String>{ 'rex', 'peer' }) {
            opportunities.add(
                new Opportunity(
                    Name = 'Board Team child ' + key,
                    StageName = 'Prospecting',
                    CloseDate = Date.today(),
                    AccountId = accounts.get('olga').Id,
                    OwnerId = userId(key)
                )
            );
        }
        opportunities[1].AccountId = accounts.get('peer').Id;
        insert opportunities;

        Map<String, Object> annasTeam = pathFilter('Opportunity(AccountId).OwnerId', new List<Id>{ userId('anna') });
        Assert.areEqual(1, run('Account', annasTeam).value, 'Only Olga\'s Account has an Opportunity owned by Rex');
    }

    @IsTest
    static void teamOnAPathThatReachesUserRoleIdBeyondFiveHopsIsAConfigError() {
        String fiveHops = 'Account.Parent.Parent.Parent.Parent.OwnerId';
        Map<String, Object> plainUsers = pathFilter(fiveHops, new List<Id>{ userId('anna') });
        plainUsers.put('matchMode', 'users');
        Assert.areEqual(0, run(plainUsers).value, 'Five hops are fine without Include team');

        try {
            run(pathFilter(fiveHops, new List<Id>{ userId('anna') }));
            Assert.fail('Expected a config error');
        } catch (AuraHandledException error) {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(error.getMessage());
            Assert.areEqual(BoardErrors.CONFIG_ERROR, payload.get('category'), String.valueOf(payload));
            Assert.areEqual('owner', payload.get('filterId'));
            Assert.areEqual(fiveHops, payload.get('fieldPath'));
            String message = (String) payload.get('message');
            Assert.isTrue(message.contains('"owner"'), 'The message names the binding: ' + message);
            Assert.isTrue(message.contains('UserRoleId'), message);
        }
    }

    // ---------------------------------------------------------------------------------------------------------

    /** One Account per key, owned by that user. */
    private static Map<String, Account> accountsOwnedBy(List<String> keys) {
        Map<String, Account> accounts = new Map<String, Account>();
        for (String key : keys) {
            accounts.put(key, new Account(Name = 'Board Team ' + key, OwnerId = userId(key)));
        }
        insert accounts.values();
        return accounts;
    }

    /** An explicit Team binding of the `owner` User filter to `path`. */
    private static Map<String, Object> pathFilter(String path, List<Id> userIds) {
        Map<String, Object> filter = ownerFilter('usersAndTeam', userIds);
        filter.put('fieldPath', path);
        filter.put('explicit', true);
        return filter;
    }

    private static void removeRole(String key) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = userId(key), UserRoleId = null);
        }
    }

    private static UserRole role(String suffix, Id parentRoleId) {
        return new UserRole(
            Name = 'Board Team ' + suffix,
            DeveloperName = 'BoardTeamTest' + suffix,
            ParentRoleId = parentRoleId
        );
    }

    private static User teamUser(String key, String lastName, Id profileId, Id roleId) {
        String alias = ALIAS_PREFIX + key.left(3);
        return new User(
            ProfileId = profileId,
            UserRoleId = roleId,
            Alias = alias,
            FirstName = key.capitalize(),
            LastName = lastName,
            Email = alias + '@example.com',
            Username = alias + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@board-team.test',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static Id userId(String key) {
        String alias = ALIAS_PREFIX + key.left(3);
        return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1].Id;
    }

    private static Map<String, Object> ownerFilter(String matchMode, List<Id> userIds) {
        return new Map<String, Object>{
            'filterId' => 'owner',
            'type' => 'USER',
            'fieldPath' => 'OwnerId',
            'explicit' => false,
            'operator' => 'IN',
            'values' => userIds,
            'targetObjectApiName' => 'User',
            'fieldApiName' => 'OwnerId',
            'matchMode' => matchMode
        };
    }

    private static BoardQueryService.MetricResult run(Map<String, Object> ownerFilter) {
        return run('Opportunity', ownerFilter);
    }

    private static BoardQueryService.MetricResult run(String objectApiName, Map<String, Object> ownerFilter) {
        Map<String, Object> metric = new Map<String, Object>{
            'objectApiName' => objectApiName,
            'aggregateFunction' => 'COUNT',
            'valueFieldApiName' => null,
            'filters' => new List<Object>{ ownerFilter },
            'baseFilters' => new List<Object>(),
            'refreshToken' => 0
        };
        return BoardQueryService.queryMetric(JSON.serialize(metric));
    }

    /** Names of the Opportunities a Table widget lists under `ownerFilter`. */
    private static Set<String> namesOf(Map<String, Object> ownerFilter) {
        Map<String, Object> table = new Map<String, Object>{
            'objectApiName' => 'Opportunity',
            'columns' => new List<Object>{ new Map<String, Object>{ 'id' => 'name', 'fieldPath' => 'Name' } },
            'filters' => new List<Object>{ ownerFilter },
            'baseFilters' => new List<Object>(),
            'refreshToken' => 0
        };
        BoardQueryService.TableResult result = BoardQueryService.queryTable(JSON.serialize(table));
        Set<String> names = new Set<String>();
        for (BoardQueryService.TableRow row : result.rows) {
            names.add((String) row.values.get('Name'));
        }
        return names;
    }
}