@SuppressWarnings('PMD.ApexDoc')
public with sharing class WeaveTemplateSecurityService {
    @TestVisible
    private static Boolean allowManagementDuringTest = false;

    public static void assertCanManageTemplates() {
        if (Test.isRunningTest()) {
            if (!allowManagementDuringTest) {
                throw new AuraHandledException('You do not have permission to manage Weave templates.');
            }
            return;
        }
        if (!FeatureManagement.checkPermission('Weave_Manage_Templates')) {
            throw new AuraHandledException('You do not have permission to manage Weave templates.');
        }
    }

    @TestVisible
    private static void enableManagementForTest() {
        allowManagementDuringTest = true;
    }
}
