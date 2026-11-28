// PMD.ApexSOQLInjection: soqlFields entries are either schema-validated simple field names
// (checked via Schema.getGlobalDescribe()) or relationship paths extracted from admin-configured
// merge tags — not user-supplied input. parentObjectApiName is escapeSingleQuotes-protected.
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.ApexDoc,PMD.ApexSOQLInjection,PMD.NcssMethodCount,PMD.NcssTypeCount,PMD.NcssConstructorCount')
public with sharing class WeavePostSendActionService {

    public static void executeActions(Id templateId, Id sourceRecordId, String parentObjectApiName) {
        if (templateId == null || sourceRecordId == null) return;
        List<Weave_Template_Action__c> actions = [
            SELECT Id, Action_Type__c, Run_Order__c, Active__c,
                Field_API_Name__c, Value_Type__c, Value__c,
                Task_Subject__c, Assigned_To_Type__c, Assigned_User_Id__c,
                Due_Date_Strategy__c, Days_After_Send__c,
                Task_Status__c, Task_Priority__c, Task_Description__c
            FROM Weave_Template_Action__c
            WHERE Weave_Template_Config__c = :templateId AND Active__c = true
            WITH USER_MODE
            ORDER BY Run_Order__c ASC NULLS LAST
        ];
        if (actions.isEmpty()) return;

        SObject sourceRecord = querySourceRecordForTasks(actions, sourceRecordId, parentObjectApiName);

        List<SObject> recordUpdates = new List<SObject>();
        List<Task> taskInserts = new List<Task>();

        for (Weave_Template_Action__c action : actions) {
            if (action.Action_Type__c == 'Update Field') {
                SObject updateRecord = handleUpdateField(action, sourceRecordId, parentObjectApiName, sourceRecord);
                if (updateRecord != null) recordUpdates.add(updateRecord);
            } else if (action.Action_Type__c == 'Create Task') {
                Task t = handleCreateTask(action, sourceRecordId, sourceRecord, parentObjectApiName);
                if (t != null) taskInserts.add(t);
            }
        }

        if (!recordUpdates.isEmpty()) update as user recordUpdates;
        if (!taskInserts.isEmpty()) insert as user taskInserts;
    }

    private static SObject querySourceRecordForTasks(List<Weave_Template_Action__c> actions, Id sourceRecordId, String parentObjectApiName) {
        if (String.isBlank(parentObjectApiName) || !Schema.getGlobalDescribe().containsKey(parentObjectApiName)) return null;

        Set<String> fieldPaths = new Set<String>{ 'Id', 'Name' };
        for (Weave_Template_Action__c action : actions) {
            if (action.Action_Type__c == 'Create Task') {
                if (!String.isBlank(action.Task_Subject__c)) {
                    fieldPaths.addAll(GenericMergeFieldResolver.extractParentFieldPaths(action.Task_Subject__c, parentObjectApiName, null));
                }
                if (!String.isBlank(action.Task_Description__c)) {
                    fieldPaths.addAll(GenericMergeFieldResolver.extractParentFieldPaths(action.Task_Description__c, parentObjectApiName, null));
                }
            } else if (action.Action_Type__c == 'Update Field' && action.Value_Type__c == 'Merge Field' && !String.isBlank(action.Value__c)) {
                fieldPaths.addAll(GenericMergeFieldResolver.extractParentFieldPaths(action.Value__c, parentObjectApiName, null));
            }
        }

        Map<String, Schema.SObjectField> objectFields = Schema.getGlobalDescribe()
            .get(parentObjectApiName).getDescribe().fields.getMap();

        Set<String> soqlFields = new Set<String>{ 'Id' };
        for (String fp : fieldPaths) {
            if (String.isBlank(fp)) continue;
            if (fp.contains('.')) {
                soqlFields.add(fp);
            } else if (objectFields.containsKey(fp.toLowerCase())) {
                soqlFields.add(fp);
            }
        }

        try {
            String soql = 'SELECT ' + String.join(new List<String>(soqlFields), ', ')
                + ' FROM ' + String.escapeSingleQuotes(parentObjectApiName)
                + ' WHERE Id = :sourceRecordId WITH USER_MODE LIMIT 1';
            List<SObject> records = Database.query(soql);
            return records.isEmpty() ? null : records[0];
        } catch (Exception e) {
            return null;
        }
    }

    private static SObject handleUpdateField(Weave_Template_Action__c action, Id recordId, String objectApiName, SObject sourceRecord) {
        if (String.isBlank(action.Field_API_Name__c)) return null;
        if (String.isBlank(objectApiName) || !Schema.getGlobalDescribe().containsKey(objectApiName)) return null;

        SObject record = Schema.getGlobalDescribe().get(objectApiName).newSObject(recordId);
        Object fieldValue = resolveFieldValue(action, sourceRecord, objectApiName);
        record.put(action.Field_API_Name__c, fieldValue);
        return record;
    }

    private static Object resolveFieldValue(Weave_Template_Action__c action, SObject sourceRecord, String parentObjectApiName) {
        String valueType = action.Value_Type__c;
        if (valueType == 'Boolean') return Boolean.valueOf(action.Value__c);
        if (valueType == 'Current Date') return Date.today();
        if (valueType == 'Current DateTime') return DateTime.now();
        if (valueType == 'Merge Field' && sourceRecord != null && !String.isBlank(action.Value__c)) {
            GenericMergeFieldResolver.MergeContext ctx = new GenericMergeFieldResolver.MergeContext();
            ctx.parentRecord = sourceRecord;
            ctx.parentObjectApiName = parentObjectApiName;
            ctx.escapeHtml = false;
            return GenericMergeFieldResolver.resolveTemplate(action.Value__c, ctx);
        }
        return action.Value__c;
    }

    private static Task handleCreateTask(Weave_Template_Action__c action, Id sourceRecordId, SObject sourceRecord, String parentObjectApiName) {
        GenericMergeFieldResolver.MergeContext ctx = new GenericMergeFieldResolver.MergeContext();
        ctx.parentRecord = sourceRecord;
        ctx.parentObjectApiName = parentObjectApiName;
        ctx.escapeHtml = false;

        Task t = new Task();
        String subjectTemplate = String.isBlank(action.Task_Subject__c) ? 'Email Sent' : action.Task_Subject__c;
        t.Subject = GenericMergeFieldResolver.resolveTemplate(subjectTemplate, ctx);
        t.WhatId = sourceRecordId;
        t.Status = String.isBlank(action.Task_Status__c) ? 'Completed' : action.Task_Status__c;
        t.Priority = String.isBlank(action.Task_Priority__c) ? 'Normal' : action.Task_Priority__c;
        t.Description = String.isBlank(action.Task_Description__c)
            ? null
            : GenericMergeFieldResolver.resolveTemplate(action.Task_Description__c, ctx);

        // Assigned to
        if (action.Assigned_To_Type__c == 'Specific User' && !String.isBlank(action.Assigned_User_Id__c)) {
            t.OwnerId = (Id) action.Assigned_User_Id__c;
        } else {
            t.OwnerId = UserInfo.getUserId();
        }

        // Due date
        if (action.Due_Date_Strategy__c == 'N Days After Send' && action.Days_After_Send__c != null) {
            t.ActivityDate = Date.today().addDays(action.Days_After_Send__c.intValue());
        } else {
            t.ActivityDate = Date.today();
        }
        return t;
    }
}
