public with sharing class WeaveEmailTemplateController {

    @AuraEnabled(cacheable=true)
    public static List<GenericEmailTemplateDTO> getAvailableTemplates(String parentObjectApiName) {
        try {
            if (String.isBlank(parentObjectApiName)) throw new AuraHandledException('Parent object API name is required.');
            if (!GenericDynamicQueryService.isValidObject(parentObjectApiName)) throw new AuraHandledException('Invalid parent object API name.');
            assertTemplateConfigReadable();

            List<GenericEmailTemplateDTO> templates = new List<GenericEmailTemplateDTO>();
            for (Weave_Template_Config__c template : [
                SELECT Id, Name, Description__c, Subject_Template__c, Parent_Object_API_Name__c,
                    Allow_User_Edit_Before_Send__c, Store_Email_History__c
                FROM Weave_Template_Config__c
                WHERE Status__c = 'Active' AND Parent_Object_API_Name__c = :parentObjectApiName
                WITH USER_MODE ORDER BY Name ASC
            ]) {
                templates.add(toTemplateDTO(template));
            }
            return templates;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('Unable to load templates. Please contact your administrator.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static GenericEmailTemplateDTO getTemplateDetails(Id templateId) {
        try {
            if (templateId == null) throw new AuraHandledException('Template Id is required.');
            assertTemplateConfigReadable();
            List<Weave_Template_Config__c> templates = [
                SELECT Id, Name, Description__c, Subject_Template__c, Parent_Object_API_Name__c,
                    Allow_User_Edit_Before_Send__c, Store_Email_History__c
                FROM Weave_Template_Config__c WHERE Id = :templateId WITH USER_MODE LIMIT 1
            ];
            if (templates.isEmpty()) throw new AuraHandledException('Template not found.');
            return toTemplateDTO(templates[0]);
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('Unable to load template details. Please contact your administrator.');
        }
    }

    @AuraEnabled
    public static List<RecipientOptionDTO> getRecipientOptions(Id templateId, Id recordId) {
        return WeaveRecipientResolver.getRecipientOptions(templateId, recordId);
    }

    @AuraEnabled
    public static WeaveEmailTemplateRenderer.RenderedEmailDTO renderEmail(Id templateId, Id recordId) {
        return WeaveEmailTemplateRenderer.renderEmail(templateId, recordId);
    }

    @AuraEnabled
    public static List<DceEmailAttachmentDTO> getRelatedAttachments(Id recordId) {
        try {
            if (recordId == null) throw new AuraHandledException('Record Id is required.');
            List<DceEmailAttachmentDTO> attachments = new List<DceEmailAttachmentDTO>();
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension,
                    ContentDocument.ContentSize, ContentDocument.LatestPublishedVersionId
                FROM ContentDocumentLink WHERE LinkedEntityId = :recordId WITH USER_MODE
                ORDER BY ContentDocument.Title ASC
            ]) {
                DceEmailAttachmentDTO dto = new DceEmailAttachmentDTO();
                dto.contentDocumentId = link.ContentDocumentId;
                dto.contentVersionId = link.ContentDocument.LatestPublishedVersionId;
                dto.title = link.ContentDocument.Title;
                dto.fileExtension = link.ContentDocument.FileExtension;
                dto.contentSize = link.ContentDocument.ContentSize;
                dto.selected = true;
                dto.source = 'Related';
                attachments.add(dto);
            }
            return attachments;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('Unable to load related attachments. Please contact your administrator.');
        }
    }

    @AuraEnabled
    public static DceEmailSendResultDTO sendEmail(GenericEmailSendRequest request) {
        return WeaveEmailSendService.sendEmail(request);
    }

    @AuraEnabled
    public static Id scheduleEmail(GenericEmailSendRequest request, Long scheduledAtMs) {
        try {
            if (scheduledAtMs == null) throw new AuraHandledException('Scheduled date/time is required.');
            Datetime scheduledAt = Datetime.newInstance(scheduledAtMs);
            return WeaveScheduledEmailService.scheduleEmail(request, scheduledAt);
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('Unable to schedule email. Please contact your administrator.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getRecordSummary(Id recordId) {
        if (recordId == null) throw new AuraHandledException('Record Id is required.');
        try {
            Schema.DescribeSObjectResult describeResult = recordId.getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED);
            Map<String, String> summary = new Map<String, String>();
            summary.put('objectApiName', describeResult.getName());
            summary.put('objectLabel', describeResult.getLabel());
            summary.put('recordName', String.valueOf(recordId));
            Schema.DescribeFieldResult nameField = describeResult.fields.getMap().containsKey('Name')
                ? describeResult.fields.getMap().get('Name').getDescribe() : null;
            if (describeResult.isAccessible() && nameField != null && nameField.isAccessible()) {
                SObject record = GenericDynamicQueryService.queryRecordById(describeResult.getName(), recordId, new Set<String>{ 'Name' });
                Object nameValue = record.get('Name');
                if (nameValue != null) summary.put('recordName', String.valueOf(nameValue));
            }
            return summary;
        } catch (AuraHandledException handledException) {
            throw handledException;
        } catch (Exception unexpectedException) {
            throw new AuraHandledException('Unable to load record summary. Please contact your administrator.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getObjectApiNameFromRecordId(Id recordId) {
        if (recordId == null) throw new AuraHandledException('Record Id is required.');
        try {
            return recordId.getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        } catch (Exception e) {
            throw new AuraHandledException('Unable to determine object type from record Id.');
        }
    }

    private static GenericEmailTemplateDTO toTemplateDTO(Weave_Template_Config__c template) {
        GenericEmailTemplateDTO dto = new GenericEmailTemplateDTO();
        dto.id = template.Id;
        dto.name = template.Name;
        dto.description = template.Description__c;
        dto.subjectTemplate = template.Subject_Template__c;
        dto.parentObjectApiName = template.Parent_Object_API_Name__c;
        dto.allowUserEditBeforeSend = template.Allow_User_Edit_Before_Send__c;
        dto.storeEmailHistory = template.Store_Email_History__c;
        return dto;
    }

    private static void assertTemplateConfigReadable() {
        if (!Weave_Template_Config__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()) {
            throw new AuraHandledException('You do not have access to Weave template configuration.');
        }
    }
}
