/**
 * Reports successful email delivery together with non-fatal history or post-send warnings.
 */
public with sharing class DceEmailSendResultDTO {
    @AuraEnabled public Boolean success { get; set; }
    @AuraEnabled public List<String> warnings { get; set; }

    /**
     * Creates an empty successful result.
     */
    public DceEmailSendResultDTO() {
        success = true;
        warnings = new List<String>();
    }
}
