/**
 * Resolves selectable Dynamic Communication Engine recipient options from configuration records.
 * Business record access is delegated to GenericDynamicQueryService.
 */
public with sharing class GenericRecipientResolver {
    private static final String SOURCE_TYPE_PARENT_FIELD = 'Parent Field';
    private static final String SOURCE_TYPE_RELATED_RECORDS = 'Related Records';
    private static final String SOURCE_TYPE_MANUAL = 'Manual';
    private static final String EMAIL_REGEX = '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$';

    public static List<RecipientOptionDTO> getRecipientOptions(Id templateId, Id recordId) {
        if (templateId == null) {
            throw new AuraHandledException('Template Id is required.');
        }
        if (recordId == null) {
            throw new AuraHandledException('Record Id is required.');
        }

        Email_Template_Config__c template = loadTemplate(templateId);
        List<Email_Template_Recipient_Config__c> configs = loadRecipientConfigs(templateId);
        List<RecipientOptionDTO> options = new List<RecipientOptionDTO>();
        List<Email_Template_Recipient_Config__c> parentFieldConfigs = new List<Email_Template_Recipient_Config__c>();
        List<Email_Template_Recipient_Config__c> manualConfigs = new List<Email_Template_Recipient_Config__c>();
        Email_Template_Recipient_Config__c relatedRecordConfig;

        for (Email_Template_Recipient_Config__c config : configs) {
            if (config.Recipient_Source_Type__c == SOURCE_TYPE_PARENT_FIELD) {
                parentFieldConfigs.add(config);
            } else if (config.Recipient_Source_Type__c == SOURCE_TYPE_RELATED_RECORDS) {
                if (relatedRecordConfig != null) {
                    throw new AuraHandledException(
                        'This template has more than one active Related Records recipient source. ' +
                        'Keep one active source and try again.'
                    );
                }
                relatedRecordConfig = config;
            } else if (config.Recipient_Source_Type__c == SOURCE_TYPE_MANUAL) {
                manualConfigs.add(config);
            }
        }
        if (relatedRecordConfig != null) {
            options.addAll(resolveRelatedRecordRecipients(template, relatedRecordConfig, recordId));
        }
        for (Email_Template_Recipient_Config__c manualConfig : manualConfigs) {
            options.add(buildManualOption(manualConfig));
        }

        List<RecipientOptionDTO> allOptions = resolveParentFieldRecipients(template, parentFieldConfigs, recordId);
        allOptions.addAll(options);
        return allOptions;
    }

    private static Email_Template_Config__c loadTemplate(Id templateId) {
        List<Email_Template_Config__c> templates = [
            SELECT Id,
                Name,
                Active__c,
                Parent_Object_API_Name__c
            FROM Email_Template_Config__c
            WHERE Id = :templateId
            WITH USER_MODE
            LIMIT 1
        ];

        if (templates.isEmpty()) {
            throw new AuraHandledException('Template not found.');
        }

        Email_Template_Config__c template = templates[0];
        if (template.Active__c != true) {
            throw new AuraHandledException('Template is inactive.');
        }
        if (String.isBlank(template.Parent_Object_API_Name__c)) {
            throw new AuraHandledException('Template parent object is not configured.');
        }

        GenericDynamicQueryService.assertValidObject(template.Parent_Object_API_Name__c);
        return template;
    }

    private static List<Email_Template_Recipient_Config__c> loadRecipientConfigs(Id templateId) {
        return [
            SELECT Id,
                Name,
                Active__c,
                Display_Order__c,
                Recipient_Source_Type__c,
                Recipient_Type__c,
                Source_Object_API_Name__c,
                Parent_Lookup_Field_API_Name__c,
                Name_Field_API_Name__c,
                Email_Field_API_Name__c,
                Filter_Logic__c,
                Default_Selected__c,
                Allow_Multiple__c,
                Required__c
            FROM Email_Template_Recipient_Config__c
            WHERE Email_Template_Config__c = :templateId
                AND Active__c = true
            WITH USER_MODE
            ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
        ];
    }

    private static List<RecipientOptionDTO> resolveParentFieldRecipients(
        Email_Template_Config__c template,
        List<Email_Template_Recipient_Config__c> configs,
        Id recordId
    ) {
        List<RecipientOptionDTO> options = new List<RecipientOptionDTO>();
        if (configs == null || configs.isEmpty()) {
            return options;
        }

        Set<String> fieldPaths = new Set<String>();
        for (Email_Template_Recipient_Config__c config : configs) {
            validateParentFieldConfig(config);
            fieldPaths.add(config.Name_Field_API_Name__c);
            fieldPaths.add(config.Email_Field_API_Name__c);
        }

        SObject parentRecord = GenericDynamicQueryService.queryRecordById(
            template.Parent_Object_API_Name__c,
            recordId,
            fieldPaths
        );

        for (Email_Template_Recipient_Config__c config : configs) {
            String email = stringValue(getValueByPath(parentRecord, config.Email_Field_API_Name__c));
            if (!isValidEmail(email)) {
                continue;
            }

            String name = stringValue(getValueByPath(parentRecord, config.Name_Field_API_Name__c));
            String idValue = SOURCE_TYPE_PARENT_FIELD + '-' + String.valueOf(config.Id);
            options.add(buildRecipientOption(
                idValue,
                name,
                email,
                config,
                SOURCE_TYPE_PARENT_FIELD,
                SOURCE_TYPE_PARENT_FIELD
            ));
        }

        return options;
    }

    private static List<RecipientOptionDTO> resolveRelatedRecordRecipients(
        Email_Template_Config__c template,
        Email_Template_Recipient_Config__c config,
        Id recordId
    ) {
        validateRelatedRecordConfig(config);

        Set<String> fieldPaths = new Set<String>{
            config.Name_Field_API_Name__c,
            config.Email_Field_API_Name__c
        };

        List<SObject> relatedRecords = GenericDynamicQueryService.queryChildRecords(
            config.Source_Object_API_Name__c,
            config.Parent_Lookup_Field_API_Name__c,
            recordId,
            fieldPaths,
            null,
            null,
            config.Filter_Logic__c
        );

        List<RecipientOptionDTO> options = new List<RecipientOptionDTO>();
        for (SObject relatedRecord : relatedRecords) {
            String email = stringValue(getValueByPath(relatedRecord, config.Email_Field_API_Name__c));
            if (!isValidEmail(email)) {
                continue;
            }

            String name = stringValue(getValueByPath(relatedRecord, config.Name_Field_API_Name__c));
            options.add(buildRecipientOption(
                String.valueOf(relatedRecord.get('Id')),
                name,
                email,
                config,
                SOURCE_TYPE_RELATED_RECORDS,
                SOURCE_TYPE_RELATED_RECORDS
            ));
        }

        return options;
    }

    private static RecipientOptionDTO buildManualOption(Email_Template_Recipient_Config__c config) {
        RecipientOptionDTO option = new RecipientOptionDTO();
        option.id = 'manual-' + String.valueOf(config.Id);
        option.name = 'Manual Recipient';
        option.email = null;
        option.recipientType = config.Recipient_Type__c;
        option.source = SOURCE_TYPE_MANUAL;
        option.selected = false;
        option.required = config.Required__c == true;
        option.allowMultiple = config.Allow_Multiple__c == true;
        option.sourceType = SOURCE_TYPE_MANUAL;
        return option;
    }

    private static RecipientOptionDTO buildRecipientOption(
        String id,
        String name,
        String email,
        Email_Template_Recipient_Config__c config,
        String source,
        String sourceType
    ) {
        RecipientOptionDTO option = new RecipientOptionDTO();
        option.id = id;
        option.name = String.isBlank(name) ? email : name;
        option.email = email;
        option.recipientType = config.Recipient_Type__c;
        option.source = source;
        option.selected = config.Default_Selected__c == true;
        option.required = config.Required__c == true;
        option.allowMultiple = config.Allow_Multiple__c == true;
        option.sourceType = sourceType;
        return option;
    }

    private static void validateParentFieldConfig(Email_Template_Recipient_Config__c config) {
        if (String.isBlank(config.Email_Field_API_Name__c)) {
            throw new AuraHandledException('Recipient configuration is missing email field.');
        }
        if (String.isBlank(config.Name_Field_API_Name__c)) {
            throw new AuraHandledException('Recipient configuration is missing name field.');
        }
        if (String.isBlank(config.Recipient_Type__c)) {
            throw new AuraHandledException('Recipient configuration is missing recipient type.');
        }
    }

    private static void validateRelatedRecordConfig(Email_Template_Recipient_Config__c config) {
        if (String.isBlank(config.Source_Object_API_Name__c)) {
            throw new AuraHandledException('Recipient configuration is missing source object.');
        }
        if (String.isBlank(config.Parent_Lookup_Field_API_Name__c)) {
            throw new AuraHandledException('Recipient configuration is missing parent lookup field.');
        }
        if (String.isBlank(config.Email_Field_API_Name__c)) {
            throw new AuraHandledException('Recipient configuration is missing email field.');
        }
        if (String.isBlank(config.Name_Field_API_Name__c)) {
            throw new AuraHandledException('Recipient configuration is missing name field.');
        }
        if (String.isBlank(config.Recipient_Type__c)) {
            throw new AuraHandledException('Recipient configuration is missing recipient type.');
        }
    }

    private static Object getValueByPath(SObject record, String fieldPath) {
        if (record == null || String.isBlank(fieldPath)) {
            return null;
        }

        List<String> segments = fieldPath.split('\\.');
        SObject currentRecord = record;

        for (Integer i = 0; i < segments.size(); i++) {
            String segment = segments[i];
            Boolean finalSegment = i == segments.size() - 1;

            try {
                if (finalSegment) {
                    return currentRecord.get(segment);
                }

                currentRecord = currentRecord.getSObject(segment);
                if (currentRecord == null) {
                    return null;
                }
            } catch (Exception ignoredException) {
                return null;
            }
        }

        return null;
    }

    private static Boolean isValidEmail(String email) {
        return !String.isBlank(email) && Pattern.matches(EMAIL_REGEX, email.trim().toUpperCase());
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }
}
