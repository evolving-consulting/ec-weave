/**
 * Transport object for moving rendered DCE email content between Apex and LWC/API callers.
 * This class intentionally contains no business logic.
 */
public with sharing class RenderedEmailDTO {
    @AuraEnabled public String subject;
    @AuraEnabled public String htmlBody;
    @AuraEnabled public String plainTextBody;

    public RenderedEmailDTO() {
    }

    public RenderedEmailDTO(String subject, String htmlBody, String plainTextBody) {
        this.subject = subject;
        this.htmlBody = htmlBody;
        this.plainTextBody = plainTextBody;
    }
}
