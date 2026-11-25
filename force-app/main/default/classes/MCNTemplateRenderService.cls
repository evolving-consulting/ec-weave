/**
 * Renders a Weave template for Experience Cloud, resolving merge fields from
 * three sources: parent SObject fields, Flow variables, and Data Cloud attributes.
 *
 * Uses WeaveUnifiedMergeFieldResolver (Phase 2) to build the merge context, then
 * delegates to WeaveEmailTemplateRenderer for the full HTML assembly pipeline.
 *
 * Results are cached for 5 minutes per (templateId + contextHash) in Platform Cache.
 * Falls back to direct render if cache is unavailable.
 */
public with sharing class MCNTemplateRenderService {

    @TestVisible
    private static final Integer CACHE_TTL_SECONDS = 300;

    // ── Public API ────────────────────────────────────────────────────────────

    public class RenderRequest {
        public Id      templateId       { get; set; }
        public Id      parentRecordId   { get; set; }
        public String  contextDataJson  { get; set; }
    }

    public class RenderResult {
        @AuraEnabled public Boolean isSuccess    { get; private set; }
        @AuraEnabled public String  subject      { get; private set; }
        @AuraEnabled public String  htmlBody     { get; private set; }
        @AuraEnabled public String  plainText    { get; private set; }
        @AuraEnabled public String  errorMessage { get; private set; }

        public RenderResult(WeaveEmailTemplateRenderer.RenderedEmailDTO dto) {
            this.isSuccess = true;
            this.subject   = dto.subject;
            this.htmlBody  = dto.htmlBody;
            this.plainText = dto.plainTextBody;
        }

        public RenderResult(String error) {
            this.isSuccess    = false;
            this.errorMessage = error;
        }
    }

    /**
     * Renders a template and returns the HTML with all merge fields resolved.
     *
     * @param templateId      Weave_Template_Config__c record ID
     * @param contextDataJson JSON object: { "recordId": "...", "flowVariables": {}, "dataCloudValues": {} }
     */
    @AuraEnabled
    public static RenderResult resolveTemplate(Id templateId, String contextDataJson) {
        try {
            if (templateId == null) throw new IllegalArgumentException('templateId is required.');

            ContextData ctx = parseContext(contextDataJson);

            String cacheKey = buildCacheKey(templateId, contextDataJson);
            RenderResult cached = getCached(cacheKey);
            if (cached != null) return cached;

            WeaveEmailTemplateRenderer.RenderedEmailDTO dto = renderWithContext(templateId, ctx);

            RenderResult result = new RenderResult(dto);
            putCache(cacheKey, result);
            return result;

        } catch (Exception e) {
            return new RenderResult(e.getMessage());
        }
    }

    // ── Context parsing ───────────────────────────────────────────────────────

    @TestVisible
    static ContextData parseContext(String jsonStr) {
        ContextData ctx = new ContextData();
        if (String.isBlank(jsonStr)) return ctx;

        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
            ctx.parentRecordId   = (String) raw.get('recordId');
            ctx.flowVariables    = extractStringObjectMap(raw, 'flowVariables');
            ctx.dataCloudValues  = extractStringStringMap(raw, 'dataCloudValues');
        } catch (Exception e) {
            // Return empty context — renderer will use parent record only
        }
        return ctx;
    }

    @TestVisible
    static WeaveEmailTemplateRenderer.RenderedEmailDTO renderWithContext(Id templateId, ContextData ctx) {
        Id recordId = ctx.parentRecordId != null ? Id.valueOf(ctx.parentRecordId) : null;
        WeaveEmailTemplateRenderer.RenderedEmailDTO dto = WeaveEmailTemplateRenderer.renderEmail(templateId, recordId, false);

        if ((ctx.flowVariables != null && !ctx.flowVariables.isEmpty())
            || (ctx.dataCloudValues != null && !ctx.dataCloudValues.isEmpty())) {
            // Resolve Flow and DataCloud tags that the standard renderer left as-is
            GenericMergeFieldResolver.MergeContext extCtx =
                WeaveUnifiedMergeFieldResolver.buildContext(null, null, ctx.flowVariables, ctx.dataCloudValues);
            dto.htmlBody    = GenericMergeFieldResolver.resolveTemplate(dto.htmlBody, extCtx);
            dto.subject     = GenericMergeFieldResolver.resolveTemplate(dto.subject, extCtx);
            dto.plainTextBody = GenericMergeFieldResolver.resolveTemplate(dto.plainTextBody, extCtx);
        }

        return dto;
    }

    // ── Platform Cache helpers ────────────────────────────────────────────────

    @TestVisible
    static String buildCacheKey(Id templateId, String contextJson) {
        String raw = String.valueOf(templateId) + (contextJson != null ? contextJson : '');
        Blob hash = Crypto.generateDigest('MD5', Blob.valueOf(raw));
        return 'mcnRender_' + EncodingUtil.convertToHex(hash).left(32);
    }

    private static RenderResult getCached(String key) {
        try {
            Cache.OrgPartition part = Cache.Org.getPartition('local.WeaveCache');
            return (RenderResult) part.get(key);
        } catch (Exception e) {
            return null;
        }
    }

    private static void putCache(String key, RenderResult result) {
        try {
            Cache.OrgPartition part = Cache.Org.getPartition('local.WeaveCache');
            part.put(key, result, CACHE_TTL_SECONDS);
        } catch (Exception e) {
            // Cache unavailable — continue without caching
        }
    }

    // ── Utility ───────────────────────────────────────────────────────────────

    private static Map<String, Object> extractStringObjectMap(Map<String, Object> parent, String key) {
        Object val = parent.get(key);
        if (val == null) return new Map<String, Object>();
        try {
            return (Map<String, Object>) val;
        } catch (Exception e) {
            return new Map<String, Object>();
        }
    }

    private static Map<String, String> extractStringStringMap(Map<String, Object> parent, String key) {
        Object val = parent.get(key);
        if (val == null) return new Map<String, String>();
        Map<String, String> result = new Map<String, String>();
        try {
            Map<String, Object> raw = (Map<String, Object>) val;
            for (String k : raw.keySet()) {
                result.put(k, String.valueOf(raw.get(k)));
            }
        } catch (Exception e) {
            // Return empty map on parse failure
        }
        return result;
    }

    @TestVisible
    class ContextData {
        public String parentRecordId;
        public Map<String, Object> flowVariables    = new Map<String, Object>();
        public Map<String, String> dataCloudValues  = new Map<String, String>();
    }
}
