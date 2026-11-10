public with sharing class DceOrgWideEmailDTO {
    @AuraEnabled public Id id { get; set; }
    @AuraEnabled public String displayName { get; set; }
    @AuraEnabled public String address { get; set; }
    @AuraEnabled public String label { get; set; }
}
