/**
 * Stores and reconstructs template HTML that can exceed a single Long Text Area field.
 */
public with sharing class DceTemplateContentService {
    public static final Integer INLINE_CONTENT_LENGTH = 131072;
    public static final Integer MAX_REGION_CONTENT_LENGTH = 1000000;
    public static final Integer MAX_RENDERED_HTML_LENGTH = 1000000;

    private static final String REGION_HEADER = 'Header';
    private static final String REGION_BODY = 'Body';
    private static final String REGION_FOOTER = 'Footer';

    /**
     * Splits three template regions into inline values and ordered overflow chunks.
     * @param headerHtml Complete header HTML source
     * @param bodyHtml Complete body HTML source
     * @param footerHtml Complete footer HTML source
     * @return Prepared values suitable for saving with a template
     * @throws AuraHandledException when a region exceeds the supported source limit
     */
    public static PreparedContent prepareContent(
        String headerHtml,
        String bodyHtml,
        String footerHtml
    ) {
        PreparedContent prepared = new PreparedContent();
        prepared.headerInline = prepareRegion(REGION_HEADER, headerHtml, prepared.overflowChunks);
        prepared.bodyInline = prepareRegion(REGION_BODY, bodyHtml, prepared.overflowChunks);
        prepared.footerInline = prepareRegion(REGION_FOOTER, footerHtml, prepared.overflowChunks);
        return prepared;
    }

    /**
     * Reconstructs all content regions for a persisted template.
     * @param template Template record containing the inline region values
     * @return Fully reconstructed content bundle
     */
    public static ContentBundle loadContent(Email_Template_Config__c template) {
        if (template == null) {
            return new ContentBundle();
        }

        ContentBundle content = new ContentBundle();
        content.headerHtml = template.Header__c ?? '';
        content.bodyHtml = template.Body_Template__c ?? '';
        content.footerHtml = template.Footer__c ?? '';
        if (template.Id == null) {
            return content;
        }

        Map<String, Integer> expectedSequenceByRegion = new Map<String, Integer>{
            REGION_HEADER => 2,
            REGION_BODY => 2,
            REGION_FOOTER => 2
        };
        for (Email_Template_Content_Chunk__c chunk : [
            SELECT Region__c, Sequence__c, Content__c
            FROM Email_Template_Content_Chunk__c
            WHERE Email_Template_Config__c = :template.Id
            WITH USER_MODE
            ORDER BY Region__c, Sequence__c
        ]) {
            Integer expectedSequence = expectedSequenceByRegion.get(chunk.Region__c);
            Integer actualSequence = chunk.Sequence__c == null ? null : chunk.Sequence__c.intValue();
            if (expectedSequence == null || actualSequence != expectedSequence) {
                throw new AuraHandledException('Template HTML overflow chunks are incomplete or out of order.');
            }
            appendChunk(content, chunk.Region__c, chunk.Content__c);
            expectedSequenceByRegion.put(chunk.Region__c, expectedSequence + 1);
        }
        return content;
    }

    /**
     * Replaces all overflow chunks for one template in a bounded number of DML operations.
     * @param templateId Parent template Id
     * @param chunkInputs Prepared overflow chunks
     */
    public static void replaceOverflowChunks(Id templateId, List<ChunkInput> chunkInputs) {
        if (templateId == null) {
            throw new AuraHandledException('Template Id is required to store overflow HTML.');
        }

        List<Email_Template_Content_Chunk__c> existingChunks = [
            SELECT Id
            FROM Email_Template_Content_Chunk__c
            WHERE Email_Template_Config__c = :templateId
            WITH USER_MODE
        ];
        if (!existingChunks.isEmpty()) {
            delete as user existingChunks;
        }

        List<Email_Template_Content_Chunk__c> chunksToInsert = new List<Email_Template_Content_Chunk__c>();
        for (ChunkInput chunkInput : chunkInputs ?? new List<ChunkInput>()) {
            chunksToInsert.add(new Email_Template_Content_Chunk__c(
                Email_Template_Config__c = templateId,
                Region__c = chunkInput.region,
                Sequence__c = chunkInput.sequence,
                Content__c = chunkInput.content
            ));
        }
        if (!chunksToInsert.isEmpty()) {
            insert as user chunksToInsert;
        }
    }

    /**
     * Ensures rendered email HTML stays within the application safety ceiling.
     * @param renderedHtml Fully rendered HTML
     */
    public static void assertRenderedSize(String renderedHtml) {
        if (renderedHtml != null && renderedHtml.length() > MAX_RENDERED_HTML_LENGTH) {
            throw new AuraHandledException(
                'Rendered email HTML exceeds ' + String.valueOf(MAX_RENDERED_HTML_LENGTH) +
                ' characters. Move large images or assets to public HTTPS URLs.'
            );
        }
    }

    private static String prepareRegion(
        String region,
        String completeContent,
        List<ChunkInput> overflowChunks
    ) {
        String normalizedContent = completeContent ?? '';
        if (normalizedContent.length() > MAX_REGION_CONTENT_LENGTH) {
            throw new AuraHandledException(
                region + ' HTML exceeds the supported limit of ' +
                String.valueOf(MAX_REGION_CONTENT_LENGTH) + ' characters.'
            );
        }

        Integer inlineEnd = Math.min(normalizedContent.length(), INLINE_CONTENT_LENGTH);
        String inlineContent = normalizedContent.substring(0, inlineEnd);
        Integer sequence = 2;
        Integer offset = inlineEnd;
        while (offset < normalizedContent.length()) {
            Integer chunkEnd = Math.min(offset + INLINE_CONTENT_LENGTH, normalizedContent.length());
            overflowChunks.add(new ChunkInput(
                region,
                sequence,
                normalizedContent.substring(offset, chunkEnd)
            ));
            offset = chunkEnd;
            sequence++;
        }
        return inlineContent;
    }

    private static void appendChunk(ContentBundle content, String region, String chunkContent) {
        String safeChunk = chunkContent ?? '';
        if (region == REGION_HEADER) {
            content.headerHtml += safeChunk;
        } else if (region == REGION_BODY) {
            content.bodyHtml += safeChunk;
        } else if (region == REGION_FOOTER) {
            content.footerHtml += safeChunk;
        }
    }

    /**
     * Prepared inline and overflow content.
     */
    public class PreparedContent {
        public String headerInline;
        public String bodyInline;
        public String footerInline;
        public List<ChunkInput> overflowChunks;

        public PreparedContent() {
            overflowChunks = new List<ChunkInput>();
        }
    }

    /**
     * One overflow chunk before it is converted to a persistence record.
     */
    public class ChunkInput {
        public String region;
        public Integer sequence;
        public String content;

        public ChunkInput(String region, Integer sequence, String content) {
            this.region = region;
            this.sequence = sequence;
            this.content = content;
        }
    }

    /**
     * Fully reconstructed HTML for all three regions.
     */
    public class ContentBundle {
        public String headerHtml = '';
        public String bodyHtml = '';
        public String footerHtml = '';
    }
}
