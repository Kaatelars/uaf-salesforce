/**
 * @description Unit tests for the UAF Flow bridge: UAF_FlowGuard, UAF_FlowInvoker and
 *              UAF_FlowExecutionResult. Invoker tests use the fixture Flow UAF_Test_Echo_Flow
 *              (echoes inputText -> outputText; faults when shouldFail = true).
 * @group UAF Flow Tests
 */
@IsTest
private inherited sharing class UAF_Flow_Test {

    private static final String GUARDED_FLOW = 'Account_After_Save_Flow';
    private static final String ECHO_FLOW = 'UAF_Test_Echo_Flow';
    private static final Id ACCOUNT_ID_1 = UAF_TestDataFactory.fakeId(Account.SObjectType, 1);
    private static final Id ACCOUNT_ID_2 = UAF_TestDataFactory.fakeId(Account.SObjectType, 2);

    private static UAF_FlowGuard.UAF_FlowGuardRequest buildRequest(String flowApiName, Id recordId) {
        UAF_FlowGuard.UAF_FlowGuardRequest request = new UAF_FlowGuard.UAF_FlowGuardRequest();
        request.flowApiName = flowApiName;
        request.recordId = recordId;
        return request;
    }

    private static UAF_FlowGuard.UAF_FlowGuardResult check(UAF_FlowGuard.UAF_FlowGuardRequest request) {
        List<UAF_FlowGuard.UAF_FlowGuardResult> results = UAF_FlowGuard.checkExecution(
            new List<UAF_FlowGuard.UAF_FlowGuardRequest>{ request }
        );
        Assert.areEqual(1, results.size(), 'One result per request');
        return results[0];
    }

    // ------------------------------------------------------------------------------------------
    // UAF_FlowGuard - allow / recursion
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void guardAllowsFirstExecutionAndBlocksRecursion() {
        Test.startTest();
        UAF_FlowGuard.UAF_FlowGuardResult first = check(buildRequest(GUARDED_FLOW, ACCOUNT_ID_1));
        UAF_FlowGuard.UAF_FlowGuardResult second = check(buildRequest(GUARDED_FLOW, ACCOUNT_ID_1));
        Test.stopTest();

        Assert.isTrue(first.shouldRun, 'First execution should be allowed');
        Assert.areEqual(UAF_FlowGuard.REASON_ALLOWED, first.reason, 'Reason should be ALLOWED');
        Assert.areEqual(1, first.executionCount, 'First execution counted');

        Assert.isFalse(second.shouldRun, 'Second execution exceeds default limit of 1');
        Assert.areEqual(UAF_FlowGuard.REASON_MAX_RECURSION, second.reason, 'Reason should be MAX_RECURSION_REACHED');
        Assert.areEqual(1, second.executionCount, 'Blocked execution is not counted');
        Assert.areEqual(1, UAF_FlowGuard.getExecutionCount(GUARDED_FLOW, ACCOUNT_ID_1), 'Counter should stay at 1');
    }

    @IsTest
    static void guardHonorsCustomMaxExecutions() {
        List<Boolean> outcomes = new List<Boolean>();
        for (Integer i = 0; i < 4; i++) {
            UAF_FlowGuard.UAF_FlowGuardRequest request = buildRequest(GUARDED_FLOW, ACCOUNT_ID_1);
            request.maxExecutionsPerRecord = 3;
            outcomes.add(check(request).shouldRun);
        }
        Assert.areEqual(new List<Boolean>{ true, true, true, false }, outcomes, 'Exactly 3 executions should be allowed');
    }

    @IsTest
    static void guardCountersAreIsolatedPerRecordAndFlow() {
        Assert.isTrue(check(buildRequest(GUARDED_FLOW, ACCOUNT_ID_1)).shouldRun, 'Record 1 / flow A allowed');
        Assert.isTrue(check(buildRequest(GUARDED_FLOW, ACCOUNT_ID_2)).shouldRun, 'Record 2 has its own counter');
        Assert.isTrue(check(buildRequest('Other_Flow', ACCOUNT_ID_1)).shouldRun, 'Another flow has its own counter');
        Assert.isFalse(check(buildRequest(GUARDED_FLOW.toUpperCase(), ACCOUNT_ID_1)).shouldRun, 'Flow name is case-insensitive');
    }

    @IsTest
    static void guardWithoutRecordIdOnlyChecksBypass() {
        for (Integer i = 0; i < 3; i++) {
            UAF_FlowGuard.UAF_FlowGuardResult result = check(buildRequest(GUARDED_FLOW, null));
            Assert.isTrue(result.shouldRun, 'Without recordId there is no recursion limit');
            Assert.areEqual(0, result.executionCount, 'Nothing is tracked without recordId');
        }
        Assert.areEqual(0, UAF_FlowGuard.getExecutionCount(GUARDED_FLOW, null), 'No counter without recordId');
    }

    @IsTest
    static void guardIsBulkSafeAndPreservesOrder() {
        List<UAF_FlowGuard.UAF_FlowGuardRequest> requests = new List<UAF_FlowGuard.UAF_FlowGuardRequest>();
        for (Integer i = 1; i <= 200; i++) {
            requests.add(buildRequest(GUARDED_FLOW, UAF_TestDataFactory.fakeId(Account.SObjectType, i)));
        }
        // Duplicate of the first record at the end: must be blocked.
        requests.add(buildRequest(GUARDED_FLOW, requests[0].recordId));

        Test.startTest();
        List<UAF_FlowGuard.UAF_FlowGuardResult> results = UAF_FlowGuard.checkExecution(requests);
        Test.stopTest();

        Assert.areEqual(201, results.size(), 'One result per request');
        for (Integer i = 0; i < 200; i++) {
            Assert.isTrue(results[i].shouldRun, 'Distinct record #' + i + ' should be allowed');
        }
        Assert.areEqual(UAF_FlowGuard.REASON_MAX_RECURSION, results[200].reason, 'Duplicate record in batch should be blocked');
        Assert.areEqual(0, Limits.getQueries(), 'Guard must not consume SOQL');
    }

    @IsTest
    static void resetExecutionCountsAllowsAgain() {
        check(buildRequest(GUARDED_FLOW, ACCOUNT_ID_1));
        UAF_FlowGuard.resetExecutionCounts();

        Assert.areEqual(0, UAF_FlowGuard.getExecutionCount(GUARDED_FLOW, ACCOUNT_ID_1), 'Counter should be reset');
        Assert.isTrue(check(buildRequest(GUARDED_FLOW, ACCOUNT_ID_1)).shouldRun, 'Execution allowed after reset');
    }

    // ------------------------------------------------------------------------------------------
    // UAF_FlowGuard - bypass
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void guardBlocksBypassedFlow() {
        UAF_BypassManager.bypassFlow(GUARDED_FLOW);

        UAF_FlowGuard.UAF_FlowGuardResult result = check(buildRequest(GUARDED_FLOW, ACCOUNT_ID_1));

        Assert.isFalse(result.shouldRun, 'Bypassed flow must not run');
        Assert.areEqual(UAF_FlowGuard.REASON_BYPASSED, result.reason, 'Reason should be BYPASSED_BY_MANAGER');
        Assert.areEqual(0, UAF_FlowGuard.getExecutionCount(GUARDED_FLOW, ACCOUNT_ID_1), 'Bypassed execution is not counted');

        UAF_BypassManager.clearBypassFlow(GUARDED_FLOW);
        Assert.isTrue(check(buildRequest(GUARDED_FLOW, ACCOUNT_ID_1)).shouldRun, 'Allowed again once bypass is cleared');
    }

    @IsTest
    static void guardBlocksBypassedObjectByName() {
        UAF_BypassManager.bypassObject('Account');
        UAF_FlowGuard.UAF_FlowGuardRequest request = buildRequest(GUARDED_FLOW, null);
        request.sObjectName = 'Account';

        UAF_FlowGuard.UAF_FlowGuardResult result = check(request);

        Assert.isFalse(result.shouldRun, 'Bypassed object must block the flow');
        Assert.areEqual(UAF_FlowGuard.REASON_BYPASSED, result.reason, 'Reason should be BYPASSED_BY_MANAGER');
    }

    @IsTest
    static void guardDerivesObjectFromRecordId() {
        UAF_BypassManager.bypassObject('Account');

        UAF_FlowGuard.UAF_FlowGuardResult result = check(buildRequest(GUARDED_FLOW, ACCOUNT_ID_1));

        Assert.isFalse(result.shouldRun, 'Object bypass should apply using the recordId SObjectType');
        Assert.areEqual(UAF_FlowGuard.REASON_BYPASSED, result.reason, 'Reason should be BYPASSED_BY_MANAGER');
    }

    // ------------------------------------------------------------------------------------------
    // UAF_FlowGuard - invalid input
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void guardRejectsInvalidRequests() {
        UAF_FlowGuard.UAF_FlowGuardRequest zeroLimit = buildRequest(GUARDED_FLOW, ACCOUNT_ID_1);
        zeroLimit.maxExecutionsPerRecord = 0;

        List<UAF_FlowGuard.UAF_FlowGuardResult> results = UAF_FlowGuard.checkExecution(
            new List<UAF_FlowGuard.UAF_FlowGuardRequest>{ null, buildRequest(null, ACCOUNT_ID_1), buildRequest('  ', null), zeroLimit }
        );

        Assert.areEqual(4, results.size(), 'One result per request, including invalid ones');
        for (UAF_FlowGuard.UAF_FlowGuardResult result : results) {
            Assert.isFalse(result.shouldRun, 'Invalid requests must not run');
            Assert.areEqual(UAF_FlowGuard.REASON_INVALID_REQUEST, result.reason, 'Reason should be INVALID_REQUEST');
        }
        Assert.isTrue(UAF_FlowGuard.checkExecution(null).isEmpty(), 'Null request list returns an empty list');
        Assert.areEqual(0, UAF_FlowGuard.getExecutionCount(null, ACCOUNT_ID_1), 'Blank flow name has no counter');
    }

    @IsTest
    static void guardResultDefaultConstructor() {
        UAF_FlowGuard.UAF_FlowGuardResult result = new UAF_FlowGuard.UAF_FlowGuardResult();
        Assert.isNull(result.shouldRun, 'Default constructor leaves fields empty (required by Flow)');
    }

    @IsTest
    static void guardBlocksEverythingForBypassAllUser() {
        // Real Permission Set assignment is covered by UAF_BypassManager_Test; here it is simulated.
        UAF_BypassManager.bypassAllOverride = true;
        List<UAF_FlowGuard.UAF_FlowGuardRequest> requests = new List<UAF_FlowGuard.UAF_FlowGuardRequest>();
        for (Integer i = 1; i <= 200; i++) {
            requests.add(buildRequest(GUARDED_FLOW, UAF_TestDataFactory.fakeId(Account.SObjectType, i)));
        }

        Test.startTest();
        List<UAF_FlowGuard.UAF_FlowGuardResult> results = UAF_FlowGuard.checkExecution(requests);
        Test.stopTest();

        for (UAF_FlowGuard.UAF_FlowGuardResult result : results) {
            Assert.isFalse(result.shouldRun, 'No flow may run for a user with UAF_Bypass_All');
            Assert.areEqual(UAF_FlowGuard.REASON_BYPASSED, result.reason, 'Reason should be BYPASSED_BY_MANAGER');
        }
        Assert.areEqual(0, UAF_FlowGuard.getExecutionCount(GUARDED_FLOW, requests[0].recordId), 'Bypassed executions are not counted');
    }

    // ------------------------------------------------------------------------------------------
    // UAF_FlowInvoker
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void invokerRunsFlowAndReturnsOutputs() {
        Test.startTest();
        UAF_FlowExecutionResult result = UAF_FlowInvoker.invokeFlow(ECHO_FLOW, new Map<String, Object>{ 'inputText' => 'hello UAF' });
        Integer queriesAfterFirstCall = Limits.getQueries();
        UAF_FlowExecutionResult second = UAF_FlowInvoker.invokeFlow(ECHO_FLOW, new Map<String, Object>{ 'inputText' => 'again' });
        Integer queriesAfterSecondCall = Limits.getQueries();
        Test.stopTest();

        Assert.isTrue(result.isSuccess, 'Flow should succeed: ' + result.errorMessage);
        Assert.isFalse(result.isBypassed, 'Flow was not bypassed');
        Assert.isNull(result.errorMessage, 'No error expected');
        Assert.isNull(result.error, 'No exception expected');
        Assert.areEqual(ECHO_FLOW, result.flowApiName, 'Flow name should be reported');
        Assert.areEqual('hello UAF', result.outputVariables.get('outputText'), 'Output should echo the input');
        Assert.isFalse(result.outputVariables.containsKey('inputText'), 'Only output variables are returned');

        Assert.areEqual('again', second.outputVariables.get('outputText'), 'Second call returns its own output');
        Assert.areEqual(queriesAfterFirstCall, queriesAfterSecondCall, 'Output variable metadata must be cached');
    }

    @IsTest
    static void invokerAcceptsNullInputs() {
        UAF_FlowExecutionResult result = UAF_FlowInvoker.invokeFlow(ECHO_FLOW, null);

        Assert.isTrue(result.isSuccess, 'Null inputs should be treated as empty: ' + result.errorMessage);
        Assert.isTrue(result.outputVariables.containsKey('outputText'), 'Output variable should be present');
        Assert.isNull(result.outputVariables.get('outputText'), 'Output should be null when no input given');
    }

    @IsTest
    static void invokerSkipsBypassedFlow() {
        UAF_BypassManager.bypassFlow(ECHO_FLOW);

        UAF_FlowExecutionResult result = UAF_FlowInvoker.invokeFlow(ECHO_FLOW, new Map<String, Object>{ 'shouldFail' => true });

        Assert.isTrue(result.isSuccess, 'A bypass is not an error');
        Assert.isTrue(result.isBypassed, 'Result should be flagged as bypassed');
        Assert.isTrue(result.outputVariables.isEmpty(), 'No outputs when the flow does not run');
        Assert.isNull(result.errorMessage, 'No error for a bypass');
    }

    @IsTest
    static void invokerSkipsFlowWhenBypassAllIsSimulated() {
        UAF_BypassManager.bypassAllOverride = true;

        UAF_FlowExecutionResult result = UAF_FlowInvoker.invokeFlow(ECHO_FLOW, new Map<String, Object>{ 'shouldFail' => true });

        Assert.isTrue(result.isSuccess, 'A user-level bypass is not an error');
        Assert.isTrue(result.isBypassed, 'Flow must be skipped for a user with UAF_Bypass_All');
        Assert.areEqual(0, Limits.getQueries(), 'Bypassed invocation must not query flow metadata');
    }

    @IsTest
    static void invokerReportsMissingFlow() {
        UAF_FlowExecutionResult result = UAF_FlowInvoker.invokeFlow('UAF_Flow_That_Does_Not_Exist', new Map<String, Object>());

        Assert.isFalse(result.isSuccess, 'Missing flow must fail');
        Assert.isFalse(result.isBypassed, 'Missing flow is not a bypass');
        Assert.isTrue(result.errorMessage.contains('was not found'), 'Descriptive message expected: ' + result.errorMessage);
        Assert.isInstanceOfType(result.error.getCause(), TypeException.class, 'Original TypeException should be the cause');
    }

    @IsTest
    static void invokerReportsFlowFault() {
        Test.startTest();
        UAF_FlowExecutionResult result = UAF_FlowInvoker.invokeFlow(ECHO_FLOW, new Map<String, Object>{ 'shouldFail' => true });
        Test.stopTest();

        Assert.isFalse(result.isSuccess, 'Faulting flow must fail');
        Assert.isTrue(result.errorMessage.contains(ECHO_FLOW), 'Message should name the flow: ' + result.errorMessage);
        Assert.isInstanceOfType(result.error.getCause(), FlowException.class, 'Original FlowException should be the cause');
        Assert.isTrue(result.outputVariables.isEmpty(), 'No outputs on failure');
    }

    @IsTest
    static void invokerRejectsBlankName() {
        for (String name : new List<String>{ null, '', '   ' }) {
            UAF_FlowExecutionResult result = UAF_FlowInvoker.invokeFlow(name, null);
            Assert.isFalse(result.isSuccess, 'Blank flow name must fail');
            Assert.isTrue(result.errorMessage.contains('flowApiName is required'), 'Unexpected message: ' + result.errorMessage);
        }
    }

    @IsTest
    static void invokeFlowOrThrowSucceedsAndThrows() {
        UAF_FlowExecutionResult ok = UAF_FlowInvoker.invokeFlowOrThrow(ECHO_FLOW, new Map<String, Object>{ 'inputText' => 'x' });
        Assert.areEqual('x', ok.outputVariables.get('outputText'), 'Success path returns outputs');

        try {
            UAF_FlowInvoker.invokeFlowOrThrow(ECHO_FLOW, new Map<String, Object>{ 'shouldFail' => true });
            Assert.fail('Expected UAF_TriggerException');
        } catch (UAF_TriggerException e) {
            Assert.isTrue(e.getMessage().contains('failed'), 'Descriptive message expected: ' + e.getMessage());
            Assert.isInstanceOfType(e.getCause(), FlowException.class, 'Cause should be the FlowException');
        }
    }
}
