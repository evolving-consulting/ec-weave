/**
 * Transport object for moving selectable DCE recipient options between Apex and LWC/API callers.
 * This class intentionally contains no business logic.
 */
public with sharing class RecipientOptionDTO {
    @AuraEnabled public String id;
    @AuraEnabled public String name;
    @AuraEnabled public String email;
    @AuraEnabled public String recipientType;
    @AuraEnabled public String source;
    @AuraEnabled public Boolean selected;
    @AuraEnabled public Boolean required;
    @AuraEnabled public Boolean allowMultiple;
    @AuraEnabled public String sourceType;

    public RecipientOptionDTO() {
    }

    public RecipientOptionDTO(
        String id,
        String name,
        String email,
        String recipientType,
        String source,
        Boolean selected,
        Boolean required,
        Boolean allowMultiple,
        String sourceType
    ) {
        this.id = id;
        this.name = name;
        this.email = email;
        this.recipientType = recipientType;
        this.source = source;
        this.selected = selected;
        this.required = required;
        this.allowMultiple = allowMultiple;
        this.sourceType = sourceType;
    }
}
