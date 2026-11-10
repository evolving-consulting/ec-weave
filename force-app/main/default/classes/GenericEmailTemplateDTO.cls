/**
 * Transport object for moving DCE template configuration data between Apex and LWC/API callers.
 * This class intentionally contains no business logic.
 */
public with sharing class GenericEmailTemplateDTO {
    @AuraEnabled public Id id;
    @AuraEnabled public String name;
    @AuraEnabled public String description;
    @AuraEnabled public String subjectTemplate;
    @AuraEnabled public String parentObjectApiName;
    @AuraEnabled public Boolean allowUserEditBeforeSend;
    @AuraEnabled public Boolean storeEmailHistory;

    public GenericEmailTemplateDTO() {
    }

    public GenericEmailTemplateDTO(
        Id id,
        String name,
        String description,
        String subjectTemplate,
        String parentObjectApiName,
        Boolean allowUserEditBeforeSend,
        Boolean storeEmailHistory
    ) {
        this.id = id;
        this.name = name;
        this.description = description;
        this.subjectTemplate = subjectTemplate;
        this.parentObjectApiName = parentObjectApiName;
        this.allowUserEditBeforeSend = allowUserEditBeforeSend;
        this.storeEmailHistory = storeEmailHistory;
    }
}
