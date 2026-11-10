@IsTest
private class DceHtmlPolicyTest {
    @IsTest
    static void acceptsEmailSafeHtmlAndRejectsExecutableMarkup() {
        Test.startTest();
        DceHtmlPolicy.assertSafeTemplateHtml(
            '<table><tr><td style="color:#333">{{Parent.Name}}</td></tr></table>',
            'Body'
        );
        AuraHandledException thrownException;
        try {
            DceHtmlPolicy.assertSafeUserHtml('<p onclick="alert(1)">Unsafe</p>');
        } catch (AuraHandledException exceptionValue) {
            thrownException = exceptionValue;
        }
        Test.stopTest();

        Assert.isNotNull(thrownException, 'Event handlers must be rejected.');
    }

    @IsTest
    static void rejectsScriptAndJavascriptUrls() {
        for (String unsafeHtml : new List<String>{
            '<script>alert(1)</script>',
            '<a href="javascript:alert(1)">Open</a>'
        }) {
            AuraHandledException thrownException;
            try {
                DceHtmlPolicy.assertSafeTemplateHtml(unsafeHtml, 'Header');
            } catch (AuraHandledException exceptionValue) {
                thrownException = exceptionValue;
            }
            Assert.isNotNull(thrownException, 'Executable HTML must be rejected.');
        }
    }
}
