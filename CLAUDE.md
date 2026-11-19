# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**EC Weave** — a Salesforce Unlocked Package (package ID `0HoOK00000007Sv0AI`) that enables admins to build dynamic email templates driven by related list data, solving the long-standing Salesforce gap of cross-object merge fields in email templates.

Default target org alias: `ec-weave-dev` (set in `.sf/config.json`). API version: 66.0.

---

## Common Commands

```bash
# Deploy all source to default org
sf project deploy start

# Deploy specific component
sf project deploy start --source-dir force-app/main/default/classes/WeaveEmailSendService.cls

# Run all Apex tests
sf apex run test --test-level RunLocalTests --result-format human --wait 10

# Run a specific test class
sf apex run test --class-names WeaveTemplateBuilderServiceTest --result-format human --wait 10

# Execute anonymous Apex
sf apex run --file scripts/apex/hello.apex

# Open default org
sf org open

# Lint LWC
npm run lint

# Run LWC Jest tests
npm run test:unit

# Run LWC Jest in watch mode
npm run test:unit:watch

# Format all files
npm run prettier

# Check formatting without writing
npm run prettier:verify

# Retrieve metadata from org to local
sf project retrieve start --source-dir force-app
```

---

## Architecture Overview

### Two-layer component model

The codebase has two parallel naming conventions — an older `Generic`/`Dce` prefix layer and the current `Weave` prefix layer. The `Weave` classes are the active, maintained layer. The `Generic` and `Dce` prefixed classes either remain as lightweight wrappers/base types (e.g. `GenericEmailSendRequest`, `RecipientInputDTO`) or are legacy. When adding features, always work in the `Weave` namespace.

### Apex layer

The Apex layer follows a strict Controller → Service → Renderer/Resolver separation:

| Layer | Classes | Responsibility |
|---|---|---|
| Controllers | `WeaveTemplateBuilderController`, `WeaveEmailTemplateController` | `@AuraEnabled` methods only; thin pass-through to services |
| Services | `WeaveTemplateBuilderService`, `WeaveEmailSendService`, `WeaveScheduledEmailService`, `WeaveBrandService` | Business logic, DML, SOQL |
| Rendering | `WeaveEmailTemplateRenderer` | Assembles component HTML by region (Header/Body/Footer), executes queries, resolves merge tags |
| Resolution | `WeaveRecipientResolver`, `GenericMergeFieldResolver`, `WeaveAttachmentResolver` | Stateless resolvers used by both renderer and send service |
| Post-send | `WeavePostSendActionService` | Runs template-configured actions (field updates, task creation) after send |
| Async | `WeaveScheduledEmailJob`, `WeaveScheduledEmailExecutor`, `WeaveBulkEmailBatch` | Scheduled/batch execution of deferred sends |
| Invocable | `WeaveSendEmailAction` | Flow-callable action; category "Dynamic Communication Engine" |

**Transport object**: `GenericEmailSendRequest` is the canonical request struct passed between LWC → controller → send service. It is not a DTO; it carries no business logic.

**All DTOs** live in `WeaveBuilderDTOs` (single class with inner classes). Legacy standalone DTO classes (`DceBuilderTemplateDTO`, etc.) exist but are superseded.

### Custom objects (Weave namespace)

| Object | Purpose |
|---|---|
| `Weave_Template_Config__c` | Root template record |
| `Weave_Template_Component__c` | Per-region HTML components (Header/Body/Footer), linked to queries |
| `Weave_Template_Query__c` | SOQL query definitions for dynamic sections |
| `Weave_Template_Recipient__c` | Recipient rule configurations |
| `Weave_Template_Action__c` | Post-send actions (Update Field, Create Task) |
| `Weave_Template_Attachment__c` | Auto-attach file rules |
| `Weave_Brand__c` | Brand kit (logo, colors, header/footer HTML) |
| `Weave_Scheduled_Send__c` | Scheduled send records with status tracking |
| `Weave_Send_Log__c` | Email send history |

The older `Email_Template_*__c` objects are legacy and not used by the Weave layer.

### LWC layer

| Component | Role |
|---|---|
| `weaveTemplateBuilder` | Admin wizard: creates/edits templates step-by-step |
| `weaveEmailComposer` | End-user runtime: select template → recipients → preview → send / schedule |
| `weaveBuilderComponentCard` | Reusable card UI for individual template components in the builder |
| `weaveBuilderQueryEditor` | UI for configuring the SOQL queries attached to components |
| `dceTemplateBuilder` | Legacy builder (do not extend) |
| `genericEmailTemplateComposer` | Legacy composer (do not extend) |
| `dceBuilderSectionCard`, `dceBuilderQueryConfig` | Legacy sub-components |

### Rendering pipeline

