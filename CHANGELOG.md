# EC Weave — Changelog

All notable changes to EC Weave are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### 2026-11-27 — Brand-Aware Signing Site & Signature Email Templates

- **Multi-brand signing site** — the Salesforce Site signing page now reflects the brand of the email template used to trigger the request; primary and secondary colors drive `--teal` / `--teal-mid` CSS variables, and the brand logo replaces the Weave lettermark when set
- **Brand token in signing link** — `WeaveSignatureService` encodes `brandId` as a third segment in the signing token (`signerId:pin:brandId`); backward-compatible with existing 2-part tokens (fall back to Weave defaults)
- **`WeaveSignatureController`** — decodes brand from token, queries `Weave_Brand__c`, and exposes `brandColor`, `brandColorMid`, `brandLogoUrl`, `brandName`, and `hasBrandLogo` to the VF page
- **Signature email templates** (`Weave_Signature_Email_Template__c`) — new object for per-brand request and reminder email templates with subject, body, logo URL, brand color, logo height, and footer text overrides; falls back to org-default template then hardcoded defaults
- **`WeaveSignatureEmailTemplateService`** — service layer for email template CRUD, rendering (subject + HTML body with brand header/footer), and reset-to-default
- **Signature config** (`Weave_Signature_Config__c`) — new singleton config object for site URL, link expiry, reminders toggle & interval, email verification, and signer email prefill settings
- **`WeaveSignatureConfigService`** — service for config CRUD and environment validation (site URL configured, active Salesforce Site found)
- **`weaveSignatureSettings` LWC** — admin settings panel in the Weave Builder for site config (URL, expiry, reminders) and per-brand email template customisation (request / reminder templates, with live edit and reset-to-default)
- **Permission sets** — `Weave_Signature_Config__c` and `Weave_Signature_Email_Template__c` access granted to `Weave_Builder_Access` (full CRUD) and `Weave_User` (read-only)

### 2026-11-27 — Signer & Write Back Tab Restructure

- **Tab reorder** — editor tabs now follow the order: Settings → Queries → Files → Signer → Write Back → Body Builder → Recipients → Actions → Preview
- **Signer tab** — renamed from "Signer Fields"; now contains only Signer Roles & Signing Order (roles table with Sig / Init / Date copy chips and "+ Add Role" action)
- **Write Back tab** — new dedicated tab for Signer Form Fields; shows the full fields table with inline merge-tag Copy chip per row
- **Add Field modal** — "+ Add Field" and "Edit" now open a centered modal overlay (Tag Label, Field Type, Signer Role, Display Order, Target Field, Required, Write Back, Show on Certificate) instead of an inline edit panel; closing the modal or clicking the backdrop cancels without saving

### 2026-11-27 — Multi-Signer Roles & Signing Order

- **Signer Roles config** — admins now define named signer roles and signing order directly in the Template Builder's Signer Fields tab; roles are stored as JSON on `Weave_Template_Config__c.Signer_Roles__c`
- **Role-specific tag chips** — per-role Sig / Init / Date click-to-copy chips replace the generic tag reference panel; tags are pre-formatted with the role name (e.g. `{{@Buyer:Full}}`)
- **Auto-populated send dialog** — `weaveSignatureSender` reads the template's configured roles on open and pre-fills the signer rows in order; Sequential mode is selected automatically when more than one role is configured
- **FLS** — `Signer_Roles__c` field access granted to `Weave_Builder_Access` (editable) and `Weave_User` (read-only)

### 2026-11-26 — E-Signature, Document Features & Builder Enhancements

- **Native e-signature sub-system** — PIN-based signing flow via `WeaveSignatureService`; supports `{{@Role:Full}}`, `{{@Role:Initials}}`, `{{@Role:Date}}`, `{{@Role:DatePick}}`, and `{{@Role:Field:Label}}` tags embedded in document bodies
- **PDF page size variants** — added Legal, A3, A5, and Custom (W×H) options alongside the existing Letter/A4 sizes
- **Public link sharing** — PDF outputs can be shared via Salesforce `ContentDistribution` public links directly from the composer
- **Document Packets** — named collections of multiple templates combined into a single merged PDF; configured and sent as one unit
- **Output Type on bulk sends** — scheduled bulk sends now support Email, PDF, or Email+PDF output selection
- **Handlebars-style conditional blocks** — `{{#if FieldName}}…{{/if}}` and `{{#unless FieldName}}…{{/unless}}` syntax for conditional content in template bodies
- **Filter condition builder** — visual AND/OR filter builder added to the query editor; supports Owner, CreatedBy, and LastModifiedBy field traversal
- **Conditional block insert in canvas** — 5-step AI wizard guides content generation inside conditional regions of canvas templates
- **Scheduler fix** — replaced comma-separated cron minutes with separate scheduled jobs per interval; added 5-minute and 10-minute frequency options
- **Resources section** — Help / documentation links panel added to the Weave sidebar
- **Segment modal redesign** — restructured into 3 sections (Source, Filters, Preview) with field-insert shortcuts and inline record preview

