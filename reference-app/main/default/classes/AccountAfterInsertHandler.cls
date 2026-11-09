/**
 * @description UAF reference handler for Account after insert. Calls an Autolaunched Flow
 *              (UAF_Test_Echo_Flow) ONCE per batch through UAF_FlowInvoker and stamps its output
 *              on UAF_Insert_Stamp__c with a single DML.
 *
 *              Re-entrancy: if inserting Accounts re-enters after insert while the first execution
 *              is still running (e.g. logic that creates more Accounts), {@link inProgressEntry}
 *              only processes records that were never stamped in this transaction, so no record
 *              is processed twice and the Flow is not invoked for already-handled records.
 * @group UAF Reference
 */
public with sharing class AccountAfterInsertHandler implements UAF_ITriggerHandler {

    public static final String ENRICHMENT_FLOW = 'UAF_Test_Echo_Flow';
    public static final String STAMP_PREFIX = 'UAF processed';
    public static final String BYPASSED_STAMP = 'UAF processed (flow bypassed)';

    /** Flow actually invoked; overridable in tests to exercise the failure path. */
    @TestVisible
    private static String enrichmentFlowName = ENRICHMENT_FLOW;

    /** Accounts already stamped in this transaction. */
    @TestVisible
    private static final Set<Id> PROCESSED_IDS = new Set<Id>();

    public void mainEntry(UAF_TriggerParameters tp) {
        stamp(filterUnprocessed(tp.newList));
    }

    public void inProgressEntry(UAF_TriggerParameters tp) {
        stamp(filterUnprocessed(tp.newList));
    }

    private static List<Account> filterUnprocessed(List<SObject> records) {
        List<Account> pending = new List<Account>();
        for (SObject record : records ?? new List<SObject>()) {
            if (!PROCESSED_IDS.contains(record.Id)) {
                pending.add((Account) record);
            }
        }
        return pending;
    }

    private static void stamp(List<Account> accounts) {
        if (accounts.isEmpty()) {
            return;
        }

        UAF_FlowExecutionResult result = UAF_FlowInvoker.invokeFlow(
            enrichmentFlowName,
            new Map<String, Object>{ 'inputText' => STAMP_PREFIX }
        );
        if (!result.isSuccess) {
            // Fail only the affected records with a descriptive message instead of an unhandled exception.
            for (Account account : accounts) {
                account.addError(result.errorMessage);
            }
            return;
        }

        String stampValue = result.isBypassed ? BYPASSED_STAMP : (String) result.outputVariables.get('outputText');
        List<Account> updates = new List<Account>();
        for (Account account : accounts) {
            updates.add(new Account(Id = account.Id, UAF_Insert_Stamp__c = stampValue));
            PROCESSED_IDS.add(account.Id);
        }
        // FLS/CRUD honored: inaccessible fields are stripped, then DML runs in user mode.
        // Users need the UAF_Reference_Implementation Permission Set for the automation to write them.
        List<Account> writable = stripUnwritable(updates);
        if (!writable.isEmpty()) {
            update as user writable;
        }
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
