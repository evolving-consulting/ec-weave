/**
 * In-process static cache for frequently accessed MCN integration data.
 * Uses static maps keyed by content hash to avoid redundant queries and
 * callouts within a single Apex transaction.
 *
 * TTLs are enforced via CreatedAt timestamps. For cross-transaction
 * persistence consider Platform Cache when available.
 */
@SuppressWarnings('PMD.ApexDoc')
public with sharing class MCNPerformanceCache {

    // TTL constants (milliseconds)
    private static final Long TTL_SCHEMA_MS   = 3600000L;  // 1 hour
    private static final Long TTL_FLOW_MS     = 3600000L;  // 1 hour
    private static final Long TTL_CONTENT_MS  = 300000L;   // 5 minutes

    // ── Cache stores ──────────────────────────────────────────────────────────

    private static Map<String, CacheEntry> schemaCache  = new Map<String, CacheEntry>();
    private static Map<String, CacheEntry> flowCache    = new Map<String, CacheEntry>();
    private static Map<String, CacheEntry> contentCache = new Map<String, CacheEntry>();

    // Stats
    @TestVisible static Integer schemaHits   = 0;
    @TestVisible static Integer schemaMisses = 0;
    @TestVisible static Integer contentHits  = 0;
    @TestVisible static Integer contentMisses = 0;

    // ── Inner types ───────────────────────────────────────────────────────────

    private class CacheEntry {
        Object  value;
        Long    createdAt;
        CacheEntry(Object v) {
            this.value     = v;
            this.createdAt = System.currentTimeMillis();
        }
        Boolean isExpired(Long ttlMs) {
            return (System.currentTimeMillis() - this.createdAt) > ttlMs;
        }
    }

    // ── Schema cache ──────────────────────────────────────────────────────────

    public static Object getSchema(String connectorKey) {
        CacheEntry e = schemaCache.get(connectorKey);
        if (e != null && !e.isExpired(TTL_SCHEMA_MS)) {
            schemaHits++;
            return e.value;
        }
        schemaMisses++;
        return null;
    }

    public static void putSchema(String connectorKey, Object schema) {
        schemaCache.put(connectorKey, new CacheEntry(schema));
    }

    // ── Flow variable cache ───────────────────────────────────────────────────

    public static Object getFlowVariables(String flowKey) {
        CacheEntry e = flowCache.get(flowKey);
        if (e != null && !e.isExpired(TTL_FLOW_MS)) {
            return e.value;
        }
        return null;
    }

    public static void putFlowVariables(String flowKey, Object variables) {
        flowCache.put(flowKey, new CacheEntry(variables));
    }

    // ── Content cache (rendered template HTML) ────────────────────────────────

    /**
     * Context hash is typically: templateId + ':' + recordId (or additional context).
     */
    public static String getRenderedContent(String contextHash) {
        CacheEntry e = contentCache.get(contextHash);
        if (e != null && !e.isExpired(TTL_CONTENT_MS)) {
            contentHits++;
            return (String) e.value;
        }
        contentMisses++;
        return null;
    }

    public static void putRenderedContent(String contextHash, String htmlContent) {
        contentCache.put(contextHash, new CacheEntry(htmlContent));
    }

    /**
     * Builds a cache key for rendered content.
     * Hashes templateId + recordId to a fixed-length string.
     */
    public static String buildContentKey(String templateId, String contextJson) {
        String raw = templateId + ':' + (contextJson == null ? '' : contextJson);
        Blob hash  = Crypto.generateDigest('SHA-256', Blob.valueOf(raw));
        return EncodingUtil.convertToHex(hash).substring(0, 16);
    }

    // ── Cache management ──────────────────────────────────────────────────────

    public static void clearAll() {
        schemaCache.clear();
        flowCache.clear();
        contentCache.clear();
    }

    public static void clearContent() {
        contentCache.clear();
    }

    /**
     * Returns current hit rate as a percentage (0-100).
     */
    public static Integer getContentHitRate() {
        Integer total = contentHits + contentMisses;
        return total == 0 ? 0 : (Integer) ((contentHits * 100.0) / total);
    }

    public static Integer getSchemaHitRate() {
        Integer total = schemaHits + schemaMisses;
        return total == 0 ? 0 : (Integer) ((schemaHits * 100.0) / total);
    }
}
