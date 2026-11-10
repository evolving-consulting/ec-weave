@IsTest
private class DceTemplateContentServiceTest {
    @IsTest
    static void splitsAndReconstructsContentBeyondLongTextAreaLimit() {
        String longBody = buildContent(DceTemplateContentService.INLINE_CONTENT_LENGTH + 5000);
        DceTemplateContentService.PreparedContent prepared =
            DceTemplateContentService.prepareContent('<header>H</header>', longBody, '<footer>F</footer>');

        Assert.areEqual(DceTemplateContentService.INLINE_CONTENT_LENGTH, prepared.bodyInline.length());
        Assert.areEqual(1, prepared.overflowChunks.size());
        Assert.areEqual('Body', prepared.overflowChunks[0].region);
        Assert.areEqual(2, prepared.overflowChunks[0].sequence);

        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Header__c = prepared.headerInline;
        template.Body_Template__c = prepared.bodyInline;
        template.Footer__c = prepared.footerInline;
        update template;

        Test.startTest();
        DceTemplateContentService.replaceOverflowChunks(template.Id, prepared.overflowChunks);
        DceTemplateContentService.ContentBundle loaded = DceTemplateContentService.loadContent(template);
        Test.stopTest();

        Assert.areEqual(longBody, loaded.bodyHtml, 'Overflow chunks must be lossless.');
        Assert.areEqual('<header>H</header>', loaded.headerHtml);
        Assert.areEqual('<footer>F</footer>', loaded.footerHtml);
    }

    @IsTest
    static void rejectsRegionAndRenderedContentAboveApplicationLimit() {
        String oversized = buildContent(DceTemplateContentService.MAX_REGION_CONTENT_LENGTH + 1);
        AuraHandledException sourceException;
        try {
            DceTemplateContentService.prepareContent(null, oversized, null);
        } catch (AuraHandledException exceptionValue) {
            sourceException = exceptionValue;
        }
        Assert.isNotNull(sourceException, 'Oversized source HTML must be rejected.');

        AuraHandledException renderedException;
        try {
            DceTemplateContentService.assertRenderedSize(oversized);
        } catch (AuraHandledException exceptionValue) {
            renderedException = exceptionValue;
        }
        Assert.isNotNull(renderedException, 'Oversized rendered HTML must be rejected.');
    }

    private static String buildContent(Integer requestedLength) {
        String value = '0123456789';
        while (value.length() < requestedLength) {
            Integer remaining = requestedLength - value.length();
            Integer copyLength = Math.min(value.length(), remaining);
            value += value.substring(0, copyLength);
        }
        return value;
    }
}
