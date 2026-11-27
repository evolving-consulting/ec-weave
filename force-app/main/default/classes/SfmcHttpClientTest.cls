@SuppressWarnings('PMD.ApexDoc,PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest
private class SfmcHttpClientTest {

    private class MockSuccess implements HttpCalloutMock {
        Integer code; String body;
        MockSuccess(Integer c, String b) { code = c; body = b; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(code);
            res.setBody(body);
            return res;
        }
    }

    @IsTest
    static void postReturnsSuccessResponse() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess(201, '{"id":"new-asset"}'));
        Test.startTest();
        SfmcHttpClient.McnResponse res = new SfmcHttpClient().post('/test', '{"name":"x"}');
        Test.stopTest();
        Assert.isTrue(res.isSuccess);
        Assert.areEqual(201, res.statusCode);
        Assert.isTrue(res.body.contains('new-asset'));
    }

    @IsTest
    static void putReturnsSuccessResponse() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess(200, '{"updated":true}'));
        Test.startTest();
        SfmcHttpClient.McnResponse res = new SfmcHttpClient().put('/test/1', '{}');
        Test.stopTest();
        Assert.isTrue(res.isSuccess);
        Assert.areEqual(200, res.statusCode);
    }

    @IsTest
    static void delReturnsSuccessResponse() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess(204, ''));
        Test.startTest();
        SfmcHttpClient.McnResponse res = new SfmcHttpClient().del('/test/1');
        Test.stopTest();
        Assert.isTrue(res.isSuccess);
        Assert.areEqual(204, res.statusCode);
    }

    @IsTest
    static void getReturnsSuccessResponse() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess(200, '{"id":"abc","name":"test"}'));
        Test.startTest();
        SfmcHttpClient.McnResponse res = new SfmcHttpClient().get('/test/abc');
        Test.stopTest();
        Assert.isTrue(res.isSuccess);
        Assert.areEqual(200, res.statusCode);
        Map<String, Object> body = res.bodyAsMap();
        Assert.areEqual('abc', body.get('id'));
    }

    @IsTest
    static void errorResponseIsNotSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess(400, '{"error":"bad request"}'));
        Test.startTest();
        SfmcHttpClient.McnResponse res = new SfmcHttpClient().post('/test', '{}');
        Test.stopTest();
        Assert.isFalse(res.isSuccess);
        Assert.isTrue(res.errorMessage.contains('400'));
    }

    @IsTest
    static void serverErrorIsNotSuccess() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess(500, '{"error":"internal"}'));
        Test.startTest();
        SfmcHttpClient.McnResponse res = new SfmcHttpClient().get('/test');
        Test.stopTest();
        Assert.isFalse(res.isSuccess);
    }

    @IsTest
    static void parameterizedConstructorAllowed() {
        Test.setMock(HttpCalloutMock.class, new MockSuccess(200, '{}'));
        Test.startTest();
        SfmcHttpClient client = new SfmcHttpClient('MCN_API');
        SfmcHttpClient.McnResponse res = client.get('/test');
        Test.stopTest();
        Assert.isTrue(res.isSuccess);
    }

    @IsTest
    static void bodyAsMapReturnsEmptyOnBlank() {
        SfmcHttpClient.McnResponse res = new SfmcHttpClient.McnResponse('error');
        Map<String, Object> m = res.bodyAsMap();
        Assert.isNotNull(m);
        Assert.isTrue(m.isEmpty());
    }
}
