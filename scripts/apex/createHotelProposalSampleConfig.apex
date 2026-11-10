// Sample DCE configuration for a hotel proposal email.
// This script inserts configuration only. It does not create business data.

Boolean recreateExisting = false;
String templateName = 'Hotel Proposal';

List<Email_Template_Config__c> existingTemplates = [
    SELECT Id
    FROM Email_Template_Config__c
    WHERE Name = :templateName
];

if (!existingTemplates.isEmpty() && !recreateExisting) {
    System.debug('Hotel Proposal template already exists. Set recreateExisting = true to recreate it.');
} else {
    if (!existingTemplates.isEmpty() && recreateExisting) {
        delete existingTemplates;
    }

    Email_Template_Config__c template = new Email_Template_Config__c(
        Name = templateName,
        Active__c = true,
        Parent_Object_API_Name__c = 'Opportunity',
        Subject_Template__c = 'Proposal for {{Name}}',
        Body_Template__c =
            'Dear {{PrimaryContact.FirstName}},<br/><br/>' +
            'Thank you for considering this potential stay at the Windjammer Landing Resort & Residences for your VIP guests. We look forward to hosting them!<br/><br/>' +
            'Windjammer Landing Resort & Residences is a Mediterranean-style village draped along 60 acres of St. Lucia’s northwestern coast. With 6 resort-wide swimming pools, a selection of signature restaurants and bars, a spa and fitness center, water sports programs and kids’ fun club, this resort offers a unique Caribbean experience that allows families, couples, friends, singles to enjoy the perfect getaway.<br/><br/>' +
            'Here are the details of the reservation request. Please be advised that pricing is inclusive of taxes, fees and accommodation Levy.<br/><br/>' +
            '{{Section.AccommodationOptions}}' +
            '<br/>' +
            '{{Arrangement_Details__c}}',
        Description__c = 'Sample hotel proposal template using Opportunity as the parent record and Accomodation_Rates__c as repeated accommodation options.',
        Allow_User_Edit_Before_Send__c = true,
        Store_Email_History__c = true
    );
    insert template;

    Email_Template_Section__c section = new Email_Template_Section__c(
        Name = 'Accommodation Options',
        Email_Template_Config__c = template.Id,
        Section_Name__c = 'Accommodation Options',
        Section_Key__c = 'AccommodationOptions',
        Active__c = true,
        Display_Order__c = 1,
        Section_Type__c = 'Text Block',
        Child_Object_API_Name__c = 'Accomodation_Rates__c',
        Parent_Lookup_Field_API_Name__c = 'Opportunity__c',
        Sort_Field_API_Name__c = 'CreatedDate',
        Sort_Direction__c = 'ASC',
        Repeat_Label__c = 'Option',
        Include_Auto_Number__c = true,
        Auto_Number_Start__c = 1
    );
    insert section;

    List<Email_Template_Line__c> lines = new List<Email_Template_Line__c>{
        new Email_Template_Line__c(
            Name = 'Accommodation Option Line 1',
            Email_Template_Section__c = section.Id,
            Display_Order__c = 1,
            Active__c = true,
            Line_Template__c = 'Dates Of Travel: {{Parent.Expected_Arrival_Date__c}} - {{Expected_Departure_Date__c}} ({{Number_of_Nights__c}} nights)',
            Display_Style__c = 'Normal',
            Render_Only_If_Not_Blank__c = false
        ),
        new Email_Template_Line__c(
            Name = 'Accommodation Option Line 2',
            Email_Template_Section__c = section.Id,
            Display_Order__c = 2,
            Active__c = true,
            Line_Template__c = 'Guests: {{Parent.Number_of_Adults__c}} Adults, {{Parent.Number_of_Children__c}} children (ages {{Parent.Children_Age_s__c}})',
            Display_Style__c = 'Normal',
            Render_Only_If_Not_Blank__c = false
        ),
        new Email_Template_Line__c(
            Name = 'Accommodation Option Line 3',
            Email_Template_Section__c = section.Id,
            Display_Order__c = 3,
            Active__c = true,
            Line_Template__c = '{{Name}} - {{Meal_Plan_Type__c}}',
            Display_Style__c = 'Bold',
            Render_Only_If_Not_Blank__c = false
        ),
        new Email_Template_Line__c(
            Name = 'Accommodation Option Line 4',
            Email_Template_Section__c = section.Id,
            Display_Order__c = 4,
            Active__c = true,
            Line_Template__c = 'Nightly Rate: {{Nightly_Rate__c}} plus {{Service_Charge__c}} Service Charge & {{VAT__c}} VAT = {{Nightly_Total__c}} plus Tourism Levy',
            Display_Style__c = 'Normal',
            Render_Only_If_Not_Blank__c = false
        ),
        new Email_Template_Line__c(
            Name = 'Accommodation Option Line 5',
            Email_Template_Section__c = section.Id,
            Display_Order__c = 5,
            Active__c = true,
            Line_Template__c = 'US${{Tourism_Levy_per_Adult_Day__c}} per adult per day = {{Nightly_Total__c}}',
            Display_Style__c = 'Normal',
            Render_Only_If_Not_Blank__c = false
        ),
        new Email_Template_Line__c(
            Name = 'Accommodation Option Line 6',
            Email_Template_Section__c = section.Id,
            Display_Order__c = 6,
            Active__c = true,
            Line_Template__c = 'Total Accommodation Charge including all taxes and Levies for {{Number_of_Nights__c}} nights = {{Total__c}}',
            Display_Style__c = 'Normal',
            Render_Only_If_Not_Blank__c = false
        )
    };
    insert lines;

    List<Email_Template_Recipient_Config__c> recipientConfigs = new List<Email_Template_Recipient_Config__c>{
        new Email_Template_Recipient_Config__c(
            Name = 'Primary Opportunity Contact',
            Email_Template_Config__c = template.Id,
            Active__c = true,
            Display_Order__c = 1,
            Recipient_Source_Type__c = 'Related Records',
            Recipient_Type__c = 'To',
            Source_Object_API_Name__c = 'OpportunityContactRole',
            Parent_Lookup_Field_API_Name__c = 'OpportunityId',
            Name_Field_API_Name__c = 'Contact.Name',
            Email_Field_API_Name__c = 'Contact.Email',
            Filter_Logic__c = 'IsPrimary = true',
            Default_Selected__c = true,
            Allow_Multiple__c = true,
            Required__c = true
        ),
        new Email_Template_Recipient_Config__c(
            Name = 'Manual CC Recipient',
            Email_Template_Config__c = template.Id,
            Active__c = true,
            Display_Order__c = 2,
            Recipient_Source_Type__c = 'Manual',
            Recipient_Type__c = 'CC',
            Default_Selected__c = false,
            Allow_Multiple__c = true,
            Required__c = false
        )
    };
    insert recipientConfigs;

    System.debug('Created Hotel Proposal DCE sample configuration. Template Id: ' + template.Id);
}
