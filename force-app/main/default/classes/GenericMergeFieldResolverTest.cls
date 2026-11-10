@IsTest
private class GenericMergeFieldResolverTest {
  @IsTest
  static void extractsPlaceholdersAndResolvesContextValues() {
    Account account = new Account(Name = 'Acme & Sons');
    Account child = new Account(Name = 'Child Account');
    Contact aliasContact = new Contact(
      FirstName = 'Grace',
      LastName = 'Hopper'
    );

    GenericMergeFieldResolver.MergeContext context = new GenericMergeFieldResolver.MergeContext();
    context.parentRecord = account;
    context.parentObjectApiName = 'Account';
    context.childRecord = child;
    context.childObjectApiName = 'Account';
    context.aliasRecords.put('PrimaryContact', aliasContact);
    context.sectionHtmlByKey.put('TestSection', '<p>Section HTML</p>');
    context.escapeHtml = true;

    Set<String> placeholders = GenericMergeFieldResolver.extractPlaceholders(
      'Hello {{PrimaryContact.FirstName}}, {{Parent.Name}}, {{Section.TestSection}}'
    );

    System.assert(placeholders.contains('PrimaryContact.FirstName'));
    System.assert(placeholders.contains('Parent.Name'));
    System.assert(placeholders.contains('Section.TestSection'));

    String resolved = GenericMergeFieldResolver.resolveTemplate(
      '{{Name}} {{Parent.Name}} {{PrimaryContact.FirstName}} {{Section.TestSection}} {{Missing__c}}',
      context
    );

    System.assert(resolved.contains('Child Account'));
    System.assert(resolved.contains('Acme &amp; Sons'));
    System.assert(resolved.contains('Grace'));
    System.assert(resolved.contains('<p>Section HTML</p>'));
  }

  @IsTest
  static void extractsParentAndChildFieldPaths() {
    Set<String> parentFields = GenericMergeFieldResolver.extractParentFieldPaths(
      '{{Name}} {{Parent.Owner.Name}} {{Account.Name}} {{Section.X}} {{PrimaryContact.Email}}',
      'Account',
      new Set<String>{ 'PrimaryContact' }
    );
    System.assert(parentFields.contains('Name'));
    System.assert(parentFields.contains('Owner.Name'));
    System.assertEquals(false, parentFields.contains('PrimaryContact.Email'));

    Set<String> childFields = GenericMergeFieldResolver.extractChildFieldPaths(
      '{{FirstName}} {{Child.Email}} {{Parent.Name}} {{PrimaryContact.Email}}',
      'Contact',
      new Set<String>{ 'PrimaryContact' }
    );
    System.assert(childFields.contains('FirstName'));
    System.assert(childFields.contains('Email'));
    System.assertEquals(false, childFields.contains('Parent.Name'));
  }

  @IsTest
  static void formatsValuesAndEscapesHtml() {
    System.assertEquals(
      'US$3,011.00',
      GenericMergeFieldResolver.formatValue(3011, 'Currency')
    );
    System.assertEquals(
      '10%',
      GenericMergeFieldResolver.formatValue(0.10, 'Percent')
    );
    System.assert(
      !GenericMergeFieldResolver.formatValue(
          Date.newInstance(2025, 12, 28),
          'Date'
        )
        .contains('00:00:00')
    );
    System.assertEquals(
      '3,011',
      GenericMergeFieldResolver.formatValue(3011, 'Number')
    );
    System.assertEquals(
      '<strong>Value</strong>',
      GenericMergeFieldResolver.formatValue('Value', 'Bold')
    );
    System.assertEquals(
      '<em>Value</em>',
      GenericMergeFieldResolver.formatValue('Value', 'Italic')
    );
    System.assertEquals(
      '',
      GenericMergeFieldResolver.formatValue(null, 'Normal')
    );
  }

