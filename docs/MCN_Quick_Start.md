# MCN Integration — Quick Start Guide

**EC Weave + Marketing Cloud Next**  
**5 steps to your first MCN email**

---

## Step 1: Assign Permissions

**Admins:** `Weave_Builder_Access`  
**End users:** `Weave_User`

Go to: **Setup → Users → [User] → Permission Set Assignments**

---

## Step 2: Verify Named Credential

Go to: **Setup → Named Credentials → MCN_API**

Confirm the endpoint URL and authentication are configured. Test:
```apex
SfmcHttpClient.testConnectivity();
```

---

## Step 3: Create Your First MCN Template

1. Open the **Weave** app → **Templates** → **New Template**
2. Set **Template Channels** = `All Channels`
3. Add a **Body** component with your HTML content
4. Use `{{Parent.FirstName}}` for personalization
5. Click **Publish to MCN**

---

## Step 4: Send an Email

1. Open a **Contact** or **Lead** record
2. Find **Weave Email Composer** on the page
3. Select your MCN template
4. Click **Preview** → **Send**

---

## Step 5: Monitor Health

Open **Weave** app → **Health Dashboard**

Green banner = everything working  
Red banner = check Recent Errors table

---

## Most Common Tasks

| Task | Where to Find It |
|------|----------------|
| Create / edit template | Weave app → Templates tab |
| Publish to MCN | Template record → Publish button |
| Send email | Contact/Lead record → Email Composer |
| Schedule send | Email Composer → Schedule button |
| Migrate legacy templates | Weave app → Migration tab |
| View send history | Record → MCN Send Logs related list |
| Check integration health | Weave app → Health Dashboard |
| Run health check manually | Anonymous Apex: `MCNHealthMonitorScheduler.runHealthCheck()` |

---

## Merge Field Quick Reference

| Syntax | Resolves To |
|--------|-------------|
| `{{Parent.Name}}` | Parent record field |
| `{{Parent.Account.Name}}` | Related field via lookup |
| `{{DataCloud.Contact__dlm.Email__c}}` | Data Cloud attribute |
| `{{flowVar.greeting}}` | Flow variable passed in context |

---

## Support

- Errors in send logs → Check `Weave_MCN_Email_Send__c` records
- Publish failures → Review `Weave_MCN_Sync_Log__c` for error details
- Alert emails → Sent to System Administrator users when error rate > 5%
- Rollback migration → Weave app → Migration tab → Rollback button
