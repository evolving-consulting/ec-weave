/**
 * Translates Weave merge field syntax ({{...}}) to AMPscript variable
 * references for Marketing Cloud Next email assets.
 *
 * Translation rules:
 *   {{Parent.FieldName}}                     →  %%=v(@ParentFieldName)=%%
 *   {{DataCloud.ObjectApiName.AttrName}}     →  %%=v(@DataCloud_ObjectApiNameAttrName)=%%
 *   {{Flow.variableName}}                    →  %%=v(@Flow_variableName)=%%
 *   {{FieldName}} / {{Child.Field}}          →  %%=v(@ChildField)=%%  (child-row context)
 *   {{Section.ApiName}}                      →  left as-is (pre-rendered HTML block)
 *   {{Brand.Attr}}                           →  left as-is (resolved by Weave brand engine)
 */
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.ApexDoc')
public with sharing class MergeFieldTranslator {

    private static final Pattern MERGE_TAG = Pattern.compile(
        '\\{\\{\\s*([A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)*)\\s*\\}\\}'
    );

    // ── Public API ────────────────────────────────────────────────────────────

    public class TranslationResult {
        public String  translatedContent   { get; set; }
        public Integer mergeFieldsFound    { get; set; }
        public Integer mergeFieldsTranslated { get; set; }
        public Integer mergeFieldsSkipped  { get; set; }
        public List<String> skippedTags    { get; set; }

        public TranslationResult() {
            this.mergeFieldsFound      = 0;
            this.mergeFieldsTranslated = 0;
            this.mergeFieldsSkipped    = 0;
            this.skippedTags           = new List<String>();
        }
    }

    /**
     * Translates all supported merge fields in content to AMPscript.
     * Tags that should not be translated (Section, Brand) are preserved.
     * Uses index-based scanning since Apex Matcher lacks appendReplacement/appendTail.
     */
    public static TranslationResult translate(String content) {
        TranslationResult result = new TranslationResult();
        if (String.isBlank(content)) {
            result.translatedContent = content;
            return result;
        }

        List<String> parts    = new List<String>();
        String       remaining = content;
        Integer      startIdx  = remaining.indexOf('{{');

        while (startIdx != -1) {
            parts.add(remaining.substring(0, startIdx));
            remaining = remaining.substring(startIdx + 2);

            Integer endIdx = remaining.indexOf('}}');
            if (endIdx == -1) {
                // Unclosed tag — treat as literal text
                parts.add('{{' + remaining);
                remaining = '';
                break;
            }

            String tagContent = remaining.substring(0, endIdx).trim();
            remaining = remaining.substring(endIdx + 2);
            result.mergeFieldsFound++;

            String replacement = translateTag(tagContent);
            if (replacement == null) {
                parts.add('{{' + tagContent + '}}');
                result.mergeFieldsSkipped++;
                result.skippedTags.add('{{' + tagContent + '}}');
            } else {
                parts.add(replacement);
                result.mergeFieldsTranslated++;
            }

            startIdx = remaining.indexOf('{{');
        }
        parts.add(remaining);

        result.translatedContent = String.join(parts, '');
        return result;
    }

    /**
     * Translates a single bare tag expression (without {{ }}) to its AMPscript form.
     * Returns null if the tag should be preserved as-is.
     */
    public static String translateTag(String tag) {
        if (String.isBlank(tag)) return null;

        List<String> parts = tag.split('\\.');
        String prefix = parts[0];

        // Preserve Section and Brand tags — Weave renders these before MCN publish
        if (prefix == 'Section' || prefix == 'Brand') {
            return null;
        }

        return '%%=v(@' + sanitize(tag) + ')=%%';
    }

    /**
     * Converts a merge field tag path to a valid AMPscript variable name.
     * Dots become underscores; all other non-alphanumeric chars are removed.
     * Example: "Parent.Account.Name" → "ParentAccountName"
     * Example: "DataCloud.Contact__dlm.Email__c" → "DataCloud_Contact__dlmEmail__c"
     */
    public static String sanitize(String tag) {
        if (String.isBlank(tag)) return '';
        // Split on dots. If a segment ends with __dlm or __dll (Data Cloud suffix),
        // the next segment is joined directly (no underscore) to preserve the MCN field format.
        // Example: "DataCloud.Contact__dlm.Email__c" → "DataCloud_Contact__dlmEmail__c"
        List<String> parts = tag.split('\\.');
        String result = parts[0];
        for (Integer i = 1; i < parts.size(); i++) {
            if (result.endsWith('__dlm') || result.endsWith('__dll')) {
                result = result + parts[i];
            } else {
                result = result + '_' + parts[i];
            }
        }
        // Remove any character that is not alphanumeric or underscore
        result = result.replaceAll('[^A-Za-z0-9_]', '');
        // Strip leading/trailing underscores
        result = result.replaceAll('^_+|_+$', '');
        return result;
    }

    // ── Convenience: build AMPscript SET block from a list of variable names ──

    /**
     * Returns an AMPscript SET block that declares variables as empty strings.
     * Place this at the top of an MCN email template so all variables are defined.
     */
    public static String buildVariableDeclarations(Set<String> variableNames) {
        if (variableNames == null || variableNames.isEmpty()) return '';
        List<String> lines = new List<String>{ '%%[' };
        for (String name : variableNames) {
            lines.add('  SET @' + sanitize(name) + ' = ""');
        }
        lines.add(']%%');
        return String.join(lines, '\n');
    }
}
