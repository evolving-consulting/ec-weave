@SuppressWarnings('PMD.MethodNamingConventions')
@IsTest
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces')
private class SfmcTemplatePublisherTest {

    // ── Test data factory ─────────────────────────────────────────────────────

    private static Weave_Template_Config__c makeTemplate(
        String status, String assetId
    ) {
        Weave_Template_Config__c t = new Weave_Template_Config__c(
            Name                      = 'Publisher Test Template',
            Status__c                 = status,
            Template_Channels__c      = 'All Channels',
            Parent_Object_API_Name__c = 'Account',
            Subject_Template__c       = 'Test Subject',
            SFMC_Template_ID__c       = assetId
        );
        insert t;
        return t;
    }

    private static void addComponent(Id templateId, String html) {
        insert new Weave_Template_Component__c(
            Weave_Template_Config__c = templateId,
            HTML_Output__c           = html,
            Region__c                = 'Body',
            Display_Order__c         = 1
        );
    }

    // ── Publish: success ──────────────────────────────────────────────────────

    @IsTest
    static void publishCreatesNewAsset() {
        Weave_Template_Config__c t = makeTemplate('Active', null);
        addComponent(t.Id, '<p>Hello {{Parent.Name}}</p>');

        MockAdapter mock = new MockAdapter('new-asset-999', true, true, true, true);

        Test.startTest();
        SfmcTemplatePublisher.PublishResult result =
            SfmcTemplatePublisher.publishTemplate(t.Id, mock);
        Test.stopTest();

        Assert.isTrue(result.isSuccess, 'Publish should succeed: ' + result.errorMessage);
        Assert.areEqual('new-asset-999', result.mcnAssetId);
        Assert.areEqual('Create', result.publishType);

        // Weave_Template_Config__c should now have Published status
        Weave_Template_Config__c updated = [
            SELECT SFMC_Publish_Status__c, SFMC_Template_ID__c FROM Weave_Template_Config__c WHERE Id = :t.Id
        ];
        Assert.areEqual('Published', updated.SFMC_Publish_Status__c);
        Assert.areEqual('new-asset-999', updated.SFMC_Template_ID__c);
    }

    @IsTest
    static void publishWritesSyncLog() {
        Weave_Template_Config__c t = makeTemplate('Active', null);
        addComponent(t.Id, '<p>Content</p>');

        MockAdapter mock = new MockAdapter('log-asset', true, true, true, true);

        Test.startTest();
        SfmcTemplatePublisher.publishTemplate(t.Id, mock);
        Test.stopTest();

        List<Weave_MCN_Sync_Log__c> logs = [
            SELECT Status__c, Publish_Type__c, MCN_Asset_ID__c
            FROM Weave_MCN_Sync_Log__c
            WHERE Template__c = :t.Id
        ];
        Assert.isFalse(logs.isEmpty(), 'A sync log should be created');
        Assert.areEqual('Success', logs[0].Status__c);
        Assert.areEqual('Create', logs[0].Publish_Type__c);
    }

    @IsTest
    static void publishTranslatesMergeFields() {
        Weave_Template_Config__c t = makeTemplate('Active', null);
        addComponent(t.Id, '<p>{{Parent.Name}} {{Flow.ref}} {{Section.Table}}</p>');

        // Capture what the mock receives
        MockAdapter mock = new MockAdapter('xlt-asset', true, true, true, true);

        Test.startTest();
        SfmcTemplatePublisher.PublishResult result =
            SfmcTemplatePublisher.publishTemplate(t.Id, mock);
        Test.stopTest();

        Assert.isTrue(result.isSuccess);
        // Parent and Flow tags should be translated; Section should be preserved
        Assert.isTrue(mock.lastHtmlSent.contains('%%=v(@Parent_Name)=%%'),
            'Parent.Name should be AMPscript: ' + mock.lastHtmlSent);
        Assert.isTrue(mock.lastHtmlSent.contains('%%=v(@Flow_ref)=%%'),
            'Flow.ref should be AMPscript: ' + mock.lastHtmlSent);
        Assert.isTrue(mock.lastHtmlSent.contains('{{Section.Table}}'),
            'Section tags should be preserved: ' + mock.lastHtmlSent);
    }

    // ── Publish: routes to update when already published ─────────────────────

