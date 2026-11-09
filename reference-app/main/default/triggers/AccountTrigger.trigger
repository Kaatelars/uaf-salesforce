trigger AccountTrigger on Account (before insert, after insert, before update, after update, before delete, after delete, after undelete) {
    UAF_TriggerFactory.createAndDispatch(Account.SObjectType);
}
