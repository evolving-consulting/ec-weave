public with sharing class WeavePdfController {

    @AuraEnabled
    public static String generatePdf(Id templateId, Id recordId) {
        try {
            ContentVersion cv = WeavePdfService.generatePdf(templateId, recordId);
            return cv.ContentDocumentId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to generate PDF. Please contact your administrator.');
        }
    }

    @AuraEnabled
    public static String previewPdfFromHtml(String html, String title) {
        try {
            ContentVersion cv = WeavePdfService.previewPdf(html, title);
            return cv.ContentDocumentId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to generate PDF preview. Please contact your administrator.');
        }
    }

    @AuraEnabled
    public static String generateCombinedPdf(List<Id> templateIds, List<Id> recordIds, String title) {
        try {
            ContentVersion cv = WeavePdfService.generateCombinedPdf(templateIds, recordIds, title);
            return cv.ContentDocumentId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to generate combined PDF. Please contact your administrator.');
        }
    }

    @AuraEnabled
    public static WeaveContentSharingService.PublicLinkResult createPublicLink(Id contentDocumentId, Integer expirationDays) {
        try {
            return WeaveContentSharingService.createPublicLink(contentDocumentId, expirationDays);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to create public link. Please contact your administrator.');
        }
    }

    @AuraEnabled
    public static void revokePublicLink(Id contentDistributionId) {
        try {
            WeaveContentSharingService.revokePublicLink(contentDistributionId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to revoke public link. Please contact your administrator.');
        }
    }
}
