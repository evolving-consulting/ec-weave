/**
 * Sends a rendered Weave template as a transactional email via Marketing Cloud Next.
 * Calls SfmcHttpClient (Phase 1) to invoke the MCN send endpoint and logs the
 * result to Weave_MCN_Email_Send__c.
 *
 * MCN send endpoint (via Named Credential MCN_API):
 *   POST /messaging/v1/email/messages
 *   Body: { "definitionKey": "<mcnDefinitionKey>", "recipient": { "address": "...", "attributes": {...} } }
 */
public with sharing class MCNEmailSendService {

    @TestVisible
    private static final String MCN_SEND_ENDPOINT = '/messaging/v1/email/messages';

    // ── Public API ────────────────────────────────────────────────────────────

    public class SendRequest {
        public Id      templateId       { get; set; }
        public String  recipientEmail   { get; set; }
        public String  contextDataJson  { get; set; }
    }

    public class SendResult {
        @AuraEnabled public Boolean isSuccess    { get; private set; }
        @AuraEnabled public String  messageId    { get; private set; }
        @AuraEnabled public String  status       { get; private set; }
        @AuraEnabled public String  errorMessage { get; private set; }

        public SendResult(String messageId) {
            this.isSuccess = true;
            this.messageId = messageId;
            this.status    = 'Sent';
        }

        public SendResult(String status, String error) {
            this.isSuccess    = false;
            this.status       = status;
            this.errorMessage = error;
        }
    }

    /**
     * Renders the template, sends via MCN, and logs the result.
     */
    public static SendResult sendEmail(Id templateId, String recipientEmail, String contextDataJson) {
        Id logId = createPendingLog(templateId, recipientEmail, contextDataJson);
        try {
            validateInputs(templateId, recipientEmail);

            MCNTemplateRenderService.RenderResult rendered =
                MCNTemplateRenderService.resolveTemplate(templateId, contextDataJson);
            if (!rendered.isSuccess) {
                return failAndLog(logId, 'Failed', 'Template render failed: ' + rendered.errorMessage);
            }

            String mcnDefinitionKey = resolveDefinitionKey(templateId);
            String payload = buildPayload(mcnDefinitionKey, recipientEmail, rendered, contextDataJson);

            SfmcHttpClient client = new SfmcHttpClient();
            SfmcHttpClient.McnResponse response = client.post(MCN_SEND_ENDPOINT, payload);

            if (!response.isSuccess) {
                return failAndLog(logId, 'Failed', response.errorMessage);
            }

            String messageId = extractMessageId(response);
            updateLog(logId, 'Sent', messageId, null);
            return new SendResult(messageId);

        } catch (Exception e) {
            return failAndLog(logId, 'Failed', e.getMessage());
        }
    }

    // ── Validation ────────────────────────────────────────────────────────────

    private static void validateInputs(Id templateId, String recipientEmail) {
        if (templateId == null) throw new IllegalArgumentException('templateId is required.');
        if (String.isBlank(recipientEmail)) throw new IllegalArgumentException('recipientEmail is required.');
        if (!Pattern.matches('^[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}$',
                             recipientEmail.toUpperCase())) {
            throw new IllegalArgumentException('recipientEmail is not a valid email address.');
        }
    }

    // ── Payload builder ───────────────────────────────────────────────────────

    private static String resolveDefinitionKey(Id templateId) {
        List<Weave_Template_Config__c> templates = [
            SELECT SFMC_Template_ID__c
            FROM Weave_Template_Config__c
            WHERE Id = :templateId
            WITH USER_MODE
            LIMIT 1
        ];
        if (!templates.isEmpty() && String.isNotBlank(templates[0].SFMC_Template_ID__c)) {
            return templates[0].SFMC_Template_ID__c;
        }
        // Fall back to Salesforce record ID as definition key
        return String.valueOf(templateId);
    }

    private static String buildPayload(
        String definitionKey,
        String recipientEmail,
        MCNTemplateRenderService.RenderResult rendered,
        String contextDataJson
    ) {
        Map<String, Object> recipientAttrs = new Map<String, Object>();
        recipientAttrs.put('Subject', rendered.subject);

        Map<String, Object> recipient = new Map<String, Object>{
            'address'    => recipientEmail,
            'attributes' => recipientAttrs
        };

        Map<String, Object> body = new Map<String, Object>{
            'definitionKey' => definitionKey,
            'recipient'     => recipient
        };

        return JSON.serialize(body);
    }

    private static String extractMessageId(SfmcHttpClient.McnResponse response) {
        Map<String, Object> bodyMap = response.bodyAsMap();
        Object msgId = bodyMap.get('requestId');
        if (msgId == null) msgId = bodyMap.get('messageId');
        return msgId != null ? String.valueOf(msgId) : null;
    }

    // ── Send log helpers ─────────────────────────────────────────────────────

    private static Id createPendingLog(Id templateId, String recipientEmail, String contextDataJson) {
        try {
            Weave_MCN_Email_Send__c log = new Weave_MCN_Email_Send__c(
                Template__c       = templateId,
                Recipient_Email__c = recipientEmail,
                Context_Data__c   = contextDataJson != null && contextDataJson.length() > 131072
                                    ? contextDataJson.left(131072) : contextDataJson,
                Send_Status__c    = 'Pending'
            );
            insert log;
            return log.Id;
        } catch (Exception e) {
            return null;
        }
    }

    private static void updateLog(Id logId, String status, String messageId, String error) {
        if (logId == null) return;
        try {
            Weave_MCN_Email_Send__c log = new Weave_MCN_Email_Send__c(
                Id              = logId,
                Send_Status__c  = status,
                MCN_Message_ID__c = messageId,
                Error_Message__c  = error,
                Sent_DateTime__c  = status == 'Sent' ? System.now() : null
            );
            update log;
        } catch (Exception e) {
            // Log update failure should not surface to caller
        }
    }

    private static SendResult failAndLog(Id logId, String status, String error) {
        updateLog(logId, status, null, error);
        return new SendResult(status, error);
    }
}
