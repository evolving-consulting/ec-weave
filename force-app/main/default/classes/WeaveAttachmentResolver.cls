@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces')
public with sharing class WeaveAttachmentResolver {

    public static List<Id> resolveDocumentIds(Id templateId, Id recordId) {
        List<Weave_Template_Attachment__c> configs = [
            SELECT Attachment_Source__c, Static_Content_Document_Id__c,
                   Linked_Query__c, Linked_Query__r.SOQL_Query__c,
                   Linked_Query__r.Parent_Lookup_Field__c,
                   File_Title_Filter__c, Max_Attachments__c
            FROM Weave_Template_Attachment__c
            WHERE Weave_Template_Config__c = :templateId AND Active__c = true
            WITH USER_MODE
            ORDER BY Display_Order__c ASC NULLS LAST
        ];

        List<Id> docIds = new List<Id>();
        Set<Id> seen = new Set<Id>();

        for (Weave_Template_Attachment__c cfg : configs) {
            List<Id> resolved = new List<Id>();
            if (cfg.Attachment_Source__c == 'Static File') {
                resolved = resolveStatic(cfg);
            } else if (cfg.Attachment_Source__c == 'Source Record Files') {
                resolved = resolveFromRecord(recordId, cfg);
            } else if (cfg.Attachment_Source__c == 'Related Record Files') {
                resolved = resolveFromRelatedRecord(recordId, cfg);
            }
            Integer cap = cfg.Max_Attachments__c != null ? cfg.Max_Attachments__c.intValue() : 5;
            Integer added = 0;
            for (Id docId : resolved) {
                if (added >= cap) break;
                if (docId != null && !seen.contains(docId)) {
                    docIds.add(docId);
                    seen.add(docId);
                    added++;
                }
            }
        }
        return docIds;
    }

    private static List<Id> resolveStatic(Weave_Template_Attachment__c cfg) {
        if (String.isBlank(cfg.Static_Content_Document_Id__c)) return new List<Id>();
        try {
            return new List<Id>{ (Id) cfg.Static_Content_Document_Id__c };
        } catch (Exception e) {
            return new List<Id>();
        }
    }

    private static List<Id> resolveFromRecord(Id recordId, Weave_Template_Attachment__c cfg) {
        if (recordId == null) return new List<Id>();
        return queryLinks(new Set<Id>{ recordId }, cfg.File_Title_Filter__c, cfg.Max_Attachments__c);
    }

    private static List<Id> resolveFromRelatedRecord(Id sourceRecordId, Weave_Template_Attachment__c cfg) {
        if (sourceRecordId == null || cfg.Linked_Query__c == null
                || String.isBlank(cfg.Linked_Query__r.SOQL_Query__c)
                || String.isBlank(cfg.Linked_Query__r.Parent_Lookup_Field__c)) {
            return new List<Id>();
        }
        try {
            String soql = cfg.Linked_Query__r.SOQL_Query__c;
            String parentField = cfg.Linked_Query__r.Parent_Lookup_Field__c;
            // Inject parent filter — append to existing WHERE or add one
            String lowerSoql = soql.toLowerCase();
            if (lowerSoql.contains(' where ')) {
                soql = soql + ' AND ' + parentField + ' = :sourceRecordId LIMIT 1';
            } else {
                soql = soql + ' WHERE ' + parentField + ' = :sourceRecordId LIMIT 1';
            }
            List<SObject> related = Database.query(soql);
            if (related.isEmpty()) return new List<Id>();
            return queryLinks(new Set<Id>{ related[0].Id }, cfg.File_Title_Filter__c, cfg.Max_Attachments__c);
        } catch (Exception e) {
            return new List<Id>();
        }
    }

    private static List<Id> queryLinks(Set<Id> entityIds, String titleFilter, Decimal maxCount) {
        Integer lim = maxCount != null ? maxCount.intValue() : 5;
        List<Id> ids = new List<Id>();
        if (String.isBlank(titleFilter)) {
            for (ContentDocumentLink cdl : [
                SELECT ContentDocumentId FROM ContentDocumentLink
                WHERE LinkedEntityId IN :entityIds WITH USER_MODE LIMIT :lim
            ]) {
                ids.add(cdl.ContentDocumentId);
            }
        } else {
            String filter = '%' + titleFilter + '%';
            for (ContentDocumentLink cdl : [
                SELECT ContentDocumentId FROM ContentDocumentLink
                WHERE LinkedEntityId IN :entityIds
                AND ContentDocument.Title LIKE :filter WITH USER_MODE LIMIT :lim
            ]) {
                ids.add(cdl.ContentDocumentId);
            }
        }
        return ids;
    }
}
