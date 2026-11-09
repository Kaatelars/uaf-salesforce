/**
 * @description Unit tests for UAF_BypassManager: explicit in-memory bypasses and the user-level
 *              bypass granted by the Custom Permission UAF_Bypass_All (Permission Set
 *              UAF_Bypass_Automations). Test users are created once in @TestSetup.
 * @group UAF Core Tests
 */
@IsTest
private inherited sharing class UAF_BypassManager_Test {

    private static final String BYPASS_USER = 'bypassmgr.bypass';
    private static final String REGULAR_USER = 'bypassmgr.regular';

    @TestSetup
    static void createUsers() {
        UAF_TestDataFactory.createUser(BYPASS_USER, new List<String>{ UAF_TestDataFactory.BYPASS_PERMISSION_SET });
        UAF_TestDataFactory.createUser(REGULAR_USER, new List<String>());
    }

    // ------------------------------------------------------------------------------------------
    // Explicit in-memory bypass
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void bypassObjectLifecycle() {
        Assert.isFalse(UAF_BypassManager.isObjectBypassed('Account'), 'No bypass by default');

        UAF_BypassManager.bypassObject('Account');
        Assert.isTrue(UAF_BypassManager.isObjectBypassed('Account'), 'Account should be bypassed');
        Assert.isTrue(UAF_BypassManager.isObjectBypassed(' account '), 'Lookup should be case/space-insensitive');
        Assert.isFalse(UAF_BypassManager.isObjectBypassed('Contact'), 'Other objects must not be bypassed');

        UAF_BypassManager.clearBypassObject('ACCOUNT');
        Assert.isFalse(UAF_BypassManager.isObjectBypassed('Account'), 'Bypass should be cleared');
    }

    @IsTest
    static void bypassFlowLifecycle() {
        Assert.isFalse(UAF_BypassManager.isFlowBypassed('My_Flow'), 'No bypass by default');

        UAF_BypassManager.bypassFlow('My_Flow');
        Assert.isTrue(UAF_BypassManager.isFlowBypassed('my_flow'), 'Flow should be bypassed (case-insensitive)');
        Assert.isFalse(UAF_BypassManager.isObjectBypassed('My_Flow'), 'Flow and object registries are independent');

        UAF_BypassManager.clearBypassFlow('My_Flow');
        Assert.isFalse(UAF_BypassManager.isFlowBypassed('My_Flow'), 'Flow bypass should be cleared');
    }

    @IsTest
    static void clearAllBypassesRemovesEverything() {
        UAF_BypassManager.bypassObject('Account');
        UAF_BypassManager.bypassObject('Invoice__c');
        UAF_BypassManager.bypassFlow('My_Flow');

        UAF_BypassManager.clearAllBypasses();

        Assert.isFalse(UAF_BypassManager.isObjectBypassed('Account'), 'Account bypass should be cleared');
        Assert.isFalse(UAF_BypassManager.isObjectBypassed('Invoice__c'), 'Invoice__c bypass should be cleared');
        Assert.isFalse(UAF_BypassManager.isFlowBypassed('My_Flow'), 'Flow bypass should be cleared');
    }

    @IsTest
    static void blankNamesAreIgnored() {
        UAF_BypassManager.bypassObject(null);
        UAF_BypassManager.bypassObject('  ');
        UAF_BypassManager.bypassFlow('');
        UAF_BypassManager.clearBypassObject(null);
        UAF_BypassManager.clearBypassFlow(null);

        Assert.isFalse(UAF_BypassManager.isObjectBypassed(null), 'Null object name is never bypassed');
        Assert.isFalse(UAF_BypassManager.isObjectBypassed(' '), 'Blank object name is never bypassed');
        Assert.isFalse(UAF_BypassManager.isFlowBypassed(null), 'Null flow name is never bypassed');
    }

    // ------------------------------------------------------------------------------------------
    // User-level bypass (Custom Permission UAF_Bypass_All)
    // ------------------------------------------------------------------------------------------

    @IsTest
    static void simulatedBypassAllBypassesEverything() {
        UAF_BypassManager.bypassAllOverride = true;

        Assert.isTrue(UAF_BypassManager.isBypassAllActive(), 'Simulated permission should be active');
        Assert.isTrue(UAF_BypassManager.isObjectBypassed('Account'), 'Any object is bypassed');
        Assert.isTrue(UAF_BypassManager.isObjectBypassed('Invoice__c'), 'Any custom object is bypassed');
        Assert.isTrue(UAF_BypassManager.isFlowBypassed('Any_Flow'), 'Any flow is bypassed');
        Assert.isFalse(UAF_BypassManager.isObjectBypassed(' '), 'Blank names are never bypassed');

        UAF_BypassManager.clearAllBypasses();
        Assert.isTrue(UAF_BypassManager.isObjectBypassed('Account'), 'clearAllBypasses must not remove the user-level bypass');

        UAF_BypassManager.bypassAllOverride = false;
        Assert.isFalse(UAF_BypassManager.isObjectBypassed('Account'), 'Without the permission nothing is bypassed');
    }

    @IsTest
    static void explicitBypassIsEvaluatedBeforePermission() {
        UAF_BypassManager.bypassAllOverride = false;
        UAF_BypassManager.bypassObject('Account');

        Assert.isTrue(UAF_BypassManager.isObjectBypassed('Account'), 'Explicit in-memory bypass applies without the permission');
        Assert.isFalse(UAF_BypassManager.isObjectBypassed('Contact'), 'Other objects are not bypassed without the permission');
    }

    @IsTest
    static void assignedPermissionSetBypassesForThatUserOnly() {
        User bypassUser = UAF_TestDataFactory.getUser(BYPASS_USER);
        User regularUser = UAF_TestDataFactory.getUser(REGULAR_USER);

        Test.startTest();
        System.runAs(bypassUser) {
            Assert.isTrue(UAF_BypassManager.isBypassAllActive(), 'UAF_Bypass_Automations grants UAF_Bypass_All');
            Assert.isTrue(UAF_BypassManager.isObjectBypassed('Account'), 'Objects are bypassed for the bypass user');
            Assert.isTrue(UAF_BypassManager.isFlowBypassed('Any_Flow'), 'Flows are bypassed for the bypass user');
        }
        System.runAs(regularUser) {
            Assert.isFalse(UAF_BypassManager.isBypassAllActive(), 'Cached result must be per user');
            Assert.isFalse(UAF_BypassManager.isObjectBypassed('Account'), 'Regular user is not bypassed');
            Assert.isFalse(UAF_BypassManager.isFlowBypassed('Any_Flow'), 'Regular user is not bypassed');
        }
        Test.stopTest();
    }
}
