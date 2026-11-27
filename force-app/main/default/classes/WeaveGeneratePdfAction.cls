/**
 * Invocable Apex action for generating a Weave PDF document from a Flow without any UI.
 * Pass a templateId (or templateApiName) and recordId; the action renders the PDF and
 * saves it as a ContentDocument linked to the record.
 *
 * Usage: Flow Action element → category "Dynamic Communication Engine" → "Generate Weave PDF"
 */
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.ApexDoc')
public with sharing class WeaveGeneratePdfAction {

    public class GeneratePdfRequest {
        @InvocableVariable(label='Template Id' required=false description='The Weave_Template_Config__c (Document output type) to render. Leave blank to use Template API Name.')
        public Id templateId;

        @InvocableVariable(label='Template API Name' required=false description='API name of the PDF template (used when Template Id is blank).')
        public String templateApiName;

        @InvocableVariable(label='Record Id' required=true description='The source record used for rendering. The generated PDF is linked to this record.')
        public Id recordId;
    }

    public class GeneratePdfResult {
        @InvocableVariable(label='Success' description='True when the PDF was generated successfully.')
        public Boolean success;

        @InvocableVariable(label='Content Document Id' description='Id of the generated ContentDocument. Use as input to Send Weave Email to attach the PDF.')
        public Id contentDocumentId;

        @InvocableVariable(label='Error Message' description='Populated when success is false.')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Generate Weave PDF'
        description='Generates a PDF document from a Weave template and links it to the source record. Use the output Content Document Id as an attachment input on Send Weave Email.'
        category='Dynamic Communication Engine'
    )
    public static List<GeneratePdfResult> generatePdf(List<GeneratePdfRequest> requests) {
        List<GeneratePdfResult> results = new List<GeneratePdfResult>();
        for (GeneratePdfRequest req : requests) {
            results.add(processRequest(req));
        }
        return results;
    }

    private static GeneratePdfResult processRequest(GeneratePdfRequest req) {
        GeneratePdfResult result = new GeneratePdfResult();
        try {
            Id resolvedTemplateId = resolveTemplateId(req, result);
            if (!result.success) return result;

            ContentVersion cv = WeavePdfService.generatePdf(resolvedTemplateId, req.recordId);
            if (cv == null || cv.ContentDocumentId == null) {
                result.success = false;
                result.errorMessage = 'PDF generation returned no document. Please contact your administrator.';
                return result;
            }

            result.success = true;
            result.contentDocumentId = cv.ContentDocumentId;
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    private static Id resolveTemplateId(GeneratePdfRequest req, GeneratePdfResult result) {
        Id templateId = req.templateId;

        if (templateId == null && String.isNotBlank(req.templateApiName)) {
            List<Weave_Template_Config__c> byName = [
                SELECT Id FROM Weave_Template_Config__c
                WHERE API_Name__c = :req.templateApiName WITH USER_MODE LIMIT 1
            ];
            if (byName.isEmpty()) {
                result.success = false;
                result.errorMessage = 'Template not found. Please contact your administrator.';
                return null;
            }
            templateId = byName[0].Id;
        }

        if (templateId == null) {
            result.success = false;
            result.errorMessage = 'Template Id or Template API Name is required.';
            return null;
        }

        List<Weave_Template_Config__c> templates = [
            SELECT Status__c, Template_Output_Type__c
            FROM Weave_Template_Config__c WHERE Id = :templateId WITH USER_MODE LIMIT 1
        ];
        if (templates.isEmpty()) {
            result.success = false;
            result.errorMessage = 'Template not found. Please contact your administrator.';
            return null;
        }

        Weave_Template_Config__c tmpl = templates[0];
        if (tmpl.Status__c != 'Active') {
            result.success = false;
            result.errorMessage = 'Template is inactive. Please contact your administrator.';
            return null;
        }
        if (tmpl.Template_Output_Type__c == 'Email') {
            result.success = false;
            result.errorMessage = 'Template is not configured for PDF output. Set Output Type to Document or Both.';
            return null;
        }

        return templateId;
    }
}
