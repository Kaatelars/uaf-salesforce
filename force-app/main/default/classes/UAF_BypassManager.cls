/**
 * @description Bypass registry for Apex trigger dispatching (by SObject API name) and Flows
 *              (by Flow API name). Bypasses are evaluated hierarchically:
 *              <ol>
 *                <li><b>Explicit in-memory bypass</b> (transaction-scoped), set with
 *                    {@link bypassObject} / {@link bypassFlow}. Typical in unit tests and in
 *                    code that must suppress automation for a single operation.</li>
 *                <li><b>User-level bypass</b> via the Custom Permission {@code UAF_Bypass_All}
 *                    (granted by the Permission Set {@code UAF_Bypass_Automations}). When the
 *                    running user has it, EVERY object and Flow is bypassed. It is meant for
 *                    integration and data-load users (Data Loader, SFDMU, ETL).</li>
 *              </ol>
 *              Names are compared case-insensitively. Blank names are never bypassed.
 *              {@link clearAllBypasses} clears only in-memory bypasses: a user-level bypass is
 *              removed by unassigning the Permission Set.
 *
 *              The permission check uses {@code FeatureManagement.checkPermission} (no SOQL) and
 *              is cached per user for the transaction, so bulk callers such as UAF_FlowGuard
 *              pay for it at most once per user.
 *              Sharing: {@code inherited sharing} so framework code always runs in the sharing
 *              context of its caller (trigger, handler or Flow) and never widens it.
 * @group UAF Core
 */
public inherited sharing class UAF_BypassManager {

    /** @description API name of the Custom Permission that bypasses every UAF automation. */
    public static final String BYPASS_ALL_PERMISSION = 'UAF_Bypass_All';

    private static final Set<String> BYPASSED_OBJECTS = new Set<String>();
    private static final Set<String> BYPASSED_FLOWS = new Set<String>();

    /** User Id -> result of the Custom Permission check (System.runAs switches users within a transaction). */
    private static final Map<Id, Boolean> BYPASS_ALL_BY_USER = new Map<Id, Boolean>();

    /**
     * Test hook: forces the user-level bypass on (true) or off (false) without assigning the
     * Permission Set. Null means "use the real Custom Permission check".
     */
    @TestVisible
    private static Boolean bypassAllOverride;

    /**
     * @description Bypasses trigger dispatching for an SObject for the rest of the transaction.
     * @param sObjectName SObject API name (e.g. {@code Account}, {@code Invoice__c}).
     */
    public static void bypassObject(String sObjectName) {
        add(BYPASSED_OBJECTS, sObjectName);
    }

    /**
     * @description Removes the in-memory bypass for an SObject.
     * @param sObjectName SObject API name.
     */
    public static void clearBypassObject(String sObjectName) {
        remove(BYPASSED_OBJECTS, sObjectName);
    }

    /**
     * @description Checks whether trigger dispatching is bypassed for an SObject, either by an
     *              explicit in-memory bypass or by the running user's {@code UAF_Bypass_All} permission.
     * @param sObjectName SObject API name.
     * @return True if bypassed; false otherwise (always false for blank names).
     */
    public static Boolean isObjectBypassed(String sObjectName) {
        return isBypassed(BYPASSED_OBJECTS, sObjectName);
    }

    /**
     * @description Bypasses a Flow (by API name) for the rest of the transaction.
     * @param flowApiName Flow API name.
     */
    public static void bypassFlow(String flowApiName) {
        add(BYPASSED_FLOWS, flowApiName);
    }

    /**
     * @description Removes the in-memory bypass for a Flow.
     * @param flowApiName Flow API name.
     */
    public static void clearBypassFlow(String flowApiName) {
        remove(BYPASSED_FLOWS, flowApiName);
    }

    /**
     * @description Checks whether a Flow is bypassed, either by an explicit in-memory bypass or by
     *              the running user's {@code UAF_Bypass_All} permission.
     * @param flowApiName Flow API name.
     * @return True if bypassed; false otherwise (always false for blank names).
     */
    public static Boolean isFlowBypassed(String flowApiName) {
        return isBypassed(BYPASSED_FLOWS, flowApiName);
    }

    /**
     * @description Whether the running user bypasses every UAF automation through the
     *              {@code UAF_Bypass_All} Custom Permission.
     * @return True if the user-level bypass is active.
     */
    public static Boolean isBypassAllActive() {
        if (bypassAllOverride != null) {
            return bypassAllOverride;
        }
        Id userId = UserInfo.getUserId();
        Boolean hasPermission = BYPASS_ALL_BY_USER.get(userId);
        if (hasPermission == null) {
            hasPermission = FeatureManagement.checkPermission(BYPASS_ALL_PERMISSION);
            BYPASS_ALL_BY_USER.put(userId, hasPermission);
        }
        return hasPermission;
    }

    /**
     * @description Removes every in-memory object and Flow bypass. Does not affect the
     *              user-level {@code UAF_Bypass_All} permission.
     */
    public static void clearAllBypasses() {
        BYPASSED_OBJECTS.clear();
        BYPASSED_FLOWS.clear();
    }

    private static Boolean isBypassed(Set<String> registry, String name) {
        String key = normalize(name);
        if (key == null) {
            return false;
        }
        // 1) Explicit in-memory bypass; 2) user-level Custom Permission.
        return registry.contains(key) || isBypassAllActive();
    }

    private static String normalize(String name) {
        return String.isBlank(name) ? null : name.trim().toLowerCase();
    }

    private static void add(Set<String> registry, String name) {
        String key = normalize(name);
        if (key != null) {
            registry.add(key);
        }
    }

    private static void remove(Set<String> registry, String name) {
        String key = normalize(name);
        if (key != null) {
            registry.remove(key);
        }
    }
}
