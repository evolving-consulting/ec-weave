public with sharing class WeaveContentSharingService {

    public class PublicLinkResult {
        @AuraEnabled public String distributionId   { get; set; }
        @AuraEnabled public String publicUrl        { get; set; }
        @AuraEnabled public String downloadUrl      { get; set; }
        @AuraEnabled public DateTime expiryDate     { get; set; }
    }

    public static PublicLinkResult createPublicLink(Id contentDocumentId, Integer expirationDays) {
        // Verify ContentDistribution is available in this org
        try {
            Schema.describeSObjects(new List<String>{ 'ContentDistribution' });
        } catch (Exception e) {
            throw new AuraHandledException(
                'Content Deliveries and Public Sharing must be enabled in your org settings before creating public links.'
            );
        }

        // Resolve the latest ContentVersionId from the ContentDocumentId
        ContentVersion cv = [
            SELECT Id FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
            WITH USER_MODE LIMIT 1
        ];

        ContentDistribution dist = new ContentDistribution();
        dist.Name                           = 'Weave Public Link';
        dist.ContentVersionId               = cv.Id;
        dist.PreferencesAllowViewInBrowser  = true;
        dist.PreferencesLinkLatestVersion   = false;
        dist.PreferencesPasswordRequired    = false;
        dist.PreferencesAllowOriginalDownload = true;

        if (expirationDays != null && expirationDays > 0) {
            dist.ExpiryDate      = DateTime.now().addDays(expirationDays);
            dist.PreferencesExpires = true;
        }

        insert as user dist;

        // Re-query for the platform-generated URLs
        dist = [
            SELECT Id, ContentDownloadUrl, DistributionPublicUrl, ExpiryDate
            FROM ContentDistribution
            WHERE Id = :dist.Id
            WITH USER_MODE
            LIMIT 1
        ];

        PublicLinkResult result    = new PublicLinkResult();
        result.distributionId      = dist.Id;
        result.publicUrl           = dist.DistributionPublicUrl;
        result.downloadUrl         = dist.ContentDownloadUrl;
        result.expiryDate          = dist.ExpiryDate;
        return result;
    }

    public static void revokePublicLink(Id contentDistributionId) {
        ContentDistribution dist = [
            SELECT Id
            FROM ContentDistribution
            WHERE Id = :contentDistributionId
            WITH USER_MODE
            LIMIT 1
        ];
        delete as user dist;
    }
}
