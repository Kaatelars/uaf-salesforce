/**
 * @description UAF reference handler for Account after update. Increments
 *              UAF_Name_Change_Count__c when the Name changes (case-sensitive).
 *
 *              Re-entrancy: the handler's own DML re-fires after update on the same records.
 *              UAF_TriggerDispatcherBase routes that nested execution to {@link inProgressEntry},
 *              which does nothing, so the counter is incremented exactly once per real change and
 *              the transaction never loops.
 * @group UAF Reference
 */
public with sharing class AccountAfterUpdateHandler implements UAF_ITriggerHandler {

    /** Number of re-entrant executions absorbed by inProgressEntry (observability for tests). */
    @TestVisible
    private static Integer reentrantExecutions = 0;

    public void mainEntry(UAF_TriggerParameters tp) {
        List<Account> updates = new List<Account>();
        for (SObject record : tp.newList) {
            Account newAccount = (Account) record;
            Account oldAccount = (Account) tp.oldMap.get(newAccount.Id);
            if (!newAccount.Name.equals(oldAccount.Name)) {
                updates.add(new Account(
                    Id = newAccount.Id,
                    UAF_Name_Change_Count__c = (newAccount.UAF_Name_Change_Count__c ?? 0) + 1
                ));
            }
        }
        if (!updates.isEmpty()) {
            // FLS/CRUD honored: inaccessible fields are stripped, then DML runs in user mode.
            // Users need the UAF_Reference_Implementation Permission Set for the automation to write them.
            List<Account> writable = stripUnwritable(updates);
            if (!writable.isEmpty()) {
                update as user writable;
            }
        }
    }

    public void inProgressEntry(UAF_TriggerParameters tp) {
        // Nested update caused by mainEntry's own DML: intentionally ignored.
        reentrantExecutions++;
    }

    /**
     * @description Removes fields the running user cannot update and drops records left with
     *              only their Id, so an empty update never re-fires triggers and Flows.
     * @param records Records to update.
     * @return Records that still carry at least one updatable field.
     */
    private static List<Account> stripUnwritable(List<Account> records) {
        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, records);
        List<Account> writable = new List<Account>();
        for (SObject record : decision.getRecords()) {
            if (record.getPopulatedFieldsAsMap().size() > 1) {
                writable.add((Account) record);
            }
        }
        return writable;
    }
}
