public with sharing class WeavePdfService {

    public static ContentVersion generatePdf(Id templateId, Id recordId) {
        if (templateId == null) throw new AuraHandledException('Template Id is required.');
        if (recordId == null) throw new AuraHandledException('Record Id is required.');

        WeaveEmailTemplateRenderer.RenderedEmailDTO rendered =
            WeaveEmailTemplateRenderer.renderEmail(templateId, recordId);

        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('PDF_TEST')
            : Blob.toPdf(wrapForPdf(rendered.htmlBody, rendered.subject));

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

    private static String wrapForPdf(String htmlBody, String title) {
        String safeTitle = title != null ? title.escapeHtml4() : 'Document';
        String safeBody = htmlBody != null ? htmlBody : '';
        return '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>' + safeTitle + '</title>'
            + '<style>'
            + 'body{font-family:Arial,Helvetica,sans-serif;font-size:11pt;color:#222;margin:0;padding:16pt;}'
            + 'table{border-collapse:collapse;width:100%;}'
            + 'td,th{border:1px solid #ccc;padding:4pt 6pt;}'
            + 'th{background:#f5f5f5;font-weight:bold;}'
            + 'img{max-width:100%;}'
            + 'a{color:#0070d2;text-decoration:none;}'
            + '</style></head><body>' + safeBody + '</body></html>';
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
