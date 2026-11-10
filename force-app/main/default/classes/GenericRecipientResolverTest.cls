@IsTest
private class GenericRecipientResolverTest {
    @IsTest
    static void resolvesParentFieldRecipients() {
        Account account = DceTestDataFactory.createAccount();
        Contact contact = DceTestDataFactory.createContact(account.Id);
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Contact');
        DceTestDataFactory.createParentFieldRecipientConfig(template.Id);

        List<RecipientOptionDTO> options = GenericRecipientResolver.getRecipientOptions(template.Id, contact.Id);

        System.assertEquals(1, options.size());
        System.assertEquals('ada.smith@example.com', options[0].email);
        System.assertEquals(true, options[0].selected);
        System.assertEquals('To', options[0].recipientType);
    }

    @IsTest
    static void resolvesRelatedAndManualRecipients() {
        Account account = DceTestDataFactory.createAccount();
        DceTestDataFactory.createContact(account.Id);
        DceTestDataFactory.createContact(account.Id, 'Alan', 'Jones', 'alan.jones@example.com');
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        DceTestDataFactory.createRelatedRecordRecipientConfig(template.Id);
        DceTestDataFactory.createManualRecipientConfig(template.Id);

        List<RecipientOptionDTO> options = GenericRecipientResolver.getRecipientOptions(template.Id, account.Id);

        System.assertEquals(2, options.size());
        System.assertEquals('ada.smith@example.com', options[0].email);
        System.assertEquals('Manual', options[1].sourceType);
        System.assert(String.valueOf(options[1].id).startsWith('manual-'));
    }

    @IsTest
    static void skipsBlankEmailsAndReturnsEmptyWhenNoRecipients() {
        Account account = DceTestDataFactory.createAccount();
        DceTestDataFactory.createContact(account.Id, 'Blank', 'Smith', null);
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        DceTestDataFactory.createRelatedRecordRecipientConfig(template.Id);

        List<RecipientOptionDTO> options = GenericRecipientResolver.getRecipientOptions(template.Id, account.Id);

        System.assertEquals(0, options.size());

        Email_Template_Config__c noConfigTemplate = DceTestDataFactory.createTemplate('Account');
        System.assertEquals(0, GenericRecipientResolver.getRecipientOptions(noConfigTemplate.Id, account.Id).size());
    }

    @IsTest
    static void throwsForMisconfiguredRelatedRecipient() {
        Account account = DceTestDataFactory.createAccount();
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        Email_Template_Recipient_Config__c config = DceTestDataFactory.createRelatedRecordRecipientConfig(template.Id);
        config.Source_Object_API_Name__c = null;
        update config;

        Boolean thrown = false;
        try {
            GenericRecipientResolver.getRecipientOptions(template.Id, account.Id);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Expected AuraHandledException.');
    }
}
