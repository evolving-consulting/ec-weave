@IsTest
private class GenericEmailTemplateControllerTest {
    @IsTest
    static void getsAvailableTemplatesAndDetails() {
        Email_Template_Config__c accountTemplate = DceTestDataFactory.createTemplate('Account');
        Email_Template_Config__c inactive = DceTestDataFactory.createTemplate('Account');
        inactive.Active__c = false;
        update inactive;
        DceTestDataFactory.createTemplate('Contact');

        List<GenericEmailTemplateDTO> templates = GenericEmailTemplateController.getAvailableTemplates('Account');

        System.assertEquals(1, templates.size());
        System.assertEquals(accountTemplate.Id, templates[0].id);

        GenericEmailTemplateDTO details = GenericEmailTemplateController.getTemplateDetails(accountTemplate.Id);
        System.assertEquals(accountTemplate.Id, details.id);
        System.assertEquals('Account', details.parentObjectApiName);
    }

    @IsTest
    static void delegatesRecipientRenderAndSend() {
        Account account = DceTestDataFactory.createAccount();
        DceTestDataFactory.createContact(account.Id);
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Body_Template__c = 'Hello {{Name}} {{Section.Contacts}}';
        template.Store_Email_History__c = false;
        update template;

        DceTestDataFactory.createRelatedRecordRecipientConfig(template.Id);
        Email_Template_Section__c section = DceTestDataFactory.createTextBlockSection(template.Id, 1);
        DceTestDataFactory.createLine(section.Id, 1, 'Contact: {{Name}} {{Email}}');

        List<RecipientOptionDTO> recipients = GenericEmailTemplateController.getRecipientOptions(template.Id, account.Id);
        System.assertEquals(1, recipients.size());

        RenderedEmailDTO rendered = GenericEmailTemplateController.renderEmail(template.Id, account.Id);
        System.assert(rendered.subject.contains(account.Name));
        System.assert(rendered.htmlBody.contains('ada.smith@example.com'), rendered.htmlBody);

        GenericEmailSendRequest request = new GenericEmailSendRequest();
        request.templateId = template.Id;
        request.recordId = account.Id;
        request.subject = rendered.subject;
        request.htmlBody = rendered.htmlBody;
        request.toRecipients = new List<RecipientInputDTO>{ new RecipientInputDTO('Ada', 'ada.smith@example.com', 'To') };
        request.ccRecipients = new List<RecipientInputDTO>();
        request.bccRecipients = new List<RecipientInputDTO>();
        request.storeHistory = false;

        Test.startTest();
        GenericEmailTemplateController.sendEmail(request);
        Test.stopTest();
    }

    @IsTest
    static void getsObjectApiNameFromRecordId() {
        Account account = DceTestDataFactory.createAccount();

        String objectApiName = GenericEmailTemplateController.getObjectApiNameFromRecordId(account.Id);

        System.assertEquals('Account', objectApiName);
    }

    @IsTest
    static void getsRecordSummary() {
        Account account = DceTestDataFactory.createAccount();

        Map<String, String> summary = GenericEmailTemplateController.getRecordSummary(account.Id);

        System.assertEquals('Account', summary.get('objectApiName'));
        System.assertEquals('Account', summary.get('objectLabel'));
        System.assertEquals(account.Name, summary.get('recordName'));
    }

    @IsTest
    static void getsRelatedAttachments() {
        Account account = DceTestDataFactory.createAccount();
        createFile(account.Id, 'Proposal');

        List<DceEmailAttachmentDTO> attachments = GenericEmailTemplateController.getRelatedAttachments(account.Id);

        System.assertEquals(1, attachments.size());
        System.assertEquals('Proposal', attachments[0].title);
        System.assertEquals(true, attachments[0].selected);
        System.assertEquals('Related', attachments[0].source);
        System.assertNotEquals(null, attachments[0].contentDocumentId);
        System.assertNotEquals(null, attachments[0].contentVersionId);
    }

    @IsTest
    static void throwsForInvalidInputs() {
        assertControllerException(new AvailableTemplatesCall('Not_A_Real_Object__c'));
        assertControllerException(new TemplateDetailsCall(null));
        assertControllerException(new ObjectApiNameFromRecordIdCall(null));
    }

    private interface ControllerRunnable {
        void run();
    }

    private class AvailableTemplatesCall implements ControllerRunnable {
        private String objectApiName;
        AvailableTemplatesCall(String objectApiName) {
            this.objectApiName = objectApiName;
        }
        public void run() {
            GenericEmailTemplateController.getAvailableTemplates(objectApiName);
        }
    }

    private class TemplateDetailsCall implements ControllerRunnable {
        private Id templateId;
        TemplateDetailsCall(Id templateId) {
            this.templateId = templateId;
        }
        public void run() {
            GenericEmailTemplateController.getTemplateDetails(templateId);
        }
    }

    private class ObjectApiNameFromRecordIdCall implements ControllerRunnable {
        private Id recordId;
        ObjectApiNameFromRecordIdCall(Id recordId) {
            this.recordId = recordId;
        }
        public void run() {
            GenericEmailTemplateController.getObjectApiNameFromRecordId(recordId);
        }
    }

    private static void assertControllerException(ControllerRunnable runnable) {
        Boolean thrown = false;
        try {
            runnable.run();
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
