@isTest
private class WeavePdfControllerTest {

    @TestSetup
    static void makeData() {
        Weave_Template_Config__c template = new Weave_Template_Config__c(
            Name = 'PDF Test Template',
            Status__c = 'Active',
            Parent_Object_API_Name__c = 'Contact',
            Subject_Template__c = 'Test PDF Subject'
        );
        insert template;

        Contact c = new Contact(FirstName = 'PDF', LastName = 'Test', Email = 'pdftest@example.com');
        insert c;
    }

    @isTest
    static void testGeneratePdf() {
        Weave_Template_Config__c template = [SELECT Id FROM Weave_Template_Config__c LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        String docId = WeavePdfController.generatePdf(template.Id, c.Id);
        Test.stopTest();

        System.assertNotEquals(null, docId, 'Should return a ContentDocumentId');
        List<ContentVersion> cvs = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId = :docId WITH USER_MODE];
        System.assertEquals(1, cvs.size(), 'ContentVersion should exist');
    }

    @isTest
    static void testGeneratePdf_nullTemplate() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        try {
            WeavePdfController.generatePdf(null, c.Id);
            System.assert(false, 'Should throw');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testGenerateCombinedPdf() {
        Weave_Template_Config__c template = [SELECT Id FROM Weave_Template_Config__c LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        List<Id> templateIds = new List<Id>{ template.Id, template.Id };
        List<Id> recordIds = new List<Id>{ c.Id, c.Id };

        Test.startTest();
        String docId = WeavePdfController.generateCombinedPdf(templateIds, recordIds, 'Combined Test');
        Test.stopTest();

        System.assertNotEquals(null, docId, 'Should return a ContentDocumentId for combined PDF');
    }

    @isTest
    static void testGenerateCombinedPdf_mismatchedLists() {
        Weave_Template_Config__c template = [SELECT Id FROM Weave_Template_Config__c LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        List<Id> templateIds = new List<Id>{ template.Id };
        List<Id> recordIds = new List<Id>{ c.Id, c.Id };

        try {
            WeavePdfController.generateCombinedPdf(templateIds, recordIds, 'Test');
            System.assert(false, 'Should throw for mismatched lists');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
