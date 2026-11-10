public with sharing class DceTemplateBuilderService {
    private static final String EDITOR_MODE_VISUAL = 'Visual';
    private static final String EDITOR_MODE_HTML_SOURCE = 'HTML Source';

    public static List<DceOrgWideEmailDTO> getOrgWideEmailAddresses() {
        DceTemplateSecurityService.assertCanManageTemplates();
        List<DceOrgWideEmailDTO> results = new List<DceOrgWideEmailDTO>();
        for (OrgWideEmailAddress orgWideEmail : [
            SELECT Id, DisplayName, Address
            FROM OrgWideEmailAddress
            WITH USER_MODE
            ORDER BY DisplayName ASC, Address ASC
        ]) {
            DceOrgWideEmailDTO dto = new DceOrgWideEmailDTO();
            dto.id = orgWideEmail.Id;
            dto.displayName = orgWideEmail.DisplayName;
            dto.address = orgWideEmail.Address;
            dto.label = buildOrgWideEmailLabel(orgWideEmail.DisplayName, orgWideEmail.Address);
            results.add(dto);
        }
        return results;
    }

    public static List<DceBuilderTemplateSummaryDTO> getTemplates() {
        DceTemplateSecurityService.assertCanManageTemplates();
        assertObjectReadable(Email_Template_Config__c.SObjectType);
        List<DceBuilderTemplateSummaryDTO> results = new List<DceBuilderTemplateSummaryDTO>();
        for (Email_Template_Config__c template : [
            SELECT Id, Name, Parent_Object_API_Name__c, Active__c, Description__c, LastModifiedDate
            FROM Email_Template_Config__c
            WITH USER_MODE
            ORDER BY Name ASC
        ]) {
            DceBuilderTemplateSummaryDTO dto = new DceBuilderTemplateSummaryDTO();
            dto.id = template.Id;
            dto.name = template.Name;
            dto.parentObjectApiName = template.Parent_Object_API_Name__c;
            dto.parentObjectLabel = getObjectLabel(template.Parent_Object_API_Name__c);
            dto.active = template.Active__c;
            dto.description = template.Description__c;
            dto.lastModifiedDate = template.LastModifiedDate;
            results.add(dto);
        }
        return results;
    }

    public static List<DceBuilderObjectDTO> getAvailableObjects() {
        DceTemplateSecurityService.assertCanManageTemplates();
        List<DceBuilderObjectDTO> results = new List<DceBuilderObjectDTO>();
        for (Schema.SObjectType objectType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult describe = objectType.getDescribe();
            if (!describe.isAccessible() || !describe.isQueryable() || describe.isDeprecatedAndHidden()) {
                continue;
            }
            String apiName = describe.getName();
            if (apiName.endsWith('Share') || apiName.endsWith('History') || apiName.endsWith('Feed')) {
                continue;
            }
            results.add(new DceBuilderObjectDTO(describe.getLabel(), apiName, describe.getLabelPlural()));
        }
        results.sort(new ObjectLabelComparator());
        return results;
    }

    public static List<DceBuilderFieldDTO> getFieldsForObject(String objectApiName) {
        DceTemplateSecurityService.assertCanManageTemplates();
        Schema.DescribeSObjectResult objectDescribe = assertReadableObject(objectApiName);
        List<DceBuilderFieldDTO> fields = new List<DceBuilderFieldDTO>();
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

    public static List<DceBuilderFieldDTO> getUpdateableFieldsForObject(String objectApiName) {
        DceTemplateSecurityService.assertCanManageTemplates();
        Schema.DescribeSObjectResult objectDescribe = assertReadableObject(objectApiName);
        List<DceBuilderFieldDTO> fields = new List<DceBuilderFieldDTO>();
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

    public static List<DceBuilderFieldDTO> getRelationshipFields(String objectApiName) {
        DceTemplateSecurityService.assertCanManageTemplates();
        List<DceBuilderFieldDTO> fields = new List<DceBuilderFieldDTO>();
        for (DceBuilderFieldDTO fieldDto : getFieldsForObject(objectApiName)) {
            if (!String.isBlank(fieldDto.relationshipName)) {
                fields.add(fieldDto);
            }
        }
        return fields;
    }

    public static List<DceBuilderFieldDTO> getLookupFieldsForChildObject(String childObjectApiName, String parentObjectApiName) {
        DceTemplateSecurityService.assertCanManageTemplates();
        List<DceBuilderFieldDTO> fields = new List<DceBuilderFieldDTO>();
        for (DceBuilderFieldDTO fieldDto : getRelationshipFields(childObjectApiName)) {
            if (String.isBlank(parentObjectApiName) || fieldDto.referenceTo.contains(parentObjectApiName)) {
                fields.add(fieldDto);
            }
        }
        return fields;
    }

    public static DceBuilderTemplateDTO loadTemplate(Id templateId) {
        DceTemplateSecurityService.assertCanManageTemplates();
        assertObjectReadable(Email_Template_Config__c.SObjectType);
        assertObjectReadable(Email_Template_Section__c.SObjectType);
        assertObjectReadable(Email_Template_Line__c.SObjectType);
        assertObjectReadable(Email_Template_Field__c.SObjectType);
        assertObjectReadable(Email_Template_Recipient_Config__c.SObjectType);
        if (templateId == null) {
            return new DceBuilderTemplateDTO();
        }
        List<Email_Template_Config__c> templates = [
            SELECT Id, Name, Active__c, Parent_Object_API_Name__c, Subject_Template__c, Body_Template__c,
                Header__c, Footer__c, Header_Editor_Mode__c, Body_Editor_Mode__c, Footer_Editor_Mode__c,
                Description__c, Default_From_Email__c,
                Allow_User_Edit_Before_Send__c, Store_Email_History__c, Post_Send_Actions__c
            FROM Email_Template_Config__c
            WHERE Id = :templateId
            WITH USER_MODE
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            throw new AuraHandledException('Template not found.');
        }
        return toTemplateDto(templates[0]);
    }

    public static DceBuilderTemplateDTO saveTemplate(DceBuilderTemplateDTO dto) {
        DceTemplateSecurityService.assertCanManageTemplates();
        if (dto == null) {
            throw new AuraHandledException('Template data is required.');
        }
        if (String.isBlank(dto.name)) {
            throw new AuraHandledException('Template name is required.');
        }
        if (String.isBlank(dto.parentObjectApiName)) {
            throw new AuraHandledException('Select a parent object before saving.');
        }
        if (String.isBlank(dto.subjectTemplate)) {
            throw new AuraHandledException('Subject template is required.');
        }
        if (String.isBlank(dto.bodyTemplate)) {
            throw new AuraHandledException('Body template is required.');
        }
        assertReadableObject(dto.parentObjectApiName);
        String headerContent = firstNonNull(dto.headerContent, dto.header);
        String footerContent = firstNonNull(dto.footerContent, dto.footer);
        DceHtmlPolicy.assertSafeTemplateHtml(headerContent, 'Header');
        DceHtmlPolicy.assertSafeTemplateHtml(dto.bodyTemplate, 'Body');
        DceHtmlPolicy.assertSafeTemplateHtml(footerContent, 'Footer');
        DceTemplateContentService.PreparedContent preparedContent =
            DceTemplateContentService.prepareContent(headerContent, dto.bodyTemplate, footerContent);

        Savepoint sp = Database.setSavepoint();
        try {
            assertCanSaveGraph(dto);
            assertExistingGraphOwnership(dto);
            Email_Template_Config__c template = new Email_Template_Config__c(
                Id = dto.id,
                Name = dto.name,
                Active__c = dto.active == true,
                Parent_Object_API_Name__c = dto.parentObjectApiName,
                Subject_Template__c = dto.subjectTemplate,
                Body_Template__c = preparedContent.bodyInline,
                Header__c = preparedContent.headerInline,
                Footer__c = preparedContent.footerInline,
                Header_Editor_Mode__c = normalizeEditorMode(dto.headerEditorMode),
                Body_Editor_Mode__c = normalizeEditorMode(dto.bodyEditorMode),
                Footer_Editor_Mode__c = normalizeEditorMode(dto.footerEditorMode),
                Description__c = dto.description,
                Default_From_Email__c = dto.defaultFromEmail,
                Allow_User_Edit_Before_Send__c = dto.allowUserEditBeforeSend == true,
                Store_Email_History__c = dto.storeEmailHistory == true,
                Post_Send_Actions__c = serializePostSendActions(dto.postSendActions)
            );
            upsert as user template;
            dto.id = template.Id;

            deleteLines(dto.deletedLineIds, template.Id);
            deleteFields(dto.deletedFieldIds, template.Id);
            deleteRecipients(dto.deletedRecipientIds, template.Id);
            deleteSections(dto.deletedSectionIds, template.Id);

            saveSections(dto, template.Id);
            saveRecipients(dto, template.Id);
            DceTemplateContentService.replaceOverflowChunks(template.Id, preparedContent.overflowChunks);
            return loadTemplate(template.Id);
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Unable to save template. Please review the configuration and try again.');
        }
    }

    public static void deleteTemplate(Id templateId) {
        DceTemplateSecurityService.assertCanManageTemplates();
        if (templateId == null) {
            throw new AuraHandledException('Template Id is required.');
        }
        assertObjectDeleteable(Email_Template_Config__c.SObjectType);
        try {
            List<Email_Template_Config__c> templatesToDelete = [
                SELECT Id
                FROM Email_Template_Config__c
                WHERE Id = :templateId
                WITH USER_MODE
                LIMIT 1
            ];
            if (!templatesToDelete.isEmpty()) {
                delete as user templatesToDelete;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Unable to delete template. Please contact your administrator.');
        }
    }

    private static void assertExistingGraphOwnership(DceBuilderTemplateDTO dto) {
        Set<Id> sectionIds = new Set<Id>();
        Set<Id> lineIds = new Set<Id>();
        Set<Id> fieldIds = new Set<Id>();
        Set<Id> recipientIds = new Set<Id>();

        for (DceBuilderSectionDTO section : dto.sections ?? new List<DceBuilderSectionDTO>()) {
            if (section.id != null) sectionIds.add(section.id);
            for (DceBuilderSectionDTO.DceBuilderLineDTO line : section.lines ?? new List<DceBuilderSectionDTO.DceBuilderLineDTO>()) {
                if (line.id != null) lineIds.add(line.id);
            }
            for (DceBuilderSectionDTO.DceBuilderColumnDTO field : section.fields ?? new List<DceBuilderSectionDTO.DceBuilderColumnDTO>()) {
                if (field.id != null) fieldIds.add(field.id);
            }
        }
        for (DceBuilderRecipientDTO recipient : dto.recipients ?? new List<DceBuilderRecipientDTO>()) {
            if (recipient.id != null) recipientIds.add(recipient.id);
        }
        sectionIds.addAll(dto.deletedSectionIds ?? new List<Id>());
        lineIds.addAll(dto.deletedLineIds ?? new List<Id>());
        fieldIds.addAll(dto.deletedFieldIds ?? new List<Id>());
        recipientIds.addAll(dto.deletedRecipientIds ?? new List<Id>());

        if (dto.id == null) {
            if (!sectionIds.isEmpty() || !lineIds.isEmpty() || !fieldIds.isEmpty() || !recipientIds.isEmpty()) {
                throw new AuraHandledException('New templates cannot reference existing child records.');
            }
            return;
        }

        if ([
            SELECT COUNT()
            FROM Email_Template_Config__c
            WHERE Id = :dto.id
            WITH USER_MODE
        ] != 1) {
            throw new AuraHandledException('Template not found or is not accessible.');
        }
        if (!sectionIds.isEmpty() && [
            SELECT COUNT()
            FROM Email_Template_Section__c
            WHERE Id IN :sectionIds
            AND Email_Template_Config__c = :dto.id
            WITH USER_MODE
        ] != sectionIds.size()) {
            throw new AuraHandledException('One or more sections do not belong to this template.');
        }
        if (!lineIds.isEmpty() && [
            SELECT COUNT()
            FROM Email_Template_Line__c
            WHERE Id IN :lineIds
            AND Email_Template_Section__r.Email_Template_Config__c = :dto.id
            WITH USER_MODE
        ] != lineIds.size()) {
            throw new AuraHandledException('One or more section lines do not belong to this template.');
        }
        if (!fieldIds.isEmpty() && [
            SELECT COUNT()
            FROM Email_Template_Field__c
            WHERE Id IN :fieldIds
            AND Email_Template_Section__r.Email_Template_Config__c = :dto.id
            WITH USER_MODE
        ] != fieldIds.size()) {
            throw new AuraHandledException('One or more section fields do not belong to this template.');
        }
        if (!recipientIds.isEmpty() && [
            SELECT COUNT()
            FROM Email_Template_Recipient_Config__c
            WHERE Id IN :recipientIds
            AND Email_Template_Config__c = :dto.id
            WITH USER_MODE
        ] != recipientIds.size()) {
            throw new AuraHandledException('One or more recipients do not belong to this template.');
        }
    }

    private static void saveSections(DceBuilderTemplateDTO dto, Id templateId) {
        if (dto.sections == null || dto.sections.isEmpty()) {
            return;
        }

        List<DceBuilderSectionDTO> sectionDtos = new List<DceBuilderSectionDTO>();
        List<Email_Template_Section__c> sections = new List<Email_Template_Section__c>();
        for (DceBuilderSectionDTO sectionDto : dto.sections) {
            validateSection(sectionDto);
            sectionDtos.add(sectionDto);
            sections.add(new Email_Template_Section__c(
                Id = sectionDto.id,
                Name = String.isBlank(sectionDto.name) ? sectionDto.sectionName : sectionDto.name,
                Email_Template_Config__c = templateId,
                Section_Name__c = sectionDto.sectionName,
                Section_Key__c = sectionDto.sectionKey,
                Active__c = sectionDto.active == true,
                Display_Order__c = sectionDto.displayOrder,
                Section_Type__c = sectionDto.sectionType,
                Child_Object_API_Name__c = sectionDto.childObjectApiName,
                Parent_Lookup_Field_API_Name__c = sectionDto.parentLookupFieldApiName,
                Sort_Field_API_Name__c = sectionDto.sortFieldApiName,
                Sort_Direction__c = sectionDto.sortDirection,
                Filter_Logic__c = sectionDto.filterLogic,
                Static_Content__c = sectionDto.staticContent,
                Section_Header__c = sectionDto.sectionHeader,
                Section_Footer__c = sectionDto.sectionFooter,
                Repeat_Label__c = sectionDto.repeatLabel,
                Include_Auto_Number__c = sectionDto.includeAutoNumber == true,
                Auto_Number_Start__c = sectionDto.autoNumberStart
            ));
        }
        upsert as user sections;

        List<Email_Template_Line__c> lines = new List<Email_Template_Line__c>();
        List<Email_Template_Field__c> fields = new List<Email_Template_Field__c>();
        for (Integer sectionIndex = 0; sectionIndex < sections.size(); sectionIndex++) {
            DceBuilderSectionDTO sectionDto = sectionDtos[sectionIndex];
            Id sectionId = sections[sectionIndex].Id;
            sectionDto.id = sectionId;
            lines.addAll(buildLines(sectionDto, sectionId));
            fields.addAll(buildFields(sectionDto, sectionId));
        }
        if (!lines.isEmpty()) {
            upsert as user lines;
        }
        if (!fields.isEmpty()) {
            upsert as user fields;
        }
    }

    private static List<Email_Template_Line__c> buildLines(DceBuilderSectionDTO sectionDto, Id sectionId) {
        List<Email_Template_Line__c> lines = new List<Email_Template_Line__c>();
        for (DceBuilderSectionDTO.DceBuilderLineDTO lineDto : sectionDto.lines ?? new List<DceBuilderSectionDTO.DceBuilderLineDTO>()) {
            DceHtmlPolicy.assertSafeTemplateHtml(lineDto.lineTemplate, 'Section line');
            lines.add(new Email_Template_Line__c(
                Id = lineDto.id,
                Name = String.isBlank(lineDto.name) ? 'Line ' + String.valueOf(lineDto.displayOrder) : lineDto.name,
                Email_Template_Section__c = sectionId,
                Display_Order__c = lineDto.displayOrder,
                Active__c = lineDto.active == true,
                Line_Template__c = lineDto.lineTemplate,
                Display_Style__c = String.isBlank(lineDto.displayStyle) ? 'Normal' : lineDto.displayStyle,
                Render_Only_If_Not_Blank__c = lineDto.renderOnlyIfNotBlank == true
            ));
        }
        return lines;
    }

    private static List<Email_Template_Field__c> buildFields(DceBuilderSectionDTO sectionDto, Id sectionId) {
        List<Email_Template_Field__c> fields = new List<Email_Template_Field__c>();
        for (DceBuilderSectionDTO.DceBuilderColumnDTO fieldDto : sectionDto.fields ?? new List<DceBuilderSectionDTO.DceBuilderColumnDTO>()) {
            assertReadableField(sectionDto.childObjectApiName, fieldDto.fieldApiName, 'section column');
            fields.add(new Email_Template_Field__c(
                Id = fieldDto.id,
                Name = String.isBlank(fieldDto.name) ? fieldDto.fieldApiName : fieldDto.name,
                Email_Template_Section__c = sectionId,
                Field_API_Name__c = fieldDto.fieldApiName,
                Label_Override__c = fieldDto.labelOverride,
                Display_Order__c = fieldDto.displayOrder,
                Active__c = fieldDto.active == true,
                Show_Label__c = fieldDto.showLabel != false,
                Display_Style__c = String.isBlank(fieldDto.displayStyle) ? 'Normal' : fieldDto.displayStyle,
                Is_Main_Title__c = fieldDto.isMainTitle == true,
                Prefix_Text__c = fieldDto.prefixText,
                Suffix_Text__c = fieldDto.suffixText,
                Line_Break_After__c = fieldDto.lineBreakAfter == true,
                Render_Only_If_Not_Blank__c = fieldDto.renderOnlyIfNotBlank == true,
                Table_Column_Width__c = fieldDto.tableColumnWidth
            ));
        }
        return fields;
    }

    private static void saveRecipients(DceBuilderTemplateDTO dto, Id templateId) {
        if (dto.recipients == null) {
            return;
        }
        List<Email_Template_Recipient_Config__c> recipients = new List<Email_Template_Recipient_Config__c>();
        Integer activeRelatedRecordSources = 0;
        for (DceBuilderRecipientDTO recipientDto : dto.recipients) {
            validateRecipient(recipientDto);
            if (recipientDto.recipientSourceType == 'Parent Field') {
                Schema.DescribeSObjectResult parentDescribe = assertReadableObject(dto.parentObjectApiName);
                assertReadableField(parentDescribe, recipientDto.nameFieldApiName, 'recipient name field');
                assertReadableField(parentDescribe, recipientDto.emailFieldApiName, 'recipient email field');
            }
            if (recipientDto.active == true && recipientDto.recipientSourceType == 'Related Records') {
                activeRelatedRecordSources++;
            }
            recipients.add(new Email_Template_Recipient_Config__c(
                Id = recipientDto.id,
                Name = String.isBlank(recipientDto.name) ? recipientDto.recipientSourceType + ' Recipient' : recipientDto.name,
                Email_Template_Config__c = templateId,
                Active__c = recipientDto.active == true,
                Display_Order__c = recipientDto.displayOrder,
                Recipient_Source_Type__c = recipientDto.recipientSourceType,
                Recipient_Type__c = recipientDto.recipientType,
                Source_Object_API_Name__c = recipientDto.sourceObjectApiName,
                Parent_Lookup_Field_API_Name__c = recipientDto.parentLookupFieldApiName,
                Name_Field_API_Name__c = recipientDto.nameFieldApiName,
                Email_Field_API_Name__c = recipientDto.emailFieldApiName,
                Filter_Logic__c = recipientDto.filterLogic,
                Default_Selected__c = recipientDto.defaultSelected == true,
                Allow_Multiple__c = recipientDto.allowMultiple == true,
                Required__c = recipientDto.required == true
            ));
        }
        if (activeRelatedRecordSources > 1) {
            throw new AuraHandledException(
                'Use only one active Related Records recipient source per template. ' +
                'A single source can still return multiple recipients.'
            );
        }
        if (!recipients.isEmpty()) {
            upsert as user recipients;
        }
    }

    private static void validateRecipient(DceBuilderRecipientDTO recipientDto) {
        if (String.isBlank(recipientDto.recipientSourceType)) {
            throw new AuraHandledException('Recipient source type is required.');
        }
        if (String.isBlank(recipientDto.recipientType)) {
            throw new AuraHandledException('Recipient type is required.');
        }
        if (recipientDto.recipientSourceType == 'Manual') {
            return;
        }
        if (String.isBlank(recipientDto.nameFieldApiName) || String.isBlank(recipientDto.emailFieldApiName)) {
            throw new AuraHandledException('Recipient name and email fields are required.');
        }
        if (recipientDto.recipientSourceType == 'Related Records') {
            if (String.isBlank(recipientDto.sourceObjectApiName)) {
                throw new AuraHandledException('Recipient source object is required.');
            }
            if (String.isBlank(recipientDto.parentLookupFieldApiName)) {
                throw new AuraHandledException('Recipient parent lookup field is required.');
            }
        }
        String sourceObject = recipientDto.recipientSourceType == 'Related Records'
            ? recipientDto.sourceObjectApiName
            : null;
        if (!String.isBlank(sourceObject)) {
            Schema.DescribeSObjectResult sourceDescribe = assertReadableObject(sourceObject);
            assertReadableField(sourceDescribe, recipientDto.parentLookupFieldApiName, 'recipient parent lookup field');
            assertReadableField(sourceDescribe, recipientDto.nameFieldApiName, 'recipient name field');
            assertReadableField(sourceDescribe, recipientDto.emailFieldApiName, 'recipient email field');
        }
    }

    private static void validateSection(DceBuilderSectionDTO sectionDto) {
        if (String.isBlank(sectionDto.sectionName)) {
            throw new AuraHandledException('Section name is required.');
        }
        if (String.isBlank(sectionDto.sectionKey)) {
            throw new AuraHandledException('Section key is required.');
        }
        if (String.isBlank(sectionDto.sectionType)) {
            throw new AuraHandledException('Section type is required.');
        }
        if (sectionDto.sectionType == 'Static Text' && String.isBlank(sectionDto.staticContent)) {
            throw new AuraHandledException('Static Text sections require static content.');
        }
        if ((sectionDto.sectionType == 'Text Block' || sectionDto.sectionType == 'Table') && String.isBlank(sectionDto.childObjectApiName)) {
            throw new AuraHandledException('Select a data source for this section.');
        }
        if ((sectionDto.sectionType == 'Text Block' || sectionDto.sectionType == 'Table') && String.isBlank(sectionDto.parentLookupFieldApiName)) {
            throw new AuraHandledException('Select the lookup field that connects this object to the parent record.');
        }
        if (sectionDto.sectionType == 'Table' && (sectionDto.fields == null || sectionDto.fields.isEmpty())) {
            throw new AuraHandledException('Add at least one column before saving this table section.');
        }
        DceHtmlPolicy.assertSafeTemplateHtml(sectionDto.staticContent, 'Section content');
        DceHtmlPolicy.assertSafeTemplateHtml(sectionDto.sectionHeader, 'Section header');
        DceHtmlPolicy.assertSafeTemplateHtml(sectionDto.sectionFooter, 'Section footer');
        if (!String.isBlank(sectionDto.childObjectApiName)) {
            Schema.DescribeSObjectResult childDescribe = assertReadableObject(sectionDto.childObjectApiName);
            assertReadableField(childDescribe, sectionDto.parentLookupFieldApiName, 'parent lookup field');
            assertReadableField(childDescribe, sectionDto.sortFieldApiName, 'sort field');
        }
    }

    private static DceBuilderTemplateDTO toTemplateDto(Email_Template_Config__c template) {
        DceBuilderTemplateDTO dto = new DceBuilderTemplateDTO();
        dto.id = template.Id;
        dto.name = template.Name;
        dto.active = template.Active__c;
        dto.parentObjectApiName = template.Parent_Object_API_Name__c;
        dto.parentObjectLabel = getObjectLabel(template.Parent_Object_API_Name__c);
        dto.subjectTemplate = template.Subject_Template__c;
        DceTemplateContentService.ContentBundle content = DceTemplateContentService.loadContent(template);
        dto.bodyTemplate = content.bodyHtml;
        dto.headerContent = content.headerHtml;
        dto.footerContent = content.footerHtml;
        dto.header = content.headerHtml;
        dto.footer = content.footerHtml;
        dto.headerEditorMode = normalizeEditorMode(template.Header_Editor_Mode__c);
        dto.bodyEditorMode = normalizeEditorMode(template.Body_Editor_Mode__c);
        dto.footerEditorMode = normalizeEditorMode(template.Footer_Editor_Mode__c);
        dto.description = template.Description__c;
        dto.defaultFromEmail = template.Default_From_Email__c;
        dto.allowUserEditBeforeSend = template.Allow_User_Edit_Before_Send__c;
        dto.storeEmailHistory = template.Store_Email_History__c;
        dto.sections = loadSections(template.Id);
        dto.recipients = loadRecipients(template.Id, template.Parent_Object_API_Name__c);
        dto.postSendActions = deserializePostSendActions(template.Post_Send_Actions__c, template.Parent_Object_API_Name__c);
        return dto;
    }

    private static String serializePostSendActions(List<DceBuilderPostSendActionDTO> actions) {
        if (actions == null || actions.isEmpty()) {
            return null;
        }
        return JSON.serialize(actions);
    }

    private static List<DceBuilderPostSendActionDTO> deserializePostSendActions(String actionsJson, String parentObjectApiName) {
        if (String.isBlank(actionsJson)) {
            return new List<DceBuilderPostSendActionDTO>();
        }
        try {
            List<DceBuilderPostSendActionDTO> actions = (List<DceBuilderPostSendActionDTO>) JSON.deserialize(actionsJson, List<DceBuilderPostSendActionDTO>.class);
            for (DceBuilderPostSendActionDTO action : actions) {
                if (action != null && action.actionType == 'Update Field') {
                    action.fieldLabel = getFieldLabel(parentObjectApiName, action.fieldApiName);
                }
            }
            return actions;
        } catch (Exception e) {
            return new List<DceBuilderPostSendActionDTO>();
        }
    }

    private static List<DceBuilderSectionDTO> loadSections(Id templateId) {
        List<DceBuilderSectionDTO> dtos = new List<DceBuilderSectionDTO>();
        Map<Id, DceBuilderSectionDTO> byId = new Map<Id, DceBuilderSectionDTO>();
        for (Email_Template_Section__c section : [
            SELECT Id, Name, Section_Name__c, Section_Key__c, Active__c, Display_Order__c, Section_Type__c,
                Child_Object_API_Name__c, Parent_Lookup_Field_API_Name__c, Sort_Field_API_Name__c, Sort_Direction__c,
                Filter_Logic__c, Static_Content__c, Section_Header__c, Section_Footer__c, Repeat_Label__c,
                Include_Auto_Number__c, Auto_Number_Start__c
            FROM Email_Template_Section__c
            WHERE Email_Template_Config__c = :templateId
            WITH USER_MODE
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ]) {
            DceBuilderSectionDTO dto = new DceBuilderSectionDTO();
            dto.id = section.Id;
            dto.name = section.Name;
            dto.sectionName = section.Section_Name__c;
            dto.sectionKey = section.Section_Key__c;
            dto.active = section.Active__c;
            dto.displayOrder = integerValue(section.Display_Order__c);
            dto.sectionType = section.Section_Type__c;
            dto.childObjectApiName = section.Child_Object_API_Name__c;
            dto.childObjectLabel = getObjectLabel(section.Child_Object_API_Name__c);
            dto.parentLookupFieldApiName = section.Parent_Lookup_Field_API_Name__c;
            dto.parentLookupFieldLabel = getFieldLabel(section.Child_Object_API_Name__c, section.Parent_Lookup_Field_API_Name__c);
            dto.sortFieldApiName = section.Sort_Field_API_Name__c;
            dto.sortFieldLabel = getFieldLabel(section.Child_Object_API_Name__c, section.Sort_Field_API_Name__c);
            dto.sortDirection = section.Sort_Direction__c;
            dto.filterLogic = section.Filter_Logic__c;
            dto.staticContent = section.Static_Content__c;
            dto.sectionHeader = section.Section_Header__c;
            dto.sectionFooter = section.Section_Footer__c;
            dto.repeatLabel = section.Repeat_Label__c;
            dto.includeAutoNumber = section.Include_Auto_Number__c;
            dto.autoNumberStart = integerValue(section.Auto_Number_Start__c);
            dtos.add(dto);
            byId.put(section.Id, dto);
        }
        loadLines(byId);
        loadFields(byId);
        return dtos;
    }

    private static void loadLines(Map<Id, DceBuilderSectionDTO> sections) {
        if (sections.isEmpty()) return;
        for (Email_Template_Line__c line : [
            SELECT Id, Name, Email_Template_Section__c, Display_Order__c, Active__c, Line_Template__c, Display_Style__c, Render_Only_If_Not_Blank__c
            FROM Email_Template_Line__c
            WHERE Email_Template_Section__c IN :sections.keySet()
            WITH USER_MODE
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ]) {
            DceBuilderSectionDTO.DceBuilderLineDTO dto = new DceBuilderSectionDTO.DceBuilderLineDTO();
            dto.id = line.Id;
            dto.sectionId = line.Email_Template_Section__c;
            dto.name = line.Name;
            dto.displayOrder = integerValue(line.Display_Order__c);
            dto.active = line.Active__c;
            dto.lineTemplate = line.Line_Template__c;
            dto.displayStyle = line.Display_Style__c;
            dto.renderOnlyIfNotBlank = line.Render_Only_If_Not_Blank__c;
            sections.get(line.Email_Template_Section__c).lines.add(dto);
        }
    }

    private static void loadFields(Map<Id, DceBuilderSectionDTO> sections) {
        if (sections.isEmpty()) return;
        for (Email_Template_Field__c fieldConfig : [
            SELECT Id, Name, Email_Template_Section__c, Field_API_Name__c, Label_Override__c, Display_Order__c, Active__c,
                Show_Label__c, Display_Style__c, Is_Main_Title__c, Prefix_Text__c, Suffix_Text__c, Line_Break_After__c,
                Render_Only_If_Not_Blank__c, Table_Column_Width__c
            FROM Email_Template_Field__c
            WHERE Email_Template_Section__c IN :sections.keySet()
            WITH USER_MODE
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ]) {
            DceBuilderSectionDTO.DceBuilderColumnDTO dto = new DceBuilderSectionDTO.DceBuilderColumnDTO();
            dto.id = fieldConfig.Id;
            dto.sectionId = fieldConfig.Email_Template_Section__c;
            dto.name = fieldConfig.Name;
            dto.fieldApiName = fieldConfig.Field_API_Name__c;
            dto.fieldLabel = getFieldLabel(sections.get(fieldConfig.Email_Template_Section__c).childObjectApiName, fieldConfig.Field_API_Name__c);
            dto.labelOverride = fieldConfig.Label_Override__c;
            dto.displayOrder = integerValue(fieldConfig.Display_Order__c);
            dto.active = fieldConfig.Active__c;
            dto.showLabel = fieldConfig.Show_Label__c;
            dto.displayStyle = fieldConfig.Display_Style__c;
            dto.isMainTitle = fieldConfig.Is_Main_Title__c;
            dto.prefixText = fieldConfig.Prefix_Text__c;
            dto.suffixText = fieldConfig.Suffix_Text__c;
            dto.lineBreakAfter = fieldConfig.Line_Break_After__c;
            dto.renderOnlyIfNotBlank = fieldConfig.Render_Only_If_Not_Blank__c;
            dto.tableColumnWidth = fieldConfig.Table_Column_Width__c;
            sections.get(fieldConfig.Email_Template_Section__c).fields.add(dto);
        }
    }

    private static List<DceBuilderRecipientDTO> loadRecipients(Id templateId, String parentObjectApiName) {
        List<DceBuilderRecipientDTO> dtos = new List<DceBuilderRecipientDTO>();
        for (Email_Template_Recipient_Config__c recipient : [
            SELECT Id, Name, Active__c, Display_Order__c, Recipient_Source_Type__c, Recipient_Type__c,
                Source_Object_API_Name__c, Parent_Lookup_Field_API_Name__c, Name_Field_API_Name__c, Email_Field_API_Name__c,
                Filter_Logic__c, Default_Selected__c, Allow_Multiple__c, Required__c
            FROM Email_Template_Recipient_Config__c
            WHERE Email_Template_Config__c = :templateId
            WITH USER_MODE
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ]) {
            DceBuilderRecipientDTO dto = new DceBuilderRecipientDTO();
            dto.id = recipient.Id;
            dto.name = recipient.Name;
            dto.active = recipient.Active__c;
            dto.displayOrder = integerValue(recipient.Display_Order__c);
            dto.recipientSourceType = recipient.Recipient_Source_Type__c;
            dto.recipientType = recipient.Recipient_Type__c;
            dto.sourceObjectApiName = recipient.Source_Object_API_Name__c;
            String sourceObjectApiName = String.isBlank(recipient.Source_Object_API_Name__c) ? parentObjectApiName : recipient.Source_Object_API_Name__c;
            dto.sourceObjectLabel = getObjectLabel(sourceObjectApiName);
            dto.parentLookupFieldApiName = recipient.Parent_Lookup_Field_API_Name__c;
            dto.parentLookupFieldLabel = getFieldLabel(sourceObjectApiName, recipient.Parent_Lookup_Field_API_Name__c);
            dto.nameFieldApiName = recipient.Name_Field_API_Name__c;
            dto.nameFieldLabel = getFieldLabel(sourceObjectApiName, recipient.Name_Field_API_Name__c);
            dto.emailFieldApiName = recipient.Email_Field_API_Name__c;
            dto.emailFieldLabel = getFieldLabel(sourceObjectApiName, recipient.Email_Field_API_Name__c);
            dto.filterLogic = recipient.Filter_Logic__c;
            dto.defaultSelected = recipient.Default_Selected__c;
            dto.allowMultiple = recipient.Allow_Multiple__c;
            dto.required = recipient.Required__c;
            dtos.add(dto);
        }
        return dtos;
    }

    private static DceBuilderFieldDTO toFieldDto(Schema.DescribeFieldResult describe) {
        DceBuilderFieldDTO dto = new DceBuilderFieldDTO();
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
            throw new AuraHandledException('Invalid object API name.');
        }
        Schema.DescribeSObjectResult describe = Schema.getGlobalDescribe().get(objectApiName).getDescribe();
        if (!describe.isAccessible()) {
            throw new AuraHandledException('You do not have access to this object.');
        }
        return describe;
    }

    private static void assertReadableField(String objectApiName, String fieldApiName, String label) {
        if (String.isBlank(fieldApiName)) return;
        assertReadableField(assertReadableObject(objectApiName), fieldApiName, label);
    }

    private static void assertReadableField(
        Schema.DescribeSObjectResult objectDescribe,
        String fieldApiName,
        String label
    ) {
        if (String.isBlank(fieldApiName)) return;
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        if (!fieldMap.containsKey(fieldApiName) || !fieldMap.get(fieldApiName).getDescribe().isAccessible()) {
            throw new AuraHandledException('Invalid or inaccessible ' + label + ': ' + fieldApiName + '.');
        }
    }

    private static String normalizeEditorMode(String editorMode) {
        return editorMode == EDITOR_MODE_HTML_SOURCE ? EDITOR_MODE_HTML_SOURCE : EDITOR_MODE_VISUAL;
    }

    private static void deleteLines(List<Id> ids, Id templateId) {
        if (ids == null || ids.isEmpty()) return;
        List<Email_Template_Line__c> recordsToDelete = [
            SELECT Id
            FROM Email_Template_Line__c
            WHERE Id IN :ids
            AND Email_Template_Section__r.Email_Template_Config__c = :templateId
            WITH USER_MODE
        ];
        if (!recordsToDelete.isEmpty()) delete as user recordsToDelete;
    }

    private static void deleteFields(List<Id> ids, Id templateId) {
        if (ids == null || ids.isEmpty()) return;
        List<Email_Template_Field__c> recordsToDelete = [
            SELECT Id
            FROM Email_Template_Field__c
            WHERE Id IN :ids
            AND Email_Template_Section__r.Email_Template_Config__c = :templateId
            WITH USER_MODE
        ];
        if (!recordsToDelete.isEmpty()) delete as user recordsToDelete;
    }

    private static void deleteRecipients(List<Id> ids, Id templateId) {
        if (ids == null || ids.isEmpty()) return;
        List<Email_Template_Recipient_Config__c> recordsToDelete = [
            SELECT Id
            FROM Email_Template_Recipient_Config__c
            WHERE Id IN :ids
            AND Email_Template_Config__c = :templateId
            WITH USER_MODE
        ];
        if (!recordsToDelete.isEmpty()) delete as user recordsToDelete;
    }

    private static void deleteSections(List<Id> ids, Id templateId) {
        if (ids == null || ids.isEmpty()) return;
        List<Email_Template_Section__c> recordsToDelete = [
            SELECT Id
            FROM Email_Template_Section__c
            WHERE Id IN :ids
            AND Email_Template_Config__c = :templateId
            WITH USER_MODE
        ];
        if (!recordsToDelete.isEmpty()) delete as user recordsToDelete;
    }

    private static void assertCanSaveGraph(DceBuilderTemplateDTO dto) {
        if (dto.id == null) {
            assertObjectCreateable(Email_Template_Config__c.SObjectType);
        } else {
            assertObjectUpdateable(Email_Template_Config__c.SObjectType);
        }
        assertObjectCreateable(Email_Template_Section__c.SObjectType);
        assertObjectUpdateable(Email_Template_Section__c.SObjectType);
        assertObjectCreateable(Email_Template_Line__c.SObjectType);
        assertObjectUpdateable(Email_Template_Line__c.SObjectType);
        assertObjectCreateable(Email_Template_Field__c.SObjectType);
        assertObjectUpdateable(Email_Template_Field__c.SObjectType);
        assertObjectCreateable(Email_Template_Recipient_Config__c.SObjectType);
        assertObjectUpdateable(Email_Template_Recipient_Config__c.SObjectType);
        assertObjectCreateable(Email_Template_Content_Chunk__c.SObjectType);
        assertObjectDeleteable(Email_Template_Content_Chunk__c.SObjectType);
        if (hasDeletes(dto)) {
            assertObjectDeleteable(Email_Template_Section__c.SObjectType);
            assertObjectDeleteable(Email_Template_Line__c.SObjectType);
            assertObjectDeleteable(Email_Template_Field__c.SObjectType);
            assertObjectDeleteable(Email_Template_Recipient_Config__c.SObjectType);
        }
    }

    private static Boolean hasDeletes(DceBuilderTemplateDTO dto) {
        return (dto.deletedSectionIds != null && !dto.deletedSectionIds.isEmpty())
            || (dto.deletedLineIds != null && !dto.deletedLineIds.isEmpty())
            || (dto.deletedFieldIds != null && !dto.deletedFieldIds.isEmpty())
            || (dto.deletedRecipientIds != null && !dto.deletedRecipientIds.isEmpty());
    }

    private static void assertObjectReadable(Schema.SObjectType objectType) {
        if (!objectType.getDescribe().isAccessible()) {
            throw new AuraHandledException('You do not have access to email template configuration.');
        }
    }

    private static void assertObjectCreateable(Schema.SObjectType objectType) {
        if (!objectType.getDescribe().isCreateable()) {
            throw new AuraHandledException('You do not have permission to create email template configuration.');
        }
    }

    private static void assertObjectUpdateable(Schema.SObjectType objectType) {
        if (!objectType.getDescribe().isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update email template configuration.');
        }
    }

    private static void assertObjectDeleteable(Schema.SObjectType objectType) {
        if (!objectType.getDescribe().isDeletable()) {
            throw new AuraHandledException('You do not have permission to delete email template configuration.');
        }
    }

    private static String getObjectLabel(String objectApiName) {
        if (String.isBlank(objectApiName) || !Schema.getGlobalDescribe().containsKey(objectApiName)) {
            return objectApiName;
        }
        return Schema.getGlobalDescribe().get(objectApiName).getDescribe().getLabel();
    }

    private static String firstNonNull(String preferredValue, String fallbackValue) {
        return preferredValue != null ? preferredValue : fallbackValue;
    }

    private static String buildOrgWideEmailLabel(String displayName, String address) {
        if (String.isBlank(displayName)) {
            return address;
        }
        if (String.isBlank(address)) {
            return displayName;
        }
        return displayName + ' <' + address + '>';
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

    private static Integer integerValue(Decimal value) {
        return value == null ? null : value.intValue();
    }

    private class ObjectLabelComparator implements Comparator<DceBuilderObjectDTO> {
        public Integer compare(DceBuilderObjectDTO a, DceBuilderObjectDTO b) {
            return a.label.compareTo(b.label);
        }
    }

    private class FieldLabelComparator implements Comparator<DceBuilderFieldDTO> {
        public Integer compare(DceBuilderFieldDTO a, DceBuilderFieldDTO b) {
            return a.label.compareTo(b.label);
        }
    }
}
