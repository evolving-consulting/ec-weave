/**
 * Builds a unified GenericMergeFieldResolver.MergeContext that resolves merge
 * fields from three data sources:
 *
 *   {{Parent.FieldName}}                 — SObject field on the parent record (existing)
 *   {{Flow.variableName}}                — Flow variable passed at render time
 *   {{DataCloud.ObjectApiName.AttrName}} — Data Cloud attribute passed at render time
 *
 * Flow and Data Cloud values are injected into MergeContext.aliasValues so the
 * existing GenericMergeFieldResolver.resolveTemplate() handles all resolution
 * without modification.
 *
 * Usage:
 *   GenericMergeFieldResolver.MergeContext ctx =
 *       WeaveUnifiedMergeFieldResolver.buildContext(
 *           parentRecord,
 *           'Account',
 *           new Map<String,Object>{ 'myFlowVar' => 'hello' },
 *           new Map<String,String>{ 'DataCloud.MyDMO__dlm.Email' => 'test@example.com' }
 *       );
 *   String html = GenericMergeFieldResolver.resolveTemplate(template, ctx);
 */
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList,PMD.ApexDoc')
public with sharing class WeaveUnifiedMergeFieldResolver {

    // ── Context builder ───────────────────────────────────────────────────────

    /**
     * Builds a full merge context from all three data sources.
     *
     * @param parentRecord         The SObject record for {{Parent.*}} fields
     * @param parentObjectApiName  API name of the parent object (e.g. 'Account')
     * @param flowVariables        Map of bare variable names → values (e.g. 'myVar' → 'hello')
     * @param dataCloudValues      Map of fully-qualified keys → values
     *                             (e.g. 'DataCloud.Contact__dlm.Email__c' → 'a@b.com')
     */
    public static GenericMergeFieldResolver.MergeContext buildContext(
        SObject parentRecord,
        String  parentObjectApiName,
        Map<String, Object> flowVariables,
        Map<String, String> dataCloudValues
    ) {
        GenericMergeFieldResolver.MergeContext ctx = new GenericMergeFieldResolver.MergeContext();
        ctx.parentRecord        = parentRecord;
        ctx.parentObjectApiName = parentObjectApiName;
        ctx.escapeHtml          = false;
        ctx.renderHtmlFormattedFields = true;

        Map<String, String> aliasValues = new Map<String, String>();

        // Inject Flow variables — stored as "Flow.varName" so {{Flow.varName}} resolves
        FlowVariableResolver.FlowResolutionResult flowResult =
            FlowVariableResolver.resolveVariables(flowVariables);
        aliasValues.putAll(flowResult.resolved);

        // Inject Data Cloud values — keys already in "DataCloud.Object.Attr" format
        if (dataCloudValues != null) {
            aliasValues.putAll(dataCloudValues);
        }

        ctx.aliasValues     = aliasValues;
        ctx.aliasRecords    = new Map<String, SObject>();
        ctx.sectionHtmlByKey = new Map<String, String>();
        return ctx;
    }

    /**
     * Convenience overload — no Flow or DataCloud values (parent fields only).
     */
    public static GenericMergeFieldResolver.MergeContext buildContext(
        SObject parentRecord,
        String  parentObjectApiName
    ) {
        return buildContext(parentRecord, parentObjectApiName, null, null);
    }

    // ── Merge field extraction helpers ───────────────────────────────────────

    /**
     * Returns all {{Flow.variableName}} references found in the template.
     */
    public static Set<String> extractFlowVariableNames(String templateContent) {
        return FlowVariableResolver.extractFlowVariableNames(templateContent);
    }

    /**
     * Returns all {{DataCloud.ObjectName.Attribute}} references found in the template
     * as fully-qualified keys (e.g. 'DataCloud.Contact__dlm.Email__c').
     */
    public static Set<String> extractDataCloudRefs(String templateContent) {
        Set<String> refs = new Set<String>();
        if (String.isBlank(templateContent)) return refs;
        Matcher m = Pattern.compile(
            '\\{\\{\\s*(DataCloud\\.[A-Za-z_][A-Za-z0-9_]*\\.[A-Za-z_][A-Za-z0-9_]*(__(c|r))?)\\s*\\}\\}'
        ).matcher(templateContent);
        while (m.find()) {
            refs.add(m.group(1).trim());
        }
        return refs;
    }

    /**
     * Validates that all merge fields in the template are syntactically correct
     * for the given parent object.
     */
    public static MergeFieldValidator.ValidationResult validateTemplate(
        String templateContent,
        String parentObjectApiName
    ) {
        return MergeFieldValidator.validateTemplate(templateContent, parentObjectApiName);
    }
}
