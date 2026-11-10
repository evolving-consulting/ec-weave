public with sharing class DceBuilderObjectDTO {
    @AuraEnabled public String label { get; set; }
    @AuraEnabled public String apiName { get; set; }
    @AuraEnabled public String pluralLabel { get; set; }

    public DceBuilderObjectDTO() {
    }

    public DceBuilderObjectDTO(String label, String apiName, String pluralLabel) {
        this.label = label;
        this.apiName = apiName;
        this.pluralLabel = pluralLabel;
    }
}
