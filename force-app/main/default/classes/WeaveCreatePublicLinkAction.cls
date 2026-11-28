@SuppressWarnings('PMD.ApexDoc')
public with sharing class WeaveCreatePublicLinkAction {

    public class ActionRequest {
        @InvocableVariable(label='Content Document ID' required=true)
        public Id contentDocumentId;

        @InvocableVariable(label='Expiration Days (0 = never)')
        public Integer expirationDays;
    }

    public class ActionResult {
        @InvocableVariable(label='Public URL')
        public String publicUrl;

        @InvocableVariable(label='Download URL')
        public String downloadUrl;

        @InvocableVariable(label='Content Distribution ID')
        public String distributionId;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Create Weave Public Link'
        description='Generates a public sharing URL for a Weave-generated PDF via ContentDistribution.'
        category='Dynamic Communication Engine'
    )
    public static List<ActionResult> createPublicLink(List<ActionRequest> requests) {
        List<ActionResult> results = new List<ActionResult>();
        for (ActionRequest req : requests) {
            ActionResult res = new ActionResult();
            try {
                WeaveContentSharingService.PublicLinkResult link =
                    WeaveContentSharingService.createPublicLink(req.contentDocumentId, req.expirationDays);
                res.publicUrl      = link.publicUrl;
                res.downloadUrl    = link.downloadUrl;
                res.distributionId = link.distributionId;
            } catch (Exception e) {
                res.errorMessage = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }
}
