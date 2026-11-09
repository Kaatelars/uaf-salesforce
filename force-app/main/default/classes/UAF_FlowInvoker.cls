/**
 * @description Safe launcher for Autolaunched Flows from Apex (typically from trigger handlers).
 *              Honors {@link UAF_BypassManager} Flow bypasses, wraps platform errors into a
 *              descriptive {@link UAF_TriggerException}, and returns every output variable.
 *
 *              Output variables are discovered from {@code FlowDefinitionView}/{@code FlowVariableView}
 *              with TWO queries the first time a Flow runs in the transaction; the result is cached,
 *              so repeated calls do not consume extra SOQL.
 *              Still, prefer one call per batch passing collections over one call per record.
 *
 *              Transaction note: {@link invokeFlow} swallows the error, so any DML the Flow
 *              performed before failing is NOT rolled back. Use {@link invokeFlowOrThrow} when the
 *              Flow's work must be atomic with the trigger transaction.
 *
 *              Example:
 *              <pre>
 *              UAF_FlowExecutionResult result = UAF_FlowInvoker.invokeFlow(
 *                  'Account_Enrichment', new Map<String, Object>{ 'accounts' => tp.newList });
 *              if (!result.isSuccess) { ... result.errorMessage ... }
 *              </pre>
 *              Sharing: {@code inherited sharing} so framework code always runs in the sharing
 *              context of its caller (trigger, handler or Flow) and never widens it.
 * @group UAF Flow
 */
public inherited sharing class UAF_FlowInvoker {

    /** Lower-cased Flow API name -> output variable names of its active version. */
    private static final Map<String, Set<String>> OUTPUT_VARIABLE_CACHE = new Map<String, Set<String>>();

    /**
     * @description Runs an Autolaunched Flow unless it is bypassed. Never throws for Flow errors.
     * @param flowApiName    Flow API name.
     * @param inputVariables Input variable name -> value (null allowed).
     * @return Execution result (success, bypassed or failure).
     */
    public static UAF_FlowExecutionResult invokeFlow(String flowApiName, Map<String, Object> inputVariables) {
        if (String.isBlank(flowApiName)) {
            return UAF_FlowExecutionResult.failure(flowApiName, new UAF_TriggerException('UAF_FlowInvoker: flowApiName is required.'));
        }
        if (UAF_BypassManager.isFlowBypassed(flowApiName)) {
            return UAF_FlowExecutionResult.bypassed(flowApiName);
        }

        try {
            Flow.Interview interview = Flow.Interview.createInterview(flowApiName, inputVariables ?? new Map<String, Object>());
            interview.start();
            return UAF_FlowExecutionResult.success(flowApiName, readOutputVariables(interview, flowApiName));
        } catch (TypeException e) {
            // Flow.Interview.createInterview throws "Invalid type" when the Flow does not exist or has no active version.
            return UAF_FlowExecutionResult.failure(flowApiName, new UAF_TriggerException(
                'UAF_FlowInvoker: Flow "' + flowApiName + '" was not found or has no active version. ' + e.getMessage(), e));
        } catch (FlowException e) {
            return UAF_FlowExecutionResult.failure(flowApiName, new UAF_TriggerException(
                'UAF_FlowInvoker: Flow "' + flowApiName + '" failed: ' + e.getMessage().normalizeSpace(), e));
        }
    }

    /**
     * @description Same as {@link invokeFlow} but throws on failure, so the caller's transaction
     *              (e.g. the trigger) is rolled back.
     * @param flowApiName    Flow API name.
     * @param inputVariables Input variable name -> value (null allowed).
     * @return Execution result (success or bypassed).
     * @throws UAF_TriggerException if the Flow cannot be found or fails.
     */
    public static UAF_FlowExecutionResult invokeFlowOrThrow(String flowApiName, Map<String, Object> inputVariables) {
        UAF_FlowExecutionResult result = invokeFlow(flowApiName, inputVariables);
        if (!result.isSuccess) {
            throw result.error;
        }
        return result;
    }

    private static Map<String, Object> readOutputVariables(Flow.Interview interview, String flowApiName) {
        Map<String, Object> outputs = new Map<String, Object>();
        for (String variableName : getOutputVariableNames(flowApiName)) {
            outputs.put(variableName, interview.getVariableValue(variableName));
        }
        return outputs;
    }

    private static Set<String> getOutputVariableNames(String flowApiName) {
        String cacheKey = flowApiName.trim().toLowerCase();
        Set<String> names = OUTPUT_VARIABLE_CACHE.get(cacheKey);
        if (names == null) {
            names = new Set<String>();
            // System mode on purpose: Flow metadata must be readable regardless of the running user's setup permissions.
            // Two simple queries instead of one relationship query: the platform rejects
            // FlowVariableView -> FlowVersionView -> FlowDefinitionView filters as "query too complicated" in some contexts.
            List<FlowDefinitionView> definitions = [
                SELECT ActiveVersionId
                FROM FlowDefinitionView
                WHERE ApiName = :flowApiName.trim()
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!definitions.isEmpty() && definitions[0].ActiveVersionId != null) {
                for (FlowVariableView variable : [
                    SELECT ApiName
                    FROM FlowVariableView
                    WHERE FlowVersionViewId = :definitions[0].ActiveVersionId
                        AND IsOutput = true
                    WITH SYSTEM_MODE
                ]) {
                    names.add(variable.ApiName);
                }
            }
            OUTPUT_VARIABLE_CACHE.put(cacheKey, names);
        }
        return names;
    }
}
