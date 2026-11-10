@IsTest
private class DceTemplateBuilderControllerTest {
    @IsTest
    static void loadsDescribeMetadataAndDtoConstructors() {
        DceTemplateSecurityService.enableManagementForTest();
        Test.startTest();
        List<DceBuilderObjectDTO> objects = DceTemplateBuilderController.getAvailableObjects();
        List<DceBuilderFieldDTO> accountFields = DceTemplateBuilderController.getFieldsForObject('Account');
        List<DceBuilderFieldDTO> relationshipFields = DceTemplateBuilderController.getRelationshipFields('Contact');
        List<DceBuilderFieldDTO> contactLookups = DceTemplateBuilderController.getLookupFieldsForChildObject('Contact', 'Account');
        DceBuilderTemplateDTO emptyTemplate = DceTemplateBuilderController.loadTemplate(null);
        Test.stopTest();

        System.assert(!objects.isEmpty(), 'Expected available objects.');
        System.assert(containsObject(objects, 'Account'), 'Expected Account to be available.');
        System.assert(containsField(accountFields, 'Name'), 'Expected Account.Name field metadata.');
        System.assert(!relationshipFields.isEmpty(), 'Expected relationship field metadata.');
        System.assert(containsField(contactLookups, 'AccountId'), 'Expected Contact.AccountId lookup metadata.');
        System.assertNotEquals(null, emptyTemplate.sections, 'Template DTO constructor should initialize sections.');
        System.assertNotEquals(null, emptyTemplate.recipients, 'Template DTO constructor should initialize recipients.');

        DceBuilderObjectDTO objectDto = new DceBuilderObjectDTO('Label', 'ApiName__c', 'Labels');
        System.assertEquals('Label', objectDto.label);

        DceBuilderFieldDTO fieldDto = new DceBuilderFieldDTO();
        System.assertNotEquals(null, fieldDto.referenceTo);

        DceBuilderSectionDTO sectionDto = new DceBuilderSectionDTO();
        System.assertNotEquals(null, sectionDto.lines);
        System.assertNotEquals(null, sectionDto.fields);
    }

    @IsTest
    static void savesLoadsPreviewsAndDeletesBuilderTemplateGraph() {
        DceTemplateSecurityService.enableManagementForTest();
        Account account = DceTestDataFactory.createAccount();
        DceTestDataFactory.createContact(account.Id, 'Ada', 'Smith', 'ada.smith@example.com');

        DceBuilderTemplateDTO dto = buildFullTemplateDto();

        Test.startTest();
        DceBuilderTemplateDTO saved = DceTemplateBuilderController.saveTemplate(dto);
        DceBuilderTemplateDTO loaded = DceTemplateBuilderController.loadTemplate(saved.id);
        List<DceBuilderTemplateSummaryDTO> summaries = DceTemplateBuilderController.getTemplates();
        RenderedEmailDTO preview = DceTemplateBuilderController.previewTemplate(saved.id, account.Id);
        Test.stopTest();

        System.assertNotEquals(null, saved.id, 'Expected saved template id.');
        System.assertEquals('Builder Coverage Template', loaded.name);
        System.assertEquals('<p>Header {{Name}}</p>', loaded.header, 'Expected loaded header value.');
        System.assertEquals('<p>Footer {{Owner.Name}}</p>', loaded.footer, 'Expected loaded footer value.');
        System.assertEquals('<p>Header {{Name}}</p>', loaded.headerContent, 'Expected loaded headerContent value.');
        System.assertEquals('<p>Footer {{Owner.Name}}</p>', loaded.footerContent, 'Expected loaded footerContent value.');
        System.assertEquals(3, loaded.sections.size(), 'Expected static, text block, and table sections.');
        System.assertEquals(2, loaded.recipients.size(), 'Expected related and manual recipient configs.');
        System.assert(containsTemplateSummary(summaries, saved.id), 'Expected saved template in selector summaries.');
        System.assert(preview.subject.contains(account.Name), 'Expected rendered preview subject.');
        System.assert(preview.htmlBody.contains('Header'), 'Expected rendered preview header.');
        System.assert(preview.htmlBody.contains('Static intro'), 'Expected static section body.');
        System.assert(preview.htmlBody.contains('Footer'), 'Expected rendered preview footer.');

        Id lineToDelete = findFirstLineId(loaded);
        Id fieldToDelete = findFirstFieldId(loaded);
        Id recipientToDelete = loaded.recipients[0].id;
        Id sectionToDelete = loaded.sections[0].id;

        loaded.name = 'Builder Coverage Template Updated';
        loaded.header = '<p>Updated Header</p>';
        loaded.headerContent = '<p>Updated Header</p>';
        loaded.footer = '<p>Updated Footer</p>';
        loaded.footerContent = '<p>Updated Footer</p>';
        loaded.active = true;
        loaded.deletedLineIds.add(lineToDelete);
        loaded.deletedFieldIds.add(fieldToDelete);
        loaded.deletedRecipientIds.add(recipientToDelete);
        loaded.deletedSectionIds.add(sectionToDelete);
        removeLineFromSections(loaded.sections, lineToDelete);
        removeFieldFromSections(loaded.sections, fieldToDelete);
        addReplacementLine(loaded.sections);
        addReplacementField(loaded.sections);
        loaded.sections = removeSection(loaded.sections, sectionToDelete);
        loaded.recipients = removeRecipient(loaded.recipients, recipientToDelete);

        DceBuilderTemplateDTO updated = DceTemplateBuilderService.saveTemplate(loaded);

        System.assertEquals('Builder Coverage Template Updated', updated.name);
        System.assertEquals('<p>Updated Header</p>', updated.header, 'Expected updated header value.');
        System.assertEquals('<p>Updated Footer</p>', updated.footer, 'Expected updated footer value.');
        System.assertEquals(2, updated.sections.size(), 'Expected one section removed.');
        System.assertEquals(1, updated.recipients.size(), 'Expected one recipient removed.');
        System.assertEquals(0, [SELECT count() FROM Email_Template_Line__c WHERE Id = :lineToDelete]);
        System.assertEquals(0, [SELECT count() FROM Email_Template_Field__c WHERE Id = :fieldToDelete]);
        System.assertEquals(0, [SELECT count() FROM Email_Template_Recipient_Config__c WHERE Id = :recipientToDelete]);
        System.assertEquals(0, [SELECT count() FROM Email_Template_Section__c WHERE Id = :sectionToDelete]);
    }

