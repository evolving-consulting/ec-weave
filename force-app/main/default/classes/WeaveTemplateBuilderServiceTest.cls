@SuppressWarnings('PMD.MethodNamingConventions')
@IsTest
private class WeaveTemplateBuilderServiceTest {

    private static Weave_Template_Config__c createTemplate(String parentObj) {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.name = 'Test Template ' + String.valueOf(Crypto.getRandomInteger());
        dto.parentObjectApiName = parentObj;
        dto.status = 'Draft';
        dto.subjectTemplate = 'Hello {{Parent.Name}}';
        dto.allowUserEditBeforeSend = true;
        dto.storeEmailHistory = true;
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO saved = WeaveTemplateBuilderService.saveTemplate(dto);
        return [SELECT Id, Name, API_Name__c, Status__c, Parent_Object_API_Name__c FROM Weave_Template_Config__c WHERE Id = :saved.id LIMIT 1];
    }

    @IsTest
    static void saveTemplate_createsConfig() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.name = 'My Test Template';
        dto.parentObjectApiName = 'Account';
        dto.status = 'Draft';
        dto.allowUserEditBeforeSend = true;
        dto.storeEmailHistory = true;

        Test.startTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO result = WeaveTemplateBuilderService.saveTemplate(dto);
        Test.stopTest();

