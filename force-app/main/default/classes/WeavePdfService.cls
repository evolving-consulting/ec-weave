public with sharing class WeavePdfService {

    public static ContentVersion generatePdf(Id templateId, Id recordId) {
        if (templateId == null) throw new AuraHandledException('Template Id is required.');
        if (recordId == null) throw new AuraHandledException('Record Id is required.');

        WeaveEmailTemplateRenderer.RenderedEmailDTO rendered = isDocumentTemplate(templateId)
            ? WeaveEmailTemplateRenderer.renderCanvas(templateId, recordId)
            : WeaveEmailTemplateRenderer.renderEmail(templateId, recordId);

        Boolean isCanvas = isDocumentTemplate(templateId);
        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('PDF_TEST')
            : Blob.toPdf(wrapForPdf(rendered.htmlBody, rendered.subject, isCanvas));

        ContentVersion cv = new ContentVersion();
        cv.Title = sanitizeTitle(rendered.subject);
        cv.PathOnClient = sanitizeFileName(rendered.subject) + '.pdf';
        cv.VersionData = pdfBlob;
        cv.FirstPublishLocationId = recordId;
        insert as user cv;

        List<ContentVersion> saved = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH USER_MODE LIMIT 1];
        return saved[0];
    }

    public static ContentVersion generateCombinedPdf(List<Id> templateIds, List<Id> recordIds, String title) {
        if (templateIds == null || templateIds.isEmpty()) throw new AuraHandledException('At least one template is required.');
        if (recordIds == null || recordIds.size() != templateIds.size()) throw new AuraHandledException('Template and record lists must match.');
        if (String.isBlank(title)) title = 'Combined Document';

        List<String> htmlParts = new List<String>();
        for (Integer i = 0; i < templateIds.size(); i++) {
            WeaveEmailTemplateRenderer.RenderedEmailDTO rendered =
                WeaveEmailTemplateRenderer.renderEmail(templateIds[i], recordIds[i]);
            if (i > 0) htmlParts.add('<div style="page-break-before:always;"></div>');
            htmlParts.add(rendered.htmlBody != null ? rendered.htmlBody : '');
        }

        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('PDF_TEST')
            : Blob.toPdf(wrapForPdf(String.join(htmlParts, '\n'), title));

        ContentVersion cv = new ContentVersion();
        cv.Title = sanitizeTitle(title);
        cv.PathOnClient = sanitizeFileName(title) + '.pdf';
        cv.VersionData = pdfBlob;
        insert as user cv;

        List<ContentVersion> saved = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH USER_MODE LIMIT 1];
        return saved[0];
    }

    public static ContentVersion previewPdf(String htmlBody, String title) {
        if (String.isBlank(htmlBody)) throw new AuraHandledException('HTML content is required.');
        if (String.isBlank(title)) title = 'Preview';

        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('PDF_TEST')
            : Blob.toPdf(wrapForPdf(htmlBody, title));

        ContentVersion cv = new ContentVersion();
        cv.Title = '[PREVIEW] ' + sanitizeTitle(title);
        cv.PathOnClient = sanitizeFileName(title) + '_preview.pdf';
        cv.VersionData = pdfBlob;
        // No FirstPublishLocationId — not linked to any record
        insert as user cv;

        List<ContentVersion> saved = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH USER_MODE LIMIT 1];
        return saved[0];
    }

    private static Boolean isDocumentTemplate(Id templateId) {
        try {
            List<Weave_Template_Config__c> t = [
                SELECT Template_Output_Type__c FROM Weave_Template_Config__c
                WHERE Id = :templateId WITH USER_MODE LIMIT 1
            ];
            return !t.isEmpty() && t[0].get('Template_Output_Type__c') == 'Document';
        } catch (Exception e) { return false; }
    }

    private static String wrapForPdf(String htmlBody, String title) {
        return wrapForPdf(htmlBody, title, false);
    }

    // isCanvas=true: canvas/document mode — zero body margins, brand elements use
    // position:fixed so they appear on every page without pushing canvas content off-page.
    private static String wrapForPdf(String htmlBody, String title, Boolean isCanvas) {
        String safeTitle = title != null ? title.escapeHtml4() : 'Document';
        String safeBody = htmlBody != null ? htmlBody : '';

        String baseFonts = 'font-family:Arial,Helvetica,sans-serif;font-size:11pt;color:#222;';

        String css;
        if (isCanvas == true) {
            css = '@page{margin:0;}'
                + 'html,body{margin:0;padding:0;' + baseFonts + '}'
                // Brand header/footer are fixed so they overlay every PDF page
                + '.weave-pdf-header{position:fixed;top:0;left:0;right:0;z-index:9999;}'
                + '.weave-pdf-footer{position:fixed;bottom:0;left:0;right:0;z-index:9999;}'
                // Page-break div between canvas pages
                + '.weave-page-break{page-break-before:always;break-before:page;}'
                + 'table{border-collapse:collapse;}'
                + 'img{max-width:100%;height:auto;}'
                + 'a{color:#0070d2;text-decoration:none;}';
        } else {
            css = 'body{' + baseFonts + 'margin:0;padding:16pt;}'
                // width:100% prevents fixed-pixel tables (e.g. width="756") from overflowing the page
                // and causing Salesforce's PDF renderer to duplicate content across pages.
                // td/th borders are intentionally NOT set here — templates control their own cell borders
                // via inline styles; the global border previously overrode them.
                + 'table{border-collapse:collapse;width:100%;}'
                // border="1" on a <table> creates black cell borders in Salesforce's PDF renderer
                // because border-color on the table doesn't cascade. inherit forces cells to pick
                // up the table's border-color.
                + 'td,th{border-color:inherit;}'
                + 'img{max-width:100%;height:auto;}'
                + 'a{color:#0070d2;text-decoration:none;}'
                + '.weave-page-break{page-break-before:always;break-before:page;}';
        }

        // Salesforce's PDF renderer doesn't cascade bgcolor attributes from <tr> to child <th>/<td>.
        // Pre-process the HTML: add an inline style with background-color for every bgcolor attribute
        // so the cell's own background renders correctly.
        safeBody = normalizeBgcolorForPdf(safeBody);

        return '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>' + safeTitle + '</title>'
            + '<style>' + css + '</style></head><body>' + safeBody + '</body></html>';
    }

    // Convert bgcolor HTML attributes to inline background-color CSS.
    // Salesforce's Blob.toPdf() renderer does not cascade bgcolor from <tr> to child cells,
    // so <th style="color:#fff"> on a <tr bgcolor="#1c1c1c"> renders white-on-white.
    // Injecting style="background-color:X" directly onto each element fixes this.
    // If a duplicate style attribute results, the renderer uses the first one — which is fine.
    private static String normalizeBgcolorForPdf(String html) {
        if (String.isBlank(html) || !html.containsIgnoreCase('bgcolor')) return html;
        // Replace bgcolor="X" with style="background-color:X" bgcolor="X"
        // Works for <tr>, <td>, <th>, <table> elements.
        return html.replaceAll('(?i)bgcolor\\s*=\\s*"([^"]+)"', 'style="background-color:$1" bgcolor="$1"');
    }

    private static String sanitizeTitle(String title) {
        if (String.isBlank(title)) return 'Document';
        return title.length() > 200 ? title.substring(0, 200) : title;
    }

    private static String sanitizeFileName(String title) {
        if (String.isBlank(title)) return 'document';
        String safe = title.replaceAll('[^A-Za-z0-9 _\\-]', '').trim().replaceAll('\\s+', '_');
        if (String.isBlank(safe)) safe = 'document';
        return safe.length() > 80 ? safe.substring(0, 80) : safe;
    }
}
