/**
 * @description Outcome of a {@link UAF_FlowInvoker} call.
 *              <ul>
 *                <li>Success: {@code isSuccess = true}, {@code outputVariables} populated.</li>
 *                <li>Bypassed: {@code isSuccess = true}, {@code isBypassed = true}, Flow not run.</li>
 *                <li>Failure: {@code isSuccess = false}, {@code errorMessage} and {@code error} set.</li>
 *              </ul>
 *              Sharing: {@code inherited sharing} so framework code always runs in the sharing
 *              context of its caller (trigger, handler or Flow) and never widens it.
 * @group UAF Flow
 */
public inherited sharing class UAF_FlowExecutionResult {

    public String flowApiName { get; private set; }
    public Boolean isSuccess { get; private set; }
    public Boolean isBypassed { get; private set; }
    /** @description Output variable name -> value. Never null. */
    public Map<String, Object> outputVariables { get; private set; }
    public String errorMessage { get; private set; }
    /** @description Wrapped failure (original exception available via getCause()); null unless failed. */
    public UAF_TriggerException error { get; private set; }

    private UAF_FlowExecutionResult(String flowApiName) {
        this.flowApiName = flowApiName;
        this.isSuccess = true;
        this.isBypassed = false;
        this.outputVariables = new Map<String, Object>();
    }

    /**
     * @description Builds a successful result.
     * @param flowApiName     Flow API name.
     * @param outputVariables Output variable values.
     * @return Result.
     */
    public static UAF_FlowExecutionResult success(String flowApiName, Map<String, Object> outputVariables) {
        UAF_FlowExecutionResult result = new UAF_FlowExecutionResult(flowApiName);
        result.outputVariables = outputVariables ?? new Map<String, Object>();
        return result;
    }

    /**
     * @description Builds a result for a Flow skipped by {@link UAF_BypassManager}.
     * @param flowApiName Flow API name.
     * @return Result.
     */
    public static UAF_FlowExecutionResult bypassed(String flowApiName) {
        UAF_FlowExecutionResult result = new UAF_FlowExecutionResult(flowApiName);
        result.isBypassed = true;
        return result;
    }

    /**
     * @description Builds a failed result.
     * @param flowApiName Flow API name.
     * @param error       Descriptive framework exception.
     * @return Result.
     */
    public static UAF_FlowExecutionResult failure(String flowApiName, UAF_TriggerException error) {
        UAF_FlowExecutionResult result = new UAF_FlowExecutionResult(flowApiName);
        result.isSuccess = false;
        result.error = error;
        result.errorMessage = error?.getMessage();
        return result;
    }
}
