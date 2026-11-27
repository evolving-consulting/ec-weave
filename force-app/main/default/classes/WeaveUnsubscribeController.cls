@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces')
public without sharing class WeaveUnsubscribeController {

    public String status       { get; private set; }
    public String brandName    { get; private set; }
    public String logoUrl      { get; private set; }
    public Boolean showResubscribe { get; private set; }

    private Id recordId;
    private String sObjectType;

    public WeaveUnsubscribeController() {
        status = 'pending';
        showResubscribe = false;
    }

    public PageReference init() {
        String token = ApexPages.currentPage().getParameters().get('token');
        if (String.isBlank(token)) {
            status = 'invalid';
            return null;
        }

        try {
            String decoded = EncodingUtil.base64Decode(token).toString();
            List<String> parts = decoded.split(':');
            if (parts.size() < 1 || String.isBlank(parts[0])) {
                status = 'invalid';
                return null;
            }

            recordId = (Id) parts[0];
            sObjectType = recordId.getSObjectType().getDescribe().getName();

            if (parts.size() >= 2 && !String.isBlank(parts[1])) {
                loadBrandInfo((Id) parts[1]);
            }

            SObject record = queryRecord(recordId, sObjectType);
            if (record == null) {
                status = 'invalid';
                return null;
            }

            Boolean alreadyOptedOut = (Boolean) record.get('HasOptedOutOfEmail');
            if (alreadyOptedOut == true) {
                status = 'already';
                showResubscribe = true;
                return null;
            }

            record.put('HasOptedOutOfEmail', true);
            update record;
            status = 'success';
            showResubscribe = true;

        } catch (Exception e) {
            status = 'error';
        }
        return null;
    }

    public PageReference resubscribe() {
        try {
            if (recordId == null || String.isBlank(sObjectType)) {
                status = 'error';
                return null;
            }
            SObject record = queryRecord(recordId, sObjectType);
            if (record == null) {
                status = 'error';
                return null;
            }
            record.put('HasOptedOutOfEmail', false);
            update record;
            status = 'resubscribed';
            showResubscribe = false;
        } catch (Exception e) {
            status = 'error';
        }
        return null;
    }

    private void loadBrandInfo(Id brandId) {
        List<Weave_Brand__c> brands = [
            SELECT Id, Display_Name__c, Logo_URL__c
            FROM Weave_Brand__c
            WHERE Id = :brandId
            LIMIT 1
        ];
        if (!brands.isEmpty()) {
            brandName = brands[0].Display_Name__c;
            logoUrl   = brands[0].Logo_URL__c;
        }
    }

    private static SObject queryRecord(Id recId, String objectType) {
        if (objectType == 'Contact') {
            List<Contact> recs = [SELECT Id, HasOptedOutOfEmail FROM Contact WHERE Id = :recId LIMIT 1];
            return recs.isEmpty() ? null : recs[0];
        } else if (objectType == 'Lead') {
            List<Lead> recs = [SELECT Id, HasOptedOutOfEmail FROM Lead WHERE Id = :recId LIMIT 1];
            return recs.isEmpty() ? null : recs[0];
        }
        return null;
    }

    public static String buildToken(Id recordId, Id brandId) {
        String raw = String.valueOf(recordId) + ':' + (brandId != null ? String.valueOf(brandId) : '');
        return EncodingUtil.base64Encode(Blob.valueOf(raw));
    }
}
