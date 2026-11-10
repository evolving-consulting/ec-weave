# EC Weave

**Dynamic email template generation from Salesforce related list data.**

Built by [Evolving Consulting](https://evolving-consulting.com)

---

## What is EC Weave?

EC Weave is a Salesforce Unlocked Package that lets administrators build fully dynamic email templates driven by related list data — including repeating text blocks and tables populated from child records. Templates are configuration-driven and reusable across any Salesforce object, eliminating the need for custom-coded email logic.

---

## The Problem It Solves

Salesforce's native email templates do not support cross-object merge fields — you cannot pull in data from related records (child objects) into an email template. This gap has been open on the [Salesforce IdeaExchange since 2009](https://ideas.salesforce.com) with no native resolution. EC Weave solves this directly: templates can include dynamic sections populated from any related list, with configurable filters, repeating text blocks, and formatted tables.

---

## How It Works

1. **Admins** use the **Template Builder** (`dceTemplateBuilder`) to create templates with dynamic sections — static text, repeating text blocks, and tables — each tied to a Salesforce object and related list query.
2. **End users** open the **Email Composer** (`genericEmailTemplateComposer`) from a Quick Action or Flow, select a template, preview the rendered email with live data, and send it directly from Salesforce.
3. **Recipients** are resolved dynamically from parent fields, related records, or entered manually.
4. The **rendering engine** resolves merge fields (e.g. `{{Parent.Name}}`, `{{Name}}`), executes dynamic SOQL for related data, and assembles the final HTML email.

---

## Requirements

- Salesforce org (Production or Sandbox)
- Salesforce CLI (`sf`) for local development
- API version 66.0+
- Appropriate permission sets assigned post-install (see [INSTALL.md](INSTALL.md))

---

## Installation

See [INSTALL.md](INSTALL.md) for install links and post-install setup steps.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

---

## Documentation

Full technical documentation is in [EC_Weave_Project_Documentation.md](EC_Weave_Project_Documentation.md).

A sample hotel proposal configuration walkthrough is in [docs/hotel-proposal-sample-configuration.md](docs/hotel-proposal-sample-configuration.md).

---

## Built By

**Evolving Consulting (EC)**
Salesforce consulting and product development.
