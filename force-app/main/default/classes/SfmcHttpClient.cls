/**
 * Low-level HTTP client for the Marketing Cloud Next (SFMC) REST API.
 * Uses Named Credential "MCN_API" so credentials never touch Apex code.
 *
 * All callers should check response.getStatusCode() — this class does
 * not throw on non-2xx responses so callers can inspect and log details.
 */
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.ApexDoc')
public with sharing class SfmcHttpClient {

    @TestVisible
    private static final String NAMED_CREDENTIAL = 'callout:MCN_API';

    @SuppressWarnings('PMD.EmptyStatementBlock')
    public SfmcHttpClient() {}

    @SuppressWarnings('PMD.EmptyStatementBlock')
    public SfmcHttpClient(String namedCredentialOverride) {}

    // ── Public request/response wrappers ─────────────────────────────────────

    public class McnResponse {
        public Integer  statusCode   { get; private set; }
        public String   body         { get; private set; }
        public Boolean  isSuccess    { get; private set; }
        public String   errorMessage { get; private set; }

        public McnResponse(HttpResponse res) {
            this.statusCode = res.getStatusCode();
            this.body       = res.getBody();
            this.isSuccess  = statusCode >= 200 && statusCode < 300;
            if (!isSuccess) {
                this.errorMessage = 'MCN API returned HTTP ' + statusCode + ': ' + body;
            }
        }

        public McnResponse(String errorMessage) {
            this.statusCode   = 0;
            this.body         = '';
            this.isSuccess    = false;
            this.errorMessage = errorMessage;
        }

        public Map<String, Object> bodyAsMap() {
            if (String.isBlank(body)) return new Map<String, Object>();
            try {
                return (Map<String, Object>) JSON.deserializeUntyped(body);
            } catch (Exception e) {
                return new Map<String, Object>();
            }
        }
    }

    // ── HTTP verbs ───────────────────────────────────────────────────────────

    public McnResponse post(String endpoint, String jsonBody) {
        return send('POST', endpoint, jsonBody);
    }

    public McnResponse put(String endpoint, String jsonBody) {
        return send('PUT', endpoint, jsonBody);
    }

    public McnResponse del(String endpoint) {
        return send('DELETE', endpoint, null);
    }

    public McnResponse get(String endpoint) {
        return send('GET', endpoint, null);
    }

    // ── Internal ─────────────────────────────────────────────────────────────

    private McnResponse send(String method, String endpoint, String body) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(NAMED_CREDENTIAL + endpoint);
            req.setMethod(method);
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(30000);
            if (body != null) {
                req.setBody(body);
            }
            HttpResponse res = new Http().send(req);
            return new McnResponse(res);
        } catch (System.CalloutException e) {
            return new McnResponse('Callout failed: ' + e.getMessage());
        } catch (Exception e) {
            return new McnResponse('Unexpected error: ' + e.getMessage());
        }
    }
}
