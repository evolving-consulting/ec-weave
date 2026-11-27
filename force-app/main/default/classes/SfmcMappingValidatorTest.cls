@IsTest
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces')
private class SfmcMappingValidatorTest {

    private static Weave_Template_Config__c makeTemplate(String status, String channels) {
        Weave_Template_Config__c t = new Weave_Template_Config__c(
            Name                   = 'Test Template',
            Status__c              = status,
            Template_Channels__c   = channels,
            Parent_Object_API_Name__c = 'Account'
        );
        insert t;
        return t;
    }

    private static Weave_Template_Component__c makeComponent(Id templateId, String html, String region) {
        Weave_Template_Component__c c = new Weave_Template_Component__c(
            Weave_Template_Config__c = templateId,
            HTML_Output__c           = html,
            Region__c                = region,
            Display_Order__c         = 1
        );
        insert c;
        return c;
    }

    // ── Status check ──────────────────────────────────────────────────────────

    @IsTest
    static void failsOnDraftTemplate() {
        Weave_Template_Config__c t = makeTemplate('Draft', 'All Channels');
        Test.startTest();
        SfmcMappingValidator.ValidationResult r = SfmcMappingValidator.validateForPublish(t.Id);
        Test.stopTest();

        Assert.isFalse(r.isValid);
        Assert.isTrue(r.errors[0].contains('Active'), 'Error should mention Active status');
    }

    // ── Empty content checks ──────────────────────────────────────────────────

    @IsTest
    static void failsOnNoComponents() {
        Weave_Template_Config__c t = makeTemplate('Active', 'All Channels');
        Test.startTest();
        SfmcMappingValidator.ValidationResult r = SfmcMappingValidator.validateForPublish(t.Id);
        Test.stopTest();

        Assert.isFalse(r.isValid);
        Assert.isTrue(r.errors[0].contains('no components'));
    }

    @IsTest
    static void warnsOnEmptyBodyComponent() {
        Weave_Template_Config__c t = makeTemplate('Active', 'All Channels');
        makeComponent(t.Id, '<p>Header</p>', 'Header');
        // No body component with content

        Test.startTest();
        SfmcMappingValidator.ValidationResult r = SfmcMappingValidator.validateForPublish(t.Id);
        Test.stopTest();

        Assert.isTrue(r.isValid, 'Should be valid (warning only for missing body)');
        Boolean hasBodyWarning = false;
        for (String w : r.warnings) {
            if (w.contains('body')) hasBodyWarning = true;
        }
        Assert.isTrue(hasBodyWarning, 'Should warn about missing body content');
    }

    // ── Merge field validation ────────────────────────────────────────────────

    @IsTest
    static void passesWithValidParentMergeField() {
        Weave_Template_Config__c t = makeTemplate('Active', 'All Channels');
        makeComponent(t.Id, '<p>{{Parent.Name}}</p>', 'Body');

        Test.startTest();
        SfmcMappingValidator.ValidationResult r = SfmcMappingValidator.validateForPublish(t.Id);
        Test.stopTest();

        Assert.isTrue(r.isValid);
        Assert.isTrue(r.errors.isEmpty());
    }

    @IsTest
    static void failsOnBadSectionTag() {
        Weave_Template_Config__c t = makeTemplate('Active', 'All Channels');
        makeComponent(t.Id, '<p>{{Section}}</p>', 'Body');

        Test.startTest();
        SfmcMappingValidator.ValidationResult r = SfmcMappingValidator.validateForPublish(t.Id);
        Test.stopTest();

        Assert.isFalse(r.isValid);
        Boolean sectionError = false;
        for (String err : r.errors) {
            if (err.contains('Section')) sectionError = true;
        }
        Assert.isTrue(sectionError);
    }

    @IsTest
    static void warnsOnFlowVariables() {
        Weave_Template_Config__c t = makeTemplate('Active', 'All Channels');
        makeComponent(t.Id, '<p>{{Flow.refCode}}</p>', 'Body');

        Test.startTest();
        SfmcMappingValidator.ValidationResult r = SfmcMappingValidator.validateForPublish(t.Id);
        Test.stopTest();

        Assert.isTrue(r.isValid, 'Flow refs should produce a warning, not an error');
        Boolean hasFlowWarning = false;
        for (String w : r.warnings) {
            if (w.contains('Flow')) hasFlowWarning = true;
        }
        Assert.isTrue(hasFlowWarning, 'Should warn about Flow variables');
    }

    // ── Not found ─────────────────────────────────────────────────────────────

    @IsTest
    static void failsOnMissingTemplate() {
        Test.startTest();
        SfmcMappingValidator.ValidationResult r =
            SfmcMappingValidator.validateForPublish('a0Q000000000001AAA');
        Test.stopTest();

        Assert.isFalse(r.isValid);
        Assert.isTrue(r.errors[0].contains('not found'));
    }

    // ── ValidationResult helpers ──────────────────────────────────────────────

    @IsTest
    static void toSummaryReturnsValidWhenClean() {
        SfmcMappingValidator.ValidationResult r = new SfmcMappingValidator.ValidationResult();
        Assert.areEqual('Valid', r.toSummary());
    }

    @IsTest
    static void toSummaryShowsErrors() {
        SfmcMappingValidator.ValidationResult r = new SfmcMappingValidator.ValidationResult();
        r.addError('something broke');
        Assert.isTrue(r.toSummary().contains('Errors'));
        Assert.isFalse(r.isValid);
    }
}
