global without sharing class WeaveSignatureController {

    // ─── Page state (read by VF bindings) ────────────────────────────────────
    public String signerName    { get; private set; }
    public String signerRole    { get; private set; }
    public String documentTitle { get; private set; }
    public String errorMessage  { get; private set; }
    public Boolean isPinVerified { get; private set; }
    public Boolean isAlreadySigned { get; private set; }
    public Boolean isTerminal   { get; private set; }
    public Id signerId          { get; private set; }
    public String signerIdStr   { get; private set; }

    // Placements serialized to JSON for JS consumption
    public String placementsJson { get; private set; }
    // Form fields serialized to JSON
    public String formFieldsJson { get; private set; }

    public WeaveSignatureController() {
        isPinVerified  = false;
        isAlreadySigned = false;
        isTerminal     = false;
        errorMessage   = '';
        placementsJson = '[]';
        formFieldsJson = '[]';

        String token = ApexPages.currentPage().getParameters().get('token');
        if (String.isBlank(token)) {
            errorMessage = 'Invalid signing link.';
            isTerminal   = true;
            return;
        }

        try {
            Blob decoded = EncodingUtil.base64Decode(token);
            String[] parts = decoded.toString().split(':');
            if (parts.size() < 2) {
                errorMessage = 'Invalid signing link.';
                isTerminal   = true;
                return;
            }
            signerId    = (Id) parts[0];
            signerIdStr = parts[0];
            String pin  = parts[1];

            List<Weave_Signer__c> rows = [
                SELECT Id, Name, Role__c, Status__c,
                       Signature_Request__c,
                       Signature_Request__r.Status__c,
                       Signature_Request__r.Template_Id__c,
                       Signature_Request__r.Template_Id__r.Name
                FROM Weave_Signer__c WHERE Id = :signerId LIMIT 1
            ];
            if (rows.isEmpty()) {
                errorMessage = 'Invalid signing link.';
                isTerminal   = true;
                return;
            }
            Weave_Signer__c s = rows[0];
            signerName  = s.Name;
            signerRole  = s.Role__c;
            documentTitle = s.Signature_Request__r.Template_Id__r != null
                ? s.Signature_Request__r.Template_Id__r.Name
                : 'Document';

            String reqStatus = s.Signature_Request__r.Status__c;
            if (reqStatus == 'Canceled' || reqStatus == 'Expired' || reqStatus == 'Completed') {
                errorMessage  = 'This signature request is ' + reqStatus.toLowerCase() + '.';
                isTerminal    = true;
                return;
            }
            if (s.Status__c == 'Signed') {
                isAlreadySigned = true;
                isPinVerified   = true;
                return;
            }
            if (s.Status__c == 'Canceled') {
                errorMessage = 'Your signing invitation has been canceled.';
                isTerminal   = true;
                return;
            }

            String result = WeaveSignatureService.validateAndOpenPin(signerId, pin);
            if (result == 'OK') {
                isPinVerified = true;
                loadPlacements(s.Signature_Request__c, s.Signature_Request__r.Template_Id__c);
            } else {
                errorMessage = result;
            }
        } catch (Exception e) {
            errorMessage = 'An error occurred loading this signing link.';
        }
    }

    private void loadPlacements(Id requestId, Id templateId) {
        List<Map<String,Object>> pls = new List<Map<String,Object>>();
        for (Weave_Signature_Placement__c pl : [
            SELECT Id, Type__c, Role__c, W_In__c, H_In__c
            FROM Weave_Signature_Placement__c
            WHERE Signature_Request__c = :requestId
            AND Signer__c = :signerId
        ]) {
            pls.add(new Map<String,Object>{
                'id'    => pl.Id,
                'type'  => pl.Type__c,
                'role'  => pl.Role__c,
                'wIn'   => pl.W_In__c,
                'hIn'   => pl.H_In__c
            });
        }
        placementsJson = JSON.serialize(pls);

        // Form fields for this signer's role
        if (templateId != null && String.isNotBlank(signerRole)) {
            List<Map<String,Object>> ffs = new List<Map<String,Object>>();
            for (Weave_Signature_Form_Field__c f : [
                SELECT Id, Tag_Label__c, Field_Type__c, Required__c, Picklist_Values__c, Display_Order__c
                FROM Weave_Signature_Form_Field__c
                WHERE Weave_Template_Config__c = :templateId
                AND Signer_Role__c = :signerRole
                ORDER BY Display_Order__c ASC NULLS LAST
            ]) {
                ffs.add(new Map<String,Object>{
                    'label'     => f.Tag_Label__c,
                    'type'      => f.Field_Type__c,
                    'required'  => f.Required__c,
                    'options'   => f.Picklist_Values__c,
                    'order'     => f.Display_Order__c
                });
            }
            formFieldsJson = JSON.serialize(ffs);
        }
    }

    // ─── @RemoteAction methods (called from VF page JavaScript) ──────────────

    @RemoteAction
    global static String submitSignatures(String signerIdStr, String signaturesJson, String formValuesJson) {
        try {
            Id sigId = (Id) signerIdStr;
            List<Weave_Signer__c> signers = [
                SELECT Id, Status__c, Signature_Request__c,
                       Signature_Request__r.Status__c,
                       Signature_Request__r.Signing_Mode__c
                FROM Weave_Signer__c WHERE Id = :sigId LIMIT 1
            ];
            if (signers.isEmpty()) return 'Error: Signer not found.';
            Weave_Signer__c signer = signers[0];
            if (signer.Status__c == 'Signed') return 'Already signed.';
            if (signer.Signature_Request__r.Status__c == 'Canceled') return 'Error: Request has been canceled.';

            Map<String,Object> sigs       = (Map<String,Object>) JSON.deserializeUntyped(signaturesJson);
            Map<String,Object> formValues = (Map<String,Object>) JSON.deserializeUntyped(formValuesJson);

            List<Weave_Signature_Placement__c> placements = [
                SELECT Id, Type__c, Role__c, Signer__c
                FROM Weave_Signature_Placement__c
                WHERE Signature_Request__c = :signer.Signature_Request__c
                AND Signer__c = :sigId
            ];
            List<Weave_Signature_Placement__c> toUpdate = new List<Weave_Signature_Placement__c>();
            for (Weave_Signature_Placement__c pl : placements) {
                String roleKey = pl.Role__c != null ? pl.Role__c.toLowerCase() : '';
                if ((pl.Type__c == 'Full' || pl.Type__c == 'Initials') && sigs.containsKey(roleKey)) {
                    pl.Collected_Value__c = (String) sigs.get(roleKey);
                    toUpdate.add(pl);
                } else if (pl.Type__c == 'Field' && formValues.containsKey(roleKey)) {
                    pl.Collected_Value__c = (String) formValues.get(roleKey);
                    toUpdate.add(pl);
                } else if (pl.Type__c == 'Date') {
                    pl.Collected_Value__c = String.valueOf(DateTime.now());
                    toUpdate.add(pl);
                }
            }
            if (!toUpdate.isEmpty()) update toUpdate;

            // Stamp IP from page parameter (passed from JS)
            signer.Status__c   = 'Signed';
            signer.Signed_At__c = DateTime.now();
            update signer;

            checkAndFinalize(signer.Signature_Request__c, signer.Signature_Request__r.Signing_Mode__c);
            return 'OK';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }

    @RemoteAction
    global static String declineRequest(String signerIdStr, String reason) {
        try {
            Id sigId = (Id) signerIdStr;
            List<Weave_Signer__c> rows = [
                SELECT Id, Status__c, Signature_Request__c FROM Weave_Signer__c WHERE Id = :sigId LIMIT 1
            ];
            if (rows.isEmpty()) return 'Error: Not found.';
            Weave_Signer__c s = rows[0];
            s.Status__c       = 'Declined';
            s.Decline_Reason__c = reason;
            update s;

            Weave_Signature_Request__c req = new Weave_Signature_Request__c(
                Id = s.Signature_Request__c, Status__c = 'Declined'
            );
            update req;
            return 'OK';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }

    private static void checkAndFinalize(Id requestId, String signingMode) {
        List<Weave_Signer__c> pending = [
            SELECT Id FROM Weave_Signer__c
            WHERE Signature_Request__c = :requestId
            AND Status__c NOT IN ('Signed', 'Declined', 'Canceled')
            LIMIT 1
        ];
        if (pending.isEmpty()) {
            try {
                WeaveSignatureService.finalizeDocument(requestId);
            } catch (Exception e) {
                update new Weave_Signature_Request__c(Id = requestId, WriteBack_Errors__c = e.getMessage());
            }
        } else if (signingMode == 'Sequential') {
            WeaveSignatureService.advanceSequentialSigning(requestId);
        }
    }
}
