/**
 * @description Base class for SObject dispatchers. Provides no-op defaults for every
 *              {@link UAF_ITriggerDispatcher} method (override only what you need) and
 *              re-entrancy control through {@link execute}.
 *
 *              Re-entrancy is tracked per SObject + TriggerEvent for the whole transaction:
 *              if a handler's work re-fires the same event on the same SObject while the first
 *              execution is still running, the handler's {@code inProgressEntry} is called
 *              instead of {@code mainEntry}, preventing infinite loops.
 *
 *              Example:
 *              <pre>
 *              public class AccountTriggerDispatcher extends UAF_TriggerDispatcherBase {
 *                  public override void afterUpdate(UAF_TriggerParameters tp) {
 *                      execute(new AccountAfterUpdateHandler(), tp, UAF_TriggerParameters.TriggerEvent.AFTER_UPDATE);
 *                  }
 *              }
 *              </pre>
 *              Sharing: {@code inherited sharing} so framework code always runs in the sharing
 *              context of its caller (trigger, handler or Flow) and never widens it.
 *
 *              PMD.EmptyStatementBlock is suppressed on purpose: the empty virtual methods are
 *              template-method hooks. Concrete dispatchers override only the events they need.
 * @group UAF Core
 */
@SuppressWarnings('PMD.EmptyStatementBlock')
public abstract inherited sharing class UAF_TriggerDispatcherBase implements UAF_ITriggerDispatcher {

    /** Keys ("SObjectName:event") of the executions currently running in this transaction. */
    private static final Set<String> EXECUTIONS_IN_PROGRESS = new Set<String>();

    public virtual void bulkBefore(UAF_TriggerParameters tp) {}
    public virtual void bulkAfter(UAF_TriggerParameters tp) {}
    public virtual void beforeInsert(UAF_TriggerParameters tp) {}
    public virtual void afterInsert(UAF_TriggerParameters tp) {}
    public virtual void beforeUpdate(UAF_TriggerParameters tp) {}
    public virtual void afterUpdate(UAF_TriggerParameters tp) {}
    public virtual void beforeDelete(UAF_TriggerParameters tp) {}
    public virtual void afterDelete(UAF_TriggerParameters tp) {}
    public virtual void afterUndelete(UAF_TriggerParameters tp) {}
    public virtual void andFinally(UAF_TriggerParameters tp) {}

    /**
     * @description Runs a handler with re-entrancy control. First entry calls
     *              {@code mainEntry}; nested entries for the same SObject/event call
     *              {@code inProgressEntry}. The in-progress flag is always released, even if
     *              the handler throws.
     * @param handler Handler to run.
     * @param tp      Trigger parameters.
     * @param event   Event being processed.
     * @throws UAF_TriggerException if any argument is null.
     */
    public void execute(
        UAF_ITriggerHandler handler,
        UAF_TriggerParameters tp,
        UAF_TriggerParameters.TriggerEvent event
    ) {
        if (handler == null || tp == null || event == null) {
            throw new UAF_TriggerException('UAF_TriggerDispatcherBase.execute: handler, tp and event are required.');
        }

        String key = buildKey(tp.sObjectName, event);
        if (EXECUTIONS_IN_PROGRESS.contains(key)) {
            handler.inProgressEntry(tp);
            return;
        }

        EXECUTIONS_IN_PROGRESS.add(key);
        try {
            handler.mainEntry(tp);
        } finally {
            EXECUTIONS_IN_PROGRESS.remove(key);
        }
    }

    /**
     * @description Whether an SObject/event execution is currently running.
     * @param sObjectName SObject API name.
     * @param event       Trigger event.
     * @return True if a {@code mainEntry} for that SObject/event is on the stack.
     */
    public static Boolean isInProgress(String sObjectName, UAF_TriggerParameters.TriggerEvent event) {
        return event != null && EXECUTIONS_IN_PROGRESS.contains(buildKey(sObjectName, event));
    }

    private static String buildKey(String sObjectName, UAF_TriggerParameters.TriggerEvent event) {
        return (sObjectName ?? 'UNKNOWN').toLowerCase() + ':' + event.name();
    }
}
