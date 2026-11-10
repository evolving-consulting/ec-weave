@IsTest
private class GenericEmailSendServiceTest {
    @IsTest
    static void sendsValidEmailAndCreatesHistoryWhenEnabled() {
        Account account = DceTestDataFactory.createAccount();
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Store_Email_History__c = true;
        update template;

        GenericEmailSendRequest request = validRequest(template.Id, account.Id);

        Test.startTest();
        GenericEmailSendService.sendEmail(request);
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id, WhatId, Subject, Status
            FROM Task
            WHERE WhatId = :account.Id
        ];
        System.assertEquals(1, tasks.size());
        System.assert(tasks[0].Subject.startsWith('Email:'));
        System.assertEquals('Completed', tasks[0].Status);
    }

    @IsTest
    static void doesNotCreateHistoryWhenDisabled() {
        Account account = DceTestDataFactory.createAccount();
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Store_Email_History__c = false;
        update template;

        GenericEmailSendRequest request = validRequest(template.Id, account.Id);
        request.storeHistory = false;

        Test.startTest();
        GenericEmailSendService.sendEmail(request);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :account.Id]);
    }

    @IsTest
    static void sendsValidEmailWithoutTemplateIdWhenDraftIsProvided() {
        Account account = DceTestDataFactory.createAccount();

        GenericEmailSendRequest request = validRequest(null, account.Id);
        request.storeHistory = false;

        Test.startTest();
        GenericEmailSendService.sendEmail(request);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :account.Id]);
    }

    @IsTest
    static void validatesRequiredRequestFieldsAndEmails() {
        Account account = DceTestDataFactory.createAccount();
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');

        assertSendException(null);

        // Explicitly test that recordId is still required
        GenericEmailSendRequest missingRecordId = validRequest(template.Id, null);
        assertSendException(missingRecordId);

        GenericEmailSendRequest missingTo = validRequest(template.Id, account.Id);
        missingTo.toRecipients = new List<RecipientInputDTO>();
        assertSendException(missingTo);

        GenericEmailSendRequest invalidEmail = validRequest(template.Id, account.Id);
        invalidEmail.toRecipients = new List<RecipientInputDTO>{ new RecipientInputDTO('Bad', 'test@', 'To') };
        assertSendException(invalidEmail);

        GenericEmailSendRequest blankSubject = validRequest(template.Id, account.Id);
        blankSubject.subject = '';
        assertSendException(blankSubject);

        GenericEmailSendRequest blankBody = validRequest(template.Id, account.Id);
        blankBody.htmlBody = '';
        assertSendException(blankBody);
    }

    @IsTest
    static void duplicateEmailsAreHandledSafely() {
        Account account = DceTestDataFactory.createAccount();
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Store_Email_History__c = false;
        update template;

        GenericEmailSendRequest request = validRequest(template.Id, account.Id);
        request.toRecipients.add(new RecipientInputDTO('Duplicate To', 'TO@example.com', 'To'));
        request.ccRecipients = new List<RecipientInputDTO>{ new RecipientInputDTO('Also To', 'to@example.com', 'CC') };
        request.bccRecipients = new List<RecipientInputDTO>{ new RecipientInputDTO('Also To Again', 'to@example.com', 'BCC') };

        Test.startTest();
        GenericEmailSendService.sendEmail(request);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :account.Id]);
    }

    @IsTest
    static void sendsEmailWithSelectedAttachments() {
        Account account = DceTestDataFactory.createAccount();
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Store_Email_History__c = false;
        update template;

        GenericEmailSendRequest request = validRequest(template.Id, account.Id);
        request.attachmentContentDocumentIds = new List<Id>{ createFile(account.Id, 'Contract') };

        Test.startTest();
        GenericEmailSendService.sendEmail(request);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :account.Id]);
    }

    @IsTest
    static void executesPostSendActionsAfterSuccessfulSend() {
        Account account = DceTestDataFactory.createAccount();
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Store_Email_History__c = false;
        DceBuilderPostSendActionDTO action = new DceBuilderPostSendActionDTO();
        action.active = true;
        action.runOrder = 1;
        action.actionType = 'Update Field';
        action.fieldApiName = 'Description';
        action.valueType = 'Static';
        action.value = 'Sent by DCE';
        template.Post_Send_Actions__c = JSON.serialize(new List<DceBuilderPostSendActionDTO>{ action });
        update template;

        Test.startTest();
        GenericEmailSendService.sendEmail(validRequest(template.Id, account.Id));
        Test.stopTest();

        Account updatedAccount = [
            SELECT Description
            FROM Account
            WHERE Id = :account.Id
        ];
        System.assertEquals('Sent by DCE', updatedAccount.Description);
    }

    @IsTest
    static void ignoresForgedDraftWhenTemplateDisallowsEditing() {
        Account account = DceTestDataFactory.createAccount();
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Allow_User_Edit_Before_Send__c = false;
        template.Subject_Template__c = 'Approved subject for {{Name}}';
        template.Body_Template__c = '<p>Approved body for {{Name}}</p>';
        template.Store_Email_History__c = true;
        update template;

        GenericEmailSendRequest request = validRequest(template.Id, account.Id);
        request.subject = 'Forged subject';
        request.htmlBody = '<p>Forged body</p>';

        Test.startTest();
        DceEmailSendResultDTO result = GenericEmailSendService.sendEmail(request);
        Test.stopTest();

        Task history = [
            SELECT Subject, Description
            FROM Task
            WHERE WhatId = :account.Id
            LIMIT 1
        ];
        Assert.isTrue(result.success);
        Assert.isTrue(history.Subject.contains('Approved subject'));
        Assert.isTrue(history.Description.contains('Approved body'));
        Assert.isFalse(history.Description.contains('Forged body'));
    }

    private static GenericEmailSendRequest validRequest(Id templateId, Id recordId) {
        GenericEmailSendRequest request = new GenericEmailSendRequest();
        request.templateId = templateId;
        request.recordId = recordId;
        request.subject = 'Test Subject';
        request.htmlBody = '<p>Hello</p>';
        request.toRecipients = new List<RecipientInputDTO>{ new RecipientInputDTO('To', 'to@example.com', 'To') };
        request.ccRecipients = new List<RecipientInputDTO>();
        request.bccRecipients = new List<RecipientInputDTO>();
        request.attachmentContentDocumentIds = new List<Id>();
        request.storeHistory = null;
        return request;
    }

    private static void assertSendException(GenericEmailSendRequest request) {
        Boolean thrown = false;
        try {
            GenericEmailSendService.sendEmail(request);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Expected AuraHandledException.');
    }

    private static Id createFile(Id parentId, String title) {
        ContentVersion version = new ContentVersion();
        version.Title = title;
        version.PathOnClient = title + '.txt';
        version.VersionData = Blob.valueOf('Sample attachment');
        version.FirstPublishLocationId = parentId;
        insert version;

        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;
    }
}
