@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces')
@SuppressWarnings('PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList')
public with sharing class WeaveSignatureConfigService {

    private static final String CONFIG_NAME = 'Default';

    // ─── Load / Save ─────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static WeaveBuilderDTOs.WeaveSignatureConfigDTO getConfig() {
        try {
            List<Weave_Signature_Config__c> rows = [
                SELECT Id, Name, Signature_Site_URL__c, Default_From_Email__c,
                       Link_Expiration_Days__c, Reminders_Enabled__c, Reminder_Hours__c,
                       Require_Email_Verification__c, Prefill_Signer_Email__c
                FROM Weave_Signature_Config__c
                WITH USER_MODE
                LIMIT 1
            ];
            if (rows.isEmpty()) return new WeaveBuilderDTOs.WeaveSignatureConfigDTO();
            return toDTO(rows[0]);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load signature config: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static WeaveBuilderDTOs.WeaveSignatureConfigDTO saveConfig(String dtoJson) {
        try {
            WeaveBuilderDTOs.WeaveSignatureConfigDTO dto =
                (WeaveBuilderDTOs.WeaveSignatureConfigDTO) JSON.deserialize(dtoJson, WeaveBuilderDTOs.WeaveSignatureConfigDTO.class);

            Weave_Signature_Config__c rec = dto.id != null
                ? new Weave_Signature_Config__c(Id = dto.id)
                : new Weave_Signature_Config__c(Name = CONFIG_NAME);

            rec.Signature_Site_URL__c         = dto.signatureSiteUrl;
            rec.Default_From_Email__c          = dto.defaultFromEmail;
            rec.Link_Expiration_Days__c        = dto.linkExpirationDays;
            rec.Reminders_Enabled__c           = dto.remindersEnabled == true;
            rec.Reminder_Hours__c              = dto.reminderHours;
            rec.Require_Email_Verification__c  = dto.requireEmailVerification == true;
            rec.Prefill_Signer_Email__c        = dto.prefillSignerEmail == true;

            upsert as user rec;
            dto.id = rec.Id;
            return dto;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to save signature config: ' + e.getMessage());
        }
    }

    // ─── Org-Wide Email Addresses ─────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<WeaveBuilderDTOs.WeaveOrgWideEmailDTO> getOrgWideEmailAddresses() {
        try {
            List<WeaveBuilderDTOs.WeaveOrgWideEmailDTO> results = new List<WeaveBuilderDTOs.WeaveOrgWideEmailDTO>();
            for (OrgWideEmailAddress owe : [
                SELECT Id, DisplayName, Address
                FROM OrgWideEmailAddress
                WITH USER_MODE
                ORDER BY DisplayName ASC, Address ASC
            ]) {
                WeaveBuilderDTOs.WeaveOrgWideEmailDTO dto = new WeaveBuilderDTOs.WeaveOrgWideEmailDTO();
                dto.id          = owe.Id;
                dto.displayName = owe.DisplayName;
                dto.address     = owe.Address;
                dto.label       = String.isNotBlank(owe.DisplayName) ? owe.DisplayName + ' <' + owe.Address + '>' : owe.Address;
                results.add(dto);
            }
            return results;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load org-wide email addresses: ' + e.getMessage());
        }
    }

    // ─── Setup status verification ────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static WeaveBuilderDTOs.WeaveSignatureSetupStatusDTO getSetupStatus() {
        WeaveBuilderDTOs.WeaveSignatureSetupStatusDTO status = new WeaveBuilderDTOs.WeaveSignatureSetupStatusDTO();

        WeaveBuilderDTOs.WeaveSignatureConfigDTO cfg = getConfig();

        // Check 1: Site URL configured
        Boolean siteUrlSet = String.isNotBlank(cfg.signatureSiteUrl);
        status.checks.add(check(
            'Site URL Configured',
            siteUrlSet,
            siteUrlSet ? 'Signature Site URL is set.' : 'Enter your Force.com Site URL in Site Config.',
            siteUrlSet ? null : 'Go to Setup',
            siteUrlSet ? null : '/lightning/setup/Sites/home'
        ));

        // Check 2: Salesforce Site active
        Boolean siteActive = false;
        String siteDetail = 'No active site found matching the configured URL.';
        try {
            List<Site> sites = [SELECT Id, Name, Status FROM Site WHERE Status = 'Active' WITH USER_MODE LIMIT 10];
            if (!sites.isEmpty()) {
                if (String.isBlank(cfg.signatureSiteUrl)) {
                    siteActive = true;
                    siteDetail = 'Active site found: ' + sites[0].Name;
                } else {
                    for (Site s : sites) {
                        SiteDetail sd = [SELECT SecureURL FROM SiteDetail WHERE DurableId = :s.Id LIMIT 1];
                        if (sd != null && cfg.signatureSiteUrl.containsIgnoreCase(s.Name)) {
                            siteActive = true;
                            siteDetail = 'Active site found: ' + s.Name;
                            break;
                        }
                    }
                    if (!siteActive && !sites.isEmpty()) {
                        siteActive = true;
                        siteDetail = 'Active site found: ' + sites[0].Name;
                    }
                }
            }
        } catch (Exception e) {
            siteDetail = 'Could not query site status: ' + e.getMessage();
        }
        status.checks.add(check(
            'Salesforce Site Active',
            siteActive,
            siteDetail,
            siteActive ? null : 'Go to Setup',
            siteActive ? null : '/lightning/setup/Sites/home'
        ));

        // Check 3: Org-Wide Email Address configured
        Boolean oweSet = false;
        String oweDetail = 'No org-wide email address configured.';
        try {
            List<OrgWideEmailAddress> owes = [SELECT Id, Address, DisplayName FROM OrgWideEmailAddress WITH USER_MODE LIMIT 1];
            if (!owes.isEmpty()) {
                oweSet = true;
                oweDetail = 'Email sender configured: ' + owes[0].DisplayName + ' <' + owes[0].Address + '>';
            }
        } catch (Exception e) {
            oweDetail = 'Could not query org-wide email: ' + e.getMessage();
        }
        status.checks.add(check(
            'Org-Wide Email Address',
            oweSet,
            oweDetail,
            oweSet ? null : 'Go to Setup',
            oweSet ? null : '/lightning/setup/OrgWideEmailAddresses/home'
        ));

        // Check 4: Guest permission set assigned
        Boolean guestPermAssigned = false;
        String guestPermDetail = 'DocGen Guest Signature permission set not found or not assigned.';
        try {
            List<PermissionSet> ps = [SELECT Id FROM PermissionSet WHERE Name = 'DocGen_Guest_Signature' WITH USER_MODE LIMIT 1];
            if (!ps.isEmpty()) {
                List<PermissionSetAssignment> psa = [
                    SELECT Id FROM PermissionSetAssignment
                    WHERE PermissionSetId = :ps[0].Id WITH USER_MODE LIMIT 1
                ];
                guestPermAssigned = !psa.isEmpty();
                guestPermDetail = guestPermAssigned
                    ? 'DocGen Guest Signature permission set is assigned.'
                    : 'Permission set exists but is not assigned to any user.';
            }
        } catch (Exception e) {
            guestPermDetail = 'Could not check permission set: ' + e.getMessage();
        }
        status.checks.add(check(
            'Guest Permission Set Assigned',
            guestPermAssigned,
            guestPermDetail,
            guestPermAssigned ? null : 'Go to Setup',
            guestPermAssigned ? null : '/lightning/setup/PermSets/home'
        ));

        // Check 5: VF pages deployed
        Boolean vfDeployed = false;
        String vfDetail = 'WeaveSignaturePage Visualforce page not found.';
        try {
            List<ApexPage> pages = [SELECT Id, Name FROM ApexPage WHERE Name = 'WeaveSignaturePage' WITH USER_MODE LIMIT 1];
            vfDeployed = !pages.isEmpty();
            vfDetail = vfDeployed ? 'WeaveSignaturePage Visualforce page is deployed.' : vfDetail;
        } catch (Exception e) {
            vfDetail = 'Could not check VF pages: ' + e.getMessage();
        }
        status.checks.add(check(
            'Visualforce Page Deployed',
            vfDeployed,
            vfDetail,
            null,
            null
        ));

        status.allPassed = true;
        for (WeaveBuilderDTOs.WeaveSignatureSetupCheckDTO c : status.checks) {
            if (!c.passed) { status.allPassed = false; break; }
        }

        return status;
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static WeaveBuilderDTOs.WeaveSignatureConfigDTO toDTO(Weave_Signature_Config__c rec) {
        WeaveBuilderDTOs.WeaveSignatureConfigDTO dto = new WeaveBuilderDTOs.WeaveSignatureConfigDTO();
        dto.id                      = rec.Id;
        dto.signatureSiteUrl        = rec.Signature_Site_URL__c;
        dto.defaultFromEmail        = rec.Default_From_Email__c;
        dto.linkExpirationDays      = rec.Link_Expiration_Days__c != null ? rec.Link_Expiration_Days__c.intValue() : 2;
        dto.remindersEnabled        = rec.Reminders_Enabled__c;
        dto.reminderHours           = rec.Reminder_Hours__c;
        dto.requireEmailVerification = rec.Require_Email_Verification__c;
        dto.prefillSignerEmail      = rec.Prefill_Signer_Email__c;
        return dto;
    }

    private static WeaveBuilderDTOs.WeaveSignatureSetupCheckDTO check(
        String label, Boolean passed, String detail, String actionLabel, String actionUrl
    ) {
        WeaveBuilderDTOs.WeaveSignatureSetupCheckDTO c = new WeaveBuilderDTOs.WeaveSignatureSetupCheckDTO();
        c.label       = label;
        c.passed      = passed;
        c.detail      = detail;
        c.actionLabel = actionLabel;
        c.actionUrl   = actionUrl;
        return c;
    }
}
