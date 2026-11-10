public with sharing class DceTemplateBuilderController {
    @AuraEnabled(cacheable=true)
    public static List<DceBuilderObjectDTO> getAvailableObjects() {
        return DceTemplateBuilderService.getAvailableObjects();
    }

    @AuraEnabled(cacheable=true)
    public static List<DceOrgWideEmailDTO> getOrgWideEmailAddresses() {
        return DceTemplateBuilderService.getOrgWideEmailAddresses();
    }

    @AuraEnabled(cacheable=true)
    public static List<DceBuilderTemplateSummaryDTO> getTemplates() {
        return DceTemplateBuilderService.getTemplates();
    }

    @AuraEnabled(cacheable=true)
    public static List<DceBuilderFieldDTO> getFieldsForObject(String objectApiName) {
        return DceTemplateBuilderService.getFieldsForObject(objectApiName);
    }

    @AuraEnabled(cacheable=true)
    public static List<DceBuilderFieldDTO> getUpdateableFieldsForObject(String objectApiName) {
        return DceTemplateBuilderService.getUpdateableFieldsForObject(objectApiName);
    }

    @AuraEnabled(cacheable=true)
    public static List<DceBuilderFieldDTO> getRelationshipFields(String objectApiName) {
        return DceTemplateBuilderService.getRelationshipFields(objectApiName);
    }

    @AuraEnabled(cacheable=true)
    public static DceBuilderTemplateDTO loadTemplate(Id templateId) {
        return DceTemplateBuilderService.loadTemplate(templateId);
    }

    @AuraEnabled
    public static DceBuilderTemplateDTO saveTemplate(DceBuilderTemplateDTO templateDto) {
        return DceTemplateBuilderService.saveTemplate(templateDto);
    }

    @AuraEnabled
    public static void deleteTemplate(Id templateId) {
        DceTemplateBuilderService.deleteTemplate(templateId);
    }

    @AuraEnabled
    public static RenderedEmailDTO previewTemplate(Id templateId, Id recordId) {
        DceTemplateSecurityService.assertCanManageTemplates();
        if (templateId == null) {
            throw new AuraHandledException('Save the template before previewing.');
        }

        if (recordId == null) {
            throw new AuraHandledException('Select a record to preview the template.');
        }

        try {
            return GenericEmailTemplateRenderer.renderEmail(templateId, recordId);
        } catch (Exception e) {
            throw new AuraHandledException('Unable to generate preview. Please check your template configuration.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DceBuilderFieldDTO> getLookupFieldsForChildObject(String childObjectApiName, String parentObjectApiName) {
        return DceTemplateBuilderService.getLookupFieldsForChildObject(childObjectApiName, parentObjectApiName);
    }
}
