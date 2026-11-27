/**
 * Resolves Flow Builder variable references used in Weave templates.
 *
 * At BUILD time:  lists active Flows in the org so the builder can show a
 *                 picker, and validates {{Flow.variableName}} syntax.
 * At RENDER time: accepts a Map<String,String> of variable values (populated
 *                 by WeaveSendEmailAction or the caller) and returns them for
 *                 injection into the merge context.
 *
 * Note: Flow variable *definitions* (names, types) are not queryable from
 * standard Apex SOQL — only the Tooling API exposes them.  This service
 * therefore validates syntax and existence of the Flow itself; individual
 * variable names are trusted at build time and resolved at runtime.
 */
public with sharing class FlowVariableResolver {

    // ── Public DTOs ───────────────────────────────────────────────────────────

    public class FlowSummary {
        @AuraEnabled public String apiName    { get; set; }
        @AuraEnabled public String label      { get; set; }
        @AuraEnabled public String description { get; set; }

        public FlowSummary(String apiName, String label, String description) {
            this.apiName      = apiName;
            this.label        = label;
            this.description  = description;
        }
    }

    public class FlowResolutionResult {
        @AuraEnabled public Boolean valid                  { get; set; }
        @AuraEnabled public String  errorMessage           { get; set; }
        @AuraEnabled public Map<String, String> resolved  { get; set; }

        public FlowResolutionResult() {
            this.valid    = true;
            this.resolved = new Map<String, String>();
        }
    }

    // ── Build-time: list flows ────────────────────────────────────────────────

    /**
     * Returns active, Auto-launched or Record-triggered Flows available in
     * the org.  Uses FlowDefinitionView (available API v55+).
     */
    @AuraEnabled(cacheable=true)
    public static List<FlowSummary> getAvailableFlows() {
        List<FlowSummary> results = new List<FlowSummary>();
        try {
            for (FlowDefinitionView fdv : [
                SELECT ApiName, Label, Description
                FROM   FlowDefinitionView
                WHERE  IsActive = true
                AND    ProcessType IN ('AutoLaunchedFlow', 'Flow', 'RecordBeforeSave', 'RecordAfterSave')
                WITH   USER_MODE
                ORDER BY Label ASC
                LIMIT  200
            ]) {
                results.add(new FlowSummary(fdv.ApiName, fdv.Label, fdv.Description));
            }
        } catch (Exception e) {
            // FlowDefinitionView may not be accessible in all contexts; return empty list
        }
        return results;
    }

    /**
     * Returns true if a flow with the given API name exists and is active.
     */
    public static Boolean isValidFlowApiName(String flowApiName) {
        if (String.isBlank(flowApiName)) return false;
        try {
            List<FlowDefinitionView> matches = [
                SELECT ApiName FROM FlowDefinitionView
                WHERE  ApiName = :flowApiName AND IsActive = true
                WITH   USER_MODE
                LIMIT  1
            ];
            return !matches.isEmpty();
        } catch (Exception e) {
            return false;
        }
    }

    // ── Render-time: resolve flow variables ───────────────────────────────────

    /**
     * Builds a resolved variable map from provided input values.
     * Keys should be bare variable names (without "Flow." prefix).
     * Returns a map keyed as "Flow.variableName" for injection into
     * GenericMergeFieldResolver.MergeContext.aliasValues.
     */
    public static FlowResolutionResult resolveVariables(Map<String, Object> inputVariables) {
        FlowResolutionResult result = new FlowResolutionResult();
        if (inputVariables == null || inputVariables.isEmpty()) {
            return result;
        }
        for (String varName : inputVariables.keySet()) {
            if (String.isBlank(varName)) continue;
            Object rawValue = inputVariables.get(varName);
            String stringValue = rawValue != null ? String.valueOf(rawValue) : '';
            // Store with and without prefix so both {{Flow.x}} and bare {{x}} styles work
            result.resolved.put('Flow.' + varName, stringValue);
        }
        return result;
    }

    /**
     * Extracts all {{Flow.variableName}} placeholder keys from a template string.
     */
    public static Set<String> extractFlowVariableNames(String templateContent) {
        Set<String> names = new Set<String>();
        if (String.isBlank(templateContent)) return names;
        Matcher m = Pattern.compile('\\{\\{\\s*Flow\\.([A-Za-z_][A-Za-z0-9_]*)\\s*\\}\\}')
                           .matcher(templateContent);
        while (m.find()) {
            names.add(m.group(1));
        }
        return names;
    }
}
