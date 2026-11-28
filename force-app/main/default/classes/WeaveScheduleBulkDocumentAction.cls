@SuppressWarnings('PMD.ApexDoc')
public with sharing class WeaveScheduleBulkDocumentAction {

    public class ActionRequest {
        @InvocableVariable(label='Template ID' required=true)
        public Id templateId;

        @InvocableVariable(label='Output Type' description='Email, PDF, or Email + PDF')
        public String outputType;

        @InvocableVariable(label='Filter Clause' description='Optional SOQL WHERE clause to filter records')
        public String filterClause;

        @InvocableVariable(label='Scheduled Date/Time' description='ISO 8601 datetime string (e.g. 2026-12-01T09:00:00)')
        public String scheduledDateTime;
    }

    public class ActionResult {
        @InvocableVariable(label='Scheduled Send ID')
        public Id scheduledSendId;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Schedule Weave Bulk Send'
        description='Creates a scheduled bulk send record and queues the Weave batch for email, PDF, or both.'
        category='Dynamic Communication Engine'
    )
    public static List<ActionResult> scheduleBulkSend(List<ActionRequest> requests) {
        List<ActionResult> results = new List<ActionResult>();
        for (ActionRequest req : requests) {
            ActionResult res = new ActionResult();
            try {
                if (req.templateId == null) {
                    res.errorMessage = 'Template ID is required.';
                    results.add(res);
                    continue;
                }
                String outType = String.isBlank(req.outputType) ? 'Email' : req.outputType;

                Datetime scheduledDt;
                if (String.isBlank(req.scheduledDateTime)) {
                    scheduledDt = System.now().addMinutes(5);
                } else {
                    scheduledDt = (Datetime) JSON.deserialize('"' + req.scheduledDateTime + '"', Datetime.class);
                }
                if (scheduledDt <= System.now()) {
                    res.errorMessage = 'Scheduled time must be in the future.';
                    results.add(res);
                    continue;
                }

                Weave_Scheduled_Send__c rec = new Weave_Scheduled_Send__c(
                    Template__c      = req.templateId,
                    Status__c        = 'Pending',
                    Send_Type__c     = 'Bulk',
                    Output_Type__c   = outType,
                    Scheduled_At__c  = scheduledDt,
                    Filter_Clause__c = req.filterClause
                );
                insert as user rec;

                String jobName = 'WeaveSend_' + rec.Id + '_' + System.now().getTime();
                String cronStr = scheduledDt.second() + ' ' + scheduledDt.minute() + ' ' + scheduledDt.hour()
                    + ' ' + scheduledDt.day() + ' ' + scheduledDt.month() + ' ? ' + scheduledDt.year();
                System.schedule(jobName, cronStr, new WeaveScheduledEmailJob(rec.Id));

                rec.Job_Name__c = jobName;
                update as user rec;

                res.scheduledSendId = rec.Id;
            } catch (Exception e) {
                res.errorMessage = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }
}
