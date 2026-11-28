/**
 * Validates merge field syntax inside Weave template content.
 * Supports three source types: Parent (SObject fields), Flow (flow variables),
 * and DataCloud (Data Cloud object attributes).
 */
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.NcssMethodCount,PMD.NcssTypeCount,PMD.NcssConstructorCount')
@SuppressWarnings('PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.ApexDoc')
public with sharing class MergeFieldValidator {

    private static final Pattern ANY_TAG = Pattern.compile(
        '\\{\\{\\s*([A-Za-z_][A-Za-z0-9_]*(__(c|r))?(\\.[A-Za-z_][A-Za-z0-9_]*(__(c|r))?){0,3})\\s*\\}\\}'
    );

    private static final Set<String> VALID_BRAND_ATTRS = new Set<String>{
        'PrimaryColor', 'SecondaryColor', 'LogoUrl',
        'DisplayName', 'PhysicalAddress', 'UnsubscribeLink'
    };

    private static final Set<String> STANDARD_ALIASES = new Set<String>{
        'Sender', 'Organization'
    };

    // ── Public DTOs ───────────────────────────────────────────────────────────

    public class ValidationResult {
        @AuraEnabled public Boolean isValid { get; set; }
        @AuraEnabled public List<ValidationMessage> errors { get; set; }
        @AuraEnabled public List<ValidationMessage> warnings { get; set; }

        public ValidationResult() {
            this.isValid = true;
            this.errors = new List<ValidationMessage>();
            this.warnings = new List<ValidationMessage>();
        }
    }

    public class ValidationMessage {
        @AuraEnabled public String tag        { get; set; }
        @AuraEnabled public String message    { get; set; }
        @AuraEnabled public String sourceType { get; set; }

        public ValidationMessage(String tag, String message, String sourceType) {
            this.tag        = tag;
            this.message    = message;
            this.sourceType = sourceType;
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Scan all {{...}} tags in templateContent and validate each one.
     * Pass parentObjectApiName to also check whether Parent fields exist on that object.
     */
    public static ValidationResult validateTemplate(String templateContent, String parentObjectApiName) {
        ValidationResult result = new ValidationResult();
        if (String.isBlank(templateContent)) {
            return result;
        }
        Set<String> seen = new Set<String>();
        Matcher m = ANY_TAG.matcher(templateContent);
        while (m.find()) {
            String tag = m.group(1).trim();
            if (!seen.add(tag)) continue; // skip duplicates
            validateTag(tag, parentObjectApiName, result);
        }
        result.isValid = result.errors.isEmpty();
        return result;
    }

    /**
     * Validate a single merge field expression (with or without {{ }}).
     */
    public static ValidationResult validateMergeField(String mergeField, String parentObjectApiName) {
        ValidationResult result = new ValidationResult();
        if (String.isBlank(mergeField)) {
            return result;
        }
        String tag = mergeField.trim();
        if (tag.startsWith('{{') && tag.endsWith('}}')) {
            tag = tag.substring(2, tag.length() - 2).trim();
        }
        validateTag(tag, parentObjectApiName, result);
        result.isValid = result.errors.isEmpty();
        return result;
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    @TestVisible
    private static void validateTag(String tag, String parentObjectApiName, ValidationResult result) {
        if (String.isBlank(tag)) return;

        List<String> segments = tag.split('\\.');
        String prefix = segments[0];

        if (prefix == 'Section') {
            // Section tags are resolved by query API name — always structurally valid
            if (segments.size() != 2) {
                result.errors.add(new ValidationMessage(
                    '{{' + tag + '}}', 'Section tags must follow the format {{Section.queryApiName}}.', 'Section'
                ));
            }
            return;
        }

        if (prefix == 'Brand') {
            if (segments.size() != 2 || !VALID_BRAND_ATTRS.contains(segments[1])) {
                result.warnings.add(new ValidationMessage(
                    '{{' + tag + '}}',
                    'Unrecognized Brand attribute. Valid: ' + String.join(new List<String>(VALID_BRAND_ATTRS), ', ') + '.',
                    'Brand'
                ));
            }
            return;
        }

        if (STANDARD_ALIASES.contains(prefix)) {
            if (segments.size() < 2) {
                result.errors.add(new ValidationMessage(
                    '{{' + tag + '}}', prefix + ' tags require a field name, e.g. {{' + prefix + '.Name}}.', prefix
                ));
            }
            return;
        }

        if (prefix == 'Flow') {
            validateFlowTag(tag, segments, result);
            return;
        }

        if (prefix == 'DataCloud') {
            validateDataCloudTag(tag, segments, result);
            return;
        }

        if (prefix == 'Parent' || prefix == 'Child') {
            if (segments.size() < 2) {
                result.errors.add(new ValidationMessage(
                    '{{' + tag + '}}',
                    prefix + ' tags require a field name, e.g. {{' + prefix + '.Name}}.',
                    prefix
                ));
                return;
            }
            if (prefix == 'Parent' && !String.isBlank(parentObjectApiName)) {
                validateParentField(tag, segments, parentObjectApiName, result);
            }
            return;
        }

        // Bare field or object-prefixed field
        if (!String.isBlank(parentObjectApiName) && prefix == parentObjectApiName) {
            return; // object API name used as explicit prefix — valid
        }
        if (!String.isBlank(parentObjectApiName) && segments.size() == 1) {
            if (!GenericDynamicQueryService.isValidFieldPath(parentObjectApiName, tag)) {
                result.warnings.add(new ValidationMessage(
                    '{{' + tag + '}}',
                    'Field "' + tag + '" was not found on ' + parentObjectApiName + '. Verify the API name.',
                    'Parent'
                ));
            }
        }
    }

    private static void validateParentField(String tag, List<String> segments, String parentObjectApiName, ValidationResult result) {
        List<String> fieldSegs = new List<String>();
        for (Integer i = 1; i < segments.size(); i++) fieldSegs.add(segments[i]);
        String fieldPath = String.join(fieldSegs, '.');
        // Single-level check only; traversal paths are trusted at build time
        if (!fieldPath.contains('.') && !GenericDynamicQueryService.isValidFieldPath(parentObjectApiName, fieldPath)) {
            result.warnings.add(new ValidationMessage(
                '{{' + tag + '}}',
                'Field "' + fieldPath + '" was not found on ' + parentObjectApiName + '. Verify the API name.',
                'Parent'
            ));
        }
    }

    private static void validateFlowTag(String tag, List<String> segments, ValidationResult result) {
        if (segments.size() != 2) {
            result.errors.add(new ValidationMessage(
                '{{' + tag + '}}',
                'Flow merge fields must follow the format {{Flow.variableName}}.',
                'Flow'
            ));
            return;
        }
        if (!Pattern.matches('^[A-Za-z_][A-Za-z0-9_]*$', segments[1])) {
            result.errors.add(new ValidationMessage(
                '{{' + tag + '}}',
                'Flow variable name "' + segments[1] + '" contains invalid characters.',
                'Flow'
            ));
        }
    }

    private static void validateDataCloudTag(String tag, List<String> segments, ValidationResult result) {
        if (segments.size() != 3) {
            result.errors.add(new ValidationMessage(
                '{{' + tag + '}}',
                'Data Cloud merge fields must follow the format {{DataCloud.ObjectApiName.AttributeName}}.',
                'DataCloud'
            ));
        }
    }
}