`WeaveEmailTemplateRenderer.renderEmail(templateId, recordId)`:
1. Loads `Weave_Template_Config__c` and all `Weave_Template_Component__c` records
2. Loads parent SObject with fields needed by merge tags and components
3. Calls `assembleRegion` for Header, Body, Footer — each iterates components in sort order, executes linked `Weave_Template_Query__c` SOQL for Related Table components, resolves `{{merge.tags}}` via `GenericMergeFieldResolver`
4. Wraps in brand header/footer HTML from `Weave_Brand__c`
5. Subject supports A/B variant (`Subject_Variant_B__c` chosen randomly at 50%)
6. Returns `RenderedEmailDTO(subject, htmlBody, plainText)`

### Scheduled / bulk send

- **Individual scheduled send** (from `weaveEmailComposer`): creates `Weave_Scheduled_Send__c`, schedules `WeaveScheduledEmailJob` via `System.schedule` with a cron expression derived from the target datetime.
- **Bulk send** (from `WeaveTemplateBuilderController.createScheduledSend` with `sendType='Bulk'`): `WeaveScheduledEmailJob` dispatches `WeaveBulkEmailBatch`, which pages through filtered records and calls `WeaveEmailSendService` per record.
- **Flow send**: `WeaveSendEmailAction` is an `@InvocableMethod`; it renders, resolves recipients from template config, and sends — no UI required.

### Unsubscribe

`WeaveUnsubscribeController` is a Visualforce page controller (`without sharing`). It decodes a base64 token of `recordId:brandId`, sets `HasOptedOutOfEmail = true` on Contact/Lead. Token is generated by `WeaveUnsubscribeController.buildToken(recordId, brandId)` and embedded in outgoing emails by the send service.

### HTML sanitization

`DceHtmlPolicy` implements `SanitizationPolicy` and is used to sanitize rich-text content before rendering to prevent XSS in stored HTML components.

### Security posture

All controllers and services use `with sharing`. All SOQL uses `WITH USER_MODE`. The exception is `WeaveUnsubscribeController` (`without sharing`) because it must process unsubscribe tokens from unauthenticated users.

---

## Key Design Conventions

- **Merge tag syntax**: `{{Parent.FieldName}}` for parent fields, `{{FieldName}}` for child record fields within a section, `{{Section.ApiName}}` for section references. Resolved by `GenericMergeFieldResolver`.
- **Template status lifecycle**: `Draft` → `Active`. Only `Active` templates appear in the composer. Builder controller's `previewTemplate` bypasses the status check.
- **Post-send actions** run synchronously within `WeaveEmailSendService` via `WeavePostSendActionService.executeActions`. Keep actions lightweight.
- **All `@AuraEnabled` non-cacheable methods** that perform DML must catch `AuraHandledException` explicitly and re-throw; unexpected exceptions must be caught and re-thrown as `AuraHandledException` with a user-safe message (no stack traces to UI).
- **LWC Jest tests** are co-located under each component folder in `__tests__/`.
- **List-query methods called after mutations** must NOT use `cacheable=true`. Imperative calls to cacheable methods return stale LWC cache data, so the UI never refreshes after a save/delete. Only schema/metadata methods that never change with user actions (e.g. `getAvailableObjects`, `getFieldsForObject`) may use `cacheable=true`.

---

## UI / Branding Rules

All Weave LWC components must follow the visual language established in `weaveTemplateBuilder`. Do not introduce new color systems, button styles, or layout patterns — extend what already exists.

### Design tokens (defined in `weaveTemplateBuilder.css` `:host`)

| Token | Value | Usage |
|---|---|---|
| `--ec-brand-teal` | `#1f5f5b` | Sidebar background, primary buttons, active states, eyebrows |
| `--ec-brand-teal-mid` | `#2d7a73` | Button hover |
| `--ec-brand-teal-light` | `#4f9b93` | Hover borders, accents |
| `--ec-brand-teal-bg` | `#ebf4f3` | Info banner background, light teal fills |
| `--ec-brand-teal-border` | `#c0deda` | Info banner border |
| `--ec-brand-ink` | `#2b2b29` | Page titles, primary text |
| `--ec-brand-muted` | `#6b7280` | Table headers, secondary text, placeholder text |
| Shell background | `#f9fafb` | Page/panel background |
| Error background | `#fef2f2` / border `#fca5a5` / text `#991b1b` | Error banners only |

New components that live outside `weaveTemplateBuilder` should copy these token definitions into their own `:host` block.

### Layout

