@SuppressWarnings('PMD.MethodNamingConventions,PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest
private class MigrationReportTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static LegacyTemplateAnalyzer.AnalysisResult makeAnalysis(
        String recommendation, Integer score, String channel
    ) {
        LegacyTemplateAnalyzer.AnalysisResult r = new LegacyTemplateAnalyzer.AnalysisResult();
        r.templateId     = UserInfo.getUserId(); // placeholder ID
        r.templateName   = 'Template ' + score;
        r.currentChannel = channel;
        r.status         = 'Active';
        r.readinessScore = score;
        r.recommendation = recommendation;
        return r;
    }

    // ── buildSummary ──────────────────────────────────────────────────────────

    @IsTest
    static void testBuildSummary_counts() {
        List<LegacyTemplateAnalyzer.AnalysisResult> results = new List<LegacyTemplateAnalyzer.AnalysisResult>{
            makeAnalysis('Migrate', 90, 'Salesforce Email'),
            makeAnalysis('Migrate', 80, 'Salesforce Email'),
            makeAnalysis('Skip', 100, 'All Channels'),
            makeAnalysis('Manual Review', 65, 'Salesforce Email'),
            makeAnalysis('Skip', 30, 'Salesforce Email')
        };

        Test.startTest();
        MigrationReport.ReportSummary s = MigrationReport.buildSummary(results);
        Test.stopTest();

        System.assertEquals(5, s.totalTemplates);
        System.assertEquals(2, s.readyToMigrate);
        System.assertEquals(1, s.alreadyMigrated);
        System.assertEquals(1, s.needManualReview);
        System.assertEquals(1, s.skip);
        System.assert(s.avgReadinessScore > 0, 'Average score should be > 0');
    }

    @IsTest
    static void testBuildSummary_empty() {
        Test.startTest();
        MigrationReport.ReportSummary s =
            MigrationReport.buildSummary(new List<LegacyTemplateAnalyzer.AnalysisResult>());
        Test.stopTest();

        System.assertEquals(0, s.totalTemplates);
        System.assertEquals(0, s.avgReadinessScore);
    }

    // ── generateAnalysisCsv ───────────────────────────────────────────────────

    @IsTest
    static void testGenerateAnalysisCsv_hasHeader() {
        List<LegacyTemplateAnalyzer.AnalysisResult> results = new List<LegacyTemplateAnalyzer.AnalysisResult>{
            makeAnalysis('Migrate', 90, 'Salesforce Email')
        };
        results[0].issues.add('Issue one');
        results[0].warnings.add('Warning one');

        Test.startTest();
        String csv = MigrationReport.generateAnalysisCsv(results);
        Test.stopTest();

        System.assert(csv.startsWith('Template ID'), 'CSV must start with header row');
        System.assert(csv.containsIgnoreCase('Template Name'), 'CSV must contain column names');
        System.assert(csv.containsIgnoreCase('Issue one'), 'CSV must contain issue text');
        System.assert(csv.containsIgnoreCase('Warning one'), 'CSV must contain warning text');
    }

    @IsTest
    static void testGenerateAnalysisCsv_escapesCommasInValues() {
        LegacyTemplateAnalyzer.AnalysisResult r = makeAnalysis('Migrate', 90, 'Salesforce Email');
        r.issues.add('Issue with, comma inside');

        Test.startTest();
        String csv = MigrationReport.generateAnalysisCsv(
            new List<LegacyTemplateAnalyzer.AnalysisResult>{ r }
        );
        Test.stopTest();

        System.assert(csv.contains('"Issue with, comma inside"'),
            'Values with commas should be quoted');
    }

    // ── generateMigrationCsv ──────────────────────────────────────────────────

    @IsTest
    static void testGenerateMigrationCsv_hasHeader() {
        LegacyTemplateMigrator.MigrationSummary summary = new LegacyTemplateMigrator.MigrationSummary();
        LegacyTemplateMigrator.MigrationItemResult item = new LegacyTemplateMigrator.MigrationItemResult();
        item.templateId      = UserInfo.getUserId();
        item.templateName    = 'Test Template';
        item.previousChannel = 'Salesforce Email';
        item.newChannel      = 'All Channels';
        item.isSuccess       = true;
        item.wasSkipped      = false;
        summary.items.add(item);

        Test.startTest();
        String csv = MigrationReport.generateMigrationCsv(summary);
        Test.stopTest();

        System.assert(csv.startsWith('Template ID'), 'CSV must start with header');
        System.assert(csv.containsIgnoreCase('All Channels'), 'CSV should include new channel');
    }
}
