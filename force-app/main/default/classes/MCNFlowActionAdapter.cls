/**
 * Custom Flow action: "Send Weave Template via MCN"
 * Category: Dynamic Communication Engine
 *
 * Can be called from any Flow type (record-triggered, screen, scheduled).
 * Input params: templateId, recipientEmail, contextVariablesJson
 * Outputs: isSuccess, messageId, errorMessage
 */
@SuppressWarnings('PMD.ApexDoc')
public with sharing class MCNFlowActionAdapter {

    public class SendRequest {
        @InvocableVariable(label='Template ID' description='Weave_Template_Config__c record ID' required=true)
        public Id templateId;

        @InvocableVariable(label='Recipient Email' description='Email address to send to' required=true)
        public String recipientEmail;

        @InvocableVariable(label='Context Variables (JSON)' description='JSON object with recordId, flowVariables, dataCloudValues')
        public String contextVariablesJson;
    }

    public class SendResult {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;

        @InvocableVariable(label='MCN Message ID')
        public String messageId;

        @InvocableVariable(label='Send Status')
        public String sendStatus;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Send Weave MCN Email'
        description='Renders a Weave template and sends it via Marketing Cloud Next'
        category='Dynamic Communication Engine'
    )
    public static List<SendResult> sendEmail(List<SendRequest> requests) {
        List<Id>     templateIds = new List<Id>();
        List<String> emails      = new List<String>();
        List<String> contexts    = new List<String>();

        for (SendRequest req : requests) {
            templateIds.add(req.templateId);
            emails.add(req.recipientEmail);
            contexts.add(req.contextVariablesJson);
        }

        List<MCNEmailSendService.SendResult> svcResults =
            MCNEmailSendService.sendBulk(templateIds, emails, contexts);

        List<SendResult> results = new List<SendResult>();
        for (MCNEmailSendService.SendResult svc : svcResults) {
            SendResult res = new SendResult();
            res.isSuccess    = svc.isSuccess;
            res.messageId    = svc.messageId;
            res.sendStatus   = svc.status;
            res.errorMessage = svc.errorMessage;
            results.add(res);
        }
        return results;
    }
}