    @IsTest
    static void publishRoutesToUpdateWhenAlreadyPublished() {
        Weave_Template_Config__c t = makeTemplate('Active', 'existing-asset-id');
        addComponent(t.Id, '<p>Content</p>');

        MockAdapter mock = new MockAdapter('existing-asset-id', true, true, true, true);

        Test.startTest();
        SfmcTemplatePublisher.PublishResult result =
            SfmcTemplatePublisher.publishTemplate(t.Id, mock);
        Test.stopTest();

        Assert.isTrue(result.isSuccess);
        Assert.areEqual('Update', result.publishType, 'Should route to Update since asset already exists');
        Assert.isTrue(mock.updateCalled);
    }

    // ── Publish: failure (MCN API error) ──────────────────────────────────────

    @IsTest
    static void publishFailsWhenMcnApiErrors() {
        Weave_Template_Config__c t = makeTemplate('Active', null);
        addComponent(t.Id, '<p>Content</p>');

        // createEmailAsset fails
        MockAdapter mock = new MockAdapter(null, false, true, true, true);

        Test.startTest();
        SfmcTemplatePublisher.PublishResult result =
            SfmcTemplatePublisher.publishTemplate(t.Id, mock);
        Test.stopTest();

        Assert.isFalse(result.isSuccess);
        Assert.isTrue(result.errorMessage.contains('MCN create failed'));

        // Status should be Error on record
        Weave_Template_Config__c updated = [
            SELECT SFMC_Publish_Status__c FROM Weave_Template_Config__c WHERE Id = :t.Id
        ];
        Assert.areEqual('Error', updated.SFMC_Publish_Status__c);
    }

    // ── Publish: validation failure ───────────────────────────────────────────

    @IsTest
    static void publishFailsValidation_DraftStatus() {
        Weave_Template_Config__c t = makeTemplate('Draft', null);
        addComponent(t.Id, '<p>Content</p>');

        MockAdapter mock = new MockAdapter('v-asset', true, true, true, true);

        Test.startTest();
        SfmcTemplatePublisher.PublishResult result =
            SfmcTemplatePublisher.publishTemplate(t.Id, mock);
        Test.stopTest();

        Assert.isFalse(result.isSuccess);
        Assert.isTrue(result.errorMessage.contains('Validation failed'));
    }

    // ── Update ────────────────────────────────────────────────────────────────

