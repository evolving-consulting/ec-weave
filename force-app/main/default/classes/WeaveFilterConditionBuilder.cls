@SuppressWarnings('PMD.IfStmtsMustUseBraces,PMD.IfElseStmtsMustUseBraces,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.ApexDoc')
public with sharing class WeaveFilterConditionBuilder {

    private static final Set<String> ALLOWED_OPERATORS = new Set<String>{
        '=', '!=', 'LIKE', 'NOT LIKE', '>', '>=', '<', '<=', 'IN', 'NOT IN'
    };

    public class FilterCondition {
        public String field       { get; set; }
        public String operator    { get; set; }
        public String value       { get; set; }
        public String conjunction { get; set; } // 'AND' | 'OR' | null
    }

    public static String buildClause(String objectApiName, String conditionsJson) {
        if (String.isBlank(objectApiName) || String.isBlank(conditionsJson)) return null;

        List<FilterCondition> conditions;
        try {
            conditions = (List<FilterCondition>) JSON.deserialize(conditionsJson, List<FilterCondition>.class);
        } catch (Exception e) {
            throw new IllegalArgumentException('Invalid filter conditions JSON.');
        }
        if (conditions == null || conditions.isEmpty()) return null;

        Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectApiName);

        List<String> parts = new List<String>();
        for (Integer i = 0; i < conditions.size(); i++) {
            FilterCondition c = conditions[i];
            if (String.isBlank(c.field) || String.isBlank(c.operator) || c.value == null) continue;

            String fieldLower = c.field.toLowerCase();
            if (!fieldMap.containsKey(fieldLower)) {
                throw new IllegalArgumentException('Unknown field: ' + c.field);
            }
            if (!ALLOWED_OPERATORS.contains(c.operator.toUpperCase())) {
                throw new IllegalArgumentException('Invalid operator: ' + c.operator);
            }

            Schema.DisplayType fieldType = fieldMap.get(fieldLower).getDescribe().getType();
            String clause = buildFieldClause(c, fieldType);

            if (i < conditions.size() - 1 && String.isNotBlank(c.conjunction)) {
                String conj = c.conjunction.toUpperCase();
                if (conj != 'AND' && conj != 'OR') conj = 'AND';
                parts.add(clause + ' ' + conj);
            } else {
                parts.add(clause);
            }
        }
        return parts.isEmpty() ? null : String.join(parts, ' ');
    }

    private static String buildFieldClause(FilterCondition c, Schema.DisplayType fieldType) {
        String op = c.operator.toUpperCase();
        String val = c.value;

        if (op == 'IN' || op == 'NOT IN') {
            List<String> items = new List<String>();
            for (String v : val.split(',')) {
                items.add('\'' + String.escapeSingleQuotes(v.trim()) + '\'');
            }
            return c.field + ' ' + op + ' (' + String.join(items, ', ') + ')';
        }

        if (op == 'LIKE' || op == 'NOT LIKE') {
            if (!val.contains('%') && !val.contains('_')) val = '%' + val + '%';
            return c.field + ' ' + op + ' \'' + String.escapeSingleQuotes(val) + '\'';
        }

        if (isNumericType(fieldType)) {
            Decimal numVal;
            try { numVal = Decimal.valueOf(val); } catch (Exception e) {
                throw new IllegalArgumentException('Expected a number for field ' + c.field);
            }
            return c.field + ' ' + op + ' ' + numVal;
        }

        if (fieldType == Schema.DisplayType.BOOLEAN) {
            Boolean boolVal = Boolean.valueOf(val);
            return c.field + ' ' + op + ' ' + boolVal;
        }

        if (fieldType == Schema.DisplayType.DATE) {
            return c.field + ' ' + op + ' ' + String.escapeSingleQuotes(val);
        }

        if (fieldType == Schema.DisplayType.DATETIME) {
            return c.field + ' ' + op + ' ' + String.escapeSingleQuotes(val);
        }

        return c.field + ' ' + op + ' \'' + String.escapeSingleQuotes(val) + '\'';
    }

    private static Boolean isNumericType(Schema.DisplayType t) {
        return t == Schema.DisplayType.INTEGER
            || t == Schema.DisplayType.DOUBLE
            || t == Schema.DisplayType.CURRENCY
            || t == Schema.DisplayType.PERCENT
            || t == Schema.DisplayType.LONG;
    }

    private static Map<String, Schema.SObjectField> getFieldMap(String objectApiName) {
        try {
            Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
            if (sot == null) throw new IllegalArgumentException('Unknown object: ' + objectApiName);
            return sot.getDescribe().fields.getMap();
        } catch (IllegalArgumentException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalArgumentException('Could not describe object: ' + objectApiName);
        }
    }
}
