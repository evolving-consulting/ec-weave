public with sharing class WeaveTemplateBuilderController {

    @AuraEnabled(cacheable=true)
    public static List<WeaveBuilderDTOs.WeaveBuilderObjectDTO> getAvailableObjects() {
        return WeaveTemplateBuilderService.getAvailableObjects();
    }

    @AuraEnabled(cacheable=true)
    public static List<WeaveBuilderDTOs.WeaveOrgWideEmailDTO> getOrgWideEmailAddresses() {
        return WeaveTemplateBuilderService.getOrgWideEmailAddresses();
    }

    @AuraEnabled
    public static List<WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO> getTemplates() {
        return WeaveTemplateBuilderService.getTemplates();
    }

    @AuraEnabled(cacheable=true)
    public static List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> getFieldsForObject(String objectApiName) {
        return WeaveTemplateBuilderService.getFieldsForObject(objectApiName);
    }

    @AuraEnabled(cacheable=true)
    public static List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> getUpdateableFieldsForObject(String objectApiName) {
        return WeaveTemplateBuilderService.getUpdateableFieldsForObject(objectApiName);
    }

    @AuraEnabled(cacheable=true)
    public static List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> getRelationshipFields(String objectApiName) {
        return WeaveTemplateBuilderService.getRelationshipFields(objectApiName);
    }

    @AuraEnabled(cacheable=true)
    public static List<WeaveBuilderDTOs.WeaveBuilderObjectDTO> getRelatedObjectsForQuery(String parentObjectApiName) {
        return WeaveTemplateBuilderService.getRelatedObjectsForQuery(parentObjectApiName);
    }

    @AuraEnabled(cacheable=true)
    public static List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> getLookupFieldsForChildObject(String childObjectApiName, String parentObjectApiName) {
        return WeaveTemplateBuilderService.getLookupFieldsForChildObject(childObjectApiName, parentObjectApiName);
    }

    @AuraEnabled
    public static WeaveBuilderDTOs.WeaveBuilderTemplateDTO loadTemplate(Id templateId) {
        return WeaveTemplateBuilderService.loadTemplate(templateId);
    }

    @AuraEnabled
    public static WeaveBuilderDTOs.WeaveBuilderTemplateDTO saveTemplate(String templateJson) {
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto =
            (WeaveBuilderDTOs.WeaveBuilderTemplateDTO) JSON.deserialize(templateJson, WeaveBuilderDTOs.WeaveBuilderTemplateDTO.class);
        return WeaveTemplateBuilderService.saveTemplate(dto);
    }

    @AuraEnabled
    public static void deleteTemplate(Id templateId) {
        WeaveTemplateBuilderService.deleteTemplate(templateId);
    }

    @AuraEnabled
    public static Id cloneTemplate(Id templateId, String newName, String newApiName, String newOutputType) {
        try {
            return WeaveTemplateBuilderService.cloneTemplate(templateId, newName, newApiName, newOutputType);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static WeaveEmailTemplateRenderer.RenderedEmailDTO previewTemplate(Id templateId, Id recordId) {
        return WeaveEmailTemplateRenderer.renderEmail(templateId, recordId, false);
    }

    @AuraEnabled
    public static String previewTemplatePdf(Id templateId, Id recordId) {
        try {
            Boolean isDocument = isDocumentOutputType(templateId);
            WeaveEmailTemplateRenderer.RenderedEmailDTO rendered = isDocument
                ? WeaveEmailTemplateRenderer.renderCanvas(templateId, recordId, false)
                : WeaveEmailTemplateRenderer.renderEmail(templateId, recordId, false);
            String title = String.isNotBlank(rendered.subject) ? rendered.subject : 'Preview';
            ContentVersion cv = WeavePdfService.previewPdf(rendered.htmlBody, title);
            return cv.ContentDocumentId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to generate PDF preview. Please contact your administrator.');
        }
    }

    private static Boolean isDocumentOutputType(Id templateId) {
        try {
            List<Weave_Template_Config__c> t = [
                SELECT Template_Output_Type__c FROM Weave_Template_Config__c
                WHERE Id = :templateId WITH USER_MODE LIMIT 1
            ];
            return !t.isEmpty() && t[0].get('Template_Output_Type__c') == 'Document';
        } catch (Exception e) { return false; }
    }

    @AuraEnabled
    public static List<Map<String,String>> getTemplateFiles(Id templateId, String fileType) {
        return WeaveTemplateBuilderService.getTemplateFiles(templateId, fileType);
    }

    @AuraEnabled
    public static String createPublicImageLink(Id contentVersionId) {
        return WeaveTemplateBuilderService.createPublicImageLink(contentVersionId);
    }

    @AuraEnabled
    public static void deleteTemplateFile(Id contentDocumentId) {
        WeaveTemplateBuilderService.deleteTemplateFile(contentDocumentId);
    }

    // ── Brand methods ─────────────────────────────────────────────────────────

    @AuraEnabled
    public static List<WeaveBuilderDTOs.WeaveBrandSummaryDTO> getBrands() {
        return WeaveBrandService.getBrands();
    }

    @AuraEnabled(cacheable=true)
    public static WeaveBuilderDTOs.WeaveBrandDTO loadBrand(Id brandId) {
        return WeaveBrandService.loadBrand(brandId);
    }

    @AuraEnabled
    public static WeaveBuilderDTOs.WeaveBrandDTO saveBrand(String brandJson) {
        WeaveBuilderDTOs.WeaveBrandDTO dto =
            (WeaveBuilderDTOs.WeaveBrandDTO) JSON.deserialize(brandJson, WeaveBuilderDTOs.WeaveBrandDTO.class);
        return WeaveBrandService.saveBrand(dto);
    }

    @AuraEnabled
    public static void deleteBrand(Id brandId) {
        WeaveBrandService.deleteBrand(brandId);
    }

    @AuraEnabled
    public static List<Map<String,String>> getBrandFiles(Id brandId) {
        return WeaveBrandService.getBrandFiles(brandId);
    }

    @AuraEnabled
    public static String createBrandPublicImageLink(Id brandId, Id contentVersionId) {
        return WeaveBrandService.createBrandPublicImageLink(brandId, contentVersionId);
    }

    @AuraEnabled
    public static void deleteBrandFile(Id contentDocumentId) {
        WeaveBrandService.deleteBrandFile(contentDocumentId);
    }

    @AuraEnabled
    public static void sendTestEmail(Id templateId, Id recordId) {
        if (templateId == null || recordId == null) {
            throw new AuraHandledException('Template and record are required for test email.');
        }
        WeaveEmailTemplateRenderer.RenderedEmailDTO rendered = WeaveEmailTemplateRenderer.renderEmail(templateId, recordId, false);
        String currentUserEmail = UserInfo.getUserEmail();
        if (String.isBlank(currentUserEmail)) {
            throw new AuraHandledException('Current user has no email address configured.');
        }
        GenericEmailSendRequest req = new GenericEmailSendRequest();
        req.recordId     = recordId;
        req.subject      = '[TEST] ' + rendered.subject;
        req.htmlBody     = rendered.htmlBody;
        req.toRecipients = new List<RecipientInputDTO>{ new RecipientInputDTO(UserInfo.getName(), currentUserEmail, 'To') };
        WeaveEmailSendService.sendEmail(req);
    }

    @AuraEnabled
    public static Id createScheduledSend(Id templateId, String scheduledDateTime, String sendType, Id recordId, String filterClause) {
        if (templateId == null || String.isBlank(scheduledDateTime) || String.isBlank(sendType)) {
            throw new AuraHandledException('Template, scheduled time, and send type are required.');
        }
        if (sendType == 'Individual' && recordId == null) {
            throw new AuraHandledException('A record is required for Individual sends.');
        }
        Datetime scheduledDt = (Datetime) JSON.deserialize('"' + scheduledDateTime + '"', Datetime.class);
        if (scheduledDt <= System.now()) {
            throw new AuraHandledException('Scheduled time must be in the future.');
        }
        Weave_Scheduled_Send__c rec = new Weave_Scheduled_Send__c(
            Template__c    = templateId,
            Status__c      = 'Pending',
            Send_Type__c   = sendType,
            Scheduled_At__c = scheduledDt,
            Record_Id__c   = recordId != null ? String.valueOf(recordId) : null,
            Filter_Clause__c = filterClause
        );
        insert rec;

        String jobName = 'WeaveSend_' + rec.Id + '_' + System.now().getTime();
        String cronStr = scheduledDt.second() + ' ' + scheduledDt.minute() + ' ' + scheduledDt.hour()
            + ' ' + scheduledDt.day() + ' ' + scheduledDt.month() + ' ? ' + scheduledDt.year();
        System.schedule(jobName, cronStr, new WeaveScheduledEmailJob(rec.Id));

        rec.Job_Name__c = jobName;
        update rec;
        return rec.Id;
    }

    @AuraEnabled
    public static List<WeaveBuilderDTOs.WeaveScheduledSendDTO> getScheduledSends(Id templateId) {
        if (templateId == null) return new List<WeaveBuilderDTOs.WeaveScheduledSendDTO>();
        List<Weave_Scheduled_Send__c> rows = [
            SELECT Id, Name, Status__c, Send_Type__c, Scheduled_At__c,
                   Filter_Clause__c, Record_Id__c, Job_Name__c,
                   Records_Targeted__c, Records_Sent__c, Records_Failed__c, Error_Detail__c
            FROM Weave_Scheduled_Send__c
            WHERE Template__c = :templateId
            WITH USER_MODE
            ORDER BY Scheduled_At__c DESC
            LIMIT 200
        ];
        List<WeaveBuilderDTOs.WeaveScheduledSendDTO> result = new List<WeaveBuilderDTOs.WeaveScheduledSendDTO>();
        for (Weave_Scheduled_Send__c r : rows) {
            WeaveBuilderDTOs.WeaveScheduledSendDTO dto = new WeaveBuilderDTOs.WeaveScheduledSendDTO();
            dto.id              = r.Id;
            dto.name            = r.Name;
            dto.status          = r.Status__c;
            dto.sendType        = r.Send_Type__c;
            dto.scheduledAt     = r.Scheduled_At__c != null ? String.valueOf(r.Scheduled_At__c) : null;
            dto.filterClause    = r.Filter_Clause__c;
            dto.recordId        = r.Record_Id__c;
            dto.jobName         = r.Job_Name__c;
            dto.recordsTargeted = r.Records_Targeted__c != null ? Integer.valueOf(r.Records_Targeted__c) : null;
            dto.recordsSent     = r.Records_Sent__c != null ? Integer.valueOf(r.Records_Sent__c) : null;
            dto.recordsFailed   = r.Records_Failed__c != null ? Integer.valueOf(r.Records_Failed__c) : null;
            dto.errorDetail     = r.Error_Detail__c;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static void cancelScheduledSend(Id scheduledSendId) {
        if (scheduledSendId == null) throw new AuraHandledException('Scheduled send ID is required.');
        List<Weave_Scheduled_Send__c> rows = [
            SELECT Id, Job_Name__c, Status__c FROM Weave_Scheduled_Send__c
            WHERE Id = :scheduledSendId WITH USER_MODE LIMIT 1
        ];
        if (rows.isEmpty()) throw new AuraHandledException('Scheduled send not found.');
        Weave_Scheduled_Send__c rec = rows[0];
        if (rec.Status__c != 'Pending') throw new AuraHandledException('Only Pending sends can be cancelled.');
        if (String.isNotBlank(rec.Job_Name__c)) {
            List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :rec.Job_Name__c LIMIT 1];
            if (!jobs.isEmpty()) {
                try { System.abortJob(jobs[0].Id); } catch (Exception ignored) {}
            }
        }
        rec.Status__c = 'Cancelled';
        update rec;
    }

    @AuraEnabled
    public static List<Weave_Recipient_Segment__c> getActiveSegments(String objectApiName) {
        return WeaveRecipientSegmentController.getActiveSegments(objectApiName);
    }

    @AuraEnabled
    public static void sendScheduledSendNow(Id scheduledSendId) {
        if (scheduledSendId == null) throw new AuraHandledException('Scheduled send ID is required.');
        List<Weave_Scheduled_Send__c> rows = [
            SELECT Id, Job_Name__c, Status__c FROM Weave_Scheduled_Send__c
            WHERE Id = :scheduledSendId WITH USER_MODE LIMIT 1
        ];
        if (rows.isEmpty()) throw new AuraHandledException('Scheduled send not found.');
        Weave_Scheduled_Send__c rec = rows[0];
        if (rec.Status__c != 'Pending') throw new AuraHandledException('Only Pending sends can be sent now.');
        if (String.isNotBlank(rec.Job_Name__c)) {
            List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :rec.Job_Name__c LIMIT 1];
            if (!jobs.isEmpty()) {
                try { System.abortJob(jobs[0].Id); } catch (Exception ignored) {}
            }
        }
        WeaveScheduledEmailJob job = new WeaveScheduledEmailJob(scheduledSendId);
        job.execute(null);
    }

    // ── Scheduler management ──────────────────────────────────────────────────

    private static final String WEAVE_EXECUTOR_JOB_NAME = 'Weave_Automated_Executor';

    public class SchedulerStatusDTO {
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String  jobId;
        @AuraEnabled public String  cronExpression;
        @AuraEnabled public String  nextFireTime;
        @AuraEnabled public String  frequency;
    }

    @AuraEnabled
    public static SchedulerStatusDTO getSchedulerStatus() {
        SchedulerStatusDTO dto = new SchedulerStatusDTO();
        dto.isActive = false;
        dto.jobId = null;
        dto.cronExpression = null;
        dto.nextFireTime = null;
        dto.frequency = null;
        List<CronTrigger> jobs = [
            SELECT Id, CronExpression, NextFireTime, State
            FROM CronTrigger
            WHERE CronJobDetail.Name = :WEAVE_EXECUTOR_JOB_NAME
            LIMIT 1
        ];
        if (!jobs.isEmpty()) {
            CronTrigger job = jobs[0];
            dto.isActive = (job.State == 'WAITING' || job.State == 'ACQUIRED' || job.State == 'EXECUTING');
            dto.jobId = job.Id;
            dto.cronExpression = job.CronExpression;
            dto.nextFireTime = job.NextFireTime != null ? String.valueOf(job.NextFireTime) : null;
            dto.frequency = cronToFrequencyLabel(job.CronExpression);
        }
        return dto;
    }

    @AuraEnabled
    public static SchedulerStatusDTO activateScheduler(String frequency) {
        try {
            // Abort any existing job first
            List<CronTrigger> existing = [
                SELECT Id FROM CronTrigger
                WHERE CronJobDetail.Name = :WEAVE_EXECUTOR_JOB_NAME LIMIT 1
            ];
            if (!existing.isEmpty()) {
                try { System.abortJob(existing[0].Id); } catch (Exception ignored) {}
            }
            String cronExpr = frequencyToCron(frequency);
            if (String.isBlank(cronExpr)) throw new AuraHandledException('Invalid frequency: ' + frequency);
            System.schedule(WEAVE_EXECUTOR_JOB_NAME, cronExpr, new WeaveScheduledEmailExecutor());
            return getSchedulerStatus();
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to activate scheduler: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deactivateScheduler() {
        try {
            List<CronTrigger> jobs = [
                SELECT Id FROM CronTrigger
                WHERE CronJobDetail.Name = :WEAVE_EXECUTOR_JOB_NAME LIMIT 1
            ];
            if (jobs.isEmpty()) throw new AuraHandledException('Scheduler is not currently active.');
            System.abortJob(jobs[0].Id);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to deactivate scheduler: ' + e.getMessage());
        }
    }

    private static String frequencyToCron(String frequency) {
        if (frequency == 'every_15_min')  return '0 0,15,30,45 * * * ?';
        if (frequency == 'every_30_min')  return '0 0,30 * * * ?';
        if (frequency == 'every_hour')    return '0 0 * * * ?';
        if (frequency == 'every_6_hours') return '0 0 0,6,12,18 * * ?';
        if (frequency == 'every_12_hours')return '0 0 0,12 * * ?';
        if (frequency == 'daily')         return '0 0 8 * * ?';
        return null;
    }

    private static String cronToFrequencyLabel(String cron) {
        if (cron == '0 0,15,30,45 * * * ?') return 'every_15_min';
        if (cron == '0 0,30 * * * ?')       return 'every_30_min';
        if (cron == '0 0 * * * ?')           return 'every_hour';
        if (cron == '0 0 0,6,12,18 * * ?')  return 'every_6_hours';
        if (cron == '0 0 0,12 * * ?')        return 'every_12_hours';
        if (cron == '0 0 8 * * ?')           return 'daily';
        return null;
    }

    // ── Data Sources (Phase 2) ────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<DataCloudConnectorService.ConnectorObject> getDataCloudConnectors() {
        try {
            return DataCloudConnectorService.getAvailableConnectors();
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load Data Cloud connectors: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<DataCloudConnectorService.ConnectorAttribute> getDataCloudAttributes(String objectApiName) {
        try {
            return DataCloudConnectorService.getAttributesForObject(objectApiName);
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load attributes for ' + objectApiName + ': ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<FlowVariableResolver.FlowSummary> getAvailableFlows() {
        try {
            return FlowVariableResolver.getAvailableFlows();
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load flows: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static MergeFieldValidator.ValidationResult validateTemplateMergeFields(
        String templateContent, String parentObjectApiName
    ) {
        try {
            return MergeFieldValidator.validateTemplate(templateContent, parentObjectApiName);
        } catch (Exception e) {
            throw new AuraHandledException('Validation error: ' + e.getMessage());
        }
    }
}
