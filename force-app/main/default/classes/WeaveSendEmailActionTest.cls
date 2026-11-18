@IsTest
private class WeaveSendEmailActionTest {

    // ── Test data helpers ─────────────────────────────────────────────────────

    private static Weave_Template_Config__c createActiveTemplate(String parentObject) {
        Weave_Template_Config__c t = new Weave_Template_Config__c(
            Name = 'Test Weave Template',
            Status__c = 'Active',
            Parent_Object_API_Name__c = parentObject,
            Subject_Template__c = 'Test Subject',
            Allow_User_Edit_Before_Send__c = true,
            Store_Email_History__c = false
        );
        insert t;
        return t;
    }

    private static void addBodyComponent(Id templateId) {
        insert new Weave_Template_Component__c(
            Weave_Template_Config__c = templateId,
            Component_Type__c = 'HTML Block',
            Region__c = 'Body',
            Display_Order__c = 1,
            HTML_Output__c = '<p>Automated email body.</p>'
        );
    }

    private static void addParentFieldRecipient(Id templateId, String emailField) {
        insert new Weave_Template_Recipient__c(
            Weave_Template_Config__c = templateId,
            Recipient_Source_Type__c = 'Parent Field',
            Recipient_Type__c = 'To',
            Name_Field_API_Name__c = 'Name',
            Email_Field_API_Name__c = emailField,
            Required__c = true,
            Active__c = true
        );
    }

    private static WeaveSendEmailAction.SendRequest buildRequest(Id templateId, Id recordId) {
        WeaveSendEmailAction.SendRequest req = new WeaveSendEmailAction.SendRequest();
        req.templateId = templateId;
        req.recordId   = recordId;
        return req;
    }

    // ── Tests ─────────────────────────────────────────────────────────────────

    @IsTest
    static void invalidTemplateId_returnsFalseWithErrorMessage() {
        Account acct = DceTestDataFactory.createAccount();

        WeaveSendEmailAction.SendRequest req = buildRequest(null, acct.Id);

        Test.startTest();
        List<WeaveSendEmailAction.SendResult> results =
            WeaveSendEmailAction.sendEmail(new List<WeaveSendEmailAction.SendRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result per request.');
        System.assertEquals(false, results[0].success, 'Null templateId should fail.');
        System.assertNotEquals(null, results[0].errorMessage, 'Error message should be set.');
    }

    @IsTest
    static void missingRecordId_returnsFalseWithErrorMessage() {
        Weave_Template_Config__c template = createActiveTemplate('Contact');

        WeaveSendEmailAction.SendRequest req = buildRequest(template.Id, null);

        Test.startTest();
        List<WeaveSendEmailAction.SendResult> results =
            WeaveSendEmailAction.sendEmail(new List<WeaveSendEmailAction.SendRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Null recordId should fail.');
        System.assertNotEquals(null, results[0].errorMessage, 'Error message should be set.');
    }

    @IsTest
    static void validContactAndTemplate_sendsSuccessfully() {
        Contact contact = new Contact(
            FirstName = 'Weave',
            LastName = 'Tester',
            Email = 'weave.tester@example.com'
        );
        insert contact;

        Weave_Template_Config__c template = createActiveTemplate('Contact');
        addBodyComponent(template.Id);
        addParentFieldRecipient(template.Id, 'Email');

        WeaveSendEmailAction.SendRequest req = buildRequest(template.Id, contact.Id);

        Test.startTest();
        List<WeaveSendEmailAction.SendResult> results =
            WeaveSendEmailAction.sendEmail(new List<WeaveSendEmailAction.SendRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, 'Valid send should succeed. Error: ' + results[0].errorMessage);
        System.assertEquals(null, results[0].errorMessage, 'No error message expected on success.');
    }

    @IsTest
    static void bulkRequests_processedIndependently() {
        Contact c1 = new Contact(FirstName = 'Alice', LastName = 'One', Email = 'alice@example.com');
        Contact c2 = new Contact(FirstName = 'Bob',   LastName = 'Two', Email = 'bob@example.com');
        insert new List<Contact>{ c1, c2 };

        Weave_Template_Config__c template = createActiveTemplate('Contact');
        addBodyComponent(template.Id);
        addParentFieldRecipient(template.Id, 'Email');

        List<WeaveSendEmailAction.SendRequest> requests = new List<WeaveSendEmailAction.SendRequest>{
            buildRequest(template.Id, c1.Id),
            buildRequest(template.Id, c2.Id)
        };

        Test.startTest();
        List<WeaveSendEmailAction.SendResult> results = WeaveSendEmailAction.sendEmail(requests);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should return a result for each request.');
        System.assertEquals(true, results[0].success, 'First request should succeed. Error: ' + results[0].errorMessage);
        System.assertEquals(true, results[1].success, 'Second request should succeed. Error: ' + results[1].errorMessage);
    }

    @IsTest
    static void templateWithNoRecipients_failsWithErrorMessage() {
        Contact contact = new Contact(
            FirstName = 'No',
            LastName = 'Recipients',
            Email = 'no.recipients@example.com'
        );
        insert contact;

        // Template with component but no recipient config
        Weave_Template_Config__c template = createActiveTemplate('Contact');
        addBodyComponent(template.Id);

        WeaveSendEmailAction.SendRequest req = buildRequest(template.Id, contact.Id);

        Test.startTest();
        List<WeaveSendEmailAction.SendResult> results =
            WeaveSendEmailAction.sendEmail(new List<WeaveSendEmailAction.SendRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'No To recipients should cause failure.');
        System.assertNotEquals(null, results[0].errorMessage);
    }
}
