/**
 * Validates administrator-authored and user-edited email HTML without rewriting source.
 */
public with sharing class DceHtmlPolicy {
    private static final Set<String> SAFE_ATTRIBUTES = new Set<String>{
        'href', 'src', 'alt', 'width', 'height', 'colspan', 'rowspan'
    };

    private static final List<String> PROHIBITED_TAGS = new List<String>{
        'script', 'iframe', 'object', 'embed', 'form', 'input', 'button',
        'svg', 'math', 'video', 'audio', 'base', 'link',
        'style', 'noscript', 'template', 'details', 'summary', 'dialog',
        'meta', 'picture', 'source', 'head', 'html'
    };
    private static final List<String> PROHIBITED_PATTERNS = new List<String>{
        '(?is)\\son[a-z0-9_-]+\\s*=',
        '(?is)javascript\\s*:',
        '(?is)vbscript\\s*:',
        '(?is)data\\s*:\\s*text/html',
        '(?is)srcdoc\\s*=',
        '(?is)expression\\s*\\(',
        '(?is)url\\s*\\(\\s*[\\x22\\x27]?\\s*javascript\\s*:',
        '(?is)@import\\b',
        '(?is)url\\s*\\(\\s*[\\x22\\x27]?\\s*https?\\s*:',
        '(?is)-moz-binding\\s*:',
        '(?is)behavior\\s*:',
        '(?is)<[^>]*&#'
    };

    /**
     * Validates and sanitizes rich-text field values before embedding in email output.
     * Runs all prohibited-content checks, then strips any HTML attribute not in SAFE_ATTRIBUTES.
     * @param html Rich-text field value to sanitize
     * @return Attribute-stripped HTML, safe for embedding
     * @throws AuraHandledException when prohibited markup is present
     */
    public static String sanitizeRichTextHtml(String html) {
        if (String.isBlank(html)) {
            return html == null ? '' : html;
        }
        assertSafeHtml(html, 'Rich-text field');
        return stripDangerousAttributes(html);
    }

    private static String stripDangerousAttributes(String html) {
        Pattern tagPattern = Pattern.compile('(?is)<([a-z][a-z0-9]*)([^>]*)>');
        Pattern attrPattern = Pattern.compile('(?is)\\s+([a-z][a-z0-9-]*)\\s*=\\s*(?:"[^"]*"|\'[^\']*\'|[^\\s>]*)');

        Matcher tagMatcher = tagPattern.matcher(html);
        String result = '';
        Integer lastEnd = 0;

        while (tagMatcher.find()) {
            result += html.substring(lastEnd, tagMatcher.start());
            String tagName = tagMatcher.group(1);
            String attrString = tagMatcher.group(2) != null ? tagMatcher.group(2) : '';

            Matcher attrMatcher = attrPattern.matcher(attrString);
            String safeAttrs = '';
            Integer attrLastEnd = 0;

            while (attrMatcher.find()) {
                safeAttrs += attrString.substring(attrLastEnd, attrMatcher.start());
                if (SAFE_ATTRIBUTES.contains(attrMatcher.group(1).toLowerCase())) {
                    safeAttrs += attrMatcher.group(0);
                }
                attrLastEnd = attrMatcher.end();
            }
            safeAttrs += attrString.substring(attrLastEnd);

            result += '<' + tagName + safeAttrs + '>';
            lastEnd = tagMatcher.end();
        }
        result += html.substring(lastEnd);
        return result;
    }

    /**
     * Rejects active or executable content from a stored HTML template.
     * @param html HTML source to validate
     * @param regionName User-facing region name for error messages
     * @throws AuraHandledException when prohibited markup is present
     */
    public static void assertSafeTemplateHtml(String html, String regionName) {
        assertSafeHtml(html, regionName);
    }

    /**
     * Rejects active or executable content submitted by an email composer.
     * @param html HTML body submitted for sending
     * @throws AuraHandledException when prohibited markup is present
     */
    public static void assertSafeUserHtml(String html) {
        assertSafeHtml(html, 'Email body');
    }

    private static void assertSafeHtml(String html, String regionName) {
        if (String.isBlank(html)) {
            return;
        }

        if (html.contains('\u0000')) {
            throw unsafeHtmlException(regionName, 'invalid null bytes');
        }

        for (String tagName : PROHIBITED_TAGS) {
            if (Pattern.compile('(?is)<\\s*/?\\s*' + tagName + '\\b').matcher(html).find()) {
                throw unsafeHtmlException(regionName, 'prohibited <' + tagName + '> markup');
            }
        }
        for (String prohibitedPattern : PROHIBITED_PATTERNS) {
            if (Pattern.compile(prohibitedPattern).matcher(html).find()) {
                throw unsafeHtmlException(regionName, 'active or executable content');
            }
        }
    }

    private static AuraHandledException unsafeHtmlException(String regionName, String reason) {
        return new AuraHandledException(
            (String.isBlank(regionName) ? 'HTML' : regionName) +
            ' contains ' + reason + '. Remove it before saving or sending.'
        );
    }
}
