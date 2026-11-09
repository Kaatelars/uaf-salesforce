/**
 * @description End-to-end tests of the UAF reference implementation on Account using real DML:
 *              AccountTrigger -> UAF_TriggerFactory -> AccountTriggerDispatcher -> handlers
 *              (with UAF_FlowInvoker) and the record-triggered UAF_Account_Guarded_Flow (with UAF_FlowGuard).
 *
 *              Users are created ONCE in @TestSetup (creating them per test method serializes
 *              parallel runs on Setup-object locks):
 *              <ul>
 *                <li>{@code BUSINESS_USER}: UAF_Reference_Implementation (FLS on the UAF_*__c fields).
 *                    Every "normal" scenario runs as this user, so results do not depend on the
 *                    permissions of whoever runs the tests.</li>
 *                <li>{@code LOAD_USER}: UAF_Bypass_Automations + UAF_Reference_Implementation
 *                    (Data Loader / SFDMU / ETL user).</li>
 *                <li>{@code NO_FLS_USER}: no Permission Sets (no field access to UAF_*__c).</li>
 *              </ul>
 *
 *              Apex static state (bypasses, re-entrancy flags, guard counters) lives for the whole
 *              test method, which is one transaction. UAF_FlowGuard.resetExecutionCounts() is used
 *              to simulate a new transaction where needed.
 * @group UAF Reference Tests
 */
