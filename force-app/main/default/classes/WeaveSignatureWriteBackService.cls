@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.ApexDoc,PMD.NcssMethodCount,PMD.NcssTypeCount,PMD.NcssConstructorCount')
public with sharing class WeaveSignatureWriteBackService {

    // Returns error string; empty string means all succeeded.
    public static String writeBack(
        Id sourceRecordId,
        List<Weave_Signature_Placement__c> placements,
        Id templateId
    ) {
        if (sourceRecordId == null || templateId == null) return '';

        List<Weave_Signature_Form_Field__c> configs = [
            SELECT Tag_Label__c, Target_Field_Api_Name__c, Field_Type__c, Write_Back__c
            FROM Weave_Signature_Form_Field__c
            WHERE Weave_Template_Config__c = :templateId
            AND Write_Back__c = true
            WITH USER_MODE
        ];
        if (configs.isEmpty()) return '';

        Map<String, String> labelToApi  = new Map<String, String>();
        Map<String, String> labelToType = new Map<String, String>();
        for (Weave_Signature_Form_Field__c c : configs) {
            if (String.isNotBlank(c.Tag_Label__c) && String.isNotBlank(c.Target_Field_Api_Name__c)) {
                labelToApi.put(c.Tag_Label__c.toLowerCase(),  c.Target_Field_Api_Name__c);
                labelToType.put(c.Tag_Label__c.toLowerCase(), c.Field_Type__c);
            }
        }

        SObject record = sourceRecordId.getSObjectType().newSObject(sourceRecordId);
        Boolean hasValues = false;
        List<String> errors = new List<String>();

        for (Weave_Signature_Placement__c pl : placements) {
            if (pl.Type__c != 'Field' || String.isBlank(pl.Collected_Value__c)) continue;
            // Field_Label__c holds the label part of {{@Role:Field:Label}}
            String lbl      = String.isNotBlank(pl.Field_Label__c) ? pl.Field_Label__c.toLowerCase() : '';
            String fieldApi = labelToApi.get(lbl);
            if (String.isBlank(fieldApi)) continue;

            String fType = labelToType.get(lbl);
            try {
                if ('Checkbox'.equalsIgnoreCase(fType)) {
                    record.put(fieldApi, 'true'.equalsIgnoreCase(pl.Collected_Value__c));
                } else if ('Number'.equalsIgnoreCase(fType) || 'Currency'.equalsIgnoreCase(fType)) {
                    record.put(fieldApi, Decimal.valueOf(pl.Collected_Value__c));
                } else if ('Date'.equalsIgnoreCase(fType)) {
                    record.put(fieldApi, Date.valueOf(pl.Collected_Value__c));
                } else {
                    record.put(fieldApi, pl.Collected_Value__c);
                }
                hasValues = true;
            } catch (Exception e) {
                errors.add(fieldApi + ': ' + e.getMessage());
            }
        }

        if (!hasValues) return '';

        try {
            update as user record;
        } catch (Exception e) {
            errors.add('DML: ' + e.getMessage());
        }
        return String.join(errors, '; ');
    }
}
