public with sharing class DceBuilderPostSendActionDTO {
    @AuraEnabled public String id { get; set; }
    @AuraEnabled public String localKey { get; set; }
    @AuraEnabled public Boolean active { get; set; }
    @AuraEnabled public Integer runOrder { get; set; }
    @AuraEnabled public String actionType { get; set; }
    @AuraEnabled public Boolean expanded { get; set; }

    @AuraEnabled public String fieldApiName { get; set; }
    @AuraEnabled public String fieldLabel { get; set; }
    @AuraEnabled public String valueType { get; set; }
    @AuraEnabled public String value { get; set; }

    @AuraEnabled public String subject { get; set; }
    @AuraEnabled public String assignedToType { get; set; }
    @AuraEnabled public Id assignedUserId { get; set; }
    @AuraEnabled public String dueDateStrategy { get; set; }
    @AuraEnabled public Integer daysAfterSend { get; set; }
    @AuraEnabled public String status { get; set; }
    @AuraEnabled public String priority { get; set; }
    @AuraEnabled public String comments { get; set; }

    public DceBuilderPostSendActionDTO() {
        this.active = true;
        this.actionType = 'Update Field';
        this.valueType = 'Static';
        this.assignedToType = 'Current User';
        this.dueDateStrategy = 'Email Sent Date + X Days';
        this.daysAfterSend = 0;
        this.status = 'Not Started';
        this.priority = 'Normal';
    }
}