@IsTest
private with sharing class Account_UAF_Integration_Test {

    private static final String GUARDED_FLOW = 'UAF_Account_Guarded_Flow';
    private static final String REFERENCE_PERMISSION_SET = 'UAF_Reference_Implementation';

    private static final String BUSINESS_USER = 'acct.business';
    private static final String LOAD_USER = 'acct.load';
    private static final String NO_FLS_USER = 'acct.nofls';

    @TestSetup
    static void createUsers() {
        UAF_TestDataFactory.createUser(BUSINESS_USER, new List<String>{ REFERENCE_PERMISSION_SET });
        UAF_TestDataFactory.createUser(LOAD_USER, new List<String>{ REFERENCE_PERMISSION_SET, UAF_TestDataFactory.BYPASS_PERMISSION_SET });
        UAF_TestDataFactory.createUser(NO_FLS_USER, new List<String>());
    }

    private static User businessUser() {
        return UAF_TestDataFactory.getUser(BUSINESS_USER);
    }

    private static List<Account> buildAccounts(Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(Name = 'UAF Integration ' + i));
        }
        return accounts;
    }

    private static Map<Id, Account> reload(List<Account> accounts) {
        return new Map<Id, Account>([
            SELECT Id, Name, UAF_Insert_Stamp__c, UAF_Flow_Run_Count__c, UAF_Name_Change_Count__c
            FROM Account
            WHERE Id IN :accounts
            WITH SYSTEM_MODE
        ]);
    }

    private static Account reloadOne(Account account) {
        return reload(new List<Account>{ account }).get(account.Id);
    }

    // ------------------------------------------------------------------------------------------
    // Trigger -> Factory -> Dispatcher -> Handler (+ FlowInvoker)
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void singleInsertRunsHandlerAndGuardedFlow() {
        Account account = buildAccounts(1)[0];

        Test.startTest();
        System.runAs(businessUser()) {
            insert account;
        }
        Test.stopTest();

        Account saved = reloadOne(account);
        Assert.areEqual(AccountAfterInsertHandler.STAMP_PREFIX, saved.UAF_Insert_Stamp__c, 'After insert handler should stamp the UAF_Test_Echo_Flow output');
        Assert.areEqual(1, saved.UAF_Flow_Run_Count__c, 'Guarded flow must run exactly once despite the nested saves');
        Assert.isNull(saved.UAF_Name_Change_Count__c, 'Name did not change');
        Assert.areEqual(1, UAF_FlowGuard.getExecutionCount(GUARDED_FLOW, account.Id), 'Guard should record one allowed execution');
    }

    @IsTest
    static void bulkInsertOf200IsBulkSafe() {
        List<Account> accounts = buildAccounts(200);
        Integer queries;
        Integer dmlStatements;

        Test.startTest();
        System.runAs(businessUser()) {
            insert accounts;
            queries = Limits.getQueries();
            dmlStatements = Limits.getDmlStatements();
        }
        Test.stopTest();

        Map<Id, Account> saved = reload(accounts);
        Assert.areEqual(200, saved.size(), 'All accounts should be inserted');
        for (Account account : saved.values()) {
            Assert.areEqual(AccountAfterInsertHandler.STAMP_PREFIX, account.UAF_Insert_Stamp__c, 'Every account should be stamped');
            Assert.areEqual(1, account.UAF_Flow_Run_Count__c, 'Guarded flow runs once per account');
        }
        // Handler invokes the flow once per batch and issues one DML: totals must not scale with record count.
        Assert.isTrue(queries <= 5, 'SOQL must not scale with records, used: ' + queries);
        Assert.isTrue(dmlStatements <= 5, 'DML must not scale with records, used: ' + dmlStatements);
    }

    @IsTest
    static void allTriggerEventsDispatchThroughFactory() {
        List<Account> accounts = buildAccounts(3);

        Test.startTest();
        System.runAs(businessUser()) {
            insert accounts;
            delete accounts;
            undelete accounts;
        }
        Test.stopTest();

        Assert.areEqual(3, reload(accounts).size(), 'Accounts should be restored after delete/undelete through the UAF trigger');
    }

    // ------------------------------------------------------------------------------------------
    // Re-entrancy
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void renameIncrementsCounterOnceDespiteRecursiveUpdate() {
        List<Account> accounts = buildAccounts(200);

        Test.startTest();
        System.runAs(businessUser()) {
            insert accounts;
            for (Account account : accounts) {
                account.Name = account.Name + ' renamed';
            }
            update accounts;
        }
        Test.stopTest();

        for (Account account : reload(accounts).values()) {
            Assert.areEqual(1, account.UAF_Name_Change_Count__c, 'Counter must be incremented exactly once per rename');
        }
        Assert.isTrue(AccountAfterUpdateHandler.reentrantExecutions >= 1, 'The handler DML must re-enter through inProgressEntry');
    }

    @IsTest
    static void updateWithoutNameChangeDoesNotIncrement() {
        Account account = buildAccounts(1)[0];

        Test.startTest();
        System.runAs(businessUser()) {
            insert account;
            update new Account(Id = account.Id, Description = 'no rename');
            update new Account(Id = account.Id, Name = account.Name.toUpperCase());
        }
        Test.stopTest();

        Assert.areEqual(1, reloadOne(account).UAF_Name_Change_Count__c, 'Only the (case-sensitive) rename should increment the counter');
    }

    @IsTest
    static void afterInsertInProgressEntrySkipsProcessedRecords() {
        Account processed = buildAccounts(1)[0];
        Account unprocessed = new Account(Name = 'UAF inserted while bypassed');
        Integer dmlUsed;
        Integer dmlOnSecondReentry;

        Test.startTest();
        System.runAs(businessUser()) {
            insert processed;
            UAF_BypassManager.bypassObject('Account');
            insert unprocessed;
            UAF_BypassManager.clearBypassObject('Account');

            List<Account> records = new List<Account>{ processed, unprocessed };
            UAF_TriggerParameters tp = new UAF_TriggerParameters.Builder()
                .operation(System.TriggerOperation.AFTER_INSERT)
                .newRecords(records, new Map<Id, SObject>(records))
                .build();

            // Isolate the handler: the guarded flow would otherwise add its own DML on the stamp update.
            UAF_BypassManager.bypassFlow(GUARDED_FLOW);

            Integer dmlBefore = Limits.getDmlStatements();
            new AccountAfterInsertHandler().inProgressEntry(tp);
            dmlUsed = Limits.getDmlStatements() - dmlBefore;

            dmlBefore = Limits.getDmlStatements();
            new AccountAfterInsertHandler().inProgressEntry(tp);
            dmlOnSecondReentry = Limits.getDmlStatements() - dmlBefore;
        }
        Test.stopTest();

        Assert.areEqual(1, dmlUsed, 'A single DML should stamp only the pending record');
        Assert.areEqual(AccountAfterInsertHandler.STAMP_PREFIX, reloadOne(unprocessed).UAF_Insert_Stamp__c, 'Pending record should be stamped on re-entry');
        Assert.isTrue(AccountAfterInsertHandler.PROCESSED_IDS.contains(unprocessed.Id), 'Pending record should now be tracked');
        Assert.areEqual(0, dmlOnSecondReentry, 'Re-entry with already processed records must do nothing');
    }

    @IsTest
    static void flowFailureInHandlerFailsRecordsWithDescriptiveError() {
        AccountAfterInsertHandler.enrichmentFlowName = 'UAF_Flow_That_Does_Not_Exist';
        List<Account> accounts = buildAccounts(3);
        List<Database.SaveResult> results;

        Test.startTest();
        System.runAs(businessUser()) {
            results = Database.insert(accounts, false);
        }
        Test.stopTest();

        for (Database.SaveResult result : results) {
            Assert.isFalse(result.isSuccess(), 'Insert should fail when the handler flow fails');
            Assert.isTrue(result.getErrors()[0].getMessage().contains('was not found'),
                'Error should come from UAF_FlowInvoker: ' + result.getErrors()[0].getMessage());
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE Id IN :accounts WITH SYSTEM_MODE], 'No account should be persisted');
    }

    // ------------------------------------------------------------------------------------------
    // Field-level security
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void userWithoutFieldAccessSavesButAutomationFieldsAreStripped() {
        List<Account> accounts = buildAccounts(5);

        Test.startTest();
        System.runAs(UAF_TestDataFactory.getUser(NO_FLS_USER)) {
            insert accounts;
            for (Account account : accounts) {
                account.Name = account.Name + ' renamed';
            }
            update accounts;
        }
        Test.stopTest();

        for (Account account : reload(accounts).values()) {
            Assert.isTrue(account.Name.endsWith(' renamed'), 'Saves must succeed even without field access');
            Assert.isNull(account.UAF_Insert_Stamp__c, 'Stamp is stripped by Security.stripInaccessible');
            Assert.isNull(account.UAF_Name_Change_Count__c, 'Counter is stripped by Security.stripInaccessible');
            Assert.areEqual(1, account.UAF_Flow_Run_Count__c, 'Record-triggered flows run in system context and still apply');
        }
    }

    // ------------------------------------------------------------------------------------------
    // In-memory bypasses
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void bypassObjectSkipsHandlerAndGuardedFlow() {
        List<Account> accounts = buildAccounts(5);

        Test.startTest();
        System.runAs(businessUser()) {
            UAF_BypassManager.bypassObject('Account');
            insert accounts;
        }
        Test.stopTest();

        for (Account account : reload(accounts).values()) {
            Assert.isNull(account.UAF_Insert_Stamp__c, 'Handler logic must not run for a bypassed object');
            Assert.isNull(account.UAF_Flow_Run_Count__c, 'Guard must also block the flow for a bypassed object');
        }
        Assert.isTrue(AccountAfterInsertHandler.PROCESSED_IDS.isEmpty(), 'Handler must not have been invoked');
    }

    @IsTest
    static void bypassGuardedFlowKeepsApexLogic() {
        Account account = buildAccounts(1)[0];

        Test.startTest();
        System.runAs(businessUser()) {
            UAF_BypassManager.bypassFlow(GUARDED_FLOW);
            insert account;
        }
        Test.stopTest();

        Account saved = reloadOne(account);
        Assert.areEqual(AccountAfterInsertHandler.STAMP_PREFIX, saved.UAF_Insert_Stamp__c, 'Apex handler still runs');
        Assert.isNull(saved.UAF_Flow_Run_Count__c, 'Bypassed flow must abort at the guard');
        Assert.areEqual(0, UAF_FlowGuard.getExecutionCount(GUARDED_FLOW, account.Id), 'Bypassed executions are not counted');
    }

    @IsTest
    static void bypassInvokedFlowFromHandler() {
        Account account = buildAccounts(1)[0];

        Test.startTest();
        System.runAs(businessUser()) {
            UAF_BypassManager.bypassFlow(AccountAfterInsertHandler.ENRICHMENT_FLOW);
            insert account;
        }
        Test.stopTest();

        Assert.areEqual(AccountAfterInsertHandler.BYPASSED_STAMP, reloadOne(account).UAF_Insert_Stamp__c,
            'UAF_FlowInvoker should skip the bypassed flow and the handler should record it');
    }

    // ------------------------------------------------------------------------------------------
    // User-level bypass: Custom Permission UAF_Bypass_All (Data Loader / SFDMU / ETL users)
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void dataLoadUserWithBypassPermissionSkipsAllAutomation() {
        List<Account> accounts = buildAccounts(200);

        Test.startTest();
        System.runAs(UAF_TestDataFactory.getUser(LOAD_USER)) {
            insert accounts;
            for (Account account : accounts) {
                account.Name = account.Name + ' reloaded';
            }
            update accounts;
        }
        Test.stopTest();

        for (Account account : reload(accounts).values()) {
            Assert.isNull(account.UAF_Insert_Stamp__c, 'After insert handler must not run for the load user');
            Assert.isNull(account.UAF_Name_Change_Count__c, 'After update handler must not run for the load user');
            Assert.isNull(account.UAF_Flow_Run_Count__c, 'Guarded record-triggered flow must abort for the load user');
        }
        Assert.isTrue(AccountAfterInsertHandler.PROCESSED_IDS.isEmpty(), 'Handler must not have been invoked');
    }

    @IsTest
    static void businessUserAutomationRunsOnRecordsLoadedWithBypass() {
        Account account = buildAccounts(1)[0];

        Test.startTest();
        System.runAs(UAF_TestDataFactory.getUser(LOAD_USER)) {
            insert account;
        }
        System.runAs(businessUser()) {
            update new Account(Id = account.Id, Name = 'UAF edited by business user');
        }
        Test.stopTest();

        Account saved = reloadOne(account);
        Assert.isNull(saved.UAF_Insert_Stamp__c, 'Insert happened under bypass');
        Assert.areEqual(1, saved.UAF_Name_Change_Count__c, 'Business user update runs Apex automation normally');
        Assert.areEqual(1, saved.UAF_Flow_Run_Count__c, 'Business user update runs the guarded flow normally');
    }

    // ------------------------------------------------------------------------------------------
    // UAF_FlowGuard limits
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void guardLimitsFlowToOncePerRecordPerTransaction() {
        Account account = buildAccounts(1)[0];
        Decimal runsSameTransaction;

        Test.startTest();
        System.runAs(businessUser()) {
            insert account;
            // Same transaction: the guard has already allowed one execution for this record.
            update new Account(Id = account.Id, Name = 'UAF same transaction');
            runsSameTransaction = reloadOne(account).UAF_Flow_Run_Count__c;

            // Simulated new transaction: counters reset, the flow may run again.
            UAF_FlowGuard.resetExecutionCounts();
            update new Account(Id = account.Id, Name = 'UAF new transaction');
        }
        Test.stopTest();

        Assert.areEqual(1, runsSameTransaction, 'Flow must be blocked by MAX_RECURSION_REACHED in the same transaction');
        Assert.areEqual(2, reloadOne(account).UAF_Flow_Run_Count__c, 'Flow should run again in a new transaction');
    }
}
