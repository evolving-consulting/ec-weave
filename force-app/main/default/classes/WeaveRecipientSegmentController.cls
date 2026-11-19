public with sharing class WeaveRecipientSegmentController {

    @AuraEnabled
    public static List<Weave_Recipient_Segment__c> getSegments() {
        try {
            return [
                SELECT Id, Name, Object_API_Name__c, Email_Field_API_Name__c,
                    Name_Field_API_Name__c, SOQL_Filter__c, Description__c, Status__c
                FROM Weave_Recipient_Segment__c
                WITH USER_MODE
                ORDER BY Name ASC
            ];
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load recipient segments.');
        }
    }

    @AuraEnabled
    public static List<Weave_Recipient_Segment__c> getActiveSegments(String objectApiName) {
        try {
            List<Weave_Recipient_Segment__c> segments = [
                SELECT Id, Name, Object_API_Name__c, Email_Field_API_Name__c,
                    Name_Field_API_Name__c, SOQL_Filter__c, Description__c
                FROM Weave_Recipient_Segment__c
                WHERE Status__c = 'Active'
                WITH USER_MODE
                ORDER BY Name ASC
            ];
            if (String.isBlank(objectApiName)) return segments;
            List<Weave_Recipient_Segment__c> filtered = new List<Weave_Recipient_Segment__c>();
            for (Weave_Recipient_Segment__c seg : segments) {
                if (seg.Object_API_Name__c == objectApiName) filtered.add(seg);
            }
            return filtered;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to load recipient segments.');
        }
    }

    @AuraEnabled
    public static Integer previewSegmentCount(Id segmentId) {
        try {
            if (segmentId == null) throw new AuraHandledException('Segment Id is required.');
            Weave_Recipient_Segment__c segment = loadSegment(segmentId);
            return countSegmentRecords(segment);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to preview segment.');
        }
    }

    @AuraEnabled
    public static List<RecipientOptionDTO> resolveSegmentRecipients(Id segmentId) {
        try {
            if (segmentId == null) throw new AuraHandledException('Segment Id is required.');
            Weave_Recipient_Segment__c segment = loadSegment(segmentId);
            return querySegmentRecipients(segment);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to resolve segment recipients.');
        }
    }

    @AuraEnabled
    public static Weave_Recipient_Segment__c saveSegment(Weave_Recipient_Segment__c segment) {
        try {
            if (segment == null) throw new AuraHandledException('Segment is required.');
            if (String.isBlank(segment.Name)) throw new AuraHandledException('Segment name is required.');
            if (String.isBlank(segment.Object_API_Name__c)) throw new AuraHandledException('Object API name is required.');
            if (String.isBlank(segment.Email_Field_API_Name__c)) throw new AuraHandledException('Email field API name is required.');
            GenericDynamicQueryService.assertValidObject(segment.Object_API_Name__c);
            GenericDynamicQueryService.assertValidField(segment.Object_API_Name__c, segment.Email_Field_API_Name__c);
            if (String.isNotBlank(segment.Name_Field_API_Name__c)) {
                GenericDynamicQueryService.assertValidField(segment.Object_API_Name__c, segment.Name_Field_API_Name__c);
            }
            if (segment.Id == null) {
                insert as user segment;
            } else {
                update as user segment;
            }
            return segment;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to save segment: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteSegment(Id segmentId) {
        try {
            if (segmentId == null) throw new AuraHandledException('Segment Id is required.');
            Weave_Recipient_Segment__c segment = [
                SELECT Id FROM Weave_Recipient_Segment__c WHERE Id = :segmentId WITH USER_MODE LIMIT 1
            ];
            delete as user segment;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to delete segment.');
        }
    }

    private static Weave_Recipient_Segment__c loadSegment(Id segmentId) {
        List<Weave_Recipient_Segment__c> segments = [
            SELECT Id, Name, Object_API_Name__c, Email_Field_API_Name__c,
                Name_Field_API_Name__c, SOQL_Filter__c, Status__c
            FROM Weave_Recipient_Segment__c WHERE Id = :segmentId WITH USER_MODE LIMIT 1
        ];
        if (segments.isEmpty()) throw new AuraHandledException('Segment not found.');
        return segments[0];
    }

    @SuppressWarnings('PMD.ApexSOQLInjection')
    private static Integer countSegmentRecords(Weave_Recipient_Segment__c segment) {
        GenericDynamicQueryService.assertValidObject(segment.Object_API_Name__c);
        String soql = 'SELECT COUNT() FROM ' + segment.Object_API_Name__c;
        if (String.isNotBlank(segment.SOQL_Filter__c)) {
            soql += ' WHERE (' + segment.SOQL_Filter__c + ')';
        }
        soql += ' WITH USER_MODE';
        return Database.countQuery(soql);
    }

    @SuppressWarnings('PMD.ApexSOQLInjection')
    private static List<RecipientOptionDTO> querySegmentRecipients(Weave_Recipient_Segment__c segment) {
        GenericDynamicQueryService.assertValidObject(segment.Object_API_Name__c);
        GenericDynamicQueryService.assertValidField(segment.Object_API_Name__c, segment.Email_Field_API_Name__c);

        Set<String> selectFields = new Set<String>{ 'Id', segment.Email_Field_API_Name__c };
        if (String.isNotBlank(segment.Name_Field_API_Name__c)) {
            GenericDynamicQueryService.assertValidField(segment.Object_API_Name__c, segment.Name_Field_API_Name__c);
            selectFields.add(segment.Name_Field_API_Name__c);
        }

        String soql = 'SELECT ' + String.join(new List<String>(selectFields), ', ')
            + ' FROM ' + segment.Object_API_Name__c;
        if (String.isNotBlank(segment.SOQL_Filter__c)) {
            soql += ' WHERE (' + segment.SOQL_Filter__c + ')';
        }
        soql += ' WITH USER_MODE ORDER BY ' + segment.Email_Field_API_Name__c + ' ASC NULLS LAST LIMIT 2000';

        List<SObject> records = Database.query(soql);
        List<RecipientOptionDTO> options = new List<RecipientOptionDTO>();
        String emailRegex = '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$';
        for (SObject record : records) {
            Object emailVal = record.get(segment.Email_Field_API_Name__c);
            if (emailVal == null) continue;
            String email = String.valueOf(emailVal).trim();
            if (!Pattern.matches(emailRegex, email.toUpperCase())) continue;
            String name = email;
            if (String.isNotBlank(segment.Name_Field_API_Name__c)) {
                Object nameVal = record.get(segment.Name_Field_API_Name__c);
                if (nameVal != null && String.isNotBlank(String.valueOf(nameVal))) name = String.valueOf(nameVal);
            }
            RecipientOptionDTO opt = new RecipientOptionDTO();
            opt.id = 'segment-' + segment.Id + '-' + String.valueOf(record.get('Id'));
            opt.name = name;
            opt.email = email;
            opt.recipientType = 'To';
            opt.source = 'Segment';
            opt.sourceType = 'Segment';
            opt.selected = true;
            opt.required = false;
            opt.allowMultiple = true;
            options.add(opt);
        }
        return options;
    }
}
