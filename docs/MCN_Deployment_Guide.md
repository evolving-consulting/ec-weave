# MCN Integration — Production Deployment Guide

**Project:** EC Weave + Marketing Cloud Next  
**Version:** Phase 6  
**Last Updated:** 2026-11-25

---

## Pre-Flight Checklist

Before deploying to production, verify every item below in your **full sandbox**:

### Org Configuration
- [ ] Named Credential `MCN_API` configured and tested
- [ ] Remote Site Setting for MCN API endpoint added
- [ ] Custom Metadata `MCN_Config__mdt` populated with connector settings
- [ ] Platform Cache partition `MCNCache` created (if using Platform Cache)
- [ ] Email deliverability set to **All Email** in production
- [ ] Org-Wide Email Address configured for Weave sends

### Permissions
- [ ] `Weave_Builder_Access` permission set assigned to all admins
- [ ] `Weave_User` permission set assigned to all end users
- [ ] Custom permission `Weave_Manage_Templates` verified on `Weave_Builder_Access`
- [ ] MCN platform event `MCN_Integration_Event__e` subscriber permissions granted

### Named Credentials & Authentication
- [ ] `MCN_API` named credential points to production MCN endpoint
- [ ] OAuth tokens renewed in production org
- [ ] Auth provider configured (if using OAuth JWT flow)
- [ ] Certificate uploaded (if using certificate-based auth)

---

## Phased Deployment Strategy

### Step 1: Phase 1 Objects & Classes
**Components:** Custom objects, fields, `SfmcHttpClient`, `WeaveMarketingCloudNextAdapter`

```
sf project deploy start --source-dir force-app/main/default/objects
sf project deploy start --source-dir force-app/main/default/classes/SfmcHttpClient.cls
sf project deploy start --source-dir force-app/main/default/classes/WeaveMarketingCloudNextAdapter.cls
```

**Post-deploy validation:**
- Run `SfmcHttpClientTest` — all assertions pass
- Confirm custom objects visible in Setup > Object Manager

---

### Step 2: Phase 2 UI Components
**Components:** `weaveTemplateBuilder` LWC, `weaveEmailComposer` LWC, supporting sub-components

```
sf project deploy start --source-dir force-app/main/default/lwc/weaveTemplateBuilder
sf project deploy start --source-dir force-app/main/default/lwc/weaveEmailComposer
```

**Post-deploy validation:**
- Open Weave app in sandbox
- Create a test template — confirm all builder steps render
- Confirm Email Composer opens on a Contact record

---

### Step 3: Phase 3 Publisher
**Components:** `SfmcTemplatePublisher`, `MergeFieldTranslator`, `SfmcMappingValidator`, `SfmcTemplateConflictDetector`, `McnTemplatePublisherController`

```
sf project deploy start --source-dir force-app/main/default/classes/SfmcTemplatePublisher.cls
```

**Post-deploy validation:**
- Run `SfmcTemplatePublisherTest` — all pass
- Publish a test template from the builder; confirm MCN asset ID populates

---

### Step 4: Phase 4 Sender
**Components:** `MCNEmailSendService`, `MCNTemplateRenderService`, `MCNFlowActionAdapter`

```
sf project deploy start --source-dir force-app/main/default/classes/MCNEmailSendService.cls
sf project deploy start --source-dir force-app/main/default/classes/MCNTemplateRenderService.cls
```

**Post-deploy validation:**
- Send a test email from Email Composer → MCN channel
- Confirm `Weave_MCN_Email_Send__c` record created with Status = Sent
- Check MCN delivery report for test send

---

### Step 5: Phase 5 Advanced Features
**Components:** `WeaveMarketingCloudNextAdapter` extensions, advanced analytics, merge field helpers

**Post-deploy validation:**
- Run all Phase 5 test classes
- Verify Data360 connector sync in `Weave_MCN_Sync_Log__c`

---

### Step 6: Legacy Template Migration
**Components:** `LegacyTemplateAnalyzer`, `LegacyTemplateMigrator`, `MigrationReport`, `legacyTemplateMigration` LWC

```
sf project deploy start --source-dir force-app/main/default/classes/LegacyTemplateAnalyzer.cls
sf project deploy start --source-dir force-app/main/default/classes/LegacyTemplateMigrator.cls
sf project deploy start --source-dir force-app/main/default/classes/MigrationReport.cls
sf project deploy start --source-dir force-app/main/default/lwc/legacyTemplateMigration
```

