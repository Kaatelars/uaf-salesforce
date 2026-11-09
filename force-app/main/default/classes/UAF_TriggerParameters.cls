/**
 * @description Immutable snapshot of the Apex trigger context. Decouples dispatchers and
 *              handlers from the static {@code Trigger} variables so they can be unit tested
 *              without real DML, and resolves the concrete {@link TriggerEvent}.
 *
 *              Inside a trigger use {@link fromTriggerContext}. To simulate a context (tests,
 *              advanced callers) use the {@link Builder}:
 *              <pre>
 *              UAF_TriggerParameters tp = new UAF_TriggerParameters.Builder()
 *                  .operation(System.TriggerOperation.AFTER_UPDATE)
 *                  .oldRecords(oldList, oldMap)
 *                  .newRecords(newList, newMap)
 *                  .build();
 *              </pre>
 *
 *              Sharing: {@code inherited sharing} because framework code must run in the sharing
 *              context of the caller (trigger, handler or Flow) and never widen it.
 * @group UAF Core
 */
public inherited sharing class UAF_TriggerParameters {

    /**
     * @description Every trigger event supported by Apex.
     */
    public enum TriggerEvent {
        BEFORE_INSERT,
        AFTER_INSERT,
        BEFORE_UPDATE,
        AFTER_UPDATE,
        BEFORE_DELETE,
        AFTER_DELETE,
        AFTER_UNDELETE
    }

    private static final Map<System.TriggerOperation, UAF_TriggerParameters.TriggerEvent> EVENT_BY_OPERATION =
        new Map<System.TriggerOperation, UAF_TriggerParameters.TriggerEvent>{
            System.TriggerOperation.BEFORE_INSERT => UAF_TriggerParameters.TriggerEvent.BEFORE_INSERT,
            System.TriggerOperation.AFTER_INSERT => UAF_TriggerParameters.TriggerEvent.AFTER_INSERT,
            System.TriggerOperation.BEFORE_UPDATE => UAF_TriggerParameters.TriggerEvent.BEFORE_UPDATE,
            System.TriggerOperation.AFTER_UPDATE => UAF_TriggerParameters.TriggerEvent.AFTER_UPDATE,
            System.TriggerOperation.BEFORE_DELETE => UAF_TriggerParameters.TriggerEvent.BEFORE_DELETE,
            System.TriggerOperation.AFTER_DELETE => UAF_TriggerParameters.TriggerEvent.AFTER_DELETE,
            System.TriggerOperation.AFTER_UNDELETE => UAF_TriggerParameters.TriggerEvent.AFTER_UNDELETE
        };

    public List<SObject> oldList { get; private set; }
    public List<SObject> newList { get; private set; }
    public Map<Id, SObject> oldMap { get; private set; }
    public Map<Id, SObject> newMap { get; private set; }

    public Boolean isBefore { get; private set; }
    public Boolean isAfter { get; private set; }
    public Boolean isInsert { get; private set; }
    public Boolean isUpdate { get; private set; }
    public Boolean isDelete { get; private set; }
    public Boolean isUndelete { get; private set; }
    /** @description True only when built from a real trigger context. */
    public Boolean isExecuting { get; private set; }

    /** @description Resolved event; {@code null} when there is no trigger operation (e.g. outside a trigger). */
    public UAF_TriggerParameters.TriggerEvent triggerEvent { get; private set; }

    /** @description SObjectType of the records, derived from newList (or oldList on delete). */
    public Schema.SObjectType sObjectType { get; private set; }

    /** @description API name of {@link sObjectType} (e.g. {@code Account}, {@code Invoice__c}). */
    public String sObjectName { get; private set; }

    private UAF_TriggerParameters(Builder builder) {
        this.oldList = builder.oldList;
        this.newList = builder.newList;
        this.oldMap = builder.oldMap;
        this.newMap = builder.newMap;
        this.isExecuting = builder.fromTrigger;
        this.triggerEvent = builder.operation == null ? null : EVENT_BY_OPERATION.get(builder.operation);

        String eventName = this.triggerEvent?.name() ?? '';
        this.isBefore = eventName.startsWith('BEFORE_');
        this.isAfter = eventName.startsWith('AFTER_');
        this.isInsert = eventName.endsWith('_INSERT');
        this.isUpdate = eventName.endsWith('_UPDATE');
        this.isDelete = eventName.endsWith('_DELETE');
        this.isUndelete = eventName.endsWith('_UNDELETE');

        List<SObject> source = newList ?? oldList;
        this.sObjectType = source?.getSObjectType();
        this.sObjectName = this.sObjectType == null ? null : String.valueOf(this.sObjectType);
    }

    /**
     * @description Captures the current {@code Trigger} context variables.
     *              Outside a trigger every list/map is null, every flag is false and the event is null.
     * @return A new UAF_TriggerParameters instance.
     */
    public static UAF_TriggerParameters fromTriggerContext() {
        Builder builder = new Builder()
            .operation(Trigger.operationType)
            .oldRecords(Trigger.old, Trigger.oldMap)
            .newRecords(Trigger.new, Trigger.newMap);
        builder.fromTrigger = Trigger.isExecuting == true;
        return builder.build();
    }

    /**
     * @description Fluent builder used to simulate a trigger context.
     */
    public inherited sharing class Builder {
        private System.TriggerOperation operation;
        private List<SObject> oldList;
        private List<SObject> newList;
        private Map<Id, SObject> oldMap;
        private Map<Id, SObject> newMap;
        private Boolean fromTrigger = false;

        /**
         * @description Sets the trigger operation (drives the event and every isXxx flag).
         * @param operation Trigger operation, e.g. {@code System.TriggerOperation.AFTER_UPDATE}.
         * @return This builder.
         */
        public Builder operation(System.TriggerOperation operation) {
            this.operation = operation;
            return this;
        }

        /**
         * @description Sets Trigger.old / Trigger.oldMap.
         * @param records   Old records (aligned with the new records).
         * @param recordMap Old records by Id.
         * @return This builder.
         */
        public Builder oldRecords(List<SObject> records, Map<Id, SObject> recordMap) {
            this.oldList = records;
            this.oldMap = recordMap;
            return this;
        }

        /**
         * @description Sets Trigger.new / Trigger.newMap.
         * @param records   New records.
         * @param recordMap New records by Id (null in before insert).
         * @return This builder.
         */
        public Builder newRecords(List<SObject> records, Map<Id, SObject> recordMap) {
            this.newList = records;
            this.newMap = recordMap;
            return this;
        }

        /**
         * @description Builds the immutable parameters.
         * @return A new UAF_TriggerParameters instance.
         */
        public UAF_TriggerParameters build() {
            return new UAF_TriggerParameters(this);
        }
    }
}
