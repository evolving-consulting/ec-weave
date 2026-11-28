@SuppressWarnings('PMD.MethodNamingConventions')
@IsTest
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.ApexUnitTestClassShouldHaveRunAs')
private class LegacyTemplateAnalyzerTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Weave_Template_Config__c makeTemplate(String name, String status, String channel) {
        Weave_Template_Config__c t = new Weave_Template_Config__c(
            Name                      = name,
            Status__c                 = status,
            Template_Channels__c      = channel,
            Parent_Object_API_Name__c = 'Contact',
            Subject_Template__c       = 'Hello {{Parent.FirstName}}'
        );
        insert t;
        return t;
    }

    private static Weave_Template_Component__c makeComponent(Id templateId, String region, String html) {
        Weave_Template_Component__c c = new Weave_Template_Component__c(
            Name                   = 'Test Component',
            Weave_Template_Config__c = templateId,
            Region__c              = region,
            HTML_Output__c         = html,
            Display_Order__c       = 1
        );
        insert c;
        return c;
    }

    // ── analyzeAll ────────────────────────────────────────────────────────────

    @IsTest
    static void testAnalyzeAll_returnsResults() {
        makeTemplate('T1', 'Active', 'Salesforce Email');
        makeTemplate('T2', 'Active', 'All Channels');

        Test.startTest();
        List<LegacyTemplateAnalyzer.AnalysisResult> results = LegacyTemplateAnalyzer.analyzeAll();
        Test.stopTest();

        System.assert(results.size() >= 2, 'Should return at least 2 results');
    }

    // ── analyze: already on All Channels ─────────────────────────────────────

    @IsTest
    static void testAnalyze_alreadyAllChannels_score100() {
        Weave_Template_Config__c t = makeTemplate('Already MCN', 'Active', 'All Channels');

        Test.startTest();
        List<LegacyTemplateAnalyzer.AnalysisResult> results =
            LegacyTemplateAnalyzer.analyzeByIds(new List<Id>{ t.Id });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(100, results[0].readinessScore, 'Already-MCN template should score 100');
        System.assertEquals('Skip', results[0].recommendation);
    }

    // ── analyze: inactive template ────────────────────────────────────────────

    @IsTest
    static void testAnalyze_inactiveTemplate_reducedScore() {
        Weave_Template_Config__c t = makeTemplate('Draft T', 'Draft', 'Salesforce Email');
        makeComponent(t.Id, 'Body', '<p>Hello {{Parent.Name}}</p>');

        Test.startTest();
        List<LegacyTemplateAnalyzer.AnalysisResult> results =
            LegacyTemplateAnalyzer.analyzeByIds(new List<Id>{ t.Id });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(results[0].readinessScore < 100, 'Inactive template score should be reduced');
        System.assert(!results[0].issues.isEmpty(), 'Should have issue about inactive status');
    }

    // ── analyze: no body component ────────────────────────────────────────────

    @IsTest
    static void testAnalyze_noBodyComponent_reducedScore() {
        Weave_Template_Config__c t = makeTemplate('No Body', 'Active', 'Salesforce Email');

        Test.startTest();
        List<LegacyTemplateAnalyzer.AnalysisResult> results =
            LegacyTemplateAnalyzer.analyzeByIds(new List<Id>{ t.Id });
        Test.stopTest();

        System.assertEquals(1, results.size());
        Boolean hasBodyIssue = false;
        for (String issue : results[0].issues) {
            if (issue.containsIgnoreCase('Body')) hasBodyIssue = true;
        }
        System.assert(hasBodyIssue, 'Should flag missing body component');
    }

    // ── analyze: script tag detection ────────────────────────────────────────

    @IsTest
    static void testAnalyze_scriptTagInHtml_warning() {
        Weave_Template_Config__c t = makeTemplate('Script T', 'Active', 'Salesforce Email');
        makeComponent(t.Id, 'Body', '<p>Hello</p><script>alert(1)</script>');

        Test.startTest();
        List<LegacyTemplateAnalyzer.AnalysisResult> results =
            LegacyTemplateAnalyzer.analyzeByIds(new List<Id>{ t.Id });
        Test.stopTest();

        Boolean hasScriptWarning = false;
        for (String w : results[0].warnings) {
            if (w.containsIgnoreCase('script')) hasScriptWarning = true;
        }
        System.assert(hasScriptWarning, 'Should warn about <script> tag');
    }

    // ── analyze: Section merge tag detection ──────────────────────────────────

    @IsTest
    static void testAnalyze_sectionMergeTag_warning() {
        Weave_Template_Config__c t = makeTemplate('Section T', 'Active', 'Salesforce Email');
        makeComponent(t.Id, 'Body', '<p>{{Section.RelatedContacts}}</p>');

        Test.startTest();
        List<LegacyTemplateAnalyzer.AnalysisResult> results =
            LegacyTemplateAnalyzer.analyzeByIds(new List<Id>{ t.Id });
        Test.stopTest();

        Boolean hasSectionWarning = false;
        for (String w : results[0].warnings) {
            if (w.containsIgnoreCase('Section')) hasSectionWarning = true;
        }
        System.assert(hasSectionWarning, 'Should warn about Section merge tag');
    }

    // ── getMigrationCandidates ────────────────────────────────────────────────

    @IsTest
    static void testGetMigrationCandidates_returnsHighScoreOnly() {
        Weave_Template_Config__c good = makeTemplate('Good Template', 'Active', 'Salesforce Email');
        makeComponent(good.Id, 'Body', '<p>Hello {{Parent.Name}}</p>');

        Weave_Template_Config__c bad = makeTemplate('Bad Template', 'Draft', 'Salesforce Email');

        Test.startTest();
        List<LegacyTemplateAnalyzer.AnalysisResult> candidates =
            LegacyTemplateAnalyzer.getMigrationCandidates();
        Test.stopTest();

        for (LegacyTemplateAnalyzer.AnalysisResult r : candidates) {
            System.assert(r.readinessScore >= 70, 'All candidates must score >= 70');
        }
    }

    // ── analyzeByIds: empty list ──────────────────────────────────────────────

    @IsTest
    static void testAnalyzeByIds_emptyList() {
        Test.startTest();
        List<LegacyTemplateAnalyzer.AnalysisResult> results =
            LegacyTemplateAnalyzer.analyzeByIds(new List<Id>());
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Empty list should return empty results');
    }
}
