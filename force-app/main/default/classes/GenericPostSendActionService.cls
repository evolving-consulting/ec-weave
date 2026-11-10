/**
 * Executes configured DCE post-send actions after email delivery succeeds.
 * Actions are intentionally stored and handled generically so new action types
 * can be added by registering another handler.
 */
public with sharing class GenericPostSendActionService {
    private static final String ACTION_UPDATE_FIELD = 'Update Field';
    private static final String ACTION_CREATE_TASK = 'Create Task';
    private static final String VALUE_STATIC = 'Static';
    private static final String VALUE_BOOLEAN = 'Boolean';
    private static final String VALUE_CURRENT_DATE = 'Current Date';
    private static final String VALUE_CURRENT_DATETIME = 'Current DateTime';
    private static final String VALUE_MERGE_FIELD = 'Merge Field';
    private static final Integer MAX_TASK_SUBJECT_LENGTH = 255;
    private static final Integer MAX_TASK_DESCRIPTION_LENGTH = 32000;

    private virtual class ActionHandler {
        public virtual void execute(DceBuilderPostSendActionDTO action, ExecutionContext context) {
        }
    }

    private class ExecutionContext {
        public Email_Template_Config__c template;
        public Id parentRecordId;
        public String parentObjectApiName;
        public Datetime sentAt;
        public SObject parentRecord;
        public Map<String, Schema.SObjectField> parentFields;
        public Map<String, Object> pendingParentUpdates;
        public List<Task> tasksToInsert;
        public List<String> warnings;

        public ExecutionContext(Email_Template_Config__c template, Id parentRecordId, String parentObjectApiName, Datetime sentAt) {
            this.template = template;
            this.parentRecordId = parentRecordId;
            this.parentObjectApiName = parentObjectApiName;
            this.sentAt = sentAt == null ? System.now() : sentAt;
            this.parentFields = new Map<String, Schema.SObjectField>();
            this.pendingParentUpdates = new Map<String, Object>();
            this.tasksToInsert = new List<Task>();
            this.warnings = new List<String>();
        }
    }

    public static List<String> executeActions(
        Email_Template_Config__c template,
        Id parentRecordId,
        String parentObjectApiName,
        Datetime sentAt
    ) {
        if (template == null || parentRecordId == null || String.isBlank(parentObjectApiName) || String.isBlank(template.Post_Send_Actions__c)) {
            return new List<String>();
        }

        List<DceBuilderPostSendActionDTO> actions = deserializeActions(template.Post_Send_Actions__c);
        if (actions.isEmpty()) {
            return new List<String>();
        }

        ExecutionContext context = new ExecutionContext(template, parentRecordId, parentObjectApiName, sentAt);
        if (!prepareContext(context, actions)) {
            return new List<String>{ 'Email sent, but post-send actions could not load the source record.' };
        }

        Map<String, ActionHandler> handlers = getHandlers();
        for (DceBuilderPostSendActionDTO action : sortActions(actions)) {
            if (action == null || action.active != true || String.isBlank(action.actionType) || !handlers.containsKey(action.actionType)) {
                continue;
            }
            try {
                handlers.get(action.actionType).execute(action, context);
            } catch (Exception e) {
                context.warnings.add('One post-send action could not be prepared.');
            }
        }

        flush(context);
        return context.warnings;
    }

    private static Map<String, ActionHandler> getHandlers() {
        return new Map<String, ActionHandler>{
            ACTION_UPDATE_FIELD => new UpdateFieldHandler(),
            ACTION_CREATE_TASK => new CreateTaskHandler()
        };
    }

    private class UpdateFieldHandler extends ActionHandler {
        public override void execute(DceBuilderPostSendActionDTO action, ExecutionContext context) {
            if (String.isBlank(action.fieldApiName) || !context.parentFields.containsKey(action.fieldApiName)) {
                return;
            }

            Schema.DescribeFieldResult fieldDescribe = context.parentFields.get(action.fieldApiName).getDescribe();
            if (!fieldDescribe.isUpdateable()) {
                return;
            }

            Object convertedValue = convertValue(action, fieldDescribe, context);
            context.pendingParentUpdates.put(action.fieldApiName, convertedValue);
        }
    }

    private class CreateTaskHandler extends ActionHandler {
        public override void execute(DceBuilderPostSendActionDTO action, ExecutionContext context) {
            if (!Task.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isCreateable()) {
                return;
            }

            Task task = new Task();
            task.Subject = truncate(resolveText(action.subject, context), MAX_TASK_SUBJECT_LENGTH);
            if (String.isBlank(task.Subject)) {
                task.Subject = 'Follow up';
            }
            task.OwnerId = resolveTaskOwnerId(action, context);
            task.Status = String.isBlank(action.status) ? 'Not Started' : action.status;
            task.Priority = String.isBlank(action.priority) ? 'Normal' : action.priority;
            task.ActivityDate = context.sentAt.date().addDays(action.daysAfterSend == null ? 0 : action.daysAfterSend);
            task.Description = truncate(resolveText(action.comments, context), MAX_TASK_DESCRIPTION_LENGTH);
            relateTask(task, context);
            context.tasksToInsert.add(task);
        }
    }

    @SuppressWarnings('PMD.ApexSOQLInjection')
    private static Boolean prepareContext(ExecutionContext context, List<DceBuilderPostSendActionDTO> actions) {
        if (!Schema.getGlobalDescribe().containsKey(context.parentObjectApiName)) {
            return false;
        }

        Schema.DescribeSObjectResult objectDescribe = Schema.getGlobalDescribe().get(context.parentObjectApiName).getDescribe();
        if (!objectDescribe.isAccessible()) {
            return false;
        }
        context.parentFields = objectDescribe.fields.getMap();

        Set<String> queryFields = new Set<String>{ 'Id' };
        if (context.parentFields.containsKey('OwnerId')) {
            queryFields.add('OwnerId');
        }

        for (DceBuilderPostSendActionDTO action : actions) {
            if (action == null) {
                continue;
            }
            if (action.actionType == ACTION_UPDATE_FIELD && !String.isBlank(action.fieldApiName) && context.parentFields.containsKey(action.fieldApiName)) {
                queryFields.add(action.fieldApiName);
            }
            for (String fieldPath : collectMergeFields(action, context.parentObjectApiName)) {
                if (isQueryableFieldPath(objectDescribe, fieldPath)) {
                    queryFields.add(fieldPath);
                }
            }
        }

        try {
            Id recordId = context.parentRecordId;
            String soql = 'SELECT ' + String.join(new List<String>(queryFields), ',') +
                ' FROM ' + context.parentObjectApiName +
                ' WHERE Id = :recordId LIMIT 1';
            List<SObject> records = Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'recordId' => recordId },
                AccessLevel.USER_MODE
            );
            if (records.isEmpty()) {
                return false;
            }
            context.parentRecord = records[0];
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private static Set<String> collectMergeFields(DceBuilderPostSendActionDTO action, String parentObjectApiName) {
        Set<String> fields = new Set<String>();
        if (action == null) {
            return fields;
        }
        if (action.actionType == ACTION_UPDATE_FIELD && action.valueType == VALUE_MERGE_FIELD) {
            fields.addAll(GenericMergeFieldResolver.extractParentFieldPaths(action.value, parentObjectApiName, new Set<String>()));
        }
        if (action.actionType == ACTION_CREATE_TASK) {
            fields.addAll(GenericMergeFieldResolver.extractParentFieldPaths(action.subject, parentObjectApiName, new Set<String>()));
            fields.addAll(GenericMergeFieldResolver.extractParentFieldPaths(action.comments, parentObjectApiName, new Set<String>()));
        }
        return fields;
    }

    private static Boolean isQueryableFieldPath(Schema.DescribeSObjectResult objectDescribe, String fieldPath) {
        if (objectDescribe == null || String.isBlank(fieldPath)) {
            return false;
        }
        List<String> segments = fieldPath.split('\\.');
        Schema.DescribeSObjectResult currentDescribe = objectDescribe;
        for (Integer i = 0; i < segments.size(); i++) {
            String segment = segments[i];
            Boolean isLeaf = i == segments.size() - 1;
            Map<String, Schema.SObjectField> fields = currentDescribe.fields.getMap();
            if (isLeaf) {
                return fields.containsKey(segment);
            }
            Schema.DescribeFieldResult relationshipField = getRelationshipField(currentDescribe, segment);
            if (relationshipField == null || relationshipField.getReferenceTo().isEmpty()) {
                return false;
            }
            currentDescribe = relationshipField.getReferenceTo()[0].getDescribe();
        }
        return false;
    }

    private static Schema.DescribeFieldResult getRelationshipField(Schema.DescribeSObjectResult objectDescribe, String relationshipName) {
        for (Schema.SObjectField fieldToken : objectDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            if (fieldDescribe.getRelationshipName() == relationshipName) {
                return fieldDescribe;
            }
        }
        return null;
    }

    private static Object convertValue(DceBuilderPostSendActionDTO action, Schema.DescribeFieldResult fieldDescribe, ExecutionContext context) {
        String valueType = String.isBlank(action.valueType) ? VALUE_STATIC : action.valueType;
        Object rawValue;

        if (valueType == VALUE_CURRENT_DATE) {
            rawValue = context.sentAt.date();
        } else if (valueType == VALUE_CURRENT_DATETIME) {
            rawValue = context.sentAt;
        } else if (valueType == VALUE_MERGE_FIELD) {
            rawValue = resolveText(action.value, context);
        } else {
            rawValue = action.value;
        }

        if (valueType == VALUE_BOOLEAN && rawValue == null) {
            rawValue = action.value;
        }

        return coerceValue(rawValue, fieldDescribe);
    }

    private static Object coerceValue(Object rawValue, Schema.DescribeFieldResult fieldDescribe) {
        if (rawValue == null) {
            return null;
        }
        String value = String.valueOf(rawValue).trim();
        if (String.isBlank(value)) {
            return null;
        }

        Schema.DisplayType fieldType = fieldDescribe.getType();
        if (fieldType == Schema.DisplayType.Boolean) {
            return value.toLowerCase() == 'true' || value.toLowerCase() == 'yes' || value == '1';
        }
        if (fieldType == Schema.DisplayType.Date) {
            if (rawValue instanceof Date) {
                return rawValue;
            }
            if (rawValue instanceof Datetime) {
                return ((Datetime) rawValue).date();
            }
            return Date.valueOf(value);
        }
        if (fieldType == Schema.DisplayType.DateTime) {
            if (rawValue instanceof Datetime) {
                return rawValue;
            }
            if (rawValue instanceof Date) {
                return Datetime.newInstance((Date) rawValue, Time.newInstance(0, 0, 0, 0));
            }
            return Datetime.valueOf(value);
        }
        if (fieldType == Schema.DisplayType.Currency || fieldType == Schema.DisplayType.Double || fieldType == Schema.DisplayType.Percent) {
            return Decimal.valueOf(value);
        }
        if (fieldType == Schema.DisplayType.Integer) {
            return Integer.valueOf(value);
        }
        return value;
    }

    private static String resolveText(String templateText, ExecutionContext context) {
        if (String.isBlank(templateText)) {
            return '';
        }
        GenericMergeFieldResolver.MergeContext mergeContext = new GenericMergeFieldResolver.MergeContext();
        mergeContext.parentRecord = context.parentRecord;
        mergeContext.parentObjectApiName = context.parentObjectApiName;
        mergeContext.escapeHtml = false;
        return GenericMergeFieldResolver.resolveTemplate(templateText, mergeContext);
    }

    private static Id resolveTaskOwnerId(DceBuilderPostSendActionDTO action, ExecutionContext context) {
        if (action.assignedToType == 'Specific User' && action.assignedUserId != null) {
            return action.assignedUserId;
        }
        if (action.assignedToType == 'Triggering Record Owner' && context.parentFields.containsKey('OwnerId')) {
            Object ownerId = context.parentRecord.get('OwnerId');
            if (ownerId != null) {
                return (Id) ownerId;
            }
        }
        return UserInfo.getUserId();
    }

    private static void relateTask(Task task, ExecutionContext context) {
        if (context.parentObjectApiName == 'Contact' || context.parentObjectApiName == 'Lead') {
            task.WhoId = context.parentRecordId;
        } else {
            task.WhatId = context.parentRecordId;
        }
    }

    private static void flush(ExecutionContext context) {
        if (!context.pendingParentUpdates.isEmpty()) {
            try {
                Schema.SObjectType parentType = Schema.getGlobalDescribe().get(context.parentObjectApiName);
                if (parentType.getDescribe().isUpdateable()) {
                    SObject updateRecord = parentType.newSObject(context.parentRecordId);
                    for (String fieldApiName : context.pendingParentUpdates.keySet()) {
                        updateRecord.put(fieldApiName, context.pendingParentUpdates.get(fieldApiName));
                    }
                    Database.SaveResult updateResult =
                        Database.update(updateRecord, false, AccessLevel.USER_MODE);
                    if (!updateResult.isSuccess()) {
                        context.warnings.add('Email sent, but a configured record update failed.');
                    }
                }
            } catch (Exception e) {
                context.warnings.add('Email sent, but a configured record update failed.');
            }
        }
        if (!context.tasksToInsert.isEmpty()) {
            try {
                for (Database.SaveResult taskResult :
                    Database.insert(context.tasksToInsert, false, AccessLevel.USER_MODE)
                ) {
                    if (!taskResult.isSuccess()) {
                        context.warnings.add('Email sent, but a configured follow-up task failed.');
                    }
                }
            } catch (Exception e) {
                context.warnings.add('Email sent, but configured follow-up tasks could not be created.');
            }
        }
    }

    private static List<DceBuilderPostSendActionDTO> deserializeActions(String actionsJson) {
        try {
            return (List<DceBuilderPostSendActionDTO>) JSON.deserialize(actionsJson, List<DceBuilderPostSendActionDTO>.class);
        } catch (Exception e) {
            return new List<DceBuilderPostSendActionDTO>();
        }
    }

    private static List<DceBuilderPostSendActionDTO> sortActions(List<DceBuilderPostSendActionDTO> actions) {
        List<DceBuilderPostSendActionDTO> sortedActions = new List<DceBuilderPostSendActionDTO>();
        sortedActions.addAll(actions);
        sortedActions.sort(new ActionComparator());
        return sortedActions;
    }

    private static String truncate(String value, Integer maxLength) {
        if (String.isBlank(value) || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    private class ActionComparator implements Comparator<DceBuilderPostSendActionDTO> {
        public Integer compare(DceBuilderPostSendActionDTO a, DceBuilderPostSendActionDTO b) {
            Integer left = a == null || a.runOrder == null ? 999999 : a.runOrder;
            Integer right = b == null || b.runOrder == null ? 999999 : b.runOrder;
            if (left == right) {
                return 0;
            }
            return left < right ? -1 : 1;
        }
    }
}
