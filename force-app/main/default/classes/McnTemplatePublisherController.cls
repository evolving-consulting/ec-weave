/**
 * Visualforce controller for the mcnTemplatePublisher page.
 * Provides publish/update/delete/validate actions and reads the
 * current template + MCN publish status for display.
 */
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces')
public with sharing class McnTemplatePublisherController {

    public Id                    templateId     { get; set; }
    public Weave_Template_Config__c template    { get; private set; }
    public String                statusMessage  { get; private set; }
    public Boolean               isSuccess      { get; private set; }
    public Boolean               hasError       { get; private set; }
    public String                mcnAssetId     { get; private set; }
    public SfmcMappingValidator.ValidationResult validationResult { get; private set; }
    public SfmcTemplateConflictDetector.ConflictResult conflictResult { get; private set; }

    public McnTemplatePublisherController() {
        try {
            String idParam = ApexPages.currentPage().getParameters().get('id');
            templateId = String.isNotBlank(idParam) ? (Id) idParam : null;
        } catch (Exception e) {
            templateId = null;
        }
        isSuccess  = false;
        hasError   = false;
        loadTemplate();
    }

    public void loadTemplate() {
        if (String.isBlank(templateId)) return;
        List<Weave_Template_Config__c> results = [
            SELECT Id, Name, Status__c, SFMC_Template_ID__c,
                   SFMC_Publish_Status__c, SFMC_Last_Published__c, SFMC_Last_Error__c,
                   Subject_Template__c
            FROM   Weave_Template_Config__c
            WHERE  Id = :templateId
            WITH   USER_MODE
            LIMIT  1
        ];
        if (!results.isEmpty()) {
            template = results[0];
            mcnAssetId = template.SFMC_Template_ID__c;
        }
    }

    public PageReference doPublish() {
        clearMessages();
        try {
            SfmcTemplatePublisher.PublishResult result =
                SfmcTemplatePublisher.publishTemplate(templateId);
            isSuccess     = result.isSuccess;
            hasError      = !result.isSuccess;
            statusMessage = result.isSuccess
                ? 'Template published successfully. MCN Asset ID: ' + result.mcnAssetId
                : result.errorMessage;
            if (result.isSuccess) mcnAssetId = result.mcnAssetId;
        } catch (Exception e) {
            hasError      = true;
            statusMessage = 'Unexpected error: ' + e.getMessage();
        }
        loadTemplate();
        return null;
    }

    public PageReference doUpdate() {
        clearMessages();
        try {
            SfmcTemplatePublisher.PublishResult result =
                SfmcTemplatePublisher.updateTemplate(templateId);
            isSuccess     = result.isSuccess;
            hasError      = !result.isSuccess;
            statusMessage = result.isSuccess
                ? 'MCN asset updated successfully.'
                : result.errorMessage;
        } catch (Exception e) {
            hasError      = true;
            statusMessage = 'Unexpected error: ' + e.getMessage();
        }
        loadTemplate();
        return null;
    }

    public PageReference doDelete() {
        clearMessages();
        try {
            SfmcTemplatePublisher.PublishResult result =
                SfmcTemplatePublisher.deleteTemplate(templateId);
            isSuccess     = result.isSuccess;
            hasError      = !result.isSuccess;
            statusMessage = result.isSuccess
                ? 'MCN asset deleted. Weave template record retained for history.'
                : result.errorMessage;
            if (result.isSuccess) mcnAssetId = null;
        } catch (Exception e) {
            hasError      = true;
            statusMessage = 'Unexpected error: ' + e.getMessage();
        }
        loadTemplate();
        return null;
    }

    public PageReference doValidate() {
        clearMessages();
        try {
            validationResult = SfmcTemplatePublisher.validateTemplate(templateId);
            isSuccess        = validationResult.isValid;
            hasError         = !validationResult.isValid;
            statusMessage    = validationResult.isValid
                ? 'Validation passed. Template is ready to publish.'
                : 'Validation failed. See errors below.';
        } catch (Exception e) {
            hasError      = true;
            statusMessage = 'Unexpected error during validation: ' + e.getMessage();
        }
        return null;
    }

    public PageReference doCheckConflict() {
        clearMessages();
        try {
            conflictResult = SfmcTemplateConflictDetector.detectConflict(templateId);
            isSuccess      = conflictResult.state != SfmcTemplateConflictDetector.ConflictState.CONFLICT_DETECTED;
            hasError       = !isSuccess;
            statusMessage  = conflictResult.message;
        } catch (Exception e) {
            hasError      = true;
            statusMessage = 'Unexpected error during conflict check: ' + e.getMessage();
        }
        return null;
    }

    public Boolean getIsPublished() {
        return template != null && !String.isBlank(template.SFMC_Template_ID__c);
    }

    public Boolean getHasConflict() {
        return conflictResult != null &&
               conflictResult.state == SfmcTemplateConflictDetector.ConflictState.CONFLICT_DETECTED;
    }

    private void clearMessages() {
        statusMessage    = null;
        isSuccess        = false;
        hasError         = false;
        validationResult = null;
        conflictResult   = null;
    }
}
