/**
 * Lists Data Cloud objects (Data Lake Objects and Data Model Objects) available
 * in the org so the template builder can offer a source picker for
 * {{DataCloud.ObjectApiName.AttributeName}} merge fields.
 *
 * Data Cloud objects in Salesforce use the suffixes:
 *   __dll  — Data Lake Object (ingested, raw)
 *   __dlm  — Data Model Object (mapped, queryable)
 *   __cio  — Calculated Insight Object
 *
 * Results are cached for the duration of the request (static variable) to
 * avoid redundant EntityDefinition queries within the same transaction.
 */
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.CyclomaticComplexity,PMD.CognitiveComplexity')
public with sharing class DataCloudConnectorService {

    // ── Public DTOs ───────────────────────────────────────────────────────────

    public class ConnectorObject {
        @AuraEnabled public String apiName    { get; set; }
        @AuraEnabled public String label      { get; set; }
        @AuraEnabled public String objectType { get; set; } // DLO, DMO, CIO
        @AuraEnabled public List<ConnectorAttribute> attributes { get; set; }

        public ConnectorObject(String apiName, String label, String objectType) {
            this.apiName     = apiName;
            this.label       = label;
            this.objectType  = objectType;
            this.attributes  = new List<ConnectorAttribute>();
        }
    }

    public class ConnectorAttribute {
        @AuraEnabled public String apiName    { get; set; }
        @AuraEnabled public String label      { get; set; }
        @AuraEnabled public String fieldType  { get; set; }

        public ConnectorAttribute(String apiName, String label, String fieldType) {
            this.apiName   = apiName;
            this.label     = label;
            this.fieldType = fieldType;
        }
    }

    // ── Request-level cache ───────────────────────────────────────────────────

    private static List<ConnectorObject> cachedObjects;

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Returns all Data Cloud objects visible to the running user.
     * Fetches attributes (fields) for each object using Schema.describeSObject.
     */
    @AuraEnabled(cacheable=true)
    public static List<ConnectorObject> getAvailableConnectors() {
        if (cachedObjects != null) {
            return cachedObjects;
        }
        cachedObjects = new List<ConnectorObject>();

        Set<String> dcSuffixes = new Set<String>{ '__dll', '__dlm', '__cio' };

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        for (String sObjectName : globalDescribe.keySet()) {
            String lower = sObjectName.toLowerCase();
            String matchedSuffix = null;
            for (String suffix : dcSuffixes) {
                if (lower.endsWith(suffix)) {
                    matchedSuffix = suffix;
                    break;
                }
            }
            if (matchedSuffix == null) continue;

            try {
                Schema.DescribeSObjectResult describe = globalDescribe.get(sObjectName).getDescribe();
                if (!describe.isAccessible()) continue;

                String objectType = suffixToType(matchedSuffix);
                ConnectorObject obj = new ConnectorObject(
                    describe.getName(), describe.getLabel(), objectType
                );

                for (Schema.SObjectField field : describe.fields.getMap().values()) {
                    Schema.DescribeFieldResult f = field.getDescribe();
                    if (!f.isAccessible()) continue;
                    obj.attributes.add(new ConnectorAttribute(
                        f.getName(), f.getLabel(), String.valueOf(f.getType())
                    ));
                }

                cachedObjects.add(obj);
            } catch (Exception ignored) {}
        }

        cachedObjects.sort();
        return cachedObjects;
    }

    /**
     * Returns field names for a specific Data Cloud object API name.
     * Used for autocomplete after the user picks a connector.
     */
    @AuraEnabled(cacheable=true)
    public static List<ConnectorAttribute> getAttributesForObject(String objectApiName) {
        if (String.isBlank(objectApiName)) return new List<ConnectorAttribute>();
        try {
            Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
            if (sot == null) return new List<ConnectorAttribute>();
            Schema.DescribeSObjectResult describe = sot.getDescribe();
            if (!describe.isAccessible()) return new List<ConnectorAttribute>();

            List<ConnectorAttribute> attrs = new List<ConnectorAttribute>();
            for (Schema.SObjectField field : describe.fields.getMap().values()) {
                Schema.DescribeFieldResult f = field.getDescribe();
                if (!f.isAccessible()) continue;
                attrs.add(new ConnectorAttribute(f.getName(), f.getLabel(), String.valueOf(f.getType())));
            }
            return attrs;
        } catch (Exception e) {
            return new List<ConnectorAttribute>();
        }
    }

    /**
     * Returns true when the org has at least one Data Cloud object accessible
     * to the running user.
     */
    public static Boolean isDataCloudEnabled() {
        List<ConnectorObject> objs = getAvailableConnectors();
        return !objs.isEmpty();
    }

    // ── Utilities ─────────────────────────────────────────────────────────────

    private static String suffixToType(String suffix) {
        if (suffix == '__dll') return 'DLO';
        if (suffix == '__dlm') return 'DMO';
        if (suffix == '__cio') return 'CIO';
        return 'Unknown';
    }
}
