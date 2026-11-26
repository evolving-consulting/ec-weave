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
    public static List<Weave_Signature_Form_Field__c> getSignerFormFields(String templateId) {
        try {
            return [
                SELECT Id, Tag_Label__c, Signer_Role__c, Field_Type__c,
                       Target_Field_Api_Name__c, Required__c, Picklist_Values__c, Display_Order__c
                FROM Weave_Signature_Form_Field__c
                WHERE Weave_Template_Config__c = :templateId
                WITH USER_MODE ORDER BY Display_Order__c ASC NULLS LAST
            ];
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
