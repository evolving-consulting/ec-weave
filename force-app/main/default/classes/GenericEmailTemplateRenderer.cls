/**
 * Renders configured Dynamic Communication Engine templates into email DTOs.
 * Business record access is delegated to GenericDynamicQueryService.
 */
public with sharing class GenericEmailTemplateRenderer {
  private static final String SECTION_TYPE_STATIC_TEXT = 'Static Text';
  private static final String SECTION_TYPE_TEXT_BLOCK = 'Text Block';
  private static final String SECTION_TYPE_TABLE = 'Table';
  private static Map<String, SObject> standardMergeAliases;

  public static RenderedEmailDTO renderEmail(Id templateId, Id recordId) {
    if (templateId == null) {
      throw new AuraHandledException('Template Id is required.');
    }
    if (recordId == null) {
      throw new AuraHandledException('Record Id is required.');
    }

    Email_Template_Config__c template = loadTemplate(templateId);
    DceTemplateContentService.ContentBundle content = DceTemplateContentService.loadContent(
      template
    );
    DceHtmlPolicy.assertSafeTemplateHtml(content.headerHtml, 'Header');
    DceHtmlPolicy.assertSafeTemplateHtml(content.bodyHtml, 'Body');
    DceHtmlPolicy.assertSafeTemplateHtml(content.footerHtml, 'Footer');
    List<Email_Template_Section__c> sections = loadSections(templateId);
    Set<Id> sectionIds = getSectionIds(sections);
    Map<Id, List<Email_Template_Line__c>> linesBySection = loadLinesBySection(
      sectionIds
    );
    Map<Id, List<Email_Template_Field__c>> fieldsBySection = loadFieldsBySection(
      sectionIds
    );

    SObject parentRecord = loadParentRecord(
      template,
      sections,
      linesBySection,
      fieldsBySection,
      recordId
    );
    Map<String, String> sectionHtmlByKey = new Map<String, String>();

    for (Email_Template_Section__c section : sections) {
      String sectionHtml = renderSection(
        section,
        parentRecord,
        template.Parent_Object_API_Name__c,
        recordId,
        getLines(linesBySection, section.Id),
        getFields(fieldsBySection, section.Id)
      );

      if (!String.isBlank(section.Section_Key__c)) {
        sectionHtmlByKey.put(section.Section_Key__c, sectionHtml);
      }
    }

    GenericMergeFieldResolver.MergeContext subjectContext = buildParentContext(
      parentRecord,
      template.Parent_Object_API_Name__c,
      sectionHtmlByKey,
      true
    );
    GenericMergeFieldResolver.MergeContext bodyContext = buildParentContext(
      parentRecord,
      template.Parent_Object_API_Name__c,
      sectionHtmlByKey,
      true
    );
    bodyContext.renderHtmlFormattedFields = true;

    String subject = GenericMergeFieldResolver.resolveTemplate(
      template.Subject_Template__c,
      subjectContext
    );
    String generatedBody = GenericMergeFieldResolver.resolveTemplate(
      content.bodyHtml,
      bodyContext
    );
    String htmlBody = wrapWithBranding(content, generatedBody, bodyContext);
    DceTemplateContentService.assertRenderedSize(htmlBody);
    String plainTextBody = stripHtml(htmlBody);

    return new RenderedEmailDTO(subject, htmlBody, plainTextBody);
  }

  private static Email_Template_Config__c loadTemplate(Id templateId) {
    List<Email_Template_Config__c> templates = [
      SELECT
        Id,
        Name,
        Active__c,
        Parent_Object_API_Name__c,
        Subject_Template__c,
        Body_Template__c,
        Header__c,
        Footer__c,
        Description__c,
        Allow_User_Edit_Before_Send__c,
        Store_Email_History__c
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
      throw new AuraHandledException(
        'Template parent object is not configured.'
      );
    }

    GenericDynamicQueryService.assertValidObject(
      template.Parent_Object_API_Name__c
    );
    return template;
  }

  private static List<Email_Template_Section__c> loadSections(Id templateId) {
    return [
      SELECT
        Id,
        Name,
        Email_Template_Config__c,
        Section_Name__c,
        Section_Key__c,
        Active__c,
        Display_Order__c,
        Section_Type__c,
        Child_Object_API_Name__c,
        Parent_Lookup_Field_API_Name__c,
        Sort_Field_API_Name__c,
        Sort_Direction__c,
        Filter_Logic__c,
        Static_Content__c,
        Section_Header__c,
        Section_Footer__c,
        Repeat_Label__c,
        Include_Auto_Number__c,
        Auto_Number_Start__c
      FROM Email_Template_Section__c
      WHERE Email_Template_Config__c = :templateId AND Active__c = TRUE
      WITH USER_MODE
      ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
    ];
  }

  private static Map<Id, List<Email_Template_Line__c>> loadLinesBySection(
    Set<Id> sectionIds
  ) {
    Map<Id, List<Email_Template_Line__c>> linesBySection = new Map<Id, List<Email_Template_Line__c>>();
    if (sectionIds == null || sectionIds.isEmpty()) {
      return linesBySection;
    }

    for (Email_Template_Line__c line : [
      SELECT
        Id,
        Name,
        Email_Template_Section__c,
        Display_Order__c,
        Active__c,
        Line_Template__c,
        Display_Style__c,
        Render_Only_If_Not_Blank__c
      FROM Email_Template_Line__c
      WHERE Email_Template_Section__c IN :sectionIds AND Active__c = TRUE
      WITH USER_MODE
      ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
    ]) {
      if (!linesBySection.containsKey(line.Email_Template_Section__c)) {
        linesBySection.put(
          line.Email_Template_Section__c,
          new List<Email_Template_Line__c>()
        );
      }
      linesBySection.get(line.Email_Template_Section__c).add(line);
    }

    return linesBySection;
  }

  private static Map<Id, List<Email_Template_Field__c>> loadFieldsBySection(
    Set<Id> sectionIds
  ) {
    Map<Id, List<Email_Template_Field__c>> fieldsBySection = new Map<Id, List<Email_Template_Field__c>>();
    if (sectionIds == null || sectionIds.isEmpty()) {
      return fieldsBySection;
    }

    for (Email_Template_Field__c fieldConfig : [
      SELECT
        Id,
        Name,
        Email_Template_Section__c,
        Field_API_Name__c,
        Label_Override__c,
        Display_Order__c,
        Active__c,
        Show_Label__c,
        Display_Style__c,
        Is_Main_Title__c,
        Prefix_Text__c,
        Suffix_Text__c,
        Line_Break_After__c,
        Render_Only_If_Not_Blank__c,
        Table_Column_Width__c
      FROM Email_Template_Field__c
      WHERE Email_Template_Section__c IN :sectionIds AND Active__c = TRUE
      WITH USER_MODE
      ORDER BY Display_Order__c ASC NULLS LAST, Name ASC
    ]) {
      if (!fieldsBySection.containsKey(fieldConfig.Email_Template_Section__c)) {
        fieldsBySection.put(
          fieldConfig.Email_Template_Section__c,
          new List<Email_Template_Field__c>()
        );
      }
      fieldsBySection.get(fieldConfig.Email_Template_Section__c)
        .add(fieldConfig);
    }

    return fieldsBySection;
  }

  private static SObject loadParentRecord(
    Email_Template_Config__c template,
    List<Email_Template_Section__c> sections,
    Map<Id, List<Email_Template_Line__c>> linesBySection,
    Map<Id, List<Email_Template_Field__c>> fieldsBySection,
    Id recordId
  ) {
    Set<String> parentFieldPaths = collectParentFieldPaths(
      template,
      sections,
      linesBySection,
      fieldsBySection
    );
    return GenericDynamicQueryService.queryRecordById(
      template.Parent_Object_API_Name__c,
      recordId,
      parentFieldPaths
    );
  }

  private static String renderSection(
    Email_Template_Section__c section,
    SObject parentRecord,
    String parentObjectApiName,
    Id parentRecordId,
    List<Email_Template_Line__c> lines,
    List<Email_Template_Field__c> fields
  ) {
    if (section.Section_Type__c == SECTION_TYPE_STATIC_TEXT) {
      return renderStaticTextSection(
        section,
        parentRecord,
        parentObjectApiName
      );
    }
    if (section.Section_Type__c == SECTION_TYPE_TEXT_BLOCK) {
      return renderTextBlockSection(
        section,
        parentRecord,
        parentObjectApiName,
        parentRecordId,
        lines,
        fields
      );
    }
    if (section.Section_Type__c == SECTION_TYPE_TABLE) {
      return renderTableSection(
        section,
        parentRecord,
        parentObjectApiName,
        parentRecordId,
        fields
      );
    }

    throw new AuraHandledException(
      'Unsupported section type: ' + section.Section_Type__c
    );
  }

  private static String renderStaticTextSection(
    Email_Template_Section__c section,
    SObject parentRecord,
    String parentObjectApiName
  ) {
    GenericMergeFieldResolver.MergeContext context = buildParentContext(
      parentRecord,
      parentObjectApiName,
      new Map<String, String>(),
      false
    );

    String html = '';
    html += resolveAdminHtml(section.Section_Header__c, context);
    html += preserveLineBreaks(
      resolveAdminHtml(section.Static_Content__c, context)
    );
    html += resolveAdminHtml(section.Section_Footer__c, context);
    return html;
  }

  private static String renderTextBlockSection(
    Email_Template_Section__c section,
    SObject parentRecord,
    String parentObjectApiName,
    Id parentRecordId,
    List<Email_Template_Line__c> lines,
    List<Email_Template_Field__c> fields
  ) {
    assertChildSectionConfigured(section);

    Set<String> childFieldPaths = collectChildFieldPaths(
      section,
      lines,
      fields
    );
    List<SObject> childRecords = GenericDynamicQueryService.queryChildRecords(
      section.Child_Object_API_Name__c,
      section.Parent_Lookup_Field_API_Name__c,
      parentRecordId,
      childFieldPaths,
      section.Sort_Field_API_Name__c,
      section.Sort_Direction__c,
      section.Filter_Logic__c
    );

    GenericMergeFieldResolver.MergeContext parentContext = buildParentContext(
      parentRecord,
      parentObjectApiName,
      new Map<String, String>(),
      false
    );
    String html = '';
    html += resolveAdminHtml(section.Section_Header__c, parentContext);

    Integer optionNumber = getAutoNumberStart(section);
    for (SObject childRecord : childRecords) {
      GenericMergeFieldResolver.MergeContext childContext = buildChildContext(
        parentRecord,
        parentObjectApiName,
        childRecord,
        section.Child_Object_API_Name__c,
        true
      );

      if (
        section.Include_Auto_Number__c == true &&
        !String.isBlank(section.Repeat_Label__c)
      ) {
        html +=
          '<strong>' +
          escapeHtml(section.Repeat_Label__c) +
          ' ' +
          String.valueOf(optionNumber) +
          ':</strong><br/>';
      }

      if (lines != null && !lines.isEmpty()) {
        html += renderLines(lines, childContext);
      } else {
        html += renderFieldFallback(
          section.Child_Object_API_Name__c,
          fields,
          childRecord
        );
      }

      html += '<br/>';
      optionNumber++;
    }

    html += resolveAdminHtml(section.Section_Footer__c, parentContext);
    return html;
  }

  private static String renderTableSection(
    Email_Template_Section__c section,
    SObject parentRecord,
    String parentObjectApiName,
    Id parentRecordId,
    List<Email_Template_Field__c> fields
  ) {
    assertChildSectionConfigured(section);

    Set<String> childFieldPaths = collectChildFieldPaths(
      section,
      new List<Email_Template_Line__c>(),
      fields
    );
    List<SObject> childRecords = GenericDynamicQueryService.queryChildRecords(
      section.Child_Object_API_Name__c,
      section.Parent_Lookup_Field_API_Name__c,
      parentRecordId,
      childFieldPaths,
      section.Sort_Field_API_Name__c,
      section.Sort_Direction__c,
      section.Filter_Logic__c
    );

    GenericMergeFieldResolver.MergeContext parentContext = buildParentContext(
      parentRecord,
      parentObjectApiName,
      new Map<String, String>(),
      false
    );

    String html = '';
    html += resolveAdminHtml(section.Section_Header__c, parentContext);

    if (fields != null && !fields.isEmpty()) {
      html += '<table style="border-collapse:collapse;width:100%;">';
      html += '<thead><tr>';
      for (Email_Template_Field__c fieldConfig : fields) {
        String widthStyle = String.isBlank(fieldConfig.Table_Column_Width__c)
          ? ''
          : 'width:' + escapeHtml(fieldConfig.Table_Column_Width__c) + ';';
        html +=
          '<th style="border:1px solid #dddddd;padding:6px;text-align:left;' +
          widthStyle +
          '">';
        html += escapeHtml(
          getFieldLabel(section.Child_Object_API_Name__c, fieldConfig)
        );
        html += '</th>';
      }
      html += '</tr></thead><tbody>';

      for (SObject childRecord : childRecords) {
        html += '<tr>';
        for (Email_Template_Field__c fieldConfig : fields) {
          html += '<td style="border:1px solid #dddddd;padding:6px;">';
          html += renderFieldValue(
            section.Child_Object_API_Name__c,
            fieldConfig,
            childRecord,
            false
          );
          html += '</td>';
        }
        html += '</tr>';
      }

      html += '</tbody></table>';
    }

    html += resolveAdminHtml(section.Section_Footer__c, parentContext);
    return html;
  }

  private static String renderLines(
    List<Email_Template_Line__c> lines,
    GenericMergeFieldResolver.MergeContext context
  ) {
    String html = '';
    for (Email_Template_Line__c line : lines) {
      String resolvedLine = GenericMergeFieldResolver.resolveTemplate(
        line.Line_Template__c,
        context
      );
      if (
        line.Render_Only_If_Not_Blank__c == true &&
        String.isBlank(stripHtml(resolvedLine))
      ) {
        continue;
      }

      html += GenericMergeFieldResolver.formatValue(
        resolvedLine,
        line.Display_Style__c
      );
      html += '<br/>';
    }
    return html;
  }

  private static String renderFieldFallback(
    String objectApiName,
    List<Email_Template_Field__c> fields,
    SObject record
  ) {
    String html = '';
    if (fields == null) {
      return html;
    }

    for (Email_Template_Field__c fieldConfig : fields) {
      String renderedField = renderFieldValue(
        objectApiName,
        fieldConfig,
        record,
        true
      );
      if (String.isBlank(renderedField)) {
        continue;
      }

      html += renderedField;
      if (fieldConfig.Line_Break_After__c == true) {
        html += '<br/>';
      }
    }

    return html;
  }

  private static String renderFieldValue(
    String objectApiName,
    Email_Template_Field__c fieldConfig,
    SObject record,
    Boolean includeLabel
  ) {
    if (fieldConfig == null || String.isBlank(fieldConfig.Field_API_Name__c)) {
      return '';
    }

    Object rawValue = GenericMergeFieldResolver.resolveValue(
      fieldConfig.Field_API_Name__c,
      buildRecordOnlyContext(record)
    );
    Boolean htmlFormattedField = GenericMergeFieldResolver.isHtmlFormattedField(
      record,
      fieldConfig.Field_API_Name__c
    );
    String formattedValue = htmlFormattedField
      ? String.valueOf(rawValue ?? '')
      : GenericMergeFieldResolver.formatValue(
          rawValue,
          getEffectiveDisplayStyle(fieldConfig)
        );
    if (
      fieldConfig.Render_Only_If_Not_Blank__c == true &&
      String.isBlank(stripHtml(formattedValue))
    ) {
      return '';
    }

    Boolean formattedContainsMarkup =
      htmlFormattedField ||
      fieldConfig.Display_Style__c == 'Bold' ||
      fieldConfig.Display_Style__c == 'Italic' ||
      fieldConfig.Is_Main_Title__c == true;

    if (htmlFormattedField) {
      DceHtmlPolicy.assertSafeUserHtml(formattedValue);
    } else if (!formattedContainsMarkup) {
      formattedValue = escapeHtml(formattedValue);
    }

    String rendered = '';
    if (!String.isBlank(fieldConfig.Prefix_Text__c)) {
      rendered += escapeHtml(fieldConfig.Prefix_Text__c);
    }

    if (includeLabel == true && fieldConfig.Show_Label__c == true) {
      rendered +=
        '<strong>' +
        escapeHtml(getFieldLabel(objectApiName, fieldConfig)) +
        ':</strong> ';
    }

    rendered += formattedValue;

    if (!String.isBlank(fieldConfig.Suffix_Text__c)) {
      rendered += escapeHtml(fieldConfig.Suffix_Text__c);
    }

    return rendered;
  }

  private static Set<String> collectParentFieldPaths(
    Email_Template_Config__c template,
    List<Email_Template_Section__c> sections,
    Map<Id, List<Email_Template_Line__c>> linesBySection,
    Map<Id, List<Email_Template_Field__c>> fieldsBySection
  ) {
    Set<String> parentFieldPaths = new Set<String>();
    collectParentFieldsFromTemplate(
      parentFieldPaths,
      template.Subject_Template__c,
      template.Parent_Object_API_Name__c,
      true
    );
    collectParentFieldsFromTemplate(
      parentFieldPaths,
      template.Body_Template__c,
      template.Parent_Object_API_Name__c,
      true
    );
    collectParentFieldsFromTemplate(
      parentFieldPaths,
      template.Header__c,
      template.Parent_Object_API_Name__c,
      true
    );
    collectParentFieldsFromTemplate(
      parentFieldPaths,
      template.Footer__c,
      template.Parent_Object_API_Name__c,
      true
    );

    for (Email_Template_Section__c section : sections) {
      collectParentFieldsFromTemplate(
        parentFieldPaths,
        section.Section_Header__c,
        template.Parent_Object_API_Name__c,
        true
      );
      collectParentFieldsFromTemplate(
        parentFieldPaths,
        section.Section_Footer__c,
        template.Parent_Object_API_Name__c,
        true
      );

      if (section.Section_Type__c == SECTION_TYPE_STATIC_TEXT) {
        collectParentFieldsFromTemplate(
          parentFieldPaths,
          section.Static_Content__c,
          template.Parent_Object_API_Name__c,
          true
        );
      } else {
        for (
          Email_Template_Line__c line : getLines(linesBySection, section.Id)
        ) {
          collectParentFieldsFromTemplate(
            parentFieldPaths,
            line.Line_Template__c,
            template.Parent_Object_API_Name__c,
            false
          );
        }
      }
    }

    return parentFieldPaths;
  }

  private static void collectParentFieldsFromTemplate(
    Set<String> parentFieldPaths,
    String templateText,
    String parentObjectApiName,
    Boolean includeUnqualified
  ) {
    for (
      String placeholder : GenericMergeFieldResolver.extractPlaceholders(
        templateText
      )
    ) {
      if (
        placeholder.startsWith('Section.') ||
        placeholder.startsWith('Child.') ||
        placeholder.startsWith('Sender.') ||
        placeholder.startsWith('Organization.')
      ) {
        continue;
      }

      if (placeholder == 'Owner.Address') {
        parentFieldPaths.add('Owner.Street');
        parentFieldPaths.add('Owner.City');
        parentFieldPaths.add('Owner.State');
        parentFieldPaths.add('Owner.PostalCode');
        parentFieldPaths.add('Owner.Country');
        continue;
      }

      if (placeholder.startsWith('Parent.')) {
        String fieldPath = stripFirstSegment(placeholder);
        if (!String.isBlank(fieldPath)) {
          parentFieldPaths.add(fieldPath);
        }
        continue;
      }

      if (
        !String.isBlank(parentObjectApiName) &&
        placeholder.startsWith(parentObjectApiName + '.')
      ) {
        String fieldPath = stripFirstSegment(placeholder);
        if (!String.isBlank(fieldPath)) {
          parentFieldPaths.add(fieldPath);
        }
        continue;
      }

      if (includeUnqualified == true) {
        parentFieldPaths.add(placeholder);
      }
    }
  }

  private static Set<String> collectChildFieldPaths(
    Email_Template_Section__c section,
    List<Email_Template_Line__c> lines,
    List<Email_Template_Field__c> fields
  ) {
    Set<String> childFieldPaths = new Set<String>();
    if (lines != null) {
      for (Email_Template_Line__c line : lines) {
        childFieldPaths.addAll(
          GenericMergeFieldResolver.extractChildFieldPaths(
            line.Line_Template__c,
            section.Child_Object_API_Name__c,
            new Set<String>()
          )
        );
      }
    }

    if (fields != null) {
      for (Email_Template_Field__c fieldConfig : fields) {
        if (!String.isBlank(fieldConfig.Field_API_Name__c)) {
          childFieldPaths.add(fieldConfig.Field_API_Name__c);
        }
      }
    }

    if (!String.isBlank(section.Sort_Field_API_Name__c)) {
      childFieldPaths.add(section.Sort_Field_API_Name__c);
    }

    childFieldPaths.addAll(
      extractSimpleFilterFieldNames(section.Filter_Logic__c)
    );
    return childFieldPaths;
  }

  private static Set<String> extractSimpleFilterFieldNames(String filterLogic) {
    Set<String> fieldNames = new Set<String>();
    if (String.isBlank(filterLogic)) {
      return fieldNames;
    }

    for (String expression : filterLogic.split('(?i)\\s+AND\\s+')) {
      Integer equalsIndex = expression.indexOf('=');
      if (equalsIndex > 0) {
        String fieldName = expression.substring(0, equalsIndex).trim();
        if (Pattern.matches('^[A-Za-z_][A-Za-z0-9_]*(__(c|r))?$', fieldName)) {
          fieldNames.add(fieldName);
        }
      }
    }

    return fieldNames;
  }

  private static void assertChildSectionConfigured(
    Email_Template_Section__c section
  ) {
    if (String.isBlank(section.Child_Object_API_Name__c)) {
      throw new AuraHandledException(
        'Template section is misconfigured: missing child object.'
      );
    }
    if (String.isBlank(section.Parent_Lookup_Field_API_Name__c)) {
      throw new AuraHandledException(
        'Template section is misconfigured: missing parent lookup field.'
      );
    }
  }

  private static String getFieldLabel(
    String objectApiName,
    Email_Template_Field__c fieldConfig
  ) {
    if (!String.isBlank(fieldConfig.Label_Override__c)) {
      return fieldConfig.Label_Override__c;
    }

    try {
      GenericDynamicQueryService.assertValidField(
        objectApiName,
        fieldConfig.Field_API_Name__c
      );
      Schema.DescribeSObjectResult objectDescribe = Schema.getGlobalDescribe()
        .get(objectApiName)
        .getDescribe();
      return objectDescribe.fields.getMap()
        .get(fieldConfig.Field_API_Name__c)
        .getDescribe()
        .getLabel();
    } catch (Exception ignoredException) {
      return fieldConfig.Field_API_Name__c;
    }
  }

  private static String getEffectiveDisplayStyle(
    Email_Template_Field__c fieldConfig
  ) {
    if (fieldConfig.Is_Main_Title__c == true) {
      return 'Bold';
    }
    return fieldConfig.Display_Style__c;
  }

  private static GenericMergeFieldResolver.MergeContext buildParentContext(
    SObject parentRecord,
    String parentObjectApiName,
    Map<String, String> sectionHtmlByKey,
    Boolean escapeHtml
  ) {
    GenericMergeFieldResolver.MergeContext context = new GenericMergeFieldResolver.MergeContext();
    context.parentRecord = parentRecord;
    context.parentObjectApiName = parentObjectApiName;
    context.sectionHtmlByKey = sectionHtmlByKey == null
      ? new Map<String, String>()
      : sectionHtmlByKey;
    context.aliasRecords = loadStandardMergeAliases();
    context.aliasValues = loadStandardMergeAliasValues(parentRecord);
    context.escapeHtml = escapeHtml;
    return context;
  }

  private static Map<String, SObject> loadStandardMergeAliases() {
    if (standardMergeAliases != null) {
      return standardMergeAliases;
    }

    standardMergeAliases = new Map<String, SObject>();
    Id currentUserId = UserInfo.getUserId();
    List<User> currentUsers = [
      SELECT Id, Name, FirstName, LastName, Email, Phone, MobilePhone,
        Street, City, State, PostalCode, Country
      FROM User
      WHERE Id = :currentUserId
      WITH USER_MODE
      LIMIT 1
    ];
    if (!currentUsers.isEmpty()) {
      standardMergeAliases.put('Sender', currentUsers[0]);
    }

    List<Organization> organizations = [
      SELECT Id, Name, Street, City, State, PostalCode, Country
      FROM Organization
      WITH USER_MODE
      LIMIT 1
    ];
    if (!organizations.isEmpty()) {
      standardMergeAliases.put('Organization', organizations[0]);
    }
    return standardMergeAliases;
  }

  private static Map<String, String> loadStandardMergeAliasValues(SObject parentRecord) {
    Map<String, String> values = new Map<String, String>();
    values.put('Sender.Address', formatAddress(standardMergeAliases.get('Sender')));
    values.put('Organization.Address', formatAddress(standardMergeAliases.get('Organization')));
    SObject ownerRecord;
    try {
      ownerRecord = parentRecord == null ? null : parentRecord.getSObject('Owner');
    } catch (Exception ignoredException) {
      ownerRecord = null;
    }
    values.put('Owner.Address', formatAddress(ownerRecord));
    return values;
  }

  private static String formatAddress(SObject record) {
    if (record == null) {
      return '';
    }
    List<String> parts = new List<String>();
    Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
    for (String fieldName : new List<String>{ 'Street', 'City', 'State', 'PostalCode', 'Country' }) {
      Object value = populatedFields.get(fieldName);
      if (value != null && !String.isBlank(String.valueOf(value))) {
        parts.add(String.valueOf(value));
      }
    }
    return String.join(parts, ', ');
  }

  private static GenericMergeFieldResolver.MergeContext buildChildContext(
    SObject parentRecord,
    String parentObjectApiName,
    SObject childRecord,
    String childObjectApiName,
    Boolean escapeHtml
  ) {
    GenericMergeFieldResolver.MergeContext context = buildParentContext(
      parentRecord,
      parentObjectApiName,
      new Map<String, String>(),
      escapeHtml
    );
    context.childRecord = childRecord;
    context.childObjectApiName = childObjectApiName;
    context.renderHtmlFormattedFields = escapeHtml;
    return context;
  }

  private static GenericMergeFieldResolver.MergeContext buildRecordOnlyContext(
    SObject record
  ) {
    GenericMergeFieldResolver.MergeContext context = new GenericMergeFieldResolver.MergeContext();
    context.parentRecord = record;
    context.escapeHtml = false;
    return context;
  }

  private static String resolveAdminHtml(
    String templateText,
    GenericMergeFieldResolver.MergeContext context
  ) {
    if (String.isBlank(templateText)) {
      return '';
    }
    return GenericMergeFieldResolver.resolveTemplate(templateText, context);
  }

  private static String wrapWithBranding(
    DceTemplateContentService.ContentBundle content,
    String generatedBody,
    GenericMergeFieldResolver.MergeContext context
  ) {
    String finalHtml = '';
    if (!String.isBlank(content.headerHtml)) {
      finalHtml += GenericMergeFieldResolver.resolveTemplate(
        content.headerHtml,
        context
      );
    }
    finalHtml += generatedBody == null ? '' : generatedBody;
    if (!String.isBlank(content.footerHtml)) {
      finalHtml += GenericMergeFieldResolver.resolveTemplate(
        content.footerHtml,
        context
      );
    }
    return finalHtml;
  }

  private static String preserveLineBreaks(String input) {
    if (input == null) {
      return '';
    }
    return input.replace('\r\n', '\n')
      .replace('\r', '\n')
      .replace('\n', '<br/>');
  }

  private static String escapeHtml(String input) {
    if (input == null) {
      return '';
    }

    String escaped = input.replace('&', '&amp;');
    escaped = escaped.replace('<', '&lt;');
    escaped = escaped.replace('>', '&gt;');
    escaped = escaped.replace('"', '&quot;');
    escaped = escaped.replace('\'', '&#39;');
    return escaped;
  }

  private static String stripHtml(String input) {
    if (input == null) {
      return '';
    }

    String plainText = input.replaceAll('(?i)<br\\s*/?>', '\n');
    plainText = plainText.replaceAll('<[^>]+>', '');
    plainText = plainText.replace('&nbsp;', ' ');
    plainText = plainText.replace('&amp;', '&');
    plainText = plainText.replace('&lt;', '<');
    plainText = plainText.replace('&gt;', '>');
    plainText = plainText.replace('&quot;', '"');
    plainText = plainText.replace('&#39;', '\'');
    return plainText;
  }

  private static Set<Id> getSectionIds(
    List<Email_Template_Section__c> sections
  ) {
    Set<Id> sectionIds = new Set<Id>();
    for (Email_Template_Section__c section : sections) {
      sectionIds.add(section.Id);
    }
    return sectionIds;
  }

  private static List<Email_Template_Line__c> getLines(
    Map<Id, List<Email_Template_Line__c>> linesBySection,
    Id sectionId
  ) {
    if (linesBySection != null && linesBySection.containsKey(sectionId)) {
      return linesBySection.get(sectionId);
    }
    return new List<Email_Template_Line__c>();
  }

  private static List<Email_Template_Field__c> getFields(
    Map<Id, List<Email_Template_Field__c>> fieldsBySection,
    Id sectionId
  ) {
    if (fieldsBySection != null && fieldsBySection.containsKey(sectionId)) {
      return fieldsBySection.get(sectionId);
    }
    return new List<Email_Template_Field__c>();
  }

  private static Integer getAutoNumberStart(Email_Template_Section__c section) {
    if (section.Auto_Number_Start__c == null) {
      return 1;
    }
    return section.Auto_Number_Start__c.intValue();
  }

  private static String stripFirstSegment(String fieldPath) {
    if (String.isBlank(fieldPath) || !fieldPath.contains('.')) {
      return null;
    }
    return fieldPath.substring(fieldPath.indexOf('.') + 1);
  }
}
