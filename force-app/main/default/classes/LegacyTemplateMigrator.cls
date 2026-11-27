/**
 * Migrates Weave email templates to Marketing Cloud Next channels.
 *
 * Migration steps per template:
 *   1. Run LegacyTemplateAnalyzer — skip templates with score < 70
 *   2. Update Template_Channels__c to 'All Channels'
 *   3. Write Weave_MCN_Sync_Log__c with Publish_Type__c='Migration',
 *      storing previous channel in MCN_Asset_ID__c for rollback
 *
 * Usage:
 *   LegacyTemplateMigrator.MigrationSummary summary =
 *       LegacyTemplateMigrator.migrateToMCN(templateIds);
 */
@SuppressWarnings('PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.ApexDoc')
public with sharing class LegacyTemplateMigrator {

    public static final String CHANNEL_MCN  = 'All Channels';
    public static final String LOG_TYPE     = 'Migration';
    public static final String ROLLBACK_PREFIX = 'PREV_CHANNEL:';

    // ── DTOs ──────────────────────────────────────────────────────────────────

    public class MigrationItemResult {
        @AuraEnabled public Id      templateId       { get; set; }
        @AuraEnabled public String  templateName     { get; set; }
        @AuraEnabled public Boolean isSuccess        { get; set; }
        @AuraEnabled public String  errorMessage     { get; set; }
        @AuraEnabled public String  previousChannel  { get; set; }
        @AuraEnabled public String  newChannel       { get; set; }
        @AuraEnabled public Boolean wasSkipped       { get; set; }
        @AuraEnabled public String  skipReason       { get; set; }
    }

    public class MigrationSummary {
        @AuraEnabled public Integer total    { get; set; }
        @AuraEnabled public Integer migrated { get; set; }
        @AuraEnabled public Integer skipped  { get; set; }
        @AuraEnabled public Integer errors   { get; set; }
        @AuraEnabled public List<MigrationItemResult> items { get; set; }

        public MigrationSummary() {
            this.total    = 0;
            this.migrated = 0;
            this.skipped  = 0;
            this.errors   = 0;
            this.items    = new List<MigrationItemResult>();
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Bulk-migrates templates to MCN channel. Max 200 IDs per call to stay within
     * governor limits; use MCNMigrationBatch for larger sets.
     */
    public static MigrationSummary migrateToMCN(List<Id> templateIds) {
        if (templateIds == null || templateIds.isEmpty()) {
            return new MigrationSummary();
        }

        Map<Id, LegacyTemplateAnalyzer.AnalysisResult> analysisMap = buildAnalysisMap(templateIds);

        List<Weave_Template_Config__c> templates = [
            SELECT Id, Name, Template_Channels__c, Status__c
            FROM   Weave_Template_Config__c
            WHERE  Id IN :templateIds
            WITH   USER_MODE
        ];

        MigrationSummary summary = new MigrationSummary();
        List<Weave_Template_Config__c> toUpdate = new List<Weave_Template_Config__c>();
        List<Weave_MCN_Sync_Log__c>    logs     = new List<Weave_MCN_Sync_Log__c>();

        for (Weave_Template_Config__c t : templates) {
            summary.total++;
            MigrationItemResult item = buildItem(t);

            LegacyTemplateAnalyzer.AnalysisResult analysis = analysisMap.get(t.Id);

            if (analysis == null || analysis.readinessScore < 70) {
                item.wasSkipped = true;
                item.skipReason = analysis != null
                    ? 'Readiness score ' + analysis.readinessScore + '/100 — below 70 threshold.'
                    : 'Analysis unavailable.';
                summary.skipped++;
                summary.items.add(item);
                continue;
            }

            if (t.Template_Channels__c == CHANNEL_MCN) {
                item.wasSkipped = true;
                item.skipReason = 'Already configured for All Channels.';
                summary.skipped++;
                summary.items.add(item);
                continue;
            }

            toUpdate.add(new Weave_Template_Config__c(
                Id                   = t.Id,
                Template_Channels__c = CHANNEL_MCN
            ));
            item.isSuccess  = true;
            item.newChannel = CHANNEL_MCN;
            summary.migrated++;
            summary.items.add(item);

            // Store previous channel in MCN_Asset_ID__c for rollback capability
            logs.add(new Weave_MCN_Sync_Log__c(
                Template__c    = t.Id,
                Publish_Type__c = LOG_TYPE,
                Status__c      = 'Success',
                MCN_Asset_ID__c = ROLLBACK_PREFIX + t.Template_Channels__c,
                Error_Message__c = 'Migrated from "' + t.Template_Channels__c + '" to "' + CHANNEL_MCN + '"'
            ));
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false);
            reprocessSaveErrors(saveResults, toUpdate, summary);
        }

        if (!logs.isEmpty()) {
            Database.insert(logs, false);
        }

        return summary;
    }

    /**
     * Rolls back a previous migration by reading the most recent migration log
     * for each template and restoring the previous channel.
     */
    public static MigrationSummary rollback(List<Id> templateIds) {
        if (templateIds == null || templateIds.isEmpty()) {
            return new MigrationSummary();
        }

        Map<Id, String> prevChannels = loadPreviousChannels(templateIds);

        MigrationSummary summary = new MigrationSummary();
        List<Weave_Template_Config__c> toUpdate = new List<Weave_Template_Config__c>();

        for (Id tId : templateIds) {
            summary.total++;
            MigrationItemResult item = new MigrationItemResult();
            item.templateId = tId;

            String prevChannel = prevChannels.get(tId);
            if (String.isBlank(prevChannel)) {
                item.wasSkipped = true;
                item.skipReason = 'No migration log found — cannot roll back.';
                summary.skipped++;
                summary.items.add(item);
                continue;
            }

            toUpdate.add(new Weave_Template_Config__c(
                Id                   = tId,
                Template_Channels__c = prevChannel
            ));
            item.isSuccess       = true;
            item.newChannel      = prevChannel;
            item.previousChannel = CHANNEL_MCN;
            summary.migrated++;
            summary.items.add(item);
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false);
            reprocessSaveErrors(saveResults, toUpdate, summary);
        }

        return summary;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Map<Id, LegacyTemplateAnalyzer.AnalysisResult> buildAnalysisMap(List<Id> ids) {
        Map<Id, LegacyTemplateAnalyzer.AnalysisResult> m = new Map<Id, LegacyTemplateAnalyzer.AnalysisResult>();
        for (LegacyTemplateAnalyzer.AnalysisResult a : LegacyTemplateAnalyzer.analyzeByIds(ids)) {
            m.put(a.templateId, a);
        }
        return m;
    }

    private static MigrationItemResult buildItem(Weave_Template_Config__c t) {
        MigrationItemResult item = new MigrationItemResult();
        item.templateId      = t.Id;
        item.templateName    = t.Name;
        item.previousChannel = t.Template_Channels__c;
        item.isSuccess       = false;
        item.wasSkipped      = false;
        return item;
    }

    private static Map<Id, String> loadPreviousChannels(List<Id> templateIds) {
        Map<Id, String> result = new Map<Id, String>();
        for (Weave_MCN_Sync_Log__c log : [
            SELECT Id, Template__c, MCN_Asset_ID__c, CreatedDate
            FROM   Weave_MCN_Sync_Log__c
            WHERE  Template__c IN :templateIds
              AND  Publish_Type__c = :LOG_TYPE
              AND  Status__c = 'Success'
            WITH   USER_MODE
            ORDER  BY CreatedDate DESC
        ]) {
            if (!result.containsKey(log.Template__c) && log.MCN_Asset_ID__c != null
                && log.MCN_Asset_ID__c.startsWith(ROLLBACK_PREFIX)) {
                result.put(log.Template__c,
                    log.MCN_Asset_ID__c.removeStart(ROLLBACK_PREFIX));
            }
        }
        return result;
    }

    private static void reprocessSaveErrors(
        List<Database.SaveResult> results,
        List<Weave_Template_Config__c> updated,
        MigrationSummary summary
    ) {
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                Id failedId = updated[i].Id;
                for (MigrationItemResult item : summary.items) {
                    if (item.templateId == failedId && item.isSuccess == true) {
                        item.isSuccess    = false;
                        item.errorMessage = results[i].getErrors()[0].getMessage();
                        summary.migrated--;
                        summary.errors++;
                        break;
                    }
                }
            }
        }
    }
}
