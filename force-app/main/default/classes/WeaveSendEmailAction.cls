/**
 * Invocable Apex action for sending a Weave email from a Flow without any UI.
 * Pass a templateId and recordId; the action resolves recipients from the
 * template configuration and renders the email automatically.
 *
 * Usage: Flow Action element → category "Dynamic Communication Engine" → "Send Weave Email"
 */
public with sharing class WeaveSendEmailAction {

    public class SendRequest {
        @InvocableVariable(label='Template Id' required=true description='The Weave_Template_Config__c to send.')
        public Id templateId;

        @InvocableVariable(label='Record Id' required=true description='The source record used for rendering and post-send actions.')
        public Id recordId;
    }

    public class SendResult {
        @InvocableVariable(label='Success' description='True when the email was sent successfully.')
        public Boolean success;

        @InvocableVariable(label='Error Message' description='Populated when success is false. Use on a Fault path to surface the reason.')
        public String errorMessage;

        @InvocableVariable(label='Warnings' description='Semicolon-separated non-fatal warnings (e.g. failed post-send actions).')
        public String warnings;
    }

    @InvocableMethod(
        label='Send Weave Email'
        description='Sends a Weave email from a record without any UI interaction. Use in Record-Triggered or Scheduled Flows.'
        category='Dynamic Communication Engine'
    )
    public static List<SendResult> sendEmail(List<SendRequest> requests) {
        List<SendResult> results = new List<SendResult>();
        for (SendRequest req : requests) {
            results.add(processSend(req));
        }
        return results;
    }

    private static SendResult processSend(SendRequest req) {
        SendResult result = new SendResult();
        try {
            // Render the template content (works for both editable and non-editable templates)
            WeaveEmailTemplateRenderer.RenderedEmailDTO rendered =
                WeaveEmailTemplateRenderer.renderEmail(req.templateId, req.recordId);

            // Resolve template-defined recipients; skip Manual type (no address to resolve)
            List<RecipientOptionDTO> options =
                WeaveRecipientResolver.getRecipientOptions(req.templateId, req.recordId);

            List<RecipientInputDTO> toList  = new List<RecipientInputDTO>();
            List<RecipientInputDTO> ccList  = new List<RecipientInputDTO>();
            List<RecipientInputDTO> bccList = new List<RecipientInputDTO>();

            for (RecipientOptionDTO opt : options) {
                if (opt.sourceType == 'Manual' || String.isBlank(opt.email)) continue;
                if (opt.required != true && opt.selected != true) continue;

                RecipientInputDTO r = new RecipientInputDTO(opt.name, opt.email, opt.recipientType);
                String rt = opt.recipientType != null ? opt.recipientType.toUpperCase() : 'TO';

                if (rt == 'CC') {
                    ccList.add(r);
                } else if (rt == 'BCC') {
                    bccList.add(r);
                } else {
                    toList.add(r);
                }
            }

            GenericEmailSendRequest sendReq = new GenericEmailSendRequest();
            sendReq.templateId   = req.templateId;
            sendReq.recordId     = req.recordId;
            sendReq.subject      = rendered.subject;
            sendReq.htmlBody     = rendered.htmlBody;
            sendReq.toRecipients  = toList;
            sendReq.ccRecipients  = ccList;
            sendReq.bccRecipients = bccList;

            DceEmailSendResultDTO sendResult = WeaveEmailSendService.sendEmail(sendReq);
            result.success = sendResult.success;
            if (sendResult.warnings != null && !sendResult.warnings.isEmpty()) {
                result.warnings = String.join(sendResult.warnings, '; ');
            }

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }
}
