public with sharing class DceBuilderSectionDTO {
    @AuraEnabled public Id id { get; set; }
    @AuraEnabled public String localKey { get; set; }
    @AuraEnabled public String name { get; set; }
    @AuraEnabled public String sectionName { get; set; }
    @AuraEnabled public String sectionKey { get; set; }
    @AuraEnabled public Boolean active { get; set; }
    @AuraEnabled public Integer displayOrder { get; set; }
    @AuraEnabled public String sectionType { get; set; }
    @AuraEnabled public String childObjectApiName { get; set; }
    @AuraEnabled public String childObjectLabel { get; set; }
    @AuraEnabled public String parentLookupFieldApiName { get; set; }
    @AuraEnabled public String parentLookupFieldLabel { get; set; }
    @AuraEnabled public String sortFieldApiName { get; set; }
    @AuraEnabled public String sortFieldLabel { get; set; }
    @AuraEnabled public String sortDirection { get; set; }
    @AuraEnabled public String filterLogic { get; set; }
    @AuraEnabled public String staticContent { get; set; }
    @AuraEnabled public String sectionHeader { get; set; }
    @AuraEnabled public String sectionFooter { get; set; }
    @AuraEnabled public String repeatLabel { get; set; }
    @AuraEnabled public Boolean includeAutoNumber { get; set; }
    @AuraEnabled public Integer autoNumberStart { get; set; }
    @AuraEnabled public List<DceBuilderLineDTO> lines { get; set; }
    @AuraEnabled public List<DceBuilderColumnDTO> fields { get; set; }

    public DceBuilderSectionDTO() {
        this.lines = new List<DceBuilderLineDTO>();
        this.fields = new List<DceBuilderColumnDTO>();
    }

    public class DceBuilderLineDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Id sectionId { get; set; }
        @AuraEnabled public String localKey { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Integer displayOrder { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public String lineTemplate { get; set; }
        @AuraEnabled public String displayStyle { get; set; }
        @AuraEnabled public Boolean renderOnlyIfNotBlank { get; set; }
    }

    public class DceBuilderColumnDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Id sectionId { get; set; }
        @AuraEnabled public String localKey { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String fieldApiName { get; set; }
        @AuraEnabled public String fieldLabel { get; set; }
        @AuraEnabled public String labelOverride { get; set; }
        @AuraEnabled public Integer displayOrder { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Boolean showLabel { get; set; }
        @AuraEnabled public String displayStyle { get; set; }
        @AuraEnabled public Boolean isMainTitle { get; set; }
        @AuraEnabled public String prefixText { get; set; }
        @AuraEnabled public String suffixText { get; set; }
        @AuraEnabled public Boolean lineBreakAfter { get; set; }
        @AuraEnabled public Boolean renderOnlyIfNotBlank { get; set; }
        @AuraEnabled public String tableColumnWidth { get; set; }
    }
}
