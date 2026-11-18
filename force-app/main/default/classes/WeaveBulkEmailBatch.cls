public with sharing class WeaveBulkEmailBatch
        implements Database.Batchable<SObject>, Database.Stateful {

    private final Id templateId;
    private final Id scheduledSendId;
    private final String objectApiName;
    private final String filterClause;

    private Integer targeted = 0;
    private Integer sent     = 0;
    private Integer failed   = 0;
    private String  errorDetail;

    public WeaveBulkEmailBatch(Id templateId, Id scheduledSendId,
                               String objectApiName, String filterClause) {
        this.templateId       = templateId;
        this.scheduledSendId  = scheduledSendId;
        this.objectApiName    = objectApiName;
        this.filterClause     = filterClause;
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
                return;
            }
        }

        for (SObject record : scope) {
            try {
                WeaveScheduledEmailJob.sendToRecord(templateId, record.Id);
                sent++;
            } catch (Exception e) {
                failed++;
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
}
