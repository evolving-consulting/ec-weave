@SuppressWarnings('PMD.ApexDoc')
public with sharing class WeaveGeneratePacketAction {

    public class ActionRequest {
        @InvocableVariable(label='Packet ID' required=true)
        public Id packetId;

        @InvocableVariable(label='Source Record ID' required=true)
        public Id sourceRecordId;
    }

    public class ActionResult {
        @InvocableVariable(label='Content Document ID')
        public Id contentDocumentId;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Generate Weave Document Packet'
        description='Renders all templates in a named Weave Document Packet and merges them into a single PDF linked to the source record.'
        category='Dynamic Communication Engine'
    )
    public static List<ActionResult> generatePacket(List<ActionRequest> requests) {
        List<ActionResult> results = new List<ActionResult>();
        for (ActionRequest req : requests) {
            ActionResult res = new ActionResult();
            try {
                ContentVersion cv = WeavePdfService.generatePacketPdf(req.packetId, req.sourceRecordId);
                res.contentDocumentId = cv.ContentDocumentId;
            } catch (Exception e) {
                res.errorMessage = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }
}
