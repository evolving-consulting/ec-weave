@IsTest
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces')
private class SfmcTemplateConflictDetectorTest {

    private static Weave_Template_Config__c makePublishedTemplate(String assetId) {
        Weave_Template_Config__c t = new Weave_Template_Config__c(
            Name                     = 'Conflict Test Template',
            Status__c                = 'Active',
            SFMC_Template_ID__c      = assetId,
            SFMC_Publish_Status__c   = 'Published',
            Parent_Object_API_Name__c = 'Account'
        );
        insert t;
        return t;
    }

    // ── NOT_PUBLISHED states ──────────────────────────────────────────────────

    @IsTest
    static void notPublishedWhenNoAssetId() {
        Weave_Template_Config__c t = new Weave_Template_Config__c(
            Name                      = 'Unpublished',
            Status__c                 = 'Active',
            Parent_Object_API_Name__c = 'Account'
        );
        insert t;

        SfmcTemplateConflictDetector.ConflictResult r =
            SfmcTemplateConflictDetector.detectConflict(t.Id);

        Assert.areEqual(SfmcTemplateConflictDetector.ConflictState.NOT_PUBLISHED, r.state);
    }

    @IsTest
    static void notPublishedOnTemplateNotFound() {
        SfmcTemplateConflictDetector.ConflictResult r =
            SfmcTemplateConflictDetector.detectConflict('a0Q000000000001AAA');
        Assert.areEqual(SfmcTemplateConflictDetector.ConflictState.NOT_PUBLISHED, r.state);
    }

    // ── NO_CONFLICT when hashes match ────────────────────────────────────────

    @IsTest
    static void noConflictWhenHashesMatch() {
        String assetId   = 'asset-123';
        String htmlContent = '<p>Hello World</p>';
        String contentHash = SfmcTemplateConflictDetector.hashContent(htmlContent);

        Weave_Template_Config__c t = makePublishedTemplate(assetId);

        // Insert a sync log that records the same hash we last published
        Weave_MCN_Sync_Log__c log = new Weave_MCN_Sync_Log__c(
            Template__c                = t.Id,
            Status__c                  = 'Success',
            Publish_Type__c            = 'Create',
            Translated_Content_Hash__c = contentHash
        );
        insert log;

        // Mock adapter returns same HTML
        MockMcnAdapter mockAdapter = new MockMcnAdapter(true, assetId, htmlContent, null);

        Test.startTest();
        SfmcTemplateConflictDetector.ConflictResult r =
            SfmcTemplateConflictDetector.detectConflict(t.Id, mockAdapter);
        Test.stopTest();

        Assert.areEqual(SfmcTemplateConflictDetector.ConflictState.NO_CONFLICT, r.state);
    }

    // ── CONFLICT_DETECTED when hashes differ ─────────────────────────────────

    @IsTest
    static void conflictDetectedWhenRemoteModified() {
        String assetId        = 'asset-456';
        String localHtml      = '<p>Original</p>';
        String remoteHtml     = '<p>Edited outside Weave</p>';
        String localHash      = SfmcTemplateConflictDetector.hashContent(localHtml);

        Weave_Template_Config__c t = makePublishedTemplate(assetId);

        Weave_MCN_Sync_Log__c log = new Weave_MCN_Sync_Log__c(
            Template__c                = t.Id,
            Status__c                  = 'Success',
            Publish_Type__c            = 'Create',
            Translated_Content_Hash__c = localHash
        );
        insert log;

        // Remote returns different HTML
        MockMcnAdapter mockAdapter = new MockMcnAdapter(true, assetId, remoteHtml, null);

        Test.startTest();
        SfmcTemplateConflictDetector.ConflictResult r =
            SfmcTemplateConflictDetector.detectConflict(t.Id, mockAdapter);
        Test.stopTest();

        Assert.areEqual(SfmcTemplateConflictDetector.ConflictState.CONFLICT_DETECTED, r.state);
        Assert.isTrue(r.message.contains('Conflict'), 'Message should mention conflict');
        Assert.areNotEqual(r.localHash, r.remoteHash);
        Assert.isTrue(r.canOverwrite);
    }

    // ── Adapter error ─────────────────────────────────────────────────────────

    @IsTest
    static void notPublishedWhenAdapterFails() {
        Weave_Template_Config__c t = makePublishedTemplate('bad-asset-id');

        MockMcnAdapter mockAdapter = new MockMcnAdapter(false, null, null, 'Network error');

        Test.startTest();
        SfmcTemplateConflictDetector.ConflictResult r =
            SfmcTemplateConflictDetector.detectConflict(t.Id, mockAdapter);
        Test.stopTest();

        Assert.areEqual(SfmcTemplateConflictDetector.ConflictState.NOT_PUBLISHED, r.state);
        Assert.isFalse(r.canOverwrite);
    }

    // ── hashContent ───────────────────────────────────────────────────────────

    @IsTest
    static void hashContentProduces64CharHex() {
        String hash = SfmcTemplateConflictDetector.hashContent('<p>hello</p>');
        Assert.areEqual(64, hash.length());
        Assert.isTrue(hash.isAllLowercase() || Pattern.matches('[0-9a-f]+', hash));
    }

    @IsTest
    static void hashContentEmptyReturnsEmpty() {
        Assert.areEqual('', SfmcTemplateConflictDetector.hashContent(''));
        Assert.areEqual('', SfmcTemplateConflictDetector.hashContent(null));
    }

    @IsTest
    static void sameContentProducesSameHash() {
        String h1 = SfmcTemplateConflictDetector.hashContent('<p>Test</p>');
        String h2 = SfmcTemplateConflictDetector.hashContent('<p>Test</p>');
        Assert.areEqual(h1, h2);
    }

    // ── Mock adapter ──────────────────────────────────────────────────────────

    private class MockMcnAdapter extends WeaveMarketingCloudNextAdapter {
        private Boolean   success;
        private String    assetId;
        private String    htmlContent;
        private String    errorMsg;

        MockMcnAdapter(Boolean success, String assetId, String htmlContent, String errorMsg) {
            this.success     = success;
            this.assetId     = assetId;
            this.htmlContent = htmlContent;
            this.errorMsg    = errorMsg;
        }

        public override WeaveMarketingCloudNextAdapter.AdapterResult getEmailAsset(String id) {
            if (!success) return new WeaveMarketingCloudNextAdapter.AdapterResult(errorMsg);
            WeaveMarketingCloudNextAdapter.AdapterResult r =
                new WeaveMarketingCloudNextAdapter.AdapterResult(true, assetId);
            r.asset = new WeaveMarketingCloudNextAdapter.McnAsset();
            r.asset.id          = assetId;
            r.asset.htmlContent = htmlContent;
            return r;
        }
    }
}
