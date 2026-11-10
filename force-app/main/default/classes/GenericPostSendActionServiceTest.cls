@IsTest
private class GenericPostSendActionServiceTest {
    @IsTest
    static void executesUpdateFieldAndCreateTaskActions() {
        Account account = DceTestDataFactory.createAccount();
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        template.Post_Send_Actions__c = JSON.serialize(new List<DceBuilderPostSendActionDTO>{
            updateDescriptionAction(1, 'Email sent for {{Parent.Name}}'),
            createTaskAction(2, 'Follow up with {{Parent.Name}}', 3)
        });
        update template;

        Test.startTest();
        GenericPostSendActionService.executeActions(template, account.Id, 'Account', Datetime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0)));
        Test.stopTest();

        Account updatedAccount = [
            SELECT Description
            FROM Account
            WHERE Id = :account.Id
        ];
        System.assertEquals('Email sent for DCE Test Account', updatedAccount.Description);

        List<Task> tasks = [
            SELECT Subject, WhatId, Status, Priority, ActivityDate
            FROM Task
            WHERE WhatId = :account.Id
        ];
        System.assertEquals(1, tasks.size());
        System.assertEquals('Follow up with DCE Test Account', tasks[0].Subject);
        System.assertEquals('Not Started', tasks[0].Status);
        System.assertEquals('Normal', tasks[0].Priority);
        System.assertEquals(Date.today().addDays(3), tasks[0].ActivityDate);
    }

    @IsTest
    static void invalidActionDoesNotBlockRemainingActions() {
        Account account = DceTestDataFactory.createAccount();
        Email_Template_Config__c template = DceTestDataFactory.createTemplate('Account');
        DceBuilderPostSendActionDTO invalidAction = updateDescriptionAction(1, 'Should not apply');
        invalidAction.fieldApiName = 'Not_A_Field__c';
        template.Post_Send_Actions__c = JSON.serialize(new List<DceBuilderPostSendActionDTO>{
            invalidAction,
            updateDescriptionAction(2, 'Valid action')
        });
        update template;

        Test.startTest();
        GenericPostSendActionService.executeActions(template, account.Id, 'Account', System.now());
        Test.stopTest();

        Account updatedAccount = [
            SELECT Description
            FROM Account
            WHERE Id = :account.Id
        ];
        System.assertEquals('Valid action', updatedAccount.Description);
    }

    private static DceBuilderPostSendActionDTO updateDescriptionAction(Integer runOrder, String value) {
        DceBuilderPostSendActionDTO action = new DceBuilderPostSendActionDTO();
        action.active = true;
        action.runOrder = runOrder;
        action.actionType = 'Update Field';
        action.fieldApiName = 'Description';
        action.valueType = 'Merge Field';
        action.value = value;
        return action;
    }

    private static DceBuilderPostSendActionDTO createTaskAction(Integer runOrder, String subject, Integer daysAfterSend) {
        DceBuilderPostSendActionDTO action = new DceBuilderPostSendActionDTO();
        action.active = true;
        action.runOrder = runOrder;
        action.actionType = 'Create Task';
        action.subject = subject;
        action.assignedToType = 'Current User';
        action.dueDateStrategy = 'Email Sent Date + X Days';
        action.daysAfterSend = daysAfterSend;
        action.status = 'Not Started';
        action.priority = 'Normal';
        action.comments = 'Created by DCE';
        return action;
    }
}
