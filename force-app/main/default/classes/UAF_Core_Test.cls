/**
 * @description Unit tests for the UAF Core: UAF_TriggerParameters, UAF_TriggerDispatcherBase
 *              and UAF_TriggerFactory. No DML is required: trigger contexts are simulated through
 *              UAF_TriggerParameters.Builder. Bypass tests live in UAF_BypassManager_Test.
 * @group UAF Core Tests
 */
@IsTest
private inherited sharing class UAF_Core_Test {

    /** Ordered log of dispatcher / handler calls, shared by the test doubles below. */
    private static List<String> callLog = new List<String>();

    /** When true, RecordingHandler re-enters the factory from mainEntry (simulates recursive DML). */
    private static Boolean reenterFromHandler = false;

    // ------------------------------------------------------------------------------------------
    // Test doubles
    // ------------------------------------------------------------------------------------------

    /** Dispatcher that logs every callback and routes each event to RecordingHandler. */
    public class RecordingDispatcher extends UAF_TriggerDispatcherBase {
        public override void bulkBefore(UAF_TriggerParameters tp) { callLog.add('bulkBefore'); }
        public override void bulkAfter(UAF_TriggerParameters tp) { callLog.add('bulkAfter'); }
        public override void beforeInsert(UAF_TriggerParameters tp) { run(tp, UAF_TriggerParameters.TriggerEvent.BEFORE_INSERT); }
        public override void afterInsert(UAF_TriggerParameters tp) { run(tp, UAF_TriggerParameters.TriggerEvent.AFTER_INSERT); }
        public override void beforeUpdate(UAF_TriggerParameters tp) { run(tp, UAF_TriggerParameters.TriggerEvent.BEFORE_UPDATE); }
        public override void afterUpdate(UAF_TriggerParameters tp) { run(tp, UAF_TriggerParameters.TriggerEvent.AFTER_UPDATE); }
        public override void beforeDelete(UAF_TriggerParameters tp) { run(tp, UAF_TriggerParameters.TriggerEvent.BEFORE_DELETE); }
        public override void afterDelete(UAF_TriggerParameters tp) { run(tp, UAF_TriggerParameters.TriggerEvent.AFTER_DELETE); }
        public override void afterUndelete(UAF_TriggerParameters tp) { run(tp, UAF_TriggerParameters.TriggerEvent.AFTER_UNDELETE); }
        public override void andFinally(UAF_TriggerParameters tp) { callLog.add('andFinally'); }

        private void run(UAF_TriggerParameters tp, UAF_TriggerParameters.TriggerEvent event) {
            callLog.add(event.name());
            execute(new RecordingHandler(), tp, event);
        }
    }

    /** Dispatcher relying only on the base no-op defaults. */
    public class EmptyDispatcher extends UAF_TriggerDispatcherBase {}

    /** Type that does NOT implement UAF_ITriggerDispatcher. */
    public class NotADispatcher {}

    public class RecordingHandler implements UAF_ITriggerHandler {
        public void mainEntry(UAF_TriggerParameters tp) {
            callLog.add('mainEntry');
            if (reenterFromHandler) {
                reenterFromHandler = false;
                // Simulates DML on the same SObject re-firing the same event.
                UAF_TriggerFactory.dispatch(Account.SObjectType, tp);
            }
        }
        public void inProgressEntry(UAF_TriggerParameters tp) {
            callLog.add('inProgressEntry');
        }
    }

    public class ThrowingHandler implements UAF_ITriggerHandler {
        public void mainEntry(UAF_TriggerParameters tp) {
            throw new UAF_TriggerException('boom');
        }
        public void inProgressEntry(UAF_TriggerParameters tp) {
            callLog.add('unexpected inProgressEntry');
        }
    }

    // ------------------------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------------------------

    private static List<Account> buildAccounts(Integer count) {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(Name = 'UAF Test ' + i));
        }
        return accounts;
    }

    private static UAF_TriggerParameters buildParams(UAF_TriggerParameters.TriggerEvent event, List<SObject> records) {
        String name = event.name();
        Boolean hasOld = name.endsWith('_UPDATE') || name.endsWith('_DELETE');
        Boolean hasNew = !name.endsWith('_DELETE');
        return new UAF_TriggerParameters.Builder()
            .operation(toOperation(event))
            .oldRecords(hasOld ? records : null, null)
            .newRecords(hasNew ? records : null, null)
            .build();
    }

    private static System.TriggerOperation toOperation(UAF_TriggerParameters.TriggerEvent event) {
        for (System.TriggerOperation operation : System.TriggerOperation.values()) {
            if (operation.name() == event.name()) {
                return operation;
            }
        }
        return null;
    }

    private static void registerRecordingDispatcher() {
        UAF_TriggerFactory.DISPATCHER_OVERRIDES.put('account', RecordingDispatcher.class);
    }

    // ------------------------------------------------------------------------------------------
    // UAF_TriggerParameters
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void parametersResolveEveryEvent() {
        List<Account> accounts = buildAccounts(2);
        for (UAF_TriggerParameters.TriggerEvent event : UAF_TriggerParameters.TriggerEvent.values()) {
            UAF_TriggerParameters tp = buildParams(event, accounts);
            String name = event.name();
            Assert.areEqual(event, tp.triggerEvent, 'Event should be resolved from the operation for ' + name);
            Assert.areEqual(name.startsWith('BEFORE_'), tp.isBefore, 'isBefore for ' + name);
            Assert.areEqual(name.startsWith('AFTER_'), tp.isAfter, 'isAfter for ' + name);
            Assert.areEqual(name.endsWith('_INSERT'), tp.isInsert, 'isInsert for ' + name);
            Assert.areEqual(name.endsWith('_UPDATE'), tp.isUpdate, 'isUpdate for ' + name);
            Assert.areEqual(name == 'BEFORE_DELETE' || name == 'AFTER_DELETE', tp.isDelete, 'isDelete for ' + name);
            Assert.areEqual(name == 'AFTER_UNDELETE', tp.isUndelete, 'isUndelete for ' + name);
            Assert.areEqual(Account.SObjectType, tp.sObjectType, 'SObjectType should be derived from the records');
            Assert.areEqual('Account', tp.sObjectName, 'SObject name should be the API name');
            Assert.isFalse(tp.isExecuting, 'A simulated context is never executing');
        }
    }

    @IsTest
    static void parametersKeepAllContextValues() {
        List<Account> accounts = buildAccounts(1);
        Map<Id, SObject> recordMap = new Map<Id, SObject>{ UAF_TestDataFactory.fakeId(Account.SObjectType, 1) => accounts[0] };

        UAF_TriggerParameters tp = new UAF_TriggerParameters.Builder()
            .operation(System.TriggerOperation.AFTER_UPDATE)
            .oldRecords(accounts, recordMap)
            .newRecords(accounts, recordMap)
            .build();

        Assert.areEqual(accounts, tp.oldList, 'oldList should be preserved');
        Assert.areEqual(accounts, tp.newList, 'newList should be preserved');
        Assert.areEqual(recordMap, tp.oldMap, 'oldMap should be preserved');
        Assert.areEqual(recordMap, tp.newMap, 'newMap should be preserved');
        Assert.areEqual(UAF_TriggerParameters.TriggerEvent.AFTER_UPDATE, tp.triggerEvent, 'Should be AFTER_UPDATE');
    }

    @IsTest
    static void parametersOutsideTriggerAreEmpty() {
        UAF_TriggerParameters tp = UAF_TriggerParameters.fromTriggerContext();

        Assert.isNull(tp.newList, 'newList should be null outside a trigger');
        Assert.isNull(tp.oldList, 'oldList should be null outside a trigger');
        Assert.isNull(tp.triggerEvent, 'No event should be resolved outside a trigger');
        Assert.isNull(tp.sObjectType, 'No SObjectType outside a trigger');
        Assert.isNull(tp.sObjectName, 'No SObject name outside a trigger');
        Assert.isFalse(tp.isExecuting, 'isExecuting should be false outside a trigger');
        Assert.isFalse(tp.isBefore, 'Flags should be false without an operation');
        Assert.isFalse(tp.isAfter, 'Flags should be false without an operation');
    }

    // ------------------------------------------------------------------------------------------
    // UAF_TriggerFactory - dispatching
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void factoryDispatchesBeforeEventsInOrder() {
        registerRecordingDispatcher();

        Test.startTest();
        UAF_TriggerFactory.dispatch(Account.SObjectType, buildParams(UAF_TriggerParameters.TriggerEvent.BEFORE_INSERT, buildAccounts(200)));
        Test.stopTest();

        Assert.areEqual(
            new List<String>{ 'bulkBefore', 'BEFORE_INSERT', 'mainEntry', 'andFinally' },
            callLog,
            'Before events should run bulkBefore -> event -> handler -> andFinally'
        );
    }

    @IsTest
    static void factoryDispatchesEveryEvent() {
        registerRecordingDispatcher();
        List<Account> accounts = buildAccounts(5);

        Test.startTest();
        for (UAF_TriggerParameters.TriggerEvent event : UAF_TriggerParameters.TriggerEvent.values()) {
            callLog.clear();
            UAF_TriggerFactory.dispatch(Account.SObjectType, buildParams(event, accounts));

            String bulkMethod = event.name().startsWith('BEFORE_') ? 'bulkBefore' : 'bulkAfter';
            Assert.areEqual(
                new List<String>{ bulkMethod, event.name(), 'mainEntry', 'andFinally' },
                callLog,
                'Unexpected call sequence for ' + event.name()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void factorySkipsBypassedObject() {
        registerRecordingDispatcher();
        UAF_BypassManager.bypassObject('Account');

        Test.startTest();
        UAF_TriggerFactory.dispatch(Account.SObjectType, buildParams(UAF_TriggerParameters.TriggerEvent.AFTER_INSERT, buildAccounts(1)));
        Test.stopTest();

        Assert.isTrue(callLog.isEmpty(), 'Bypassed object must not reach the dispatcher');
    }

    @IsTest
    static void factoryBypassDoesNotRequireDispatcher() {
        // No override and no ContactTriggerDispatcher class: bypass must short-circuit before lookup.
        UAF_BypassManager.bypassObject('Contact');
        UAF_TriggerParameters tp = buildParams(UAF_TriggerParameters.TriggerEvent.BEFORE_INSERT, new List<Contact>{ new Contact() });

        UAF_TriggerFactory.dispatch(Contact.SObjectType, tp);

        Assert.isTrue(callLog.isEmpty(), 'Nothing should run for a bypassed object');
    }

    @IsTest
    static void factoryWorksWithBaseDefaults() {
        UAF_TriggerFactory.DISPATCHER_OVERRIDES.put('account', EmptyDispatcher.class);
        List<Account> accounts = buildAccounts(1);

        for (UAF_TriggerParameters.TriggerEvent event : UAF_TriggerParameters.TriggerEvent.values()) {
            UAF_TriggerFactory.dispatch(Account.SObjectType, buildParams(event, accounts));
        }

        Assert.isTrue(callLog.isEmpty(), 'Default base implementations must be no-ops');
    }

    @IsTest
    static void factoryThrowsWhenDispatcherMissing() {
        // Independent of org contents: a null resolved type is exactly what Type.forName returns for a missing class.
        try {
            UAF_TriggerFactory.instantiateDispatcher(null, 'Invoice__c');
            Assert.fail('Expected UAF_TriggerException for missing dispatcher');
        } catch (UAF_TriggerException e) {
            Assert.isTrue(e.getMessage().contains('InvoiceTriggerDispatcher'), 'Message should name the expected class: ' + e.getMessage());
        }
    }

    @IsTest
    static void factoryThrowsWhenTypeIsNotADispatcher() {
        UAF_TriggerFactory.DISPATCHER_OVERRIDES.put('account', NotADispatcher.class);
        try {
            UAF_TriggerFactory.dispatch(Account.SObjectType, buildParams(UAF_TriggerParameters.TriggerEvent.BEFORE_INSERT, buildAccounts(1)));
            Assert.fail('Expected UAF_TriggerException for invalid dispatcher type');
        } catch (UAF_TriggerException e) {
            Assert.isTrue(e.getMessage().contains('does not implement'), 'Unexpected message: ' + e.getMessage());
        }
    }

    @IsTest
    static void factoryRejectsInvalidArguments() {
        UAF_TriggerParameters invalid = UAF_TriggerParameters.fromTriggerContext();
        List<UAF_TriggerParameters> cases = new List<UAF_TriggerParameters>{ null, invalid };
        for (UAF_TriggerParameters tp : cases) {
            try {
                UAF_TriggerFactory.dispatch(Account.SObjectType, tp);
                Assert.fail('Expected UAF_TriggerException for invalid context');
            } catch (UAF_TriggerException e) {
                Assert.isTrue(e.getMessage().contains('required'), 'Unexpected message: ' + e.getMessage());
            }
        }
        try {
            UAF_TriggerFactory.dispatch(null, buildParams(UAF_TriggerParameters.TriggerEvent.BEFORE_INSERT, buildAccounts(1)));
            Assert.fail('Expected UAF_TriggerException for null SObjectType');
        } catch (UAF_TriggerException e) {
            Assert.isNotNull(e.getMessage(), 'Exception should have a message');
        }
    }

    @IsTest
    static void createAndDispatchOutsideTriggerThrows() {
        try {
            UAF_TriggerFactory.createAndDispatch(Account.SObjectType);
            Assert.fail('Expected UAF_TriggerException outside a trigger');
        } catch (UAF_TriggerException e) {
            Assert.isTrue(e.getMessage().contains('must be called from a trigger'), 'Unexpected message: ' + e.getMessage());
        }
    }

    @IsTest
    static void dispatcherClassNameConvention() {
        Assert.areEqual('AccountTriggerDispatcher', UAF_TriggerFactory.getDispatcherClassName('Account'), 'Standard object');
        Assert.areEqual('InvoiceTriggerDispatcher', UAF_TriggerFactory.getDispatcherClassName('Invoice__c'), 'Custom object');
        Assert.areEqual('Invoice_LineTriggerDispatcher', UAF_TriggerFactory.getDispatcherClassName('Invoice_Line__c'), 'Custom object with underscores');
        Assert.areEqual('InvoiceTriggerDispatcher', UAF_TriggerFactory.getDispatcherClassName('ns__Invoice__c'), 'Namespaced custom object');
        Assert.areEqual('Order_EventTriggerDispatcher', UAF_TriggerFactory.getDispatcherClassName('Order_Event__e'), 'Platform event');
    }

    // ------------------------------------------------------------------------------------------
    // UAF_TriggerDispatcherBase - re-entrancy
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void reentrantDispatchCallsInProgressEntry() {
        registerRecordingDispatcher();
        reenterFromHandler = true;
        UAF_TriggerParameters tp = buildParams(UAF_TriggerParameters.TriggerEvent.AFTER_UPDATE, buildAccounts(200));

        Test.startTest();
        UAF_TriggerFactory.dispatch(Account.SObjectType, tp);
        Test.stopTest();

        Assert.areEqual(
            new List<String>{
                'bulkAfter', 'AFTER_UPDATE', 'mainEntry',
                    'bulkAfter', 'AFTER_UPDATE', 'inProgressEntry', 'andFinally',
                'andFinally'
            },
            callLog,
            'Nested dispatch of the same event must route to inProgressEntry, not mainEntry'
        );
        Assert.isFalse(
            UAF_TriggerDispatcherBase.isInProgress('Account', UAF_TriggerParameters.TriggerEvent.AFTER_UPDATE),
            'In-progress flag must be released after the outer execution'
        );
    }

    @IsTest
    static void inProgressFlagIsScopedToEvent() {
        RecordingDispatcher dispatcher = new RecordingDispatcher();
        UAF_TriggerParameters tp = buildParams(UAF_TriggerParameters.TriggerEvent.BEFORE_UPDATE, buildAccounts(1));

        // Handler that, while beforeUpdate is running, checks flags and runs a different event.
        UAF_ITriggerHandler inspectingHandler = new FlagInspectingHandler(dispatcher);
        dispatcher.execute(inspectingHandler, tp, UAF_TriggerParameters.TriggerEvent.BEFORE_UPDATE);

        Assert.areEqual(
            new List<String>{ 'beforeUpdate:inProgress=true', 'afterUpdate:inProgress=false', 'mainEntry' },
            callLog,
            'Only the running SObject/event should be flagged as in progress'
        );
        Assert.isFalse(
            UAF_TriggerDispatcherBase.isInProgress('Account', UAF_TriggerParameters.TriggerEvent.BEFORE_UPDATE),
            'Flag must be released'
        );
        Assert.isFalse(UAF_TriggerDispatcherBase.isInProgress('Account', null), 'Null event is never in progress');
    }

    public class FlagInspectingHandler implements UAF_ITriggerHandler {
        private UAF_TriggerDispatcherBase dispatcher;
        public FlagInspectingHandler(UAF_TriggerDispatcherBase dispatcher) {
            this.dispatcher = dispatcher;
        }
        public void mainEntry(UAF_TriggerParameters tp) {
            callLog.add('beforeUpdate:inProgress=' + UAF_TriggerDispatcherBase.isInProgress('account', UAF_TriggerParameters.TriggerEvent.BEFORE_UPDATE));
            callLog.add('afterUpdate:inProgress=' + UAF_TriggerDispatcherBase.isInProgress('Account', UAF_TriggerParameters.TriggerEvent.AFTER_UPDATE));
            dispatcher.execute(new RecordingHandler(), tp, UAF_TriggerParameters.TriggerEvent.AFTER_UPDATE);
        }
        public void inProgressEntry(UAF_TriggerParameters tp) {
            callLog.add('unexpected inProgressEntry');
        }
    }

    @IsTest
    static void inProgressFlagReleasedWhenHandlerThrows() {
        EmptyDispatcher dispatcher = new EmptyDispatcher();
        UAF_TriggerParameters tp = buildParams(UAF_TriggerParameters.TriggerEvent.AFTER_INSERT, buildAccounts(1));

        try {
            dispatcher.execute(new ThrowingHandler(), tp, UAF_TriggerParameters.TriggerEvent.AFTER_INSERT);
            Assert.fail('Handler exception should propagate');
        } catch (UAF_TriggerException e) {
            Assert.areEqual('boom', e.getMessage(), 'Original exception should propagate');
        }

        Assert.isFalse(
            UAF_TriggerDispatcherBase.isInProgress('Account', UAF_TriggerParameters.TriggerEvent.AFTER_INSERT),
            'Flag must be released even if the handler throws'
        );

        // A subsequent execution must reach mainEntry again.
        dispatcher.execute(new RecordingHandler(), tp, UAF_TriggerParameters.TriggerEvent.AFTER_INSERT);
        Assert.areEqual(new List<String>{ 'mainEntry' }, callLog, 'Next execution should be a main entry');
    }

    @IsTest
    static void executeRejectsNullArguments() {
        EmptyDispatcher dispatcher = new EmptyDispatcher();
        UAF_TriggerParameters tp = buildParams(UAF_TriggerParameters.TriggerEvent.AFTER_INSERT, buildAccounts(1));
        try {
            dispatcher.execute(null, tp, UAF_TriggerParameters.TriggerEvent.AFTER_INSERT);
            Assert.fail('Expected UAF_TriggerException for null handler');
        } catch (UAF_TriggerException e) {
            Assert.isTrue(e.getMessage().contains('required'), 'Unexpected message: ' + e.getMessage());
        }
    }
}
