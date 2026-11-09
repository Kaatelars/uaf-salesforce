/**
 * @description Contract for per-SObject trigger dispatchers. {@link UAF_TriggerFactory}
 *              invokes, in order: bulkBefore/bulkAfter, the event-specific method, andFinally.
 *              Extend {@link UAF_TriggerDispatcherBase} instead of implementing this directly.
 * @group UAF Core
 */
public interface UAF_ITriggerDispatcher {

    /** @description Runs once before any before-event method (bulk caching, queries). */
    void bulkBefore(UAF_TriggerParameters tp);

    /** @description Runs once before any after-event method (bulk caching, queries). */
    void bulkAfter(UAF_TriggerParameters tp);

    void beforeInsert(UAF_TriggerParameters tp);
    void afterInsert(UAF_TriggerParameters tp);
    void beforeUpdate(UAF_TriggerParameters tp);
    void afterUpdate(UAF_TriggerParameters tp);
    void beforeDelete(UAF_TriggerParameters tp);
    void afterDelete(UAF_TriggerParameters tp);
    void afterUndelete(UAF_TriggerParameters tp);

    /** @description Runs once at the end of every dispatch (e.g. commit pending DML). */
    void andFinally(UAF_TriggerParameters tp);
}
