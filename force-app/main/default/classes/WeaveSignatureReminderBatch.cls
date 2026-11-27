@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces')
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
            SELECT Id, Name, Email__c, Role__c, Signature_Request__c
            FROM Weave_Signer__c
            WHERE Signature_Request__c IN :activeIds
            AND Status__c IN ('Sent', 'Opened')
            WITH USER_MODE
        ];

        // Build a map of requestId → template info (brand + doc title)
        Map<Id, Id> reqToBrand = new Map<Id, Id>();
        Map<Id, String> reqToTitle = new Map<Id, String>();
        Set<Id> templateIds = new Set<Id>();
        List<Weave_Signature_Request__c> allReqs = [
            SELECT Id, Template_Id__c FROM Weave_Signature_Request__c WHERE Id IN :activeIds WITH USER_MODE
        ];
        for (Weave_Signature_Request__c r : allReqs) if (r.Template_Id__c != null) templateIds.add(r.Template_Id__c);
        Map<Id, Weave_Template_Config__c> tplMap = new Map<Id, Weave_Template_Config__c>(
            [SELECT Id, Brand__c, Name FROM Weave_Template_Config__c WHERE Id IN :templateIds WITH USER_MODE]
        );
        for (Weave_Signature_Request__c r : allReqs) {
            Weave_Template_Config__c tpl = tplMap.get(r.Template_Id__c);
            reqToBrand.put(r.Id, tpl != null ? tpl.Brand__c : null);
            reqToTitle.put(r.Id, tpl != null ? tpl.Name : '');
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Weave_Signer__c s : signers) {
            Id brandId = reqToBrand.get(s.Signature_Request__c);
            String docTitle = reqToTitle.get(s.Signature_Request__c);
            Map<String, Object> tokenCtx = new Map<String, Object>{
                'SignerName'    => s.Name,
                'DocumentTitle' => docTitle != null ? docTitle : '',
                'RoleName'      => s.Role__c != null ? s.Role__c : 'Signer',
                'ActionButton'  => '<p style="color:#6b7280;">Please use the original signing link from your invitation email to continue.</p>'
            };
            WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO tpl =
                WeaveSignatureEmailTemplateService.getEmailTemplate(brandId, WeaveSignatureEmailTemplateService.TYPE_REMINDER);
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setToAddresses(new List<String>{ s.Email__c });
            m.setSubject(WeaveSignatureEmailTemplateService.renderSubject(tpl, tokenCtx));
            m.setHtmlBody(WeaveSignatureEmailTemplateService.renderBody(tpl, tokenCtx, brandId));
            m.setSaveAsActivity(false);
            emails.add(m);
        }
        if (!emails.isEmpty()) Messaging.sendEmail(emails);
    }

    @SuppressWarnings('PMD.EmptyStatementBlock')
    public void finish(Database.BatchableContext ctx) {}
}
