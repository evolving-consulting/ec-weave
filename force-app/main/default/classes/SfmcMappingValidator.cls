/**
 * Validates a Weave template before publishing to Marketing Cloud Next.
 * Checks syntax, content, referenced data sources, and Flow existence.
 */
public with sharing class SfmcMappingValidator {

    // ── Public DTOs ───────────────────────────────────────────────────────────

    public class ValidationResult {
        public Boolean      isValid       { get; set; }
        public List<String> errors        { get; set; }
        public List<String> warnings      { get; set; }

        public ValidationResult() {
            this.isValid   = true;
            this.errors    = new List<String>();
            this.warnings  = new List<String>();
        }

        public void addError(String msg) {
            this.errors.add(msg);
            this.isValid = false;
        }

        public void addWarning(String msg) {
            this.warnings.add(msg);
        }

        public String toSummary() {
            List<String> lines = new List<String>();
            if (!errors.isEmpty())   lines.add('Errors: ' + String.join(errors, ' | '));
            if (!warnings.isEmpty()) lines.add('Warnings: ' + String.join(warnings, ' | '));
            if (lines.isEmpty())     return 'Valid';
            return String.join(lines, '\n');
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Full pre-publish validation for a template.
     * Runs all checks and returns a consolidated result.
     */
    public static ValidationResult validateForPublish(Id templateId) {
        ValidationResult result = new ValidationResult();

        // 1. Load template
        List<Weave_Template_Config__c> configs = [
            SELECT Id, Name, Status__c, Parent_Object_API_Name__c
            FROM   Weave_Template_Config__c
            WHERE  Id = :templateId
            WITH   USER_MODE
            LIMIT  1
        ];
        if (configs.isEmpty()) {
            result.addError('Template not found: ' + templateId);
            return result;
        }
        Weave_Template_Config__c config = configs[0];

        if (config.Status__c != 'Active') {
            result.addError('Template must be Active before publishing. Current status: ' + config.Status__c + '.');
        }

        // 2. Load all components and check for content
        List<Weave_Template_Component__c> components = [
            SELECT Id, HTML_Output__c, Region__c
            FROM   Weave_Template_Component__c
            WHERE  Weave_Template_Config__c = :templateId
            WITH   USER_MODE
        ];
        if (components.isEmpty()) {
            result.addError('Template has no components. Add at least one body component before publishing.');
        }

        // Collect all HTML content for merge field scanning
        String allContent = '';
        Boolean hasBodyContent = false;
        for (Weave_Template_Component__c comp : components) {
            if (!String.isBlank(comp.HTML_Output__c)) {
                allContent += comp.HTML_Output__c + ' ';
                if (comp.Region__c == 'Body') hasBodyContent = true;
            }
        }
        if (!hasBodyContent && !components.isEmpty()) {
            result.addWarning('No body components have content. The published email may appear empty.');
        }

        // 3. Validate merge field syntax using existing validator
        if (!String.isBlank(allContent)) {
            MergeFieldValidator.ValidationResult syntaxResult =
                MergeFieldValidator.validateTemplate(allContent, config.Parent_Object_API_Name__c);
            for (MergeFieldValidator.ValidationMessage err : syntaxResult.errors) {
                result.addError('Merge field syntax error — ' + err.tag + ': ' + err.message);
            }
            for (MergeFieldValidator.ValidationMessage warn : syntaxResult.warnings) {
                result.addWarning('Merge field warning — ' + warn.tag + ': ' + warn.message);
            }
        }

        // 4. Validate DataCloud connector references
        validateDataCloudRefs(allContent, result);

        // 5. Validate Flow references
        validateFlowRefs(allContent, result);

        return result;
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private static void validateDataCloudRefs(String content, ValidationResult result) {
        Set<String> dcRefs = WeaveUnifiedMergeFieldResolver.extractDataCloudRefs(content);
        if (dcRefs.isEmpty()) return;

        // For each unique Data Cloud object name, check it exists in org schema
        // by looking for __dlm or __dll suffixed EntityDefinition entries
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Set<String> objectApiNames = new Set<String>();
        for (String ref : dcRefs) {
            List<String> parts = ref.split('\\.');
            if (parts.size() >= 2) objectApiNames.add(parts[1].toLowerCase());
        }

        for (String objectApiName : objectApiNames) {
            Boolean found = globalDescribe.containsKey(objectApiName)
                         || globalDescribe.containsKey(objectApiName + '__dlm')
                         || globalDescribe.containsKey(objectApiName + '__dll');
            if (!found) {
                result.addWarning(
                    'Data Cloud object "' + objectApiName +
                    '" was not found in this org\'s schema. Verify the API name and that Data Cloud is provisioned.'
                );
            }
        }
    }

    private static void validateFlowRefs(String content, ValidationResult result) {
        Set<String> flowVarNames = WeaveUnifiedMergeFieldResolver.extractFlowVariableNames(content);
        if (flowVarNames.isEmpty()) return;

        // Flow variable names are bare; we can't check individual variable existence
        // via standard SOQL, so we warn that they must be supplied at render time.
        result.addWarning(
            flowVarNames.size() + ' Flow variable(s) referenced (' +
            String.join(new List<String>(flowVarNames), ', ') +
            '). Ensure they are supplied when the template is rendered via Flow.'
        );
    }
}
