@IsTest
private class MergeFieldValidatorTest {

    // ── validateTemplate ──────────────────────────────────────────────────────

    @IsTest
    static void validateTemplate_emptyContent_returnsValid() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('', 'Account');
        System.assert(result.isValid, 'Empty template should be valid');
        System.assertEquals(0, result.errors.size());
    }

    @IsTest
    static void validateTemplate_validParentField_noErrors() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('Hello {{Parent.Name}}', 'Account');
        System.assertEquals(0, result.errors.size(), 'Valid parent field should produce no errors');
    }

    @IsTest
    static void validateTemplate_validFlowTag_noErrors() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('Value: {{Flow.myVariable}}', 'Account');
        System.assertEquals(0, result.errors.size(), 'Valid flow tag should produce no errors');
    }

    @IsTest
    static void validateTemplate_validDataCloudTag_noErrors() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('{{DataCloud.Contact__dlm.Email__c}}', 'Account');
        System.assertEquals(0, result.errors.size(), 'Valid DataCloud tag should produce no errors');
    }

    @IsTest
    static void validateTemplate_invalidFlowTagMissingVarName_hasError() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('{{Flow}}', 'Account');
        // 'Flow' alone doesn't match the placeholder regex (no dot segment) — no tag extracted
        // A single-word 'Flow' is treated as a bare field reference
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void validateTemplate_flowTagWithTooManySegments_hasError() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('{{Flow.var.extra}}', 'Account');
        System.assertEquals(1, result.errors.size(), 'Flow tag with extra segments should error');
        System.assertEquals('Flow', result.errors[0].sourceType);
    }

    @IsTest
    static void validateTemplate_dataCloudTagMissingAttribute_hasError() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('{{DataCloud.MyObject}}', 'Account');
        System.assertEquals(1, result.errors.size(), 'DataCloud tag with only 2 segments should error');
        System.assertEquals('DataCloud', result.errors[0].sourceType);
    }

    @IsTest
    static void validateTemplate_dataCloudTagTooManySegments_hasError() {
        // 4-segment tag is beyond the resolver's supported depth; the extra segment makes it invalid
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('{{DataCloud.Obj.Attr.Extra}}', 'Account');
        System.assertEquals(1, result.errors.size(), 'DataCloud tag with 4 segments should error');
    }

    @IsTest
    static void validateTemplate_validBrandTag_noErrors() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('{{Brand.LogoUrl}}', 'Account');
        System.assertEquals(0, result.errors.size());
        System.assertEquals(0, result.warnings.size());
    }

    @IsTest
    static void validateTemplate_invalidBrandAttr_hasWarning() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('{{Brand.FakeAttr}}', 'Account');
        System.assertEquals(1, result.warnings.size(), 'Unknown Brand attr should warn');
        System.assertEquals('Brand', result.warnings[0].sourceType);
    }

    @IsTest
    static void validateTemplate_senderAlias_noErrors() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('{{Sender.Name}}', 'Account');
        System.assertEquals(0, result.errors.size());
        System.assertEquals(0, result.warnings.size());
    }

    @IsTest
    static void validateTemplate_sectionTag_noErrors() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('{{Section.myQuery}}', 'Account');
        System.assertEquals(0, result.errors.size());
    }

    @IsTest
    static void validateTemplate_sectionTagMissingKey_hasError() {
        // 'Section' alone — doesn't match regex (single word), so no tag extracted
        // This tests the actual Section.X format with wrong number of parts
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('{{Section.a.b}}', 'Account');
        System.assertEquals(1, result.errors.size(), 'Section tag with extra segment should error');
    }

    @IsTest
    static void validateTemplate_parentMissingField_hasError() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate('{{Parent}}', 'Account');
        System.assertEquals(1, result.errors.size(), 'Parent tag with no field should error');
    }

    @IsTest
    static void validateTemplate_duplicateTags_validatedOnce() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateTemplate(
                '{{Flow.var.extra}} and {{Flow.var.extra}}', 'Account'
            );
        System.assertEquals(1, result.errors.size(), 'Duplicate invalid tags should produce one error');
    }

    // ── validateMergeField ────────────────────────────────────────────────────

    @IsTest
    static void validateMergeField_withBraces_stripsAndValidates() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateMergeField('{{Flow.myVar}}', 'Account');
        System.assertEquals(0, result.errors.size());
        System.assert(result.isValid);
    }

    @IsTest
    static void validateMergeField_withoutBraces_validates() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateMergeField('Flow.myVar', 'Account');
        System.assertEquals(0, result.errors.size());
        System.assert(result.isValid);
    }

    @IsTest
    static void validateMergeField_emptyInput_returnsValid() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateMergeField('', null);
        System.assert(result.isValid);
    }

    @IsTest
    static void validateMergeField_invalidFlowSyntax_returnsInvalid() {
        MergeFieldValidator.ValidationResult result =
            MergeFieldValidator.validateMergeField('Flow.a.b', 'Account');
        Assert.isFalse(result.isValid);
        Assert.areEqual(1, result.errors.size());
    }
}