    @IsTest
    static void validatesBuilderMisconfiguration() {
        DceTemplateSecurityService.enableManagementForTest();
        Boolean thrown = false;
        try {
            DceTemplateBuilderController.saveTemplate(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Null template should fail.');

        DceBuilderTemplateDTO missingName = buildFullTemplateDto();
        missingName.name = null;
        thrown = false;
        try {
            DceTemplateBuilderController.saveTemplate(missingName);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Missing template name should fail.');

        DceBuilderTemplateDTO missingParent = buildFullTemplateDto();
        missingParent.parentObjectApiName = null;
        thrown = false;
        try {
            DceTemplateBuilderController.saveTemplate(missingParent);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Missing parent object should fail.');

        DceBuilderTemplateDTO missingTableColumn = buildFullTemplateDto();
        missingTableColumn.sections[2].fields.clear();
        thrown = false;
        try {
            DceTemplateBuilderController.saveTemplate(missingTableColumn);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Table without columns should fail.');

        DceBuilderTemplateDTO missingRecipientEmail = buildFullTemplateDto();
        missingRecipientEmail.recipients[0].emailFieldApiName = null;
        thrown = false;
        try {
            DceTemplateBuilderController.saveTemplate(missingRecipientEmail);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Recipient without email field should fail.');

        thrown = false;
        try {
            DceTemplateBuilderController.getFieldsForObject('NotARealObject__c');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Invalid object should fail.');

        thrown = false;
        try {
            DceTemplateBuilderController.previewTemplate(null, DceTestDataFactory.createAccount().Id);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Unsaved preview should fail.');
    }

    private static DceBuilderTemplateDTO buildFullTemplateDto() {
        DceBuilderTemplateDTO dto = new DceBuilderTemplateDTO();
        dto.name = 'Builder Coverage Template';
        dto.active = true;
        dto.parentObjectApiName = 'Account';
        dto.subjectTemplate = 'Builder subject {{Name}}';
        dto.bodyTemplate = 'Hello {{Name}}<br/>{{Section.StaticIntro}}{{Section.ContactLines}}{{Section.ContactTable}}';
        dto.header = '<p>Header {{Name}}</p>';
        dto.headerContent = '<p>Header {{Name}}</p>';
        dto.footer = '<p>Footer {{Owner.Name}}</p>';
        dto.footerContent = '<p>Footer {{Owner.Name}}</p>';
        dto.description = 'Builder test template';
        dto.allowUserEditBeforeSend = true;
        dto.storeEmailHistory = true;

        DceBuilderSectionDTO staticSection = new DceBuilderSectionDTO();
        staticSection.name = 'Static Intro';
        staticSection.sectionName = 'Static Intro';
        staticSection.sectionKey = 'StaticIntro';
        staticSection.active = true;
        staticSection.displayOrder = 1;
        staticSection.sectionType = 'Static Text';
        staticSection.staticContent = 'Static intro for {{Name}}';
        dto.sections.add(staticSection);

        DceBuilderSectionDTO textBlock = new DceBuilderSectionDTO();
        textBlock.name = 'Contact Lines';
        textBlock.sectionName = 'Contact Lines';
        textBlock.sectionKey = 'ContactLines';
        textBlock.active = true;
        textBlock.displayOrder = 2;
        textBlock.sectionType = 'Text Block';
        textBlock.childObjectApiName = 'Contact';
        textBlock.parentLookupFieldApiName = 'AccountId';
        textBlock.sortFieldApiName = 'LastName';
        textBlock.sortDirection = 'ASC';
        textBlock.filterLogic = 'LastName = \'Smith\'';
        textBlock.repeatLabel = 'Contact';
        textBlock.includeAutoNumber = true;
        textBlock.autoNumberStart = 1;
        DceBuilderSectionDTO.DceBuilderLineDTO line = new DceBuilderSectionDTO.DceBuilderLineDTO();
        line.name = 'Contact Line';
        line.displayOrder = 1;
        line.active = true;
        line.lineTemplate = 'Contact: {{FirstName}} {{LastName}} - {{Email}}';
        line.displayStyle = 'Normal';
        line.renderOnlyIfNotBlank = false;
        textBlock.lines.add(line);
        dto.sections.add(textBlock);

        DceBuilderSectionDTO table = new DceBuilderSectionDTO();
        table.name = 'Contact Table';
        table.sectionName = 'Contact Table';
        table.sectionKey = 'ContactTable';
        table.active = true;
        table.displayOrder = 3;
        table.sectionType = 'Table';
        table.childObjectApiName = 'Contact';
        table.parentLookupFieldApiName = 'AccountId';
        table.sortFieldApiName = 'LastName';
        table.sortDirection = 'ASC';
        DceBuilderSectionDTO.DceBuilderColumnDTO column = new DceBuilderSectionDTO.DceBuilderColumnDTO();
        column.name = 'Email Column';
        column.fieldApiName = 'Email';
        column.labelOverride = 'Email';
        column.displayOrder = 1;
        column.active = true;
        column.showLabel = true;
        column.displayStyle = 'Normal';
        column.renderOnlyIfNotBlank = true;
        column.tableColumnWidth = '40%';
        table.fields.add(column);
        dto.sections.add(table);

        DceBuilderRecipientDTO related = new DceBuilderRecipientDTO();
        related.name = 'Related Contacts';
        related.active = true;
        related.displayOrder = 1;
        related.recipientSourceType = 'Related Records';
        related.recipientType = 'To';
        related.sourceObjectApiName = 'Contact';
        related.parentLookupFieldApiName = 'AccountId';
        related.nameFieldApiName = 'Name';
        related.emailFieldApiName = 'Email';
        related.filterLogic = 'LastName = \'Smith\'';
        related.defaultSelected = true;
        related.allowMultiple = true;
        related.required = true;
        dto.recipients.add(related);

        DceBuilderRecipientDTO manual = new DceBuilderRecipientDTO();
        manual.name = 'Manual CC';
        manual.active = true;
        manual.displayOrder = 2;
        manual.recipientSourceType = 'Manual';
        manual.recipientType = 'CC';
        manual.defaultSelected = false;
        manual.allowMultiple = true;
        manual.required = false;
        dto.recipients.add(manual);

        return dto;
    }

    private static Boolean containsObject(List<DceBuilderObjectDTO> objects, String apiName) {
        for (DceBuilderObjectDTO objectDto : objects) {
            if (objectDto.apiName == apiName) {
                return true;
            }
        }
        return false;
    }

    private static Boolean containsField(List<DceBuilderFieldDTO> fields, String apiName) {
        for (DceBuilderFieldDTO fieldDto : fields) {
            if (fieldDto.apiName == apiName) {
                return true;
            }
        }
        return false;
    }

    private static Boolean containsTemplateSummary(List<DceBuilderTemplateSummaryDTO> summaries, Id templateId) {
        for (DceBuilderTemplateSummaryDTO summary : summaries) {
            if (summary.id == templateId) {
                return true;
            }
        }
        return false;
    }

    private static Id findFirstLineId(DceBuilderTemplateDTO dto) {
        for (DceBuilderSectionDTO sectionDto : dto.sections) {
            if (!sectionDto.lines.isEmpty()) {
                return sectionDto.lines[0].id;
            }
        }
        return null;
    }

    private static Id findFirstFieldId(DceBuilderTemplateDTO dto) {
        for (DceBuilderSectionDTO sectionDto : dto.sections) {
            if (!sectionDto.fields.isEmpty()) {
                return sectionDto.fields[0].id;
            }
        }
        return null;
    }

    private static List<DceBuilderSectionDTO> removeSection(List<DceBuilderSectionDTO> sections, Id sectionId) {
        List<DceBuilderSectionDTO> remaining = new List<DceBuilderSectionDTO>();
        for (DceBuilderSectionDTO sectionDto : sections) {
            if (sectionDto.id != sectionId) {
                remaining.add(sectionDto);
            }
        }
        return remaining;
    }

    private static void removeLineFromSections(List<DceBuilderSectionDTO> sections, Id lineId) {
        for (DceBuilderSectionDTO sectionDto : sections) {
            List<DceBuilderSectionDTO.DceBuilderLineDTO> remaining = new List<DceBuilderSectionDTO.DceBuilderLineDTO>();
            for (DceBuilderSectionDTO.DceBuilderLineDTO lineDto : sectionDto.lines) {
                if (lineDto.id != lineId) {
                    remaining.add(lineDto);
                }
            }
            sectionDto.lines = remaining;
        }
    }

    private static void removeFieldFromSections(List<DceBuilderSectionDTO> sections, Id fieldId) {
        for (DceBuilderSectionDTO sectionDto : sections) {
            List<DceBuilderSectionDTO.DceBuilderColumnDTO> remaining = new List<DceBuilderSectionDTO.DceBuilderColumnDTO>();
            for (DceBuilderSectionDTO.DceBuilderColumnDTO fieldDto : sectionDto.fields) {
                if (fieldDto.id != fieldId) {
                    remaining.add(fieldDto);
                }
            }
            sectionDto.fields = remaining;
        }
    }

    private static void addReplacementLine(List<DceBuilderSectionDTO> sections) {
        for (DceBuilderSectionDTO sectionDto : sections) {
            if (sectionDto.sectionType == 'Text Block') {
                DceBuilderSectionDTO.DceBuilderLineDTO line = new DceBuilderSectionDTO.DceBuilderLineDTO();
                line.name = 'Replacement Line';
                line.displayOrder = 2;
                line.active = true;
                line.lineTemplate = 'Replacement {{Email}}';
                line.displayStyle = 'Normal';
                line.renderOnlyIfNotBlank = false;
                sectionDto.lines.add(line);
            }
        }
    }

    private static void addReplacementField(List<DceBuilderSectionDTO> sections) {
        for (DceBuilderSectionDTO sectionDto : sections) {
            if (sectionDto.sectionType == 'Table') {
                DceBuilderSectionDTO.DceBuilderColumnDTO field = new DceBuilderSectionDTO.DceBuilderColumnDTO();
                field.name = 'Replacement Name';
                field.fieldApiName = 'Name';
                field.displayOrder = 2;
                field.active = true;
                field.showLabel = true;
                field.displayStyle = 'Normal';
                field.renderOnlyIfNotBlank = true;
                sectionDto.fields.add(field);
            }
        }
    }

    private static List<DceBuilderRecipientDTO> removeRecipient(List<DceBuilderRecipientDTO> recipients, Id recipientId) {
        List<DceBuilderRecipientDTO> remaining = new List<DceBuilderRecipientDTO>();
        for (DceBuilderRecipientDTO recipientDto : recipients) {
            if (recipientDto.id != recipientId) {
                remaining.add(recipientDto);
            }
        }
        return remaining;
    }

}
