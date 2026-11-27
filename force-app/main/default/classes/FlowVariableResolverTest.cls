@SuppressWarnings('PMD.MethodNamingConventions')
@IsTest
private class FlowVariableResolverTest {

    // ── resolveVariables ──────────────────────────────────────────────────────

    @IsTest
    static void resolveVariables_nullInput_returnsEmptyResult() {
        FlowVariableResolver.FlowResolutionResult result =
            FlowVariableResolver.resolveVariables(null);
        System.assert(result.valid);
        System.assertEquals(0, result.resolved.size());
    }

    @IsTest
    static void resolveVariables_emptyMap_returnsEmptyResult() {
        FlowVariableResolver.FlowResolutionResult result =
            FlowVariableResolver.resolveVariables(new Map<String, Object>());
        System.assert(result.valid);
        System.assertEquals(0, result.resolved.size());
    }

    @IsTest
    static void resolveVariables_singleVariable_prefixedInResult() {
        Map<String, Object> vars = new Map<String, Object>{ 'greeting' => 'Hello World' };
        FlowVariableResolver.FlowResolutionResult result =
            FlowVariableResolver.resolveVariables(vars);
        System.assert(result.valid);
        System.assert(result.resolved.containsKey('Flow.greeting'));
        System.assertEquals('Hello World', result.resolved.get('Flow.greeting'));
    }

    @IsTest
    static void resolveVariables_nullValue_resolvedAsEmpty() {
        Map<String, Object> vars = new Map<String, Object>{ 'nullVar' => null };
        FlowVariableResolver.FlowResolutionResult result =
            FlowVariableResolver.resolveVariables(vars);
        System.assertEquals('', result.resolved.get('Flow.nullVar'));
    }

    @IsTest
    static void resolveVariables_multipleVariables_allPrefixed() {
        Map<String, Object> vars = new Map<String, Object>{
            'firstName' => 'John',
            'lastName'  => 'Doe',
            'amount'    => 1500
        };
        FlowVariableResolver.FlowResolutionResult result =
            FlowVariableResolver.resolveVariables(vars);
        System.assertEquals(3, result.resolved.size());
        System.assertEquals('John', result.resolved.get('Flow.firstName'));
        System.assertEquals('Doe',  result.resolved.get('Flow.lastName'));
        System.assertEquals('1500', result.resolved.get('Flow.amount'));
    }

    @IsTest
    static void resolveVariables_blankKey_skipped() {
        Map<String, Object> vars = new Map<String, Object>{
            ''      => 'ignored',
            'valid' => 'kept'
        };
        FlowVariableResolver.FlowResolutionResult result =
            FlowVariableResolver.resolveVariables(vars);
        System.assertEquals(1, result.resolved.size());
        System.assert(result.resolved.containsKey('Flow.valid'));
    }

    // ── extractFlowVariableNames ──────────────────────────────────────────────

    @IsTest
    static void extractFlowVariableNames_noFlowTags_emptySet() {
        Set<String> names = FlowVariableResolver.extractFlowVariableNames('Hello {{Parent.Name}}');
        System.assertEquals(0, names.size());
    }

    @IsTest
    static void extractFlowVariableNames_singleTag_returned() {
        Set<String> names = FlowVariableResolver.extractFlowVariableNames('{{Flow.myVar}}');
        System.assertEquals(1, names.size());
        System.assert(names.contains('myVar'));
    }

    @IsTest
    static void extractFlowVariableNames_multipleTags_allReturned() {
        Set<String> names = FlowVariableResolver.extractFlowVariableNames(
            '{{Flow.firstName}} {{Flow.lastName}} {{Flow.firstName}}'
        );
        System.assertEquals(2, names.size(), 'Duplicates should be deduplicated');
        System.assert(names.contains('firstName'));
        System.assert(names.contains('lastName'));
    }

    @IsTest
    static void extractFlowVariableNames_blankContent_emptySet() {
        Set<String> names = FlowVariableResolver.extractFlowVariableNames(null);
        System.assertEquals(0, names.size());
    }

    // ── getAvailableFlows ─────────────────────────────────────────────────────

    @IsTest
    static void getAvailableFlows_returnsListWithoutError() {
        // FlowDefinitionView may return 0 flows in a fresh scratch org — just verify no exception
        List<FlowVariableResolver.FlowSummary> flows = FlowVariableResolver.getAvailableFlows();
        System.assertNotEquals(null, flows, 'Should return a list (possibly empty)');
    }

    // ── end-to-end: resolve and inject into merge context ────────────────────

    @IsTest
    static void resolveVariables_integratesWithMergeContext() {
        Map<String, Object> vars = new Map<String, Object>{ 'promoCode' => 'SAVE20' };
        FlowVariableResolver.FlowResolutionResult result =
            FlowVariableResolver.resolveVariables(vars);

        GenericMergeFieldResolver.MergeContext ctx = new GenericMergeFieldResolver.MergeContext();
        ctx.aliasValues = result.resolved;

        String resolved = GenericMergeFieldResolver.resolveTemplate(
            'Your code: {{Flow.promoCode}}', ctx
        );
        System.assertEquals('Your code: SAVE20', resolved);
    }
}