- **Shell**: `display: flex; height: 100vh; overflow: hidden` — sidebar + main panel side by side.
- **Sidebar**: fixed width `220px`, teal background, holds the Weave logo mark + wordmark + "EC" chip + nav items + footer credit.
- **Main panel**: `flex: 1`, white/light-gray background, scrollable vertically.
- **Page header**: eyebrow (`WEAVE`, teal, 11px 800-weight all-caps) + h1 title (ink, 24px 700-weight) on the left; primary action button on the right. `padding: 28px 0 20px`.
- **Content padding**: `0 32px 32px` on the library/list view.

### Buttons

| Variant | Style |
|---|---|
| Primary (create/save) | `background: --ec-brand-teal`, white text, `border-radius: 8px`, `padding: 9px 18px`, `font-size: 13px 600-weight`. Hover → `--ec-brand-teal-mid`. |
| Filter tab (inactive) | Transparent, `border: 1px solid #e5e7eb`, `border-radius: 20px`, muted text, `padding: 5px 14px`. |
| Filter tab (active) | `background: --ec-brand-teal`, teal border, white text, 600-weight. |
| Destructive / cancel | Use SLDS `lightning-button` variant `destructive` or `neutral` — do not custom-style. |

### Banners

- **Error**: red strip at top of main panel (`#fef2f2` bg, `#fca5a5` border). Always includes a dismiss (`✕`) button.
- **Info**: teal-tinted (`--ec-brand-teal-bg` bg, `--ec-brand-teal-border` border, teal text). Dismissable. Use for first-run guidance only.
- **Success feedback**: use `ShowToastEvent` with `variant: 'success'` — do not build custom success banners.

### Post-mutation page refresh

After any save or delete operation, **always reload the list immediately** in the same `.then()` handler before resolving the promise. Never rely on `cacheable=true` list methods to auto-refresh (see design conventions above). Pattern:

```js
saveRecord({ ... })
  .then(() => {
    this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: '...', variant: 'success' }));
    this.isEditing = false;
    this.loadItems(); // ← always call the list reload here
  })
```

### Tables

**Always use a custom `slds-table`, never `<lightning-datatable>`.** The `lightning-datatable` component renders its own UI chrome (checkboxes, sort arrows, header rows) that cannot be styled to match the Weave brand.

Pattern:
```html
<table class="slds-table slds-table_cell-buffer slds-table_bordered">
  <thead>
    <tr class="slds-line-height_reset">
      <th scope="col"><span class="slds-truncate">NAME</span></th>
      <th scope="col"><span class="slds-truncate">STATUS</span></th>
      <th scope="col"><span class="slds-truncate">ACTIONS</span></th>
    </tr>
  </thead>
  <tbody>
    <template for:each={items} for:item="row">
      <tr key={row.Id} class="slds-hint-parent">
        <td><button class="row-name-link" data-id={row.Id} onclick={handleEdit}>{row.Name}</button></td>
        <td><span class={row.statusClass}>{row.Status__c}</span></td>
        <td>
          <span class="action-links">
            <button class="action-link edit-link" data-id={row.Id} onclick={handleEdit}>Edit</button>
            <button class="action-link delete-link" data-id={row.Id} onclick={handleDelete}>Delete</button>
          </span>
        </td>
      </tr>
    </template>
  </tbody>
</table>
```

CSS rules:
- `th`: `background: #f3f4f6`, `color: var(--ec-brand-muted)`, `font-size: 11px`, `font-weight: 700`, `letter-spacing: 0.06em`, uppercase
- `td`: `color: var(--ec-brand-ink)`, `font-size: 13px`
- Row hover: `background: #f9fafb`
- `.row-name-link`: `color: var(--ec-brand-teal)`, no border/bg, underline on hover
- `.edit-link`: teal, underline on hover
- `.delete-link`: `#dc2626`, underline on hover
- `.preview-link` / `.action-link`: muted, `color: var(--ec-brand-ink)` on hover

**Filter row** (always above the table):
```html
<div class="filter-row">
  <div class="filter-tabs">
    <button class={filterTabAll} data-status="All" onclick={handleStatusFilter}>All</button>
    <button class={filterTabActive} data-status="Active" onclick={handleStatusFilter}>Active</button>
    <button class={filterTabInactive} data-status="Inactive" onclick={handleStatusFilter}>Inactive</button>
  </div>
  <lightning-input type="search" placeholder="Search…" value={searchTerm} onchange={handleSearch} variant="label-hidden"></lightning-input>
</div>
```

**Status pills** — add `statusClass` to each row object when loading results (never compute in the template):
```js
this.items = result.map(r => ({
  ...r,
  statusClass: r.Status__c === 'Active' ? 'status-pill status-pill_active'
             : r.Status__c === 'Inactive' ? 'status-pill status-pill_inactive'
             : 'status-pill status-pill_draft'
}));
```

