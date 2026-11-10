public with sharing class DceBuilderRecipientDTO {
    @AuraEnabled public Id id { get; set; }
    @AuraEnabled public String localKey { get; set; }
    @AuraEnabled public String name { get; set; }
    @AuraEnabled public Boolean active { get; set; }
    @AuraEnabled public Integer displayOrder { get; set; }
    @AuraEnabled public String recipientSourceType { get; set; }
    @AuraEnabled public String recipientType { get; set; }
    @AuraEnabled public String sourceObjectApiName { get; set; }
    @AuraEnabled public String sourceObjectLabel { get; set; }
    @AuraEnabled public String parentLookupFieldApiName { get; set; }
    @AuraEnabled public String parentLookupFieldLabel { get; set; }
    @AuraEnabled public String nameFieldApiName { get; set; }
    @AuraEnabled public String nameFieldLabel { get; set; }
    @AuraEnabled public String emailFieldApiName { get; set; }
    @AuraEnabled public String emailFieldLabel { get; set; }
    @AuraEnabled public String filterLogic { get; set; }
    @AuraEnabled public Boolean defaultSelected { get; set; }
    @AuraEnabled public Boolean allowMultiple { get; set; }
    @AuraEnabled public Boolean required { get; set; }
}
