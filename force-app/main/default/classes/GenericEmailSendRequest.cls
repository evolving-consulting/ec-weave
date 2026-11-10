/**
 * Transport object for moving a DCE email send request from LWC/API callers into Apex.
 * This class intentionally contains no business logic or email-sending behavior.
 */
public with sharing class GenericEmailSendRequest {
    @AuraEnabled public Id templateId { get; set; }
    @AuraEnabled public Id recordId { get; set; }
    @AuraEnabled public String subject { get; set; }
    @AuraEnabled public String htmlBody { get; set; }
    @AuraEnabled public List<RecipientInputDTO> toRecipients { get; set; }
    @AuraEnabled public List<RecipientInputDTO> ccRecipients { get; set; }
    @AuraEnabled public List<RecipientInputDTO> bccRecipients { get; set; }
    @AuraEnabled public List<Id> attachmentContentDocumentIds { get; set; }
    @AuraEnabled public Boolean storeHistory { get; set; }

    public GenericEmailSendRequest() {
    }

    public GenericEmailSendRequest(
        Id templateId,
        Id recordId,
        String subject,
        String htmlBody,
        List<RecipientInputDTO> toRecipients,
        List<RecipientInputDTO> ccRecipients,
        List<RecipientInputDTO> bccRecipients,
        Boolean storeHistory
    ) {
        this.templateId = templateId;
        this.recordId = recordId;
        this.subject = subject;
        this.htmlBody = htmlBody;
        this.toRecipients = toRecipients;
        this.ccRecipients = ccRecipients;
        this.bccRecipients = bccRecipients;
        this.storeHistory = storeHistory;
    }
}