| Pill variant | Background | Text color |
|---|---|---|
| `status-pill_active` | `#d1fae5` | `#065f46` |
| `status-pill_inactive` | `#f3f4f6` | `var(--ec-brand-muted)` |
| `status-pill_draft` | `#fef3c7` | `#92400e` |

**Empty state** — centered container with SVG icon (40–48px teal), title (15px 600-weight ink), body text (13px muted), and a CTA primary button. `padding: 3rem 1rem`.

### Forms (edit panels)

Inline edit forms (without a full view switch) use the `.edit-panel` card:

```html
<div class="edit-panel">
  <div class="edit-panel-header">
    <p class="edit-panel-title">Edit Record</p>
    <button class="edit-panel-close" onclick={handleCancel}>&#x2715;</button>
  </div>
  <!-- form fields here -->
  <div class="form-actions">
    <button class="btn-cancel" onclick={handleCancel}>Cancel</button>
    <button class="btn-primary" onclick={handleSave} disabled={isLoading}>Save</button>
  </div>
</div>
```

- `.edit-panel`: `background: var(--ec-brand-teal-bg)`, `border: 1px solid var(--ec-brand-teal-border)`, `border-radius: 8px`, `padding: 1.25rem`, `margin-bottom: 1rem`
- `.edit-panel-header`: flex row, space-between, with title on left and `✕` close button on right
- `.edit-panel-title`: 13px, 600-weight, teal, uppercase, letter-spacing 0.04em
- `.edit-panel-close`: no bg/border, muted color, hover → ink
- `.form-row`: `margin-bottom: 0.75rem`
- `.field-hint`: 11px muted text below an input
- `.form-actions`: flex row, `gap: 8px`, `margin-top: 1rem`; Cancel on left, primary Save on right

Always use `<lightning-input>`, `<lightning-combobox>`, `<lightning-textarea>` — no custom inputs.

### Typography

- Font stack: `-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif`
- Eyebrow labels: 11px, 800-weight, letter-spacing 0.1em, all-caps, teal color
- Section headings: 13–14px, 600-weight, muted or ink color
- Body / table cells: 13px, 400–500-weight

### Spinner

Always use `<lightning-spinner alternative-text="Loading" size="medium">` wrapped in `<template if:true={isLoading}>`. Do not build custom loading states.

---

## Permission Set Rules

There are exactly two permission sets. All Weave access must be granted through one of these — do not create additional permission sets.

### `Weave_Builder_Access` — admin / template configurator

Grants full configuration rights. Assign to users who build and manage templates.

| Object | Access |
|---|---|
| `Weave_Template_Config__c` | CRUD + Modify All + View All |
| `Weave_Template_Component__c` | CRUD + Modify All + View All |
| `Weave_Template_Query__c` | CRUD + Modify All + View All |
| `Weave_Template_Recipient__c` | CRUD + Modify All + View All |
| `Weave_Template_Action__c` | CRUD + Modify All + View All |
| `Weave_Template_Attachment__c` | CRUD + Modify All + View All |
| `Weave_Brand__c` | CRUD + Modify All + View All |
| `Weave_Recipient_Segment__c` | CRUD + Modify All + View All |
| `Weave_Scheduled_Send__c` | CRUD + Modify All + View All |
| `Weave_Send_Log__c` | Create + Read + View All |
| All fields on above objects | Editable |
| Custom permission `Weave_Manage_Templates` | Enabled |
| App `Weave` | Visible |
| Builder tab (`weaveTemplateBuilder`) | Visible |

### `Weave_User` — end user / email sender

Read-only on all configuration objects. Can create send records and scheduled sends. No access to the builder app. Assign to anyone who sends emails via Weave.

| Object | Access |
|---|---|
| `Weave_Template_Config__c` | Read + View All |
| `Weave_Template_Component__c` | Read + View All |
| `Weave_Template_Query__c` | Read + View All |
| `Weave_Template_Recipient__c` | Read + View All |
| `Weave_Template_Action__c` | Read + View All |
| `Weave_Template_Attachment__c` | Read + View All |
| `Weave_Brand__c` | Read + View All |
| `Weave_Recipient_Segment__c` | Read + View All |
| `Weave_Scheduled_Send__c` | Create + Read (own records only) |
| `Weave_Send_Log__c` | Create + Read (own records only) |
| All fields on above objects | Read-only (not editable) |
| Custom permission `Weave_Manage_Templates` | **Not granted** |
| App `Weave` | Visible |
| Builder tab (`weaveTemplateBuilder`) | **Not visible** |
| Send Log tab (`Weave_Send_Log__c`) | Visible |

**Rule of thumb**: if a field or object is part of template configuration (how an email is built), `Weave_User` gets read-only. If it's a runtime record created during sending (logs, scheduled sends), `Weave_User` gets create + read on their own records only.
