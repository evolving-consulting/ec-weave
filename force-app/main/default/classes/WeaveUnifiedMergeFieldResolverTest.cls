@SuppressWarnings('PMD.MethodNamingConventions')
@IsTest
private class WeaveUnifiedMergeFieldResolverTest {

    // ── buildContext ──────────────────────────────────────────────────────────

    @IsTest
    static void buildContext_noExtraData_resolvesSObjectFields() {
        Account acc = new Account(Name = 'Acme Corp');
        insert acc;
        acc = [SELECT Id, Name FROM Account WHERE Id = :acc.Id];

        GenericMergeFieldResolver.MergeContext ctx =
            WeaveUnifiedMergeFieldResolver.buildContext(acc, 'Account', null, null);

        String result = GenericMergeFieldResolver.resolveTemplate('Hello {{Parent.Name}}', ctx);
        System.assertEquals('Hello Acme Corp', result);
    }

    @IsTest
    static void buildContext_withFlowVariables_resolvesFlowTags() {
        Account acc = new Account(Name = 'Test');
        insert acc;
        acc = [SELECT Id, Name FROM Account WHERE Id = :acc.Id];

        Map<String, Object> flowVars = new Map<String, Object>{ 'promoCode' => 'SAVE20' };
        GenericMergeFieldResolver.MergeContext ctx =
            WeaveUnifiedMergeFieldResolver.buildContext(acc, 'Account', flowVars, null);

        String result = GenericMergeFieldResolver.resolveTemplate('Code: {{Flow.promoCode}}', ctx);
        System.assertEquals('Code: SAVE20', result);
    }

    @IsTest
    static void buildContext_withDataCloudValues_resolvesDataCloudTags() {
        Account acc = new Account(Name = 'Test');
        insert acc;
        acc = [SELECT Id, Name FROM Account WHERE Id = :acc.Id];

        Map<String, String> dcValues = new Map<String, String>{
            'DataCloud.Contact__dlm.Email__c' => 'jane@example.com'
        };
        GenericMergeFieldResolver.MergeContext ctx =
            WeaveUnifiedMergeFieldResolver.buildContext(acc, 'Account', null, dcValues);

        String result = GenericMergeFieldResolver.resolveTemplate(
            'Email: {{DataCloud.Contact__dlm.Email__c}}', ctx
        );
        System.assertEquals('Email: jane@example.com', result);
    }

    @IsTest
    static void buildContext_allThreeSources_resolvesCombined() {
        Account acc = new Account(Name = 'Acme');
        insert acc;
        acc = [SELECT Id, Name FROM Account WHERE Id = :acc.Id];

        Map<String, Object> flowVars = new Map<String, Object>{ 'discount' => '10%' };
        Map<String, String> dcValues = new Map<String, String>{
            'DataCloud.Order__dlm.Total__c' => '500'
        };
        GenericMergeFieldResolver.MergeContext ctx =
            WeaveUnifiedMergeFieldResolver.buildContext(acc, 'Account', flowVars, dcValues);

        String template = '{{Parent.Name}} | Discount: {{Flow.discount}} | Total: {{DataCloud.Order__dlm.Total__c}}';
        String result = GenericMergeFieldResolver.resolveTemplate(template, ctx);
        System.assertEquals('Acme | Discount: 10% | Total: 500', result);
    }

    @IsTest
    static void buildContext_missingFlowVar_resolvesToEmpty() {
        Account acc = new Account(Name = 'Test');
        insert acc;
        acc = [SELECT Id, Name FROM Account WHERE Id = :acc.Id];

        GenericMergeFieldResolver.MergeContext ctx =
            WeaveUnifiedMergeFieldResolver.buildContext(acc, 'Account', null, null);

        String result = GenericMergeFieldResolver.resolveTemplate('{{Flow.undeclared}}', ctx);
        System.assertEquals('', result);
    }

    @IsTest
    static void buildContext_convenienceOverload_works() {
        Account acc = new Account(Name = 'Test');
        insert acc;
        acc = [SELECT Id, Name FROM Account WHERE Id = :acc.Id];

        GenericMergeFieldResolver.MergeContext ctx =
            WeaveUnifiedMergeFieldResolver.buildContext(acc, 'Account');
        System.assertNotEquals(null, ctx);
        System.assertEquals(acc, ctx.parentRecord);
    }

    // ── extractFlowVariableNames ──────────────────────────────────────────────

    @IsTest
    static void extractFlowVariableNames_delegatesToResolver() {
        Set<String> names = WeaveUnifiedMergeFieldResolver.extractFlowVariableNames(
            '{{Flow.one}} and {{Flow.two}}'
        );
        System.assertEquals(2, names.size());
        System.assert(names.contains('one'));
        System.assert(names.contains('two'));
    }

    // ── extractDataCloudRefs ──────────────────────────────────────────────────

    @IsTest
    static void extractDataCloudRefs_singleRef_returned() {
        Set<String> refs = WeaveUnifiedMergeFieldResolver.extractDataCloudRefs(
            '{{DataCloud.Contact__dlm.Email__c}}'
        );
        System.assertEquals(1, refs.size());
        System.assert(refs.contains('DataCloud.Contact__dlm.Email__c'));
    }

    @IsTest
    static void extractDataCloudRefs_noRefs_emptySet() {
        Set<String> refs = WeaveUnifiedMergeFieldResolver.extractDataCloudRefs(
            '{{Parent.Name}} {{Flow.myVar}}'
        );
        System.assertEquals(0, refs.size());
    }

    @IsTest
    static void extractDataCloudRefs_multipleRefs_allReturned() {
        Set<String> refs = WeaveUnifiedMergeFieldResolver.extractDataCloudRefs(
            '{{DataCloud.A__dlm.Field1}} and {{DataCloud.B__dll.Field2}}'
        );
        System.assertEquals(2, refs.size());
    }

    // ── validateTemplate ──────────────────────────────────────────────────────

    @IsTest
    static void validateTemplate_delegatesToValidator() {
        MergeFieldValidator.ValidationResult result =
            WeaveUnifiedMergeFieldResolver.validateTemplate('{{Flow.myVar}}', 'Account');
        System.assertNotEquals(null, result);
        System.assert(result.isValid);
    }
}
