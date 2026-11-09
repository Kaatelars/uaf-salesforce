/**
 * @description In-memory (transaction-scoped) bypass registry for Apex trigger dispatching
 *              (by SObject API name) and for Flows (by Flow API name). Typical uses are unit
 *              tests and code that must suppress automation for a single operation.
 *              Names are compared case-insensitively. Blank names are never bypassed.
 *              Sharing: {@code inherited sharing} so framework code always runs in the sharing
 *              context of its caller (trigger, handler or Flow) and never widens it.
 * @group UAF Core
 */
public inherited sharing class UAF_BypassManager {

    private static final Set<String> BYPASSED_OBJECTS = new Set<String>();
    private static final Set<String> BYPASSED_FLOWS = new Set<String>();

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
     * @description Checks whether trigger dispatching is bypassed for an SObject.
     * @param sObjectName SObject API name.
     * @return True if bypassed; false otherwise (always false for blank names).
     */
    public static Boolean isObjectBypassed(String sObjectName) {
        return contains(BYPASSED_OBJECTS, sObjectName);
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
     * @description Checks whether a Flow is bypassed.
     * @param flowApiName Flow API name.
     * @return True if bypassed; false otherwise (always false for blank names).
     */
    public static Boolean isFlowBypassed(String flowApiName) {
        return contains(BYPASSED_FLOWS, flowApiName);
    }

    /**
     * @description Removes every in-memory object and Flow bypass.
     */
    public static void clearAllBypasses() {
        BYPASSED_OBJECTS.clear();
        BYPASSED_FLOWS.clear();
    }

    private static Boolean contains(Set<String> registry, String name) {
        String key = normalize(name);
        return key != null && registry.contains(key);
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
