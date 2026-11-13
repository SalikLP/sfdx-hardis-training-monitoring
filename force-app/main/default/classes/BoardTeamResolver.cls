/**
 * Role resolver for User filters in Team match mode (`usersAndTeam`). A user's Team is the user plus everyone whose
 * role is strictly below that user's role; peers holding the same role are not part of it.
 *
 * The role hierarchy and the picked users' roles are read once per transaction in system mode (`SystemReads`, the only
 * code without sharing, so a viewer's User sharing never shrinks the hierarchy) and memoized in static state; no
 * Platform Cache. Record queries that use the resolved roles stay `USER_MODE`, so totals still count only records the
 * viewer can see. Role Ids and names never leave Apex: callers bind them into `SOQL` and return only people labels to
 * the client.
 */
public with sharing class BoardTeamResolver {
    /** Role Id -> parent role Id (null at the top) of every UserRole; loaded on first use per transaction. */
    private static Map<Id, Id> parentByRoleMemo;
    /** User Id -> role Id (null when the user has no role) of users already resolved in this transaction. */
    private static final Map<Id, Id> ROLE_BY_USER_MEMO = new Map<Id, Id>();
    /** Users of `ROLE_BY_USER_MEMO` that exist (a memoized null role then means "no role", not "not a user"). */
    private static final Set<Id> FOUND_USER_IDS = new Set<Id>();

    /**
     * Roles strictly below the roles of `userIds` (the union over all users), from the org's role hierarchy.
     * Users without a role, and Ids that are not users (e.g. queues), add no roles.
     */
    public static Set<Id> rolesBelowUsers(Set<Id> userIds) {
        Set<Id> pickedRoleIds = new Set<Id>();
        Map<Id, Id> roleByUser = rolesByUser(userIds);
        for (Id userId : userIds) {
            Id roleId = roleByUser.get(userId);
            if (roleId != null) {
                pickedRoleIds.add(roleId);
            }
        }
        if (pickedRoleIds.isEmpty()) {
            return new Set<Id>();
        }
        return rolesBelow(parentByRole(), pickedRoleIds);
    }

    /**
     * Pure: the roles strictly below each of `topRoleIds` in `parentByRole` (role Id -> parent role Id), unioned.
     * The top roles themselves are not included unless one sits below another.
     */
    public static Set<Id> rolesBelow(Map<Id, Id> parentByRole, Set<Id> topRoleIds) {
        Map<Id, List<Id>> childrenByRole = new Map<Id, List<Id>>();
        for (Id roleId : parentByRole.keySet()) {
            Id parentId = parentByRole.get(roleId);
            if (parentId == null) {
                continue;
            }
            List<Id> children = childrenByRole.get(parentId);
            if (children == null) {
                children = new List<Id>();
                childrenByRole.put(parentId, children);
            }
            children.add(roleId);
        }
        Set<Id> below = new Set<Id>();
        // Iterative walk: deep hierarchies never hit the Apex stack depth limit.
        List<Id> pending = new List<Id>(topRoleIds);
        while (!pending.isEmpty()) {
            Id roleId = pending.remove(pending.size() - 1);
            List<Id> children = childrenByRole.get(roleId);
            if (children == null) {
                continue;
            }
            for (Id childId : children) {
                if (below.add(childId)) {
                    pending.add(childId);
                }
            }
        }
        return below;
    }

    /**
     * The users among `userIds` who have no role, so their Team is only themselves (the Filter widget names them in
     * a notice). Inactive users count like active ones; queues, other non-user Ids, and unknown users are left out.
     */
    public static Set<Id> usersWithoutRole(Set<Id> userIds) {
        Map<Id, Id> roleByUser = rolesByUser(userIds);
        Set<Id> withoutRole = new Set<Id>();
        for (Id userId : userIds) {
            if (FOUND_USER_IDS.contains(userId) && roleByUser.get(userId) == null) {
                withoutRole.add(userId);
            }
        }
        return withoutRole;
    }

    private static Map<Id, Id> rolesByUser(Set<Id> userIds) {
        Set<Id> missing = new Set<Id>();
        for (Id userId : userIds) {
            if (
                userId != null &&
                !ROLE_BY_USER_MEMO.containsKey(userId) &&
                userId.getSObjectType() == User.SObjectType
            ) {
                missing.add(userId);
            }
        }
        if (!missing.isEmpty()) {
            for (Id userId : missing) {
                ROLE_BY_USER_MEMO.put(userId, null);
            }
            for (User picked : new SystemReads().usersWithRoles(missing)) {
                FOUND_USER_IDS.add(picked.Id);
                ROLE_BY_USER_MEMO.put(picked.Id, picked.UserRoleId);
            }
        }
        return ROLE_BY_USER_MEMO;
    }

    private static Map<Id, Id> parentByRole() {
        if (parentByRoleMemo == null) {
            parentByRoleMemo = new Map<Id, Id>();
            for (UserRole role : new SystemReads().roles()) {
                parentByRoleMemo.put(role.Id, role.ParentRoleId);
            }
        }
        return parentByRoleMemo;
    }

    /** The two system-mode reads, without sharing: User sharing must not hide roles or picked users. */
    private without sharing class SystemReads {
        public List<User> usersWithRoles(Set<Id> userIds) {
            return [SELECT Id, UserRoleId FROM User WHERE Id IN :userIds WITH SYSTEM_MODE];
        }

        public List<UserRole> roles() {
            return [SELECT Id, ParentRoleId FROM UserRole WITH SYSTEM_MODE];
        }
    }
}