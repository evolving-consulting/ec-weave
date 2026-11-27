@SuppressWarnings('PMD.MethodNamingConventions')
@IsTest
private class WeaveBrandServiceTest {

    @TestSetup
    static void setup() {
        WeaveTemplateSecurityService.enableManagementForTest();
    }

    // ── getBrands ──────────────────────────────────────────────────────────

    @IsTest
    static void getBrands_returnsAllBrands() {
        WeaveTemplateSecurityService.enableManagementForTest();
        insert new Weave_Brand__c(Name = 'Alpha', Status__c = 'Active');
        insert new Weave_Brand__c(Name = 'Beta',  Status__c = 'Inactive');

        Test.startTest();
        List<WeaveBuilderDTOs.WeaveBrandSummaryDTO> results = WeaveBrandService.getBrands();
        Test.stopTest();

        System.assert(results.size() >= 2, 'Expected at least 2 brands');
    }

    // ── saveBrand (insert) ─────────────────────────────────────────────────

    @IsTest
    static void saveBrand_insert_createsRecord() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBrandDTO dto = new WeaveBuilderDTOs.WeaveBrandDTO();
        dto.name           = 'Test Brand';
        dto.displayName    = 'Test Display';
        dto.status         = 'Active';
        dto.primaryColor   = '#1f5f5b';
        dto.secondaryColor = '#4fb893';

        Test.startTest();
        WeaveBuilderDTOs.WeaveBrandDTO saved = WeaveBrandService.saveBrand(dto);
        Test.stopTest();

