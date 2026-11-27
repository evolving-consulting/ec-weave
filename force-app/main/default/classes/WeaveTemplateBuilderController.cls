@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces')
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
    public static Id createScheduledSend(Id templateId, String scheduledDateTime, String sendType, Id recordId, String filterClause, String outputType) {
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
            Template__c      = templateId,
            Status__c        = 'Pending',
            Send_Type__c     = sendType,
            Output_Type__c   = String.isBlank(outputType) ? 'Email' : outputType,
            Scheduled_At__c  = scheduledDt,
            Record_Id__c     = recordId != null ? String.valueOf(recordId) : null,
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
            SELECT Id, Name, Status__c, Send_Type__c, Output_Type__c, Scheduled_At__c,
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
            dto.outputType      = r.Output_Type__c;
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

    // ── Bulk Send ─────────────────────────────────────────────────────────────

    @AuraEnabled
    public static List<WeaveBuilderDTOs.WeaveScheduledSendDTO> getBulkSends() {
        List<Weave_Scheduled_Send__c> rows = [
            SELECT Id, Name, Status__c, Send_Type__c, Output_Type__c, Scheduled_At__c,
                   Filter_Clause__c, Filter_Conditions__c, Job_Name__c,
                   Template__c, Template__r.Name, Template__r.Parent_Object_API_Name__c,
                   Email_Template__c, Email_Template__r.Name,
                   Records_Targeted__c, Records_Sent__c, Records_Failed__c, Error_Detail__c
            FROM Weave_Scheduled_Send__c
            WHERE Send_Type__c IN ('Bulk', 'Recurring') AND Record_Id__c = null
            WITH USER_MODE
            ORDER BY Scheduled_At__c DESC
            LIMIT 500
        ];
        List<WeaveBuilderDTOs.WeaveScheduledSendDTO> result = new List<WeaveBuilderDTOs.WeaveScheduledSendDTO>();
        for (Weave_Scheduled_Send__c r : rows) {
            WeaveBuilderDTOs.WeaveScheduledSendDTO dto = new WeaveBuilderDTOs.WeaveScheduledSendDTO();
            dto.id                = r.Id;
            dto.name              = r.Name;
            dto.status            = r.Status__c;
            dto.sendType          = r.Send_Type__c;
            dto.outputType        = r.Output_Type__c;
            dto.scheduledAt       = r.Scheduled_At__c != null ? String.valueOf(r.Scheduled_At__c) : null;
            dto.filterClause      = r.Filter_Clause__c;
            dto.filterConditions  = r.Filter_Conditions__c;
            dto.jobName           = r.Job_Name__c;
            dto.emailTemplateId   = r.Email_Template__c;
            dto.emailTemplateName = r.Email_Template__r?.Name;
            dto.templateName      = r.Template__r?.Name;
            dto.objectApiName     = r.Template__r?.Parent_Object_API_Name__c;
            dto.recordsTargeted   = r.Records_Targeted__c != null ? Integer.valueOf(r.Records_Targeted__c) : null;
            dto.recordsSent       = r.Records_Sent__c != null ? Integer.valueOf(r.Records_Sent__c) : null;
            dto.recordsFailed     = r.Records_Failed__c != null ? Integer.valueOf(r.Records_Failed__c) : null;
            dto.errorDetail       = r.Error_Detail__c;
            result.add(dto);
        }
        return result;
    }

    @AuraEnabled
    public static Integer countBulkSendRecords(String objectApiName, String filterConditionsJson) {
        if (String.isBlank(objectApiName)) throw new AuraHandledException('Object API name is required.');
        if (Schema.getGlobalDescribe().get(objectApiName) == null) {
            throw new AuraHandledException('Unknown object: ' + objectApiName);
        }
        try {
            String whereClause = WeaveFilterConditionBuilder.buildClause(objectApiName, filterConditionsJson);
            String soql = 'SELECT count() FROM ' + objectApiName;
            List<String> conditions = new List<String>();
            if (String.isNotBlank(whereClause)) conditions.add(whereClause);
            if (objectApiName == 'Contact' || objectApiName == 'Lead') conditions.add('HasOptedOutOfEmail = false');
            if (!conditions.isEmpty()) soql += ' WHERE ' + String.join(conditions, ' AND ');
            soql += ' WITH USER_MODE';
            return Database.countQuery(soql);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not count records: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Id createBulkSend(String bulkSendJson) {
        WeaveBuilderDTOs.WeaveBulkSendDTO req;
        try {
            req = (WeaveBuilderDTOs.WeaveBulkSendDTO) JSON.deserialize(bulkSendJson, WeaveBuilderDTOs.WeaveBulkSendDTO.class);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid bulk send data.');
        }
        try {
        if (req.templateId == null) throw new AuraHandledException('Template is required.');

        Boolean isRecurring = req.scheduleMode == 'recurring';

        List<Weave_Template_Config__c> tmplRows = [
            SELECT Id, Parent_Object_API_Name__c, Name FROM Weave_Template_Config__c
            WHERE Id = :req.templateId WITH USER_MODE LIMIT 1
        ];
        if (tmplRows.isEmpty()) throw new AuraHandledException('Template not found.');
        String objectApiName = tmplRows[0].Parent_Object_API_Name__c;

        String filterClause = null;
        try {
            filterClause = WeaveFilterConditionBuilder.buildClause(objectApiName, req.filterConditionsJson);
        } catch (Exception e) {
            throw new AuraHandledException('Filter error: ' + e.getMessage());
        }

        if (isRecurring) {
            if (String.isBlank(req.recurringConfigJson)) throw new AuraHandledException('Recurring configuration is required.');
            WeaveRecurringEmailJob.RecurringConfig config = WeaveRecurringEmailJob.parseConfig(req.recurringConfigJson);
            if (config == null) throw new AuraHandledException('Invalid recurring configuration.');
            if (config.daysOfWeek == null || config.daysOfWeek.isEmpty()) throw new AuraHandledException('Select at least one day of the week.');
            if (String.isBlank(config.startDate)) throw new AuraHandledException('Start date is required.');
            config.filterClause = filterClause;
            String configJson = JSON.serialize(config);

            Datetime firstOccurrence = WeaveRecurringEmailJob.getFirstOccurrence(config);
            if (firstOccurrence == null) throw new AuraHandledException('No upcoming occurrence found for the selected days and start date.');

            Weave_Scheduled_Send__c rec = new Weave_Scheduled_Send__c(
                Template__c          = req.templateId,
                Email_Template__c    = req.emailTemplateId,
                Status__c            = 'Pending',
                Send_Type__c         = 'Recurring',
                Output_Type__c       = String.isBlank(req.outputType) ? 'Email' : req.outputType,
                Scheduled_At__c      = firstOccurrence,
                Filter_Conditions__c = req.filterConditionsJson,
                Filter_Clause__c     = filterClause,
                Recurring_Config__c  = configJson,
                Batch_Size__c        = req.batchSize != null ? req.batchSize : 20,
                Job_Name__c          = 'Recurring Bulk: ' + tmplRows[0].Name
            );
            insert rec;
            String cron = WeaveRecurringEmailJob.buildCron(firstOccurrence);
            System.schedule('WeaveRecurring-' + rec.Id, cron, new WeaveRecurringEmailJob(rec.Id));
            return rec.Id;
        }

        if (String.isBlank(req.scheduledAt)) throw new AuraHandledException('Scheduled time is required.');
        Datetime scheduledDt;
        try {
            String isoStr = req.scheduledAt;
            if (isoStr.length() == 16) isoStr += ':00';
            String[] dtParts = isoStr.split('T');
            String[] timeParts = dtParts[1].split(':');
            Date d = Date.valueOf(dtParts[0]);
            scheduledDt = Datetime.newInstance(d,
                Time.newInstance(Integer.valueOf(timeParts[0]), Integer.valueOf(timeParts[1]),
                    timeParts.size() > 2 ? Integer.valueOf(timeParts[2]) : 0, 0));
        } catch (Exception e) {
            throw new AuraHandledException('Invalid scheduled date/time format.');
        }
        if (scheduledDt <= System.now()) throw new AuraHandledException('Scheduled time must be in the future.');

        Weave_Scheduled_Send__c rec = new Weave_Scheduled_Send__c(
            Template__c           = req.templateId,
            Email_Template__c     = req.emailTemplateId,
            Status__c             = 'Pending',
            Send_Type__c          = 'Bulk',
            Output_Type__c        = String.isBlank(req.outputType) ? 'Email' : req.outputType,
            Scheduled_At__c       = scheduledDt,
            Filter_Conditions__c  = req.filterConditionsJson,
            Filter_Clause__c      = filterClause,
            Batch_Size__c         = req.batchSize != null ? req.batchSize : 20
        );
        insert rec;

        String jobName = 'WeaveBulk_' + rec.Id + '_' + System.now().getTime();
        String cronStr = scheduledDt.second() + ' ' + scheduledDt.minute() + ' ' + scheduledDt.hour()
            + ' ' + scheduledDt.day() + ' ' + scheduledDt.month() + ' ? ' + scheduledDt.year();
        System.schedule(jobName, cronStr, new WeaveScheduledEmailJob(rec.Id));
        rec.Job_Name__c = jobName;
        update rec;
        return rec.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Could not schedule bulk send: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static List<WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO> getActiveEmailTemplates() {
        List<Weave_Template_Config__c> rows = [
            SELECT Id, Name, API_Name__c, Status__c, Parent_Object_API_Name__c,
                   Description__c, LastModifiedDate, Brand__c, Brand__r.Name, Template_Output_Type__c
            FROM Weave_Template_Config__c
            WHERE Status__c = 'Active' AND Template_Output_Type__c = 'Email'
            WITH USER_MODE
            ORDER BY Name
            LIMIT 500
        ];
        List<WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO> result = new List<WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO>();
        for (Weave_Template_Config__c r : rows) {
            WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO();
            dto.id                  = r.Id;
            dto.name                = r.Name;
            dto.apiName             = r.API_Name__c;
            dto.status              = r.Status__c;
            dto.parentObjectApiName = r.Parent_Object_API_Name__c;
            dto.description         = r.Description__c;
            dto.lastModifiedDate    = r.LastModifiedDate;
            dto.brandId             = r.Brand__c;
            dto.brandName           = r.Brand__c != null ? r.Brand__r.Name : null;
            dto.templateOutputType  = r.Template_Output_Type__c;
            result.add(dto);
        }
        return result;
    }

    // ── Scheduler management ──────────────────────────────────────────────────

    private static final String WEAVE_EXECUTOR_JOB_PREFIX = 'Weave_Automated_Executor';

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
        String likePattern = WEAVE_EXECUTOR_JOB_PREFIX + '%';
        List<CronTrigger> jobs = [
            SELECT Id, CronExpression, NextFireTime, State
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :likePattern
            ORDER BY CronExpression
        ];
        if (!jobs.isEmpty()) {
            Boolean anyActive = false;
            for (CronTrigger j : jobs) {
                if (j.State == 'WAITING' || j.State == 'ACQUIRED' || j.State == 'EXECUTING') {
                    anyActive = true; break;
                }
            }
            dto.isActive = anyActive;
            dto.jobId = jobs[0].Id;
            dto.cronExpression = jobs[0].CronExpression;
            dto.nextFireTime = jobs[0].NextFireTime != null ? String.valueOf(jobs[0].NextFireTime) : null;
            dto.frequency = detectFrequency(jobs);
        }
        return dto;
    }

    private static String detectFrequency(List<CronTrigger> jobs) {
        Integer cnt = jobs.size();
        if (cnt == 12) return 'every_5_min';
        if (cnt == 6)  return 'every_10_min';
        if (cnt == 4)  return 'every_15_min';
        if (cnt == 2)  return 'every_30_min';
        if (cnt == 1)  return cronToFrequencyLabel(jobs[0].CronExpression);
        return null;
    }

    @AuraEnabled
    public static SchedulerStatusDTO activateScheduler(String frequency) {
        try {
            String likePattern = WEAVE_EXECUTOR_JOB_PREFIX + '%';
            List<CronTrigger> existing = [
                SELECT Id FROM CronTrigger
                WHERE CronJobDetail.Name LIKE :likePattern
            ];
            for (CronTrigger ct : existing) {
                try { System.abortJob(ct.Id); } catch (Exception ignored) {}
            }
            List<String> crons = frequencyToCrons(frequency);
            if (crons.isEmpty()) throw new AuraHandledException('Invalid frequency: ' + frequency);
            for (Integer i = 0; i < crons.size(); i++) {
                String jobName = crons.size() == 1
                    ? WEAVE_EXECUTOR_JOB_PREFIX
                    : WEAVE_EXECUTOR_JOB_PREFIX + '_' + i;
                System.schedule(jobName, crons[i], new WeaveScheduledEmailExecutor());
            }
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
            String likePattern = WEAVE_EXECUTOR_JOB_PREFIX + '%';
            List<CronTrigger> jobs = [
                SELECT Id FROM CronTrigger
                WHERE CronJobDetail.Name LIKE :likePattern
            ];
            if (jobs.isEmpty()) throw new AuraHandledException('Scheduler is not currently active.');
            for (CronTrigger ct : jobs) {
                try { System.abortJob(ct.Id); } catch (Exception ignored) {}
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to deactivate scheduler: ' + e.getMessage());
        }
    }

    private static List<String> frequencyToCrons(String frequency) {
        List<String> crons = new List<String>();
        if (frequency == 'every_5_min') {
            for (Integer m = 0; m < 60; m += 5)  crons.add('0 ' + m + ' * * * ?');
        } else if (frequency == 'every_10_min') {
            for (Integer m = 0; m < 60; m += 10) crons.add('0 ' + m + ' * * * ?');
        } else if (frequency == 'every_15_min') {
            for (Integer m = 0; m < 60; m += 15) crons.add('0 ' + m + ' * * * ?');
        } else if (frequency == 'every_30_min') {
            crons.add('0 0 * * * ?');
            crons.add('0 30 * * * ?');
        } else if (frequency == 'every_hour') {
            crons.add('0 0 * * * ?');
        } else if (frequency == 'every_6_hours') {
            crons.add('0 0 0,6,12,18 * * ?');
        } else if (frequency == 'every_12_hours') {
            crons.add('0 0 0,12 * * ?');
        } else if (frequency == 'daily') {
            crons.add('0 0 8 * * ?');
        }
        return crons;
    }

    private static String cronToFrequencyLabel(String cron) {
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
