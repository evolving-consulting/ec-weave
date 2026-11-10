public with sharing class DceBuilderTemplateDTO {
    private static final String DEFAULT_EDITOR_MODE = 'Visual';

    @AuraEnabled public Id id { get; set; }
    @AuraEnabled public String name { get; set; }
    @AuraEnabled public Boolean active { get; set; }
    @AuraEnabled public String parentObjectApiName { get; set; }
    @AuraEnabled public String parentObjectLabel { get; set; }
    @AuraEnabled public String subjectTemplate { get; set; }
    @AuraEnabled public String bodyTemplate { get; set; }
    @AuraEnabled public String headerContent { get; set; }
    @AuraEnabled public String footerContent { get; set; }
    // Deprecated compatibility aliases for existing API consumers.
    @AuraEnabled public String header { get; set; }
    @AuraEnabled public String footer { get; set; }
    @AuraEnabled public String headerEditorMode { get; set; }
    @AuraEnabled public String bodyEditorMode { get; set; }
    @AuraEnabled public String footerEditorMode { get; set; }
    @AuraEnabled public String description { get; set; }
    @AuraEnabled public String defaultFromEmail { get; set; }
    @AuraEnabled public Boolean allowUserEditBeforeSend { get; set; }
    @AuraEnabled public Boolean storeEmailHistory { get; set; }
    @AuraEnabled public List<DceBuilderSectionDTO> sections { get; set; }
    @AuraEnabled public List<DceBuilderRecipientDTO> recipients { get; set; }
    @AuraEnabled public List<DceBuilderPostSendActionDTO> postSendActions { get; set; }
    @AuraEnabled public List<Id> deletedSectionIds { get; set; }
    @AuraEnabled public List<Id> deletedLineIds { get; set; }
    @AuraEnabled public List<Id> deletedFieldIds { get; set; }
    @AuraEnabled public List<Id> deletedRecipientIds { get; set; }

    public DceBuilderTemplateDTO() {
        this.headerEditorMode = DEFAULT_EDITOR_MODE;
        this.bodyEditorMode = DEFAULT_EDITOR_MODE;
        this.footerEditorMode = DEFAULT_EDITOR_MODE;
        this.sections = new List<DceBuilderSectionDTO>();
        this.recipients = new List<DceBuilderRecipientDTO>();
        this.postSendActions = new List<DceBuilderPostSendActionDTO>();
        this.deletedSectionIds = new List<Id>();
        this.deletedLineIds = new List<Id>();
        this.deletedFieldIds = new List<Id>();
        this.deletedRecipientIds = new List<Id>();
    }
}
