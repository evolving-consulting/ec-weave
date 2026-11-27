@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.NcssMethodCount,PMD.NcssTypeCount,PMD.NcssConstructorCount')
@SuppressWarnings('PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.ApexDoc')
public with sharing class WeaveEmailSendService {
    private static final String EMAIL_REGEX = '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$';
    private static final Integer MAX_SINGLE_EMAIL_RECIPIENTS = 150;
    private static final Integer MAX_SENDS_PER_USER_PER_DAY = 200;
    private static final Integer BULK_SEND_THRESHOLD = 10;
    private static final Integer MAX_DESCRIPTION_LENGTH = 32000;

    public static DceEmailSendResultDTO sendEmail(GenericEmailSendRequest request) {
        try {
            DceEmailSendResultDTO result = new DceEmailSendResultDTO();
            validateBaseRequest(request);
            Weave_Template_Config__c template = request.templateId == null ? null : loadTemplate(request.templateId);
            applyAuthoritativeContent(request, template);
            if (template != null && (request.attachmentContentDocumentIds == null || request.attachmentContentDocumentIds.isEmpty())) {
                request.attachmentContentDocumentIds = WeaveAttachmentResolver.resolveDocumentIds(template.Id, request.recordId);
            }
            validateContent(request);
        applyUnsubscribeBackstop(request, template);
            List<String> toAddresses = normalizeRecipients(request.toRecipients, 'To');
            List<String> ccAddresses = normalizeRecipients(request.ccRecipients, 'CC');
            List<String> bccAddresses = normalizeRecipients(request.bccRecipients, 'BCC');
            dedupeRecipientBuckets(toAddresses, ccAddresses, bccAddresses);
            if (toAddresses.isEmpty()) throw new AuraHandledException('At least one To recipient is required.');
            validateRecipientLimit(toAddresses, ccAddresses, bccAddresses);
            Integer totalRecipients = toAddresses.size() + ccAddresses.size() + bccAddresses.size();
            assertWithinRateLimit(totalRecipients);

            String plainTextBody = htmlToPlainText(request.htmlBody);
            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(toAddresses);
            if (!ccAddresses.isEmpty()) msg.setCcAddresses(ccAddresses);
            if (!bccAddresses.isEmpty()) msg.setBccAddresses(bccAddresses);
            msg.setSubject(request.subject.trim());
            msg.setHtmlBody(request.htmlBody);
            msg.setPlainTextBody(plainTextBody);
            msg.setSaveAsActivity(false);

            List<String> attachmentVersionIds = resolveAttachmentVersionIds(request.attachmentContentDocumentIds);
            if (!attachmentVersionIds.isEmpty()) msg.setEntityAttachments(attachmentVersionIds);

            String resolvedFromEmail = null;
            if (template != null) {
                resolvedFromEmail = String.isNotBlank(template.Default_From_Email__c)
                    ? template.Default_From_Email__c
                    : (template.Brand__c != null ? template.Brand__r.Org_Wide_Email_Address__c : null);
            }
            Id orgWideEmailAddressId = findOrgWideEmailAddressId(resolvedFromEmail);
            if (orgWideEmailAddressId != null) msg.setOrgWideEmailAddressId(orgWideEmailAddressId);

            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { msg });
            if (results == null || results.isEmpty() || !results[0].isSuccess()) {
                throw new AuraHandledException('Email failed to send: ' + getSendEmailErrorMessage(results));
            }

            logSend(template, totalRecipients, request.recordId);

            if (shouldStoreHistory(request, template)) {
                String historyWarning = logTaskHistory(request, toAddresses, ccAddresses, bccAddresses, plainTextBody);
                if (historyWarning != null) result.warnings.add(historyWarning);
            }
            if (template != null) {
                try {
                    WeavePostSendActionService.executeActions(template.Id, request.recordId, template.Parent_Object_API_Name__c);
                } catch (Exception postSendEx) {
                    result.warnings.add('Email sent, but one or more post-send actions could not be completed: ' + postSendEx.getMessage());
                }
            }
            return result;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('Unable to send email. Please contact your administrator.');
        }
    }

    private static Weave_Template_Config__c loadTemplate(Id templateId) {
        List<Weave_Template_Config__c> templates = [
            SELECT Id, Name, Status__c, Store_Email_History__c,
                Allow_User_Edit_Before_Send__c, Default_From_Email__c, Parent_Object_API_Name__c,
                Brand__c, Brand__r.Org_Wide_Email_Address__c,
                Brand__r.Unsubscribe_URL__c, Brand__r.Unsubscribe_Label__c
            FROM Weave_Template_Config__c
            WHERE Id = :templateId
            WITH USER_MODE
            LIMIT 1
        ];
        if (templates.isEmpty()) throw new AuraHandledException('Template not found.');
        if (templates[0].Status__c != 'Active') throw new AuraHandledException('Template is not active.');
        return templates[0];
    }

    private static void validateBaseRequest(GenericEmailSendRequest request) {
        if (request == null) throw new AuraHandledException('Email send request is required.');
        if (request.recordId == null) throw new AuraHandledException('Record Id is required.');
    }

    private static void applyAuthoritativeContent(GenericEmailSendRequest request, Weave_Template_Config__c template) {
        if (template == null || template.Allow_User_Edit_Before_Send__c == true) return;
        WeaveEmailTemplateRenderer.RenderedEmailDTO rendered = WeaveEmailTemplateRenderer.renderEmail(template.Id, request.recordId);
        request.subject = rendered.subject;
        request.htmlBody = rendered.htmlBody;
    }

    private static void validateContent(GenericEmailSendRequest request) {
        if (String.isBlank(request.subject)) throw new AuraHandledException('Email subject is required.');
        if (String.isBlank(request.htmlBody)) throw new AuraHandledException('Email body is required.');
        DceHtmlPolicy.assertSafeUserHtml(request.htmlBody);
        DceTemplateContentService.assertRenderedSize(request.htmlBody);
    }

    private static List<String> normalizeRecipients(List<RecipientInputDTO> recipients, String category) {
        List<String> addresses = new List<String>();
        Set<String> seenAddresses = new Set<String>();
        if (recipients == null) return addresses;
        for (RecipientInputDTO recipient : recipients) {
            if (recipient == null || String.isBlank(recipient.email)) continue;
            String email = recipient.email.trim();
            if (!isValidEmail(email)) throw new AuraHandledException('Invalid email address: ' + email);
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

    private static void dedupeRecipientBuckets(List<String> toAddresses, List<String> ccAddresses, List<String> bccAddresses) {
        Set<String> toKeys = toLowercaseSet(toAddresses);
        removeExistingRecipients(ccAddresses, toKeys);
        Set<String> ccKeys = toLowercaseSet(ccAddresses);
        removeExistingRecipients(bccAddresses, toKeys);
        removeExistingRecipients(bccAddresses, ccKeys);
    }

    private static void removeExistingRecipients(List<String> addresses, Set<String> existingKeys) {
        for (Integer i = addresses.size() - 1; i >= 0; i--) {
            if (existingKeys.contains(addresses[i].toLowerCase())) addresses.remove(i);
        }
    }

    private static Set<String> toLowercaseSet(List<String> addresses) {
        Set<String> keys = new Set<String>();
        for (String address : addresses) keys.add(address.toLowerCase());
        return keys;
    }

    private static void validateRecipientLimit(List<String> toAddresses, List<String> ccAddresses, List<String> bccAddresses) {
        Integer count = toAddresses.size() + ccAddresses.size() + bccAddresses.size();
        if (count > MAX_SINGLE_EMAIL_RECIPIENTS) {
            throw new AuraHandledException('Email recipient count exceeds the Salesforce limit of 150 recipients.');
        }
    }

    private static Id findOrgWideEmailAddressId(String fromEmail) {
        if (String.isBlank(fromEmail)) return null;
        String normalized = fromEmail.trim();
        if (!isValidEmail(normalized)) throw new AuraHandledException('Configured default from email does not match an Org-Wide Email Address.');
        List<OrgWideEmailAddress> addrs = [
            SELECT Id, Address FROM OrgWideEmailAddress WHERE Address = :normalized WITH USER_MODE LIMIT 1
        ];
        if (addrs.isEmpty()) throw new AuraHandledException('Configured default from email does not match an Org-Wide Email Address.');
        return addrs[0].Id;
    }

    private static List<String> resolveAttachmentVersionIds(List<Id> contentDocumentIds) {
        List<String> versionIds = new List<String>();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) return versionIds;
        Set<Id> uniqueIds = new Set<Id>(contentDocumentIds);
        uniqueIds.remove(null);
        if (uniqueIds.isEmpty()) return versionIds;
        Map<Id, Id> latestVersionByDocId = new Map<Id, Id>();
        for (ContentVersion cv : [
            SELECT Id, ContentDocumentId FROM ContentVersion
            WHERE ContentDocumentId IN :uniqueIds AND IsLatest = true WITH USER_MODE
        ]) {
            latestVersionByDocId.put(cv.ContentDocumentId, cv.Id);
        }
        Set<Id> seenVersionIds = new Set<Id>();
        for (Id docId : contentDocumentIds) {
            Id versionId = latestVersionByDocId.get(docId);
            if (versionId != null && !seenVersionIds.contains(versionId)) {
                versionIds.add(String.valueOf(versionId));
                seenVersionIds.add(versionId);
            }
        }
        return versionIds;
    }

    private static Boolean shouldStoreHistory(GenericEmailSendRequest request, Weave_Template_Config__c template) {
        return template == null ? request.storeHistory == true : template.Store_Email_History__c == true;
    }

    private static String logTaskHistory(GenericEmailSendRequest request, List<String> toAddresses, List<String> ccAddresses, List<String> bccAddresses, String plainTextBody) {
        if (!Task.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isCreateable()) {
            return 'Email sent, but history was not stored because Task creation is not permitted.';
        }
        try {
            Task t = new Task();
            t.WhatId = request.recordId;
            t.Subject = truncate('Email: ' + request.subject, 255);
            t.Description = buildTaskDescription(toAddresses, ccAddresses, bccAddresses, plainTextBody);
            t.TaskSubtype = 'Email';
            t.Status = 'Completed';
            t.Priority = 'Normal';
            t.ActivityDate = Date.today();
            insert as user t;
            return null;
        } catch (Exception ignored) {
            return 'Email sent, but its Task history could not be stored.';
        }
    }

    private static String buildTaskDescription(List<String> toAddresses, List<String> ccAddresses, List<String> bccAddresses, String plainTextBody) {
        String description = 'To: ' + String.join(toAddresses, ', ') + '\n';
        if (!ccAddresses.isEmpty()) description += 'CC: ' + String.join(ccAddresses, ', ') + '\n';
        if (!bccAddresses.isEmpty()) description += 'BCC: ' + String.join(bccAddresses, ', ') + '\n';
        description += '\n' + (plainTextBody == null ? '' : plainTextBody);
        return truncate(description, MAX_DESCRIPTION_LENGTH);
    }

    private static String htmlToPlainText(String html) {
        if (html == null) return '';
        String plain = html.replaceAll('(?i)<br\\s*/?>', '\n').replaceAll('(?i)</p\\s*>', '\n')
            .replaceAll('(?i)</div\\s*>', '\n').replaceAll('(?i)</tr\\s*>', '\n')
            .replaceAll('(?i)</li\\s*>', '\n').replaceAll('<[^>]+>', '');
        return plain.replace('&nbsp;', ' ').replace('&amp;', '&').replace('&lt;', '<')
            .replace('&gt;', '>').replace('&quot;', '"').replace('&#39;', '\'').trim();
    }

    private static String getSendEmailErrorMessage(Messaging.SendEmailResult[] results) {
        if (results == null || results.isEmpty() || results[0] == null || results[0].getErrors() == null || results[0].getErrors().isEmpty()) return 'Unknown error';
        List<String> messages = new List<String>();
        for (Messaging.SendEmailError error : results[0].getErrors()) messages.add(error.getMessage());
        return String.join(messages, '; ');
    }

    private static void assertWithinRateLimit(Integer recipientCount) {
        if (recipientCount > BULK_SEND_THRESHOLD && !FeatureManagement.checkPermission('DCE_Bulk_Send')) {
            throw new AuraHandledException('Sending to more than ' + BULK_SEND_THRESHOLD + ' recipients requires the DCE Bulk Send permission.');
        }
        Datetime startOfDay = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
        Integer todayCount = [
            SELECT COUNT() FROM Weave_Send_Log__c WHERE Running_User__c = :UserInfo.getUserId() AND Sent_At__c >= :startOfDay WITH USER_MODE
        ];
        if (todayCount >= MAX_SENDS_PER_USER_PER_DAY) {
            throw new AuraHandledException('You have reached your daily email send limit of ' + MAX_SENDS_PER_USER_PER_DAY + '.');
        }
    }

    private static void logSend(Weave_Template_Config__c template, Integer recipientCount, Id sourceRecordId) {
        if (!Weave_Send_Log__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isCreateable()) return;
        try {
            Weave_Send_Log__c log = new Weave_Send_Log__c();
            log.Template__c = template == null ? null : template.Id;
            log.Recipient_Count__c = recipientCount;
            log.Sent_At__c = System.now();
            log.Source_Record_Id__c = sourceRecordId == null ? null : String.valueOf(sourceRecordId);
            log.Running_User__c = UserInfo.getUserId();
            insert as user log;
        } catch (Exception ignored) {}
    }

    private static void applyUnsubscribeBackstop(GenericEmailSendRequest request, Weave_Template_Config__c template) {
        if (template?.Brand__c == null) return;
        String unsubUrl = template.Brand__r?.Unsubscribe_URL__c;
        if (String.isBlank(unsubUrl)) return;
        if (request.htmlBody != null && request.htmlBody.contains(unsubUrl)) return;
        String label = String.isBlank(template.Brand__r?.Unsubscribe_Label__c) ? 'Unsubscribe' : template.Brand__r.Unsubscribe_Label__c;
        request.htmlBody = (request.htmlBody ?? '')
            + '<p style="font-size:11px;color:#666;text-align:center;">To unsubscribe, <a href="'
            + unsubUrl + '">' + label + '</a>.</p>';
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) return value;
        return value.substring(0, maxLength);
    }
}