**Post-deploy steps:**
1. Open Legacy Template Migration tab (Weave app)
2. Click **Analyze Templates** — review readiness scores
3. Migrate templates scored ≥ 70 in batches of 25
4. Verify `Template_Channels__c` updated to `All Channels` on migrated records

---

### Step 7: Monitoring & Alerting
**Components:** `MCN_Integration_Event__e`, `MCNHealthMonitorScheduler`, `MCNDailyCacheRefreshBatch`, `mcnHealthDashboard` LWC

```
sf project deploy start --source-dir force-app/main/default/objects/MCN_Integration_Event__e
sf project deploy start --source-dir force-app/main/default/classes/MCNHealthMonitorScheduler.cls
sf project deploy start --source-dir force-app/main/default/classes/MCNDailyCacheRefreshBatch.cls
sf project deploy start --source-dir force-app/main/default/lwc/mcnHealthDashboard
```

**Post-deploy steps:**
Run in Anonymous Apex:
```apex
// Schedule hourly health monitor
MCNHealthMonitorScheduler.scheduleHourly();

// Schedule nightly cache refresh (11pm UTC)
System.schedule('MCN Daily Cache Refresh', '0 0 23 * * ?',
    new System.SchedulableContext() {
        public void execute(SchedulableContext ctx) {
            MCNDailyCacheRefreshBatch.scheduleNightly();
        }
    }
);
```

---

## Rollback Procedure

If a critical issue is found in production, disable MCN integration with these steps:

### Option A: Disable MCN channel on templates (non-destructive)
```apex
// Revert all templates to Salesforce Email
List<Weave_Template_Config__c> templates = [
    SELECT Id, Template_Channels__c FROM Weave_Template_Config__c
    WHERE Template_Channels__c = 'All Channels'
];
for (Weave_Template_Config__c t : templates) {
    t.Template_Channels__c = 'Salesforce Email';
}
update templates;
```

### Option B: Use LegacyTemplateMigrator.rollback()
```apex
List<Id> migratedIds = new List<Id>(); // populate from your migration log
LegacyTemplateMigrator.MigrationSummary result =
    LegacyTemplateMigrator.rollback(migratedIds);
System.debug(result.migrated + ' templates rolled back');
```

### Option C: Full component removal
1. Deactivate `MCN Health Monitor` scheduled job in Setup > Apex Jobs
2. Delete `MCN Daily Cache Refresh` scheduled job
3. Remove `MCN_Integration_Event__e` subscriber triggers
4. Uninstall Phase 6 change set (if change sets were used)

---

## Post-Deployment Validation

After production deployment, complete within 48 hours:

- [ ] Send 5 test emails via MCN to internal addresses — confirm delivery
- [ ] Check `Weave_MCN_Email_Send__c` — all records show `Status = Sent`
- [ ] Open MCN Health Dashboard — confirm green health banner
- [ ] Verify hourly health monitor is running in Setup > Scheduled Jobs
- [ ] Trigger a test alert by temporarily setting `ERROR_THRESHOLD_PCT = 0` in anonymous Apex
- [ ] Check admin email inbox for alert delivery
- [ ] Restore threshold to 5%

---

## Troubleshooting

| Symptom | Root Cause | Resolution |
|---------|-----------|-----------|
| `CalloutException: Unauthorized` | Named Credential token expired | Refresh OAuth token; re-authenticate Named Credential |
| `System.LimitException: Too many callouts` | Multiple sends in one transaction | Use `MCNEmailSendService` with async dispatch pattern |
| Health Dashboard shows no data | `MCN_Integration_Event__e` not deployed | Deploy Phase 7 components first |
| Migration shows all templates as Skip | Templates are Draft | Activate templates before running migration |
| `FIELD_CUSTOM_VALIDATION_EXCEPTION` on update | Validation rules blocking channel change | Temporarily bypass or update validation rules for migration |
| Alert email not delivered | Email deliverability set to System Only | Set to All Email in production org settings |

---

## Change Set Structure

| Change Set | Contains |
|-----------|----------|
| `MCN-Phase-1` | Custom objects, SfmcHttpClient, Adapter |
| `MCN-Phase-2` | LWC builder/composer components |
| `MCN-Phase-3` | Publisher, validator, conflict detector |
| `MCN-Phase-4` | Sender, renderer, flow action |
| `MCN-Phase-5` | Advanced features, analytics |
| `MCN-Phase-6` | Migration toolkit, monitoring, caching |

**Change Set Dependencies:** Each set depends on the previous. Never skip phases.
