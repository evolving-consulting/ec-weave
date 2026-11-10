# Hotel Proposal Sample Configuration

## Overview

This sample configures the Dynamic Communication Engine (DCE) to generate a hotel proposal email from an `Opportunity` record. It demonstrates parent merge fields, a repeated child text block section using `Email_Template_Line__c`, related-record recipient resolution, and optional manual recipients.

This is sample configuration only. The DCE engine remains generic and does not hardcode `Opportunity`, `OpportunityContactRole`, `Accomodation_Rates__c`, hotel fields, or proposal logic.

## Prerequisites

Deploy the DCE metadata, Apex services, controller, and `genericEmailTemplateComposer` LWC before running this sample.

The following business objects and fields must already exist in the target org.

Parent object: `Opportunity`

Required fields:

- `Name`
- `Expected_Arrival_Date__c`
- `Number_of_Adults__c`
- `Number_of_Children__c`
- `Children_Age_s__c`
- `Arrangement_Details__c`

Child object: `Accomodation_Rates__c`

Required fields:

- `Opportunity__c`
- `Name`
- `Expected_Departure_Date__c`
- `Number_of_Nights__c`
- `Meal_Plan_Type__c`
- `Nightly_Rate__c`
- `Service_Charge__c`
- `VAT__c`
- `Tourism_Levy_per_Adult_Day__c`
- `Nightly_Total__c`
- `Total__c`
- `CreatedDate`

Recipient source object: `OpportunityContactRole`

Required fields:

- `OpportunityId`
- `Contact.Name`
- `Contact.Email`
- `IsPrimary`

## What the Script Creates

The anonymous Apex script creates:

- One active `Email_Template_Config__c` named `Hotel Proposal`
- One active `Email_Template_Section__c` named `Accommodation Options`
- Six active `Email_Template_Line__c` records under the section
- One related-record recipient config using `OpportunityContactRole`
- One manual recipient config for optional CC entries

The script does not create any `Opportunity`, `Contact`, `OpportunityContactRole`, or `Accomodation_Rates__c` business data.

## How to Run the Script

Open Salesforce Developer Console, VS Code Execute Anonymous, or Salesforce CLI anonymous Apex execution.

Run:

```bash
sf apex run --file scripts/apex/createHotelProposalSampleConfig.apex --target-org <your-org-alias>
```

By default, the script uses:

```apex
Boolean recreateExisting = false;
```

If a `Hotel Proposal` template already exists, the script skips creating a duplicate. Set `recreateExisting = true` in the script if you want it to delete and recreate the existing sample configuration.

## Add the LWC Quick Action to Opportunity

1. Go to Setup.
2. Open Object Manager.
3. Select `Opportunity`.
4. Go to Buttons, Links, and Actions.
5. Create a new Action.
6. Set Action Type to `Lightning Web Component`.
7. Select `genericEmailTemplateComposer`.
8. Name the action, for example `Send Hotel Proposal`.
9. Add the action to the Opportunity Lightning page or page layout publisher actions.

You can also place `genericEmailTemplateComposer` directly on an Opportunity record page.

## How to Test the Sample

1. Open an Opportunity that has values for the required parent fields.
2. Confirm it has at least one related `Accomodation_Rates__c` record where `Opportunity__c` points to the Opportunity.
3. Confirm it has a primary `OpportunityContactRole` with a related Contact that has an email address.
4. Launch the `genericEmailTemplateComposer` quick action or record page component.
5. Select or confirm the `Hotel Proposal` template.
6. Review the recipients.
7. Continue to preview.
8. Confirm the accommodation options render as repeated text blocks.

## Alias Limitation Note

The body uses `{{PrimaryContact.FirstName}}` as an alias example. The current generic engine needs alias resolution configured or extended before this placeholder can resolve automatically. Until alias support is implemented, replace this with a parent field placeholder or extend the recipient resolver/renderer to populate `PrimaryContact` from `OpportunityContactRole`.

The current reusable renderer supports alias records when they are provided in `GenericMergeFieldResolver.MergeContext.aliasRecords`, but this sample does not add renderer orchestration that populates `PrimaryContact`.

## Troubleshooting

### No Templates Found

Confirm that:

- The script ran successfully.
- `Hotel Proposal` has `Active__c = true`.
- `Parent_Object_API_Name__c = Opportunity`.
- The component is running on an Opportunity record page or Opportunity quick action so `objectApiName` is `Opportunity`.

### No Recipients Found

Confirm that:

- The Opportunity has an `OpportunityContactRole`.
- `IsPrimary = true`.
- The related Contact has a valid `Email`.
- The user has access to `OpportunityContactRole`, `Contact.Name`, and `Contact.Email`.

### Section Renders Blank

Confirm that:

- The Opportunity has related `Accomodation_Rates__c` records.
- The lookup field from `Accomodation_Rates__c` to Opportunity is `Opportunity__c`.
- The user has read access to `Accomodation_Rates__c` and the configured fields.
- The `Accommodation Options` section is active.
- The six line records are active.

### Invalid Field API Name

Confirm the sample field API names match your org exactly. If your business fields differ, update the DCE configuration records rather than changing the engine.

### Accomodation_Rates__c Lookup Field May Differ

This sample assumes the child lookup field is `Opportunity__c`. If your org uses a different lookup field, update `Parent_Lookup_Field_API_Name__c` on the `Accommodation Options` section.

### Primary Contact Alias Not Resolving

`{{PrimaryContact.FirstName}}` is intentionally included as an alias example. If it renders blank, either:

- Replace it in `Body_Template__c` with a parent field placeholder your org supports, or
- Extend the renderer orchestration in a future block to populate `MergeContext.aliasRecords.put('PrimaryContact', contactRecord)`.

### Config Inserts But Preview Fails

The DCE services validate object and field access at runtime. Ensure the running user has CRUD/FLS access to the configured parent, child, and recipient source objects and fields.
