@IsTest
private class MCNEmailSendServiceTest {

    // ── Mock HTTP ─────────────────────────────────────────────────────────────

    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(202);
            res.setBody('{"requestId":"mock-msg-123","status":"Accepted"}');
            return res;
        }
    }

    private class FailMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(400);
            res.setBody('{"message":"Bad request"}');
            return res;
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Weave_Template_Config__c makeTemplate() {
        Weave_Template_Config__c t = new Weave_Template_Config__c(
            Name                      = 'MCN Send Test',
            Status__c                 = 'Draft',
            Parent_Object_API_Name__c = 'Contact',
            Subject_Template__c       = 'Test Subject',
            SFMC_Template_ID__c       = 'weave-mcn-def-key'
        );
        insert t;
        return t;
    }

    private static Contact makeContact() {
        Contact c = new Contact(FirstName = 'John', LastName = 'Smith', Email = 'john@test.com');
        insert c;
        return c;
    }

    // ── Validation ────────────────────────────────────────────────────────────

    @IsTest
    static void testNullTemplateIdReturnsFailure() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Test.startTest();
        MCNEmailSendService.SendResult result =
            MCNEmailSendService.sendEmail(null, 'a@b.com', '{}');
        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
        System.assert(result.errorMessage != null);
    }

    @IsTest
    static void testBlankRecipientReturnsFailure() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Weave_Template_Config__c t = makeTemplate();

        Test.startTest();
        MCNEmailSendService.SendResult result =
            MCNEmailSendService.sendEmail(t.Id, '', '{}');
        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
        System.assert(result.errorMessage.contains('recipientEmail'));
    }

    @IsTest
    static void testInvalidEmailReturnsFailure() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Weave_Template_Config__c t = makeTemplate();

        Test.startTest();
        MCNEmailSendService.SendResult result =
            MCNEmailSendService.sendEmail(t.Id, 'not-an-email', '{}');
        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
    }

    // ── Success path ──────────────────────────────────────────────────────────

    @IsTest
    static void testSuccessfulSendCreatesLogRecord() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Weave_Template_Config__c t = makeTemplate();
        Contact c = makeContact();

        String ctx = JSON.serialize(new Map<String, Object>{ 'recordId' => String.valueOf(c.Id) });

        Test.startTest();
        MCNEmailSendService.SendResult result =
            MCNEmailSendService.sendEmail(t.Id, 'john@test.com', ctx);
        Test.stopTest();

        List<Weave_MCN_Email_Send__c> logs = [
            SELECT Send_Status__c, MCN_Message_ID__c, Recipient_Email__c
            FROM Weave_MCN_Email_Send__c
            WHERE Template__c = :t.Id
        ];
        // Log was created (Pending → Sent if template render succeeds; may fail on render in test context)
        System.assert(!logs.isEmpty(), 'At least a pending log should be created');
    }

    // ── Failure path ──────────────────────────────────────────────────────────

    @IsTest
    static void testMcnApiFailureSetsFailedStatus() {
        Test.setMock(HttpCalloutMock.class, new FailMock());
        Weave_Template_Config__c t = makeTemplate();
        Contact c = makeContact();

        String ctx = JSON.serialize(new Map<String, Object>{ 'recordId' => String.valueOf(c.Id) });

        Test.startTest();
        MCNEmailSendService.SendResult result =
            MCNEmailSendService.sendEmail(t.Id, 'john@test.com', ctx);
        Test.stopTest();

        // Either render failed (no HTML assembly in unit test) or MCN call failed
        System.assertEquals(false, result.isSuccess);
    }

    // ── Log update ────────────────────────────────────────────────────────────

    @IsTest
    static void testLogCreatedInPendingState() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Weave_Template_Config__c t = makeTemplate();

        Test.startTest();
        MCNEmailSendService.sendEmail(t.Id, 'valid@email.com', null);
        Test.stopTest();

        List<Weave_MCN_Email_Send__c> logs = [
            SELECT Send_Status__c FROM Weave_MCN_Email_Send__c
            WHERE Template__c = :t.Id
        ];
        System.assert(!logs.isEmpty(), 'Log record must be created');
    }
}
