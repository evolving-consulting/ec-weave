@SuppressWarnings('PMD.ApexDoc,PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest
private class WeaveMarketingCloudNextAdapterTest {

    private class SuccessMock implements HttpCalloutMock {
        Integer statusCode; String body;
        SuccessMock(Integer c, String b) { statusCode = c; body = b; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    // ── getInstance / setInstance ─────────────────────────────────────────────

    @IsTest
    static void getInstanceReturnsSingleton() {
        WeaveMarketingCloudNextAdapter.setInstance(null);
        WeaveMarketingCloudNextAdapter a1 = WeaveMarketingCloudNextAdapter.getInstance();
        Assert.isNotNull(a1);
    }

    @IsTest
    static void setInstanceOverridesDefault() {
        WeaveMarketingCloudNextAdapter mock = new WeaveMarketingCloudNextAdapter();
        WeaveMarketingCloudNextAdapter.setInstance(mock);
        Assert.areEqual(mock, WeaveMarketingCloudNextAdapter.getInstance());
        WeaveMarketingCloudNextAdapter.setInstance(null);
    }

    // ── CRUD: createEmailAsset ────────────────────────────────────────────────

    @IsTest
    static void createEmailAssetSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock(201, '{"id":"new-asset-1"}'));
        Test.startTest();
        WeaveMarketingCloudNextAdapter.AdapterResult r =
            new WeaveMarketingCloudNextAdapter().createEmailAsset('Test', '<p>Hi</p>', 'Subj');
        Test.stopTest();
        Assert.isTrue(r.isSuccess);
        Assert.areEqual('new-asset-1', r.assetId);
    }

    @IsTest
    static void createEmailAssetFailure() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock(400, '{"message":"Bad request"}'));
        Test.startTest();
        WeaveMarketingCloudNextAdapter.AdapterResult r =
            new WeaveMarketingCloudNextAdapter().createEmailAsset('Test', '<p>Hi</p>', 'Subj');
        Test.stopTest();
        Assert.isFalse(r.isSuccess);
        Assert.isTrue(r.errorMessage.contains('Create failed'));
    }

    // ── CRUD: updateEmailAsset ────────────────────────────────────────────────

    @IsTest
    static void updateEmailAssetSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock(200, '{"id":"asset-1"}'));
        Test.startTest();
        WeaveMarketingCloudNextAdapter.AdapterResult r =
            new WeaveMarketingCloudNextAdapter().updateEmailAsset('asset-1', '<p>Updated</p>', 'New Subj');
        Test.stopTest();
        Assert.isTrue(r.isSuccess);
        Assert.areEqual('asset-1', r.assetId);
    }

    @IsTest
    static void updateEmailAssetBlankIdFails() {
        WeaveMarketingCloudNextAdapter.AdapterResult r =
            new WeaveMarketingCloudNextAdapter().updateEmailAsset('', '<p>x</p>', 'x');
        Assert.isFalse(r.isSuccess);
    }

    // ── CRUD: deleteEmailAsset ────────────────────────────────────────────────

    @IsTest
    static void deleteEmailAssetSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock(200, '{}'));
        Test.startTest();
        WeaveMarketingCloudNextAdapter.AdapterResult r =
            new WeaveMarketingCloudNextAdapter().deleteEmailAsset('asset-2');
        Test.stopTest();
        Assert.isTrue(r.isSuccess);
    }

    @IsTest
    static void deleteEmailAssetBlankIdFails() {
        WeaveMarketingCloudNextAdapter.AdapterResult r =
            new WeaveMarketingCloudNextAdapter().deleteEmailAsset(null);
        Assert.isFalse(r.isSuccess);
    }

    // ── CRUD: getEmailAsset ───────────────────────────────────────────────────

    @IsTest
    static void getEmailAssetParsesHtmlContent() {
        String body = '{"id":"a3","name":"MyEmail","views":{"html":{"content":"<p>Hello</p>"}}}';
        Test.setMock(HttpCalloutMock.class, new SuccessMock(200, body));
        Test.startTest();
        WeaveMarketingCloudNextAdapter.AdapterResult r =
            new WeaveMarketingCloudNextAdapter().getEmailAsset('a3');
        Test.stopTest();
        Assert.isTrue(r.isSuccess);
        Assert.isNotNull(r.asset);
        Assert.areEqual('<p>Hello</p>', r.asset.htmlContent);
    }

    // ── MCNPublishResult ──────────────────────────────────────────────────────

    @IsTest
    static void publishTemplateResultFieldsReachable() {
        WeaveMarketingCloudNextAdapter.MCNPublishResult res =
            new WeaveMarketingCloudNextAdapter.MCNPublishResult(true, 'asset-99');
        Assert.isTrue(res.isSuccess);
        Assert.isTrue(res.success);
        Assert.areEqual('asset-99', res.mcnAssetId);
    }

    @IsTest
    static void publishTemplateResultErrorConstructor() {
        WeaveMarketingCloudNextAdapter.MCNPublishResult res =
            new WeaveMarketingCloudNextAdapter.MCNPublishResult('Something went wrong');
        Assert.isFalse(res.isSuccess);
        Assert.isFalse(res.success);
        Assert.isTrue(res.errorMessage.contains('Something went wrong'));
    }
}
