/**
 * Centralizes authorization for Dynamic Communication Engine template administration.
 */
public with sharing class DceTemplateSecurityService {
    @TestVisible
    private static Boolean allowManagementDuringTest = false;

    /**
     * Verifies that the current user can administer templates and author raw HTML.
     * @throws AuraHandledException when the custom permission is not assigned
     */
    public static void assertCanManageTemplates() {
        if (
            FeatureManagement.checkPermission('DCE_Manage_Templates') ||
            (Test.isRunningTest() && allowManagementDuringTest)
        ) {
            return;
        }
        throw new AuraHandledException('You do not have permission to manage email templates.');
    }

    /**
     * Enables template-management entry points for isolated unit tests.
     */
    @TestVisible
    private static void enableManagementForTest() {
        allowManagementDuringTest = true;
    }
}
