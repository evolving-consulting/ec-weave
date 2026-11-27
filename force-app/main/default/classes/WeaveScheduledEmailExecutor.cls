/**
 * Schedulable job that processes pending individual scheduled email sends.
 * Schedule hourly (or more frequently) via Setup > Apex Scheduler or the platform-apex-anonymous-run skill:
 *   System.schedule('Weave Scheduled Email', '0 0 * * * ?', new WeaveScheduledEmailExecutor());
 */
public without sharing class WeaveScheduledEmailExecutor implements Schedulable {

    public void execute(SchedulableContext ctx) {
        processPendingSends();
    }

    @TestVisible
    public static void processPendingSends() {
        List<Weave_Scheduled_Send__c> pendingSends = [
            SELECT Id, Send_Request_Payload__c, Template__c, Template__r.Status__c
            FROM Weave_Scheduled_Send__c
            WHERE Status__c = 'Pending'
              AND Scheduled_At__c <= :System.now()
              AND Send_Type__c = 'Individual'
            WITH USER_MODE
            ORDER BY Scheduled_At__c ASC
            LIMIT 25
        ];

        for (Weave_Scheduled_Send__c scheduledSend : pendingSends) {
            if (String.isBlank(scheduledSend.Send_Request_Payload__c)) continue;
            processSingleSend(scheduledSend);
        }
    }

    private static void processSingleSend(Weave_Scheduled_Send__c scheduledSend) {
        if (scheduledSend.Template__r?.Status__c != 'Active') {
            scheduledSend.Status__c = 'Failed';
            scheduledSend.Error_Detail__c = 'Template is inactive. Please contact your administrator.';
            scheduledSend.Records_Failed__c = 1;
            update scheduledSend;
            return;
        }

        scheduledSend.Status__c = 'Running';
        update scheduledSend;

        try {
            WeaveScheduledSendPayload payload = (WeaveScheduledSendPayload) JSON.deserialize(
                scheduledSend.Send_Request_Payload__c,
                WeaveScheduledSendPayload.class
            );

            Messaging.SingleEmailMessage msg = buildMessage(payload);
            Messaging.SendEmailResult[] results = Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ msg }
            );

            if (results == null || results.isEmpty() || !results[0].isSuccess()) {
                throw new AuraHandledException('Send failed: ' + getError(results));
            }

            scheduledSend.Status__c = 'Sent';
            scheduledSend.Records_Sent__c = 1;
            scheduledSend.Records_Failed__c = 0;

            logSend(payload);
        } catch (Exception e) {
            scheduledSend.Status__c = 'Failed';
            scheduledSend.Error_Detail__c = truncate(e.getMessage(), 32000);
            scheduledSend.Records_Failed__c = 1;
        }

        update scheduledSend;
    }

    private static Messaging.SingleEmailMessage buildMessage(WeaveScheduledSendPayload payload) {
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(payload.toAddresses);
        if (payload.ccAddresses != null && !payload.ccAddresses.isEmpty()) {
            msg.setCcAddresses(payload.ccAddresses);
        }
        if (payload.bccAddresses != null && !payload.bccAddresses.isEmpty()) {
            msg.setBccAddresses(payload.bccAddresses);
        }
        msg.setSubject(payload.subject);
        msg.setHtmlBody(payload.htmlBody);
        msg.setPlainTextBody(htmlToPlainText(payload.htmlBody));
        msg.setSaveAsActivity(false);
        if (payload.attachmentVersionIds != null && !payload.attachmentVersionIds.isEmpty()) {
            msg.setEntityAttachments(payload.attachmentVersionIds);
        }
        if (String.isNotBlank(payload.orgWideEmailAddressId)) {
            msg.setOrgWideEmailAddressId((Id) payload.orgWideEmailAddressId);
        }
        return msg;
    }

    private static void logSend(WeaveScheduledSendPayload payload) {
        if (!Weave_Send_Log__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isCreateable()) return;
        try {
            Integer recipientCount =
                (payload.toAddresses?.size() ?? 0) +
                (payload.ccAddresses?.size() ?? 0) +
                (payload.bccAddresses?.size() ?? 0);
            Weave_Send_Log__c log = new Weave_Send_Log__c();
            log.Template__c = payload.templateId;
            log.Recipient_Count__c = recipientCount;
            log.Sent_At__c = System.now();
            log.Source_Record_Id__c = payload.recordId;
            log.Running_User__c = String.isNotBlank(payload.scheduledByUserId)
                ? (Id) payload.scheduledByUserId
                : null;
            insert log;
        } catch (Exception ignored) {
            System.debug(ignored);
        }
    }

    private static String htmlToPlainText(String html) {
        if (html == null) return '';
        String plain = html
            .replaceAll('(?i)<br\\s*/?>', '\n')
            .replaceAll('(?i)</p\\s*>', '\n')
            .replaceAll('(?i)</div\\s*>', '\n')
            .replaceAll('(?i)</tr\\s*>', '\n')
            .replaceAll('(?i)</li\\s*>', '\n')
            .replaceAll('<[^>]+>', '');
        return plain
            .replace('&nbsp;', ' ').replace('&amp;', '&').replace('&lt;', '<')
            .replace('&gt;', '>').replace('&quot;', '"').replace('&#39;', '\'').trim();
    }

    private static String getError(Messaging.SendEmailResult[] results) {
        if (results == null || results.isEmpty() || results[0]?.getErrors() == null) return 'Unknown error';
        List<String> msgs = new List<String>();
        for (Messaging.SendEmailError e : results[0].getErrors()) msgs.add(e.getMessage());
        return String.join(msgs, '; ');
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) return value;
        return value.substring(0, maxLength);
    }
}
