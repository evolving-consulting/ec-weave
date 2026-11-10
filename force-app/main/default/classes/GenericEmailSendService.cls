/**
 * Sends finalized Dynamic Communication Engine email requests.
 * This service is generic and does not assume any specific business object.
 */
public with sharing class GenericEmailSendService {
    private static final String EMAIL_REGEX = '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$';
    private static final Integer MAX_DESCRIPTION_LENGTH = 32000;
    private static final Integer MAX_SINGLE_EMAIL_RECIPIENTS = 150;
    private static final Integer MAX_SENDS_PER_USER_PER_DAY = 200;
    private static final Integer BULK_SEND_THRESHOLD = 10;

    public static DceEmailSendResultDTO sendEmail(GenericEmailSendRequest request) {
        try {
            DceEmailSendResultDTO result = new DceEmailSendResultDTO();
            validateBaseRequest(request);
            Email_Template_Config__c template = request.templateId == null ? null : loadTemplate(request.templateId);
            applyAuthoritativeContent(request, template);
            validateContent(request);
            List<String> toAddresses = normalizeRecipients(request.toRecipients, 'To');
            List<String> ccAddresses = normalizeRecipients(request.ccRecipients, 'CC');
            List<String> bccAddresses = normalizeRecipients(request.bccRecipients, 'BCC');
            dedupeRecipientBuckets(toAddresses, ccAddresses, bccAddresses);

            if (toAddresses.isEmpty()) {
                throw new AuraHandledException('At least one To recipient is required.');
            }
            validateRecipientLimit(toAddresses, ccAddresses, bccAddresses);
            Integer totalRecipients = toAddresses.size() + ccAddresses.size() + bccAddresses.size();
            assertWithinRateLimit(totalRecipients);

            String plainTextBody = htmlToPlainText(request.htmlBody);
            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(toAddresses);
            if (!ccAddresses.isEmpty()) {
                msg.setCcAddresses(ccAddresses);
            }
            if (!bccAddresses.isEmpty()) {
                msg.setBccAddresses(bccAddresses);
            }
            msg.setSubject(request.subject.trim());
            msg.setHtmlBody(request.htmlBody);
            msg.setPlainTextBody(plainTextBody);
            msg.setSaveAsActivity(false);
            List<String> attachmentVersionIds = resolveAttachmentVersionIds(request.attachmentContentDocumentIds);
            if (!attachmentVersionIds.isEmpty()) {
                msg.setEntityAttachments(attachmentVersionIds);
            }

            Id orgWideEmailAddressId = template == null ? null : findOrgWideEmailAddressId(template.Default_From_Email__c);
            if (orgWideEmailAddressId != null) {
                msg.setOrgWideEmailAddressId(orgWideEmailAddressId);
            }

            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { msg });
            if (results == null || results.isEmpty() || !results[0].isSuccess()) {
                throw new AuraHandledException('Email failed to send: ' + getSendEmailErrorMessage(results));
            }

            logSend(request.templateId, totalRecipients);

            if (shouldStoreHistory(request, template)) {
                String historyWarning = logTaskHistory(request, toAddresses, ccAddresses, bccAddresses, plainTextBody);
                if (historyWarning != null) {
                    result.warnings.add(historyWarning);
                }
            }
            if (template != null) {
                result.warnings.addAll(
                    GenericPostSendActionService.executeActions(
                        template,
                        request.recordId,
                        template.Parent_Object_API_Name__c,
                        System.now()
                    )
                );
            }
            return result;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('Unable to send email. Please contact your administrator.');
        }
    }

    private static Email_Template_Config__c loadTemplate(Id templateId) {
        List<Email_Template_Config__c> templates = [
            SELECT Id,
                Name,
                Active__c,
                Store_Email_History__c,
                Allow_User_Edit_Before_Send__c,
                Default_From_Email__c,
                Parent_Object_API_Name__c,
                Post_Send_Actions__c
            FROM Email_Template_Config__c
            WHERE Id = :templateId
            WITH USER_MODE
            LIMIT 1
        ];

        if (templates.isEmpty()) {
            throw new AuraHandledException('Template not found.');
        }
        if (templates[0].Active__c != true) {
            throw new AuraHandledException('Template is inactive.');
        }

        return templates[0];
    }

    private static void validateBaseRequest(GenericEmailSendRequest request) {
        if (request == null) {
            throw new AuraHandledException('Email send request is required.');
        }
        if (request.recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }
    }

    private static void applyAuthoritativeContent(
        GenericEmailSendRequest request,
        Email_Template_Config__c template
    ) {
        if (template == null || template.Allow_User_Edit_Before_Send__c == true) {
            return;
        }
        RenderedEmailDTO rendered = GenericEmailTemplateRenderer.renderEmail(template.Id, request.recordId);
        request.subject = rendered.subject;
        request.htmlBody = rendered.htmlBody;
    }

    private static void validateContent(GenericEmailSendRequest request) {
        if (String.isBlank(request.subject)) {
            throw new AuraHandledException('Email subject is required.');
        }
        if (String.isBlank(request.htmlBody)) {
            throw new AuraHandledException('Email body is required.');
        }
        DceHtmlPolicy.assertSafeUserHtml(request.htmlBody);
        DceTemplateContentService.assertRenderedSize(request.htmlBody);
    }

    private static List<String> normalizeRecipients(List<RecipientInputDTO> recipients, String category) {
        List<String> addresses = new List<String>();
        Set<String> seenAddresses = new Set<String>();

        if (recipients == null) {
            return addresses;
        }

        for (RecipientInputDTO recipient : recipients) {
            if (recipient == null || String.isBlank(recipient.email)) {
                continue;
            }

            String email = recipient.email.trim();
            if (!isValidEmail(email)) {
                throw new AuraHandledException('Invalid email address: ' + email);
            }

            String key = email.toLowerCase();
            if (!seenAddresses.contains(key)) {
                addresses.add(email);
                seenAddresses.add(key);
            }
        }

        return addresses;
    }

    private static Boolean isValidEmail(String email) {
        return !String.isBlank(email) && Pattern.matches(EMAIL_REGEX, email.trim().toUpperCase());
    }

    private static void dedupeRecipientBuckets(
        List<String> toAddresses,
        List<String> ccAddresses,
        List<String> bccAddresses
    ) {
        Set<String> toKeys = toLowercaseSet(toAddresses);
        removeExistingRecipients(ccAddresses, toKeys);

        Set<String> ccKeys = toLowercaseSet(ccAddresses);
        removeExistingRecipients(bccAddresses, toKeys);
        removeExistingRecipients(bccAddresses, ccKeys);
    }

    private static void removeExistingRecipients(List<String> addresses, Set<String> existingKeys) {
        for (Integer i = addresses.size() - 1; i >= 0; i--) {
            if (existingKeys.contains(addresses[i].toLowerCase())) {
                addresses.remove(i);
            }
        }
    }

    private static Set<String> toLowercaseSet(List<String> addresses) {
        Set<String> keys = new Set<String>();
        for (String address : addresses) {
            keys.add(address.toLowerCase());
        }
        return keys;
    }

    private static void validateRecipientLimit(
        List<String> toAddresses,
        List<String> ccAddresses,
        List<String> bccAddresses
    ) {
        Integer recipientCount = toAddresses.size() + ccAddresses.size() + bccAddresses.size();
        if (recipientCount > MAX_SINGLE_EMAIL_RECIPIENTS) {
            throw new AuraHandledException('Email recipient count exceeds the Salesforce limit of 150 recipients.');
        }
    }

    private static Id findOrgWideEmailAddressId(String fromEmail) {
        if (String.isBlank(fromEmail)) {
            return null;
        }

        String normalizedFromEmail = fromEmail.trim();
        if (!isValidEmail(normalizedFromEmail)) {
            throw new AuraHandledException('Configured default from email does not match an Org-Wide Email Address.');
        }

        List<OrgWideEmailAddress> orgWideEmailAddresses = [
            SELECT Id,
                Address
            FROM OrgWideEmailAddress
            WHERE Address = :normalizedFromEmail
            WITH USER_MODE
            LIMIT 1
        ];

        if (orgWideEmailAddresses.isEmpty()) {
            throw new AuraHandledException('Configured default from email does not match an Org-Wide Email Address.');
        }

        return orgWideEmailAddresses[0].Id;
    }

    private static List<String> resolveAttachmentVersionIds(List<Id> contentDocumentIds) {
        List<String> versionIds = new List<String>();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return versionIds;
        }

        Set<Id> uniqueDocumentIds = new Set<Id>();
        for (Id contentDocumentId : contentDocumentIds) {
            if (contentDocumentId != null) {
                uniqueDocumentIds.add(contentDocumentId);
            }
        }
        if (uniqueDocumentIds.isEmpty()) {
            return versionIds;
        }

        Map<Id, Id> latestVersionByDocumentId = new Map<Id, Id>();
        for (ContentVersion version : [
            SELECT Id,
                ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId IN :uniqueDocumentIds
                AND IsLatest = true
            WITH USER_MODE
        ]) {
            latestVersionByDocumentId.put(version.ContentDocumentId, version.Id);
        }

        Set<Id> seenVersionIds = new Set<Id>();
        for (Id contentDocumentId : contentDocumentIds) {
            Id versionId = latestVersionByDocumentId.get(contentDocumentId);
            if (versionId != null && !seenVersionIds.contains(versionId)) {
                versionIds.add(String.valueOf(versionId));
                seenVersionIds.add(versionId);
            }
        }

        return versionIds;
    }

    private static Boolean shouldStoreHistory(GenericEmailSendRequest request, Email_Template_Config__c template) {
        return template == null
            ? request.storeHistory == true
            : template.Store_Email_History__c == true;
    }

    private static String logTaskHistory(
        GenericEmailSendRequest request,
        List<String> toAddresses,
        List<String> ccAddresses,
        List<String> bccAddresses,
        String plainTextBody
    ) {
        if (!Task.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isCreateable()) {
            return 'Email sent, but history was not stored because Task creation is not permitted.';
        }

        try {
            Task historyTask = new Task();
            historyTask.WhatId = request.recordId;
            historyTask.Subject = truncate('Email: ' + request.subject, 255);
            historyTask.Description = buildTaskDescription(toAddresses, ccAddresses, bccAddresses, plainTextBody);
            historyTask.TaskSubtype = 'Email';
            historyTask.Status = 'Completed';
            historyTask.Priority = 'Normal';
            historyTask.ActivityDate = Date.today();
            insert as user historyTask;
            return null;
        } catch (Exception ignoredException) {
            return 'Email sent, but its Task history could not be stored.';
        }
    }

    private static String buildTaskDescription(
        List<String> toAddresses,
        List<String> ccAddresses,
        List<String> bccAddresses,
        String plainTextBody
    ) {
        String description = '';
        description += 'To: ' + String.join(toAddresses, ', ') + '\n';
        if (!ccAddresses.isEmpty()) {
            description += 'CC: ' + String.join(ccAddresses, ', ') + '\n';
        }
        if (!bccAddresses.isEmpty()) {
            description += 'BCC: ' + String.join(bccAddresses, ', ') + '\n';
        }
        description += '\n' + (plainTextBody == null ? '' : plainTextBody);
        return truncate(description, MAX_DESCRIPTION_LENGTH);
    }

    private static String htmlToPlainText(String html) {
        if (html == null) {
            return '';
        }

        String plainText = html;
        plainText = plainText.replaceAll('(?i)<br\\s*/?>', '\n');
        plainText = plainText.replaceAll('(?i)</p\\s*>', '\n');
        plainText = plainText.replaceAll('(?i)</div\\s*>', '\n');
        plainText = plainText.replaceAll('(?i)</tr\\s*>', '\n');
        plainText = plainText.replaceAll('(?i)</li\\s*>', '\n');
        plainText = plainText.replaceAll('<[^>]+>', '');
        plainText = plainText.replace('&nbsp;', ' ');
        plainText = plainText.replace('&amp;', '&');
        plainText = plainText.replace('&lt;', '<');
        plainText = plainText.replace('&gt;', '>');
        plainText = plainText.replace('&quot;', '"');
        plainText = plainText.replace('&#39;', '\'');
        return plainText.trim();
    }

    private static String getSendEmailErrorMessage(Messaging.SendEmailResult[] results) {
        if (results == null || results.isEmpty() || results[0] == null || results[0].getErrors() == null || results[0].getErrors().isEmpty()) {
            return 'Unknown error';
        }

        List<String> messages = new List<String>();
        for (Messaging.SendEmailError error : results[0].getErrors()) {
            messages.add(error.getMessage());
        }
        return String.join(messages, '; ');
    }

    private static void assertWithinRateLimit(Integer recipientCount) {
        if (recipientCount > BULK_SEND_THRESHOLD && !FeatureManagement.checkPermission('DCE_Bulk_Send')) {
            throw new AuraHandledException(
                'Sending to more than ' + BULK_SEND_THRESHOLD +
                ' recipients requires the DCE Bulk Send permission. Please contact your administrator.'
            );
        }

        Datetime startOfDay = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
        Integer todaySendCount = [
            SELECT COUNT()
            FROM DCE_Send_Log__c
            WHERE OwnerId = :UserInfo.getUserId()
                AND Sent_At__c >= :startOfDay
            WITH USER_MODE
        ];

        if (todaySendCount >= MAX_SENDS_PER_USER_PER_DAY) {
            throw new AuraHandledException(
                'You have reached your daily email send limit of ' + MAX_SENDS_PER_USER_PER_DAY +
                '. Please contact your administrator.'
            );
        }
    }

    private static void logSend(Id templateId, Integer recipientCount) {
        if (!DCE_Send_Log__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isCreateable()) {
            return;
        }
        try {
            DCE_Send_Log__c log = new DCE_Send_Log__c();
            log.Template__c = templateId;
            log.Recipient_Count__c = recipientCount;
            log.Sent_At__c = System.now();
            insert as user log;
        } catch (Exception ignoredException) {
            // Audit log failure must not block confirmed email delivery
        }
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }
}
