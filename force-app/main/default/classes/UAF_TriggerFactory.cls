/**
 * @description Single entry point for every trigger. Usage (one trigger per SObject):
 *              <pre>
 *              trigger AccountTrigger on Account (before insert, after insert, before update,
 *                  after update, before delete, after delete, after undelete) {
 *                  UAF_TriggerFactory.createAndDispatch(Account.SObjectType);
 *              }
 *              </pre>
 *              The dispatcher is resolved by convention:
 *              {@code <SObjectName without namespace/suffix> + 'TriggerDispatcher'}, e.g.
 *              {@code Account -> AccountTriggerDispatcher},
 *              {@code Invoice__c -> InvoiceTriggerDispatcher},
 *              {@code ns__Invoice__c -> InvoiceTriggerDispatcher},
 *              {@code Order_Event__e -> Order_EventTriggerDispatcher}.
 *              Sharing: {@code inherited sharing} so framework code always runs in the sharing
 *              context of its caller (trigger, handler or Flow) and never widens it.
 * @group UAF Core
 */
public inherited sharing class UAF_TriggerFactory {

    private static final String DISPATCHER_SUFFIX = 'TriggerDispatcher';
    private static final List<String> SOBJECT_SUFFIXES = new List<String>{ '__c', '__e' };

    /** Test hook: lower-cased SObject name -> dispatcher Type, takes precedence over the naming convention. */
    @TestVisible
    private static final Map<String, Type> DISPATCHER_OVERRIDES = new Map<String, Type>();

    /**
     * @description Resolves the dispatcher for the SObject and dispatches the current trigger
     *              context to it. Does nothing if the SObject is bypassed in {@link UAF_BypassManager}.
     * @param sObjectType SObjectType of the trigger.
     * @throws UAF_TriggerException if called outside a trigger, or no valid dispatcher exists.
     */
    public static void createAndDispatch(Schema.SObjectType sObjectType) {
        if (!Trigger.isExecuting) {
            throw new UAF_TriggerException('UAF_TriggerFactory.createAndDispatch must be called from a trigger.');
        }
        dispatch(sObjectType, UAF_TriggerParameters.fromTriggerContext());
    }

    /**
     * @description Core dispatch logic, separated from the Trigger context for testability.
     * @param sObjectType SObjectType being processed.
     * @param tp          Trigger parameters.
     */
    @TestVisible
    private static void dispatch(Schema.SObjectType sObjectType, UAF_TriggerParameters tp) {
        if (sObjectType == null || tp == null || tp.triggerEvent == null) {
            throw new UAF_TriggerException('UAF_TriggerFactory: a valid SObjectType and trigger context are required.');
        }

        String sObjectName = String.valueOf(sObjectType);
        if (UAF_BypassManager.isObjectBypassed(sObjectName)) {
            return;
        }

        UAF_ITriggerDispatcher dispatcher = getDispatcher(sObjectName);
        if (tp.isBefore) {
            dispatcher.bulkBefore(tp);
        } else {
            dispatcher.bulkAfter(tp);
        }

        switch on tp.triggerEvent {
            when BEFORE_INSERT  { dispatcher.beforeInsert(tp); }
            when AFTER_INSERT   { dispatcher.afterInsert(tp); }
            when BEFORE_UPDATE  { dispatcher.beforeUpdate(tp); }
            when AFTER_UPDATE   { dispatcher.afterUpdate(tp); }
            when BEFORE_DELETE  { dispatcher.beforeDelete(tp); }
            when AFTER_DELETE   { dispatcher.afterDelete(tp); }
            when AFTER_UNDELETE { dispatcher.afterUndelete(tp); }
        }

        dispatcher.andFinally(tp);
    }

    /**
     * @description Instantiates the dispatcher registered for (or named after) the SObject.
     * @param sObjectName SObject API name.
     * @return Dispatcher instance.
     * @throws UAF_TriggerException if no class is found or it does not implement UAF_ITriggerDispatcher.
     */
    @TestVisible
    private static UAF_ITriggerDispatcher getDispatcher(String sObjectName) {
        Type dispatcherType = DISPATCHER_OVERRIDES.get(sObjectName.toLowerCase())
            ?? Type.forName(getDispatcherClassName(sObjectName));
        return instantiateDispatcher(dispatcherType, sObjectName);
    }

    /**
     * @description Validates and instantiates a resolved dispatcher type. Separated from the lookup
     *              so the "not found" path can be tested regardless of which dispatchers exist in the org.
     * @param dispatcherType Resolved type (null if no class was found).
     * @param sObjectName    SObject API name (for error messages).
     * @return Dispatcher instance.
     * @throws UAF_TriggerException if the type is null or does not implement UAF_ITriggerDispatcher.
     */
    @TestVisible
    private static UAF_ITriggerDispatcher instantiateDispatcher(Type dispatcherType, String sObjectName) {
        if (dispatcherType == null) {
            throw new UAF_TriggerException('UAF_TriggerFactory: no dispatcher class "' + getDispatcherClassName(sObjectName) + '" found for ' + sObjectName + '.');
        }

        Object instance = dispatcherType.newInstance();
        if (!(instance instanceof UAF_ITriggerDispatcher)) {
            throw new UAF_TriggerException('UAF_TriggerFactory: ' + dispatcherType.getName() + ' does not implement UAF_ITriggerDispatcher.');
        }
        return (UAF_ITriggerDispatcher) instance;
    }

    /**
     * @description Applies the naming convention: strips the namespace prefix and the
     *              {@code __c}/{@code __e} suffix, then appends {@code TriggerDispatcher}.
     * @param sObjectName SObject API name.
     * @return Expected dispatcher class name.
     */
    @TestVisible
    private static String getDispatcherClassName(String sObjectName) {
        String baseName = sObjectName;
        for (String suffix : SOBJECT_SUFFIXES) {
            baseName = baseName.removeEndIgnoreCase(suffix);
        }
        if (baseName.contains('__')) {
            baseName = baseName.substringAfter('__');
        }
        return baseName + DISPATCHER_SUFFIX;
    }
}
