/**
 * @description Shared test utilities for UAF test classes. Builds fake record Ids from the
 *              SObject key prefix, so tests never hardcode Ids.
 * @group UAF Core Tests
 */
@IsTest
public inherited sharing class UAF_TestDataFactory {

    /**
     * @description Builds a syntactically valid, non-persisted Id for an SObject type.
     * @param sObjectType Target SObject type.
     * @param index       Sequence number (1..999999999999).
     * @return Fake Id.
     */
    public static Id fakeId(Schema.SObjectType sObjectType, Integer index) {
        String keyPrefix = sObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix();
        return Id.valueOf(keyPrefix + String.valueOf(index).leftPad(12, '0'));
    }
}
