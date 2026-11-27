@SuppressWarnings('PMD.MethodNamingConventions')
@IsTest
private class LegacyTemplateMigratorTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Weave_Template_Config__c makeActiveTemplate(String name) {
        Weave_Template_Config__c t = new Weave_Template_Config__c(
            Name                      = name,
            Status__c                 = 'Active',
            Template_Channels__c      = 'Salesforce Email',
            Parent_Object_API_Name__c = 'Contact',
            Subject_Template__c       = 'Hello {{Parent.FirstName}}'
        );
        insert t;
        // Add body component so analyzer scores it high enough
        insert new Weave_Template_Component__c(
            Name                     = 'Body',
            Weave_Template_Config__c = t.Id,
            Region__c                = 'Body',
            HTML_Output__c           = '<p>Hello {{Parent.Name}}</p>',
            Display_Order__c         = 1
        );
        return t;
    }

    private static Weave_Template_Config__c makeDraftTemplate(String name) {
        Weave_Template_Config__c t = new Weave_Template_Config__c(
            Name                      = name,
            Status__c                 = 'Draft',
            Template_Channels__c      = 'Salesforce Email',
            Parent_Object_API_Name__c = 'Contact',
            Subject_Template__c       = 'Draft subject'
        );
        insert t;
        return t;
    }

    // ── migrateToMCN: success path ────────────────────────────────────────────

    @IsTest
    static void testMigrateToMCN_success() {
        Weave_Template_Config__c t = makeActiveTemplate('Active Template');

        Test.startTest();
        LegacyTemplateMigrator.MigrationSummary summary =
            LegacyTemplateMigrator.migrateToMCN(new List<Id>{ t.Id });
        Test.stopTest();

        System.assertEquals(1, summary.total);
        System.assertEquals(1, summary.migrated, 'Active template with body should migrate');
        System.assertEquals(0, summary.errors);

        Weave_Template_Config__c updated = [
            SELECT Template_Channels__c FROM Weave_Template_Config__c WHERE Id = :t.Id
        ];
        System.assertEquals(LegacyTemplateMigrator.CHANNEL_MCN, updated.Template_Channels__c,
            'Template_Channels__c should be updated to All Channels');
    }

    // ── migrateToMCN: skip draft template ────────────────────────────────────

    @IsTest
    static void testMigrateToMCN_skipsDraftTemplate() {
        Weave_Template_Config__c t = makeDraftTemplate('Draft Template');

        Test.startTest();
        LegacyTemplateMigrator.MigrationSummary summary =
            LegacyTemplateMigrator.migrateToMCN(new List<Id>{ t.Id });
        Test.stopTest();

        System.assertEquals(1, summary.total);
        System.assertEquals(1, summary.skipped, 'Draft template should be skipped');
        System.assertEquals(0, summary.migrated);
    }

    // ── migrateToMCN: skip already-MCN template ───────────────────────────────

    @IsTest
    static void testMigrateToMCN_skipsAlreadyMigrated() {
        Weave_Template_Config__c t = makeActiveTemplate('Already MCN');
        update new Weave_Template_Config__c(
            Id = t.Id, Template_Channels__c = 'All Channels'
        );

        Test.startTest();
        LegacyTemplateMigrator.MigrationSummary summary =
            LegacyTemplateMigrator.migrateToMCN(new List<Id>{ t.Id });
        Test.stopTest();

        System.assertEquals(1, summary.skipped, 'Already-MCN template should be skipped');
    }

    // ── migrateToMCN: bulk (3 templates) ─────────────────────────────────────

    @IsTest
    static void testMigrateToMCN_bulk() {
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < 3; i++) {
            ids.add(makeActiveTemplate('Bulk Template ' + i).Id);
        }

        Test.startTest();
        LegacyTemplateMigrator.MigrationSummary summary =
            LegacyTemplateMigrator.migrateToMCN(ids);
        Test.stopTest();

        System.assertEquals(3, summary.total);
        System.assert(summary.migrated > 0, 'Should migrate at least some templates');
        System.assertEquals(0, summary.errors);
    }

    // ── migrateToMCN: empty list ──────────────────────────────────────────────

    @IsTest
    static void testMigrateToMCN_emptyList() {
        Test.startTest();
        LegacyTemplateMigrator.MigrationSummary summary =
            LegacyTemplateMigrator.migrateToMCN(new List<Id>());
        Test.stopTest();

        System.assertEquals(0, summary.total);
    }

    // ── rollback ──────────────────────────────────────────────────────────────

    @IsTest
    static void testRollback_success() {
        Weave_Template_Config__c t = makeActiveTemplate('Rollback Template');

        // Migrate first
        LegacyTemplateMigrator.migrateToMCN(new List<Id>{ t.Id });

        Test.startTest();
        LegacyTemplateMigrator.MigrationSummary rollbackSummary =
            LegacyTemplateMigrator.rollback(new List<Id>{ t.Id });
        Test.stopTest();

        System.assertEquals(1, rollbackSummary.total);
        System.assertEquals(1, rollbackSummary.migrated, 'Rollback should succeed');

        Weave_Template_Config__c reverted = [
            SELECT Template_Channels__c FROM Weave_Template_Config__c WHERE Id = :t.Id
        ];
        System.assertEquals('Salesforce Email', reverted.Template_Channels__c,
            'Should revert to original channel');
    }

    // ── rollback: no migration log ────────────────────────────────────────────

    @IsTest
    static void testRollback_noLog_skips() {
        Weave_Template_Config__c t = makeActiveTemplate('No Log Template');

        Test.startTest();
        LegacyTemplateMigrator.MigrationSummary summary =
            LegacyTemplateMigrator.rollback(new List<Id>{ t.Id });
        Test.stopTest();

        System.assertEquals(1, summary.skipped, 'No log should result in skip');
    }
}
