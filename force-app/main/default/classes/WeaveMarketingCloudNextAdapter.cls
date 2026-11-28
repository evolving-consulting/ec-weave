/**
 * Adapter for the Marketing Cloud Next email asset API.
 * Translates Weave domain objects to/from MCN REST API payloads.
 *
 * MCN email asset endpoints (relative to Named Credential base URL):
 *   POST   /asset/v1/content/assets          — create
 *   PUT    /asset/v1/content/assets/{id}     — update
 *   DELETE /asset/v1/content/assets/{id}     — delete
 *   GET    /asset/v1/content/assets/{id}     — read
 */
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList,PMD.ApexDoc')
public virtual with sharing class WeaveMarketingCloudNextAdapter {

    @TestVisible
    private static final String ASSETS_PATH = '/asset/v1/content/assets';

    @TestVisible
    private static SfmcHttpClient httpClient = new SfmcHttpClient();

    @TestVisible
    private static WeaveMarketingCloudNextAdapter testInstance;

    public static WeaveMarketingCloudNextAdapter getInstance() {
        return testInstance != null ? testInstance : new WeaveMarketingCloudNextAdapter();
    }

    @TestVisible
    static void setInstance(WeaveMarketingCloudNextAdapter mock) {
        testInstance = mock;
    }

    // ── Public DTOs ──────────────────────────────────────────────────────────

    public class MCNPublishResult {
        public Boolean isSuccess    { get; set; }
        public Boolean success      { get { return isSuccess; } set { isSuccess = value; } }
        public String  mcnAssetId   { get; set; }
        public String  errorMessage { get; set; }
        public Integer statusCode   { get; set; }
        @SuppressWarnings('PMD.EmptyStatementBlock')
        public MCNPublishResult() {}
        public MCNPublishResult(Boolean success, String assetId) {
            this.isSuccess  = success;
            this.mcnAssetId = assetId;
        }
        public MCNPublishResult(String error) {
            this.isSuccess    = false;
            this.errorMessage = error;
        }
    }

    public class McnAsset {
        public String id          { get; set; }
        public String name        { get; set; }
        public String assetType   { get; set; }
        public String htmlContent { get; set; }
        public String subject     { get; set; }
        public String version     { get; set; }
        public String contentHash { get; set; }

        @SuppressWarnings('PMD.EmptyStatementBlock')
        public McnAsset() {}
    }

    public class AdapterResult {
        public Boolean  isSuccess    { get; set; }
        public String   assetId      { get; set; }
        public String   errorMessage { get; set; }
        public McnAsset asset        { get; set; }

        public AdapterResult(Boolean success, String assetId) {
            this.isSuccess = success;
            this.assetId   = assetId;
        }

        public AdapterResult(String error) {
            this.isSuccess    = false;
            this.errorMessage = error;
        }
    }

    // ── High-level publish ───────────────────────────────────────────────────

    public virtual MCNPublishResult publishTemplate(Id templateId) {
        SfmcTemplatePublisher.PublishResult r = SfmcTemplatePublisher.publishTemplate(templateId);
        MCNPublishResult out = new MCNPublishResult(r.isSuccess, r.mcnAssetId);
        out.errorMessage = r.errorMessage;
        return out;
    }

    // ── CRUD operations ──────────────────────────────────────────────────────

    public virtual AdapterResult createEmailAsset(String assetName, String htmlContent, String subject) {
        Map<String, Object> payload = buildPayload(assetName, htmlContent, subject);
        SfmcHttpClient.McnResponse res = httpClient.post(ASSETS_PATH, JSON.serialize(payload));
        if (!res.isSuccess) {
            return new AdapterResult('Create failed: ' + res.errorMessage);
        }
        String assetId = extractAssetId(res.bodyAsMap());
        return new AdapterResult(true, assetId);
    }

    public virtual AdapterResult updateEmailAsset(String assetId, String htmlContent, String subject) {
        if (String.isBlank(assetId)) {
            return new AdapterResult('Cannot update: no MCN asset ID on record.');
        }
        Map<String, Object> payload = buildPayload(null, htmlContent, subject);
        SfmcHttpClient.McnResponse res = httpClient.put(ASSETS_PATH + '/' + assetId, JSON.serialize(payload));
        if (!res.isSuccess) {
            return new AdapterResult('Update failed: ' + res.errorMessage);
        }
        return new AdapterResult(true, assetId);
    }

    public virtual AdapterResult deleteEmailAsset(String assetId) {
        if (String.isBlank(assetId)) {
            return new AdapterResult('Cannot delete: no MCN asset ID on record.');
        }
        SfmcHttpClient.McnResponse res = httpClient.del(ASSETS_PATH + '/' + assetId);
        if (!res.isSuccess) {
            return new AdapterResult('Delete failed: ' + res.errorMessage);
        }
        return new AdapterResult(true, assetId);
    }

    public virtual AdapterResult getEmailAsset(String assetId) {
        if (String.isBlank(assetId)) {
            return new AdapterResult('Cannot read: no MCN asset ID on record.');
        }
        SfmcHttpClient.McnResponse res = httpClient.get(ASSETS_PATH + '/' + assetId);
        if (!res.isSuccess) {
            return new AdapterResult('Read failed: ' + res.errorMessage);
        }
        AdapterResult result = new AdapterResult(true, assetId);
        result.asset = parseAsset(res.bodyAsMap());
        return result;
    }

    // ── Internal helpers ─────────────────────────────────────────────────────

    private Map<String, Object> buildPayload(String name, String htmlContent, String subject) {
        Map<String, Object> payload = new Map<String, Object>{
            'assetType' => new Map<String, Object>{ 'name' => 'htmlemail', 'id' => 208 },
            'views' => new Map<String, Object>{
                'html' => new Map<String, Object>{ 'content' => htmlContent }
            }
        };
        if (name != null)    payload.put('name', name);
        if (subject != null) payload.put('channels', new Map<String, Object>{ 'email' => new Map<String, Object>{ 'subject' => subject } });
        return payload;
    }

    private String extractAssetId(Map<String, Object> body) {
        Object idVal = body.get('id');
        return idVal != null ? String.valueOf(idVal) : null;
    }

    private McnAsset parseAsset(Map<String, Object> body) {
        McnAsset a = new McnAsset();
        a.id      = body.containsKey('id')      ? String.valueOf(body.get('id'))      : null;
        a.name    = body.containsKey('name')     ? String.valueOf(body.get('name'))    : null;
        a.version = body.containsKey('version')  ? String.valueOf(body.get('version')) : null;
        // Extract HTML content if present
        Object views = body.get('views');
        if (views instanceof Map<String, Object>) {
            Object html = ((Map<String, Object>) views).get('html');
            if (html instanceof Map<String, Object>) {
                Object content = ((Map<String, Object>) html).get('content');
                a.htmlContent = content != null ? String.valueOf(content) : null;
            }
        }
        return a;
    }
}
