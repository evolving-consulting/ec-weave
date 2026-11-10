/**
 * Generic merge field resolver for the Dynamic Communication Engine.
 * This utility parses and resolves template placeholders without querying data.
 */
public with sharing class GenericMergeFieldResolver {
  private static final String PLACEHOLDER_REGEX = '\\{\\{\\s*([A-Za-z_][A-Za-z0-9_]*(__(c|r))?(\\.[A-Za-z_][A-Za-z0-9_]*(__(c|r))?){0,3})\\s*\\}\\}';
  private static final String FIELD_PATH_REGEX = '^[A-Za-z_][A-Za-z0-9_]*(__(c|r))?(\\.[A-Za-z_][A-Za-z0-9_]*(__(c|r))?){0,3}$';

  public class MergeContext {
    public SObject parentRecord;
    public String parentObjectApiName;
    public SObject childRecord;
    public String childObjectApiName;
    public Map<String, SObject> aliasRecords;
    public Map<String, String> aliasValues;
    public Map<String, String> sectionHtmlByKey;
    public Boolean escapeHtml;
    public Boolean renderHtmlFormattedFields;

    public MergeContext() {
      this.aliasRecords = new Map<String, SObject>();
      this.aliasValues = new Map<String, String>();
      this.sectionHtmlByKey = new Map<String, String>();
      this.escapeHtml = true;
      this.renderHtmlFormattedFields = false;
    }
  }

  public static Set<String> extractPlaceholders(String template) {
    Set<String> placeholders = new Set<String>();
    if (isBlank(template)) {
      return placeholders;
    }

    Matcher matcher = Pattern.compile(PLACEHOLDER_REGEX).matcher(template);
    while (matcher.find()) {
      placeholders.add(matcher.group(1).trim());
    }

    return placeholders;
  }

  public static Set<String> extractParentFieldPaths(
    String template,
    String parentObjectApiName,
    Set<String> knownAliases
  ) {
    Set<String> fieldPaths = new Set<String>();
    Set<String> aliases = normalizeAliases(knownAliases);

    for (String placeholderKey : extractPlaceholders(template)) {
      if (
        !isSafeFieldPath(placeholderKey) || isSectionPlaceholder(placeholderKey)
      ) {
        continue;
      }

      List<String> segments = placeholderKey.split('\\.');
      String firstSegment = segments[0];

      if (aliases.contains(firstSegment) || firstSegment == 'Child') {
        continue;
      }

      if (firstSegment == 'Parent') {
        String strippedPath = stripFirstSegment(placeholderKey);
        if (!isBlank(strippedPath)) {
          fieldPaths.add(strippedPath);
        }
        continue;
      }

      if (
        !isBlank(parentObjectApiName) && firstSegment == parentObjectApiName
      ) {
        String strippedPath = stripFirstSegment(placeholderKey);
        if (!isBlank(strippedPath)) {
          fieldPaths.add(strippedPath);
        }
        continue;
      }

      fieldPaths.add(placeholderKey);
    }

    return fieldPaths;
  }

  public static Set<String> extractChildFieldPaths(
    String template,
    String childObjectApiName,
    Set<String> knownAliases
  ) {
    Set<String> fieldPaths = new Set<String>();
    Set<String> aliases = normalizeAliases(knownAliases);

    for (String placeholderKey : extractPlaceholders(template)) {
      if (
        !isSafeFieldPath(placeholderKey) || isSectionPlaceholder(placeholderKey)
      ) {
        continue;
      }

      List<String> segments = placeholderKey.split('\\.');
      String firstSegment = segments[0];

      if (firstSegment == 'Parent' || aliases.contains(firstSegment)) {
        continue;
      }

      if (firstSegment == 'Child') {
        String strippedPath = stripFirstSegment(placeholderKey);
        if (!isBlank(strippedPath)) {
          fieldPaths.add(strippedPath);
        }
        continue;
      }

      if (!isBlank(childObjectApiName) && firstSegment == childObjectApiName) {
        String strippedPath = stripFirstSegment(placeholderKey);
        if (!isBlank(strippedPath)) {
          fieldPaths.add(strippedPath);
        }
        continue;
      }

      if (segments.size() == 1 || !aliases.contains(firstSegment)) {
        fieldPaths.add(placeholderKey);
      }
    }

    return fieldPaths;
  }

  public static String resolveTemplate(String template, MergeContext context) {
    if (isBlank(template)) {
      return '';
    }

    MergeContext safeContext = normalizeContext(context);
    Matcher matcher = Pattern.compile(PLACEHOLDER_REGEX).matcher(template);
    String resolvedTemplate = '';
    Integer lastEnd = 0;

    while (matcher.find()) {
      resolvedTemplate += template.substring(lastEnd, matcher.start());

      String placeholderKey = matcher.group(1).trim();
      Boolean sectionPlaceholder = isSectionPlaceholder(placeholderKey);
      ResolvedMergeValue resolvedMergeValue = resolveMergeValue(
        placeholderKey,
        safeContext
      );
      String resolvedValue = formatValue(
        resolvedMergeValue.value,
        resolvedMergeValue.fieldDescribe
      );
      resolvedValue = prepareResolvedValueForOutput(
        resolvedValue,
        safeContext.escapeHtml,
        sectionPlaceholder,
        safeContext.renderHtmlFormattedFields == true &&
        isHtmlFormatted(resolvedMergeValue.fieldDescribe)
      );

      resolvedTemplate += resolvedValue;
      lastEnd = matcher.end();
    }

    resolvedTemplate += template.substring(lastEnd);
    return resolvedTemplate;
  }

  public static Object resolveValue(
    String placeholderKey,
    MergeContext context
  ) {
    if (isBlank(placeholderKey) || !isSafeFieldPath(placeholderKey)) {
      return null;
    }

    MergeContext safeContext = normalizeContext(context);
    List<String> segments = placeholderKey.split('\\.');
    String firstSegment = segments[0];

    if (firstSegment == 'Section') {
      String sectionKey = stripFirstSegment(placeholderKey);
      if (isBlank(sectionKey)) {
        return null;
      }
      return safeContext.sectionHtmlByKey.get(sectionKey);
    }

    if (safeContext.aliasValues.containsKey(placeholderKey)) {
      return safeContext.aliasValues.get(placeholderKey);
    }

    if (firstSegment == 'Parent') {
      return getValueByPath(
        safeContext.parentRecord,
        stripFirstSegment(placeholderKey)
      );
    }

    if (firstSegment == 'Child') {
      return getValueByPath(
        safeContext.childRecord,
        stripFirstSegment(placeholderKey)
      );
    }

    if (safeContext.aliasRecords.containsKey(firstSegment)) {
      return getValueByPath(
        safeContext.aliasRecords.get(firstSegment),
        stripFirstSegment(placeholderKey)
      );
    }

    if (
      !isBlank(safeContext.parentObjectApiName) &&
      firstSegment == safeContext.parentObjectApiName
    ) {
      return getValueByPath(
        safeContext.parentRecord,
        stripFirstSegment(placeholderKey)
      );
    }

    if (
      !isBlank(safeContext.childObjectApiName) &&
      firstSegment == safeContext.childObjectApiName
    ) {
      return getValueByPath(
        safeContext.childRecord,
        stripFirstSegment(placeholderKey)
      );
    }

    if (safeContext.childRecord != null) {
      Object childValue = getValueByPath(
        safeContext.childRecord,
        placeholderKey
      );
      if (childValue != null) {
        return childValue;
      }
    }

    return getValueByPath(safeContext.parentRecord, placeholderKey);
  }

  /**
   * Determines whether the final field in a record path stores Salesforce rich text.
   * @param record Record that owns the field path
   * @param fieldPath Direct or relationship field path
   * @return true when the final field is HTML-formatted
   */
  public static Boolean isHtmlFormattedField(SObject record, String fieldPath) {
    ResolvedMergeValue resolvedValue = getValueByPathWithDescribe(
      record,
      fieldPath
    );
    return isHtmlFormatted(resolvedValue.fieldDescribe);
  }

  private static ResolvedMergeValue resolveMergeValue(
    String placeholderKey,
    MergeContext context
  ) {
    ResolvedMergeValue blankValue = new ResolvedMergeValue(null, null);
    if (isBlank(placeholderKey) || !isSafeFieldPath(placeholderKey)) {
      return blankValue;
    }

    MergeContext safeContext = normalizeContext(context);
    List<String> segments = placeholderKey.split('\\.');
    String firstSegment = segments[0];

    if (firstSegment == 'Section') {
      String sectionKey = stripFirstSegment(placeholderKey);
      if (isBlank(sectionKey)) {
        return blankValue;
      }
      return new ResolvedMergeValue(
        safeContext.sectionHtmlByKey.get(sectionKey),
        null
      );
    }

    if (safeContext.aliasValues.containsKey(placeholderKey)) {
      return new ResolvedMergeValue(
        safeContext.aliasValues.get(placeholderKey),
        null
      );
    }

    if (firstSegment == 'Parent') {
      return getValueByPathWithDescribe(
        safeContext.parentRecord,
        stripFirstSegment(placeholderKey)
      );
    }

    if (firstSegment == 'Child') {
      return getValueByPathWithDescribe(
        safeContext.childRecord,
        stripFirstSegment(placeholderKey)
      );
    }

    if (safeContext.aliasRecords.containsKey(firstSegment)) {
      return getValueByPathWithDescribe(
        safeContext.aliasRecords.get(firstSegment),
        stripFirstSegment(placeholderKey)
      );
    }

    if (
      !isBlank(safeContext.parentObjectApiName) &&
      firstSegment == safeContext.parentObjectApiName
    ) {
      return getValueByPathWithDescribe(
        safeContext.parentRecord,
        stripFirstSegment(placeholderKey)
      );
    }

    if (
      !isBlank(safeContext.childObjectApiName) &&
      firstSegment == safeContext.childObjectApiName
    ) {
      return getValueByPathWithDescribe(
        safeContext.childRecord,
        stripFirstSegment(placeholderKey)
      );
    }

    if (safeContext.childRecord != null) {
      ResolvedMergeValue childValue = getValueByPathWithDescribe(
        safeContext.childRecord,
        placeholderKey
      );
      if (childValue.value != null) {
        return childValue;
      }
    }

    return getValueByPathWithDescribe(safeContext.parentRecord, placeholderKey);
  }

  public static String formatValue(Object value, String displayStyle) {
    if (value == null) {
      return '';
    }

    String normalizedStyle = isBlank(displayStyle)
      ? 'Normal'
      : displayStyle.trim();
    String formattedValue;

    if (normalizedStyle == 'Currency') {
      formattedValue = formatCurrency(value);
    } else if (normalizedStyle == 'Percent') {
      formattedValue = formatPercent(value);
    } else if (normalizedStyle == 'Date') {
      formattedValue = formatDate(value);
    } else if (normalizedStyle == 'DateTime') {
      formattedValue = formatDateTime(value);
    } else if (normalizedStyle == 'Number') {
      formattedValue = formatNumber(value);
    } else {
      formattedValue = String.valueOf(value);
    }

    if (isBlank(formattedValue)) {
      return '';
    }

    if (normalizedStyle == 'Bold') {
      return '<strong>' + escapeHtml(formattedValue) + '</strong>';
    }
    if (normalizedStyle == 'Italic') {
      return '<em>' + escapeHtml(formattedValue) + '</em>';
    }

    return formattedValue;
  }

  private static Object getValueByPath(SObject record, String fieldPath) {
    return getValueByPathWithDescribe(record, fieldPath).value;
  }

  private static ResolvedMergeValue getValueByPathWithDescribe(
    SObject record,
    String fieldPath
  ) {
    if (record == null || isBlank(fieldPath) || !isSafeFieldPath(fieldPath)) {
      return new ResolvedMergeValue(null, null);
    }

    List<String> segments = fieldPath.split('\\.');
    SObject currentRecord = record;

    for (Integer i = 0; i < segments.size(); i++) {
      String segment = segments[i];
      Boolean finalSegment = i == segments.size() - 1;

      try {
        if (finalSegment) {
          Schema.DescribeFieldResult fieldDescribe = getFieldDescribe(
            currentRecord,
            segment
          );
          return new ResolvedMergeValue(
            currentRecord.get(segment),
            fieldDescribe
          );
        }

        currentRecord = currentRecord.getSObject(segment);
        if (currentRecord == null) {
          return new ResolvedMergeValue(null, null);
        }
      } catch (Exception ignoredException) {
        return new ResolvedMergeValue(null, null);
      }
    }

    return new ResolvedMergeValue(null, null);
  }

  private static Schema.DescribeFieldResult getFieldDescribe(
    SObject record,
    String fieldApiName
  ) {
    if (record == null || isBlank(fieldApiName)) {
      return null;
    }

    Map<String, Schema.SObjectField> fields = record.getSObjectType()
      .getDescribe()
      .fields.getMap();
    if (!fields.containsKey(fieldApiName)) {
      return null;
    }

    return fields.get(fieldApiName).getDescribe();
  }

  private static String formatValue(
    Object value,
    Schema.DescribeFieldResult fieldDescribe
  ) {
    if (value == null) {
      return '';
    }
    if (fieldDescribe == null) {
      return String.valueOf(value);
    }

    Schema.DisplayType fieldType = fieldDescribe.getType();
    if (fieldType == Schema.DisplayType.Date) {
      return formatDate(value);
    }
    if (fieldType == Schema.DisplayType.DateTime) {
      return formatDateTime(value);
    }
    if (fieldType == Schema.DisplayType.Currency) {
      return formatCurrency(value);
    }
    if (fieldType == Schema.DisplayType.Percent) {
      return formatPercent(value);
    }
    if (
      fieldType == Schema.DisplayType.Double ||
      fieldType == Schema.DisplayType.Integer
    ) {
      return formatNumber(value);
    }
    if (fieldType == Schema.DisplayType.Boolean) {
      return ((Boolean) value) ? 'Yes' : 'No';
    }
    if (fieldType == Schema.DisplayType.MultiPicklist) {
      return String.valueOf(value).replace(';', ', ');
    }

    return String.valueOf(value);
  }

  private static String formatCurrency(Object value) {
    Decimal decimalValue = toDecimal(value);
    if (decimalValue == null) {
      return String.valueOf(value);
    }
    return 'US$' + formatDecimalWithScale(decimalValue, 2);
  }

  private static String formatPercent(Object value) {
    Decimal decimalValue = toDecimal(value);
    if (decimalValue == null) {
      return String.valueOf(value);
    }

    Decimal percentValue = decimalValue;
    if (decimalValue.abs() <= 1) {
      percentValue = decimalValue * 100;
    }

    return formatDecimalCompact(percentValue) + '%';
  }

  private static String formatDecimalWithScale(Decimal value, Integer scale) {
    String formattedValue = value.setScale(scale).format();
    if (!formattedValue.contains('.')) {
      formattedValue += '.';
    }

    Integer decimalPlaces =
      formattedValue.length() -
      formattedValue.indexOf('.') -
      1;
    while (decimalPlaces < scale) {
      formattedValue += '0';
      decimalPlaces++;
    }

    return formattedValue;
  }

  private static String formatDate(Object value) {
    if (value instanceof Date) {
      return ((Date) value).format();
    } else if (value instanceof Datetime) {
      return ((Datetime) value).date().format();
    } else {
      return String.valueOf(value);
    }
  }

  private static String formatDateTime(Object value) {
    if (value instanceof Datetime) {
      return ((Datetime) value).format();
    }
    if (value instanceof Date) {
      return formatDate(value);
    }
    return String.valueOf(value);
  }

  private static String formatNumber(Object value) {
    Decimal decimalValue = toDecimal(value);
    if (decimalValue == null) {
      return String.valueOf(value);
    }
    return decimalValue.format();
  }

  private static String formatDecimalCompact(Decimal value) {
    if (value == null) {
      return '';
    }

    Decimal scaledValue = value.setScale(2);
    if (scaledValue == scaledValue.setScale(0)) {
      return scaledValue.setScale(0).format();
    }

    String formattedValue = scaledValue.format();
    while (formattedValue.endsWith('0')) {
      formattedValue = formattedValue.substring(0, formattedValue.length() - 1);
    }
    if (formattedValue.endsWith('.')) {
      formattedValue = formattedValue.substring(0, formattedValue.length() - 1);
    }
    return formattedValue;
  }

  private static Decimal toDecimal(Object value) {
    if (value == null) {
      return null;
    }

    try {
      if (value instanceof Decimal) {
        return (Decimal) value;
      }
      if (value instanceof Integer) {
        return Decimal.valueOf(String.valueOf(value));
      }
      if (value instanceof Long) {
        return Decimal.valueOf(String.valueOf(value));
      }
      if (value instanceof Double) {
        return Decimal.valueOf(String.valueOf(value));
      }
      return Decimal.valueOf(String.valueOf(value));
    } catch (Exception ignoredException) {
      return null;
    }
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

  @TestVisible
  private static String prepareResolvedValueForOutput(
    String resolvedValue,
    Boolean escapeHtmlValue,
    Boolean sectionPlaceholder,
    Boolean renderHtmlFormattedField
  ) {
    String safeValue = resolvedValue ?? '';
    if (sectionPlaceholder == true) {
      return safeValue;
    }
    if (renderHtmlFormattedField == true) {
      return DceHtmlPolicy.sanitizeRichTextHtml(safeValue);
    }
    return escapeHtmlValue == true ? escapeHtml(safeValue) : safeValue;
  }

  private static Boolean isHtmlFormatted(
    Schema.DescribeFieldResult fieldDescribe
  ) {
    return fieldDescribe != null && fieldDescribe.isHtmlFormatted();
  }

  private static Boolean isSectionPlaceholder(String placeholderKey) {
    return !isBlank(placeholderKey) && placeholderKey.startsWith('Section.');
  }

  private static Boolean isSafeFieldPath(String fieldPath) {
    return !isBlank(fieldPath) &&
      Pattern.matches(FIELD_PATH_REGEX, fieldPath.trim());
  }

  private static Set<String> normalizeAliases(Set<String> knownAliases) {
    Set<String> aliases = new Set<String>();
    if (knownAliases == null) {
      return aliases;
    }

    for (String aliasName : knownAliases) {
      if (!isBlank(aliasName)) {
        aliases.add(aliasName.trim());
      }
    }

    return aliases;
  }

  private static MergeContext normalizeContext(MergeContext context) {
    MergeContext safeContext = context == null ? new MergeContext() : context;
    if (safeContext.aliasRecords == null) {
      safeContext.aliasRecords = new Map<String, SObject>();
    }
    if (safeContext.aliasValues == null) {
      safeContext.aliasValues = new Map<String, String>();
    }
    if (safeContext.sectionHtmlByKey == null) {
      safeContext.sectionHtmlByKey = new Map<String, String>();
    }
    if (safeContext.escapeHtml == null) {
      safeContext.escapeHtml = true;
    }
    if (safeContext.renderHtmlFormattedFields == null) {
      safeContext.renderHtmlFormattedFields = false;
    }
    return safeContext;
  }

  private static String stripFirstSegment(String fieldPath) {
    if (isBlank(fieldPath) || !fieldPath.contains('.')) {
      return null;
    }
    return fieldPath.substring(fieldPath.indexOf('.') + 1);
  }

  private static Boolean isBlank(String value) {
    return value == null || value.trim().length() == 0;
  }

  private class ResolvedMergeValue {
    private Object value;
    private Schema.DescribeFieldResult fieldDescribe;

    private ResolvedMergeValue(
      Object value,
      Schema.DescribeFieldResult fieldDescribe
    ) {
      this.value = value;
      this.fieldDescribe = fieldDescribe;
    }
  }
}
