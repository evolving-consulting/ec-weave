@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.NcssMethodCount,PMD.NcssTypeCount,PMD.NcssConstructorCount,PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.ApexDoc')
public with sharing class WeaveBulkEmailBatch
        implements Database.Batchable<SObject>, Database.Stateful {

    private final Id templateId;
    private final Id scheduledSendId;
    private final String objectApiName;
    private final String filterClause;
    private final String outputType;
    private final Id emailTemplateId;

    private Integer targeted = 0;
    private Integer sent     = 0;
    private Integer failed   = 0;
    private String  errorDetail;

    public WeaveBulkEmailBatch(Id templateId, Id scheduledSendId,
                               String objectApiName, String filterClause) {
        this(templateId, scheduledSendId, objectApiName, filterClause, 'Email', null);
    }

    public WeaveBulkEmailBatch(Id templateId, Id scheduledSendId,
                               String objectApiName, String filterClause, String outputType) {
        this(templateId, scheduledSendId, objectApiName, filterClause, outputType, null);
    }

    public WeaveBulkEmailBatch(Id templateId, Id scheduledSendId,
                               String objectApiName, String filterClause, String outputType, Id emailTemplateId) {
        this.templateId      = templateId;
        this.scheduledSendId = scheduledSendId;
        this.objectApiName   = objectApiName;
        this.filterClause    = filterClause;
        this.outputType      = String.isBlank(outputType) ? 'Email' : outputType;
        this.emailTemplateId = emailTemplateId;
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

        if ((outputType == 'Email' || outputType == 'Both') && dailyEmailLimitExceeded(scope.size())) {
            failed += scope.size();
            return;
        }

        for (SObject record : scope) {
            try {
                if (outputType == 'Email + PDF' && emailTemplateId != null) {
                    ContentVersion cv = WeavePdfService.generatePdf(templateId, record.Id);
                    WeaveEmailTemplateRenderer.RenderedEmailDTO rendered =
                        WeaveEmailTemplateRenderer.renderEmail(emailTemplateId, record.Id, false);
                    List<RecipientOptionDTO> options =
                        WeaveRecipientResolver.getRecipientOptions(emailTemplateId, record.Id);
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
                    GenericEmailSendRequest req = new GenericEmailSendRequest();
                    req.templateId           = emailTemplateId;
                    req.recordId             = record.Id;
                    req.subject              = rendered.subject;
                    req.htmlBody             = rendered.htmlBody;
                    req.toRecipients         = toList;
                    req.ccRecipients         = ccList;
                    req.bccRecipients        = bccList;
                    req.attachmentContentDocumentIds = new List<Id>{ cv.ContentDocumentId };
                    WeaveEmailSendService.sendEmail(req);
                } else {
                    if (outputType == 'Email' || outputType == 'Both') {
                        WeaveScheduledEmailJob.sendToRecord(templateId, record.Id);
                    }
                    if (outputType == 'PDF' || outputType == 'Both') {
                        WeavePdfService.generatePdf(templateId, record.Id);
                    }
                }
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

    private Boolean dailyEmailLimitExceeded(Integer batchSize) {
        OrgLimit emailLimit = OrgLimits.getMap().get('SingleEmail');
        if (emailLimit == null) return false;
        Integer remaining = emailLimit.getLimit() - emailLimit.getValue();
        if (remaining >= batchSize) return false;
        errorDetail = 'Stopped: org daily email limit nearly reached (' + remaining + ' remaining).';
        return true;
    }
}
