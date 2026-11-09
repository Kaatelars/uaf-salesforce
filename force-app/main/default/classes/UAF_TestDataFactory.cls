/**
 * @description Shared test utilities for UAF test classes:
 *              <ul>
 *                <li>Fake record Ids built from the SObject key prefix (no hardcoded Ids).</li>
 *                <li>Test users with optional Permission Sets (e.g. UAF_Bypass_Automations), meant to
 *                    be created ONCE per test class in {@code @TestSetup} and fetched with
 *                    {@link getUser}. Creating users in every test method serializes parallel
 *                    test runs on Setup-object locks and slows the suite down dramatically.</li>
 *              </ul>
 *              Setup DML runs inside System.runAs(current user) so callers can mix it with
 *              non-setup DML (e.g. Account) without MIXED_DML_OPERATION errors.
 * @group UAF Core Tests
 */
@IsTest
public inherited sharing class UAF_TestDataFactory {

    /** @description Permission Set granting the UAF_Bypass_All Custom Permission. */
    public static final String BYPASS_PERMISSION_SET = 'UAF_Bypass_Automations';

    private static final String USERNAME_PREFIX = 'uaf.test.';
    private static final String USERNAME_DOMAIN = '@example.com';

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

    /**
     * @description Creates a user cloned from the running user's profile (same object access),
     *              optionally assigning Permission Sets. Call it from {@code @TestSetup}.
     * @param tag                Unique tag used to fetch the user later with {@link getUser}.
     * @param permissionSetNames Permission Set API names to assign (may be empty).
     * @return Inserted user.
     */
    public static User createUser(String tag, List<String> permissionSetNames) {
        String unique = tag + '.' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User user = new User(
            ProfileId = UserInfo.getProfileId(),
            LastName = 'UAF ' + tag,
            Username = USERNAME_PREFIX + unique + USERNAME_DOMAIN,
            Email = USERNAME_PREFIX + unique + USERNAME_DOMAIN,
            Alias = ('u' + tag).left(8),
            TimeZoneSidKey = 'America/Mexico_City',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert user;
            if (!permissionSetNames.isEmpty()) {
                List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
                for (PermissionSet permissionSet : [
                    SELECT Id FROM PermissionSet WHERE Name IN :permissionSetNames WITH SYSTEM_MODE
                ]) {
                    assignments.add(new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetId = permissionSet.Id));
                }
                insert assignments;
            }
        }
        return user;
    }

    /**
     * @description Returns a user previously created with {@link createUser} (e.g. in @TestSetup).
     * @param tag Tag passed to createUser.
     * @return The user.
     */
    public static User getUser(String tag) {
        String pattern = USERNAME_PREFIX + tag + '.%';
        return [SELECT Id, Username FROM User WHERE Username LIKE :pattern WITH SYSTEM_MODE LIMIT 1];
    }
}
