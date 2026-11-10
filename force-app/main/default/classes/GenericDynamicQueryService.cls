/**
 * Generic, safe dynamic query helper for the Dynamic Communication Engine.
 * This class validates object and field API names before constructing SOQL.
 */
public with sharing class GenericDynamicQueryService {
    private static final String IDENTIFIER_REGEX = '^[A-Za-z_][A-Za-z0-9_]*(__(c|r))?$';
    private static final String FIELD_PATH_REGEX = '^[A-Za-z_][A-Za-z0-9_]*(__(c|r))?(\\.[A-Za-z_][A-Za-z0-9_]*(__(c|r))?){0,2}$';

    public static Boolean isValidObject(String objectApiName) {
        if (isBlank(objectApiName) || !isSafeIdentifier(objectApiName)) {
            return false;
        }
        return Schema.getGlobalDescribe().containsKey(objectApiName);
    }

    public static void assertValidObject(String objectApiName) {
        if (!isValidObject(objectApiName)) {
            throw new AuraHandledException('Invalid object API name: ' + objectApiName);
        }

        Schema.DescribeSObjectResult objectDescribe = getObjectDescribe(objectApiName);
        if (!objectDescribe.isAccessible()) {
            throw new AuraHandledException('You do not have access to object: ' + objectApiName);
        }
    }

    public static Boolean isValidField(String objectApiName, String fieldApiName) {
        if (!isValidObject(objectApiName) || isBlank(fieldApiName) || !isSafeIdentifier(fieldApiName) || fieldApiName.contains('.')) {
            return false;
        }

        Map<String, Schema.SObjectField> fields = getObjectDescribe(objectApiName).fields.getMap();
        return fields.containsKey(fieldApiName);
    }

    public static void assertValidField(String objectApiName, String fieldApiName) {
        if (!isValidField(objectApiName, fieldApiName)) {
            throw new AuraHandledException('Invalid field API name: ' + fieldApiName + ' on object: ' + objectApiName);
        }

        Schema.DescribeFieldResult fieldDescribe = getFieldDescribe(objectApiName, fieldApiName);
        if (!fieldDescribe.isAccessible()) {
            throw new AuraHandledException('You do not have access to field: ' + fieldApiName + ' on object: ' + objectApiName);
        }
    }

    public static Boolean isValidFieldPath(String baseObjectApiName, String fieldPath) {
        if (!isValidObject(baseObjectApiName) || isBlank(fieldPath) || !isSafeFieldPathSyntax(fieldPath)) {
            return false;
        }

        List<String> segments = fieldPath.split('\\.');
        String currentObjectApiName = baseObjectApiName;

        for (Integer i = 0; i < segments.size(); i++) {
            String segment = segments[i];

            if (i == segments.size() - 1) {
                if (!isValidField(currentObjectApiName, segment)) {
                    return false;
                }
                return getFieldDescribe(currentObjectApiName, segment).isAccessible();
            }

            RelationshipDescribe relationshipDescribe = getRelationshipDescribe(currentObjectApiName, segment);
            if (relationshipDescribe == null || relationshipDescribe.referenceObjectApiNames.isEmpty()) {
                return false;
            }

            currentObjectApiName = getAccessibleReferenceObject(relationshipDescribe.referenceObjectApiNames, segments[i + 1]);
            if (currentObjectApiName == null) {
                return false;
            }
        }

        return true;
    }

    public static void assertValidFieldPath(String baseObjectApiName, String fieldPath) {
        assertValidObject(baseObjectApiName);
        if (!isValidFieldPath(baseObjectApiName, fieldPath)) {
            throw new AuraHandledException('Invalid field path: ' + fieldPath + ' on object: ' + baseObjectApiName);
        }
    }

    @SuppressWarnings('PMD.ApexSOQLInjection')
    public static SObject queryRecordById(String objectApiName, Id recordId, Set<String> fieldPaths) {
        assertValidObject(objectApiName);
        assertValidRecordId(recordId);

        String selectClause = buildSelectClause(objectApiName, fieldPaths);
        String soql = 'SELECT ' + selectClause +
            ' FROM ' + objectApiName +
            ' WHERE Id = :recordId' +
            ' WITH USER_MODE' +
            ' LIMIT 1';

        List<SObject> records;
        try {
            records = Database.query(soql);
        } catch (QueryException queryException) {
            throw new AuraHandledException('Unable to read the requested record with your current access.');
        }

        if (records.isEmpty()) {
            throw new AuraHandledException('No record found for the provided record Id.');
        }

        return records[0];
    }

    @SuppressWarnings('PMD.ApexSOQLInjection')
    public static List<SObject> queryChildRecords(
        String childObjectApiName,
        String parentLookupFieldApiName,
        Id parentRecordId,
        Set<String> fieldPaths,
        String sortFieldApiName,
        String sortDirection,
        String filterLogic
    ) {
        assertValidObject(childObjectApiName);
        assertValidRecordId(parentRecordId);
        assertValidField(childObjectApiName, parentLookupFieldApiName);

        Schema.DescribeFieldResult parentLookupDescribe = getFieldDescribe(childObjectApiName, parentLookupFieldApiName);
        if (parentLookupDescribe.getType() != Schema.DisplayType.Reference) {
            throw new AuraHandledException('Parent lookup field must be a lookup or master-detail field: ' + parentLookupFieldApiName);
        }

        String selectClause = buildSelectClause(childObjectApiName, fieldPaths);
        String soql = 'SELECT ' + selectClause +
            ' FROM ' + childObjectApiName +
            ' WHERE ' + parentLookupFieldApiName + ' = :parentRecordId';

        String safeFilterClause = buildSafeFilterClause(childObjectApiName, filterLogic);
        if (!isBlank(safeFilterClause)) {
            soql += ' AND ' + safeFilterClause;
        }

        soql += ' WITH USER_MODE';

        if (!isBlank(sortFieldApiName)) {
            assertValidField(childObjectApiName, sortFieldApiName);
            soql += ' ORDER BY ' + sortFieldApiName + ' ' + normalizeSortDirection(sortDirection);
        } else {
            soql += ' ORDER BY Id';
        }
        soql += ' LIMIT 2000';

        try {
            return Database.query(soql);
        } catch (QueryException queryException) {
            throw new AuraHandledException('Unable to read related records with your current access.');
        }
    }

    private static String buildSelectClause(String objectApiName, Set<String> fieldPaths) {
        Set<String> selectedFields = new Set<String>{ 'Id' };

        if (fieldPaths != null) {
            for (String fieldPath : fieldPaths) {
                if (isBlank(fieldPath)) {
                    continue;
                }
                assertValidFieldPath(objectApiName, fieldPath);
                selectedFields.add(fieldPath.trim());
            }
        }

        List<String> orderedFields = new List<String>(selectedFields);
        orderedFields.sort();
        return String.join(orderedFields, ', ');
    }

    private static String buildSafeFilterClause(String objectApiName, String filterLogic) {
        if (isBlank(filterLogic)) {
            return null;
        }

        String trimmedFilter = filterLogic.trim();
        rejectUnsafeFilterTokens(trimmedFilter);

        List<String> expressions = trimmedFilter.split('(?i)\\s+AND\\s+');
        if (expressions.isEmpty()) {
            return null;
        }

        List<String> safeExpressions = new List<String>();
        for (String expression : expressions) {
            String safeExpression = buildSafeEqualityExpression(objectApiName, expression);
            safeExpressions.add(safeExpression);
        }

        return String.join(safeExpressions, ' AND ');
    }

    private static String buildSafeEqualityExpression(String objectApiName, String expression) {
        if (isBlank(expression)) {
            throw unsupportedFilterException();
        }

        Integer firstEqualsIndex = expression.indexOf('=');
        Integer lastEqualsIndex = expression.lastIndexOf('=');
        if (firstEqualsIndex <= 0 || firstEqualsIndex != lastEqualsIndex) {
            throw unsupportedFilterException();
        }

        String fieldApiName = expression.substring(0, firstEqualsIndex).trim();
        String value = expression.substring(firstEqualsIndex + 1).trim();

        assertValidField(objectApiName, fieldApiName);
        if (!isSafeLiteral(value)) {
            throw unsupportedFilterException();
        }

        return fieldApiName + ' = ' + value;
    }

    private static void rejectUnsafeFilterTokens(String filterLogic) {
        String upperFilter = filterLogic.toUpperCase();
        List<String> rejectedTokens = new List<String>{
            'SELECT', 'FROM', 'WHERE', 'ORDER BY', 'LIMIT', 'GROUP BY', 'HAVING', 'OR'
        };

        for (String token : rejectedTokens) {
            if (Pattern.matches('(?s).*\\b' + token.replace(' ', '\\s+') + '\\b.*', upperFilter)) {
                throw unsupportedFilterException();
            }
        }

        if (
            filterLogic.contains('(') ||
            filterLogic.contains(')') ||
            filterLogic.contains(';') ||
            filterLogic.contains(':') ||
            filterLogic.contains(',') ||
            filterLogic.contains('--') ||
            filterLogic.contains('/*') ||
            filterLogic.contains('*/') ||
            filterLogic.contains('\\')
        ) {
            throw unsupportedFilterException();
        }
    }

    private static Boolean isSafeLiteral(String value) {
        if (isBlank(value)) {
            return false;
        }

        String trimmedValue = value.trim();
        if (
            trimmedValue.equalsIgnoreCase('true') ||
            trimmedValue.equalsIgnoreCase('false') ||
            trimmedValue.equalsIgnoreCase('null')
        ) {
            return true;
        }

        if (Pattern.matches('^-?\\d+(\\.\\d+)?$', trimmedValue)) {
            return true;
        }

        if (trimmedValue.startsWith('\'') && trimmedValue.endsWith('\'') && trimmedValue.length() >= 2) {
            String innerValue = trimmedValue.substring(1, trimmedValue.length() - 1);
            return Pattern.matches('^[A-Za-z0-9 _.,@%+\\-]*$', innerValue);
        }

        return false;
    }

    private static Boolean isSafeIdentifier(String value) {
        return !isBlank(value) && Pattern.matches(IDENTIFIER_REGEX, value.trim());
    }

    private static Boolean isSafeFieldPathSyntax(String fieldPath) {
        if (isBlank(fieldPath) || !Pattern.matches(FIELD_PATH_REGEX, fieldPath.trim())) {
            return false;
        }

        String upperPath = fieldPath.toUpperCase();
        List<String> rejectedTokens = new List<String>{
            'SELECT', 'FROM', 'WHERE', 'ORDER', 'BY', 'LIMIT', 'GROUP', 'HAVING', 'OR', 'AND'
        };

        for (String token : rejectedTokens) {
            if (Pattern.matches('(?s).*\\b' + token + '\\b.*', upperPath)) {
                return false;
            }
        }

        return true;
    }

    private static String normalizeSortDirection(String sortDirection) {
        if (isBlank(sortDirection)) {
            return 'ASC';
        }

        String normalizedDirection = sortDirection.trim().toUpperCase();
        if (normalizedDirection == 'ASC' || normalizedDirection == 'DESC') {
            return normalizedDirection;
        }

        throw new AuraHandledException('Invalid sort direction. Only ASC or DESC are supported.');
    }

    private static void assertValidRecordId(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }
    }

    private static Schema.DescribeSObjectResult getObjectDescribe(String objectApiName) {
        return Schema.getGlobalDescribe().get(objectApiName).getDescribe();
    }

    private static Schema.DescribeFieldResult getFieldDescribe(String objectApiName, String fieldApiName) {
        return getObjectDescribe(objectApiName).fields.getMap().get(fieldApiName).getDescribe();
    }

    private static RelationshipDescribe getRelationshipDescribe(String objectApiName, String relationshipName) {
        Map<String, Schema.SObjectField> fields = getObjectDescribe(objectApiName).fields.getMap();

        for (Schema.SObjectField fieldToken : fields.values()) {
            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
            if (
                fieldDescribe.getType() == Schema.DisplayType.Reference &&
                fieldDescribe.getRelationshipName() == relationshipName &&
                fieldDescribe.isAccessible()
            ) {
                return new RelationshipDescribe(fieldDescribe.getReferenceTo());
            }
        }

        return null;
    }

    private static String getAccessibleReferenceObject(List<Schema.SObjectType> referenceTypes, String nextSegment) {
        for (Schema.SObjectType referenceType : referenceTypes) {
            Schema.DescribeSObjectResult referenceDescribe = referenceType.getDescribe();
            String referenceObjectApiName = referenceDescribe.getName();

            if (
                referenceDescribe.isAccessible() &&
                isValidField(referenceObjectApiName, nextSegment) &&
                getFieldDescribe(referenceObjectApiName, nextSegment).isAccessible()
            ) {
                return referenceObjectApiName;
            }
        }

        return null;
    }

    private static AuraHandledException unsupportedFilterException() {
        return new AuraHandledException('Advanced filter logic is not supported yet. Please use simple equality filters only.');
    }

    private static Boolean isBlank(String value) {
        return value == null || value.trim().length() == 0;
    }

    private class RelationshipDescribe {
        private List<Schema.SObjectType> referenceObjectApiNames;

        private RelationshipDescribe(List<Schema.SObjectType> referenceObjectApiNames) {
            this.referenceObjectApiNames = referenceObjectApiNames;
        }
    }
}
