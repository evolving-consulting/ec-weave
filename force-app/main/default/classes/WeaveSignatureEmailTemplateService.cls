public with sharing class WeaveSignatureEmailTemplateService {

    public static final String TYPE_REQUEST      = 'Signature Request';
    public static final String TYPE_REMINDER     = 'Reminder';
    public static final String TYPE_VERIFICATION = 'Verification';
    public static final String TYPE_COMPLETION   = 'Completion';

    public static final List<String> ALL_TYPES = new List<String>{
        TYPE_REQUEST, TYPE_REMINDER, TYPE_VERIFICATION, TYPE_COMPLETION
    };

    // ─── Read ─────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO> getEmailTemplates(Id brandId) {
        try {
            Map<String, Weave_Signature_Email_Template__c> byType = queryTemplates(brandId);
            List<WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO> results = new List<WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO>();
            for (String t : ALL_TYPES) {
                results.add(byType.containsKey(t) ? toDTO(byType.get(t)) : getHardcodedDefault(brandId, t));
            }
            return results;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load email templates: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO getEmailTemplate(Id brandId, String emailType) {
        try {
            Map<String, Weave_Signature_Email_Template__c> byType = queryTemplates(brandId);
            if (byType.containsKey(emailType)) return toDTO(byType.get(emailType));

            // Try org default (null brand)
            if (brandId != null) {
                Map<String, Weave_Signature_Email_Template__c> defaults = queryTemplates(null);
                if (defaults.containsKey(emailType)) return toDTO(defaults.get(emailType));
            }

            return getHardcodedDefault(brandId, emailType);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load email template: ' + e.getMessage());
        }
    }

    // ─── Save ─────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO saveEmailTemplate(String dtoJson) {
        try {
            WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO dto =
                (WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO) JSON.deserialize(
                    dtoJson, WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO.class);

            Weave_Signature_Email_Template__c rec = dto.id != null
                ? new Weave_Signature_Email_Template__c(Id = dto.id)
                : new Weave_Signature_Email_Template__c();

            rec.Brand__c              = dto.brandId;
            rec.Email_Type__c         = dto.emailType;
            rec.Subject__c            = dto.subject;
            rec.Body__c               = dto.body;
            rec.Brand_Color_Override__c = dto.brandColorOverride;
            rec.Logo_URL_Override__c  = dto.logoUrlOverride;
            rec.Logo_Height_Px__c     = dto.logoHeightPx != null ? dto.logoHeightPx : 48;
            rec.Footer_Text_Override__c = dto.footerTextOverride;
            rec.Is_Active__c          = dto.isActive != false;

            if (dto.id == null) {
                rec.Name = (String.isNotBlank(dto.brandName) ? dto.brandName : 'Default')
                    + ' — ' + dto.emailType;
            }

            upsert as user rec;
            dto.id = rec.Id;
            return dto;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to save email template: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static void resetToDefault(Id templateId) {
        try {
            List<Weave_Signature_Email_Template__c> recs = [
                SELECT Id FROM Weave_Signature_Email_Template__c WHERE Id = :templateId WITH USER_MODE LIMIT 1
            ];
            if (!recs.isEmpty()) delete as user recs;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to reset template: ' + e.getMessage());
        }
    }

    // ─── Render ───────────────────────────────────────────────────────────────

    public static String renderSubject(WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO tpl, Map<String, Object> ctx) {
        return resolveTokens(tpl.subject != null ? tpl.subject : '', ctx);
    }

    public static String renderBody(WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO tpl, Map<String, Object> ctx, Id brandId) {
        String body = resolveTokens(tpl.body != null ? tpl.body : '', ctx);

        String brandColor = String.isNotBlank(tpl.brandColorOverride) ? tpl.brandColorOverride : '#1f5f5b';
        String logoUrl    = String.isNotBlank(tpl.logoUrlOverride) ? tpl.logoUrlOverride : '';
        Integer logoH     = tpl.logoHeightPx != null ? tpl.logoHeightPx : 48;
        String footerText = String.isNotBlank(tpl.footerTextOverride) ? tpl.footerTextOverride : '';

        // Apply brand header/footer HTML if brand has one, otherwise use minimal chrome
        String headerHtml = '';
        String footerHtml = '';
        if (brandId != null) {
            try {
                WeaveBuilderDTOs.WeaveBrandDTO brand = WeaveBrandService.loadBrand(brandId);
                if (String.isNotBlank(brand.headerHtml)) {
                    headerHtml = brand.headerHtml;
                    if (String.isNotBlank(brand.primaryColor)) brandColor = brand.primaryColor;
                    if (String.isNotBlank(brand.logoUrl) && String.isBlank(tpl.logoUrlOverride)) logoUrl = brand.logoUrl;
                } else {
                    headerHtml = buildDefaultHeader(brandColor, logoUrl, logoH);
                }
                footerHtml = String.isNotBlank(brand.footerHtml) ? brand.footerHtml : buildDefaultFooter(footerText);
            } catch (Exception e) {
                headerHtml = buildDefaultHeader(brandColor, logoUrl, logoH);
                footerHtml = buildDefaultFooter(footerText);
            }
        } else {
            headerHtml = buildDefaultHeader(brandColor, logoUrl, logoH);
            footerHtml = buildDefaultFooter(footerText);
        }

        return headerHtml + body + footerHtml;
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static Map<String, Weave_Signature_Email_Template__c> queryTemplates(Id brandId) {
        List<Weave_Signature_Email_Template__c> recs = brandId != null
            ? [SELECT Id, Name, Brand__c, Email_Type__c, Subject__c, Body__c,
                      Brand_Color_Override__c, Logo_URL_Override__c, Logo_Height_Px__c,
                      Footer_Text_Override__c, Is_Active__c
               FROM Weave_Signature_Email_Template__c
               WHERE Brand__c = :brandId WITH USER_MODE]
            : [SELECT Id, Name, Brand__c, Email_Type__c, Subject__c, Body__c,
                      Brand_Color_Override__c, Logo_URL_Override__c, Logo_Height_Px__c,
                      Footer_Text_Override__c, Is_Active__c
               FROM Weave_Signature_Email_Template__c
               WHERE Brand__c = null WITH USER_MODE];

        Map<String, Weave_Signature_Email_Template__c> byType = new Map<String, Weave_Signature_Email_Template__c>();
        for (Weave_Signature_Email_Template__c r : recs) byType.put(r.Email_Type__c, r);
        return byType;
    }

    private static WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO toDTO(Weave_Signature_Email_Template__c rec) {
        WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO dto = new WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO();
        dto.id                 = rec.Id;
        dto.brandId            = rec.Brand__c;
        dto.emailType          = rec.Email_Type__c;
        dto.subject            = rec.Subject__c;
        dto.body               = rec.Body__c;
        dto.brandColorOverride = rec.Brand_Color_Override__c;
        dto.logoUrlOverride    = rec.Logo_URL_Override__c;
        dto.logoHeightPx       = rec.Logo_Height_Px__c != null ? rec.Logo_Height_Px__c.intValue() : 48;
        dto.footerTextOverride = rec.Footer_Text_Override__c;
        dto.isActive           = rec.Is_Active__c;
        return dto;
    }

    private static WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO getHardcodedDefault(Id brandId, String emailType) {
        WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO dto = new WeaveBuilderDTOs.WeaveSignatureEmailTemplateDTO();
        dto.brandId   = brandId;
        dto.emailType = emailType;
        dto.isActive  = true;
        dto.logoHeightPx = 48;

        if (emailType == TYPE_REQUEST) {
            dto.subject = 'Action Required: Please Sign {DocumentTitle}';
            dto.body    = '<p>Hi {SignerName},</p>'
                + '<p>{Message}</p>'
                + '<p>{DocumentInfo}{ActionButton}{SecurityNote}</p>';
        } else if (emailType == TYPE_REMINDER) {
            dto.subject = 'Reminder: {DocumentTitle} Awaiting Your Signature';
            dto.body    = '<p>Hi {SignerName},</p>'
                + '<p>This is a friendly reminder that <strong>{DocumentTitle}</strong> is still awaiting your electronic signature.</p>'
                + '<p>{ActionButton}{SecurityNote}</p>';
        } else if (emailType == TYPE_VERIFICATION) {
            dto.subject = 'Your Signing Verification Code';
            dto.body    = '<p>Hi {SignerName},</p>'
                + '<p>Your one-time verification code for signing <strong>{DocumentTitle}</strong> is:</p>'
                + '<p style="font-size:28px;font-weight:700;letter-spacing:6px;color:#1f5f5b;">{VerificationCode}</p>'
                + '<p style="color:#6b7280;font-size:12px;">This code expires in 10 minutes. Do not share it with anyone.</p>';
        } else {
            dto.subject = '{DocumentTitle} Has Been Signed';
            dto.body    = '<p>Hi {SenderName},</p>'
                + '<p>All signers have completed <strong>{DocumentTitle}</strong>. The signed document has been attached to the original record.</p>'
                + '<p>{DocumentInfo}</p>';
        }
        return dto;
    }

    private static String resolveTokens(String template, Map<String, Object> ctx) {
        if (String.isBlank(template) || ctx == null) return template;
        String result = template;
        for (String key : ctx.keySet()) {
            Object val = ctx.get(key);
            result = result.replace('{' + key + '}', val != null ? String.valueOf(val) : '');
        }
        return result;
    }

    private static String buildDefaultHeader(String brandColor, String logoUrl, Integer logoH) {
        String header = '<div style="background:' + brandColor + ';padding:20px 32px;">';
        if (String.isNotBlank(logoUrl)) {
            header += '<img src="' + logoUrl + '" height="' + logoH + '" style="display:block;" alt="Logo" />';
        }
        header += '</div><div style="padding:32px;">';
        return header;
    }

    private static String buildDefaultFooter(String footerText) {
        String footer = '</div>';
        if (String.isNotBlank(footerText)) {
            footer += '<div style="padding:16px 32px;border-top:1px solid #e5e7eb;color:#6b7280;font-size:12px;">'
                + footerText + '</div>';
        }
        return footer;
    }
}
