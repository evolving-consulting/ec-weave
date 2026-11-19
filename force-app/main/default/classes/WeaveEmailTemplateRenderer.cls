/**
 * Renders Weave templates by assembling component HTML_Output values by region,
 * executing linked queries for Related Table components, and resolving merge tags.
 */
public with sharing class WeaveEmailTemplateRenderer {

    private static Map<String, SObject> standardMergeAliases;

    public static RenderedEmailDTO renderEmail(Id templateId, Id recordId) {
        return renderEmail(templateId, recordId, true);
    }

    public static RenderedEmailDTO renderEmail(Id templateId, Id recordId, Boolean enforceActive) {
        if (templateId == null) throw new AuraHandledException('Template Id is required.');
        if (recordId == null) throw new AuraHandledException('Record Id is required.');

        Weave_Template_Config__c template = enforceActive ? loadTemplate(templateId) : loadTemplateForPreview(templateId);
        List<Weave_Template_Component__c> components = loadComponents(templateId);

        SObject parentRecord = loadParentRecord(template, components, recordId);

        GenericMergeFieldResolver.MergeContext context = buildContext(parentRecord, template.Parent_Object_API_Name__c);
        context.renderHtmlFormattedFields = true;

        String headerHtml = assembleRegion(components, 'Header', parentRecord, template.Parent_Object_API_Name__c, recordId, context);
        String bodyHtml   = assembleRegion(components, 'Body',   parentRecord, template.Parent_Object_API_Name__c, recordId, context);
        String footerHtml = assembleRegion(components, 'Footer', parentRecord, template.Parent_Object_API_Name__c, recordId, context);

        Weave_Brand__c brand = template.Brand__c != null ? loadBrand(template.Brand__c, enforceActive) : null;
        String brandHeader = brand != null ? resolveBrandMergeTags(brand.Header_HTML__c, brand) : '';
        String brandFooter = brand != null ? resolveBrandMergeTags(brand.Footer_HTML__c, brand) : '';

        String fullHtml = brandHeader
                        + (headerHtml == null ? '' : headerHtml)
                        + (bodyHtml == null ? '' : bodyHtml)
                        + (footerHtml == null ? '' : footerHtml)
                        + brandFooter;

        String subjectTemplate = (String.isNotBlank(template.Subject_Variant_B__c) && Math.random() >= 0.5)
            ? template.Subject_Variant_B__c
            : template.Subject_Template__c;
        String subject = GenericMergeFieldResolver.resolveTemplate(subjectTemplate, buildContext(parentRecord, template.Parent_Object_API_Name__c));
        String plainText = stripHtml(fullHtml);

        return new RenderedEmailDTO(subject, fullHtml, plainText);
    }

    // ── Load template ─────────────────────────────────────────────────────────

    private static Weave_Template_Config__c loadTemplate(Id templateId) {
        List<Weave_Template_Config__c> templates = [
            SELECT Id, Name, Status__c, Parent_Object_API_Name__c, Subject_Template__c, Subject_Variant_B__c,
                Default_From_Email__c, Allow_User_Edit_Before_Send__c, Store_Email_History__c, Brand__c
            FROM Weave_Template_Config__c
            WHERE Id = :templateId
            WITH USER_MODE
            LIMIT 1
        ];
        if (templates.isEmpty()) throw new AuraHandledException('Template not found.');
        Weave_Template_Config__c template = templates[0];
        if (template.Status__c != 'Active') throw new AuraHandledException('Template is not active.');
        if (String.isBlank(template.Parent_Object_API_Name__c)) throw new AuraHandledException('Template parent object is not configured.');
        GenericDynamicQueryService.assertValidObject(template.Parent_Object_API_Name__c);
        return template;
    }

    private static Weave_Template_Config__c loadTemplateForPreview(Id templateId) {
        List<Weave_Template_Config__c> templates = [
            SELECT Id, Name, Status__c, Parent_Object_API_Name__c, Subject_Template__c, Subject_Variant_B__c,
                Default_From_Email__c, Allow_User_Edit_Before_Send__c, Store_Email_History__c, Brand__c
            FROM Weave_Template_Config__c
            WHERE Id = :templateId
            WITH USER_MODE
            LIMIT 1
        ];
        if (templates.isEmpty()) throw new AuraHandledException('Template not found.');
        Weave_Template_Config__c template = templates[0];
        if (String.isBlank(template.Parent_Object_API_Name__c)) throw new AuraHandledException('Template parent object is not configured.');
        GenericDynamicQueryService.assertValidObject(template.Parent_Object_API_Name__c);
        return template;
    }

    private static List<Weave_Template_Component__c> loadComponents(Id templateId) {
        return [
            SELECT Id, Name, Component_Type__c, Region__c, Display_Order__c,
                Linked_Query__c, Linked_Query__r.SOQL_Query__c, Linked_Query__r.Parent_Lookup_Field__c,
                Config_JSON__c, HTML_Output__c,
                Canvas_Mode__c, Canvas_X__c, Canvas_Y__c, Canvas_W__c, Canvas_H__c, Canvas_Page__c
            FROM Weave_Template_Component__c
            WHERE Weave_Template_Config__c = :templateId
            WITH USER_MODE
            ORDER BY Region__c ASC, Display_Order__c ASC NULLS LAST, Name ASC
        ];
    }

    // ── Assemble region HTML ───────────────────────────────────────────────────

    private static String assembleRegion(
        List<Weave_Template_Component__c> components,
        String region,
        SObject parentRecord,
        String parentObjectApiName,
        Id recordId,
        GenericMergeFieldResolver.MergeContext context
    ) {
        String html = '';
        for (Weave_Template_Component__c c : components) {
            if (c.Region__c != region) continue;
            html += renderComponent(c, parentRecord, parentObjectApiName, recordId, context);
        }
        return html;
    }

    private static String renderComponent(
        Weave_Template_Component__c c,
        SObject parentRecord,
        String parentObjectApiName,
        Id recordId,
        GenericMergeFieldResolver.MergeContext context
    ) {
        if (c.Component_Type__c == 'Related Table') {
            return renderRelatedTableComponent(c, parentRecord, parentObjectApiName, recordId);
        }
        // All other types: resolve merge tags in HTML_Output
        if (String.isBlank(c.HTML_Output__c)) return '';
        return GenericMergeFieldResolver.resolveTemplate(c.HTML_Output__c, context);
    }

    private static String renderRelatedTableComponent(
        Weave_Template_Component__c c,
        SObject parentRecord,
        String parentObjectApiName,
        Id recordId
    ) {
        if (c.Linked_Query__c == null) return '';
        String storedSoql = c.Linked_Query__r.SOQL_Query__c;
        String parentLookupField = c.Linked_Query__r.Parent_Lookup_Field__c;
        if (String.isBlank(storedSoql) || String.isBlank(parentLookupField)) return '';

        // Extract the child object name from the stored SOQL (SELECT ... FROM <ObjectName> ...)
        String childObjectApiName = extractObjectName(storedSoql);
        if (String.isBlank(childObjectApiName)) return '';

        // Validate parent lookup field before injecting it into the query
        GenericDynamicQueryService.assertValidField(childObjectApiName, parentLookupField);

        // Build final SOQL: inject WHERE + WITH USER_MODE before any ORDER BY / LIMIT
        String finalSoql = injectParentFilter(storedSoql, parentLookupField);

        List<SObject> childRecords;
        try {
            childRecords = Database.query(finalSoql);
        } catch (QueryException e) {
            throw new AuraHandledException('Unable to execute query for Related Table component: ' + e.getMessage());
        }
        if (childRecords == null || childRecords.isEmpty()) return '';

        // Use HTML_Output as the row template; resolve merge tags per child record
        if (String.isBlank(c.HTML_Output__c)) return '';

        // If the stored output contains a full table structure (thead + tbody), split it so
        // the header is emitted once and only the body rows are repeated per child record.
        String htmlTemplate = c.HTML_Output__c;
        Pattern tbodyOpen  = Pattern.compile('(?i)<tbody[^>]*>');
        Pattern tbodyClose = Pattern.compile('(?i)</tbody>');
        Matcher mOpen  = tbodyOpen.matcher(htmlTemplate);
        Matcher mClose = tbodyClose.matcher(htmlTemplate);

        String tablePrefix = '';
        String rowTemplate = htmlTemplate;
        String tableSuffix = '';

        if (mOpen.find() && mClose.find()) {
            Integer bodyStart = mOpen.start();
            Integer bodyEnd   = mOpen.end();
            Integer closeStart = mClose.start();
            Integer closeEnd   = mClose.end();
            tablePrefix = htmlTemplate.substring(0, bodyEnd);         // …<tbody>
            rowTemplate = htmlTemplate.substring(bodyEnd, closeStart); // <tr>…</tr>
            tableSuffix = htmlTemplate.substring(closeStart);          // </tbody>…
        }

        String tableHtml = tablePrefix;
        for (SObject childRecord : childRecords) {
            GenericMergeFieldResolver.MergeContext childContext = buildContext(childRecord, parentObjectApiName);
            tableHtml += GenericMergeFieldResolver.resolveTemplate(rowTemplate, childContext);
        }
        tableHtml += tableSuffix;
        return tableHtml;
    }

    // ── Parent record loading ─────────────────────────────────────────────────

    private static SObject loadParentRecord(
        Weave_Template_Config__c template,
        List<Weave_Template_Component__c> components,
        Id recordId
    ) {
        Set<String> fieldPaths = collectParentFieldPaths(components, template);
        fieldPaths.add('Id');
        fieldPaths.add('Name');
        // Always try to load Owner for Sender.Owner merge tags
        try {
            fieldPaths.add('OwnerId');
        } catch (Exception ignored) {}
        return GenericDynamicQueryService.queryRecordById(
            template.Parent_Object_API_Name__c, recordId, fieldPaths
        );
    }

    private static Set<String> collectParentFieldPaths(
        List<Weave_Template_Component__c> components,
        Weave_Template_Config__c template
    ) {
        Set<String> paths = new Set<String>();
        // Collect from subject template
        if (!String.isBlank(template.Subject_Template__c)) {
            for (String path : GenericMergeFieldResolver.extractPlaceholders(template.Subject_Template__c)) {
                if (path.startsWith('Parent.')) {
                    paths.add(path.substringAfter('Parent.'));
                }
            }
        }
        // Collect from each component's HTML_Output (non-related-table components only)
        for (Weave_Template_Component__c c : components) {
            if (c.Component_Type__c == 'Related Table') continue;
            if (String.isBlank(c.HTML_Output__c)) continue;
            for (String path : GenericMergeFieldResolver.extractPlaceholders(c.HTML_Output__c)) {
                if (path.startsWith('Parent.')) {
                    paths.add(path.substringAfter('Parent.'));
                } else if (!path.contains('.')) {
                    paths.add(path);
                }
            }
        }
        return paths;
    }

    // ── Merge context ─────────────────────────────────────────────────────────

    private static GenericMergeFieldResolver.MergeContext buildContext(
        SObject parentRecord,
        String parentObjectApiName
    ) {
        GenericMergeFieldResolver.MergeContext context = new GenericMergeFieldResolver.MergeContext();
        context.parentRecord = parentRecord;
        context.parentObjectApiName = parentObjectApiName;
        context.sectionHtmlByKey = new Map<String, String>();
        context.aliasRecords = loadStandardMergeAliases();
        context.aliasValues = loadStandardMergeAliasValues(parentRecord);
        context.escapeHtml = false;
        context.renderHtmlFormattedFields = true;
        return context;
    }

    private static Map<String, SObject> loadStandardMergeAliases() {
        if (standardMergeAliases != null) return standardMergeAliases;
        standardMergeAliases = new Map<String, SObject>();
        Id currentUserId = UserInfo.getUserId();
        List<User> currentUsers = [
            SELECT Id, Name, FirstName, LastName, Email, Phone, MobilePhone,
                Street, City, State, PostalCode, Country
            FROM User WHERE Id = :currentUserId WITH USER_MODE LIMIT 1
        ];
        if (!currentUsers.isEmpty()) standardMergeAliases.put('Sender', currentUsers[0]);
        List<Organization> orgs = [
            SELECT Id, Name, Street, City, State, PostalCode, Country
            FROM Organization WITH USER_MODE LIMIT 1
        ];
        if (!orgs.isEmpty()) standardMergeAliases.put('Organization', orgs[0]);
        return standardMergeAliases;
    }

    private static Map<String, String> loadStandardMergeAliasValues(SObject parentRecord) {
        Map<String, String> values = new Map<String, String>();
        // Delegate address formatting if Sender/Org are loaded
        SObject sender = standardMergeAliases != null ? standardMergeAliases.get('Sender') : null;
        SObject org = standardMergeAliases != null ? standardMergeAliases.get('Organization') : null;
        values.put('Sender.Address', formatAddress(sender));
        values.put('Organization.Address', formatAddress(org));
        return values;
    }

    private static String formatAddress(SObject record) {
        if (record == null) return '';
        List<String> parts = new List<String>();
        addPart(parts, record, 'Street');
        addPart(parts, record, 'City');
        addPart(parts, record, 'State');
        addPart(parts, record, 'PostalCode');
        addPart(parts, record, 'Country');
        return String.join(parts, ', ');
    }

    private static void addPart(List<String> parts, SObject record, String field) {
        try {
            Object val = record.get(field);
            if (val != null && !String.isBlank(String.valueOf(val))) {
                parts.add(String.valueOf(val));
            }
        } catch (Exception ignored) {}
    }

    // ── Utilities ─────────────────────────────────────────────────────────────

    // ── SOQL helpers ──────────────────────────────────────────────────────────

    @SuppressWarnings('PMD.ApexSOQLInjection')
    private static String injectParentFilter(String storedSoql, String parentLookupField) {
        // Insert WHERE clause + WITH USER_MODE before ORDER BY / LIMIT / GROUP BY
        String upper = storedSoql.toUpperCase();
        Integer insertAt = -1;
        for (String keyword : new List<String>{ 'ORDER BY', 'LIMIT', 'GROUP BY', 'HAVING' }) {
            Integer pos = upper.indexOf(keyword);
            if (pos >= 0 && (insertAt < 0 || pos < insertAt)) {
                insertAt = pos;
            }
        }
        // parentLookupField is validated by assertValidField before this call
        String filter = ' WHERE ' + parentLookupField + ' = :recordId WITH USER_MODE';
        if (insertAt < 0) {
            return storedSoql.trim() + filter;
        }
        return storedSoql.substring(0, insertAt).trim() + filter + ' ' + storedSoql.substring(insertAt).trim();
    }

    private static String extractObjectName(String soql) {
        if (String.isBlank(soql)) return null;
        Matcher m = Pattern.compile('(?i)\\bFROM\\s+(\\w+)').matcher(soql);
        return m.find() ? m.group(1) : null;
    }

    private static String stripHtml(String input) {
        if (input == null) return '';
        String plain = input.replaceAll('(?i)<br\\s*/?>', '\n');
        plain = plain.replaceAll('<[^>]+>', '');
        plain = plain.replace('&nbsp;', ' ').replace('&amp;', '&')
                     .replace('&lt;', '<').replace('&gt;', '>')
                     .replace('&quot;', '"').replace('&#39;', '\'');
        return plain;
    }

    // ── Brand helpers ─────────────────────────────────────────────────────────

    private static Weave_Brand__c loadBrand(Id brandId, Boolean enforceActive) {
        List<Weave_Brand__c> brands = [
            SELECT Id, Display_Name__c, Primary_Color__c, Secondary_Color__c, Logo_URL__c,
                Physical_Address__c, Unsubscribe_URL__c, Unsubscribe_Label__c,
                Header_HTML__c, Footer_HTML__c, Status__c
            FROM Weave_Brand__c
            WHERE Id = :brandId
            WITH USER_MODE
            LIMIT 1
        ];
        if (brands.isEmpty()) return null;
        if (enforceActive && brands[0].Status__c != 'Active') return null;
        return brands[0];
    }

    private static String resolveBrandMergeTags(String html, Weave_Brand__c brand) {
        if (String.isBlank(html) || brand == null) return '';
        String result = html;
        result = result.replace('{{Brand.PrimaryColor}}',   brand.Primary_Color__c   ?? '');
        result = result.replace('{{Brand.SecondaryColor}}', brand.Secondary_Color__c ?? '');
        result = result.replace('{{Brand.LogoUrl}}',        brand.Logo_URL__c        ?? '');
        result = result.replace('{{Brand.DisplayName}}',    brand.Display_Name__c    ?? '');
        result = result.replace('{{Brand.PhysicalAddress}}',brand.Physical_Address__c ?? '');
        String unsubLink = '';
        if (String.isNotBlank(brand.Unsubscribe_URL__c)) {
            String label = String.isBlank(brand.Unsubscribe_Label__c) ? 'Unsubscribe' : brand.Unsubscribe_Label__c;
            unsubLink = '<a href="' + brand.Unsubscribe_URL__c + '">' + label + '</a>';
        }
        result = result.replace('{{Brand.UnsubscribeLink}}', unsubLink);
        return result;
    }

    // ── Canvas rendering ──────────────────────────────────────────────────────

    public static RenderedEmailDTO renderCanvas(Id templateId, Id recordId) {
        return renderCanvas(templateId, recordId, true);
    }

    public static RenderedEmailDTO renderCanvas(Id templateId, Id recordId, Boolean enforceActive) {
        if (templateId == null) throw new AuraHandledException('Template Id is required.');
        if (recordId == null) throw new AuraHandledException('Record Id is required.');

        Weave_Template_Config__c template = enforceActive ? loadTemplate(templateId) : loadTemplateForPreview(templateId);
        List<Weave_Template_Component__c> components = loadComponents(templateId);

        SObject parentRecord = loadParentRecord(template, components, recordId);
        GenericMergeFieldResolver.MergeContext context = buildContext(parentRecord, template.Parent_Object_API_Name__c);
        context.renderHtmlFormattedFields = true;

        // Determine page dimensions
        String pageSizeField = 'Canvas_Page_Size__c';
        String orientField   = 'Canvas_Orientation__c';
        Boolean landscape    = false;
        Decimal pageW = 8.5;
        Decimal pageH = 11.0;
        try {
            String pageSize = (String) template.get(pageSizeField);
            String orient   = (String) template.get(orientField);
            if (pageSize == 'A4') { pageW = 8.27; pageH = 11.69; }
            if (orient == 'Landscape') { Decimal tmp = pageW; pageW = pageH; pageH = tmp; landscape = true; }
        } catch (Exception ex) { /* fields not yet deployed — use Letter portrait defaults */ }

        // Group canvas components by page
        Map<Integer, List<Weave_Template_Component__c>> byPage = new Map<Integer, List<Weave_Template_Component__c>>();
        for (Weave_Template_Component__c c : components) {
            if (c.Canvas_Mode__c != true) continue;
            Integer pg = c.Canvas_Page__c != null ? c.Canvas_Page__c.intValue() : 1;
            if (!byPage.containsKey(pg)) byPage.put(pg, new List<Weave_Template_Component__c>());
            byPage.get(pg).add(c);
        }
        if (byPage.isEmpty()) {
            // No canvas components — fall back to email rendering
            return renderEmail(templateId, recordId, enforceActive);
        }

        List<Integer> pageNums = new List<Integer>(byPage.keySet());
        pageNums.sort();

        List<String> pageDivs = new List<String>();
        for (Integer pg : pageNums) {
            if (!pageDivs.isEmpty()) pageDivs.add('<div style="page-break-before:always;"></div>');
            String pageHtml = '<div style="position:relative;width:' + pageW + 'in;height:' + pageH + 'in;overflow:hidden;">';
            for (Weave_Template_Component__c c : byPage.get(pg)) {
                Decimal x = c.Canvas_X__c != null ? c.Canvas_X__c : 0;
                Decimal y = c.Canvas_Y__c != null ? c.Canvas_Y__c : 0;
                Decimal w = c.Canvas_W__c != null ? c.Canvas_W__c : 1;
                Decimal h = c.Canvas_H__c != null ? c.Canvas_H__c : 0.5;
                String boxStyle = 'position:absolute;left:' + x + 'in;top:' + y + 'in;width:' + w + 'in;height:' + h + 'in;overflow:hidden;';
                String innerHtml = renderComponent(c, parentRecord, template.Parent_Object_API_Name__c, recordId, context);
                pageHtml += '<div style="' + boxStyle + '">' + (innerHtml != null ? innerHtml : '') + '</div>';
            }
            pageHtml += '</div>';
            pageDivs.add(pageHtml);
        }

        String canvasHtml = String.join(pageDivs, '\n');

        // Apply brand header/footer (same as renderEmail)
        Weave_Brand__c brand = template.Brand__c != null ? loadBrand(template.Brand__c, enforceActive) : null;
        String brandHeader = brand != null ? resolveBrandMergeTags(brand.Header_HTML__c, brand) : '';
        String brandFooter = brand != null ? resolveBrandMergeTags(brand.Footer_HTML__c, brand) : '';
        String fullHtml = brandHeader + canvasHtml + brandFooter;

        String subject  = String.isNotBlank(template.Subject_Template__c)
            ? GenericMergeFieldResolver.resolveTemplate(template.Subject_Template__c, buildContext(parentRecord, template.Parent_Object_API_Name__c))
            : template.Name;

        return new RenderedEmailDTO(subject, fullHtml, stripHtml(fullHtml));
    }

    // ── Rendered Email DTO ────────────────────────────────────────────────────

    public class RenderedEmailDTO {
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String htmlBody { get; set; }
        @AuraEnabled public String plainTextBody { get; set; }

        public RenderedEmailDTO(String subject, String htmlBody, String plainTextBody) {
            this.subject = subject;
            this.htmlBody = htmlBody;
            this.plainTextBody = plainTextBody;
        }
    }
}
