/**
 * Detects conflicts between a Weave template's local content and the
 * version currently live in Marketing Cloud Next.
 *
 * A conflict occurs when the MCN asset has been edited outside Weave
 * (i.e., its content differs from what Weave last published).
 * Detection uses a SHA-256 content hash stored on Weave_Send_Log__c
 * via the MCN sync log's Translated_Content_Hash__c field.
 */
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces')
@SuppressWarnings('PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList')
public with sharing class SfmcTemplateConflictDetector {

    // ── Public DTOs ───────────────────────────────────────────────────────────

    public enum ConflictState {
        NOT_PUBLISHED,    // template has never been published to MCN
        NO_CONFLICT,      // local and remote content hashes match
        CONFLICT_DETECTED // remote was modified outside Weave
    }

    public class ConflictResult {
        public ConflictState state           { get; set; }
        public String        localHash       { get; set; }
        public String        remoteHash      { get; set; }
        public String        mcnAssetId      { get; set; }
        public String        message         { get; set; }
        public Boolean       canOverwrite    { get; set; }

        public ConflictResult(ConflictState state, String message) {
            this.state       = state;
            this.message     = message;
            this.canOverwrite = true;
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Checks whether the template's last-published content matches what
     * is currently in MCN.
     *
     * @param templateId  The Weave_Template_Config__c record ID.
     * @param adapter     Injected adapter (supports mock in tests).
     */
    public static ConflictResult detectConflict(
        Id templateId,
        WeaveMarketingCloudNextAdapter adapter
    ) {
        // Load the template record
        List<Weave_Template_Config__c> configs = [
            SELECT Id, Name, SFMC_Template_ID__c
            FROM   Weave_Template_Config__c
            WHERE  Id = :templateId
            WITH   USER_MODE
            LIMIT  1
        ];
        if (configs.isEmpty()) {
            return new ConflictResult(ConflictState.NOT_PUBLISHED, 'Template not found.');
        }
        Weave_Template_Config__c config = configs[0];

        if (String.isBlank(config.SFMC_Template_ID__c)) {
            return new ConflictResult(ConflictState.NOT_PUBLISHED, 'Template has not been published to MCN yet.');
        }

        // Load the hash we stored when we last published
        String lastPublishedHash = getLastPublishedHash(templateId);

        // Fetch current remote content to compute its hash
        WeaveMarketingCloudNextAdapter.AdapterResult remoteResult =
            adapter.getEmailAsset(config.SFMC_Template_ID__c);

        if (!remoteResult.isSuccess) {
            ConflictResult cr = new ConflictResult(
                ConflictState.NOT_PUBLISHED,
                'Could not retrieve MCN asset to check for conflicts: ' + remoteResult.errorMessage
            );
            cr.canOverwrite = false;
            return cr;
        }

        String remoteHash = hashContent(remoteResult.asset.htmlContent);
        ConflictResult cr = new ConflictResult(ConflictState.NO_CONFLICT, 'No conflict detected.');
        cr.mcnAssetId  = config.SFMC_Template_ID__c;
        cr.localHash   = lastPublishedHash;
        cr.remoteHash  = remoteHash;

        if (String.isBlank(lastPublishedHash) || lastPublishedHash == remoteHash) {
            cr.state   = ConflictState.NO_CONFLICT;
            cr.message = 'No conflict — remote content matches last publish.';
        } else {
            cr.state   = ConflictState.CONFLICT_DETECTED;
            cr.message = 'Conflict detected: the MCN asset was edited outside Weave since the last publish. ' +
                         'You can overwrite the remote version or discard your local changes.';
        }
        return cr;
    }

    /**
     * Convenience overload that creates a default adapter instance.
     */
    public static ConflictResult detectConflict(Id templateId) {
        return detectConflict(templateId, new WeaveMarketingCloudNextAdapter());
    }

    /**
     * Computes a simple SHA-256 hex digest of the given content.
     * Returns an empty string for null/blank input.
     */
    public static String hashContent(String content) {
        if (String.isBlank(content)) return '';
        Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(content));
        return EncodingUtil.convertToHex(hash);
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private static String getLastPublishedHash(Id templateId) {
        List<Weave_MCN_Sync_Log__c> logs = [
            SELECT Translated_Content_Hash__c
            FROM   Weave_MCN_Sync_Log__c
            WHERE  Template__c = :templateId
            AND    Status__c   = 'Success'
            AND    Publish_Type__c IN ('Create', 'Update')
            WITH   USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT  1
        ];
        return logs.isEmpty() ? null : logs[0].Translated_Content_Hash__c;
    }
}
