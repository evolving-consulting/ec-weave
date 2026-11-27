# MCN Integration — User Training Guide

**Project:** EC Weave + Marketing Cloud Next  
**Version:** Phase 6  
**Last Updated:** 2026-11-25

---

## For Salesforce Administrators

### 1. Overview

The MCN integration extends EC Weave to deliver emails via Marketing Cloud Next (MCN) in addition to Salesforce standard email. MCN provides enterprise-grade deliverability, real-time analytics, and Data Cloud merge field support.

### 2. Configuring a New MCN Template

**Prerequisites:** `Weave_Builder_Access` permission set assigned.

1. Open the **Weave** app in Salesforce.
2. Click the **Templates** tab → **New Template**.
3. Fill in:
   - **Template Name** — unique, descriptive name
   - **Parent Object** — the SObject the template runs against (e.g., `Contact`)
   - **Template Channels** — select **All Channels** to enable MCN
   - **Brand** — select the brand kit for header/footer styling
4. Click **Next** to open the builder.
5. Add components:
   - **Header** — typically logo and greeting
   - **Body** — main email content with merge fields
   - **Footer** — unsubscribe link, legal text
6. Use merge tag syntax:
   - `{{Parent.FieldName}}` for parent record fields
   - `{{DataCloud.Object.Field}}` for Data Cloud attributes
7. Click **Preview** to verify rendering.
8. Click **Publish to MCN** — the template is pushed to Marketing Cloud Next.
9. Confirm **SFMC Publish Status** = `Published` on the template record.

---

### 3. Managing Template Versions

- Each publish creates a new MCN asset version. The active version is tracked via `SFMC_Template_ID__c`.
- To roll back: use the **Conflict Detection** view in the builder to compare versions.
- Republishing with changed HTML updates the MCN asset in place.

---

### 4. Running the Legacy Template Migration

Use this tool to upgrade existing Salesforce Email templates to also support MCN delivery.

1. Open the **Weave** app → **Migration** tab.
2. Click **Analyze Templates** — review the readiness score for each template.
3. Review recommendations:
   - **Migrate** (score ≥ 70) — safe to migrate automatically
   - **Manual Review** — has warnings; review issues before migrating
   - **Skip** — not suitable for MCN (Draft, no body, etc.)
4. Select templates with **Migrate** status → Click **Migrate Selected**.
5. Confirm in the results panel: check migrated count and any errors.
6. If a migration introduced issues, click **Rollback** to restore original settings.

**Export:** Click **Export CSV** to download a full analysis report for stakeholder review.

---

### 5. Configuring the MCN Connector

1. Go to **Setup → Named Credentials**.
2. Find `MCN_API` → verify endpoint URL and authentication method.
3. Test connectivity: run in Anonymous Apex:
   ```apex
   SfmcHttpClient.testConnectivity();
   ```
4. If authentication fails: re-authenticate the named credential using the MCN OAuth client credentials.

---

### 6. Monitoring Integration Health

1. Open the **Weave** app → **Health Dashboard** tab.
2. The dashboard refreshes automatically on load; click **Refresh** for the latest data.
3. Green banner = healthy; Red/Orange banner = alert condition.
4. Review **Recent Errors** table for the 10 latest failures.
5. Alert emails are sent automatically when error rate exceeds 5% in a 1-hour window.

**Scheduled jobs to verify in Setup → Apex Jobs:**
- `MCN Health Monitor` — runs hourly
- `MCN Daily Cache Refresh` — runs nightly at 11pm UTC

---

## For End Users

### Sending an Email via MCN from Email Composer

**Prerequisites:** `Weave_User` permission set assigned.

1. Open any **Contact**, **Lead**, or supported record.
2. Find the **Weave Email Composer** component on the page layout.
3. Click **New Email**.
4. In the **Template** picker, select a template with **All Channels**.
5. The **Send Via** selector will show **Marketing Cloud Next** — confirm it's selected.
6. Review the recipient (pre-filled from the record) and add CC/BCC if needed.
7. Click **Preview** to see the rendered email before sending.
8. Click **Send** — the email is dispatched through MCN.
9. Confirm delivery: check the **Send Log** related list on the record.

**Scheduling a send:**
- Instead of clicking **Send**, click **Schedule** and pick a future date/time.
- The send will fire automatically at the scheduled time.
- To cancel: find the scheduled send in the **Scheduled Sends** related list → Delete.

---

### Reading Your Send Logs

1. Open the record (Contact, Lead, etc.).
2. Find the **MCN Send Logs** related list.
3. Each row shows: template name, send time, recipient, status (Sent / Failed).
4. Click a row to see the full send details and any error messages.

---

## For Developers

### Using the MCN Flow Action

The `WeaveSendEmailAction` invocable method is available in Flow Builder under the category **Dynamic Communication Engine**.

**Input variables:**
| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `templateId` | String | ✓ | ID of the `Weave_Template_Config__c` record |
| `recipientEmail` | String | ✓ | Recipient's email address |
| `contextDataJson` | String | | JSON string with `recordId`, `flowVariables`, `dataCloudValues` |

**Example Flow usage:**
1. Add a **Get Records** element to load the Contact.
2. Add an **Action** element → search for `Weave Send Email`.
3. Map `{!Contact.Id}` to `recordId` in the context JSON.
4. Map the template ID from a text variable or custom metadata.
5. Connect to your flow's success/failure paths using the `isSuccess` output variable.

**Context JSON format:**
```json
{
  "recordId": "003xxxxxxxxxxxx",
  "flowVariables": {
    "greeting": "Hello",
    "promoCode": "SAVE20"
  },
  "dataCloudValues": {
    "DataCloud.Contact__dlm.LTV__c": "1500"
  }
}
```

---

### Publishing Templates Programmatically

```apex
SfmcTemplatePublisher.PublishResult result =
    SfmcTemplatePublisher.publishTemplate(templateId);

if (result.isSuccess) {
    System.debug('MCN Asset ID: ' + result.mcnAssetId);
} else {
    System.debug('Error: ' + result.errorMessage);
}
```

---

### Subscribing to MCN Platform Events

To build custom integrations that react to MCN operations (send, publish, migrate, health check), subscribe to `MCN_Integration_Event__e`:

```apex
// In a trigger or EventBus subscriber
trigger MCNIntegrationEventTrigger on MCN_Integration_Event__e (after insert) {
    for (MCN_Integration_Event__e evt : Trigger.new) {
        if (evt.Status__c == 'Failed') {
            // Custom error handling
        }
    }
}
```

**Event fields:**
- `Operation__c` — Publish | Send | Migrate | Rollback | HealthCheck | CacheRefresh
- `Template_Id__c` — Salesforce template record ID
- `Status__c` — Success | Failed | Alert | Healthy | PartialFailure
- `Error_Message__c` — error detail on failure
- `Execution_Time_Ms__c` — wall-clock time in milliseconds

---

### Performance Guidelines

- Target send latency: 100–200ms per email
- Publish latency: 50–100ms
- Cache hit rate target: >80% for active templates
- Max batch size for migration: 200 templates per call
- Health monitor threshold: 5% error rate (configurable via `ERROR_THRESHOLD_PCT`)
