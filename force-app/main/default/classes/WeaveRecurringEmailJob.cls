@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces')
@SuppressWarnings('PMD.AvoidBooleanMethodParameters,PMD.ExcessiveParameterList,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.ApexDoc')
public with sharing class WeaveRecurringEmailJob implements Schedulable {

    private static final Date KNOWN_SUNDAY = Date.newInstance(2000, 1, 2);

    private static final Map<String, Integer> DAY_NAME_TO_INDEX = new Map<String, Integer>{
        'sun' => 0, 'mon' => 1, 'tue' => 2, 'wed' => 3, 'thu' => 4, 'fri' => 5, 'sat' => 6
    };

    private final Id scheduledSendId;

    public WeaveRecurringEmailJob(Id scheduledSendId) {
        this.scheduledSendId = scheduledSendId;
    }

    public void execute(SchedulableContext ctx) {
        List<Weave_Scheduled_Send__c> rows = [
            SELECT Id, Status__c, Template__c, Record_Id__c, Filter_Clause__c,
                   Recurring_Config__c, Records_Sent__c, Batch_Size__c,
                   Template__r.Parent_Object_API_Name__c
            FROM Weave_Scheduled_Send__c
            WHERE Id = :scheduledSendId WITH USER_MODE LIMIT 1
        ];
        if (rows.isEmpty() || rows[0].Status__c == 'Cancelled') return;

        Weave_Scheduled_Send__c record = rows[0];
        RecurringConfig config = parseConfig(record.Recurring_Config__c);
        if (config == null) {
            setStatus(record.Id, 'Failed', null, 'Invalid recurring configuration.');
            return;
        }

        Integer sendCount = record.Records_Sent__c != null ? (Integer)record.Records_Sent__c : 0;
        Boolean isBulk = String.isBlank(record.Record_Id__c);

        try {
            if (isBulk) {
                sendBulkOccurrence(record);
            } else {
                WeaveScheduledEmailJob.sendToRecord(record.Template__c, (Id)record.Record_Id__c);
            }
            sendCount++;
        } catch (Exception e) {
            setStatus(record.Id, 'Failed', sendCount, e.getMessage());
            return;
        }

        if (config.endType == 'maxSends' && config.maxSends != null && sendCount >= config.maxSends) {
            setStatus(record.Id, 'Complete', sendCount, null);
            return;
        }

        Datetime nextRun = getNextOccurrence(config, System.now());
        if (nextRun == null) {
            setStatus(record.Id, 'Complete', sendCount, null);
            return;
        }

        String cron = buildCron(nextRun);
        String jobName = 'WeaveRecurring-' + record.Id + '-s' + sendCount;
        try {
            System.schedule(jobName, cron, new WeaveRecurringEmailJob(record.Id));
            setStatus(record.Id, 'Pending', sendCount, null);
        } catch (Exception e) {
            setStatus(record.Id, 'Failed', sendCount, 'Could not schedule next occurrence: ' + e.getMessage());
        }
    }

    private void sendBulkOccurrence(Weave_Scheduled_Send__c parent) {
        String objectApiName = parent.Template__r.Parent_Object_API_Name__c;
        if (String.isBlank(objectApiName)) {
            throw new IllegalArgumentException('Template has no parent object configured for bulk send.');
        }
        Integer batchSize = parent.Batch_Size__c != null ? parent.Batch_Size__c.intValue() : 20;

        Weave_Scheduled_Send__c run = new Weave_Scheduled_Send__c(
            Template__c      = parent.Template__c,
            Scheduled_At__c  = System.now(),
            Status__c        = 'Running',
            Send_Type__c     = 'Bulk',
            Job_Name__c      = (parent.Job_Name__c != null ? parent.Job_Name__c : 'Recurring') + ' (occurrence)',
            Filter_Clause__c = parent.Filter_Clause__c,
            Batch_Size__c    = batchSize
        );
        insert as user run;

        Database.executeBatch(
            new WeaveBulkEmailBatch(parent.Template__c, run.Id, objectApiName, parent.Filter_Clause__c),
            batchSize
        );
    }

    public static Datetime getFirstOccurrence(RecurringConfig config) {
        if (config == null || config.daysOfWeek == null || config.daysOfWeek.isEmpty()) return null;

        Set<Integer> targetDays = toDayIndexSet(config.daysOfWeek);
        if (targetDays.isEmpty()) return null;

        Integer[] timeParts = parseTime(config.timeOfDay);

        Date startDate;
        try {
            startDate = Date.valueOf(config.startDate);
        } catch (Exception e) {
            startDate = Date.today();
        }

        for (Integer offset = 0; offset <= 8; offset++) {
            Date candidate = startDate.addDays(offset);
            if (!targetDays.contains(getDayIndex(candidate))) continue;

            Datetime result = Datetime.newInstance(
                candidate.year(), candidate.month(), candidate.day(),
                timeParts[0], timeParts[1], 0
            );
            if (result > System.now().addMinutes(5)) return result;
        }
        return null;
    }

    public static Datetime getNextOccurrence(RecurringConfig config, Datetime fromNow) {
        if (config == null || config.daysOfWeek == null || config.daysOfWeek.isEmpty()) return null;

        Set<Integer> targetDays = toDayIndexSet(config.daysOfWeek);
        if (targetDays.isEmpty()) return null;

        Integer[] timeParts = parseTime(config.timeOfDay);
        Date today = fromNow.date();

        for (Integer offset = 1; offset <= 8; offset++) {
            Date candidate = today.addDays(offset);

            if (config.endType == 'endDate' && String.isNotBlank(config.endDate)) {
                try {
                    if (candidate > Date.valueOf(config.endDate)) return null;
                } catch (Exception ignored) {}
            }

            if (!targetDays.contains(getDayIndex(candidate))) continue;

            return Datetime.newInstance(
                candidate.year(), candidate.month(), candidate.day(),
                timeParts[0], timeParts[1], 0
            );
        }
        return null;
    }

    public static String buildCron(Datetime dt) {
        return '0 ' + dt.minute() + ' ' + dt.hour() + ' ' + dt.day() + ' ' + dt.month() + ' ? ' + dt.year();
    }

    public static RecurringConfig parseConfig(String jsonStr) {
        if (String.isBlank(jsonStr)) return null;
        try {
            return (RecurringConfig)JSON.deserialize(jsonStr, RecurringConfig.class);
        } catch (Exception e) {
            return null;
        }
    }

    private static Set<Integer> toDayIndexSet(List<String> days) {
        Set<Integer> result = new Set<Integer>();
        for (String day : days) {
            String lower = day.toLowerCase();
            if (DAY_NAME_TO_INDEX.containsKey(lower)) {
                result.add(DAY_NAME_TO_INDEX.get(lower));
            }
        }
        return result;
    }

    private static Integer getDayIndex(Date d) {
        Integer diff = KNOWN_SUNDAY.daysBetween(d);
        return Math.mod(7 + Math.mod(diff, 7), 7);
    }

    private static Integer[] parseTime(String timeStr) {
        if (String.isBlank(timeStr)) return new Integer[]{ 9, 0 };
        List<String> parts = timeStr.split(':');
        Integer h = 0, m = 0;
        try { h = Integer.valueOf(parts[0]); } catch (Exception ignored) {}
        try { m = parts.size() > 1 ? Integer.valueOf(parts[1]) : 0; } catch (Exception ignored) {}
        return new Integer[]{ Math.min(Math.max(h, 0), 23), Math.min(Math.max(m, 0), 59) };
    }

    private static void setStatus(Id recordId, String status, Integer sendCount, String errorDetail) {
        Weave_Scheduled_Send__c upd = new Weave_Scheduled_Send__c(Id = recordId, Status__c = status);
        if (sendCount != null) upd.Records_Sent__c = sendCount;
        if (errorDetail != null) upd.Error_Detail__c = errorDetail;
        try { update as user upd; } catch (Exception ignored) {}
    }

    public class RecurringConfig {
        public List<String> daysOfWeek;
        public String timeOfDay;
        public String startDate;
        public String endType;
        public String endDate;
        public Integer maxSends;
        public String filterClause;
    }
}
