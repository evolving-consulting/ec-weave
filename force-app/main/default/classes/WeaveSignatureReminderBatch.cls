public with sharing class WeaveSignatureReminderBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        return Database.getQueryLocator([
            SELECT Id, Status__c, Expiry_Date__c
            FROM Weave_Signature_Request__c
            WHERE Status__c IN ('Sent', 'In Progress')
            WITH USER_MODE
        ]);
    }

    public void execute(Database.BatchableContext ctx, List<Weave_Signature_Request__c> requests) {
        List<Weave_Signature_Request__c> toExpire = new List<Weave_Signature_Request__c>();
        List<Id> activeIds = new List<Id>();

        for (Weave_Signature_Request__c req : requests) {
            if (req.Expiry_Date__c != null && req.Expiry_Date__c < DateTime.now()) {
                req.Status__c = 'Expired';
                toExpire.add(req);
            } else {
                activeIds.add(req.Id);
            }
        }
        if (!toExpire.isEmpty()) update as user toExpire;

        if (activeIds.isEmpty()) return;

        List<Weave_Signer__c> signers = [
            SELECT Id, Name, Email__c
            FROM Weave_Signer__c
            WHERE Signature_Request__c IN :activeIds
            AND Status__c IN ('Sent', 'Opened')
            WITH USER_MODE
        ];
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Weave_Signer__c s : signers) {
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setToAddresses(new List<String>{ s.Email__c });
            m.setSubject('Reminder: Document Awaiting Your Signature');
            m.setHtmlBody('<p>Hello ' + s.Name + ',</p>'
                + '<p>This is a friendly reminder that a document is still awaiting your electronic signature. Please use the original signing link in your invitation email.</p>');
            m.setSaveAsActivity(false);
            emails.add(m);
        }
        if (!emails.isEmpty()) Messaging.sendEmail(emails);
    }

    public void finish(Database.BatchableContext ctx) {}
}
