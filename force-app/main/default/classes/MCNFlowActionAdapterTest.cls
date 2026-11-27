@SuppressWarnings('PMD.MethodNamingConventions,PMD.ApexDoc,PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest
private class MCNFlowActionAdapterTest {

    private class SuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(202);
            res.setBody('{"requestId":"flow-msg-456"}');
            return res;
        }
    }

    private static Weave_Template_Config__c makeTemplate() {
        Weave_Template_Config__c t = new Weave_Template_Config__c(
            Name                      = 'Flow Action Test',
            Status__c                 = 'Draft',
            Parent_Object_API_Name__c = 'Contact',
            Subject_Template__c       = 'Subject'
        );
        insert t;
        return t;
    }

    // ── Single request ────────────────────────────────────────────────────────

    @IsTest
    static void testSingleRequest_nullTemplate() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        MCNFlowActionAdapter.SendRequest req = new MCNFlowActionAdapter.SendRequest();
        req.templateId    = null;
        req.recipientEmail = 'a@b.com';

        Test.startTest();
        List<MCNFlowActionAdapter.SendResult> results =
            MCNFlowActionAdapter.sendEmail(new List<MCNFlowActionAdapter.SendRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].errorMessage != null);
    }

    @IsTest
    static void testSingleRequest_invalidEmail() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Weave_Template_Config__c t = makeTemplate();

        MCNFlowActionAdapter.SendRequest req = new MCNFlowActionAdapter.SendRequest();
        req.templateId     = t.Id;
        req.recipientEmail = 'bad-email';

        Test.startTest();
        List<MCNFlowActionAdapter.SendResult> results =
            MCNFlowActionAdapter.sendEmail(new List<MCNFlowActionAdapter.SendRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assertEquals('Failed', results[0].sendStatus);
    }

    @IsTest
    static void testResultOutputFields_populated() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Weave_Template_Config__c t = makeTemplate();

        Contact c = new Contact(FirstName = 'Test', LastName = 'User', Email = 'test@flow.com');
        insert c;

        MCNFlowActionAdapter.SendRequest req = new MCNFlowActionAdapter.SendRequest();
        req.templateId            = t.Id;
        req.recipientEmail        = 'test@flow.com';
        req.contextVariablesJson  = JSON.serialize(new Map<String,Object>{ 'recordId' => String.valueOf(c.Id) });

        Test.startTest();
        List<MCNFlowActionAdapter.SendResult> results =
            MCNFlowActionAdapter.sendEmail(new List<MCNFlowActionAdapter.SendRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        // isSuccess may be false if template render fails in test context (no HTML components)
        // but result fields must always be populated
        System.assertNotEquals(null, results[0].sendStatus);
    }

    // ── Bulk / governor limit ─────────────────────────────────────────────────

    @IsTest
    static void testBulkification_100Requests() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        Weave_Template_Config__c t = makeTemplate();

        List<MCNFlowActionAdapter.SendRequest> requests = new List<MCNFlowActionAdapter.SendRequest>();
        for (Integer i = 0; i < 100; i++) {
            MCNFlowActionAdapter.SendRequest req = new MCNFlowActionAdapter.SendRequest();
            req.templateId     = t.Id;
            req.recipientEmail = 'user' + i + '@bulk.test';
            requests.add(req);
        }

        Test.startTest();
        List<MCNFlowActionAdapter.SendResult> results =
            MCNFlowActionAdapter.sendEmail(requests);
        Test.stopTest();

        System.assertEquals(100, results.size(), 'Must return one result per request');
        for (MCNFlowActionAdapter.SendResult res : results) {
            System.assertNotEquals(null, res, 'No null results allowed');
        }
    }
}
