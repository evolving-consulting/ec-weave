public with sharing class WeavePdfService {

    public static ContentVersion generatePdf(Id templateId, Id recordId) {
        if (templateId == null) throw new AuraHandledException('Template Id is required.');
        if (recordId == null) throw new AuraHandledException('Record Id is required.');

        Boolean isCanvas = isDocumentTemplate(templateId);
        WeaveEmailTemplateRenderer.RenderedEmailDTO rendered = isCanvas
            ? WeaveEmailTemplateRenderer.renderCanvas(templateId, recordId)
            : WeaveEmailTemplateRenderer.renderEmail(templateId, recordId);

        String pageSizeProp = resolvePageSizeProperty(templateId);
        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('PDF_TEST')
            : Blob.toPdf(wrapForPdf(rendered.htmlBody, rendered.subject, isCanvas, pageSizeProp));

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
            Boolean isCanvas = isDocumentTemplate(templateIds[i]);
            WeaveEmailTemplateRenderer.RenderedEmailDTO rendered = isCanvas
                ? WeaveEmailTemplateRenderer.renderCanvas(templateIds[i], recordIds[i])
                : WeaveEmailTemplateRenderer.renderEmail(templateIds[i], recordIds[i]);
            if (i > 0) htmlParts.add('<div style="page-break-before:always;"></div>');
            htmlParts.add(rendered.htmlBody != null ? rendered.htmlBody : '');
        }

        String pageSizeProp = templateIds.isEmpty() ? '' : resolvePageSizeProperty(templateIds[0]);
        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('PDF_TEST')
            : Blob.toPdf(wrapForPdf(String.join(htmlParts, '\n'), title, false, pageSizeProp));

        ContentVersion cv = new ContentVersion();
        cv.Title = sanitizeTitle(title);
        cv.PathOnClient = sanitizeFileName(title) + '.pdf';
        cv.VersionData = pdfBlob;
        insert as user cv;

        List<ContentVersion> saved = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH USER_MODE LIMIT 1];
        return saved[0];
    }

    public static ContentVersion generatePacketPdf(Id packetId, Id sourceRecordId) {
        if (packetId == null) throw new AuraHandledException('Packet Id is required.');
        if (sourceRecordId == null) throw new AuraHandledException('Source Record Id is required.');

        List<Weave_Document_Packet__c> packets = [
            SELECT Id, Name, Title_Template__c,
                (SELECT Id, Template__c, Display_Order__c, Record_Source__c,
                        Static_Record_Id__c, Parent_Lookup_Field__c,
                        Template__r.Parent_Object_API_Name__c
                 FROM Packet_Items__r ORDER BY Display_Order__c ASC NULLS LAST)
            FROM Weave_Document_Packet__c
            WHERE Id = :packetId WITH USER_MODE LIMIT 1
        ];
        if (packets.isEmpty()) throw new AuraHandledException('Packet not found.');
        Weave_Document_Packet__c packet = packets[0];

        // Resolve merge tags in the title against the source record
        String title = String.isBlank(packet.Title_Template__c) ? packet.Name : packet.Title_Template__c;
        if (title.contains('{{')) {
            SObject src = resolveSourceRecord(sourceRecordId, title);
            if (src != null) {
                GenericMergeFieldResolver.MergeContext ctx = new GenericMergeFieldResolver.MergeContext();
                ctx.parentRecord = src;
                title = GenericMergeFieldResolver.resolveTemplate(title, ctx);
            }
        }

        List<String> htmlParts = new List<String>();
        for (Weave_Packet_Item__c item : packet.Packet_Items__r) {
            if (item.Template__c == null) continue;
            Id itemRecordId = resolveItemRecord(item, sourceRecordId);
            if (itemRecordId == null) continue;

            Boolean isCanvas = isDocumentTemplate(item.Template__c);
            WeaveEmailTemplateRenderer.RenderedEmailDTO rendered = isCanvas
                ? WeaveEmailTemplateRenderer.renderCanvas(item.Template__c, itemRecordId)
                : WeaveEmailTemplateRenderer.renderEmail(item.Template__c, itemRecordId);

            if (!htmlParts.isEmpty()) htmlParts.add('<div style="page-break-before:always;"></div>');
            htmlParts.add(rendered.htmlBody != null ? rendered.htmlBody : '');
        }

        if (htmlParts.isEmpty()) throw new AuraHandledException('No renderable items found in packet.');

        Id firstTemplateId = packet.Packet_Items__r.isEmpty() ? null : packet.Packet_Items__r[0].Template__c;
        String pageSizeProp = firstTemplateId != null ? resolvePageSizeProperty(firstTemplateId) : '';
        Blob pdfBlob = Test.isRunningTest()
            ? Blob.valueOf('PDF_TEST')
            : Blob.toPdf(wrapForPdf(String.join(htmlParts, '\n'), title, false, pageSizeProp));

        ContentVersion cv = new ContentVersion();
        cv.Title = sanitizeTitle(title);
        cv.PathOnClient = sanitizeFileName(title) + '.pdf';
        cv.VersionData = pdfBlob;
        cv.FirstPublishLocationId = sourceRecordId;
        insert as user cv;

        List<ContentVersion> saved = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id WITH USER_MODE LIMIT 1];
        return saved[0];
    }

    private static Id resolveItemRecord(Weave_Packet_Item__c item, Id sourceRecordId) {
        String src = item.Record_Source__c;
        if (src == 'Static Record') {
            return String.isNotBlank(item.Static_Record_Id__c) ? (Id) item.Static_Record_Id__c : null;
        }
        if (src == 'Parent Lookup Field' && String.isNotBlank(item.Parent_Lookup_Field__c)) {
            String objApi = item.Template__r.Parent_Object_API_Name__c;
            if (String.isBlank(objApi)) return sourceRecordId;
            try {
                String q = 'SELECT ' + String.escapeSingleQuotes(item.Parent_Lookup_Field__c)
                    + ' FROM ' + String.escapeSingleQuotes(objApi)
                    + ' WHERE Id = :sourceRecordId WITH USER_MODE LIMIT 1';
                List<SObject> rows = Database.query(q);
                if (!rows.isEmpty()) {
                    Object val = rows[0].get(item.Parent_Lookup_Field__c);
                    return val != null ? (Id) val : null;
                }
            } catch (Exception e) { return null; }
        }
        return sourceRecordId;
    }

    private static SObject resolveSourceRecord(Id recordId, String template) {
        String objectType;
        try { objectType = recordId.getSObjectType().getDescribe().getName(); } catch (Exception e) { return null; }
        // Extract field API names from {{FieldName}} placeholders
        Set<String> fields = new Set<String>{ 'Id', 'Name' };
        Pattern p = Pattern.compile('\\{\\{([A-Za-z_][A-Za-z0-9_.]*(?:__[cr])?)\\}\\}');
        Matcher m = p.matcher(template);
        while (m.find()) { fields.add(m.group(1).split('\\.')[0]); }
        try {
            String q = 'SELECT ' + String.join(new List<String>(fields), ',')
                + ' FROM ' + String.escapeSingleQuotes(objectType)
                + ' WHERE Id = :recordId WITH USER_MODE LIMIT 1';
            List<SObject> rows = Database.query(q);
            return rows.isEmpty() ? null : rows[0];
        } catch (Exception e) { return null; }
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

    private static String resolvePageSizeProperty(Id templateId) {
        try {
            List<Weave_Template_Config__c> rows = [
                SELECT Pdf_Page_Size__c, Pdf_Page_Width_In__c, Pdf_Page_Height_In__c
                FROM Weave_Template_Config__c WHERE Id = :templateId WITH USER_MODE LIMIT 1
            ];
            if (rows.isEmpty()) return '';
            Weave_Template_Config__c t = rows[0];
            String size = (String) t.get('Pdf_Page_Size__c');
            if (String.isBlank(size) || size == 'Letter') return '';
            Decimal w, h;
            if      (size == 'Legal')  { w = 8.5;   h = 14.0;  }
            else if (size == 'A4')     { w = 8.27;  h = 11.69; }
            else if (size == 'A3')     { w = 11.69; h = 16.54; }
            else if (size == 'A5')     { w = 5.83;  h = 8.27;  }
            else if (size == 'Custom') { w = t.Pdf_Page_Width_In__c; h = t.Pdf_Page_Height_In__c; }
            if (w == null || h == null) return '';
            return 'size:' + w + 'in ' + h + 'in;';
        } catch (Exception e) { return ''; }
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
        return wrapForPdf(htmlBody, title, false, '');
    }

    private static String wrapForPdf(String htmlBody, String title, Boolean isCanvas) {
        return wrapForPdf(htmlBody, title, isCanvas, '');
    }

    // pageSizeProp: CSS property string like "size:8.5in 14.0in;" or "" for default (Letter)
    private static String wrapForPdf(String htmlBody, String title, Boolean isCanvas, String pageSizeProp) {
        String safeTitle = title != null ? title.escapeHtml4() : 'Document';
        String safeBody = htmlBody != null ? htmlBody : '';
        String sizeProp = String.isBlank(pageSizeProp) ? '' : pageSizeProp;

        String baseFonts = 'font-family:Arial,Helvetica,sans-serif;font-size:11pt;color:#222;';

        String css;
        if (isCanvas == true) {
            css = '@page{margin:0;' + sizeProp + '}'
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
            String pageRule = String.isBlank(sizeProp) ? '' : '@page{' + sizeProp + '}';
            css = pageRule
                + 'body{' + baseFonts + 'margin:0;padding:16pt;}'
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
