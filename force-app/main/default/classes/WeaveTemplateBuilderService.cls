public with sharing class WeaveTemplateBuilderService {

    // ── Public read methods ───────────────────────────────────────────────────

    public static List<WeaveBuilderDTOs.WeaveOrgWideEmailDTO> getOrgWideEmailAddresses() {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        List<WeaveBuilderDTOs.WeaveOrgWideEmailDTO> results = new List<WeaveBuilderDTOs.WeaveOrgWideEmailDTO>();
        for (OrgWideEmailAddress orgWideEmail : [
            SELECT Id, DisplayName, Address
            FROM OrgWideEmailAddress
            WITH USER_MODE
            ORDER BY DisplayName ASC, Address ASC
        ]) {
            WeaveBuilderDTOs.WeaveOrgWideEmailDTO dto = new WeaveBuilderDTOs.WeaveOrgWideEmailDTO();
            dto.id = orgWideEmail.Id;
            dto.displayName = orgWideEmail.DisplayName;
            dto.address = orgWideEmail.Address;
            dto.label = buildOrgWideEmailLabel(orgWideEmail.DisplayName, orgWideEmail.Address);
            results.add(dto);
        }
        return results;
    }

    public static List<WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO> getTemplates() {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        assertObjectReadable(Weave_Template_Config__c.SObjectType);
        List<WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO> results = new List<WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO>();
        for (Weave_Template_Config__c template : [
            SELECT Id, Name, API_Name__c, Status__c, Parent_Object_API_Name__c, Description__c, LastModifiedDate,
                Brand__c, Brand__r.Name
            FROM Weave_Template_Config__c
            WITH USER_MODE
            ORDER BY Name ASC
        ]) {
            WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateSummaryDTO();
            dto.id = template.Id;
            dto.name = template.Name;
            dto.apiName = template.API_Name__c;
            dto.status = template.Status__c;
            dto.parentObjectApiName = template.Parent_Object_API_Name__c;
            dto.parentObjectLabel = getObjectLabel(template.Parent_Object_API_Name__c);
            dto.description = template.Description__c;
            dto.lastModifiedDate = template.LastModifiedDate;
            dto.brandId = template.Brand__c;
            dto.brandName = template.Brand__c != null ? template.Brand__r.Name : null;
            results.add(dto);
        }
        return results;
    }

    public static List<WeaveBuilderDTOs.WeaveBuilderObjectDTO> getAvailableObjects() {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        List<WeaveBuilderDTOs.WeaveBuilderObjectDTO> results = new List<WeaveBuilderDTOs.WeaveBuilderObjectDTO>();
        for (Schema.SObjectType objectType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult describe = objectType.getDescribe();
            if (!describe.isAccessible() || !describe.isQueryable() || describe.isDeprecatedAndHidden()) {
                continue;
            }
            String apiName = describe.getName();
            if (apiName.endsWith('Share') || apiName.endsWith('History') || apiName.endsWith('Feed')) {
                continue;
            }
            results.add(new WeaveBuilderDTOs.WeaveBuilderObjectDTO(describe.getLabel(), apiName, describe.getLabelPlural()));
        }
        results.sort(new ObjectLabelComparator());
        return results;
    }

    public static List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> getFieldsForObject(String objectApiName) {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        Schema.DescribeSObjectResult objectDescribe = assertReadableObject(objectApiName);
        List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> fields = new List<WeaveBuilderDTOs.WeaveBuilderFieldDTO>();
        for (Schema.SObjectField fieldToken : objectDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            if (!fieldDescribe.isAccessible()) {
                continue;
            }
            fields.add(toFieldDto(fieldDescribe));
        }
        fields.sort(new FieldLabelComparator());
        return fields;
    }

    public static List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> getUpdateableFieldsForObject(String objectApiName) {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        Schema.DescribeSObjectResult objectDescribe = assertReadableObject(objectApiName);
        List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> fields = new List<WeaveBuilderDTOs.WeaveBuilderFieldDTO>();
        for (Schema.SObjectField fieldToken : objectDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            if (!fieldDescribe.isAccessible() || !fieldDescribe.isUpdateable()) {
                continue;
            }
            fields.add(toFieldDto(fieldDescribe));
        }
        fields.sort(new FieldLabelComparator());
        return fields;
    }

    public static List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> getRelationshipFields(String objectApiName) {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> fields = new List<WeaveBuilderDTOs.WeaveBuilderFieldDTO>();
        for (WeaveBuilderDTOs.WeaveBuilderFieldDTO fieldDto : getFieldsForObject(objectApiName)) {
            if (!String.isBlank(fieldDto.relationshipName)) {
                fields.add(fieldDto);
            }
        }
        return fields;
    }

    public static List<WeaveBuilderDTOs.WeaveBuilderObjectDTO> getRelatedObjectsForQuery(String parentObjectApiName) {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        List<WeaveBuilderDTOs.WeaveBuilderObjectDTO> results = new List<WeaveBuilderDTOs.WeaveBuilderObjectDTO>();
        Set<String> addedObjects = new Set<String>();

        Schema.DescribeSObjectResult parentDescribe = assertReadableObject(parentObjectApiName);

        // Add the parent object itself first
        WeaveBuilderDTOs.WeaveBuilderObjectDTO selfDto = new WeaveBuilderDTOs.WeaveBuilderObjectDTO(parentDescribe.getLabel(), parentDescribe.getName(), parentDescribe.getLabelPlural());
        selfDto.relationshipType = 'self';
        results.add(selfDto);
        addedObjects.add(parentDescribe.getName());

        // 1 level down: child objects with a lookup/MD back to the parent
        for (Schema.ChildRelationship childRel : parentDescribe.getChildRelationships()) {
            Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();
            if (!childDescribe.isAccessible() || !childDescribe.isQueryable() || childDescribe.isDeprecatedAndHidden()) continue;
            String childApiName = childDescribe.getName();
            if (childApiName.endsWith('Share') || childApiName.endsWith('History') || childApiName.endsWith('Feed')) continue;
            if (addedObjects.add(childApiName)) {
                WeaveBuilderDTOs.WeaveBuilderObjectDTO dto = new WeaveBuilderDTOs.WeaveBuilderObjectDTO(childDescribe.getLabel(), childApiName, childDescribe.getLabelPlural());
                dto.relationshipType = 'down';
                dto.connectorField = childRel.getField().getDescribe().getName();
                results.add(dto);
            }
        }

        // 1 level up: objects that the parent has a lookup field pointing to
        for (Schema.SObjectField fieldToken : parentDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fd = fieldToken.getDescribe();
            if (fd.getType() != Schema.DisplayType.REFERENCE || !fd.isAccessible()) continue;
            for (Schema.SObjectType refType : fd.getReferenceTo()) {
                Schema.DescribeSObjectResult refDescribe = refType.getDescribe();
                if (!refDescribe.isAccessible() || !refDescribe.isQueryable() || refDescribe.isDeprecatedAndHidden()) continue;
                String refApiName = refDescribe.getName();
                if (refApiName.endsWith('Share') || refApiName.endsWith('History') || refApiName.endsWith('Feed')) continue;
                if (addedObjects.add(refApiName)) {
                    WeaveBuilderDTOs.WeaveBuilderObjectDTO dto = new WeaveBuilderDTOs.WeaveBuilderObjectDTO(refDescribe.getLabel(), refApiName, refDescribe.getLabelPlural());
                    dto.relationshipType = 'up';
                    dto.connectorField = fd.getName(); // field on the PARENT object (e.g. AccountId)
                    results.add(dto);
                }
            }
        }

        results.sort(new ObjectLabelComparator());
        return results;
    }

    public static List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> getLookupFieldsForChildObject(String childObjectApiName, String parentObjectApiName) {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        List<WeaveBuilderDTOs.WeaveBuilderFieldDTO> fields = new List<WeaveBuilderDTOs.WeaveBuilderFieldDTO>();
        for (WeaveBuilderDTOs.WeaveBuilderFieldDTO fieldDto : getRelationshipFields(childObjectApiName)) {
            if (String.isBlank(parentObjectApiName) || fieldDto.referenceTo.contains(parentObjectApiName)) {
                fields.add(fieldDto);
            }
        }
        return fields;
    }

    public static WeaveBuilderDTOs.WeaveBuilderTemplateDTO loadTemplate(Id templateId) {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        assertObjectReadable(Weave_Template_Config__c.SObjectType);
        if (templateId == null) {
            return new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        }
        List<Weave_Template_Config__c> templates = [
            SELECT Id, Name, API_Name__c, Status__c, Parent_Object_API_Name__c, Subject_Template__c, Subject_Variant_B__c,
                Default_From_Email__c, Description__c, Allow_User_Edit_Before_Send__c, Store_Email_History__c,
                Brand__c, Brand__r.Name, Template_Output_Type__c, Canvas_Page_Size__c, Canvas_Orientation__c
            FROM Weave_Template_Config__c
            WHERE Id = :templateId
            WITH USER_MODE
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            throw new AuraHandledException('Template not found.');
        }
        return toTemplateDto(templates[0]);
    }

    public static WeaveBuilderDTOs.WeaveBuilderTemplateDTO saveTemplate(WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto) {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        if (dto == null) {
            throw new AuraHandledException('Template data is required.');
        }
        if (String.isBlank(dto.name)) {
            throw new AuraHandledException('Template name is required.');
        }
        if (String.isBlank(dto.parentObjectApiName)) {
            throw new AuraHandledException('Select a parent object before saving.');
        }
        assertReadableObject(dto.parentObjectApiName);

        Savepoint sp = Database.setSavepoint();
        try {
            String apiName = dto.id == null ? generateApiName(dto.name) : dto.apiName;

            Weave_Template_Config__c template = new Weave_Template_Config__c(
                Id = dto.id,
                Name = dto.name,
                API_Name__c = apiName,
                Status__c = String.isBlank(dto.status) ? 'Draft' : dto.status,
                Parent_Object_API_Name__c = dto.parentObjectApiName,
                Subject_Template__c = dto.subjectTemplate,
                Subject_Variant_B__c = dto.subjectVariantB,
                Default_From_Email__c = dto.defaultFromEmail,
                Description__c = dto.description,
                Allow_User_Edit_Before_Send__c = dto.allowUserEditBeforeSend == true,
                Store_Email_History__c = dto.storeEmailHistory == true,
                Brand__c = dto.brandId,
                Template_Output_Type__c = dto.templateOutputType,
                Canvas_Page_Size__c = dto.canvasPageSize,
                Canvas_Orientation__c = dto.canvasOrientation
            );
            upsert as user template;
            dto.id = template.Id;
            dto.apiName = apiName;

            deleteChildRecords(dto.deletedQueryIds, 'Weave_Template_Query__c', 'Weave_Template_Config__c', template.Id);
            deleteChildRecords(dto.deletedComponentIds, 'Weave_Template_Component__c', 'Weave_Template_Config__c', template.Id);
            deleteChildRecords(dto.deletedRecipientIds, 'Weave_Template_Recipient__c', 'Weave_Template_Config__c', template.Id);
            deleteChildRecords(dto.deletedActionIds, 'Weave_Template_Action__c', 'Weave_Template_Config__c', template.Id);
            deleteChildRecords(dto.deletedAttachmentIds, 'Weave_Template_Attachment__c', 'Weave_Template_Config__c', template.Id);

            saveQueries(dto, template.Id);
            saveComponents(dto, template.Id);
            saveRecipients(dto, template.Id);
            saveActions(dto, template.Id);
            saveAttachments(dto, template.Id);

            return loadTemplate(template.Id);
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Save failed: ' + e.getMessage());
        }
    }

    public static void deleteTemplate(Id templateId) {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        if (templateId == null) return;
        List<Weave_Template_Config__c> records = [
            SELECT Id FROM Weave_Template_Config__c WHERE Id = :templateId WITH USER_MODE LIMIT 1
        ];
        if (!records.isEmpty()) {
            delete as user records;
        }
    }

    public static Id cloneTemplate(Id templateId, String newName, String newApiName, String newOutputType) {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        if (templateId == null) throw new AuraHandledException('Source template is required.');
        if (String.isBlank(newName)) throw new AuraHandledException('New template name is required.');
        if (String.isBlank(newApiName)) throw new AuraHandledException('New API name is required.');

        List<Weave_Template_Config__c> sources = [
            SELECT Id, Name, API_Name__c, Status__c, Parent_Object_API_Name__c,
                Subject_Template__c, Subject_Variant_B__c, Default_From_Email__c,
                Description__c, Allow_User_Edit_Before_Send__c, Store_Email_History__c,
                Brand__c, Template_Output_Type__c, Canvas_Page_Size__c, Canvas_Orientation__c
            FROM Weave_Template_Config__c WHERE Id = :templateId WITH USER_MODE LIMIT 1
        ];
        if (sources.isEmpty()) throw new AuraHandledException('Source template not found.');
        Weave_Template_Config__c src = sources[0];

        Boolean isDocument = newOutputType == 'Document';

        Savepoint sp = Database.setSavepoint();
        try {
            Weave_Template_Config__c clone = new Weave_Template_Config__c(
                Name = newName,
                API_Name__c = newApiName,
                Status__c = 'Draft',
                Parent_Object_API_Name__c = src.Parent_Object_API_Name__c,
                Subject_Template__c = isDocument ? null : src.Subject_Template__c,
                Subject_Variant_B__c = isDocument ? null : src.Subject_Variant_B__c,
                Default_From_Email__c = isDocument ? null : src.Default_From_Email__c,
                Description__c = src.Description__c,
                Allow_User_Edit_Before_Send__c = isDocument ? false : src.Allow_User_Edit_Before_Send__c,
                Store_Email_History__c = isDocument ? false : src.Store_Email_History__c,
                Brand__c = src.Brand__c,
                Template_Output_Type__c = String.isBlank(newOutputType) ? src.Template_Output_Type__c : newOutputType,
                Canvas_Page_Size__c = src.Canvas_Page_Size__c,
                Canvas_Orientation__c = src.Canvas_Orientation__c
            );
            insert as user clone;
            Id newId = clone.Id;

            // Clone queries first; build old→new ID map for component/attachment remapping
            Map<Id, Id> queryIdMap = new Map<Id, Id>();
            List<Weave_Template_Query__c> srcQueries = [
                SELECT Id, Name, Query_API_Name__c, SOQL_Query__c, Parent_Lookup_Field__c, Relationship_Type__c, Parent_Query__c
                FROM Weave_Template_Query__c WHERE Weave_Template_Config__c = :templateId WITH USER_MODE
            ];
            if (!srcQueries.isEmpty()) {
                List<Weave_Template_Query__c> newQueries = new List<Weave_Template_Query__c>();
                for (Weave_Template_Query__c q : srcQueries) {
                    newQueries.add(new Weave_Template_Query__c(
                        Name = q.Name,
                        Query_API_Name__c = q.Query_API_Name__c,
                        Weave_Template_Config__c = newId,
                        SOQL_Query__c = q.SOQL_Query__c,
                        Parent_Lookup_Field__c = q.Parent_Lookup_Field__c,
                        Relationship_Type__c = q.Relationship_Type__c
                    ));
                }
                insert as user newQueries;
                for (Integer i = 0; i < srcQueries.size(); i++) {
                    queryIdMap.put(srcQueries[i].Id, newQueries[i].Id);
                }
                // Pass 2: clone Parent_Query__c FK using old→new Id map
                List<Weave_Template_Query__c> childUpdates = new List<Weave_Template_Query__c>();
                for (Integer i = 0; i < srcQueries.size(); i++) {
                    if (srcQueries[i].Parent_Query__c != null) {
                        Id newParentId = queryIdMap.get(srcQueries[i].Parent_Query__c);
                        if (newParentId != null) {
                            childUpdates.add(new Weave_Template_Query__c(
                                Id = newQueries[i].Id, Parent_Query__c = newParentId
                            ));
                        }
                    }
                }
                if (!childUpdates.isEmpty()) update as user childUpdates;
            }

            // Clone components
            List<Weave_Template_Component__c> srcComponents = [
                SELECT Id, Name, Component_Type__c, Region__c, Display_Order__c,
                    Linked_Query__c, Config_JSON__c, HTML_Output__c, Visibility_Condition__c,
                    Canvas_Mode__c, Canvas_X__c, Canvas_Y__c, Canvas_W__c, Canvas_H__c, Canvas_Page__c
                FROM Weave_Template_Component__c WHERE Weave_Template_Config__c = :templateId WITH USER_MODE
                ORDER BY Region__c ASC, Display_Order__c ASC NULLS LAST
            ];
            if (!srcComponents.isEmpty()) {
                List<Weave_Template_Component__c> newComponents = new List<Weave_Template_Component__c>();
                for (Weave_Template_Component__c c : srcComponents) {
                    if (c.Component_Type__c == 'Text' || c.Component_Type__c == 'HTML Block') {
                        DceHtmlPolicy.assertSafeTemplateHtml(c.HTML_Output__c, c.Component_Type__c);
                    }
                    newComponents.add(new Weave_Template_Component__c(
                        Name = c.Name,
                        Weave_Template_Config__c = newId,
                        Component_Type__c = c.Component_Type__c,
                        Region__c = c.Region__c,
                        Display_Order__c = c.Display_Order__c,
                        Linked_Query__c = c.Linked_Query__c != null ? queryIdMap.get(c.Linked_Query__c) : null,
                        Config_JSON__c = c.Config_JSON__c,
                        HTML_Output__c = c.HTML_Output__c,
                        Visibility_Condition__c = c.Visibility_Condition__c,
                        Canvas_Mode__c = c.Canvas_Mode__c,
                        Canvas_X__c = c.Canvas_X__c,
                        Canvas_Y__c = c.Canvas_Y__c,
                        Canvas_W__c = c.Canvas_W__c,
                        Canvas_H__c = c.Canvas_H__c,
                        Canvas_Page__c = c.Canvas_Page__c
                    ));
                }
                insert as user newComponents;
            }

            // Clone recipients
            List<Weave_Template_Recipient__c> srcRecipients = [
                SELECT Id, Name, Active__c, Display_Order__c, Recipient_Type__c, Recipient_Source_Type__c,
                    Source_Object_API_Name__c, Parent_Lookup_Field_API_Name__c, Name_Field_API_Name__c,
                    Email_Field_API_Name__c, Filter_Logic__c, Default_Selected__c, Allow_Multiple__c,
                    Required__c, Segment_Id__c
                FROM Weave_Template_Recipient__c WHERE Weave_Template_Config__c = :templateId WITH USER_MODE
                ORDER BY Display_Order__c ASC NULLS LAST
            ];
            if (!srcRecipients.isEmpty()) {
                List<Weave_Template_Recipient__c> newRecipients = new List<Weave_Template_Recipient__c>();
                for (Weave_Template_Recipient__c r : srcRecipients) {
                    newRecipients.add(new Weave_Template_Recipient__c(
                        Name = r.Name,
                        Weave_Template_Config__c = newId,
                        Active__c = r.Active__c,
                        Display_Order__c = r.Display_Order__c,
                        Recipient_Type__c = r.Recipient_Type__c,
                        Recipient_Source_Type__c = r.Recipient_Source_Type__c,
                        Source_Object_API_Name__c = r.Source_Object_API_Name__c,
                        Parent_Lookup_Field_API_Name__c = r.Parent_Lookup_Field_API_Name__c,
                        Name_Field_API_Name__c = r.Name_Field_API_Name__c,
                        Email_Field_API_Name__c = r.Email_Field_API_Name__c,
                        Filter_Logic__c = r.Filter_Logic__c,
                        Default_Selected__c = r.Default_Selected__c,
                        Allow_Multiple__c = r.Allow_Multiple__c,
                        Required__c = r.Required__c,
                        Segment_Id__c = r.Segment_Id__c
                    ));
                }
                insert as user newRecipients;
            }

            // Clone actions
            List<Weave_Template_Action__c> srcActions = [
                SELECT Id, Name, Active__c, Run_Order__c, Action_Type__c,
                    Field_API_Name__c, Value_Type__c, Value__c,
                    Task_Subject__c, Assigned_To_Type__c, Assigned_User_Id__c,
                    Due_Date_Strategy__c, Days_After_Send__c, Task_Status__c,
                    Task_Priority__c, Task_Description__c
                FROM Weave_Template_Action__c WHERE Weave_Template_Config__c = :templateId WITH USER_MODE
                ORDER BY Run_Order__c ASC NULLS LAST
            ];
            if (!srcActions.isEmpty()) {
                List<Weave_Template_Action__c> newActions = new List<Weave_Template_Action__c>();
                for (Weave_Template_Action__c a : srcActions) {
                    newActions.add(new Weave_Template_Action__c(
                        Name = a.Name,
                        Weave_Template_Config__c = newId,
                        Active__c = a.Active__c,
                        Run_Order__c = a.Run_Order__c,
                        Action_Type__c = a.Action_Type__c,
                        Field_API_Name__c = a.Field_API_Name__c,
                        Value_Type__c = a.Value_Type__c,
                        Value__c = a.Value__c,
                        Task_Subject__c = a.Task_Subject__c,
                        Assigned_To_Type__c = a.Assigned_To_Type__c,
                        Assigned_User_Id__c = a.Assigned_User_Id__c,
                        Due_Date_Strategy__c = a.Due_Date_Strategy__c,
                        Days_After_Send__c = a.Days_After_Send__c,
                        Task_Status__c = a.Task_Status__c,
                        Task_Priority__c = a.Task_Priority__c,
                        Task_Description__c = a.Task_Description__c
                    ));
                }
                insert as user newActions;
            }

            // Clone attachments (Static File references carry over as-is; query links remapped)
            List<Weave_Template_Attachment__c> srcAttachments = [
                SELECT Id, Active__c, Display_Order__c, Attachment_Source__c,
                    Static_Content_Document_Id__c, Linked_Query__c,
                    File_Title_Filter__c, Max_Attachments__c
                FROM Weave_Template_Attachment__c WHERE Weave_Template_Config__c = :templateId WITH USER_MODE
                ORDER BY Display_Order__c ASC NULLS LAST
            ];
            if (!srcAttachments.isEmpty()) {
                List<Weave_Template_Attachment__c> newAttachments = new List<Weave_Template_Attachment__c>();
                Integer order = 0;
                for (Weave_Template_Attachment__c a : srcAttachments) {
                    newAttachments.add(new Weave_Template_Attachment__c(
                        Name = 'Attachment ' + (++order),
                        Weave_Template_Config__c = newId,
                        Active__c = a.Active__c,
                        Display_Order__c = a.Display_Order__c,
                        Attachment_Source__c = a.Attachment_Source__c,
                        Static_Content_Document_Id__c = a.Static_Content_Document_Id__c,
                        Linked_Query__c = a.Linked_Query__c != null ? queryIdMap.get(a.Linked_Query__c) : null,
                        File_Title_Filter__c = a.File_Title_Filter__c,
                        Max_Attachments__c = a.Max_Attachments__c
                    ));
                }
                insert as user newAttachments;
            }

            return newId;
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Clone failed: ' + e.getMessage());
        }
    }

    // ── Private save helpers ──────────────────────────────────────────────────

    private static void saveQueries(WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto, Id templateId) {
        if (dto.queries == null || dto.queries.isEmpty()) return;
        // Pass 1: upsert all records with Parent_Query__c omitted to get Ids for new rows
        List<Weave_Template_Query__c> records = new List<Weave_Template_Query__c>();
        for (WeaveBuilderDTOs.WeaveBuilderQueryDTO q : dto.queries) {
            String queryApiName = q.id == null ? generateApiName(q.name) : q.queryApiName;
            records.add(new Weave_Template_Query__c(
                Id = q.id,
                Name = q.name,
                Query_API_Name__c = queryApiName,
                Weave_Template_Config__c = templateId,
                SOQL_Query__c = q.soqlQuery,
                Parent_Lookup_Field__c = q.parentLookupField,
                Relationship_Type__c = String.isBlank(q.relationshipType) ? 'down' : q.relationshipType
            ));
        }
        upsert as user records;
        // Back-fill Ids and build localKey → Salesforce Id map
        Map<String, Id> localKeyToId = new Map<String, Id>();
        for (Integer i = 0; i < dto.queries.size(); i++) {
            if (dto.queries[i].id == null) {
                dto.queries[i].id = records[i].Id;
            }
            if (String.isNotBlank(dto.queries[i].localKey)) {
                localKeyToId.put(dto.queries[i].localKey, dto.queries[i].id);
            }
        }
        // Pass 2: update Parent_Query__c for child queries
        List<Weave_Template_Query__c> childUpdates = new List<Weave_Template_Query__c>();
        for (Integer i = 0; i < dto.queries.size(); i++) {
            WeaveBuilderDTOs.WeaveBuilderQueryDTO q = dto.queries[i];
            if (String.isBlank(q.parentQueryLocalKey) && q.parentQueryId == null) continue;
            Id parentId = String.isNotBlank(q.parentQueryLocalKey) ? localKeyToId.get(q.parentQueryLocalKey) : null;
            if (parentId == null) parentId = q.parentQueryId;
            if (parentId == null) continue;
            childUpdates.add(new Weave_Template_Query__c(Id = records[i].Id, Parent_Query__c = parentId));
        }
        if (!childUpdates.isEmpty()) {
            update as user childUpdates;
        }
    }

    private static void saveComponents(WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto, Id templateId) {
        if (dto.components == null || dto.components.isEmpty()) return;
        List<Weave_Template_Component__c> records = new List<Weave_Template_Component__c>();
        for (WeaveBuilderDTOs.WeaveBuilderComponentDTO c : dto.components) {
            if (c.componentType == 'Text' || c.componentType == 'HTML Block') {
                DceHtmlPolicy.assertSafeTemplateHtml(c.htmlOutput, c.componentType);
            }
            records.add(new Weave_Template_Component__c(
                Id = c.id,
                Name = String.isBlank(c.name) ? (c.componentType + ' ' + (dto.components.indexOf(c) + 1)) : c.name,
                Weave_Template_Config__c = templateId,
                Component_Type__c = c.componentType,
                Region__c = String.isBlank(c.region) ? 'Body' : c.region,
                Display_Order__c = c.displayOrder,
                Linked_Query__c = c.linkedQueryId,
                Config_JSON__c = c.configJson,
                HTML_Output__c = c.htmlOutput,
                Visibility_Condition__c = c.visibilityCondition,
                Canvas_Mode__c = c.canvasMode != null ? c.canvasMode : false,
                Canvas_X__c = c.canvasX,
                Canvas_Y__c = c.canvasY,
                Canvas_W__c = c.canvasW,
                Canvas_H__c = c.canvasH,
                Canvas_Page__c = c.canvasPage
            ));
        }
        upsert as user records;
        for (Integer i = 0; i < dto.components.size(); i++) {
            if (dto.components[i].id == null) {
                dto.components[i].id = records[i].Id;
            }
        }
    }

    private static void saveRecipients(WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto, Id templateId) {
        if (dto.recipients == null || dto.recipients.isEmpty()) return;
        List<Weave_Template_Recipient__c> records = new List<Weave_Template_Recipient__c>();
        Integer order = 0;
        for (WeaveBuilderDTOs.WeaveBuilderRecipientDTO r : dto.recipients) {
            validateRecipient(r);
            records.add(new Weave_Template_Recipient__c(
                Id = r.id,
                Name = String.isBlank(r.name) ? ('Recipient ' + (++order)) : r.name,
                Weave_Template_Config__c = templateId,
                Active__c = r.active != false,
                Display_Order__c = r.displayOrder,
                Recipient_Type__c = String.isBlank(r.recipientType) ? 'To' : r.recipientType,
                Recipient_Source_Type__c = r.recipientSourceType,
                Source_Object_API_Name__c = r.sourceObjectApiName,
                Parent_Lookup_Field_API_Name__c = r.parentLookupFieldApiName,
                Name_Field_API_Name__c = r.nameFieldApiName,
                Email_Field_API_Name__c = r.emailFieldApiName,
                Segment_Id__c = r.segmentId,
                Filter_Logic__c = r.filterLogic,
                Default_Selected__c = r.defaultSelected != false,
                Allow_Multiple__c = r.allowMultiple != false,
                Required__c = r.required == true
            ));
        }
        upsert as user records;
    }

    private static void saveActions(WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto, Id templateId) {
        if (dto.actions == null || dto.actions.isEmpty()) return;
        List<Weave_Template_Action__c> records = new List<Weave_Template_Action__c>();
        Integer order = 0;
        for (WeaveBuilderDTOs.WeaveBuilderActionDTO a : dto.actions) {
            records.add(new Weave_Template_Action__c(
                Id = a.id,
                Name = String.isBlank(a.actionType) ? 'Action' : (a.actionType + ' ' + (++order)),
                Weave_Template_Config__c = templateId,
                Active__c = a.active != false,
                Action_Type__c = a.actionType,
                Run_Order__c = a.runOrder,
                Field_API_Name__c = a.fieldApiName,
                Value_Type__c = a.valueType,
                Value__c = a.value,
                Task_Subject__c = a.taskSubject,
                Assigned_To_Type__c = a.assignedToType,
                Assigned_User_Id__c = a.assignedUserId != null ? String.valueOf(a.assignedUserId) : null,
                Due_Date_Strategy__c = a.dueDateStrategy,
                Days_After_Send__c = a.daysAfterSend,
                Task_Status__c = String.isBlank(a.taskStatus) ? 'Completed' : a.taskStatus,
                Task_Priority__c = String.isBlank(a.taskPriority) ? 'Normal' : a.taskPriority,
                Task_Description__c = a.taskDescription
            ));
        }
        upsert as user records;
    }

    // ── Delete helper ─────────────────────────────────────────────────────────

    private static void deleteChildRecords(List<Id> ids, String objectType, String parentField, Id templateId) {
        if (ids == null || ids.isEmpty()) return;
        String soql = 'SELECT Id FROM ' + objectType + ' WHERE Id IN :ids AND ' + parentField + ' = :templateId WITH USER_MODE';
        List<SObject> toDelete = Database.query(soql);
        if (!toDelete.isEmpty()) delete as user toDelete;
    }

    // ── Load helpers ──────────────────────────────────────────────────────────

    private static WeaveBuilderDTOs.WeaveBuilderTemplateDTO toTemplateDto(Weave_Template_Config__c template) {
        WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto = new WeaveBuilderDTOs.WeaveBuilderTemplateDTO();
        dto.id = template.Id;
        dto.name = template.Name;
        dto.apiName = template.API_Name__c;
        dto.status = template.Status__c;
        dto.parentObjectApiName = template.Parent_Object_API_Name__c;
        dto.parentObjectLabel = getObjectLabel(template.Parent_Object_API_Name__c);
        dto.defaultFromEmail = template.Default_From_Email__c;
        dto.description = template.Description__c;
        dto.allowUserEditBeforeSend = template.Allow_User_Edit_Before_Send__c;
        dto.storeEmailHistory = template.Store_Email_History__c;
        dto.subjectTemplate = template.Subject_Template__c;
        dto.subjectVariantB = template.Subject_Variant_B__c;
        dto.brandId = template.Brand__c;
        dto.brandName = template.Brand__c != null ? template.Brand__r.Name : null;
        dto.templateOutputType = template.Template_Output_Type__c;
        dto.canvasPageSize = template.Canvas_Page_Size__c;
        dto.canvasOrientation = template.Canvas_Orientation__c;
        dto.queries = loadQueries(template.Id);
        dto.components = loadComponents(template.Id);
        dto.recipients = loadRecipients(template.Id, template.Parent_Object_API_Name__c);
        dto.actions = loadActions(template.Id, template.Parent_Object_API_Name__c);
        dto.attachments = loadAttachments(template.Id);
        return dto;
    }

    private static List<WeaveBuilderDTOs.WeaveBuilderQueryDTO> loadQueries(Id templateId) {
        List<WeaveBuilderDTOs.WeaveBuilderQueryDTO> dtos = new List<WeaveBuilderDTOs.WeaveBuilderQueryDTO>();
        for (Weave_Template_Query__c q : [
            SELECT Id, Name, Query_API_Name__c, SOQL_Query__c, Parent_Lookup_Field__c, Relationship_Type__c,
                   Parent_Query__c, Parent_Query__r.Query_API_Name__c
            FROM Weave_Template_Query__c
            WHERE Weave_Template_Config__c = :templateId
            WITH USER_MODE
            ORDER BY Name ASC
        ]) {
            WeaveBuilderDTOs.WeaveBuilderQueryDTO dto = new WeaveBuilderDTOs.WeaveBuilderQueryDTO();
            dto.id = q.Id;
            dto.name = q.Name;
            dto.queryApiName = q.Query_API_Name__c;
            dto.soqlQuery = q.SOQL_Query__c;
            dto.parentLookupField = q.Parent_Lookup_Field__c;
            dto.relationshipType = String.isBlank(q.Relationship_Type__c) ? 'down' : q.Relationship_Type__c;
            dto.parentQueryId = q.Parent_Query__c;
            dto.parentQueryLocalKey = q.Parent_Query__c != null ? q.Parent_Query__r.Query_API_Name__c : null;
            dtos.add(dto);
        }
        return dtos;
    }

    private static List<WeaveBuilderDTOs.WeaveBuilderComponentDTO> loadComponents(Id templateId) {
        List<WeaveBuilderDTOs.WeaveBuilderComponentDTO> dtos = new List<WeaveBuilderDTOs.WeaveBuilderComponentDTO>();
        for (Weave_Template_Component__c c : [
            SELECT Id, Name, Component_Type__c, Region__c, Display_Order__c,
                Linked_Query__c, Linked_Query__r.Name, Config_JSON__c, HTML_Output__c, Visibility_Condition__c,
                Canvas_Mode__c, Canvas_X__c, Canvas_Y__c, Canvas_W__c, Canvas_H__c, Canvas_Page__c
            FROM Weave_Template_Component__c
            WHERE Weave_Template_Config__c = :templateId
            WITH USER_MODE
            ORDER BY Region__c ASC, Display_Order__c ASC NULLS LAST, Name ASC
        ]) {
            WeaveBuilderDTOs.WeaveBuilderComponentDTO dto = new WeaveBuilderDTOs.WeaveBuilderComponentDTO();
            dto.id = c.Id;
            dto.name = c.Name;
            dto.componentType = c.Component_Type__c;
            dto.region = c.Region__c;
            dto.displayOrder = c.Display_Order__c != null ? c.Display_Order__c.intValue() : null;
            dto.linkedQueryId = c.Linked_Query__c;
            dto.linkedQueryName = c.Linked_Query__c != null ? c.Linked_Query__r.Name : null;
            dto.configJson = c.Config_JSON__c;
            dto.htmlOutput = c.HTML_Output__c;
            dto.canvasMode = c.Canvas_Mode__c;
            dto.canvasX = c.Canvas_X__c;
            dto.canvasY = c.Canvas_Y__c;
            dto.canvasW = c.Canvas_W__c;
            dto.canvasH = c.Canvas_H__c;
            dto.canvasPage = c.Canvas_Page__c != null ? c.Canvas_Page__c.intValue() : null;
            dto.visibilityCondition = c.Visibility_Condition__c;
            dtos.add(dto);
        }
        return dtos;
    }

    private static List<WeaveBuilderDTOs.WeaveBuilderRecipientDTO> loadRecipients(Id templateId, String parentObjectApiName) {
        List<WeaveBuilderDTOs.WeaveBuilderRecipientDTO> dtos = new List<WeaveBuilderDTOs.WeaveBuilderRecipientDTO>();
        for (Weave_Template_Recipient__c r : [
            SELECT Id, Name, Active__c, Display_Order__c, Recipient_Type__c, Recipient_Source_Type__c,
                Source_Object_API_Name__c, Parent_Lookup_Field_API_Name__c, Name_Field_API_Name__c,
                Email_Field_API_Name__c, Filter_Logic__c, Default_Selected__c, Allow_Multiple__c, Required__c,
                Segment_Id__c
            FROM Weave_Template_Recipient__c
            WHERE Weave_Template_Config__c = :templateId
            WITH USER_MODE
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ]) {
            WeaveBuilderDTOs.WeaveBuilderRecipientDTO dto = new WeaveBuilderDTOs.WeaveBuilderRecipientDTO();
            dto.id = r.Id;
            dto.name = r.Name;
            dto.active = r.Active__c;
            dto.displayOrder = r.Display_Order__c != null ? r.Display_Order__c.intValue() : null;
            dto.recipientType = r.Recipient_Type__c;
            dto.recipientSourceType = r.Recipient_Source_Type__c;
            dto.sourceObjectApiName = r.Source_Object_API_Name__c;
            String sourceObj = String.isBlank(r.Source_Object_API_Name__c) ? parentObjectApiName : r.Source_Object_API_Name__c;
            dto.sourceObjectLabel = getObjectLabel(sourceObj);
            dto.parentLookupFieldApiName = r.Parent_Lookup_Field_API_Name__c;
            dto.parentLookupFieldLabel = getFieldLabel(sourceObj, r.Parent_Lookup_Field_API_Name__c);
            dto.nameFieldApiName = r.Name_Field_API_Name__c;
            dto.nameFieldLabel = getFieldLabel(sourceObj, r.Name_Field_API_Name__c);
            dto.emailFieldApiName = r.Email_Field_API_Name__c;
            dto.emailFieldLabel = getFieldLabel(sourceObj, r.Email_Field_API_Name__c);
            dto.filterLogic = r.Filter_Logic__c;
            dto.defaultSelected = r.Default_Selected__c;
            dto.allowMultiple = r.Allow_Multiple__c;
            dto.required = r.Required__c;
            dto.segmentId = r.Segment_Id__c;
            dtos.add(dto);
        }
        return dtos;
    }

    private static List<WeaveBuilderDTOs.WeaveBuilderActionDTO> loadActions(Id templateId, String parentObjectApiName) {
        List<WeaveBuilderDTOs.WeaveBuilderActionDTO> dtos = new List<WeaveBuilderDTOs.WeaveBuilderActionDTO>();
        for (Weave_Template_Action__c a : [
            SELECT Id, Name, Active__c, Run_Order__c, Action_Type__c,
                Field_API_Name__c, Value_Type__c, Value__c,
                Task_Subject__c, Assigned_To_Type__c, Assigned_User_Id__c,
                Due_Date_Strategy__c, Days_After_Send__c, Task_Status__c, Task_Priority__c, Task_Description__c
            FROM Weave_Template_Action__c
            WHERE Weave_Template_Config__c = :templateId
            WITH USER_MODE
            ORDER BY Run_Order__c ASC NULLS LAST, Name ASC
        ]) {
            WeaveBuilderDTOs.WeaveBuilderActionDTO dto = new WeaveBuilderDTOs.WeaveBuilderActionDTO();
            dto.id = a.Id;
            dto.active = a.Active__c;
            dto.runOrder = a.Run_Order__c != null ? a.Run_Order__c.intValue() : null;
            dto.actionType = a.Action_Type__c;
            dto.fieldApiName = a.Field_API_Name__c;
            dto.fieldLabel = getFieldLabel(parentObjectApiName, a.Field_API_Name__c);
            dto.valueType = a.Value_Type__c;
            dto.value = a.Value__c;
            dto.taskSubject = a.Task_Subject__c;
            dto.assignedToType = a.Assigned_To_Type__c;
            dto.assignedUserId = String.isBlank(a.Assigned_User_Id__c) ? null : (Id) a.Assigned_User_Id__c;
            dto.dueDateStrategy = a.Due_Date_Strategy__c;
            dto.daysAfterSend = a.Days_After_Send__c != null ? a.Days_After_Send__c.intValue() : 0;
            dto.taskStatus = a.Task_Status__c;
            dto.taskPriority = a.Task_Priority__c;
            dto.taskDescription = a.Task_Description__c;
            dtos.add(dto);
        }
        return dtos;
    }

    private static void saveAttachments(WeaveBuilderDTOs.WeaveBuilderTemplateDTO dto, Id templateId) {
        if (dto.attachments == null || dto.attachments.isEmpty()) return;
        List<Weave_Template_Attachment__c> records = new List<Weave_Template_Attachment__c>();
        Integer order = 0;
        for (WeaveBuilderDTOs.WeaveBuilderAttachmentDTO a : dto.attachments) {
            records.add(new Weave_Template_Attachment__c(
                Id = a.id,
                Name = 'Attachment ' + (++order),
                Weave_Template_Config__c = templateId,
                Active__c = a.active != false,
                Display_Order__c = a.displayOrder,
                Attachment_Source__c = String.isBlank(a.attachmentSource) ? 'Static File' : a.attachmentSource,
                Static_Content_Document_Id__c = a.staticContentDocumentId,
                Linked_Query__c = a.linkedQueryId,
                File_Title_Filter__c = a.fileTitleFilter,
                Max_Attachments__c = a.maxAttachments != null ? a.maxAttachments : 5
            ));
        }
        upsert as user records;
        for (Integer i = 0; i < dto.attachments.size(); i++) {
            if (dto.attachments[i].id == null) {
                dto.attachments[i].id = records[i].Id;
            }
        }
    }

    private static List<WeaveBuilderDTOs.WeaveBuilderAttachmentDTO> loadAttachments(Id templateId) {
        List<WeaveBuilderDTOs.WeaveBuilderAttachmentDTO> dtos = new List<WeaveBuilderDTOs.WeaveBuilderAttachmentDTO>();
        for (Weave_Template_Attachment__c a : [
            SELECT Id, Active__c, Display_Order__c, Attachment_Source__c,
                Static_Content_Document_Id__c, Linked_Query__c, Linked_Query__r.Name,
                File_Title_Filter__c, Max_Attachments__c
            FROM Weave_Template_Attachment__c
            WHERE Weave_Template_Config__c = :templateId
            WITH USER_MODE
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ]) {
            WeaveBuilderDTOs.WeaveBuilderAttachmentDTO dto = new WeaveBuilderDTOs.WeaveBuilderAttachmentDTO();
            dto.id = a.Id;
            dto.active = a.Active__c;
            dto.displayOrder = a.Display_Order__c != null ? a.Display_Order__c.intValue() : null;
            dto.attachmentSource = a.Attachment_Source__c;
            dto.staticContentDocumentId = a.Static_Content_Document_Id__c;
            dto.linkedQueryId = a.Linked_Query__c;
            dto.linkedQueryName = a.Linked_Query__c != null ? a.Linked_Query__r.Name : null;
            dto.fileTitleFilter = a.File_Title_Filter__c;
            dto.maxAttachments = a.Max_Attachments__c != null ? a.Max_Attachments__c.intValue() : 5;
            dtos.add(dto);
        }
        return dtos;
    }

    // ── Validation ────────────────────────────────────────────────────────────

    private static void validateRecipient(WeaveBuilderDTOs.WeaveBuilderRecipientDTO r) {
        if (String.isBlank(r.recipientSourceType)) {
            throw new AuraHandledException('Recipient source type is required.');
        }
        if (r.recipientSourceType == 'Parent Field' && String.isBlank(r.emailFieldApiName)) {
            throw new AuraHandledException('Email field is required for Parent Field recipients.');
        }
        if (r.recipientSourceType == 'Related Records') {
            if (String.isBlank(r.sourceObjectApiName)) {
                throw new AuraHandledException('Source object is required for Related Records recipients.');
            }
            if (String.isBlank(r.emailFieldApiName)) {
                throw new AuraHandledException('Email field is required for Related Records recipients.');
            }
        }
        if (r.recipientSourceType == 'Dynamic Segment' && String.isBlank(r.segmentId)) {
            throw new AuraHandledException('A segment must be selected for Dynamic Segment recipients.');
        }
    }

    // ── API Name generation ───────────────────────────────────────────────────

    @TestVisible
    static String generateApiName(String displayName) {
        if (String.isBlank(displayName)) return 'untitled';
        String base = displayName.toLowerCase()
            .replaceAll('[^a-z0-9]+', '_')
            .replaceAll('^_+|_+$', '');
        if (String.isBlank(base)) base = 'untitled';
        // Check uniqueness — append suffix if collision
        Set<String> existing = new Set<String>();
        for (Weave_Template_Config__c t : [
            SELECT API_Name__c FROM Weave_Template_Config__c WHERE API_Name__c LIKE :base + '%' WITH USER_MODE
        ]) {
            existing.add(t.API_Name__c);
        }
        for (Weave_Template_Query__c q : [
            SELECT Query_API_Name__c FROM Weave_Template_Query__c WHERE Query_API_Name__c LIKE :base + '%' WITH USER_MODE
        ]) {
            existing.add(q.Query_API_Name__c);
        }
        if (!existing.contains(base)) return base;
        for (Integer i = 2; i <= 999; i++) {
            String candidate = base + '_' + i;
            if (!existing.contains(candidate)) return candidate;
        }
        return base + '_' + System.currentTimeMillis();
    }

    // ── Field / object helpers ────────────────────────────────────────────────

    private static WeaveBuilderDTOs.WeaveBuilderFieldDTO toFieldDto(Schema.DescribeFieldResult describe) {
        WeaveBuilderDTOs.WeaveBuilderFieldDTO dto = new WeaveBuilderDTOs.WeaveBuilderFieldDTO();
        dto.label = describe.getLabel();
        dto.apiName = describe.getName();
        dto.dataType = String.valueOf(describe.getType());
        dto.relationshipName = describe.getRelationshipName();
        dto.isSortable = describe.isSortable();
        dto.isFilterable = describe.isFilterable();
        dto.isNameField = describe.isNameField();
        for (Schema.SObjectType referenceType : describe.getReferenceTo()) {
            dto.referenceTo.add(referenceType.getDescribe().getName());
        }
        return dto;
    }

    private static Schema.DescribeSObjectResult assertReadableObject(String objectApiName) {
        if (String.isBlank(objectApiName) || !Schema.getGlobalDescribe().containsKey(objectApiName)) {
            throw new AuraHandledException('Invalid object API name: ' + objectApiName);
        }
        Schema.DescribeSObjectResult describe = Schema.getGlobalDescribe().get(objectApiName).getDescribe();
        if (!describe.isAccessible()) {
            throw new AuraHandledException('You do not have access to this object.');
        }
        return describe;
    }

    private static void assertObjectReadable(Schema.SObjectType objectType) {
        if (!objectType.getDescribe().isAccessible()) {
            throw new AuraHandledException('You do not have access to Weave template data.');
        }
    }

    private static String getObjectLabel(String objectApiName) {
        if (String.isBlank(objectApiName) || !Schema.getGlobalDescribe().containsKey(objectApiName)) {
            return objectApiName;
        }
        return Schema.getGlobalDescribe().get(objectApiName).getDescribe().getLabel();
    }

    private static String getFieldLabel(String objectApiName, String fieldPath) {
        if (String.isBlank(objectApiName) || String.isBlank(fieldPath) || !Schema.getGlobalDescribe().containsKey(objectApiName)) {
            return fieldPath;
        }
        List<String> segments = fieldPath.split('\\.');
        String leafFieldName = segments.isEmpty() ? fieldPath : segments[segments.size() - 1];
        Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();
        if (fields.containsKey(leafFieldName)) {
            return fields.get(leafFieldName).getDescribe().getLabel();
        }
        return fieldPath;
    }

    private static String buildOrgWideEmailLabel(String displayName, String address) {
        if (String.isBlank(displayName)) return address;
        if (String.isBlank(address)) return displayName;
        return displayName + ' <' + address + '>';
    }

    private class ObjectLabelComparator implements Comparator<WeaveBuilderDTOs.WeaveBuilderObjectDTO> {
        public Integer compare(WeaveBuilderDTOs.WeaveBuilderObjectDTO a, WeaveBuilderDTOs.WeaveBuilderObjectDTO b) {
            return a.label.compareTo(b.label);
        }
    }

    private class FieldLabelComparator implements Comparator<WeaveBuilderDTOs.WeaveBuilderFieldDTO> {
        public Integer compare(WeaveBuilderDTOs.WeaveBuilderFieldDTO a, WeaveBuilderDTOs.WeaveBuilderFieldDTO b) {
            return a.label.compareTo(b.label);
        }
    }

    // ── File management ─────────────────────────────────────────────────────────

    private static final Set<String> IMAGE_TYPES = new Set<String>{ 'png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'bmp' };

    public static List<Map<String,String>> getTemplateFiles(Id templateId, String fileType) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileType,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :templateId
            WITH USER_MODE
            ORDER BY ContentDocument.CreatedDate DESC
        ];
        List<Map<String,String>> result = new List<Map<String,String>>();
        for (ContentDocumentLink cdl : links) {
            String docType = (cdl.ContentDocument.FileType ?? '').toLowerCase();
            Boolean isImage = IMAGE_TYPES.contains(docType);
            if ((fileType == 'image' && isImage) || (fileType == 'attachment' && !isImage)) {
                Map<String,String> m = new Map<String,String>{
                    'contentDocumentId' => cdl.ContentDocumentId,
                    'contentVersionId'  => cdl.ContentDocument.LatestPublishedVersionId,
                    'title'             => cdl.ContentDocument.Title,
                    'fileType'          => cdl.ContentDocument.FileType
                };
                result.add(m);
            }
        }
        return result;
    }

    public static String createPublicImageLink(Id contentVersionId) {
        List<ContentDistribution> existing = [
            SELECT ContentDownloadUrl FROM ContentDistribution
            WHERE ContentVersionId = :contentVersionId
            WITH USER_MODE LIMIT 1
        ];
        if (!existing.isEmpty() && !String.isBlank(existing[0].ContentDownloadUrl)) {
            return existing[0].ContentDownloadUrl;
        }
        ContentDistribution cd = new ContentDistribution();
        cd.Name = 'Weave Public Image';
        cd.ContentVersionId = contentVersionId;
        cd.PreferencesAllowViewInBrowser = true;
        cd.PreferencesLinkLatestVersion = true;
        cd.PreferencesNotifyOnVisit = false;
        cd.PreferencesPasswordRequired = false;
        insert as user cd;
        cd = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :cd.Id WITH USER_MODE LIMIT 1];
        return cd.ContentDownloadUrl;
    }

    public static void deleteTemplateFile(Id contentDocumentId) {
        ContentDocument doc = new ContentDocument(Id = contentDocumentId);
        delete as user doc;
    }
}