### 2026-11-25 — AI Prompt Builder & Brand AI

- **Brand AI — Generate with AI** — one-click brand kit generation from a URL or description; produces logo suggestions, color palette, and header/footer HTML; includes W×H image sizing and actual brand colors in the preview step
- **AI Prompt Builder — PDF guardrails** — Document-type templates include Salesforce HTML sanitizer constraints in the AI prompt to prevent blocked tags on save
- **AI Prompt Builder — Salesforce rules badge** — permanent badge in the Review Prompt step lists all tags disallowed by `DceHtmlPolicy`, updated to match the sanitizer exactly
- **AI Prompt Builder — brand auto-load** — brand details are injected into the prompt automatically when a template opens or when the brand selection changes
- **Brand fields** — added Contact Email and Contact Phone to `Weave_Brand__c`

### 2026-11-24 — MCN Integration & Data Sources

- **MCN integration (Phases 2–6)** — Multi-Channel Notification publisher (`mcnTemplatePublisher`), merge field translation layer, conflict detection, sync logs, MCN email sender, and Flow action; includes migration toolkit, performance instrumentation, and monitoring dashboards
- **Data Sources** — connector framework for Flow variables and Data Cloud objects; merge field validation against resolved data sources
- **LWC Jest fixes** — corrected test failures in `weaveMergeFieldHelper` and `weaveDataSourceEditor`

### 2026-11-19–21 — Canvas Designer, PDF, Branding & Segments

- **Canvas Designer** (`weaveCanvasDesigner`) — new LWC with dual modes: Builder Blocks (drag-and-drop sections) and HTML Mode (direct HTML editing); routes Document-type templates through canvas rendering for PDF output
- **PDF generation** — `renderCanvas` endpoint for Document templates; PDF preview in the builder; fixed rendering issues for email and canvas templates
- **Builder UX overhaul** — AI modal with scoped field picker, relationship traversal, inline section rendering, cleaner toolbar; clone template action
- **Rich text editor** — added to component body fields in the builder
- **Recipient Segments** — `weaveRecipientSegment` LWC with smart object/field pickers; Segments section in the Weave Builder sidebar; Dynamic Segment source type for recipients; segment-based filtering in the composer
- **Scheduled Sends tab** — moved schedule-send UI to a dedicated tab; added recurring bulk send support; removed Individual Record send type
- **Branding standardization** — tokenized all hardcoded teal colors to CSS custom properties; aligned Recipient Segments UI to Weave design language
- **Permission fixes** — `Weave_Recipient_Segment__c` and `Segment_Id__c` FLS corrected across both permission sets; removed `cacheable=true` from list methods that refresh after mutations

### 2026-11-18 — Scheduling, Composer & v1 Feature Completion

- **Send Later** — date/time scheduling from the email composer via `Weave_Scheduled_Send__c` and `WeaveScheduledEmailJob`
- **Tabbed composer** — recurrence UI added to `weaveEmailComposer` with Send Now / Schedule tabs
- Full v1 feature parity across template builder, composer, branding, and Flow integration

---

## [1.0.0] — 2026-11-10

### Initial Release

- **Template Builder** (`weaveTemplateBuilder`) — wizard-based LWC for admins to create and manage dynamic email templates, with support for dynamic sections, tables, merge fields, recipient rules, header/footer branding, and live preview
- **Email Composer** (`weaveEmailComposer`) — runtime LWC for end users to select a template, choose recipients, preview the rendered email with live Salesforce data, optionally edit, and send; available as a Quick Action and in Flow
- **Dynamic Sections** — three section types: Static Text (fixed content), Text Block (repeating content from related records), and Table (dynamic table from related records)
- **Merge Fields** — parent object fields (`{{Parent.FieldName}}`), related record fields (`{{FieldName}}`), and section references (`{{Section.SectionName}}`)
- **Dynamic Recipient Resolution** — recipients sourced from parent record fields, related record queries, or manual entry at send time
- **Configurable Filters** — section and recipient filters using operators: Equals, Not Equals, Greater Than, Less Than, Is Blank, Is Not Blank
- **Email Branding** — rich text headers and footers, company logo support, dynamic signatures, HTML-safe formatting
- **Preview System** — live preview against a selected Salesforce record to validate merge fields, sections, recipients, and formatting before sending
- **Org-Wide Email Address support** — sends via configured org-wide email addresses
- **Flow and Quick Action support** — composer component embeddable in Flows and launchable as a Quick Action
