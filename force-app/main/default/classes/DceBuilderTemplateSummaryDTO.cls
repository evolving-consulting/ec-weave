public with sharing class DceBuilderTemplateSummaryDTO {
    @AuraEnabled public Id id { get; set; }
    @AuraEnabled public String name { get; set; }
    @AuraEnabled public String parentObjectApiName { get; set; }
    @AuraEnabled public String parentObjectLabel { get; set; }
    @AuraEnabled public Boolean active { get; set; }
    @AuraEnabled public String description { get; set; }
    @AuraEnabled public Datetime lastModifiedDate { get; set; }
}
