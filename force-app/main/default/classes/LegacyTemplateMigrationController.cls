/**
 * AuraEnabled controller backing the legacyTemplateMigration LWC.
 * Thin pass-through — all logic lives in the service classes.
 */
public with sharing class LegacyTemplateMigrationController {

    @AuraEnabled(cacheable=false)
    public static List<LegacyTemplateAnalyzer.AnalysisResult> analyzeAll() {
        try {
            return LegacyTemplateAnalyzer.analyzeAll();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static MigrationReport.ReportSummary buildSummary(
        List<LegacyTemplateAnalyzer.AnalysisResult> results
    ) {
        try {
            return MigrationReport.buildSummary(results);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static LegacyTemplateMigrator.MigrationSummary migrateToMCN(List<Id> templateIds) {
        try {
            return LegacyTemplateMigrator.migrateToMCN(templateIds);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static LegacyTemplateMigrator.MigrationSummary rollback(List<Id> templateIds) {
        try {
            return LegacyTemplateMigrator.rollback(templateIds);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static String generateAnalysisCsv(
        List<LegacyTemplateAnalyzer.AnalysisResult> results
    ) {
        try {
            return MigrationReport.generateAnalysisCsv(results);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
