public with sharing class WeaveScheduledEmailJob implements Schedulable {

    private final Id scheduledSendId;

    public WeaveScheduledEmailJob(Id scheduledSendId) {
        this.scheduledSendId = scheduledSendId;
    }

    public void execute(SchedulableContext ctx) {
        Weave_Scheduled_Send__c record = loadRecord();
        if (record == null || record.Status__c == 'Cancelled') return;

        try {
            updateStatus(record.Id, 'Running', null, null, null, null);
            if (record.Send_Type__c == 'Bulk') {
                executeBulk(record);
            } else {
                executeIndividual(record);
            }
        } catch (Exception e) {
            updateStatus(record.Id, 'Failed', null, null, null, e.getMessage());
        }
    }

    private Weave_Scheduled_Send__c loadRecord() {
        List<Weave_Scheduled_Send__c> rows = [
            SELECT Id, Status__c, Send_Type__c, Template__c, Record_Id__c, Filter_Clause__c,
                   Batch_Size__c, Template__r.Parent_Object_API_Name__c
            FROM Weave_Scheduled_Send__c
            WHERE Id = :scheduledSendId
            WITH USER_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private void executeIndividual(Weave_Scheduled_Send__c record) {
        Id recId = record.Record_Id__c;
        sendToRecord(record.Template__c, recId);
        updateStatus(record.Id, 'Sent', 1, 1, 0, null);
    }

    private void executeBulk(Weave_Scheduled_Send__c record) {
        String objectApiName = record.Template__r.Parent_Object_API_Name__c;
        if (String.isBlank(objectApiName)) {
            updateStatus(record.Id, 'Failed', 0, 0, 0, 'Template has no parent object configured.');
            return;
        }
        Integer batchSize = record.Batch_Size__c != null ? record.Batch_Size__c.intValue() : 20;
        updateStatus(record.Id, 'Running', null, null, null, null);
        Database.executeBatch(
            new WeaveBulkEmailBatch(record.Template__c, record.Id, objectApiName, record.Filter_Clause__c),
            batchSize
        );
    }

    public static void sendToRecord(Id templateId, Id recId) {
        WeaveEmailTemplateRenderer.RenderedEmailDTO rendered =
            WeaveEmailTemplateRenderer.renderEmail(templateId, recId);

        List<RecipientOptionDTO> options =
            WeaveRecipientResolver.getRecipientOptions(templateId, recId);

        List<RecipientInputDTO> toList  = new List<RecipientInputDTO>();
        List<RecipientInputDTO> ccList  = new List<RecipientInputDTO>();
        List<RecipientInputDTO> bccList = new List<RecipientInputDTO>();

        for (RecipientOptionDTO opt : options) {
            if (opt.sourceType == 'Manual' || String.isBlank(opt.email)) continue;
            if (opt.required != true && opt.selected != true) continue;
            RecipientInputDTO r = new RecipientInputDTO(opt.name, opt.email, opt.recipientType);
            String rt = opt.recipientType != null ? opt.recipientType.toUpperCase() : 'TO';
            if (rt == 'CC') ccList.add(r);
            else if (rt == 'BCC') bccList.add(r);
            else toList.add(r);
        }

        GenericEmailSendRequest sendReq = new GenericEmailSendRequest();
        sendReq.templateId    = templateId;
        sendReq.recordId      = recId;
        sendReq.subject       = rendered.subject;
        sendReq.htmlBody      = rendered.htmlBody;
        sendReq.toRecipients  = toList;
        sendReq.ccRecipients  = ccList;
        sendReq.bccRecipients = bccList;
        WeaveEmailSendService.sendEmail(sendReq);
    }

    private static void updateStatus(Id recordId, String status, Integer targeted, Integer sent, Integer failed, String errorDetail) {
        Weave_Scheduled_Send__c upd = new Weave_Scheduled_Send__c(Id = recordId, Status__c = status);
        if (targeted != null) upd.Records_Targeted__c = targeted;
        if (sent    != null) upd.Records_Sent__c     = sent;
        if (failed  != null) upd.Records_Failed__c   = failed;
        if (errorDetail != null) upd.Error_Detail__c = errorDetail;
        try { update upd; } catch (Exception ignored) {}
    }
}
