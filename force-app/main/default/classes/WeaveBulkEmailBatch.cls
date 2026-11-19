public with sharing class WeaveBulkEmailBatch
        implements Database.Batchable<SObject>, Database.Stateful {

    private final Id templateId;
    private final Id scheduledSendId;
    private final String objectApiName;
    private final String filterClause;
    private final Map<String, Id> recordIdToRetryOfLogId;

    private Integer targeted = 0;
    private Integer sent     = 0;
    private Integer failed   = 0;
    private String  errorDetail;

    public WeaveBulkEmailBatch(Id templateId, Id scheduledSendId,
                               String objectApiName, String filterClause) {
        this(templateId, scheduledSendId, objectApiName, filterClause, null);
    }

    public WeaveBulkEmailBatch(Id templateId, Id scheduledSendId,
                               String objectApiName, String filterClause,
                               Map<String, Id> recordIdToRetryOfLogId) {
        this.templateId              = templateId;
        this.scheduledSendId         = scheduledSendId;
        this.objectApiName           = objectApiName;
        this.filterClause            = filterClause;
        this.recordIdToRetryOfLogId  = recordIdToRetryOfLogId;
    }

    @SuppressWarnings('PMD.ApexSOQLInjection')
    public Database.QueryLocator start(Database.BatchableContext ctx) {
        String soql = 'SELECT Id FROM ' + objectApiName;
        List<String> conditions = new List<String>();
        if (String.isNotBlank(filterClause)) conditions.add(filterClause);
        if (objectApiName == 'Contact' || objectApiName == 'Lead') {
            conditions.add('HasOptedOutOfEmail = false');
        }
        if (!conditions.isEmpty()) soql += ' WHERE ' + String.join(conditions, ' AND ');
        soql += ' WITH USER_MODE';
        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext ctx, List<SObject> scope) {
        targeted += scope.size();

        OrgLimit emailLimit = OrgLimits.getMap().get('SingleEmail');
        if (emailLimit != null) {
            Integer remaining = emailLimit.getLimit() - emailLimit.getValue();
            if (remaining < scope.size()) {
                failed += scope.size();
                errorDetail = 'Stopped: org daily email limit nearly reached (' + remaining + ' remaining).';
                for (SObject record : scope) {
                    Id retryOfId = getRetryOfLogId(record.Id);
                    WeaveEmailSendService.logFailedSend(templateId, record.Id, scheduledSendId, retryOfId);
                }
                return;
            }
        }

        for (SObject record : scope) {
            Id retryOfId = getRetryOfLogId(record.Id);
            try {
                WeaveScheduledEmailJob.sendToRecord(templateId, record.Id, scheduledSendId, retryOfId);
                sent++;
            } catch (Exception e) {
                failed++;
                WeaveEmailSendService.logFailedSend(templateId, record.Id, scheduledSendId, retryOfId);
            }
        }
    }

    public void finish(Database.BatchableContext ctx) {
        String status = failed == 0 ? 'Sent' : (sent == 0 ? 'Failed' : 'Partial');
        Weave_Scheduled_Send__c upd = new Weave_Scheduled_Send__c(
            Id                  = scheduledSendId,
            Status__c           = status,
            Records_Targeted__c = targeted,
            Records_Sent__c     = sent,
            Records_Failed__c   = failed
        );
        if (errorDetail != null) upd.Error_Detail__c = errorDetail;
        try { update upd; } catch (Exception ignored) {}
    }

    private Id getRetryOfLogId(Id recordId) {
        if (recordIdToRetryOfLogId == null || recordId == null) return null;
        return recordIdToRetryOfLogId.get(String.valueOf(recordId));
    }
}
