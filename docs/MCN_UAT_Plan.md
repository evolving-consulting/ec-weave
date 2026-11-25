# MCN Integration — UAT Test Plan

**Project:** EC Weave + Marketing Cloud Next  
**Version:** Phase 6  
**Last Updated:** 2026-11-25  
**UAT Environment:** Full Sandbox  
**UAT Duration:** 2–3 weeks

---

## UAT Participants

| Role | Responsibility |
|------|---------------|
| Salesforce Admin | Configure templates, run migration, monitor health |
| End User | Send emails from Email Composer via MCN |
| Developer | Validate Flow integration, review logs |
| QA Lead | Execute all test scenarios, document results |

---

## Scenario Group 1: Template Creation & Publishing

| ID | Scenario | Steps | Expected Result | Pass/Fail |
|----|----------|-------|----------------|-----------|
| TC-01 | Create MCN template | Open Weave Builder → New Template → Set Channels = All Channels → Save | Template created with Status = Draft | |
| TC-02 | Add body component | Open template → Body tab → Add HTML component → Save | Component saved; preview renders HTML | |
| TC-03 | Configure merge fields | Add `{{Parent.Name}}` to subject → Preview | Subject shows resolved field value | |
| TC-04 | Publish template to MCN | Open template → Publish → Confirm | SFMC_Publish_Status = Published; MCN Asset ID populated | |
| TC-05 | Republish after edit | Edit component HTML → Publish again | MCN asset updated; Publish_Type = Update | |
| TC-06 | Publish with invalid merge field | Add `{{InvalidField}}` → Publish | Validation error shown; template not published | |

---

## Scenario Group 2: Send from Email Composer

| ID | Scenario | Steps | Expected Result | Pass/Fail |
|----|----------|-------|----------------|-----------|
| TC-07 | Select MCN template | Open Email Composer on Contact → Select template with All Channels | Template loads with MCN option available | |
| TC-08 | Send email via MCN | Select MCN template → Preview → Send | `Weave_MCN_Email_Send__c` created; delivery confirmed in MCN | |
| TC-09 | Schedule MCN send | Compose → Schedule for future date → Confirm | Scheduled send record created; fires at scheduled time | |
| TC-10 | Send with Data360 merge fields | Select template using `{{DataCloud.*}}` → Send | Data360 values resolved in sent email | |

---

## Scenario Group 3: Flow Integration

| ID | Scenario | Steps | Expected Result | Pass/Fail |
|----|----------|-------|----------------|-----------|
| TC-11 | Add MCN Flow action to flow | Open Flow Builder → Add WeaveSendEmailAction → Configure MCN template | Action saved; no validation errors | |
| TC-12 | Execute flow send | Trigger flow on Contact record | Email sent; `Weave_MCN_Email_Send__c` logged | |
| TC-13 | Flow with missing merge field | Configure flow with unmapped required variable → Run | Flow error logged; email not sent | |

---

## Scenario Group 4: Legacy Template Migration

| ID | Scenario | Steps | Expected Result | Pass/Fail |
|----|----------|-------|----------------|-----------|
| TC-14 | Analyze templates | Open Migration tab → Analyze | Readiness scores displayed; recommendations shown | |
| TC-15 | Migrate ready templates | Select all Migrate-recommended → Migrate Selected | Templates updated to All Channels; migration log created | |
| TC-16 | Skip draft templates | Include Draft templates in selection → Migrate | Draft templates skipped; skip reason displayed | |
| TC-17 | Export analysis CSV | Click Export CSV | CSV file downloaded with all templates and scores | |
| TC-18 | Rollback migration | After migration → Rollback | Templates restored to Salesforce Email; confirmed in org | |
| TC-19 | Migrate 50+ templates | Run analysis on org with 50+ templates | All complete within 2 minutes; no governor limit errors | |

---

## Scenario Group 5: Performance & Load

| ID | Scenario | Steps | Expected Result | Pass/Fail |
|----|----------|-------|----------------|-----------|
| TC-20 | Send 10 emails in sequence | Send 10 MCN emails to different contacts | All 10 succeed; total time < 10 seconds | |
| TC-21 | Concurrent renders | Trigger 10 template renders simultaneously via anonymous Apex | No `System.LimitException`; all render correctly | |
| TC-22 | Cache hit rate | Send same template 5 times; check `MCNPerformanceCache.getContentHitRate()` | Hit rate > 0% after 2nd send | |
| TC-23 | Health monitor execution | Manually execute `MCNHealthMonitorScheduler` | Health check completes; event published | |

---

## Scenario Group 6: Error Cases

| ID | Scenario | Steps | Expected Result | Pass/Fail |
|----|----------|-------|----------------|-----------|
| TC-24 | Invalid Data360 connector | Configure template with non-existent Data360 connector → Publish | Error shown; template not published | |
| TC-25 | MCN API unavailable | Disable Named Credential → Send email | User-friendly error shown; `Weave_MCN_Email_Send__c` with Status=Failed | |
| TC-26 | Missing recipient email | Send without recipient email | Validation error; no callout made | |
| TC-27 | Error rate alert | Inject 10 failure records → Run health monitor | Alert email received by admins within 5 minutes | |
| TC-28 | Duplicate publish | Publish same template twice simultaneously | Second publish detects conflict; no duplicate MCN asset | |

---

## Scenario Group 7: Analytics & Logging

| ID | Scenario | Steps | Expected Result | Pass/Fail |
|----|----------|-------|----------------|-----------|
| TC-29 | View send logs | Open Send Log tab | `Weave_MCN_Email_Send__c` records visible; correct data | |
| TC-30 | Health dashboard loads | Open MCN Health Dashboard | Metrics load; no errors | |
| TC-31 | Error list in dashboard | Generate a failed send → Open dashboard | Failed send appears in Recent Errors table | |
| TC-32 | Platform event published | Send email → Check Event Monitoring | `MCN_Integration_Event__e` with Operation=Send published | |

---

## Regression Scenarios (Existing Weave Functionality)

| ID | Scenario | Expected Result | Pass/Fail |
|----|----------|----------------|-----------|
| TC-33 | Standard Weave email send (non-MCN) | Send completes normally via standard Salesforce Email | |
| TC-34 | Weave template builder (Salesforce Email type) | Builder works unchanged; MCN options not visible | |
| TC-35 | Scheduled Weave send | Existing scheduled sends fire correctly | |
| TC-36 | Weave send logs | Standard send logs still populated | |
| TC-37 | Weave unsubscribe link | Unsubscribe still works for non-MCN emails | |

---

## UAT Sign-Off

| Scenario Group | Tester | Date | Pass % | Signed Off |
|---------------|--------|------|--------|-----------|
| Template Creation & Publishing | | | | |
| Email Composer | | | | |
| Flow Integration | | | | |
| Legacy Migration | | | | |
| Performance & Load | | | | |
| Error Cases | | | | |
| Analytics & Logging | | | | |
| Regression | | | | |

**Go/No-Go decision:** All scenario groups must achieve 100% pass rate before production deployment.
