public with sharing class WeaveSignatureService {

    public class SignerInput {
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String role;
        @AuraEnabled public Integer signOrder;
    }

    // ─── Create ───────────────────────────────────────────────────────────────

    public static Weave_Signature_Request__c createRequest(
        Id templateId,
        Id sourceRecordId,
        String contentVersionId,
        String signingMode,
        Integer expiryDays,
        List<SignerInput> signerInputs
    ) {
        if (templateId == null)   throw new AuraHandledException('Template ID is required.');
        if (sourceRecordId == null) throw new AuraHandledException('Source Record ID is required.');
        if (signerInputs == null || signerInputs.isEmpty()) throw new AuraHandledException('At least one signer is required.');

        Savepoint sp = Database.setSavepoint();
        try {
            Weave_Signature_Request__c req = new Weave_Signature_Request__c(
                Status__c            = 'Draft',
                Source_Record_Id__c  = String.valueOf(sourceRecordId),
                Template_Id__c       = templateId,
                Content_Version_Id__c = contentVersionId,
                Signing_Mode__c      = String.isBlank(signingMode) ? 'Parallel' : signingMode,
                Expiry_Date__c       = DateTime.now().addDays(expiryDays != null && expiryDays > 0 ? expiryDays : 30)
            );
            insert as user req;

            List<Weave_Signer__c> signers = new List<Weave_Signer__c>();
            for (SignerInput si : signerInputs) {
                signers.add(new Weave_Signer__c(
                    Name                 = si.name,
                    Signature_Request__c = req.Id,
                    Email__c             = si.email,
                    Role__c              = si.role,
                    Sign_Order__c        = si.signOrder,
                    Status__c            = 'Pending',
                    PIN_Attempts__c      = 0
                ));
            }
            insert as user signers;

            List<Weave_Signature_Placement__c> placements = buildPlacements(req.Id, signers, templateId, sourceRecordId);
            if (!placements.isEmpty()) insert as user placements;

            if (signingMode == 'Sequential') {
                // Send only to the signer with the lowest signOrder
                Weave_Signer__c first = lowestOrderSigner(signers);
                generateAndSendPin(first, req);
            } else {
                for (Weave_Signer__c s : signers) generateAndSendPin(s, req);
            }

            req.Status__c = 'Sent';
            update as user req;
            return req;
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Failed to create signature request: ' + e.getMessage());
        }
    }

    // ─── Cancel ───────────────────────────────────────────────────────────────

    public static void cancelRequest(Id requestId, String cancelReason) {
        List<Weave_Signature_Request__c> reqs = [
            SELECT Id FROM Weave_Signature_Request__c WHERE Id = :requestId WITH USER_MODE LIMIT 1
        ];
        if (reqs.isEmpty()) throw new AuraHandledException('Signature request not found.');

        Weave_Signature_Request__c req = reqs[0];
        req.Status__c      = 'Canceled';
        req.Cancel_Reason__c = cancelReason;
        req.Canceled_Date__c = DateTime.now();
        update as user req;

        List<Weave_Signer__c> signers = [
            SELECT Id FROM Weave_Signer__c
            WHERE Signature_Request__c = :requestId
            AND Status__c IN ('Pending','Sent','Opened')
            WITH USER_MODE
        ];
        for (Weave_Signer__c s : signers) {
            s.Status__c    = 'Canceled';
            s.Canceled_At__c = DateTime.now();
        }
        if (!signers.isEmpty()) update as user signers;
    }

    // ─── Finalize ─────────────────────────────────────────────────────────────

    public static void finalizeDocument(Id requestId) {
        List<Weave_Signature_Request__c> reqs = [
            SELECT Id, Status__c, Source_Record_Id__c, Template_Id__c
            FROM Weave_Signature_Request__c WHERE Id = :requestId WITH USER_MODE LIMIT 1
        ];
        if (reqs.isEmpty()) throw new AuraHandledException('Signature request not found.');
        Weave_Signature_Request__c req = reqs[0];

        List<Weave_Signature_Placement__c> placements = [
            SELECT Id, Type__c, Role__c, Page__c, X_In__c, Y_In__c, W_In__c, H_In__c, Collected_Value__c, Signer__c
            FROM Weave_Signature_Placement__c WHERE Signature_Request__c = :requestId WITH USER_MODE
        ];
        List<Weave_Signer__c> signers = [
            SELECT Id, Name, Email__c, Role__c, Status__c, Signed_At__c, IP_Address__c
            FROM Weave_Signer__c WHERE Signature_Request__c = :requestId WITH USER_MODE
        ];

        Id templateId    = req.Template_Id__c;
        Id sourceRecordId = req.Source_Record_Id__c != null ? (Id) req.Source_Record_Id__c : null;

        // Re-render base document with sig-box placeholders replaced
        String renderedHtml = '';
        if (templateId != null && sourceRecordId != null) {
            Boolean isCanvas = isDocumentTemplate(templateId);
            WeaveEmailTemplateRenderer.RenderedEmailDTO rendered = isCanvas
                ? WeaveEmailTemplateRenderer.renderCanvas(templateId, sourceRecordId)
                : WeaveEmailTemplateRenderer.renderEmail(templateId, sourceRecordId);
            renderedHtml = rendered.htmlBody != null ? rendered.htmlBody : '';
        }

        // Inject collected signatures
        for (Weave_Signature_Placement__c pl : placements) {
            if (String.isBlank(pl.Collected_Value__c)) continue;
            String roleAttr = 'data-sig-role="' + escAttr(pl.Role__c) + '"';
            if (pl.Type__c == 'Full' || pl.Type__c == 'Initials') {
                Decimal w = pl.W_In__c != null ? pl.W_In__c : 2.5;
                Decimal h = pl.H_In__c != null ? pl.H_In__c : 0.75;
                String img = '<img src="' + pl.Collected_Value__c + '" style="width:' + w + 'in;height:' + h + 'in;" alt="Signature"/>';
                renderedHtml = renderedHtml.replace('<div ' + roleAttr, img + '<!-- ');
            } else if (pl.Type__c == 'Date') {
                String dateVal = pl.Collected_Value__c;
                renderedHtml = renderedHtml.replace('<div ' + roleAttr, '<div style="border-bottom:1px solid #333;" ' + roleAttr);
            }
        }

        renderedHtml += buildCertificatePage(signers, req);

        String writeBackErrors = '';
        try {
            writeBackErrors = WeaveSignatureWriteBackService.writeBack(sourceRecordId, placements, templateId);
        } catch (Exception e) {
            writeBackErrors = e.getMessage();
        }

        Blob finalPdf = Test.isRunningTest()
            ? Blob.valueOf('FINAL_PDF_TEST')
            : Blob.toPdf(wrapForSignedPdf(renderedHtml));

        ContentVersion cv = new ContentVersion();
        cv.Title            = 'Signed Document';
        cv.PathOnClient     = 'signed_document.pdf';
        cv.VersionData      = finalPdf;
        cv.FirstPublishLocationId = sourceRecordId;
        insert as user cv;

        List<ContentVersion> saved = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id WITH USER_MODE LIMIT 1];
        req.Status__c              = 'Completed';
        req.Completed_Date__c      = DateTime.now();
        req.Final_Content_Version_Id__c = saved[0].Id;
        if (String.isNotBlank(writeBackErrors)) req.WriteBack_Errors__c = writeBackErrors;
        update as user req;
    }

    // ─── PIN Validation (called without sharing from VF controller) ───────────

    public static String validateAndOpenPin(Id signerId, String enteredPin) {
        List<Weave_Signer__c> rows = [
            SELECT Id, PIN_Hash__c, PIN_Expiry__c, PIN_Attempts__c, Status__c,
                   Signature_Request__r.Status__c
            FROM Weave_Signer__c WHERE Id = :signerId LIMIT 1
        ];
        if (rows.isEmpty()) return 'Invalid signing link.';
        Weave_Signer__c s = rows[0];

        String reqStatus = s.Signature_Request__r.Status__c;
        if (reqStatus == 'Canceled' || reqStatus == 'Expired')
            return 'This signature request has been ' + reqStatus.toLowerCase() + '.';
        if (s.Status__c == 'Signed')   return 'You have already signed this document.';
        if (s.Status__c == 'Canceled') return 'This signing invitation has been canceled.';
        if (s.PIN_Expiry__c != null && s.PIN_Expiry__c < DateTime.now())
            return 'Your PIN has expired. Please request a new link.';
        if (s.PIN_Attempts__c != null && s.PIN_Attempts__c >= 3)
            return 'Maximum PIN attempts exceeded. Contact the sender.';

        if (hashPin(enteredPin, signerId) != s.PIN_Hash__c) {
            s.PIN_Attempts__c = (s.PIN_Attempts__c == null ? 0 : s.PIN_Attempts__c) + 1;
            update s;
            return 'Incorrect PIN. ' + (3 - s.PIN_Attempts__c.intValue()) + ' attempt(s) remaining.';
        }

        s.Status__c    = 'Opened';
        s.Opened_At__c = DateTime.now();
        s.PIN_Attempts__c = 0;
        update s;
        return 'OK';
    }

    // ─── Sequential: advance to next signer after one completes ──────────────

    public static void advanceSequentialSigning(Id requestId) {
        List<Weave_Signature_Request__c> reqs = [
            SELECT Id, Status__c, Signing_Mode__c FROM Weave_Signature_Request__c
            WHERE Id = :requestId WITH USER_MODE LIMIT 1
        ];
        if (reqs.isEmpty() || reqs[0].Signing_Mode__c != 'Sequential') return;

        List<Weave_Signer__c> pending = [
            SELECT Id, Name, Email__c, Role__c, Sign_Order__c, Status__c
            FROM Weave_Signer__c
            WHERE Signature_Request__c = :requestId AND Status__c = 'Pending'
            WITH USER_MODE ORDER BY Sign_Order__c ASC NULLS LAST LIMIT 1
        ];
        if (!pending.isEmpty()) generateAndSendPin(pending[0], reqs[0]);
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static void generateAndSendPin(Weave_Signer__c signer, Weave_Signature_Request__c req) {
        String pin = String.valueOf(Math.abs(Math.mod(Crypto.getRandomInteger(), 1000000))).leftPad(6, '0');
        signer.PIN_Hash__c   = hashPin(pin, signer.Id);
        signer.PIN_Expiry__c = DateTime.now().addMinutes(10);
        signer.Status__c     = 'Sent';
        signer.Sent_At__c    = DateTime.now();
        update signer;

        String token      = EncodingUtil.base64Encode(Blob.valueOf(signer.Id + ':' + pin));
        String signingUrl = getSiteBaseUrl() + '/weave-sign?token=' + EncodingUtil.urlEncode(token, 'UTF-8');

        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setToAddresses(new List<String>{ signer.Email__c });
        m.setSubject('Action Required: Sign Document');
        m.setHtmlBody('<p>Hello ' + signer.Name + ',</p>'
            + '<p>You have been invited to review and sign a document.</p>'
            + '<p><a href="' + signingUrl + '" style="background:#1f5f5b;color:#fff;padding:10px 20px;border-radius:6px;text-decoration:none;">Sign Now</a></p>'
            + '<p>Your one-time PIN: <strong style="font-size:18px;letter-spacing:4px;">' + pin + '</strong></p>'
            + '<p style="color:#6b7280;font-size:11px;">This PIN expires in 10 minutes.</p>');
        m.setSaveAsActivity(false);
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m });
    }

    private static String hashPin(String pin, Id signerId) {
        Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(pin + ':' + signerId));
        return EncodingUtil.convertToHex(hash);
    }

    private static String getSiteBaseUrl() {
        try { return Site.getBaseUrl(); } catch (Exception e) { return Url.getOrgDomainUrl().toExternalForm(); }
    }

    private static Boolean isDocumentTemplate(Id templateId) {
        try {
            List<Weave_Template_Config__c> t = [
                SELECT Template_Output_Type__c FROM Weave_Template_Config__c
                WHERE Id = :templateId WITH USER_MODE LIMIT 1
            ];
            return !t.isEmpty() && t[0].get('Template_Output_Type__c') == 'Document';
        } catch (Exception e) { return false; }
    }

    private static Weave_Signer__c lowestOrderSigner(List<Weave_Signer__c> signers) {
        Weave_Signer__c first = signers[0];
        for (Weave_Signer__c s : signers) {
            Integer cur  = s.Sign_Order__c != null ? s.Sign_Order__c.intValue() : 999;
            Integer best = first.Sign_Order__c != null ? first.Sign_Order__c.intValue() : 999;
            if (cur < best) first = s;
        }
        return first;
    }

    private static List<Weave_Signature_Placement__c> buildPlacements(
        Id requestId, List<Weave_Signer__c> signers, Id templateId, Id sourceRecordId
    ) {
        String html = '';
        try {
            Boolean isCanvas = isDocumentTemplate(templateId);
            WeaveEmailTemplateRenderer.RenderedEmailDTO r = isCanvas
                ? WeaveEmailTemplateRenderer.renderCanvas(templateId, sourceRecordId)
                : WeaveEmailTemplateRenderer.renderEmail(templateId, sourceRecordId);
            html = r.htmlBody != null ? r.htmlBody : '';
        } catch (Exception e) { return new List<Weave_Signature_Placement__c>(); }

        Map<String, Weave_Signer__c> byRole = new Map<String, Weave_Signer__c>();
        for (Weave_Signer__c s : signers) {
            if (String.isNotBlank(s.Role__c)) byRole.put(s.Role__c.toLowerCase(), s);
        }

        // Pattern: {{@Role}}, {{@initials:Role}}, {{@date:Role}}, {{@field:Label:Role[:type]}}
        Pattern p = Pattern.compile('\\{\\{@(?:(initials|date|field):)?([^:}\\n]+)(?::([^:}\\n]*))?(?::([^}\\n]*))?\\}\\}');
        Matcher m = p.matcher(html);
        List<Weave_Signature_Placement__c> results = new List<Weave_Signature_Placement__c>();
        while (m.find()) {
            String modifier     = m.group(1);
            String roleOrLabel  = m.group(2);
            String roleForField = m.group(3);
            String plType = 'Full';
            String role   = roleOrLabel;

            if      ('initials'.equalsIgnoreCase(modifier)) { plType = 'Initials'; }
            else if ('date'.equalsIgnoreCase(modifier))     { plType = 'Date'; }
            else if ('field'.equalsIgnoreCase(modifier))    { plType = 'Field'; role = roleForField; }

            if (String.isBlank(role)) continue;
            Weave_Signer__c signer = byRole.get(role.toLowerCase());

            results.add(new Weave_Signature_Placement__c(
                Signature_Request__c = requestId,
                Signer__c   = signer != null ? signer.Id : null,
                Type__c     = plType,
                Role__c     = role,
                Page__c     = 1,
                X_In__c     = 1.0,
                Y_In__c     = 9.0,
                W_In__c     = plType == 'Initials' ? 1.0 : 2.5,
                H_In__c     = plType == 'Date' ? 0.3 : 0.75
            ));
        }
        return results;
    }

    private static String buildCertificatePage(List<Weave_Signer__c> signers, Weave_Signature_Request__c req) {
        String rows = '';
        for (Weave_Signer__c s : signers) {
            rows += '<tr>'
                + '<td>' + esc(s.Name) + '</td>'
                + '<td>' + esc(s.Email__c) + '</td>'
                + '<td>' + esc(s.Role__c) + '</td>'
                + '<td>' + esc(s.Status__c) + '</td>'
                + '<td>' + (s.Signed_At__c != null ? String.valueOf(s.Signed_At__c) : '') + '</td>'
                + '<td>' + esc(s.IP_Address__c) + '</td>'
                + '</tr>';
        }
        return '<div style="page-break-before:always;padding:48pt;">'
            + '<h2 style="font-family:Arial,sans-serif;font-size:16pt;color:#1f5f5b;margin:0 0 12pt;">Certificate of Completion</h2>'
            + '<p style="font-family:Arial,sans-serif;font-size:10pt;color:#444;">This document was signed electronically in accordance with applicable electronic signature laws (US ESIGN Act and UETA).</p>'
            + '<p style="font-family:Arial,sans-serif;font-size:10pt;color:#444;">Completed: ' + (req.Completed_Date__c != null ? String.valueOf(req.Completed_Date__c) : String.valueOf(DateTime.now())) + '</p>'
            + '<table style="width:100%;border-collapse:collapse;font-family:Arial,sans-serif;font-size:9pt;margin-top:12pt;">'
            + '<thead><tr style="background:#1f5f5b;color:#fff;"><th style="padding:6px;text-align:left;">Name</th><th>Email</th><th>Role</th><th>Status</th><th>Signed At</th><th>IP Address</th></tr></thead>'
            + '<tbody>' + rows + '</tbody></table></div>';
    }

    private static String wrapForSignedPdf(String htmlBody) {
        return '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Signed Document</title>'
            + '<style>@page{margin:0.75in;}body{font-family:Arial,Helvetica,sans-serif;font-size:11pt;color:#222;}'
            + 'table{border-collapse:collapse;width:100%;}td,th{padding:4px;border:1px solid #d1d5db;}'
            + 'img{max-width:100%;height:auto;}</style></head><body>'
            + (htmlBody != null ? htmlBody : '') + '</body></html>';
    }

    private static String esc(String s) { return s != null ? s.escapeHtml4() : ''; }
    private static String escAttr(String s) { return s != null ? s.replace('"', '&quot;') : ''; }
}
