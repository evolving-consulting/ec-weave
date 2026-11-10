public with sharing class DceBuilderFieldDTO {
    @AuraEnabled public String label { get; set; }
    @AuraEnabled public String apiName { get; set; }
    @AuraEnabled public String dataType { get; set; }
    @AuraEnabled public String relationshipName { get; set; }
    @AuraEnabled public List<String> referenceTo { get; set; }
    @AuraEnabled public Boolean isSortable { get; set; }
    @AuraEnabled public Boolean isFilterable { get; set; }
    @AuraEnabled public Boolean isNameField { get; set; }

    public DceBuilderFieldDTO() {
        this.referenceTo = new List<String>();
    }
}
