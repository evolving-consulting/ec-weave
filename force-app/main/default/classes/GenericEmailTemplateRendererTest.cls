@IsTest
private class GenericEmailTemplateRendererTest {
    @IsTest
    static void rendersParentMergeFieldsStaticAndTextBlockLines() {
        Account account = DceTestDataFactory.createAccount();
        DceTestDataFactory.createContact(account.Id);
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Body_Template__c = 'Hello {{Name}}<br/>{{Section.Static1}}<br/>{{Section.Contacts}}';
        update template;

        DceTestDataFactory.createStaticSection(template.Id, 1);
        Email_Template_Section__c textSection = DceTestDataFactory.createTextBlockSection(template.Id, 2);
        DceTestDataFactory.createLine(textSection.Id, 1, 'Contact: {{FirstName}} {{LastName}} - {{Email}}');

        RenderedEmailDTO rendered = GenericEmailTemplateRenderer.renderEmail(template.Id, account.Id);

        System.assertEquals('Hello ' + account.Name, rendered.subject);
        System.assert(rendered.htmlBody.contains('Static content for ' + account.Name), rendered.htmlBody);
        System.assert(rendered.htmlBody.contains('Contact: Ada Smith - ada.smith@example.com'), rendered.htmlBody);
    }

    @IsTest
    static void rendersTextBlockFieldFallback() {
        Account account = DceTestDataFactory.createAccount();
        DceTestDataFactory.createContact(account.Id);
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Body_Template__c = '{{Section.Contacts}}';
        update template;

        Email_Template_Section__c textSection = DceTestDataFactory.createTextBlockSection(template.Id, 1);
        DceTestDataFactory.createField(textSection.Id, 1, 'FirstName');
        DceTestDataFactory.createField(textSection.Id, 2, 'Email');

        RenderedEmailDTO rendered = GenericEmailTemplateRenderer.renderEmail(template.Id, account.Id);

        System.assert(rendered.htmlBody.contains('First Name:'), rendered.htmlBody);
        System.assert(rendered.htmlBody.contains('ada.smith@example.com'), rendered.htmlBody);
    }

    @IsTest
    static void rendersUniversalSenderOwnerAndOrganizationAliases() {
        Account account = DceTestDataFactory.createAccount();
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Body_Template__c = '{{Sender.Email}}|{{Owner.Name}}|{{Organization.Name}}';
        update template;

        User currentUser = [
            SELECT Email, Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        Organization organization = [
            SELECT Name
            FROM Organization
            LIMIT 1
        ];

        RenderedEmailDTO rendered = GenericEmailTemplateRenderer.renderEmail(template.Id, account.Id);

        Assert.isTrue(rendered.htmlBody.contains(currentUser.Email), 'Sender email alias should render.');
        Assert.isTrue(rendered.htmlBody.contains(currentUser.Name), 'Owner name alias should render for the test owner.');
        Assert.isTrue(rendered.htmlBody.contains(organization.Name), 'Organization name alias should render.');
    }

    @IsTest
    static void rendersTableSection() {
        Account account = DceTestDataFactory.createAccount();
        DceTestDataFactory.createContact(account.Id);
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Body_Template__c = '{{Section.ContactsTable}}';
        update template;

        Email_Template_Section__c tableSection = DceTestDataFactory.createTableSection(template.Id, 1);
        DceTestDataFactory.createField(tableSection.Id, 1, 'FirstName');
        DceTestDataFactory.createField(tableSection.Id, 2, 'LastName');
        DceTestDataFactory.createField(tableSection.Id, 3, 'Email');

        RenderedEmailDTO rendered = GenericEmailTemplateRenderer.renderEmail(template.Id, account.Id);

        System.assert(rendered.htmlBody.contains('<table'), rendered.htmlBody);
        System.assert(rendered.htmlBody.contains('ada.smith@example.com'), rendered.htmlBody);
    }

    @IsTest
    static void escapesMergeValuesWhilePreservingTrustedTemplateHtml() {
        Account account = DceTestDataFactory.createAccount();
        account.Name = '<b>Untrusted Name</b>';
        update account;
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Body_Template__c = '<p class="greeting">Hello {{Name}}</p>';
        update template;

        RenderedEmailDTO rendered = GenericEmailTemplateRenderer.renderEmail(template.Id, account.Id);

        Assert.isTrue(rendered.htmlBody.contains('<p class="greeting">'));
        Assert.isTrue(rendered.htmlBody.contains('&lt;b&gt;Untrusted Name&lt;/b&gt;'));
        Assert.isFalse(rendered.htmlBody.contains('Hello <b>Untrusted Name</b>'));
    }

    @IsTest
    static void throwsForMissingInactiveAndMisconfiguredTemplates() {
        Account account = DceTestDataFactory.createAccount();

        assertAuraException(new RendererCall(null, account.Id));

        Email_Template_Config__c inactive = DceTestDataFactory.createTemplate('Account');
        inactive.Active__c = false;
        update inactive;
        assertAuraException(new RendererCall(inactive.Id, account.Id));

        Email_Template_Config__c badChild = DceTestDataFactory.createTemplate('Account');
        badChild.Body_Template__c = '{{Section.Contacts}}';
        update badChild;
        Email_Template_Section__c section = DceTestDataFactory.createTextBlockSection(badChild.Id, 1);
        section.Child_Object_API_Name__c = 'Not_A_Real_Object__c';
        update section;
        assertAuraException(new RendererCall(badChild.Id, account.Id));
    }

    private interface RendererRunnable {
        void run();
    }

    private class RendererCall implements RendererRunnable {
        private Id templateId;
        private Id recordId;
        RendererCall(Id templateId, Id recordId) {
            this.templateId = templateId;
            this.recordId = recordId;
        }
        public void run() {
            GenericEmailTemplateRenderer.renderEmail(templateId, recordId);
        }
    }

    private static void assertAuraException(RendererRunnable runnable) {
        Boolean thrown = false;
        try {
            runnable.run();
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Expected AuraHandledException.');
    }
}
