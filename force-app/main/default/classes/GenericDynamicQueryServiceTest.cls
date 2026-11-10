@IsTest
private class GenericDynamicQueryServiceTest {
    @IsTest
    static void validatesObjectsFieldsAndFieldPaths() {
        System.assertEquals(true, GenericDynamicQueryService.isValidObject('Account'));
        System.assertEquals(false, GenericDynamicQueryService.isValidObject('Not_A_Real_Object__c'));
        System.assertEquals(true, GenericDynamicQueryService.isValidField('Account', 'Name'));
        System.assertEquals(false, GenericDynamicQueryService.isValidField('Account', 'NotAField__c'));
        System.assertEquals(true, GenericDynamicQueryService.isValidFieldPath('Contact', 'Account.Name'));
        System.assertEquals(false, GenericDynamicQueryService.isValidFieldPath('Contact', 'Name FROM Account'));
        System.assertEquals(false, GenericDynamicQueryService.isValidFieldPath('Contact', 'Account.Name;DELETE'));
    }

    @IsTest
    static void queriesParentAndChildRecordsWithSafeFilter() {
        Account account = DceTestDataFactory.createAccount();
        DceTestDataFactory.createContact(account.Id);
        DceTestDataFactory.createContact(account.Id, 'Alan', 'Jones', 'alan.jones@example.com');

        SObject queriedAccount = GenericDynamicQueryService.queryRecordById(
            'Account',
            account.Id,
            new Set<String>{ 'Name' }
        );
        System.assertEquals(account.Name, queriedAccount.get('Name'));

        List<SObject> contacts = GenericDynamicQueryService.queryChildRecords(
            'Contact',
            'AccountId',
            account.Id,
            new Set<String>{ 'FirstName', 'LastName', 'Email' },
            'LastName',
            'ASC',
            'LastName = \'Smith\''
        );

        System.assertEquals(1, contacts.size());
        System.assertEquals('Smith', contacts[0].get('LastName'));
    }

    @IsTest
    static void rejectsUnsafeFilterAndSortDirection() {
        Account account = DceTestDataFactory.createAccount();

        assertAuraExceptionThrown(new ThrowingRunnableUnsafeFilter(account.Id));
        assertAuraExceptionThrown(new ThrowingRunnableBadSort(account.Id));
    }

    private interface ThrowingRunnable {
        void run();
    }

    private class ThrowingRunnableUnsafeFilter implements ThrowingRunnable {
        private Id accountId;
        ThrowingRunnableUnsafeFilter(Id accountId) {
            this.accountId = accountId;
        }
        public void run() {
            GenericDynamicQueryService.queryChildRecords('Contact', 'AccountId', accountId, new Set<String>{ 'Email' }, null, null, 'LastName = \'Smith\' OR Email != null');
        }
    }

    private class ThrowingRunnableBadSort implements ThrowingRunnable {
        private Id accountId;
        ThrowingRunnableBadSort(Id accountId) {
            this.accountId = accountId;
        }
        public void run() {
            GenericDynamicQueryService.queryChildRecords('Contact', 'AccountId', accountId, new Set<String>{ 'Email' }, 'LastName', 'SIDEWAYS', null);
        }
    }

    private static void assertAuraExceptionThrown(ThrowingRunnable runnable) {
        Boolean thrown = false;
        try {
            runnable.run();
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assertEquals(true, thrown, 'Expected AuraHandledException.');
    }
}
