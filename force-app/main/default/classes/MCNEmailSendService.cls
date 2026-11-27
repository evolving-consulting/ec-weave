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
     * DML is deferred until after the callout to avoid "uncommitted work pending" errors.
     */
    @AuraEnabled
    public static SendResult sendEmail(Id templateId, String recipientEmail, String contextDataJson) {
        try {
            validateInputs(templateId, recipientEmail);

            MCNTemplateRenderService.RenderResult rendered =
                MCNTemplateRenderService.resolveTemplate(templateId, contextDataJson);
            if (!rendered.isSuccess) {
                String err = 'Template render failed: ' + rendered.errorMessage;
                createLog(templateId, recipientEmail, contextDataJson, 'Failed', null, err);
                return new SendResult('Failed', err);
            }

            String mcnDefinitionKey = resolveDefinitionKey(templateId);
            String payload = buildPayload(mcnDefinitionKey, recipientEmail, rendered, contextDataJson);

            SfmcHttpClient client = new SfmcHttpClient();
            SfmcHttpClient.McnResponse response = client.post(MCN_SEND_ENDPOINT, payload);

            if (!response.isSuccess) {
                createLog(templateId, recipientEmail, contextDataJson, 'Failed', null, response.errorMessage);
                return new SendResult('Failed', response.errorMessage);
            }

            String messageId = extractMessageId(response);
            createLog(templateId, recipientEmail, contextDataJson, 'Sent', messageId, null);
            return new SendResult(messageId);

        } catch (Exception e) {
            createLog(templateId, recipientEmail, contextDataJson, 'Failed', null, e.getMessage());
            return new SendResult('Failed', e.getMessage());
        }
    }

    /**
     * Bulkified send — 1 SOQL + 1 DML regardless of list size.
     * All callouts run before the single bulk-insert, avoiding "uncommitted work pending".
     * Used by MCNFlowActionAdapter to stay within governor limits.
     */
    public static List<SendResult> sendBulk(List<Id> templateIds, List<String> emails, List<String> contexts) {
        Integer size = templateIds.size();

        // Bulk-resolve definition keys (1 SOQL for all unique templates)
        Map<Id, String> defKeyByTemplateId = resolveDefinitionKeys(new Set<Id>(templateIds));

        // Render + callout per record (no DML)
        List<SendResult>              results      = new List<SendResult>();
        List<Weave_MCN_Email_Send__c> logsToInsert = new List<Weave_MCN_Email_Send__c>();

        for (Integer i = 0; i < size; i++) {
            SendResult res;
            Weave_MCN_Email_Send__c logRec = new Weave_MCN_Email_Send__c(
                Template__c        = templateIds.get(i),
                Recipient_Email__c = emails.get(i),
                Context_Data__c    = truncate(contexts.get(i))
            );
            try {
                validateInputs(templateIds.get(i), emails.get(i));
                MCNTemplateRenderService.RenderResult rendered =
                    MCNTemplateRenderService.resolveTemplate(templateIds.get(i), contexts.get(i));
                if (!rendered.isSuccess) {
                    logRec.Send_Status__c   = 'Failed';
                    logRec.Error_Message__c = 'Render failed: ' + rendered.errorMessage;
                    res = new SendResult('Failed', logRec.Error_Message__c);
                } else {
                    String defKey  = defKeyByTemplateId.get(templateIds.get(i));
                    String payload = buildPayload(defKey, emails.get(i), rendered, contexts.get(i));
                    SfmcHttpClient client = new SfmcHttpClient();
                    SfmcHttpClient.McnResponse resp = client.post(MCN_SEND_ENDPOINT, payload);
                    if (!resp.isSuccess) {
                        logRec.Send_Status__c   = 'Failed';
                        logRec.Error_Message__c = resp.errorMessage;
                        res = new SendResult('Failed', resp.errorMessage);
                    } else {
                        String msgId = extractMessageId(resp);
                        logRec.Send_Status__c    = 'Sent';
                        logRec.MCN_Message_ID__c = msgId;
                        logRec.Sent_DateTime__c  = System.now();
                        res = new SendResult(msgId);
                    }
                }
            } catch (Exception e) {
                logRec.Send_Status__c   = 'Failed';
                logRec.Error_Message__c = e.getMessage();
                res = new SendResult('Failed', e.getMessage());
            }
            logsToInsert.add(logRec);
            results.add(res);
        }

        // Single bulk insert after all callouts (1 DML)
        try { insert logsToInsert; } catch (Exception e) { /* non-fatal */ }

        return results;
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

    private static Map<Id, String> resolveDefinitionKeys(Set<Id> templateIds) {
        Map<Id, String> result = new Map<Id, String>();
        for (Weave_Template_Config__c t : [
            SELECT Id, SFMC_Template_ID__c
            FROM Weave_Template_Config__c
            WHERE Id IN :templateIds
            WITH USER_MODE
        ]) {
            result.put(t.Id, String.isNotBlank(t.SFMC_Template_ID__c)
                ? t.SFMC_Template_ID__c
                : String.valueOf(t.Id));
        }
        // Fallback for IDs not found
        for (Id tid : templateIds) {
            if (!result.containsKey(tid)) result.put(tid, String.valueOf(tid));
        }
        return result;
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

    private static void createLog(Id templateId, String recipientEmail, String contextDataJson,
                                  String status, String messageId, String error) {
        try {
            insert new Weave_MCN_Email_Send__c(
                Template__c        = templateId,
                Recipient_Email__c = recipientEmail,
                Context_Data__c    = truncate(contextDataJson),
                Send_Status__c     = status,
                MCN_Message_ID__c  = messageId,
                Sent_DateTime__c   = status == 'Sent' ? System.now() : null,
                Error_Message__c   = error
            );
        } catch (Exception e) {
            // Log failure must not surface to caller
        }
    }

    private static String truncate(String s) {
        return s != null && s.length() > 131072 ? s.left(131072) : s;
    }
}
