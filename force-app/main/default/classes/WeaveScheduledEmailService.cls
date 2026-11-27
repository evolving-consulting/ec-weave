@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.CyclomaticComplexity,PMD.CognitiveComplexity')
public with sharing class WeaveScheduledEmailService {
    private static final String EMAIL_REGEX = '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$';
    private static final Integer MIN_SCHEDULE_MINUTES = 5;

    public static Id scheduleEmail(GenericEmailSendRequest request, Datetime scheduledAt) {
        validateScheduleRequest(request, scheduledAt);

        Weave_Template_Config__c template = request.templateId == null ? null : loadTemplate(request.templateId);

        applyAuthoritativeContent(request, template);

        if (String.isBlank(request.subject)) throw new AuraHandledException('Email subject is required.');
        if (String.isBlank(request.htmlBody)) throw new AuraHandledException('Email body is required.');

        applyUnsubscribeBackstop(request, template);

        List<String> toAddresses = normalizeRecipients(request.toRecipients);
        List<String> ccAddresses = normalizeRecipients(request.ccRecipients);
        List<String> bccAddresses = normalizeRecipients(request.bccRecipients);
        if (toAddresses.isEmpty()) throw new AuraHandledException('At least one To recipient is required.');

        List<String> attachmentVersionIds = resolveAttachmentVersionIds(request.attachmentContentDocumentIds);

        String resolvedFromEmail = resolveFromEmail(template);
        String orgWideEmailAddressId = findOrgWideEmailAddressId(resolvedFromEmail);

        WeaveScheduledSendPayload payload = new WeaveScheduledSendPayload();
        payload.templateId = request.templateId;
        payload.recordId = request.recordId == null ? null : String.valueOf(request.recordId);
        payload.subject = request.subject.trim();
        payload.htmlBody = request.htmlBody;
        payload.toAddresses = toAddresses;
        payload.ccAddresses = ccAddresses;
        payload.bccAddresses = bccAddresses;
        payload.attachmentVersionIds = attachmentVersionIds;
        payload.orgWideEmailAddressId = orgWideEmailAddressId;
        payload.storeHistory = template == null
            ? (request.storeHistory == true)
            : (template.Store_Email_History__c == true);
        payload.scheduledByUserId = UserInfo.getUserId();

        if (!Weave_Scheduled_Send__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isCreateable()) {
            throw new AuraHandledException('You do not have permission to schedule email sends.');
        }

        Weave_Scheduled_Send__c scheduledSend = new Weave_Scheduled_Send__c();
        scheduledSend.Template__c = request.templateId;
        scheduledSend.Record_Id__c = payload.recordId;
        scheduledSend.Scheduled_At__c = scheduledAt;
        scheduledSend.Status__c = 'Pending';
        scheduledSend.Send_Type__c = 'Individual';
        scheduledSend.Job_Name__c = truncate('Scheduled: ' + request.subject, 255);
        scheduledSend.Send_Request_Payload__c = JSON.serialize(payload);

        insert as user scheduledSend;
        return scheduledSend.Id;
    }

    private static void validateScheduleRequest(GenericEmailSendRequest request, Datetime scheduledAt) {
        if (request == null) throw new AuraHandledException('Send request is required.');
        if (request.recordId == null) throw new AuraHandledException('Record Id is required.');
        if (scheduledAt == null) throw new AuraHandledException('Scheduled date/time is required.');
        if (scheduledAt <= System.now().addMinutes(MIN_SCHEDULE_MINUTES)) {
            throw new AuraHandledException(
                'Scheduled time must be at least ' + MIN_SCHEDULE_MINUTES + ' minutes from now.'
            );
        }
    }

    private static Weave_Template_Config__c loadTemplate(Id templateId) {
        List<Weave_Template_Config__c> templates = [
            SELECT Id, Name, Status__c, Store_Email_History__c, Allow_User_Edit_Before_Send__c,
                Default_From_Email__c, Parent_Object_API_Name__c,
                Brand__c, Brand__r.Org_Wide_Email_Address__c,
                Brand__r.Unsubscribe_URL__c, Brand__r.Unsubscribe_Label__c
            FROM Weave_Template_Config__c
            WHERE Id = :templateId WITH USER_MODE LIMIT 1
        ];
        if (templates.isEmpty()) throw new AuraHandledException('Template not found.');
        if (templates[0].Status__c != 'Active') throw new AuraHandledException('Template is not active.');
        return templates[0];
    }

    private static void applyAuthoritativeContent(GenericEmailSendRequest request, Weave_Template_Config__c template) {
        if (template == null || template.Allow_User_Edit_Before_Send__c == true) return;
        WeaveEmailTemplateRenderer.RenderedEmailDTO rendered =
            WeaveEmailTemplateRenderer.renderEmail(template.Id, request.recordId);
        request.subject = rendered.subject;
        request.htmlBody = rendered.htmlBody;
    }

    private static void applyUnsubscribeBackstop(GenericEmailSendRequest request, Weave_Template_Config__c template) {
        if (template?.Brand__c == null) return;
        String unsubUrl = template.Brand__r?.Unsubscribe_URL__c;
        if (String.isBlank(unsubUrl)) return;
        if (request.htmlBody != null && request.htmlBody.contains(unsubUrl)) return;
        String label = String.isBlank(template.Brand__r?.Unsubscribe_Label__c)
            ? 'Unsubscribe'
            : template.Brand__r.Unsubscribe_Label__c;
        request.htmlBody = (request.htmlBody ?? '')
            + '<p style="font-size:11px;color:#666;text-align:center;">To unsubscribe, <a href="'
            + unsubUrl + '">' + label + '</a>.</p>';
    }

    private static String resolveFromEmail(Weave_Template_Config__c template) {
        if (template == null) return null;
        if (String.isNotBlank(template.Default_From_Email__c)) return template.Default_From_Email__c;
        return template.Brand__c != null ? template.Brand__r.Org_Wide_Email_Address__c : null;
    }

    private static String findOrgWideEmailAddressId(String fromEmail) {
        if (String.isBlank(fromEmail)) return null;
        List<OrgWideEmailAddress> addrs = [
            SELECT Id FROM OrgWideEmailAddress WHERE Address = :fromEmail.trim() WITH USER_MODE LIMIT 1
        ];
        return addrs.isEmpty() ? null : String.valueOf(addrs[0].Id);
    }

    private static List<String> normalizeRecipients(List<RecipientInputDTO> recipients) {
        List<String> addresses = new List<String>();
        Set<String> seen = new Set<String>();
        if (recipients == null) return addresses;
        for (RecipientInputDTO r : recipients) {
            if (r == null || String.isBlank(r.email)) continue;
            String email = r.email.trim();
            if (!Pattern.matches(EMAIL_REGEX, email.toUpperCase())) {
                throw new AuraHandledException('Invalid email address: ' + email);
            }
            String key = email.toLowerCase();
            if (!seen.contains(key)) {
                addresses.add(email);
                seen.add(key);
            }
        }
        return addresses;
    }

    private static List<String> resolveAttachmentVersionIds(List<Id> contentDocumentIds) {
        List<String> versionIds = new List<String>();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) return versionIds;
        Set<Id> uniqueIds = new Set<Id>(contentDocumentIds);
        uniqueIds.remove(null);
        if (uniqueIds.isEmpty()) return versionIds;
        Set<Id> seen = new Set<Id>();
        for (ContentVersion cv : [
            SELECT Id FROM ContentVersion
            WHERE ContentDocumentId IN :uniqueIds AND IsLatest = true WITH USER_MODE
        ]) {
            if (!seen.contains(cv.Id)) {
                versionIds.add(String.valueOf(cv.Id));
                seen.add(cv.Id);
            }
        }
        return versionIds;
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) return value;
        return value.substring(0, maxLength);
    }
}
