@SuppressWarnings('PMD.ApexDoc')
public with sharing class WeaveCancelSignatureAction {

    public class ActionRequest {
        @InvocableVariable(label='Signature Request ID' required=true)
        public Id signatureRequestId;
        @InvocableVariable(label='Cancel Reason')
        public String cancelReason;
    }

    @InvocableMethod(
        label='Cancel Weave Signature Request'
        description='Cancels an in-progress Weave e-signature request and notifies all pending signers.'
        category='Dynamic Communication Engine'
    )
    public static void cancelRequest(List<ActionRequest> requests) {
        for (ActionRequest req : requests) {
            if (req.signatureRequestId != null) {
                WeaveSignatureService.cancelRequest(req.signatureRequestId, req.cancelReason);
            }
        }
    }
}
