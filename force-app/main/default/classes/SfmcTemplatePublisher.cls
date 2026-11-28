/**
 * Orchestrates publishing Weave templates to Marketing Cloud Next.
 *
 * Publish flow:
 *   1. Validate template (SfmcMappingValidator)
 *   2. Load all component HTML
 *   3. Translate merge fields to AMPscript (MergeFieldTranslator)
 *   4. Create or update MCN email asset (WeaveMarketingCloudNextAdapter)
 *   5. Update Weave_Template_Config__c status fields
 *   6. Write Weave_MCN_Sync_Log__c entry
 */
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.ApexDoc')
public with sharing class SfmcTemplatePublisher {

    // ── Public DTOs ───────────────────────────────────────────────────────────

    public class PublishResult {
        @AuraEnabled public Boolean isSuccess    { get; set; }
        @AuraEnabled public String  mcnAssetId   { get; set; }
        @AuraEnabled public String  errorMessage { get; set; }
        @AuraEnabled public String  publishType  { get; set; }

        public PublishResult(Boolean success, String assetId, String publishType) {
            this.isSuccess   = success;
            this.mcnAssetId  = assetId;
            this.publishType = publishType;
        }

        public PublishResult(String error, String publishType) {
            this.isSuccess    = false;
            this.errorMessage = error;
            this.publishType  = publishType;
        }
    }

    // ── Invocable (called from Flow) ─────────────────────────────────────────

    public class FlowPublishRequest {
        @InvocableVariable(label='Template Record ID' required=true)
        public Id templateId;
    }

    public class FlowPublishResult {
        @InvocableVariable(label='Success')
        public Boolean isSuccess;
        @InvocableVariable(label='MCN Asset ID')
        public String mcnAssetId;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Publish Template to MCN'
        description='Publishes or updates a Weave template as a Marketing Cloud Next email asset.'
        category='Dynamic Communication Engine'
    )
    public static List<FlowPublishResult> publishFromFlow(List<FlowPublishRequest> requests) {
        List<FlowPublishResult> results = new List<FlowPublishResult>();
        for (FlowPublishRequest req : requests) {
            FlowPublishResult fr = new FlowPublishResult();
            try {
                PublishResult pr = publishTemplate(req.templateId);
                fr.isSuccess   = pr.isSuccess;
                fr.mcnAssetId  = pr.mcnAssetId;
                fr.errorMessage = pr.errorMessage;
            } catch (Exception e) {
                fr.isSuccess    = false;
                fr.errorMessage = e.getMessage();
            }
            results.add(fr);
        }
        return results;
    }

    // ── AuraEnabled (called from VF page controller) ─────────────────────────

    @AuraEnabled
    public static PublishResult publishTemplateAura(Id templateId) {
        try {
            return publishTemplate(templateId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static PublishResult updateTemplateAura(Id templateId) {
        try {
            return updateTemplate(templateId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static PublishResult deleteTemplateAura(Id templateId) {
        try {
            return deleteTemplate(templateId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static SfmcMappingValidator.ValidationResult validateTemplateAura(Id templateId) {
        try {
            return validateTemplate(templateId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ── Core publish operations ───────────────────────────────────────────────

    public static PublishResult publishTemplate(Id templateId) {
        return publishTemplate(templateId, new WeaveMarketingCloudNextAdapter());
    }

    @TestVisible
    static PublishResult publishTemplate(Id templateId, WeaveMarketingCloudNextAdapter adapter) {
        // 1. Validate
        SfmcMappingValidator.ValidationResult validation = validateTemplate(templateId);
        if (!validation.isValid) {
            String errSummary = String.join(validation.errors, '; ');
            updateTemplateStatus(templateId, 'Error', null, errSummary);
            writeLog(templateId, 'Create', 'Error', null, 0, false, errSummary);
            return new PublishResult('Validation failed: ' + errSummary, 'Create');
        }

        // 2. Build translated content
        TranslatedTemplate tt = buildTranslatedContent(templateId);
        if (!tt.isValid) {
            updateTemplateStatus(templateId, 'Error', null, tt.errorMessage);
            writeLog(templateId, 'Create', 'Error', null, 0, false, tt.errorMessage);
            return new PublishResult(tt.errorMessage, 'Create');
        }

        // 3. Load the template to get the name and existing MCN ID
        Weave_Template_Config__c config = loadConfig(templateId);

        // If already published, do an update instead
        if (!String.isBlank(config.SFMC_Template_ID__c)) {
            return updateTemplate(templateId, adapter);
        }

        // 4. Create new MCN asset
        WeaveMarketingCloudNextAdapter.AdapterResult createResult =
            adapter.createEmailAsset(config.Name, tt.htmlContent, config.Subject_Template__c);

        if (!createResult.isSuccess) {
            updateTemplateStatus(templateId, 'Error', null, createResult.errorMessage);
            writeLog(templateId, 'Create', 'Error', null, tt.mergeFieldCount, false, createResult.errorMessage);
            return new PublishResult('MCN create failed: ' + createResult.errorMessage, 'Create');
        }

        // 5. Update Weave record
        String contentHash = SfmcTemplateConflictDetector.hashContent(tt.htmlContent);
        updateTemplateStatus(templateId, 'Published', createResult.assetId, null);
        writeLog(templateId, 'Create', 'Success', createResult.assetId, tt.mergeFieldCount, false, null, contentHash);

        return new PublishResult(true, createResult.assetId, 'Create');
    }

    public static PublishResult updateTemplate(Id templateId) {
        return updateTemplate(templateId, new WeaveMarketingCloudNextAdapter());
    }

    @TestVisible
    static PublishResult updateTemplate(Id templateId, WeaveMarketingCloudNextAdapter adapter) {
        Weave_Template_Config__c config = loadConfig(templateId);

        TranslatedTemplate tt = buildTranslatedContent(templateId);
        if (!tt.isValid) {
            updateTemplateStatus(templateId, 'Error', null, tt.errorMessage);
            writeLog(templateId, 'Update', 'Error', config.SFMC_Template_ID__c, 0, false, tt.errorMessage);
            return new PublishResult(tt.errorMessage, 'Update');
        }

        WeaveMarketingCloudNextAdapter.AdapterResult updateResult =
            adapter.updateEmailAsset(config.SFMC_Template_ID__c, tt.htmlContent, config.Subject_Template__c);

        if (!updateResult.isSuccess) {
            updateTemplateStatus(templateId, 'Error', null, updateResult.errorMessage);
            writeLog(templateId, 'Update', 'Error', config.SFMC_Template_ID__c, tt.mergeFieldCount, false, updateResult.errorMessage);
            return new PublishResult('MCN update failed: ' + updateResult.errorMessage, 'Update');
        }

        String contentHash = SfmcTemplateConflictDetector.hashContent(tt.htmlContent);
        updateTemplateStatus(templateId, 'Published', config.SFMC_Template_ID__c, null);
        writeLog(templateId, 'Update', 'Success', config.SFMC_Template_ID__c, tt.mergeFieldCount, false, null, contentHash);

        return new PublishResult(true, config.SFMC_Template_ID__c, 'Update');
    }

    public static PublishResult deleteTemplate(Id templateId) {
        return deleteTemplate(templateId, new WeaveMarketingCloudNextAdapter());
    }

    @TestVisible
    static PublishResult deleteTemplate(Id templateId, WeaveMarketingCloudNextAdapter adapter) {
        Weave_Template_Config__c config = loadConfig(templateId);

        if (String.isBlank(config.SFMC_Template_ID__c)) {
            return new PublishResult('Template has not been published to MCN.', 'Delete');
        }

        WeaveMarketingCloudNextAdapter.AdapterResult deleteResult =
            adapter.deleteEmailAsset(config.SFMC_Template_ID__c);

        if (!deleteResult.isSuccess) {
            writeLog(templateId, 'Delete', 'Error', config.SFMC_Template_ID__c, 0, false, deleteResult.errorMessage);
            return new PublishResult('MCN delete failed: ' + deleteResult.errorMessage, 'Delete');
        }

        // Clear MCN fields but keep Weave record for history
        updateTemplateStatus(templateId, 'Draft', '', null);
        writeLog(templateId, 'Delete', 'Success', config.SFMC_Template_ID__c, 0, false, null);

        return new PublishResult(true, config.SFMC_Template_ID__c, 'Delete');
    }

    public static SfmcMappingValidator.ValidationResult validateTemplate(Id templateId) {
        return SfmcMappingValidator.validateForPublish(templateId);
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    private class TranslatedTemplate {
        public Boolean isValid          { get; set; }
        public String  htmlContent      { get; set; }
        public Integer mergeFieldCount  { get; set; }
        public String  errorMessage     { get; set; }

        public TranslatedTemplate() {
            this.isValid         = true;
            this.mergeFieldCount = 0;
        }
    }

    private static TranslatedTemplate buildTranslatedContent(Id templateId) {
        TranslatedTemplate tt = new TranslatedTemplate();

        List<Weave_Template_Component__c> components = [
            SELECT Id, HTML_Output__c, Region__c, Display_Order__c
            FROM   Weave_Template_Component__c
            WHERE  Weave_Template_Config__c = :templateId
            WITH   USER_MODE
            ORDER BY Display_Order__c ASC NULLS LAST, CreatedDate ASC
        ];

        if (components.isEmpty()) {
            tt.isValid       = false;
            tt.errorMessage  = 'No components found for template.';
            return tt;
        }

        // Concatenate all component HTML in render order
        List<String> parts = new List<String>();
        for (Weave_Template_Component__c comp : components) {
            if (!String.isBlank(comp.HTML_Output__c)) {
                parts.add(comp.HTML_Output__c);
            }
        }

        String rawHtml = String.join(parts, '\n');
        MergeFieldTranslator.TranslationResult tr = MergeFieldTranslator.translate(rawHtml);

        tt.htmlContent     = tr.translatedContent;
        tt.mergeFieldCount = tr.mergeFieldsTranslated;
        return tt;
    }

    private static Weave_Template_Config__c loadConfig(Id templateId) {
        return [
            SELECT Id, Name, Subject_Template__c, SFMC_Template_ID__c, Status__c
            FROM   Weave_Template_Config__c
            WHERE  Id = :templateId
            WITH   USER_MODE
            LIMIT  1
        ];
    }

    private static void updateTemplateStatus(
        Id templateId, String status, String assetId, String errorMsg
    ) {
        Weave_Template_Config__c upd = new Weave_Template_Config__c(Id = templateId);
        upd.SFMC_Publish_Status__c = status;
        if (assetId != null) upd.SFMC_Template_ID__c = assetId;
        if (status == 'Published') upd.SFMC_Last_Published__c = System.now();
        upd.SFMC_Last_Error__c = errorMsg;
        update as user upd;
    }

    private static void writeLog(
        Id templateId, String publishType, String status, String assetId,
        Integer mergeFieldCount, Boolean conflictDetected, String errorMsg
    ) {
        writeLog(templateId, publishType, status, assetId, mergeFieldCount, conflictDetected, errorMsg, null);
    }

    private static void writeLog(
        Id templateId, String publishType, String status, String assetId,
        Integer mergeFieldCount, Boolean conflictDetected, String errorMsg, String contentHash
    ) {
        Weave_MCN_Sync_Log__c log = new Weave_MCN_Sync_Log__c(
            Template__c                  = templateId,
            Publish_Type__c              = publishType,
            Status__c                    = status,
            MCN_Asset_ID__c              = assetId,
            Merge_Fields_Translated__c   = mergeFieldCount,
            Conflict_Detected__c         = conflictDetected,
            Error_Message__c             = errorMsg,
            Translated_Content_Hash__c   = contentHash
        );
        insert as user log;
    }
}
