/**
 * File option shown in the DCE composer and passed through preview/send selection.
 */
public with sharing class DceEmailAttachmentDTO {
    @AuraEnabled public Id contentDocumentId { get; set; }
    @AuraEnabled public Id contentVersionId { get; set; }
    @AuraEnabled public String title { get; set; }
    @AuraEnabled public String fileExtension { get; set; }
    @AuraEnabled public Integer contentSize { get; set; }
    @AuraEnabled public Boolean selected { get; set; }
    @AuraEnabled public String source { get; set; }

    public DceEmailAttachmentDTO() {
    }
}
