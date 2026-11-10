# Dynamic Communication Engine (DCE)

## Project Overview

The **Dynamic Communication Engine (DCE)** is a Salesforce-based framework that allows administrators and business users to:

- Create reusable dynamic email templates
- Generate emails using Salesforce data
- Build repeating sections and dynamic tables
- Configure automated recipient rules
- Preview emails before sending
- Send emails directly from Salesforce
- Allow optional end-user editing before send

The solution is designed to be **fully configuration-driven**, reducing the need for custom hardcoded email logic.

---

# Core Components

## 1. Template Builder (`dceTemplateBuilder`)

The Template Builder is an administrative Lightning Web Component (LWC) used to create and manage email templates.

### Features

- Wizard-based UI
- Dynamic section builder
- Dynamic line builder
- Dynamic table support
- Merge field insertion
- Recipient configuration
- Preview rendering
- Header/Footer branding
- Dynamic SOQL filter configuration

### Builder Steps

1. Template Details
2. Add Sections
3. Section Lines
4. Email Body
5. Recipients
6. Preview & Save

---

## 2. Email Composer (`genericEmailTemplateComposer`)

The Email Composer is the runtime experience used by end users to generate and send emails.

### Features

- Template selection
- Dynamic recipient selection
- Manual recipients
- Preview before send
- Edit before send
- Send email directly from Salesforce
- Quick Action support
- Flow support

### Composer Steps

1. Select Template
2. Select Recipients
3. Preview Email
4. Send Email

---

# Apex Architecture

## Main Services

| Class | Purpose |
|---|---|
| `GenericEmailSendService` | Sends generated emails |
| `GenericEmailTemplateRenderer` | Renders templates and merge fields |
| `GenericMergeFieldResolver` | Resolves merge field values |
| `GenericRecipientResolver` | Resolves recipients dynamically |
| `GenericDynamicQueryService` | Builds and executes dynamic SOQL |
| `DceTemplateBuilderService` | Saves and loads template configurations |
| `DceTemplateBuilderController` | LWC controller for template builder |
| `GenericEmailTemplateController` | LWC controller for runtime composer |

---

# DTO Layer

The solution uses DTOs (Data Transfer Objects) to separate UI and backend logic.

## DTO Classes

| DTO | Purpose |
|---|---|
| `DceBuilderTemplateDTO` | Full template configuration |
| `DceBuilderSectionDTO` | Section configuration |
| `DceBuilderFieldDTO` | Table field configuration |
| `DceBuilderRecipientDTO` | Recipient configuration |
| `DceBuilderObjectDTO` | Salesforce object metadata |
| `DceOrgWideEmailDTO` | Org-wide email metadata |
| `RenderedEmailDTO` | Final rendered email |
| `RecipientInputDTO` | Runtime recipient input |
| `RecipientOptionDTO` | Runtime recipient options |

---

# Template Structure

A template consists of:

- Template Details
- Sections
- Section Lines
- Email Body
- Recipient Rules
- Branding
- Preview Configuration

---

# Section Types

## Static Text

Used for:

- Legal disclaimers
- Intro paragraphs
- Instructions
- Standard reusable content

## Text Block

Repeating text sections based on related records.

Examples:

- Reservation options
- Product summaries
- Attendees
- Line items

## Table

Dynamic table generated from related Salesforce records.

Examples:

- Quote products
- Reservation summaries
- Pricing tables

---

# Merge Field Syntax

## Parent Object

```text
{{Parent.Name}}
{{Parent.Owner.Name}}
```

## Child Record

```text
{{Name}}
{{Meal_Plan_Type__c}}
```

## Sections

```text
{{Section.AccomodationOptions}}
```

---

# Recipient Sources

## Parent Field

Uses fields directly from the main record.

Example:

- Opportunity.Primary_Contact__r.Email

## Related Records

Uses related records dynamically.

Examples:

- Opportunity Contact Roles
- Contacts
- Attendees

## Manual

Allows users to manually enter recipients during send.

---

# Dynamic Filters

The system supports configurable filter logic for:

- Sections
- Recipients

## Supported Operators

- Equals
- Not Equals
- Greater Than
- Less Than
- Is Blank
- Is Not Blank

Example:

```text
Status__c = 'Active'
```

---

# Runtime Rendering Process

## High Level Flow

1. User selects template
2. Template loads
3. Merge fields resolve
4. Dynamic sections render
5. Recipients resolve
6. Email preview generates
7. User optionally edits
8. Email sends

---

# Email Branding

Templates support:

- Rich text headers
- Rich text footers
- Company logos
- Dynamic signatures
- HTML-safe formatting

---

# Preview System

The preview engine allows users to:

- Select a Salesforce record
- Render live data
- Validate sections
- Validate recipients
- Validate formatting before sending

---

# Key Design Principles

## Configuration Driven

No hardcoded templates required.

## Reusable

One framework supports many business processes.

## Admin Friendly

Business users can configure templates without developers.

## Scalable

Supports multiple objects and use cases.

## Generic

Framework is object-agnostic.

---

# Supported Use Cases

- Reservation confirmations
- Quotes
- Proposal emails
- Product summaries
- Client onboarding
- Follow-up communications
- Contract notifications
- Dynamic marketing emails

---

# Salesforce Technologies Used

- Apex
- Lightning Web Components (LWC)
- SLDS
- Dynamic SOQL
- Org-Wide Email Addresses
- Flow Integration
- Quick Actions
- Rich Text Editor Components

---

# Security Considerations

- Uses Salesforce sharing model
- Respects field-level security where applicable
- Supports org-wide email governance
- Dynamic queries should always be validated

---

# Best Practices

## Template Design

- Keep sections reusable
- Avoid duplicate logic
- Use clear section names

## Merge Fields

- Always validate merge fields in preview
- Avoid hardcoding values

## Recipients

- Use filters carefully
- Validate recipient email fields

## Performance

- Avoid overly complex dynamic queries
- Limit unnecessary related record rendering

---

# Future Enhancement Ideas

- PDF attachment generation
- Multi-language templates
- Template versioning
- Conditional rendering UI
- AI-assisted template generation
- Approval workflows
- Scheduled email delivery
- Analytics/dashboarding

---

# Conclusion

The Dynamic Communication Engine provides a scalable, reusable, and admin-friendly framework for generating dynamic emails inside Salesforce.

The framework minimizes custom development while maximizing flexibility for business users and administrators.
