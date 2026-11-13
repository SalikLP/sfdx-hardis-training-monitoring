/**
 * Engine-unit tests of the Team role resolver over an in-memory role hierarchy (role Id -> parent role Id).
 *
 * Hierarchy used below:
 *   ceo
 *   ├── salesVp
 *   │   ├── managerEast ── repEast ── juniorEast
 *   │   └── managerWest ── repWest
 *   └── serviceVp ── agent
 */
@IsTest
private class BoardTeamResolverTest {
    private static final Id CEO = roleId(1);
    private static final Id SALES_VP = roleId(2);
    private static final Id MANAGER_EAST = roleId(3);
    private static final Id REP_EAST = roleId(4);
    private static final Id JUNIOR_EAST = roleId(5);
    private static final Id MANAGER_WEST = roleId(6);
    private static final Id REP_WEST = roleId(7);
    private static final Id SERVICE_VP = roleId(8);
    private static final Id AGENT = roleId(9);

    private static Map<Id, Id> hierarchy() {
        return new Map<Id, Id>{
            CEO => null,
            SALES_VP => CEO,
            MANAGER_EAST => SALES_VP,
            REP_EAST => MANAGER_EAST,
            JUNIOR_EAST => REP_EAST,
            MANAGER_WEST => SALES_VP,
            REP_WEST => MANAGER_WEST,
            SERVICE_VP => CEO,
            AGENT => SERVICE_VP
        };
    }

    @IsTest
    static void teamRolesAreTheWholeSubtreeStrictlyBelowTheRole() {
        Set<Id> below = BoardTeamResolver.rolesBelow(hierarchy(), new Set<Id>{ SALES_VP });

        Assert.areEqual(new Set<Id>{ MANAGER_EAST, REP_EAST, JUNIOR_EAST, MANAGER_WEST, REP_WEST }, below);
    }

    @IsTest
    static void thePickedRoleAndItsPeersAreNotBelowIt() {
        Set<Id> below = BoardTeamResolver.rolesBelow(hierarchy(), new Set<Id>{ MANAGER_EAST });

        Assert.areEqual(new Set<Id>{ REP_EAST, JUNIOR_EAST }, below);
        Assert.isFalse(below.contains(MANAGER_EAST), 'Peers holding the picked role stay out of the Team');
        Assert.isFalse(below.contains(MANAGER_WEST), 'Sibling roles stay out of the Team');
    }

    @IsTest
    static void aLeafRoleHasNoRolesBelow() {
        Assert.isTrue(BoardTeamResolver.rolesBelow(hierarchy(), new Set<Id>{ JUNIOR_EAST }).isEmpty());
    }

    @IsTest
    static void severalRolesUnionTheirTeams() {
        Set<Id> below = BoardTeamResolver.rolesBelow(hierarchy(), new Set<Id>{ MANAGER_WEST, SERVICE_VP, REP_EAST });

        Assert.areEqual(new Set<Id>{ REP_WEST, AGENT, JUNIOR_EAST }, below);
    }

    @IsTest
    static void nestedPicksDoNotDuplicateOrDropRoles() {
        Set<Id> below = BoardTeamResolver.rolesBelow(hierarchy(), new Set<Id>{ SALES_VP, MANAGER_EAST });

        Assert.areEqual(new Set<Id>{ MANAGER_EAST, REP_EAST, JUNIOR_EAST, MANAGER_WEST, REP_WEST }, below);
    }

    @IsTest
    static void deepHierarchiesResolveEveryLevel() {
        Map<Id, Id> chain = new Map<Id, Id>{ roleId(100) => null };
        Set<Id> expected = new Set<Id>();
        for (Integer level = 101; level <= 400; level++) {
            chain.put(roleId(level), roleId(level - 1));
            expected.add(roleId(level));
        }

        Assert.areEqual(expected, BoardTeamResolver.rolesBelow(chain, new Set<Id>{ roleId(100) }));
        Assert.areEqual(299, BoardTeamResolver.rolesBelow(chain, new Set<Id>{ roleId(101) }).size());
    }

    @IsTest
    static void noPickedRolesMeansNoTeamRoles() {
        Assert.isTrue(BoardTeamResolver.rolesBelow(hierarchy(), new Set<Id>()).isEmpty());
    }

    private static Id roleId(Integer sequence) {
        return Id.valueOf(
            UserRole.SObjectType.getDescribe().getKeyPrefix() + String.valueOf(sequence).leftPad(12, '0')
        );
    }
}