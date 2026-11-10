# EC Weave — Changelog

All notable changes to EC Weave are documented here.

## [1.0.0] — TBD

### Initial Release

- **Template Builder** (`dceTemplateBuilder`) — wizard-based LWC for admins to create and manage dynamic email templates, with support for dynamic sections, tables, merge fields, recipient rules, header/footer branding, and live preview
- **Email Composer** (`genericEmailTemplateComposer`) — runtime LWC for end users to select a template, choose recipients, preview the rendered email with live Salesforce data, optionally edit, and send; available as a Quick Action and in Flow
- **Dynamic Sections** — three section types: Static Text (fixed content), Text Block (repeating content from related records), and Table (dynamic table from related records)
- **Merge Fields** — parent object fields (`{{Parent.FieldName}}`), related record fields (`{{FieldName}}`), and section references (`{{Section.SectionName}}`)
- **Dynamic Recipient Resolution** — recipients sourced from parent record fields, related record queries, or manual entry at send time
- **Configurable Filters** — section and recipient filters using operators: Equals, Not Equals, Greater Than, Less Than, Is Blank, Is Not Blank
- **Email Branding** — rich text headers and footers, company logo support, dynamic signatures, HTML-safe formatting
- **Preview System** — live preview against a selected Salesforce record to validate merge fields, sections, recipients, and formatting before sending
- **Org-Wide Email Address support** — sends via configured org-wide email addresses
- **Flow and Quick Action support** — composer component embeddable in Flows and launchable as a Quick Action
