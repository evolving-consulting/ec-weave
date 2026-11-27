@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest
private class MergeFieldTranslatorTest {

    // ── translate() ───────────────────────────────────────────────────────────

    @IsTest
    static void translateParentField() {
        MergeFieldTranslator.TranslationResult r =
            MergeFieldTranslator.translate('<p>Hello {{Parent.Name}}</p>');

        Assert.areEqual('<p>Hello %%=v(@Parent_Name)=%%</p>', r.translatedContent);
        Assert.areEqual(1, r.mergeFieldsTranslated);
        Assert.areEqual(0, r.mergeFieldsSkipped);
    }

    @IsTest
    static void translateDataCloudField() {
        String input = 'Email: {{DataCloud.Contact__dlm.Email__c}}';
        MergeFieldTranslator.TranslationResult r = MergeFieldTranslator.translate(input);

        Assert.isTrue(r.translatedContent.contains('%%=v(@DataCloud_Contact__dlmEmail__c)=%%'),
            'Expected AMPscript var for DataCloud ref, got: ' + r.translatedContent);
        Assert.areEqual(1, r.mergeFieldsTranslated);
    }

    @IsTest
    static void translateFlowVariable() {
        String input = 'Token: {{Flow.authToken}}';
        MergeFieldTranslator.TranslationResult r = MergeFieldTranslator.translate(input);

        Assert.isTrue(r.translatedContent.contains('%%=v(@Flow_authToken)=%%'),
            'Expected AMPscript var for Flow ref, got: ' + r.translatedContent);
        Assert.areEqual(1, r.mergeFieldsTranslated);
    }

    @IsTest
    static void preservesSectionTags() {
        String input = '<div>{{Section.RelatedProducts}}</div>';
        MergeFieldTranslator.TranslationResult r = MergeFieldTranslator.translate(input);

        Assert.isTrue(r.translatedContent.contains('{{Section.RelatedProducts}}'),
            'Section tags should be preserved unchanged');
        Assert.areEqual(0, r.mergeFieldsTranslated);
        Assert.areEqual(1, r.mergeFieldsSkipped);
    }

    @IsTest
    static void preservesBrandTags() {
        String input = '<img src="{{Brand.LogoUrl}}" />';
        MergeFieldTranslator.TranslationResult r = MergeFieldTranslator.translate(input);

        Assert.isTrue(r.translatedContent.contains('{{Brand.LogoUrl}}'),
            'Brand tags should be preserved unchanged');
        Assert.areEqual(0, r.mergeFieldsTranslated);
        Assert.areEqual(1, r.mergeFieldsSkipped);
    }

    @IsTest
    static void translateMultipleMixedFields() {
        String input = '{{Parent.Name}} {{Flow.refCode}} {{Section.Table}} {{DataCloud.Acct__dlm.Revenue__c}}';
        MergeFieldTranslator.TranslationResult r = MergeFieldTranslator.translate(input);

        Assert.areEqual(4, r.mergeFieldsFound);
        Assert.areEqual(3, r.mergeFieldsTranslated);
        Assert.areEqual(1, r.mergeFieldsSkipped);
    }

    @IsTest
    static void translateBlankContent() {
        MergeFieldTranslator.TranslationResult r = MergeFieldTranslator.translate('');
        Assert.areEqual('', r.translatedContent);
        Assert.areEqual(0, r.mergeFieldsFound);
    }

    @IsTest
    static void translateNullContent() {
        MergeFieldTranslator.TranslationResult r = MergeFieldTranslator.translate(null);
        Assert.isNull(r.translatedContent);
    }

    // ── sanitize() ────────────────────────────────────────────────────────────

    @IsTest
    static void sanitizeParentFieldPath() {
        Assert.areEqual('Parent_Name', MergeFieldTranslator.sanitize('Parent.Name'));
    }

    @IsTest
    static void sanitizeDataCloudPath() {
        Assert.areEqual('DataCloud_Contact__dlmEmail__c',
            MergeFieldTranslator.sanitize('DataCloud.Contact__dlm.Email__c'));
    }

    @IsTest
    static void sanitizeFlowVariable() {
        Assert.areEqual('Flow_authToken', MergeFieldTranslator.sanitize('Flow.authToken'));
    }

    @IsTest
    static void sanitizeRemovesInvalidChars() {
        // Hyphens and spaces (if somehow present) should be removed
        String result = MergeFieldTranslator.sanitize('My-Field Name');
        Assert.isFalse(result.contains('-'), 'Hyphens should be removed');
        Assert.isFalse(result.contains(' '), 'Spaces should be removed');
    }

    // ── buildVariableDeclarations() ───────────────────────────────────────────

    @IsTest
    static void buildVariableDeclarationsOutput() {
        Set<String> vars = new Set<String>{ 'Parent.Name', 'Flow.token' };
        String block = MergeFieldTranslator.buildVariableDeclarations(vars);
        Assert.isTrue(block.startsWith('%%['), 'Block should start with %%[');
        Assert.isTrue(block.endsWith(']%%'), 'Block should end with ]%%');
        Assert.isTrue(block.contains('SET @'), 'Block should contain SET statements');
    }

    @IsTest
    static void buildVariableDeclarationsEmpty() {
        Assert.areEqual('', MergeFieldTranslator.buildVariableDeclarations(new Set<String>()));
    }
}
