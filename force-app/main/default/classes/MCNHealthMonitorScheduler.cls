/**
 * Hourly health check for the MCN integration.
 * Queries recent Weave_MCN_Sync_Log__c records to calculate error rate.
 * Sends an alert email if error rate exceeds the configured threshold (5%).
 *
 * Schedule:
 *   System.schedule('MCN Health Monitor', '0 0 * * * ?', new MCNHealthMonitorScheduler());
 */
@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces')
@SuppressWarnings('PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList')
public with sharing class MCNHealthMonitorScheduler implements Schedulable {

    @TestVisible static final Decimal ERROR_THRESHOLD_PCT = 5.0;

    // ── Schedulable ───────────────────────────────────────────────────────────

    public void execute(SchedulableContext ctx) {
        HealthCheckResult result = runHealthCheck();
        if (result.errorRatePct > ERROR_THRESHOLD_PCT) {
            sendAlertEmail(result);
        }
        logHealthCheck(result);
        publishEvent(result);
    }

    // ── Health check ──────────────────────────────────────────────────────────

    public class HealthCheckResult {
        @AuraEnabled public Integer totalOperations { get; set; }
        @AuraEnabled public Integer errorCount      { get; set; }
        @AuraEnabled public Decimal errorRatePct    { get; set; }
        @AuraEnabled public Boolean isHealthy       { get; set; }
        @AuraEnabled public DateTime checkTime      { get; set; }
        @AuraEnabled public List<String> recentErrors { get; set; }

        public HealthCheckResult() {
            this.recentErrors = new List<String>();
            this.checkTime    = DateTime.now();
        }
    }

    public static HealthCheckResult runHealthCheck() {
        DateTime oneHourAgo = DateTime.now().addHours(-1);

        HealthCheckResult r = new HealthCheckResult();
        r.totalOperations = [
            SELECT COUNT()
            FROM   Weave_MCN_Sync_Log__c
            WHERE  CreatedDate >= :oneHourAgo
            WITH   USER_MODE
        ];
        r.errorCount = [
            SELECT COUNT()
            FROM   Weave_MCN_Sync_Log__c
            WHERE  CreatedDate >= :oneHourAgo
              AND  Status__c = 'Failed'
            WITH   USER_MODE
        ];

        r.errorRatePct = r.totalOperations == 0
            ? 0
            : ((Decimal) r.errorCount / r.totalOperations * 100).setScale(2);

        r.isHealthy = r.errorRatePct <= ERROR_THRESHOLD_PCT;

        // Collect 10 most recent errors
        for (Weave_MCN_Sync_Log__c log : [
            SELECT Id, Template__c, Error_Message__c, CreatedDate
            FROM   Weave_MCN_Sync_Log__c
            WHERE  CreatedDate >= :oneHourAgo
              AND  Status__c = 'Failed'
            WITH   USER_MODE
            ORDER  BY CreatedDate DESC
            LIMIT  10
        ]) {
            r.recentErrors.add(
                '[' + log.CreatedDate.format() + '] Template ' + log.Template__c
                    + ': ' + (log.Error_Message__c != null ? log.Error_Message__c : 'Unknown error')
            );
        }

        return r;
    }

    // ── Alert email ───────────────────────────────────────────────────────────

    private static void sendAlertEmail(HealthCheckResult r) {
        List<String> adminEmails = getAdminEmails();
        if (adminEmails.isEmpty()) return;

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(adminEmails);
        mail.setSubject('[MCN ALERT] Error rate ' + r.errorRatePct + '% exceeds threshold');
        mail.setPlainTextBody(buildAlertBody(r));

        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'MCNHealthMonitor: failed to send alert — ' + e.getMessage());
        }
    }

    private static String buildAlertBody(HealthCheckResult r) {
        List<String> lines = new List<String>{
            'MCN Integration Health Alert',
            '============================',
            'Time: ' + r.checkTime.format(),
            'Error Rate: ' + r.errorRatePct + '% (threshold: ' + ERROR_THRESHOLD_PCT + '%)',
            'Total Operations (last hour): ' + r.totalOperations,
            'Error Count: ' + r.errorCount,
            '',
            'Recent Errors:'
        };
        for (String err : r.recentErrors) {
            lines.add('  - ' + err);
        }
        lines.add('');
        lines.add('Log in to Salesforce and check the MCN Health Dashboard for details.');
        return String.join(lines, '\n');
    }

    private static List<String> getAdminEmails() {
        List<String> emails = new List<String>();
        for (User u : [
            SELECT Email
            FROM   User
            WHERE  Profile.Name IN ('System Administrator', 'Salesforce Administrator')
              AND  IsActive = true
            WITH   USER_MODE
            LIMIT  10
        ]) {
            emails.add(u.Email);
        }
        return emails;
    }

    // ── Logging ───────────────────────────────────────────────────────────────

    private static void logHealthCheck(HealthCheckResult r) {
        // Log to debug for visibility in developer console
        System.debug(LoggingLevel.INFO,
            'MCN Health Check | Ops: ' + r.totalOperations
                + ' | Errors: ' + r.errorCount
                + ' | Rate: ' + r.errorRatePct + '%'
                + ' | Healthy: ' + r.isHealthy);
    }

    // ── Platform event ────────────────────────────────────────────────────────

    private static void publishEvent(HealthCheckResult r) {
        MCN_Integration_Event__e evt = new MCN_Integration_Event__e(
            Operation__c    = 'HealthCheck',
            Status__c       = r.isHealthy ? 'Healthy' : 'Alert',
            Execution_Time_Ms__c = 0,
            Error_Message__c = r.isHealthy ? null :
                'Error rate ' + r.errorRatePct + '% exceeds ' + ERROR_THRESHOLD_PCT + '% threshold'
        );
        EventBus.publish(evt);
    }

    // ── Convenience method to schedule ────────────────────────────────────────

    public static String scheduleHourly() {
        return System.schedule(
            'MCN Health Monitor',
            '0 0 * * * ?',
            new MCNHealthMonitorScheduler()
        );
    }
}