    @IsTest
    static void updateReturnsSuccessResult() {
        Weave_Template_Config__c t = makeTemplate('Active', 'upd-asset-id');
        addComponent(t.Id, '<p>Updated content</p>');

        MockAdapter mock = new MockAdapter('upd-asset-id', true, true, true, true);

        Test.startTest();
        SfmcTemplatePublisher.PublishResult result =
            SfmcTemplatePublisher.updateTemplate(t.Id, mock);
        Test.stopTest();

        Assert.isTrue(result.isSuccess);
        Assert.areEqual('Update', result.publishType);
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    @IsTest
    static void deleteRemovesAssetIdFromRecord() {
        Weave_Template_Config__c t = makeTemplate('Active', 'del-asset-id');
        addComponent(t.Id, '<p>Content</p>');

        MockAdapter mock = new MockAdapter('del-asset-id', true, true, true, true);

        Test.startTest();
        SfmcTemplatePublisher.PublishResult result =
            SfmcTemplatePublisher.deleteTemplate(t.Id, mock);
        Test.stopTest();

        Assert.isTrue(result.isSuccess);
        Assert.areEqual('Delete', result.publishType);

        Weave_Template_Config__c updated = [
            SELECT SFMC_Publish_Status__c, SFMC_Template_ID__c FROM Weave_Template_Config__c WHERE Id = :t.Id
        ];
        Assert.areEqual('Draft', updated.SFMC_Publish_Status__c);
        Assert.isTrue(String.isBlank(updated.SFMC_Template_ID__c));
    }

    @IsTest
    static void deleteFailsWhenNotPublished() {
        Weave_Template_Config__c t = makeTemplate('Active', null);
        MockAdapter mock = new MockAdapter(null, true, true, true, true);

        Test.startTest();
        SfmcTemplatePublisher.PublishResult result =
            SfmcTemplatePublisher.deleteTemplate(t.Id, mock);
        Test.stopTest();

        Assert.isFalse(result.isSuccess);
        Assert.isTrue(result.errorMessage.contains('not been published'));
    }

    // ── InvocableMethod ───────────────────────────────────────────────────────

    @IsTest
    static void invocableMethodHandlesRequest() {
        Weave_Template_Config__c t = makeTemplate('Active', null);
        addComponent(t.Id, '<p>Flow invocable test</p>');

        // The invocable method makes real callouts — we can only test the
        // error path via a callout mock, since HTTP is prohibited in tests
        // without a mock. We verify the method signature and error handling.
        SfmcTemplatePublisher.FlowPublishRequest req = new SfmcTemplatePublisher.FlowPublishRequest();
        req.templateId = t.Id;

        Test.setMock(HttpCalloutMock.class, new McnCalloutMock(201, '{"id":"flow-asset-1"}'));
        Test.startTest();
        List<SfmcTemplatePublisher.FlowPublishResult> results =
            SfmcTemplatePublisher.publishFromFlow(
                new List<SfmcTemplatePublisher.FlowPublishRequest>{ req }
            );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        // With a successful mock response, should succeed
        Assert.isTrue(results[0].isSuccess, 'Expected success: ' + results[0].errorMessage);
    }

    // ── Validate ──────────────────────────────────────────────────────────────

    @IsTest
    static void validateTemplateReturnsResult() {
        Weave_Template_Config__c t = makeTemplate('Active', null);
        addComponent(t.Id, '<p>{{Parent.Name}}</p>');

        Test.startTest();
        SfmcMappingValidator.ValidationResult r =
            SfmcTemplatePublisher.validateTemplate(t.Id);
        Test.stopTest();

        Assert.isNotNull(r);
        Assert.isTrue(r.isValid);
    }

    // ── Mock adapter ──────────────────────────────────────────────────────────

    private class MockAdapter extends WeaveMarketingCloudNextAdapter {
        String  assetId;
        Boolean createSuccess;
        Boolean updateSuccess;
        Boolean deleteSuccess;
        Boolean getSuccess;
        Boolean updateCalled = false;
        String  lastHtmlSent;

        MockAdapter(String assetId, Boolean c, Boolean u, Boolean d, Boolean g) {
            this.assetId       = assetId;
            this.createSuccess = c;
            this.updateSuccess = u;
            this.deleteSuccess = d;
            this.getSuccess    = g;
        }

        public override WeaveMarketingCloudNextAdapter.AdapterResult createEmailAsset(
            String name, String html, String subject
        ) {
            lastHtmlSent = html;
            if (!createSuccess) return new WeaveMarketingCloudNextAdapter.AdapterResult('Simulated create failure');
            return new WeaveMarketingCloudNextAdapter.AdapterResult(true, assetId);
        }

        public override WeaveMarketingCloudNextAdapter.AdapterResult updateEmailAsset(
            String id, String html, String subject
        ) {
            updateCalled = true;
            lastHtmlSent = html;
            if (!updateSuccess) return new WeaveMarketingCloudNextAdapter.AdapterResult('Simulated update failure');
            return new WeaveMarketingCloudNextAdapter.AdapterResult(true, id);
        }

        public override WeaveMarketingCloudNextAdapter.AdapterResult deleteEmailAsset(String id) {
            if (!deleteSuccess) return new WeaveMarketingCloudNextAdapter.AdapterResult('Simulated delete failure');
            return new WeaveMarketingCloudNextAdapter.AdapterResult(true, id);
        }

        public override WeaveMarketingCloudNextAdapter.AdapterResult getEmailAsset(String id) {
            if (!getSuccess) return new WeaveMarketingCloudNextAdapter.AdapterResult('Simulated get failure');
            WeaveMarketingCloudNextAdapter.AdapterResult r =
                new WeaveMarketingCloudNextAdapter.AdapterResult(true, id);
            r.asset = new WeaveMarketingCloudNextAdapter.McnAsset();
            r.asset.id          = id;
            r.asset.htmlContent = '<p>remote content</p>';
            return r;
        }
    }

    // ── HTTP callout mock (for invocable path) ────────────────────────────────

    private class McnCalloutMock implements HttpCalloutMock {
        Integer statusCode;
        String  body;

        McnCalloutMock(Integer code, String body) {
            this.statusCode = code;
            this.body       = body;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }
}
