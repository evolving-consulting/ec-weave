@IsTest
private class MCNTemplateRenderServiceTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Weave_Template_Config__c makeTemplate() {
        Weave_Template_Config__c t = new Weave_Template_Config__c(
            Name                   = 'MCN Render Test',
            Status__c              = 'Draft',
            Parent_Object_API_Name__c = 'Contact',
            Subject_Template__c    = 'Hello {{Parent.FirstName}}'
        );
        insert t;
        return t;
    }

    private static Contact makeContact() {
        Contact c = new Contact(FirstName = 'Jane', LastName = 'Doe', Email = 'jane@example.com');
        insert c;
        return c;
    }

    // ── Context parsing ───────────────────────────────────────────────────────

    @IsTest
    static void testParseContext_null() {
        MCNTemplateRenderService.ContextData ctx = MCNTemplateRenderService.parseContext(null);
        System.assertNotEquals(null, ctx, 'Should return empty context for null input');
    }

    @IsTest
    static void testParseContext_empty() {
        MCNTemplateRenderService.ContextData ctx = MCNTemplateRenderService.parseContext('{}');
        System.assertEquals(null, ctx.parentRecordId, 'No recordId in payload');
    }

    @IsTest
    static void testParseContext_full() {
        Contact c = makeContact();
        String json = JSON.serialize(new Map<String, Object>{
            'recordId'      => String.valueOf(c.Id),
            'flowVariables' => new Map<String, Object>{ 'greeting' => 'Hi' },
            'dataCloudValues' => new Map<String, Object>{ 'DataCloud.Contact__dlm.Email__c' => 'a@b.com' }
        });

        MCNTemplateRenderService.ContextData ctx = MCNTemplateRenderService.parseContext(json);
        System.assertEquals(String.valueOf(c.Id), ctx.parentRecordId);
        System.assertEquals('Hi', ctx.flowVariables.get('greeting'));
        System.assertEquals('a@b.com', ctx.dataCloudValues.get('DataCloud.Contact__dlm.Email__c'));
    }

    @IsTest
    static void testParseContext_malformedJson_returnsEmpty() {
        MCNTemplateRenderService.ContextData ctx = MCNTemplateRenderService.parseContext('not-json');
        System.assertNotEquals(null, ctx, 'Should not throw on malformed JSON');
    }

    // ── Cache key ─────────────────────────────────────────────────────────────

    @IsTest
    static void testBuildCacheKey_deterministicForSameInput() {
        Id fakeId = '001000000000001AAA';
        String key1 = MCNTemplateRenderService.buildCacheKey(fakeId, '{"a":1}');
        String key2 = MCNTemplateRenderService.buildCacheKey(fakeId, '{"a":1}');
        System.assertEquals(key1, key2, 'Same input must produce same cache key');
    }

    @IsTest
    static void testBuildCacheKey_differsForDifferentInput() {
        Id fakeId = '001000000000001AAA';
        String key1 = MCNTemplateRenderService.buildCacheKey(fakeId, '{"a":1}');
        String key2 = MCNTemplateRenderService.buildCacheKey(fakeId, '{"a":2}');
        System.assertNotEquals(key1, key2, 'Different context should produce different key');
    }

    // ── resolveTemplate ───────────────────────────────────────────────────────

    @IsTest
    static void testResolveTemplate_nullTemplateIdReturnsError() {
        MCNTemplateRenderService.RenderResult result =
            MCNTemplateRenderService.resolveTemplate(null, '{}');
        System.assertNotEquals(null, result);
        System.assertEquals(false, result.isSuccess);
        System.assert(result.errorMessage != null, 'Error message should be populated');
    }

    @IsTest
    static void testResolveTemplate_invalidTemplateIdReturnsError() {
        // Non-existent template — renderer will throw
        MCNTemplateRenderService.RenderResult result =
            MCNTemplateRenderService.resolveTemplate('001000000000001AAA', '{}');
        System.assertEquals(false, result.isSuccess);
    }
}
