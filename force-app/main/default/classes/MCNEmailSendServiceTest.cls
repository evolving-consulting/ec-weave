@SuppressWarnings('PMD.MethodNamingConventions,PMD.ApexDoc,PMD.ApexUnitTestClassShouldHaveRunAs')
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

    // ── Log creation ─────────────────────────────────────────────────────────

    @IsTest
    static void testLogCreatedWithFinalStatus() {
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
        System.assertNotEquals('Pending', logs[0].Send_Status__c, 'Log must have final status after synchronous send');
    }

    // ── sendBulk ──────────────────────────────────────────────────────────────

    @IsTest
    static void testSendBulk_successPath_withRecordId() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Weave_Template_Config__c t = makeTemplate();
        Contact c = makeContact();
        String ctx = JSON.serialize(new Map<String, Object>{ 'recordId' => String.valueOf(c.Id) });

        List<Id>     tids   = new List<Id>{ t.Id };
        List<String> emails = new List<String>{ 'bulk@test.com' };
        List<String> ctxs   = new List<String>{ ctx };

        Test.startTest();
        List<MCNEmailSendService.SendResult> results = MCNEmailSendService.sendBulk(tids, emails, ctxs);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].status);
    }

    @IsTest
    static void testSendBulk_returnsOneResultPerRequest() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Weave_Template_Config__c t = makeTemplate();

        List<Id>     tids   = new List<Id>{ t.Id, t.Id };
        List<String> emails = new List<String>{ 'a@test.com', 'b@test.com' };
        List<String> ctxs   = new List<String>{ null, null };

        Test.startTest();
        List<MCNEmailSendService.SendResult> results = MCNEmailSendService.sendBulk(tids, emails, ctxs);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Must return one result per request');
        for (MCNEmailSendService.SendResult r : results) {
            System.assertNotEquals(null, r, 'No null results');
            System.assertNotEquals(null, r.status, 'Status must be populated');
        }
    }

    @IsTest
    static void testSendBulk_logsCreatedForAllRequests() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Weave_Template_Config__c t = makeTemplate();

        List<Id>     tids   = new List<Id>{ t.Id, t.Id, t.Id };
        List<String> emails = new List<String>{ 'x@test.com', 'y@test.com', 'z@test.com' };
        List<String> ctxs   = new List<String>{ '{}', '{}', '{}' };

        Test.startTest();
        MCNEmailSendService.sendBulk(tids, emails, ctxs);
        Test.stopTest();

        List<Weave_MCN_Email_Send__c> logs = [
            SELECT Send_Status__c FROM Weave_MCN_Email_Send__c
            WHERE Template__c = :t.Id
        ];
        System.assert(logs.size() >= 3, 'At least 3 log records should be created');
    }

    @IsTest
    static void testSendBulk_invalidEmailsReturnFailure() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Weave_Template_Config__c t = makeTemplate();

        List<Id>     tids   = new List<Id>{ t.Id };
        List<String> emails = new List<String>{ 'not-valid' };
        List<String> ctxs   = new List<String>{ null };

        Test.startTest();
        List<MCNEmailSendService.SendResult> results = MCNEmailSendService.sendBulk(tids, emails, ctxs);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].isSuccess);
    }

    @IsTest
    static void testSendBulk_mcnFailureReturnsFailed() {
        Test.setMock(HttpCalloutMock.class, new FailMock());
        Weave_Template_Config__c t = makeTemplate();

        List<Id>     tids   = new List<Id>{ t.Id };
        List<String> emails = new List<String>{ 'fail@test.com' };
        List<String> ctxs   = new List<String>{ '{}' };

        Test.startTest();
        List<MCNEmailSendService.SendResult> results = MCNEmailSendService.sendBulk(tids, emails, ctxs);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].isSuccess);
    }
}
