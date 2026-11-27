public with sharing class WeaveSignatureAuraController {

    @AuraEnabled
    public static void createSignatureRequest(
        String templateId,
        String sourceRecordId,
        String contentVersionId,
        String signingMode,
        Integer expiryDays,
        String signerInputsJson
    ) {
        try {
            List<WeaveSignatureService.SignerInput> inputs = parseSignerInputs(signerInputsJson);
            WeaveSignatureService.createRequest(
                (Id) templateId,
                (Id) sourceRecordId,
                contentVersionId,
                signingMode,
                expiryDays,
                inputs
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void cancelSignatureRequest(String requestId, String cancelReason) {
        try {
            WeaveSignatureService.cancelRequest((Id) requestId, cancelReason);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Weave_Signature_Request__c> getSignatureRequests(
        String sourceRecordId,
        String signatureRequestId
    ) {
        try {
            if (String.isNotBlank(signatureRequestId)) {
                return [
                    SELECT Id, Name, Status__c, Signing_Mode__c, Expiry_Date__c, Completed_Date__c,
                           Cancel_Reason__c,
                           (SELECT Id, Name, Email__c, Role__c, Status__c, Sign_Order__c,
                                   Signed_At__c, Sent_At__c, Opened_At__c
                            FROM Signers__r ORDER BY Sign_Order__c ASC NULLS LAST)
                    FROM Weave_Signature_Request__c
                    WHERE Id = :signatureRequestId
                    WITH USER_MODE LIMIT 1
                ];
            }
            if (String.isNotBlank(sourceRecordId)) {
                return [
                    SELECT Id, Name, Status__c, Signing_Mode__c, Expiry_Date__c, Completed_Date__c,
                           Cancel_Reason__c,
                           (SELECT Id, Name, Email__c, Role__c, Status__c, Sign_Order__c,
                                   Signed_At__c, Sent_At__c, Opened_At__c
                            FROM Signers__r ORDER BY Sign_Order__c ASC NULLS LAST)
                    FROM Weave_Signature_Request__c
                    WHERE Source_Record_Id__c = :sourceRecordId
                    WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 10
                ];
            }
            return new List<Weave_Signature_Request__c>();
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String,Object>> getSignerFormFields(String templateId) {
        try {
            List<Weave_Signature_Form_Field__c> recs = [
                SELECT Id, Tag_Label__c, Signer_Role__c, Field_Type__c,
                       Target_Field_Api_Name__c, Required__c, Picklist_Values__c,
                       Display_Order__c, Write_Back__c, On_Certificate__c
                FROM Weave_Signature_Form_Field__c
                WHERE Weave_Template_Config__c = :templateId
                WITH USER_MODE ORDER BY Display_Order__c ASC NULLS LAST
            ];
            List<Map<String,Object>> result = new List<Map<String,Object>>();
            for (Weave_Signature_Form_Field__c f : recs) {
                // Compute the unified merge tag: {{@Role:Field:Label}}
                String role  = String.isNotBlank(f.Signer_Role__c) ? f.Signer_Role__c.trim() : 'Signer';
                String label = String.isNotBlank(f.Tag_Label__c)   ? f.Tag_Label__c.trim()   : 'Field';
                String tag   = '{{@' + role + ':Field:' + label + '}}';
                Map<String,Object> row = new Map<String,Object>();
                row.put('Id',                    f.Id);
                row.put('Tag_Label__c',          f.Tag_Label__c);
                row.put('Signer_Role__c',        f.Signer_Role__c);
                row.put('Field_Type__c',         f.Field_Type__c);
                row.put('Target_Field_Api_Name__c', f.Target_Field_Api_Name__c);
                row.put('Required__c',           f.Required__c);
                row.put('Picklist_Values__c',    f.Picklist_Values__c);
                row.put('Display_Order__c',      f.Display_Order__c);
                row.put('Write_Back__c',         f.Write_Back__c);
                row.put('On_Certificate__c',     f.On_Certificate__c);
                row.put('mergeTag',              tag);
                result.add(row);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void upsertSignerFormField(String fieldJson) {
        try {
            Map<String,Object> raw = (Map<String,Object>) JSON.deserializeUntyped(fieldJson);
            Weave_Signature_Form_Field__c f = new Weave_Signature_Form_Field__c();
            if (raw.containsKey('Id') && raw.get('Id') != null) f.Id = (Id) raw.get('Id');
            f.Weave_Template_Config__c   = (Id)      raw.get('templateId');
            f.Tag_Label__c               = (String)  raw.get('tagLabel');
            f.Signer_Role__c             = (String)  raw.get('signerRole');
            f.Field_Type__c              = (String)  raw.get('fieldType');
            f.Target_Field_Api_Name__c   = (String)  raw.get('targetFieldApiName');
            f.Required__c                = raw.containsKey('required') && (Boolean) raw.get('required');
            f.Write_Back__c              = raw.containsKey('writeBack') && (Boolean) raw.get('writeBack');
            f.On_Certificate__c          = raw.containsKey('onCertificate') && (Boolean) raw.get('onCertificate');
            f.Picklist_Values__c         = (String)  raw.get('picklistValues');
            if (raw.containsKey('displayOrder') && raw.get('displayOrder') != null) {
                f.Display_Order__c = Decimal.valueOf(String.valueOf(raw.get('displayOrder')));
            }
            upsert as user f;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getTemplateSignerRoles(String templateId) {
        List<Weave_Template_Config__c> rows = [
            SELECT Signer_Roles__c FROM Weave_Template_Config__c
            WHERE Id = :templateId WITH USER_MODE LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Signer_Roles__c;
    }

    @AuraEnabled
    public static void deleteSignerFormField(String fieldId) {
        try {
            delete as user new Weave_Signature_Form_Field__c(Id = (Id) fieldId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static List<WeaveSignatureService.SignerInput> parseSignerInputs(String jsonStr) {
        List<Object> raw = (List<Object>) JSON.deserializeUntyped(jsonStr);
        List<WeaveSignatureService.SignerInput> inputs = new List<WeaveSignatureService.SignerInput>();
        for (Object obj : raw) {
            Map<String,Object> m = (Map<String,Object>) obj;
            WeaveSignatureService.SignerInput si = new WeaveSignatureService.SignerInput();
            si.name      = (String) m.get('name');
            si.email     = (String) m.get('email');
            si.role      = (String) m.get('role');
            si.signOrder = m.containsKey('signOrder') && m.get('signOrder') != null
                ? Integer.valueOf(String.valueOf(m.get('signOrder'))) : 1;
            inputs.add(si);
        }
        return inputs;
    }
}
