@isTest
private class WeaveRecipientSegmentControllerTest {

    @TestSetup
    static void makeData() {
        Weave_Recipient_Segment__c seg = new Weave_Recipient_Segment__c(
            Name = 'Test Segment',
            Object_API_Name__c = 'Contact',
            Email_Field_API_Name__c = 'Email',
            Name_Field_API_Name__c = 'Name',
            Status__c = 'Active',
            Description__c = 'Test'
        );
        insert seg;

        Contact c = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com'
        );
        insert c;
    }

    @isTest
    static void testGetActiveSegments_all() {
        List<Weave_Recipient_Segment__c> results = WeaveRecipientSegmentController.getActiveSegments(null);
        System.assert(!results.isEmpty(), 'Should return active segments');
        System.assertEquals('Test Segment', results[0].Name);
    }

    @isTest
    static void testGetActiveSegments_filtered() {
        List<Weave_Recipient_Segment__c> results = WeaveRecipientSegmentController.getActiveSegments('Contact');
        System.assert(!results.isEmpty(), 'Should return segment for Contact');
        System.assertEquals('Contact', results[0].Object_API_Name__c);
    }

    @isTest
    static void testGetActiveSegments_noMatch() {
        List<Weave_Recipient_Segment__c> results = WeaveRecipientSegmentController.getActiveSegments('Opportunity');
        System.assertEquals(0, results.size(), 'Should return empty for non-matching object');
    }

    @isTest
    static void testSaveSegment_insert() {
        Weave_Recipient_Segment__c seg = new Weave_Recipient_Segment__c(
            Name = 'New Segment',
            Object_API_Name__c = 'Contact',
            Email_Field_API_Name__c = 'Email',
            Status__c = 'Active'
        );
        Weave_Recipient_Segment__c saved = WeaveRecipientSegmentController.saveSegment(seg);
        System.assertNotEquals(null, saved.Id);
    }

    @isTest
    static void testSaveSegment_update() {
        Weave_Recipient_Segment__c seg = [
            SELECT Id, Name, Object_API_Name__c, Email_Field_API_Name__c, Name_Field_API_Name__c
            FROM Weave_Recipient_Segment__c
            LIMIT 1
        ];
        seg.Description__c = 'Updated';
        Weave_Recipient_Segment__c updated = WeaveRecipientSegmentController.saveSegment(seg);
        System.assertEquals(seg.Id, updated.Id);
    }

    @isTest
    static void testSaveSegment_missingName() {
        Weave_Recipient_Segment__c seg = new Weave_Recipient_Segment__c(
            Object_API_Name__c = 'Contact',
            Email_Field_API_Name__c = 'Email'
        );
        try {
            WeaveRecipientSegmentController.saveSegment(seg);
            System.assert(false, 'Should throw');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e, 'Should throw AuraHandledException for missing name');
        }
    }

    @isTest
    static void testDeleteSegment() {
        Weave_Recipient_Segment__c seg = [SELECT Id FROM Weave_Recipient_Segment__c LIMIT 1];
        WeaveRecipientSegmentController.deleteSegment(seg.Id);
        List<Weave_Recipient_Segment__c> remaining = [SELECT Id FROM Weave_Recipient_Segment__c WHERE Id = :seg.Id];
        System.assertEquals(0, remaining.size(), 'Segment should be deleted');
    }

    @isTest
    static void testDeleteSegment_nullId() {
        try {
            WeaveRecipientSegmentController.deleteSegment(null);
            System.assert(false, 'Should throw');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void testPreviewSegmentCount() {
        Weave_Recipient_Segment__c seg = [SELECT Id FROM Weave_Recipient_Segment__c LIMIT 1];
        Integer count = WeaveRecipientSegmentController.previewSegmentCount(seg.Id);
        System.assert(count >= 0, 'Count should be non-negative');
    }

    @isTest
    static void testResolveSegmentRecipients() {
        Weave_Recipient_Segment__c seg = [SELECT Id FROM Weave_Recipient_Segment__c LIMIT 1];
        List<RecipientOptionDTO> opts = WeaveRecipientSegmentController.resolveSegmentRecipients(seg.Id);
        System.assert(!opts.isEmpty(), 'Should resolve at least one recipient');
        System.assertEquals('test@example.com', opts[0].email);
        System.assertEquals('Segment', opts[0].sourceType);
    }

    @isTest
    static void testResolveSegmentRecipients_nullId() {
        try {
            WeaveRecipientSegmentController.resolveSegmentRecipients(null);
            System.assert(false, 'Should throw');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
