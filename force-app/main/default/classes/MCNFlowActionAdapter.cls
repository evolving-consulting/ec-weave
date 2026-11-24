/**
 * Custom Flow action: "Send Weave Template via MCN"
 * Category: Dynamic Communication Engine
 *
 * Can be called from any Flow type (record-triggered, screen, scheduled).
 * Input params: templateId, recipientEmail, contextVariablesJson
 * Outputs: isSuccess, messageId, errorMessage
 */
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
        List<SendResult> results = new List<SendResult>();

        for (SendRequest req : requests) {
            SendResult res = new SendResult();
            try {
                MCNEmailSendService.SendResult svcResult =
                    MCNEmailSendService.sendEmail(req.templateId, req.recipientEmail, req.contextVariablesJson);

                res.isSuccess    = svcResult.isSuccess;
                res.messageId    = svcResult.messageId;
                res.sendStatus   = svcResult.status;
                res.errorMessage = svcResult.errorMessage;
            } catch (Exception e) {
                res.isSuccess    = false;
                res.sendStatus   = 'Failed';
                res.errorMessage = e.getMessage();
            }
            results.add(res);
        }

        return results;
    }
}
