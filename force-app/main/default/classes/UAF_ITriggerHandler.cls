/**
 * @description Contract for concrete trigger handlers. The dispatcher calls
 *              {@link mainEntry} on the first entry into an event and
 *              {@link inProgressEntry} when the same SObject/event re-enters while the
 *              first execution is still running (e.g. a handler's DML re-fires the trigger).
 * @group UAF Core
 */
public interface UAF_ITriggerHandler {

    /**
     * @description Main business logic for the event.
     * @param tp Trigger parameters.
     */
    void mainEntry(UAF_TriggerParameters tp);

    /**
     * @description Logic to run on re-entry. Leave empty to skip recursive processing.
     * @param tp Trigger parameters of the re-entrant execution.
     */
    void inProgressEntry(UAF_TriggerParameters tp);
}