  @IsTest
  static void resolvesFieldValuesUsingSalesforceFieldTypes() {
    Account account = new Account(
      Name = 'Typed Account',
      AnnualRevenue = 3011,
      NumberOfEmployees = 3011
    );
    insert account;
    account = [
      SELECT Name, AnnualRevenue, NumberOfEmployees, CreatedDate
      FROM Account
      WHERE Id = :account.Id
    ];

    GenericMergeFieldResolver.MergeContext accountContext = new GenericMergeFieldResolver.MergeContext();
    accountContext.parentRecord = account;
    accountContext.parentObjectApiName = 'Account';
    accountContext.escapeHtml = true;

    String accountOutput = GenericMergeFieldResolver.resolveTemplate(
      '{{AnnualRevenue}}|{{NumberOfEmployees}}|{{CreatedDate}}',
      accountContext
    );
    System.assert(accountOutput.contains('US$3,011.00'), accountOutput);
    System.assert(accountOutput.contains('3,011'), accountOutput);
    System.assert(!accountOutput.contains('00:00:00'), accountOutput);

    Contact contact = new Contact(
      LastName = 'Date Tester',
      Birthdate = Date.newInstance(2027, 5, 2)
    );
    insert contact;
    contact = [
      SELECT Birthdate
      FROM Contact
      WHERE Id = :contact.Id
    ];

    GenericMergeFieldResolver.MergeContext contactContext = new GenericMergeFieldResolver.MergeContext();
    contactContext.parentRecord = contact;
    contactContext.parentObjectApiName = 'Contact';

    String dateOutput = GenericMergeFieldResolver.resolveTemplate(
      '{{Birthdate}}',
      contactContext
    );
    System.assert(!dateOutput.contains('00:00:00'), dateOutput);

    Opportunity opportunity = new Opportunity(
      Name = 'Percent Tester',
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(10),
      Probability = 7
    );
    insert opportunity;
    opportunity = [
      SELECT Probability
      FROM Opportunity
      WHERE Id = :opportunity.Id
    ];

    GenericMergeFieldResolver.MergeContext opportunityContext = new GenericMergeFieldResolver.MergeContext();
    opportunityContext.parentRecord = opportunity;
    opportunityContext.parentObjectApiName = 'Opportunity';

    System.assertEquals(
      '7%',
      GenericMergeFieldResolver.resolveTemplate(
        '{{Probability}}',
        opportunityContext
      )
    );
  }

  @IsTest
  static void rendersHtmlFormattedValueWhenBodyRenderingAllowsHtmlFields() {
    String richTextValue = '<p><strong>Project notes</strong></p>';

    Test.startTest();
    String renderedValue = GenericMergeFieldResolver.prepareResolvedValueForOutput(
      richTextValue,
      true,
      false,
      true
    );
    Test.stopTest();

    Assert.areEqual(
      richTextValue,
      renderedValue,
      'Safe rich text must remain HTML in an HTML body.'
    );
  }

  @IsTest
  static void escapesHtmlFormattedValueWhenHtmlFieldsAreNotAllowed() {
    String richTextValue = '<p>Project notes</p>';

    Test.startTest();
    String renderedValue = GenericMergeFieldResolver.prepareResolvedValueForOutput(
      richTextValue,
      true,
      false,
      false
    );
    Test.stopTest();

    Assert.areEqual(
      '&lt;p&gt;Project notes&lt;/p&gt;',
      renderedValue,
      'Rich text must remain escaped outside an explicitly enabled HTML body.'
    );
  }

  @IsTest
  static void rejectsExecutableHtmlFormattedValueWhenBodyRenderingAllowsHtmlFields() {
    AuraHandledException thrownException;

    Test.startTest();
    try {
      GenericMergeFieldResolver.prepareResolvedValueForOutput(
        '<p onclick="alert(1)">Unsafe</p>',
        true,
        false,
        true
      );
      Assert.fail('Executable rich text must be rejected.');
    } catch (AuraHandledException exceptionValue) {
      thrownException = exceptionValue;
    }
    Test.stopTest();

    Assert.isNotNull(
      thrownException,
      'The HTML safety policy must reject event handlers.'
    );
  }
}