        System.assertNotEquals(null, saved.id, 'ID should be set after insert');
        Weave_Brand__c rec = [SELECT Name, Status__c FROM Weave_Brand__c WHERE Id = :saved.id];
        System.assertEquals('Test Brand', rec.Name);
        System.assertEquals('Active', rec.Status__c);
    }

    @IsTest
    static void saveBrand_insert_autoGeneratesApiName() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBrandDTO dto = new WeaveBuilderDTOs.WeaveBrandDTO();
        dto.name   = 'My Brand Name';
        dto.status = 'Active';

        Test.startTest();
        WeaveBuilderDTOs.WeaveBrandDTO saved = WeaveBrandService.saveBrand(dto);
        Test.stopTest();

        Weave_Brand__c rec = [SELECT API_Name__c FROM Weave_Brand__c WHERE Id = :saved.id];
        System.assert(String.isNotBlank(rec.API_Name__c), 'API_Name__c should be auto-populated');
    }

    // ── saveBrand (update) ─────────────────────────────────────────────────

    @IsTest
    static void saveBrand_update_modifiesRecord() {
        WeaveTemplateSecurityService.enableManagementForTest();
        Weave_Brand__c existing = new Weave_Brand__c(Name = 'Old Name', Status__c = 'Active', API_Name__c = 'old_name');
        insert existing;

        WeaveBuilderDTOs.WeaveBrandDTO dto = new WeaveBuilderDTOs.WeaveBrandDTO();
        dto.id     = existing.Id;
        dto.name   = 'New Name';
        dto.status = 'Inactive';

        Test.startTest();
        WeaveBuilderDTOs.WeaveBrandDTO updated = WeaveBrandService.saveBrand(dto);
        Test.stopTest();

        Weave_Brand__c rec = [SELECT Name, Status__c FROM Weave_Brand__c WHERE Id = :existing.Id];
        System.assertEquals('New Name', rec.Name);
        System.assertEquals('Inactive', rec.Status__c);
    }

    // ── saveBrand validation ───────────────────────────────────────────────

    @IsTest
    static void saveBrand_missingName_throwsException() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBrandDTO dto = new WeaveBuilderDTOs.WeaveBrandDTO();
        dto.status = 'Active';

        Test.startTest();
        try {
            WeaveBrandService.saveBrand(dto);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException ex) {
            System.assert(ex.getMessage().contains('Name') || ex.getMessage() != null);
        }
        Test.stopTest();
    }

    @IsTest
    static void saveBrand_invalidPrimaryColor_throwsException() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBrandDTO dto = new WeaveBuilderDTOs.WeaveBrandDTO();
        dto.name         = 'Color Brand';
        dto.primaryColor = 'notacolor';

        Test.startTest();
        try {
            WeaveBrandService.saveBrand(dto);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void saveBrand_invalidEmail_throwsException() {
        WeaveTemplateSecurityService.enableManagementForTest();
        WeaveBuilderDTOs.WeaveBrandDTO dto = new WeaveBuilderDTOs.WeaveBrandDTO();
        dto.name                 = 'Email Brand';
        dto.orgWideEmailAddress  = 'not-an-email';

        Test.startTest();
        try {
            WeaveBrandService.saveBrand(dto);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
        Test.stopTest();
    }

    // ── loadBrand ─────────────────────────────────────────────────────────

    @IsTest
    static void loadBrand_returnsFullDTO() {
        WeaveTemplateSecurityService.enableManagementForTest();
        Weave_Brand__c brand = new Weave_Brand__c(
            Name           = 'Full Brand',
            Status__c      = 'Active',
            API_Name__c    = 'full_brand',
            Primary_Color__c   = '#1f5f5b',
            Secondary_Color__c = '#4fb893',
            Header_HTML__c = '<p>header</p>',
            Footer_HTML__c = '<p>footer</p>'
        );
        insert brand;

        Test.startTest();
        WeaveBuilderDTOs.WeaveBrandDTO dto = WeaveBrandService.loadBrand(brand.Id);
        Test.stopTest();

        System.assertEquals(brand.Id, dto.id);
        System.assertEquals('Full Brand', dto.name);
        System.assertEquals('#1f5f5b', dto.primaryColor);
        System.assertEquals('<p>header</p>', dto.headerHtml);
    }

    // ── deleteBrand ────────────────────────────────────────────────────────

    @IsTest
    static void deleteBrand_removesRecord() {
        WeaveTemplateSecurityService.enableManagementForTest();
        Weave_Brand__c brand = new Weave_Brand__c(Name = 'To Delete', Status__c = 'Active', API_Name__c = 'to_delete');
        insert brand;

        Test.startTest();
        WeaveBrandService.deleteBrand(brand.Id);
        Test.stopTest();

        List<Weave_Brand__c> remaining = [SELECT Id FROM Weave_Brand__c WHERE Id = :brand.Id];
        System.assertEquals(0, remaining.size(), 'Brand should be deleted');
    }

    @IsTest
    static void deleteBrand_nullsBrandOnTemplates() {
        WeaveTemplateSecurityService.enableManagementForTest();
        Weave_Brand__c brand = new Weave_Brand__c(Name = 'Ref Brand', Status__c = 'Active', API_Name__c = 'ref_brand');
        insert brand;

        // Create a template via the service so required fields are satisfied
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO tDto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        tDto.name                = 'Brand Template';
        tDto.status              = 'Active';
        tDto.parentObjectApiName = 'Contact';
        tDto.brandId             = brand.Id;
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO saved = WeaveTemplateBuilderService.saveTemplate(tDto);

        Test.startTest();
        WeaveBrandService.deleteBrand(brand.Id);
        Test.stopTest();

        Weave_Template_Config__c reloaded = [SELECT Brand__c FROM Weave_Template_Config__c WHERE Id = :saved.id];
        System.assertEquals(null, reloaded.Brand__c, 'Template Brand__c should be nulled after brand delete');
    }

    // ── Permission guard ───────────────────────────────────────────────────

    @IsTest
    static void getBrands_withoutPermission_throwsException() {
        // Do NOT call enableManagementForTest — no permission
        try {
            WeaveBrandService.getBrands();
            System.assert(false, 'Expected permission exception');
        } catch (AuraHandledException ex) {
            System.assertNotEquals(null, ex.getMessage());
        }
    }
}
