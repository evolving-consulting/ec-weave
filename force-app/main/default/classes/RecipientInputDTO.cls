/**
 * Transport object for moving selected DCE recipient input between Apex and LWC/API callers.
 * This class intentionally contains no business logic.
 */
public with sharing class RecipientInputDTO {
    @AuraEnabled public String name { get; set; }
    @AuraEnabled public String email { get; set; }
    @AuraEnabled public String recipientType { get; set; }

    public RecipientInputDTO() {
    }

    public RecipientInputDTO(String name, String email, String recipientType) {
        this.name = name;
        this.email = email;
        this.recipientType = recipientType;
    }
}
