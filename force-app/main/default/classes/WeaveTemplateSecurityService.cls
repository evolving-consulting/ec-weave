public with sharing class WeaveTemplateSecurityService {
    @TestVisible
    private static Boolean allowManagementDuringTest = false;

    public static void assertCanManageTemplates() {
        if (
            FeatureManagement.checkPermission('Weave_Manage_Templates') ||
            (Test.isRunningTest() && allowManagementDuringTest)
        ) {
            return;
        }
        throw new AuraHandledException('You do not have permission to manage Weave templates.');
    }

    @TestVisible
    private static void enableManagementForTest() {
        allowManagementDuringTest = true;
    }
}
