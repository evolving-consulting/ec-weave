@SuppressWarnings('PMD.MethodNamingConventions')
@IsTest
private class WeaveTemplateBuilderControllerTest {

    @IsTest
    static void saveTemplate_delegatesToService() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.name = 'Controller Test Template';
        dto.parentObjectApiName = 'Account';
        dto.status = 'Draft';
        String templateJson = JSON.serialize(dto);

        Test.startTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO result = WeaveTemplateBuilderController.saveTemplate(templateJson);
        Test.stopTest();

        System.assertNotEquals(null, result.id, 'Template should be created via controller.');
        System.assertNotEquals(null, result.apiName, 'API name should be generated.');
    }

    @IsTest
    static void loadTemplate_returnsFullDTO() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.name = 'Load Controller Test';
        dto.parentObjectApiName = 'Account';
        dto.status = 'Draft';
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO saved = WeaveTemplateBuilderController.saveTemplate(JSON.serialize(dto));

        Test.startTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO loaded = WeaveTemplateBuilderController.loadTemplate(saved.id);
        Test.stopTest();

        System.assertEquals(saved.id, loaded.id, 'Loaded template Id should match.');
        System.assertEquals('Account', loaded.parentObjectApiName, 'Parent object should be preserved.');
    }

    @IsTest
    static void deleteTemplate_removesRecord() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.name = 'Delete Controller Test';
        dto.parentObjectApiName = 'Account';
        dto.status = 'Draft';
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO saved = WeaveTemplateBuilderController.saveTemplate(JSON.serialize(dto));

        Test.startTest();
        WeaveTemplateBuilderController.deleteTemplate(saved.id);
        Test.stopTest();

        List<Weave_Template_Config__c> remaining = [SELECT Id FROM Weave_Template_Config__c WHERE Id = :saved.id];
        System.assertEquals(0, remaining.size(), 'Template should be deleted.');
    }

    @IsTest
    static void getTemplates_returnsList() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.name = 'List Controller Test';
        dto.parentObjectApiName = 'Account';
        WeaveTemplateBuilderController.saveTemplate(JSON.serialize(dto));

        Test.startTest();
        List<WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO> templates = WeaveTemplateBuilderController.getTemplates();
        Test.stopTest();

        System.assert(templates.size() >= 1, 'At least one template should be returned.');
    }

    @IsTest
    static void getAvailableObjects_returnsObjects() {
        WeaveTemplateSecurityService.enableManagementForTest();
        Test.startTest();
        List<WeaveBuilderDTOs.WeaveBuilderObjectDTO> objects = WeaveTemplateBuilderController.getAvailableObjects();
        Test.stopTest();

        System.assert(!objects.isEmpty(), 'Available objects list should not be empty.');
    }

    @IsTest
    static void getFieldsForObject_returnsFields() {
        WeaveTemplateSecurityService.enableManagementForTest();
        Test.startTest();
        List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> fields = WeaveTemplateBuilderController.getFieldsForObject('Account');
        Test.stopTest();

        System.assert(!fields.isEmpty(), 'Account fields should be returned.');
    }

    @IsTest
    static void getUpdateableFieldsForObject_returnsFields() {
        WeaveTemplateSecurityService.enableManagementForTest();
        Test.startTest();
        List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> fields = WeaveTemplateBuilderController.getUpdateableFieldsForObject('Account');
        Test.stopTest();

        System.assert(!fields.isEmpty(), 'Updateable fields should be returned.');
    }

    @IsTest
    static void getRelationshipFields_returnsFields() {
        WeaveTemplateSecurityService.enableManagementForTest();
        Test.startTest();
        List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> fields = WeaveTemplateBuilderController.getRelationshipFields('Contact');
        Test.stopTest();

        System.assert(!fields.isEmpty(), 'Contact relationship fields should be returned.');
    }

    @IsTest
    static void saveTemplate_invalidJson_throws() {
        Test.startTest();
        try {
            WeaveTemplateBuilderController.saveTemplate('{ invalid json }');
            System.assert(false, 'Expected an exception for invalid JSON.');
        } catch (Exception e) {
            System.assert(true, 'Exception expected for malformed input.');
        }
        Test.stopTest();
    }
}
