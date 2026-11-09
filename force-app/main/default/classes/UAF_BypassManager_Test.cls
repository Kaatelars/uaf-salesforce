/**
 * @description Unit tests for UAF_BypassManager in-memory bypasses (objects and Flows).
 * @group UAF Core Tests
 */
@IsTest
private inherited sharing class UAF_BypassManager_Test {

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
}
