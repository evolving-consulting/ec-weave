/**
 * Analyzes existing Weave email templates for MCN migration readiness.
 * Produces a per-template AnalysisResult with a 0-100 readiness score
 * and a list of blocking issues that must be resolved before migration.
 *
 * Usage:
 *   List<LegacyTemplateAnalyzer.AnalysisResult> results =
 *       LegacyTemplateAnalyzer.analyzeAll();
 */
public with sharing class LegacyTemplateAnalyzer {

    // ── DTOs ──────────────────────────────────────────────────────────────────

    public class AnalysisResult {
        @AuraEnabled public Id      templateId      { get; set; }
        @AuraEnabled public String  templateName    { get; set; }
        @AuraEnabled public String  currentChannel  { get; set; }
        @AuraEnabled public String  status          { get; set; }
        @AuraEnabled public Integer readinessScore  { get; set; }  // 0-100
        @AuraEnabled public String  recommendation  { get; set; }  // 'Migrate', 'Skip', 'Manual Review'
        @AuraEnabled public List<String> issues     { get; set; }
        @AuraEnabled public List<String> warnings   { get; set; }

        public AnalysisResult() {
            this.issues   = new List<String>();
            this.warnings = new List<String>();
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Analyzes all Weave templates in the org.
     */
    public static List<AnalysisResult> analyzeAll() {
        List<Weave_Template_Config__c> templates = loadAllTemplates();
        return analyzeTemplates(templates);
    }

    /**
     * Analyzes a specific set of templates by ID.
     */
    public static List<AnalysisResult> analyzeByIds(List<Id> templateIds) {
        List<Weave_Template_Config__c> templates = loadTemplatesByIds(templateIds);
        return analyzeTemplates(templates);
    }

    /**
     * Returns only templates that are ready to migrate (score >= 70).
     */
    public static List<AnalysisResult> getMigrationCandidates() {
        List<AnalysisResult> all = analyzeAll();
        List<AnalysisResult> candidates = new List<AnalysisResult>();
        for (AnalysisResult r : all) {
            if (r.readinessScore >= 70) {
                candidates.add(r);
            }
        }
        return candidates;
    }

    // ── Core analysis ─────────────────────────────────────────────────────────

    @TestVisible
    static List<AnalysisResult> analyzeTemplates(List<Weave_Template_Config__c> templates) {
        Map<Id, List<Weave_Template_Component__c>> componentsByTemplate =
            loadComponentsByTemplateIds(extractIds(templates));

        List<AnalysisResult> results = new List<AnalysisResult>();
        for (Weave_Template_Config__c t : templates) {
            List<Weave_Template_Component__c> components =
                componentsByTemplate.containsKey(t.Id)
                    ? componentsByTemplate.get(t.Id)
                    : new List<Weave_Template_Component__c>();
            results.add(analyze(t, components));
        }
        return results;
    }

    @TestVisible
    static AnalysisResult analyze(
        Weave_Template_Config__c t,
        List<Weave_Template_Component__c> components
    ) {
        AnalysisResult r = new AnalysisResult();
        r.templateId     = t.Id;
        r.templateName   = t.Name;
        r.currentChannel = t.Template_Channels__c;
        r.status         = t.Status__c;

        // Already on All Channels → skip
        if (t.Template_Channels__c == 'All Channels') {
            r.readinessScore = 100;
            r.recommendation = 'Skip';
            r.warnings.add('Template already configured for All Channels.');
            return r;
        }

        Integer score = 100;

        // Check: template must be Active to migrate
        if (t.Status__c != 'Active') {
            r.issues.add('Template is not Active (current: ' + t.Status__c + '). Activate before migrating.');
            score -= 30;
        }

        // Check: must have subject
        if (String.isBlank(t.Subject_Template__c)) {
            r.issues.add('Subject_Template__c is empty. MCN requires a subject line.');
            score -= 20;
        }

        // Check: must have at least one body component
        Boolean hasBody = false;
        for (Weave_Template_Component__c comp : components) {
            if (comp.Region__c == 'Body' && String.isNotBlank(comp.Component_HTML__c)) {
                hasBody = true;
                break;
            }
        }
        if (!hasBody) {
            r.issues.add('No Body component with HTML found. MCN requires body content.');
            score -= 25;
        }

        // Check: unsupported HTML patterns
        List<String> htmlIssues = detectUnsupportedHtml(components);
        for (String issue : htmlIssues) {
            r.warnings.add(issue);
            score -= 5;
        }

        // Check: merge field compatibility
        List<String> mergeIssues = detectUnsupportedMergeFields(t, components);
        for (String issue : mergeIssues) {
            r.warnings.add(issue);
            score -= 5;
        }

        // Check: brand configured
        if (t.Brand__c == null) {
            r.warnings.add('No Brand assigned. MCN emails render without brand header/footer.');
            score -= 5;
        }

        r.readinessScore = Math.max(0, Math.min(100, score));
        r.recommendation = r.readinessScore >= 70
            ? (r.issues.isEmpty() ? 'Migrate' : 'Manual Review')
            : 'Skip';

        return r;
    }

    // ── Feature detection ─────────────────────────────────────────────────────

    private static List<String> detectUnsupportedHtml(List<Weave_Template_Component__c> components) {
        List<String> issues = new List<String>();
        Set<String> checked = new Set<String>();

        for (Weave_Template_Component__c comp : components) {
            String html = comp.Component_HTML__c;
            if (String.isBlank(html)) continue;

            if (html.containsIgnoreCase('<script') && !checked.contains('script')) {
                issues.add('Component "' + comp.Name + '" contains <script> tags — not supported in MCN.');
                checked.add('script');
            }
            if (html.containsIgnoreCase('<iframe') && !checked.contains('iframe')) {
                issues.add('Component "' + comp.Name + '" contains <iframe> tags — not supported in MCN.');
                checked.add('iframe');
            }
            if (html.containsIgnoreCase('javascript:') && !checked.contains('js-href')) {
                issues.add('Component "' + comp.Name + '" contains javascript: href — blocked by MCN.');
                checked.add('js-href');
            }
        }
        return issues;
    }

    private static List<String> detectUnsupportedMergeFields(
        Weave_Template_Config__c t,
        List<Weave_Template_Component__c> components
    ) {
        List<String> issues = new List<String>();
        Pattern mergePattern = Pattern.compile('\\{\\{([^}]+)\\}\\}');

        // Check subject
        if (String.isNotBlank(t.Subject_Template__c)) {
            Matcher m = mergePattern.matcher(t.Subject_Template__c);
            while (m.find()) {
                String tag = m.group(1);
                if (tag.startsWith('Section.')) {
                    issues.add('Subject uses {{Section.*}} merge tag which MCN does not support: {{' + tag + '}}');
                }
            }
        }

        // Check components
        for (Weave_Template_Component__c comp : components) {
            if (String.isBlank(comp.Component_HTML__c)) continue;
            Matcher m = mergePattern.matcher(comp.Component_HTML__c);
            while (m.find()) {
                String tag = m.group(1);
                if (tag.startsWith('Section.') && !issues.contains('Section tag in body')) {
                    issues.add('Body uses {{Section.*}} merge tag — requires manual AMPscript conversion.');
                    issues.add('Section tag in body');
                }
            }
        }
        // Remove internal sentinel
        issues.remove('Section tag in body');
        return issues;
    }

    // ── Data loading ──────────────────────────────────────────────────────────

    private static List<Weave_Template_Config__c> loadAllTemplates() {
        return [
            SELECT Id, Name, Status__c, Template_Channels__c, Subject_Template__c, Brand__c
            FROM   Weave_Template_Config__c
            WITH   USER_MODE
            ORDER  BY Name
        ];
    }

    private static List<Weave_Template_Config__c> loadTemplatesByIds(List<Id> ids) {
        return [
            SELECT Id, Name, Status__c, Template_Channels__c, Subject_Template__c, Brand__c
            FROM   Weave_Template_Config__c
            WHERE  Id IN :ids
            WITH   USER_MODE
        ];
    }

    private static Map<Id, List<Weave_Template_Component__c>> loadComponentsByTemplateIds(Set<Id> templateIds) {
        Map<Id, List<Weave_Template_Component__c>> result = new Map<Id, List<Weave_Template_Component__c>>();
        for (Weave_Template_Component__c comp : [
            SELECT Id, Name, Region__c, Component_HTML__c, Template_Config__c
            FROM   Weave_Template_Component__c
            WHERE  Template_Config__c IN :templateIds
            WITH   USER_MODE
        ]) {
            if (!result.containsKey(comp.Template_Config__c)) {
                result.put(comp.Template_Config__c, new List<Weave_Template_Component__c>());
            }
            result.get(comp.Template_Config__c).add(comp);
        }
        return result;
    }

    private static Set<Id> extractIds(List<Weave_Template_Config__c> templates) {
        Set<Id> ids = new Set<Id>();
        for (Weave_Template_Config__c t : templates) {
            ids.add(t.Id);
        }
        return ids;
    }
}
