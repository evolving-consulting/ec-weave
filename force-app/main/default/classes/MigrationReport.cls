/**
 * Generates migration analysis and status reports in CSV format.
 * Accepts results from LegacyTemplateAnalyzer or LegacyTemplateMigrator.
 *
 * Usage:
 *   String csv = MigrationReport.generateAnalysisCsv(analysisResults);
 *   String csv = MigrationReport.generateMigrationCsv(migrationSummary);
 *   MigrationReport.ReportSummary s = MigrationReport.buildSummary(analyses);
 */
public with sharing class MigrationReport {

    // ── DTOs ──────────────────────────────────────────────────────────────────

    public class ReportSummary {
        @AuraEnabled public Integer totalTemplates    { get; set; }
        @AuraEnabled public Integer readyToMigrate    { get; set; }
        @AuraEnabled public Integer alreadyMigrated  { get; set; }
        @AuraEnabled public Integer needManualReview { get; set; }
        @AuraEnabled public Integer skip             { get; set; }
        @AuraEnabled public Decimal avgReadinessScore { get; set; }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    public static ReportSummary buildSummary(List<LegacyTemplateAnalyzer.AnalysisResult> results) {
        ReportSummary s = new ReportSummary();
        s.totalTemplates   = results.size();
        s.readyToMigrate   = 0;
        s.alreadyMigrated  = 0;
        s.needManualReview = 0;
        s.skip             = 0;
        Decimal totalScore = 0;

        for (LegacyTemplateAnalyzer.AnalysisResult r : results) {
            totalScore += r.readinessScore;
            if (r.recommendation == 'Migrate') {
                s.readyToMigrate++;
            } else if (r.recommendation == 'Skip' && r.currentChannel == 'All Channels') {
                s.alreadyMigrated++;
            } else if (r.recommendation == 'Manual Review') {
                s.needManualReview++;
            } else {
                s.skip++;
            }
        }

        s.avgReadinessScore = results.isEmpty() ? 0 :
            (totalScore / results.size()).setScale(1);

        return s;
    }

    /**
     * Generates a CSV report from LegacyTemplateAnalyzer results.
     */
    public static String generateAnalysisCsv(List<LegacyTemplateAnalyzer.AnalysisResult> results) {
        List<String> lines = new List<String>();
        lines.add(csvRow(new List<String>{
            'Template ID', 'Template Name', 'Current Channel',
            'Status', 'Readiness Score', 'Recommendation',
            'Issues', 'Warnings'
        }));

        for (LegacyTemplateAnalyzer.AnalysisResult r : results) {
            lines.add(csvRow(new List<String>{
                String.valueOf(r.templateId),
                r.templateName,
                nvl(r.currentChannel),
                nvl(r.status),
                String.valueOf(r.readinessScore),
                nvl(r.recommendation),
                String.join(r.issues, '; '),
                String.join(r.warnings, '; ')
            }));
        }
        return String.join(lines, '\n');
    }

    /**
     * Generates a CSV report from a LegacyTemplateMigrator summary.
     */
    public static String generateMigrationCsv(LegacyTemplateMigrator.MigrationSummary summary) {
        List<String> lines = new List<String>();
        lines.add(csvRow(new List<String>{
            'Template ID', 'Template Name', 'Previous Channel',
            'New Channel', 'Success', 'Skipped', 'Skip Reason', 'Error'
        }));

        for (LegacyTemplateMigrator.MigrationItemResult item : summary.items) {
            lines.add(csvRow(new List<String>{
                String.valueOf(item.templateId),
                nvl(item.templateName),
                nvl(item.previousChannel),
                nvl(item.newChannel),
                item.isSuccess == true ? 'Yes' : 'No',
                item.wasSkipped == true ? 'Yes' : 'No',
                nvl(item.skipReason),
                nvl(item.errorMessage)
            }));
        }
        return String.join(lines, '\n');
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static String csvRow(List<String> cells) {
        List<String> escaped = new List<String>();
        for (String cell : cells) {
            String s = cell == null ? '' : cell;
            if (s.contains(',') || s.contains('"') || s.contains('\n')) {
                s = '"' + s.replace('"', '""') + '"';
            }
            escaped.add(s);
        }
        return String.join(escaped, ',');
    }

    private static String nvl(String s) {
        return s == null ? '' : s;
    }
}