        System.assertNotEquals(null, result.id, 'Template Id should be set after save.');
        System.assertNotEquals(null, result.apiName, 'API name should be auto-generated.');
        System.assertEquals('Account', result.parentObjectApiName, 'Parent object should be preserved.');
    }

    @IsTest
    static void saveTemplate_generatesUniqueApiName() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto1 = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto1.name = 'Duplicate Name';
        dto1.parentObjectApiName = 'Account';
        dto1.status = 'Draft';

        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto2 = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto2.name = 'Duplicate Name';
        dto2.parentObjectApiName = 'Account';
        dto2.status = 'Draft';

        Test.startTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO result1 = WeaveTemplateBuilderService.saveTemplate(dto1);
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO result2 = WeaveTemplateBuilderService.saveTemplate(dto2);
        Test.stopTest();

        System.assertNotEquals(result1.apiName, result2.apiName, 'API names must be unique across templates.');
    }

    @IsTest
    static void saveTemplate_savesAndLoadsComponents() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.name = 'Component Test Template';
        dto.parentObjectApiName = 'Account';
        dto.status = 'Draft';
        WeaveBuilderDTOs.WeaveBuilderComponentDTO comp = new WeaveBuilderDTOs.WeaveBuilderComponentDTO();
        comp.componentType = 'Text';
        comp.region = 'Body';
        comp.displayOrder = 1;
        comp.htmlOutput = '<p>Hello World</p>';
        dto.components.add(comp);

        Test.startTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO saved = WeaveTemplateBuilderService.saveTemplate(dto);
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO loaded = WeaveTemplateBuilderService.loadTemplate(saved.id);
        Test.stopTest();

        System.assertEquals(1, loaded.components.size(), 'One component should be saved and loaded.');
        System.assertEquals('Text', loaded.components[0].componentType, 'Component type should be preserved.');
        System.assertEquals('Body', loaded.components[0].region, 'Region should be preserved.');
    }

    @IsTest
    static void saveTemplate_savesQuery() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.name = 'Query Test Template';
        dto.parentObjectApiName = 'Account';
        dto.status = 'Draft';
        WeaveBuilderDTOs.WeaveBuilderQueryDTO q = new WeaveBuilderDTOs.WeaveBuilderQueryDTO();
        q.name = 'Related Contacts';
        q.soqlQuery = 'SELECT Id, Name, Email FROM Contact';
        q.parentLookupField = 'AccountId';
        dto.queries.add(q);

        Test.startTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO saved = WeaveTemplateBuilderService.saveTemplate(dto);
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO loaded = WeaveTemplateBuilderService.loadTemplate(saved.id);
        Test.stopTest();

        System.assertEquals(1, loaded.queries.size(), 'One query should be saved and loaded.');
        System.assertEquals('Related Contacts', loaded.queries[0].name, 'Query name should be preserved.');
    }

    @IsTest
    static void saveTemplate_deletesChildren() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.name = 'Delete Test Template';
        dto.parentObjectApiName = 'Account';
        dto.status = 'Draft';
        WeaveBuilderDTOs.WeaveBuilderComponentDTO comp = new WeaveBuilderDTOs.WeaveBuilderComponentDTO();
        comp.componentType = 'Divider';
        comp.region = 'Body';
        comp.displayOrder = 1;
        dto.components.add(comp);
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO saved = WeaveTemplateBuilderService.saveTemplate(dto);

        Id compId = saved.components[0].id;
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO updateDto = WeaveTemplateBuilderService.loadTemplate(saved.id);
        updateDto.components.clear();
        updateDto.deletedComponentIds.add(compId);

        Test.startTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO result = WeaveTemplateBuilderService.saveTemplate(updateDto);
        Test.stopTest();

        System.assertEquals(0, result.components.size(), 'Component should have been deleted.');
    }

    @IsTest
    static void deleteTemplate_removesConfig() {
        WeaveTemplateSecurityService.enableManagementForTest();
        Weave_Template_Config__c template = createTemplate('Account');

        Test.startTest();
        WeaveTemplateBuilderService.deleteTemplate(template.Id);
        Test.stopTest();

        List<Weave_Template_Config__c> remaining = [SELECT Id FROM Weave_Template_Config__c WHERE Id = :template.Id];
        System.assertEquals(0, remaining.size(), 'Template should have been deleted.');
    }

    @IsTest
    static void saveTemplate_withoutPermission_throws() {
        // Run as a standard user who does not have the Weave_Manage_Templates custom permission
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User noPermUser = new User(
            Alias = 'wvnoperm',
            Email = 'weavenoperm@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'WeaveNoPerms',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = stdProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'weavenoperm_' + String.valueOf(Crypto.getRandomInteger()) + '@example.com.invalid'
        );
        insert noPermUser;

        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.name = 'Permission Test';
        dto.parentObjectApiName = 'Account';

        Boolean threwException = false;
        Test.startTest();
        System.runAs(noPermUser) {
            try {
                WeaveTemplateBuilderService.saveTemplate(dto);
            } catch (AuraHandledException e) {
                threwException = true;
            }
        }
        Test.stopTest();

        System.assert(threwException, 'saveTemplate should throw for a user without Weave_Manage_Templates.');
    }

    @IsTest
    static void getTemplates_returnsList() {
        WeaveTemplateSecurityService.enableManagementForTest();
        createTemplate('Account');

        Test.startTest();
        List<WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO> templates = WeaveTemplateBuilderService.getTemplates();
        Test.stopTest();

        System.assert(templates.size() >= 1, 'At least one template should be returned.');
    }

    @IsTest
    static void getFieldsForObject_returnsFields() {
        WeaveTemplateSecurityService.enableManagementForTest();
        Test.startTest();
        List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> fields = WeaveTemplateBuilderService.getFieldsForObject('Account');
        Test.stopTest();

        System.assert(!fields.isEmpty(), 'Account should have accessible fields.');
        Boolean hasName = false;
        for (WeaveBuilderDTOs.WeaveBuilderFieldDTO f : fields) {
            if (f.apiName == 'Name') { hasName = true; break; }
        }
        System.assert(hasName, 'Account fields should include Name.');
    }

    @IsTest
    static void saveTemplate_withDynamicSegmentRecipient_roundTrips() {
        WeaveTemplateSecurityService.enableManagementForTest();

        Weave_Recipient_Segment__c seg = new Weave_Recipient_Segment__c(
            Name = 'Test Segment',
            Object_API_Name__c = 'Contact',
            Email_Field_API_Name__c = 'Email',
            Status__c = 'Active'
        );
        insert seg;

        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.name = 'Segment Recipient Template';
        dto.parentObjectApiName = 'Contact';
        dto.status = 'Draft';
        WeaveBuilderDTOs.WeaveBuilderRecipientDTO r = new WeaveBuilderDTOs.WeaveBuilderRecipientDTO();
        r.localKey = 'local-seg-1';
        r.recipientType = 'To';
        r.recipientSourceType = 'Dynamic Segment';
        r.segmentId = seg.Id;
        r.active = true;
        r.defaultSelected = true;
        dto.recipients = new List<WeaveBuilderDTOs.WeaveBuilderRecipientDTO>{ r };

        Test.startTest();
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO saved = WeaveTemplateBuilderService.saveTemplate(dto);
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO loaded = WeaveTemplateBuilderService.loadTemplate(saved.id);
        Test.stopTest();

        System.assertEquals(1, loaded.recipients.size(), 'One recipient should be saved.');
        System.assertEquals('Dynamic Segment', loaded.recipients[0].recipientSourceType, 'Source type should be Dynamic Segment.');
        System.assertEquals(String.valueOf(seg.Id), loaded.recipients[0].segmentId, 'Segment Id should round-trip.');
    }

    @IsTest
    static void validateRecipient_dynamicSegmentWithoutSegmentId_throws() {
        WeaveTemplateSecurityService.enableManagementForTest();

        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.name = 'Invalid Segment Recipient';
        dto.parentObjectApiName = 'Account';
        dto.status = 'Draft';
        WeaveBuilderDTOs.WeaveBuilderRecipientDTO r = new WeaveBuilderDTOs.WeaveBuilderRecipientDTO();
        r.localKey = 'local-bad';
        r.recipientType = 'To';
        r.recipientSourceType = 'Dynamic Segment';
        r.segmentId = null;
        r.active = true;
        dto.recipients = new List<WeaveBuilderDTOs.WeaveBuilderRecipientDTO>{ r };

        Boolean threw = false;
        Test.startTest();
        try {
            WeaveTemplateBuilderService.saveTemplate(dto);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Should throw when Dynamic Segment recipient has no segmentId.');
    }
}
