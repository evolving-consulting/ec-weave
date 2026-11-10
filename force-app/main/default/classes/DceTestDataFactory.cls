@IsTest
public class DceTestDataFactory {
    public static Account createAccount() {
        Account account = new Account(Name = 'DCE Test Account');
        insert account;
        return account;
    }

    public static Contact createContact(Id accountId) {
        Contact contact = new Contact(
            AccountId = accountId,
            FirstName = 'Ada',
            LastName = 'Smith',
            Email = 'ada.smith@example.com'
        );
        insert contact;
        return contact;
    }

    public static Contact createContact(Id accountId, String firstName, String lastName, String email) {
        Contact contact = new Contact(
            AccountId = accountId,
            FirstName = firstName,
            LastName = lastName,
            Email = email
        );
        insert contact;
        return contact;
    }

    public static Opportunity createOpportunity(Id accountId) {
        Opportunity opportunity = new Opportunity(
            AccountId = accountId,
            Name = 'DCE Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;
        return opportunity;
    }

    public static Email_Template_Config__c createTemplate(String parentObjectApiName) {
        Email_Template_Config__c template = new Email_Template_Config__c(
            Name = 'DCE Test Template ' + String.valueOf(Crypto.getRandomInteger()),
            Active__c = true,
            Parent_Object_API_Name__c = parentObjectApiName,
            Subject_Template__c = 'Hello {{Name}}',
            Body_Template__c = 'Body for {{Name}} {{Section.Contacts}}',
            Description__c = 'Test template',
            Allow_User_Edit_Before_Send__c = true,
            Store_Email_History__c = true
        );
        insert template;
        return template;
    }

    public static Email_Template_Section__c createStaticSection(Id templateId, Integer orderNum) {
        Email_Template_Section__c section = new Email_Template_Section__c(
            Name = 'Static Section ' + orderNum,
            Email_Template_Config__c = templateId,
            Section_Name__c = 'Static Section',
            Section_Key__c = 'Static' + orderNum,
            Active__c = true,
            Display_Order__c = orderNum,
            Section_Type__c = 'Static Text',
            Static_Content__c = 'Static content for {{Name}}'
        );
        insert section;
        return section;
    }

    public static Email_Template_Section__c createTextBlockSection(Id templateId, Integer orderNum) {
        Email_Template_Section__c section = new Email_Template_Section__c(
            Name = 'Contacts Text Section ' + orderNum,
            Email_Template_Config__c = templateId,
            Section_Name__c = 'Contacts',
            Section_Key__c = 'Contacts',
            Active__c = true,
            Display_Order__c = orderNum,
            Section_Type__c = 'Text Block',
            Child_Object_API_Name__c = 'Contact',
            Parent_Lookup_Field_API_Name__c = 'AccountId',
            Sort_Field_API_Name__c = 'LastName',
            Sort_Direction__c = 'ASC'
        );
        insert section;
        return section;
    }

    public static Email_Template_Section__c createTableSection(Id templateId, Integer orderNum) {
        Email_Template_Section__c section = new Email_Template_Section__c(
            Name = 'Contacts Table Section ' + orderNum,
            Email_Template_Config__c = templateId,
            Section_Name__c = 'Contacts Table',
            Section_Key__c = 'ContactsTable',
            Active__c = true,
            Display_Order__c = orderNum,
            Section_Type__c = 'Table',
            Child_Object_API_Name__c = 'Contact',
            Parent_Lookup_Field_API_Name__c = 'AccountId',
            Sort_Field_API_Name__c = 'LastName',
            Sort_Direction__c = 'ASC'
        );
        insert section;
        return section;
    }

    public static Email_Template_Line__c createLine(Id sectionId, Integer orderNum, String lineTemplate) {
        Email_Template_Line__c line = new Email_Template_Line__c(
            Name = 'Line ' + orderNum,
            Email_Template_Section__c = sectionId,
            Display_Order__c = orderNum,
            Active__c = true,
            Line_Template__c = lineTemplate,
            Display_Style__c = 'Normal',
            Render_Only_If_Not_Blank__c = false
        );
        insert line;
        return line;
    }

    public static Email_Template_Field__c createField(Id sectionId, Integer orderNum, String fieldApiName) {
        Email_Template_Field__c fieldConfig = new Email_Template_Field__c(
            Name = 'Field ' + orderNum,
            Email_Template_Section__c = sectionId,
            Field_API_Name__c = fieldApiName,
            Label_Override__c = null,
            Display_Order__c = orderNum,
            Active__c = true,
            Show_Label__c = true,
            Display_Style__c = 'Normal',
            Render_Only_If_Not_Blank__c = true
        );
        insert fieldConfig;
        return fieldConfig;
    }

    public static Email_Template_Recipient_Config__c createParentFieldRecipientConfig(Id templateId) {
        Email_Template_Recipient_Config__c config = new Email_Template_Recipient_Config__c(
            Name = 'Parent Email',
            Email_Template_Config__c = templateId,
            Active__c = true,
            Display_Order__c = 1,
            Recipient_Source_Type__c = 'Parent Field',
            Recipient_Type__c = 'To',
            Name_Field_API_Name__c = 'Name',
            Email_Field_API_Name__c = 'Email',
            Default_Selected__c = true,
            Allow_Multiple__c = false,
            Required__c = true
        );
        insert config;
        return config;
    }

    public static Email_Template_Recipient_Config__c createRelatedRecordRecipientConfig(Id templateId) {
        Email_Template_Recipient_Config__c config = new Email_Template_Recipient_Config__c(
            Name = 'Related Contact',
            Email_Template_Config__c = templateId,
            Active__c = true,
            Display_Order__c = 1,
            Recipient_Source_Type__c = 'Related Records',
            Recipient_Type__c = 'To',
            Source_Object_API_Name__c = 'Contact',
            Parent_Lookup_Field_API_Name__c = 'AccountId',
            Name_Field_API_Name__c = 'Name',
            Email_Field_API_Name__c = 'Email',
            Filter_Logic__c = 'LastName = \'Smith\'',
            Default_Selected__c = true,
            Allow_Multiple__c = true,
            Required__c = true
        );
        insert config;
        return config;
    }

    public static Email_Template_Recipient_Config__c createManualRecipientConfig(Id templateId) {
        Email_Template_Recipient_Config__c config = new Email_Template_Recipient_Config__c(
            Name = 'Manual Recipient',
            Email_Template_Config__c = templateId,
            Active__c = true,
            Display_Order__c = 2,
            Recipient_Source_Type__c = 'Manual',
            Recipient_Type__c = 'CC',
            Default_Selected__c = false,
            Allow_Multiple__c = true,
            Required__c = false
        );
        insert config;
        return config;
    }
}
