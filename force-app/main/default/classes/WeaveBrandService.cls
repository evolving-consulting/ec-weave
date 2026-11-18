public with sharing class WeaveBrandService {

    private static final String COLOR_REGEX = '^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$';
    private static final String EMAIL_REGEX = '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$';
    private static final Set<String> IMAGE_TYPES = new Set<String>{ 'png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'bmp' };

    // ── Public read methods ───────────────────────────────────────────────────

    public static List<WeaveBuilderDTOs.WeaveBrandSummaryDTO> getBrands() {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        List<WeaveBuilderDTOs.WeaveBrandSummaryDTO> results = new List<WeaveBuilderDTOs.WeaveBrandSummaryDTO>();
        for (Weave_Brand__c brand : [
            SELECT Id, Name, API_Name__c, Display_Name__c, Status__c,
                Primary_Color__c, Secondary_Color__c, Logo_URL__c,
                Org_Wide_Email_Address__c, Description__c, LastModifiedDate
            FROM Weave_Brand__c
            WITH USER_MODE
            ORDER BY Name ASC
        ]) {
            results.add(toSummaryDto(brand));
        }
        return results;
    }

    public static WeaveBuilderDTOs.WeaveBrandDTO loadBrand(Id brandId) {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        if (brandId == null) return new WeaveBuilderDTOs.WeaveBrandDTO();
        List<Weave_Brand__c> brands = [
            SELECT Id, Name, API_Name__c, Display_Name__c, Status__c,
                Primary_Color__c, Secondary_Color__c,
                Logo_Content_Document_Id__c, Logo_URL__c,
                Org_Wide_Email_Address__c, Physical_Address__c,
                Unsubscribe_URL__c, Unsubscribe_Label__c,
                Header_HTML__c, Header_Editor_Mode__c,
                Footer_HTML__c, Footer_Editor_Mode__c,
                Description__c
            FROM Weave_Brand__c
            WHERE Id = :brandId
            WITH USER_MODE
            LIMIT 1
        ];
        if (brands.isEmpty()) throw new AuraHandledException('Brand not found.');
        return toDto(brands[0]);
    }

    public static WeaveBuilderDTOs.WeaveBrandDTO saveBrand(WeaveBuilderDTOs.WeaveBrandDTO dto) {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        if (dto == null) throw new AuraHandledException('Brand data is required.');
        if (String.isBlank(dto.name)) throw new AuraHandledException('Brand name is required.');

        if (String.isNotBlank(dto.primaryColor) && !Pattern.matches(COLOR_REGEX, dto.primaryColor)) {
            throw new AuraHandledException('Primary color must be a valid hex color (e.g. #1f5f5b).');
        }
        if (String.isNotBlank(dto.secondaryColor) && !Pattern.matches(COLOR_REGEX, dto.secondaryColor)) {
            throw new AuraHandledException('Secondary color must be a valid hex color (e.g. #4fb893).');
        }
        if (String.isNotBlank(dto.orgWideEmailAddress) &&
            !Pattern.matches(EMAIL_REGEX, dto.orgWideEmailAddress.toUpperCase())) {
            throw new AuraHandledException('Org Wide Email Address is not a valid email format.');
        }
        if (String.isNotBlank(dto.headerHtml)) {
            DceHtmlPolicy.assertSafeTemplateHtml(dto.headerHtml, 'Brand Header');
        }
        if (String.isNotBlank(dto.footerHtml)) {
            DceHtmlPolicy.assertSafeTemplateHtml(dto.footerHtml, 'Brand Footer');
        }

        String apiName = dto.id == null ? generateBrandApiName(dto.name) : dto.apiName;

        Weave_Brand__c brand = new Weave_Brand__c(
            Id = dto.id,
            Name = dto.name,
            API_Name__c = apiName,
            Display_Name__c = dto.displayName,
            Status__c = String.isBlank(dto.status) ? 'Active' : dto.status,
            Primary_Color__c = dto.primaryColor,
            Secondary_Color__c = dto.secondaryColor,
            Logo_Content_Document_Id__c = dto.logoContentDocumentId,
            Logo_URL__c = dto.logoUrl,
            Org_Wide_Email_Address__c = dto.orgWideEmailAddress,
            Physical_Address__c = dto.physicalAddress,
            Unsubscribe_URL__c = dto.unsubscribeUrl,
            Unsubscribe_Label__c = String.isBlank(dto.unsubscribeLabel) ? 'Unsubscribe' : dto.unsubscribeLabel,
            Header_HTML__c = dto.headerHtml,
            Header_Editor_Mode__c = String.isBlank(dto.headerEditorMode) ? 'Visual' : dto.headerEditorMode,
            Footer_HTML__c = dto.footerHtml,
            Footer_Editor_Mode__c = String.isBlank(dto.footerEditorMode) ? 'Visual' : dto.footerEditorMode,
            Description__c = dto.description
        );
        upsert as user brand;
        return loadBrand(brand.Id);
    }

    public static void deleteBrand(Id brandId) {
        WeaveTemplateSecurityService.assertCanManageTemplates();
        if (brandId == null) return;
        List<Weave_Brand__c> records = [
            SELECT Id FROM Weave_Brand__c WHERE Id = :brandId WITH USER_MODE LIMIT 1
        ];
        if (!records.isEmpty()) {
            delete as user records;
        }
    }

    // ── File / image management ───────────────────────────────────────────────

    public static List<Map<String,String>> getBrandFiles(Id brandId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.FileType,
                ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :brandId
            WITH USER_MODE
            ORDER BY ContentDocument.CreatedDate DESC
        ];

        Set<Id> versionIds = new Set<Id>();
        for (ContentDocumentLink cdl : links) {
            if (cdl.ContentDocument.LatestPublishedVersionId != null) {
                versionIds.add(cdl.ContentDocument.LatestPublishedVersionId);
            }
        }
        Map<Id, String> urlByVersionId = new Map<Id, String>();
        if (!versionIds.isEmpty()) {
            for (ContentDistribution cd : [
                SELECT ContentVersionId, ContentDownloadUrl
                FROM ContentDistribution
                WHERE ContentVersionId IN :versionIds
                WITH USER_MODE
            ]) {
                if (String.isNotBlank(cd.ContentDownloadUrl)) {
                    urlByVersionId.put(cd.ContentVersionId, cd.ContentDownloadUrl);
                }
            }
        }

        List<Map<String,String>> result = new List<Map<String,String>>();
        for (ContentDocumentLink cdl : links) {
            String docType = (cdl.ContentDocument.FileType ?? '').toLowerCase();
            if (IMAGE_TYPES.contains(docType)) {
                Map<String,String> row = new Map<String,String>{
                    'contentDocumentId' => cdl.ContentDocumentId,
                    'contentVersionId'  => cdl.ContentDocument.LatestPublishedVersionId,
                    'title'             => cdl.ContentDocument.Title,
                    'fileType'          => cdl.ContentDocument.FileType
                };
                String existingUrl = urlByVersionId.get(cdl.ContentDocument.LatestPublishedVersionId);
                if (existingUrl != null) {
                    row.put('publicUrl', existingUrl);
                }
                result.add(row);
            }
        }
        return result;
    }

    public static String createBrandPublicImageLink(Id brandId, Id contentVersionId) {
        List<ContentDistribution> existing = [
            SELECT ContentDownloadUrl FROM ContentDistribution
            WHERE ContentVersionId = :contentVersionId
            WITH USER_MODE LIMIT 1
        ];
        String publicUrl;
        if (!existing.isEmpty() && !String.isBlank(existing[0].ContentDownloadUrl)) {
            publicUrl = existing[0].ContentDownloadUrl;
        } else {
            ContentDistribution cd = new ContentDistribution();
            cd.Name = 'Weave Brand Image';
            cd.ContentVersionId = contentVersionId;
            cd.PreferencesAllowViewInBrowser = true;
            cd.PreferencesLinkLatestVersion = true;
            cd.PreferencesNotifyOnVisit = false;
            cd.PreferencesPasswordRequired = false;
            insert as user cd;
            cd = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :cd.Id WITH USER_MODE LIMIT 1];
            publicUrl = cd.ContentDownloadUrl;
        }

        // If this is the logo content version, update the brand's Logo_URL__c
        if (brandId != null && !String.isBlank(publicUrl)) {
            List<ContentVersion> versions = [
                SELECT ContentDocumentId FROM ContentVersion
                WHERE Id = :contentVersionId WITH USER_MODE LIMIT 1
            ];
            if (!versions.isEmpty()) {
                List<Weave_Brand__c> brands = [
                    SELECT Id, Logo_Content_Document_Id__c
                    FROM Weave_Brand__c WHERE Id = :brandId WITH USER_MODE LIMIT 1
                ];
                if (!brands.isEmpty() && brands[0].Logo_Content_Document_Id__c == versions[0].ContentDocumentId) {
                    brands[0].Logo_URL__c = publicUrl;
                    update as user brands;
                }
            }
        }
        return publicUrl;
    }

    public static void deleteBrandFile(Id contentDocumentId) {
        ContentDocument doc = new ContentDocument(Id = contentDocumentId);
        delete as user doc;
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static WeaveBuilderDTOs.WeaveBrandSummaryDTO toSummaryDto(Weave_Brand__c brand) {
        WeaveBuilderDTOs.WeaveBrandSummaryDTO dto = new WeaveBuilderDTOs.WeaveBrandSummaryDTO();
        dto.id = brand.Id;
        dto.name = brand.Name;
        dto.apiName = brand.API_Name__c;
        dto.displayName = brand.Display_Name__c;
        dto.status = brand.Status__c;
        dto.primaryColor = brand.Primary_Color__c;
        dto.secondaryColor = brand.Secondary_Color__c;
        dto.logoUrl = brand.Logo_URL__c;
        dto.orgWideEmailAddress = brand.Org_Wide_Email_Address__c;
        dto.description = brand.Description__c;
        dto.lastModifiedDate = brand.LastModifiedDate;
        return dto;
    }

    private static WeaveBuilderDTOs.WeaveBrandDTO toDto(Weave_Brand__c brand) {
        WeaveBuilderDTOs.WeaveBrandDTO dto = new WeaveBuilderDTOs.WeaveBrandDTO();
        dto.id = brand.Id;
        dto.name = brand.Name;
        dto.apiName = brand.API_Name__c;
        dto.displayName = brand.Display_Name__c;
        dto.status = brand.Status__c;
        dto.primaryColor = brand.Primary_Color__c;
        dto.secondaryColor = brand.Secondary_Color__c;
        dto.logoContentDocumentId = brand.Logo_Content_Document_Id__c;
        dto.logoUrl = brand.Logo_URL__c;
        dto.orgWideEmailAddress = brand.Org_Wide_Email_Address__c;
        dto.physicalAddress = brand.Physical_Address__c;
        dto.unsubscribeUrl = brand.Unsubscribe_URL__c;
        dto.unsubscribeLabel = brand.Unsubscribe_Label__c;
        dto.headerHtml = brand.Header_HTML__c;
        dto.headerEditorMode = String.isBlank(brand.Header_Editor_Mode__c) ? 'Visual' : brand.Header_Editor_Mode__c;
        dto.footerHtml = brand.Footer_HTML__c;
        dto.footerEditorMode = String.isBlank(brand.Footer_Editor_Mode__c) ? 'Visual' : brand.Footer_Editor_Mode__c;
        dto.description = brand.Description__c;
        return dto;
    }

    @TestVisible
    static String generateBrandApiName(String displayName) {
        if (String.isBlank(displayName)) return 'untitled_brand';
        String base = displayName.toLowerCase()
            .replaceAll('[^a-z0-9]+', '_')
            .replaceAll('^_+|_+$', '');
        if (String.isBlank(base)) base = 'untitled_brand';
        Set<String> existing = new Set<String>();
        for (Weave_Brand__c b : [
            SELECT API_Name__c FROM Weave_Brand__c WHERE API_Name__c LIKE :base + '%' WITH USER_MODE
        ]) {
            existing.add(b.API_Name__c);
        }
        if (!existing.contains(base)) return base;
        for (Integer i = 2; i <= 999; i++) {
            String candidate = base + '_' + i;
            if (!existing.contains(candidate)) return candidate;
        }
        return base + '_' + System.currentTimeMillis();
    }
}
