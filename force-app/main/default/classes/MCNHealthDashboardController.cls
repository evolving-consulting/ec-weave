/**
 * AuraEnabled controller backing mcnHealthDashboard LWC.
 * Delegates heavy logic to MCNHealthMonitorScheduler.runHealthCheck().
 */
@SuppressWarnings('PMD.ApexDoc')
public with sharing class MCNHealthDashboardController {

    @AuraEnabled(cacheable=false)
    public static MCNHealthMonitorScheduler.HealthCheckResult getHealthMetrics() {
        try {
            return MCNHealthMonitorScheduler.runHealthCheck();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Weave_MCN_Sync_Log__c> getRecentLogs(Integer limitCount) {
        Integer lim = (limitCount != null && limitCount > 0) ? limitCount : 10;
        try {
            return [
                SELECT Id, Template__c, Template__r.Name,
                       Publish_Type__c, Status__c, Error_Message__c, CreatedDate
                FROM   Weave_MCN_Sync_Log__c
                WHERE  Status__c = 'Failed'
                WITH   USER_MODE
                ORDER  BY CreatedDate DESC
                LIMIT  :lim
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Integer> get24hCounts() {
        try {
            DateTime cutoff = DateTime.now().addHours(-24);
            Integer total = [
                SELECT COUNT() FROM Weave_MCN_Sync_Log__c
                WHERE CreatedDate >= :cutoff WITH USER_MODE
            ];
            Integer errors = [
                SELECT COUNT() FROM Weave_MCN_Sync_Log__c
                WHERE CreatedDate >= :cutoff AND Status__c = 'Failed' WITH USER_MODE
            ];
            Integer migrations = [
                SELECT COUNT() FROM Weave_MCN_Sync_Log__c
                WHERE CreatedDate >= :cutoff AND Publish_Type__c = 'Migration'
                  AND Status__c = 'Success' WITH USER_MODE
            ];
            return new Map<String, Integer>{
                'total'      => total,
                'errors'     => errors,
                'migrations' => migrations
            };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
