/**
 * @description UAF reference dispatcher for Account. Resolved by convention by
 *              UAF_TriggerFactory ("Account" + "TriggerDispatcher"). Only the events that carry
 *              business logic are overridden; every other event uses the base no-op default.
 * @group UAF Reference
 */
public with sharing class AccountTriggerDispatcher extends UAF_TriggerDispatcherBase {

    public override void afterInsert(UAF_TriggerParameters tp) {
        execute(new AccountAfterInsertHandler(), tp, UAF_TriggerParameters.TriggerEvent.AFTER_INSERT);
    }

    public override void afterUpdate(UAF_TriggerParameters tp) {
        execute(new AccountAfterUpdateHandler(), tp, UAF_TriggerParameters.TriggerEvent.AFTER_UPDATE);
    }
}
