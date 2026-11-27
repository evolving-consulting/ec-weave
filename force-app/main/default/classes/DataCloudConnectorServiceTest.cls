@IsTest
private class DataCloudConnectorServiceTest {

    // ── getAvailableConnectors ────────────────────────────────────────────────

    @IsTest
    static void getAvailableConnectors_returnsListWithoutError() {
        // In a standard dev sandbox without Data Cloud, this returns an empty list.
        // The test verifies no exception is thrown and the return type is correct.
        List<DataCloudConnectorService.ConnectorObject> connectors =
            DataCloudConnectorService.getAvailableConnectors();
        System.assertNotEquals(null, connectors, 'Should return a list');
    }

    @IsTest
    static void getAvailableConnectors_cacheReturnsSameReference() {
        List<DataCloudConnectorService.ConnectorObject> first  =
            DataCloudConnectorService.getAvailableConnectors();
        List<DataCloudConnectorService.ConnectorObject> second =
            DataCloudConnectorService.getAvailableConnectors();
        // Both calls within the same transaction should return the same list instance
        System.assert(first === second, 'Second call should return cached instance');
    }

    // ── getAttributesForObject ────────────────────────────────────────────────

    @IsTest
    static void getAttributesForObject_nullApiName_returnsEmpty() {
        List<DataCloudConnectorService.ConnectorAttribute> attrs =
            DataCloudConnectorService.getAttributesForObject(null);
        System.assertEquals(0, attrs.size());
    }

    @IsTest
    static void getAttributesForObject_blankApiName_returnsEmpty() {
        List<DataCloudConnectorService.ConnectorAttribute> attrs =
            DataCloudConnectorService.getAttributesForObject('   ');
        System.assertEquals(0, attrs.size());
    }

    @IsTest
    static void getAttributesForObject_unknownObject_returnsEmpty() {
        List<DataCloudConnectorService.ConnectorAttribute> attrs =
            DataCloudConnectorService.getAttributesForObject('NonExistentObject__dll');
        System.assertEquals(0, attrs.size());
    }

    @IsTest
    static void getAttributesForObject_knownStandardObject_returnsFields() {
        // Use Account as a proxy to verify the describe logic works correctly
        // (actual Data Cloud objects (__dll/__dlm) may not exist in the test org)
        List<DataCloudConnectorService.ConnectorAttribute> attrs =
            DataCloudConnectorService.getAttributesForObject('Account');
        // Account has fields (Id, Name, etc.) — list should not be empty
        System.assert(!attrs.isEmpty(), 'Account should return field attributes');
        // Verify DTO fields are populated
        DataCloudConnectorService.ConnectorAttribute first = attrs[0];
        System.assertNotEquals(null, first.apiName);
        System.assertNotEquals(null, first.label);
        System.assertNotEquals(null, first.fieldType);
    }

    // ── isDataCloudEnabled ────────────────────────────────────────────────────

    @IsTest
    static void isDataCloudEnabled_returnsBoolean() {
        Boolean enabled = DataCloudConnectorService.isDataCloudEnabled();
        // Simply verify the method executes without error; value depends on the org
        System.assertNotEquals(null, enabled);
    }

    // ── ConnectorObject DTO ───────────────────────────────────────────────────

    @IsTest
    static void connectorObjectDTO_fieldsPopulatedCorrectly() {
        DataCloudConnectorService.ConnectorObject obj =
            new DataCloudConnectorService.ConnectorObject('MyObj__dlm', 'My Object', 'DMO');
        System.assertEquals('MyObj__dlm', obj.apiName);
        System.assertEquals('My Object', obj.label);
        System.assertEquals('DMO', obj.objectType);
        System.assertEquals(0, obj.attributes.size());
    }

    @IsTest
    static void connectorAttributeDTO_fieldsPopulatedCorrectly() {
        DataCloudConnectorService.ConnectorAttribute attr =
            new DataCloudConnectorService.ConnectorAttribute('Email__c', 'Email', 'STRING');
        System.assertEquals('Email__c', attr.apiName);
        System.assertEquals('Email', attr.label);
        System.assertEquals('STRING', attr.fieldType);
    }
}
