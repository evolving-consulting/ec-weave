@IsTest
private class WeaveRecipientResolverTest {

    @TestSetup
    static void setup() {
        Weave_Template_Config__c template = new Weave_Template_Config__c(
            Name = 'Resolver Test Template',
            API_Name__c = 'resolver_test_template',
            Status__c = 'Active',
            Parent_Object_API_Name__c = 'Contact',
            Subject_Template__c = 'Hello',
            Allow_User_Edit_Before_Send__c = true,
            Store_Email_History__c = false
        );
        insert template;

        Contact c = new Contact(
            FirstName = 'Jane',
            LastName = 'Resolver',
            Email = 'jane.resolver@example.com'
        );
        insert c;

        Weave_Recipient_Segment__c seg = new Weave_Recipient_Segment__c(
            Name = 'All Contacts',
            Object_API_Name__c = 'Contact',
            Email_Field_API_Name__c = 'Email',
            Name_Field_API_Name__c = 'Name',
            Status__c = 'Active'
        );
        insert seg;

        Weave_Template_Recipient__c segRecipient = new Weave_Template_Recipient__c(
            Name = 'Segment Recipient',
            Weave_Template_Config__c = template.Id,
            Recipient_Source_Type__c = 'Dynamic Segment',
            Recipient_Type__c = 'To',
            Segment_Id__c = seg.Id,
            Active__c = true,
            Default_Selected__c = true,
            Allow_Multiple__c = true,
            Required__c = false,
            Display_Order__c = 1
        );
        insert segRecipient;
    }

    @IsTest
    static void getRecipientOptions_dynamicSegment_returnsRecipients() {
        Weave_Template_Config__c template = [
            SELECT Id FROM Weave_Template_Config__c WHERE API_Name__c = 'resolver_test_template' LIMIT 1
        ];
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'Resolver' LIMIT 1];

        Test.startTest();
        List<RecipientOptionDTO> options = WeaveRecipientResolver.getRecipientOptions(template.Id, c.Id);
        Test.stopTest();

        Boolean foundSegmentRecipient = false;
        for (RecipientOptionDTO opt : options) {
            if (opt.sourceType == 'Segment') {
                foundSegmentRecipient = true;
            }
        }
        System.assert(foundSegmentRecipient, 'Should include recipients resolved from the Dynamic Segment.');
    }

    @IsTest
    static void resolveSegmentRecipients_emptySegmentId_returnsEmpty() {
        Weave_Template_Config__c template = [
            SELECT Id FROM Weave_Template_Config__c WHERE API_Name__c = 'resolver_test_template' LIMIT 1
        ];

        Weave_Template_Recipient__c noSegRecipient = new Weave_Template_Recipient__c(
            Name = 'Empty Segment Recipient',
            Weave_Template_Config__c = template.Id,
            Recipient_Source_Type__c = 'Dynamic Segment',
            Recipient_Type__c = 'To',
            Segment_Id__c = null,
            Active__c = true,
            Default_Selected__c = false,
            Allow_Multiple__c = true,
            Required__c = false,
            Display_Order__c = 10
        );
        insert noSegRecipient;

        Contact c = [SELECT Id FROM Contact WHERE LastName = 'Resolver' LIMIT 1];

        Test.startTest();
        List<RecipientOptionDTO> options = WeaveRecipientResolver.getRecipientOptions(template.Id, c.Id);
        Test.stopTest();

        // Should not throw; just returns options from other configured recipients
        System.assertNotEquals(null, options, 'Options list should not be null.');
    }
}
