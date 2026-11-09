/**
 * @description Invocable gatekeeper for Flows. Place it as the first Action of a
 *              Record-Triggered (after-save) or Autolaunched Flow and add a Decision on
 *              {@code shouldRun}. It blocks the Flow when:
 *              <ul>
 *                <li>the Flow or its SObject is bypassed in {@link UAF_BypassManager}
 *                    ({@code BYPASSED_BY_MANAGER});</li>
 *                <li>the same Flow already ran {@code maxExecutionsPerRecord} times for the same
 *                    record in this transaction ({@code MAX_RECURSION_REACHED});</li>
 *                <li>the request is invalid ({@code INVALID_REQUEST}).</li>
 *              </ul>
 *              Execution counters are transaction-scoped (static) and keyed by Flow + recordId.
 *              Without a recordId only the bypass check applies, so bulk calls are never
 *              throttled by accident. An allowed request increments its counter; blocked
 *              requests do not.
 *              Sharing: {@code inherited sharing} so framework code always runs in the sharing
 *              context of its caller (trigger, handler or Flow) and never widens it.
 * @group UAF Flow
 */
public inherited sharing class UAF_FlowGuard {

    public static final String REASON_ALLOWED = 'ALLOWED';
    public static final String REASON_BYPASSED = 'BYPASSED_BY_MANAGER';
    public static final String REASON_MAX_RECURSION = 'MAX_RECURSION_REACHED';
    public static final String REASON_INVALID_REQUEST = 'INVALID_REQUEST';

    /** @description Executions allowed per Flow + record when the request does not specify a limit. */
    public static final Integer DEFAULT_MAX_EXECUTIONS_PER_RECORD = 1;

    /** "flowapiname:recordId" -> number of allowed executions in this transaction. */
    private static final Map<String, Integer> EXECUTION_COUNTS = new Map<String, Integer>();

    /**
     * @description Invocable input.
     */
    public class UAF_FlowGuardRequest {
        @InvocableVariable(label='Flow API Name' description='API name of the calling Flow.' required=true)
        public String flowApiName;

        @InvocableVariable(label='SObject API Name' description='Optional. Checked against object bypasses. Derived from Record Id when empty.' required=false)
        public String sObjectName;

        @InvocableVariable(label='Record Id' description='Optional. Enables the per-record recursion limit.' required=false)
        public Id recordId;

        @InvocableVariable(label='Max Executions Per Record' description='Optional. Executions allowed per record and transaction. Defaults to 1.' required=false)
        public Integer maxExecutionsPerRecord;
    }

    /**
     * @description Invocable output.
     */
    public class UAF_FlowGuardResult {
        @InvocableVariable(label='Should Run' description='True if the Flow may continue.')
        public Boolean shouldRun;

        @InvocableVariable(label='Reason' description='ALLOWED, BYPASSED_BY_MANAGER, MAX_RECURSION_REACHED or INVALID_REQUEST.')
        public String reason;

        @InvocableVariable(label='Execution Count' description='Executions of this Flow for this record in the transaction, including the current one if allowed.')
        public Integer executionCount;

    }

    /**
     * @description Bulk entry point for Flow. Returns one result per request, in the same order.
     * @param requests Guard requests (one per Flow interview).
     * @return Results aligned with {@code requests}; empty list if {@code requests} is null.
     */
    @InvocableMethod(
        label='UAF Flow Guard'
        description='Checks UAF bypasses and per-record recursion limits. Returns shouldRun and reason.'
        category='UAF'
    )
    public static List<UAF_FlowGuardResult> checkExecution(List<UAF_FlowGuardRequest> requests) {
        List<UAF_FlowGuardResult> results = new List<UAF_FlowGuardResult>();
        if (requests == null) {
            return results;
        }
        for (UAF_FlowGuardRequest request : requests) {
            results.add(evaluate(request));
        }
        return results;
    }

    /**
     * @description Evaluates a single request. Also usable from Apex.
     * @param request Guard request.
     * @return Guard result.
     */
    public static UAF_FlowGuardResult evaluate(UAF_FlowGuardRequest request) {
        if (!isValid(request)) {
            return toResult(REASON_INVALID_REQUEST, 0);
        }

        String key = buildKey(request.flowApiName, request.recordId);
        Integer currentCount = countFor(key);

        if (isBypassed(request)) {
            return toResult(REASON_BYPASSED, currentCount);
        }
        if (key == null) {
            // No record to track: only the bypass check applies.
            return toResult(REASON_ALLOWED, 0);
        }
        if (currentCount >= maxExecutionsFor(request)) {
            return toResult(REASON_MAX_RECURSION, currentCount);
        }

        EXECUTION_COUNTS.put(key, currentCount + 1);
        return toResult(REASON_ALLOWED, currentCount + 1);
    }

    /**
     * @description Allowed executions recorded for a Flow + record in this transaction.
     * @param flowApiName Flow API name.
     * @param recordId    Record Id.
     * @return Execution count (0 if never executed or arguments are blank).
     */
    public static Integer getExecutionCount(String flowApiName, Id recordId) {
        return countFor(buildKey(flowApiName, recordId));
    }

    /**
     * @description Clears every execution counter (e.g. between logical units of work in batch jobs).
     */
    public static void resetExecutionCounts() {
        EXECUTION_COUNTS.clear();
    }

    private static Boolean isValid(UAF_FlowGuardRequest request) {
        return request != null && String.isNotBlank(request.flowApiName) && maxExecutionsFor(request) >= 1;
    }

    private static Integer maxExecutionsFor(UAF_FlowGuardRequest request) {
        return request.maxExecutionsPerRecord ?? DEFAULT_MAX_EXECUTIONS_PER_RECORD;
    }

    private static Boolean isBypassed(UAF_FlowGuardRequest request) {
        return UAF_BypassManager.isFlowBypassed(request.flowApiName)
            || UAF_BypassManager.isObjectBypassed(resolveSObjectName(request));
    }

    private static String resolveSObjectName(UAF_FlowGuardRequest request) {
        if (String.isNotBlank(request.sObjectName)) {
            return request.sObjectName;
        }
        return request.recordId == null ? null : String.valueOf(request.recordId.getSObjectType());
    }

    private static Integer countFor(String key) {
        return key == null ? 0 : (EXECUTION_COUNTS.get(key) ?? 0);
    }

    private static UAF_FlowGuardResult toResult(String reason, Integer executionCount) {
        UAF_FlowGuardResult result = new UAF_FlowGuardResult();
        result.shouldRun = reason == REASON_ALLOWED;
        result.reason = reason;
        result.executionCount = executionCount;
        return result;
    }

    private static String buildKey(String flowApiName, Id recordId) {
        if (String.isBlank(flowApiName) || recordId == null) {
            return null;
        }
        return flowApiName.trim().toLowerCase() + ':' + recordId;
    }
}
