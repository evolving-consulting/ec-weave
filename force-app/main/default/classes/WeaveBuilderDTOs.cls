public with sharing class WeaveBuilderDTOs {

    public class WeaveBuilderTemplateDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String parentObjectApiName { get; set; }
        @AuraEnabled public String parentObjectLabel { get; set; }
        @AuraEnabled public String defaultFromEmail { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Boolean allowUserEditBeforeSend { get; set; }
        @AuraEnabled public Boolean storeEmailHistory { get; set; }
        @AuraEnabled public String subjectTemplate { get; set; }
        @AuraEnabled public String subjectVariantB { get; set; }
        @AuraEnabled public Id brandId { get; set; }
        @AuraEnabled public String brandName { get; set; }
        @AuraEnabled public List<WeaveBuilderQueryDTO> queries { get; set; }
        @AuraEnabled public List<WeaveBuilderComponentDTO> components { get; set; }
        @AuraEnabled public List<WeaveBuilderRecipientDTO> recipients { get; set; }
        @AuraEnabled public List<WeaveBuilderActionDTO> actions { get; set; }
        @AuraEnabled public List<WeaveBuilderAttachmentDTO> attachments { get; set; }
        @AuraEnabled public List<Id> deletedQueryIds { get; set; }
        @AuraEnabled public List<Id> deletedComponentIds { get; set; }
        @AuraEnabled public List<Id> deletedRecipientIds { get; set; }
        @AuraEnabled public List<Id> deletedActionIds { get; set; }
        @AuraEnabled public List<Id> deletedAttachmentIds { get; set; }
        @AuraEnabled public String templateOutputType { get; set; }
        @AuraEnabled public String canvasPageSize { get; set; }
        @AuraEnabled public String canvasOrientation { get; set; }

        public WeaveBuilderTemplateDTO() {
            this.status = 'Draft';
            this.allowUserEditBeforeSend = true;
            this.storeEmailHistory = true;
            this.queries = new List<WeaveBuilderQueryDTO>();
            this.components = new List<WeaveBuilderComponentDTO>();
            this.recipients = new List<WeaveBuilderRecipientDTO>();
            this.actions = new List<WeaveBuilderActionDTO>();
            this.attachments = new List<WeaveBuilderAttachmentDTO>();
            this.deletedQueryIds = new List<Id>();
            this.deletedComponentIds = new List<Id>();
            this.deletedRecipientIds = new List<Id>();
            this.deletedActionIds = new List<Id>();
            this.deletedAttachmentIds = new List<Id>();
        }
    }

    public class WeaveBuilderTemplateSummaryDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String parentObjectApiName { get; set; }
        @AuraEnabled public String parentObjectLabel { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
        @AuraEnabled public Id brandId { get; set; }
        @AuraEnabled public String brandName { get; set; }
    }

    public class WeaveBrandSummaryDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String displayName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String primaryColor { get; set; }
        @AuraEnabled public String secondaryColor { get; set; }
        @AuraEnabled public String logoUrl { get; set; }
        @AuraEnabled public String orgWideEmailAddress { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
    }

    public class WeaveBrandDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String displayName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String primaryColor { get; set; }
        @AuraEnabled public String secondaryColor { get; set; }
        @AuraEnabled public String logoContentDocumentId { get; set; }
        @AuraEnabled public String logoUrl { get; set; }
        @AuraEnabled public String orgWideEmailAddress { get; set; }
        @AuraEnabled public String physicalAddress { get; set; }
        @AuraEnabled public String unsubscribeUrl { get; set; }
        @AuraEnabled public String unsubscribeLabel { get; set; }
        @AuraEnabled public String headerHtml { get; set; }
        @AuraEnabled public String headerEditorMode { get; set; }
        @AuraEnabled public String footerHtml { get; set; }
        @AuraEnabled public String footerEditorMode { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String contactEmail { get; set; }
        @AuraEnabled public String contactPhone { get; set; }

        public WeaveBrandDTO() {
            this.status = 'Active';
            this.primaryColor = '#1f5f5b';
            this.secondaryColor = '#4fb893';
            this.headerEditorMode = 'Visual';
            this.footerEditorMode = 'Visual';
            this.unsubscribeLabel = 'Unsubscribe';
        }
    }

    public class WeaveBuilderQueryDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String localKey { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String queryApiName { get; set; }
        @AuraEnabled public String soqlQuery { get; set; }
        @AuraEnabled public String parentLookupField { get; set; }
        @AuraEnabled public String relationshipType { get; set; } // 'down' (child) or 'up' (parent lookup)
        @AuraEnabled public String soqlObject { get; set; }      // derived from SOQL, cached for UI
        @AuraEnabled public Id parentQueryId { get; set; }
        @AuraEnabled public String parentQueryLocalKey { get; set; }
    }

    public class WeaveBuilderComponentDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String localKey { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String componentType { get; set; }
        @AuraEnabled public String region { get; set; }
        @AuraEnabled public Integer displayOrder { get; set; }
        @AuraEnabled public Id linkedQueryId { get; set; }
        @AuraEnabled public String linkedQueryName { get; set; }
        @AuraEnabled public String configJson { get; set; }
        @AuraEnabled public String htmlOutput { get; set; }
        @AuraEnabled public Boolean canvasMode { get; set; }
        @AuraEnabled public Decimal canvasX { get; set; }
        @AuraEnabled public Decimal canvasY { get; set; }
        @AuraEnabled public Decimal canvasW { get; set; }
        @AuraEnabled public Decimal canvasH { get; set; }
        @AuraEnabled public Integer canvasPage { get; set; }
    }

    public class WeaveBuilderRecipientDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String localKey { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Integer displayOrder { get; set; }
        @AuraEnabled public String recipientType { get; set; }
        @AuraEnabled public String recipientSourceType { get; set; }
        @AuraEnabled public String sourceObjectApiName { get; set; }
        @AuraEnabled public String sourceObjectLabel { get; set; }
        @AuraEnabled public String parentLookupFieldApiName { get; set; }
        @AuraEnabled public String parentLookupFieldLabel { get; set; }
        @AuraEnabled public String nameFieldApiName { get; set; }
        @AuraEnabled public String nameFieldLabel { get; set; }
        @AuraEnabled public String emailFieldApiName { get; set; }
        @AuraEnabled public String emailFieldLabel { get; set; }
        @AuraEnabled public String filterLogic { get; set; }
        @AuraEnabled public Boolean defaultSelected { get; set; }
        @AuraEnabled public Boolean allowMultiple { get; set; }
        @AuraEnabled public Boolean required { get; set; }
        @AuraEnabled public String segmentId { get; set; }
        @AuraEnabled public String segmentName { get; set; }
    }

    public class WeaveBuilderActionDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String localKey { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Integer runOrder { get; set; }
        @AuraEnabled public String actionType { get; set; }
        @AuraEnabled public Boolean expanded { get; set; }
        // Update Field fields
        @AuraEnabled public String fieldApiName { get; set; }
        @AuraEnabled public String fieldLabel { get; set; }
        @AuraEnabled public String valueType { get; set; }
        @AuraEnabled public String value { get; set; }
        // Create Task fields
        @AuraEnabled public String taskSubject { get; set; }
        @AuraEnabled public String assignedToType { get; set; }
        @AuraEnabled public Id assignedUserId { get; set; }
        @AuraEnabled public String dueDateStrategy { get; set; }
        @AuraEnabled public Integer daysAfterSend { get; set; }
        @AuraEnabled public String taskStatus { get; set; }
        @AuraEnabled public String taskPriority { get; set; }
        @AuraEnabled public String taskDescription { get; set; }

        public WeaveBuilderActionDTO() {
            this.active = true;
            this.actionType = 'Update Field';
            this.valueType = 'Static';
            this.assignedToType = 'Current User';
            this.dueDateStrategy = 'Same Day';
            this.daysAfterSend = 0;
            this.taskStatus = 'Completed';
            this.taskPriority = 'Normal';
        }
    }

    public class WeaveBuilderAttachmentDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String localKey { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Integer displayOrder { get; set; }
        @AuraEnabled public String attachmentSource { get; set; }
        @AuraEnabled public String staticContentDocumentId { get; set; }
        @AuraEnabled public Id linkedQueryId { get; set; }
        @AuraEnabled public String linkedQueryName { get; set; }
        @AuraEnabled public String fileTitleFilter { get; set; }
        @AuraEnabled public Integer maxAttachments { get; set; }

        public WeaveBuilderAttachmentDTO() {
            this.active = true;
            this.attachmentSource = 'Static File';
            this.maxAttachments = 5;
        }
    }

    public class WeaveOrgWideEmailDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String displayName { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String label { get; set; }
    }

    public class WeaveBuilderObjectDTO {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String pluralLabel { get; set; }
        @AuraEnabled public String relationshipType { get; set; }  // 'self', 'up', 'down'
        @AuraEnabled public String connectorField { get; set; }    // field linking this object to parent

        public WeaveBuilderObjectDTO(String label, String apiName, String pluralLabel) {
            this.label = label;
            this.apiName = apiName;
            this.pluralLabel = pluralLabel;
        }
    }

    public class WeaveScheduledSendDTO {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String sendType { get; set; }
        @AuraEnabled public String scheduledAt { get; set; }
        @AuraEnabled public String filterClause { get; set; }
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public Integer recordsTargeted { get; set; }
        @AuraEnabled public Integer recordsSent { get; set; }
        @AuraEnabled public Integer recordsFailed { get; set; }
        @AuraEnabled public String errorDetail { get; set; }
        @AuraEnabled public String jobName { get; set; }
    }

    public class WeaveBuilderFieldDTO {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String dataType { get; set; }
        @AuraEnabled public String relationshipName { get; set; }
        @AuraEnabled public Boolean isSortable { get; set; }
        @AuraEnabled public Boolean isFilterable { get; set; }
        @AuraEnabled public Boolean isNameField { get; set; }
        @AuraEnabled public List<String> referenceTo { get; set; }

        public WeaveBuilderFieldDTO() {
            this.referenceTo = new List<String>();
        }
    }
}
