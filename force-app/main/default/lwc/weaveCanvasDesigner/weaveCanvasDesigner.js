import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplateFiles from '@salesforce/apex/WeaveTemplateBuilderController.getTemplateFiles';
import createPublicImageLink from '@salesforce/apex/WeaveTemplateBuilderController.createPublicImageLink';

const COPY_RESET_MS = 2000;

function extractSoqlFields(soql) {
    if (!soql) return [];
    const match = soql.match(/SELECT\s+([\s\S]+?)\s+FROM/i);
    if (!match) return [];
    return match[1].split(',')
        .map(f => f.trim().split(/\s+/).pop())
        .filter(f => f && !/[()]/g.test(f))
        .slice(0, 25);
}

function buildMergeColumns(fields) {
    return fields.map((f, i) => ({
        field: f,
        header: f,
        selected: true,
        isFirst: i === 0,
        isLast: i === fields.length - 1
    }));
}

function recomputeFirstLast(cols) {
    return cols.map((c, i) => ({ ...c, isFirst: i === 0, isLast: i === cols.length - 1 }));
}

let _ctaSeq = 0;
let _aiCondSeq = 0;

export default class WeaveCanvasDesigner extends LightningElement {
    @api parentFields;
    @api previewRecordId;
    @api brandDetails; // {displayName, logoUrl, primaryColor, secondaryColor, headerHtml, footerHtml}
    @api outputType = 'Email'; // 'Email' | 'Document'

    _draftTemplate = {};

    @api
    get draftTemplate() { return this._draftTemplate; }
    set draftTemplate(val) {
        this._draftTemplate = val || {};
        const htmlComp = (val?.components || []).find(c => this._isHtmlModeComponent(c));
        this.htmlContent = htmlComp?.htmlOutput || '';
    }

    @track mode = 'richtext';
    @track htmlContent = '';

    // Image panel
    @track showInsertImage = false;
    @track templateImages = [];
    @track isLoadingImages = false;
    @track showManualImageUrl = false;
    @track insertImageUrl = '';
    @track imgWidth = '';
    @track imgHeight = '';

    // CTA panel
    @track showInsertCta = false;
    // Conditional panel
    @track showInsertConditional = false;
    @track condType = 'truthy';
    @track condFieldPath = '';
    @track condOperator = '==';
    @track condValue = '';
    @track condIfContent = '';
    @track condElseContent = '';
    @track showCondIfTagPicker = false;
    @track showCondElseTagPicker = false;
    @track condTagSearch = '';
    @track ctaLabel = 'Click Here';
    @track ctaHref = '#';
    @track showCtaTagPicker = false;
    @track ctaTagSearch = '';

    // Enhanced Merge Tag
    @track showInsertMerge = false;
    @track selectedInsertMergeField = '';
    @track selectedMergeQueryId = '';
    @track mergeAsTable = false;
    @track mergeColumns = [];

    // AI Modal
    @track showAiModal = false;
    @track aiStep = 1;
    @track pdfConstraintsExpanded = false;
    @track sfRulesExpanded = false;
    @track aiDescription = '';
    @track aiParentFieldOptions = [];
    @track aiQueryConfigs = [];
    @track aiCtas = [];
    @track aiConditionals = [];
    @track aiCondTagSearch = '';
    @track promptCopied = false;
    @track aiBrandConfig = { primaryColor: '', secondaryColor: '', headerDescription: '', footerDescription: '', logoUrl: '' };
    @track showAiBrandLogoPicker = false;

    _copyTimer = null;

    // ── Mode computed ─────────────────────────────────────────────────────────

    get isRichTextMode() { return this.mode === 'richtext'; }
    get isHtmlMode() { return this.mode === 'html'; }

    get richTextModeClass() {
        return 'mode-tab' + (this.mode === 'richtext' ? ' mode-tab_active' : '');
    }
    get htmlModeClass() {
        return 'mode-tab' + (this.mode === 'html' ? ' mode-tab_active' : '');
    }

    // ── Insert toolbar computed ───────────────────────────────────────────────

    get hasNoQueries() { return !(this._draftTemplate.queries || []).length; }
    get hasParentFields() { return !!(this.parentFields || []).length; }
    get hasQueries() { return !!(this._draftTemplate.queries || []).length; }

    get queryOptions() {
        return (this._draftTemplate.queries || []).map(q => ({
            label: q.name,
            value: q.queryApiName || q.name
        }));
    }

    get mergeTagOptions() {
        return (this.parentFields || []).map(f => ({
            label: f.label + '  →  {{Parent.' + f.value + '}}',
            value: f.value
        }));
    }

    get noInsertImageUrl() { return !this.insertImageUrl?.trim(); }
    get noInsertMergeSelected() { return !this.selectedInsertMergeField; }
    get noMergeQuerySelected() { return !this.selectedMergeQueryId; }
    get noCtaLabel() { return !(this.ctaLabel || '').trim(); }
    get hasTemplateImages() { return this.templateImages.length > 0; }
    get hasMergeColumns() { return this.mergeColumns.length > 0; }
    get hasAiCtas() { return this.aiCtas.length > 0; }
    get hasBrandConfig() {
        const b = this.aiBrandConfig;
        return !!(b.primaryColor || b.secondaryColor || b.headerDescription || b.footerDescription || b.logoUrl);
    }

    get hasBrandLinked() {
        const bd = this.brandDetails;
        return !!(bd && (bd.logoUrl || bd.headerHtml || bd.footerHtml || bd.primaryColor || bd.secondaryColor));
    }

    get brandPrimarySwatchStyle() {
        const c = this.brandDetails?.primaryColor;
        return c ? `background-color:${c}` : '';
    }

    get brandSecondarySwatchStyle() {
        const c = this.brandDetails?.secondaryColor;
        return c ? `background-color:${c}` : '';
    }

    get draftTemplateId() { return this._draftTemplate.id || ''; }
    get hasDraftTemplateId() { return !!this._draftTemplate.id; }
    get imageAcceptTypes() { return ['.jpg', '.jpeg', '.png', '.gif', '.svg', '.webp']; }

    get insertBtnClassImage() { return 'insert-btn' + (this.showInsertImage ? ' insert-btn_active' : ''); }
    get insertBtnClassMerge() { return 'insert-btn' + (this.showInsertMerge ? ' insert-btn_active' : ''); }
    get insertBtnClassCta()   { return 'insert-btn' + (this.showInsertCta ? ' insert-btn_active' : ''); }
    get insertBtnClassConditional() { return 'insert-btn' + (this.showInsertConditional ? ' insert-btn_active' : ''); }

    get condTypeOptions() {
        return [
            { label: 'Truthy — show if field has a value  ({{#Field}})', value: 'truthy' },
            { label: 'Falsy — show if field is empty  ({{^Field}})', value: 'falsy' },
            { label: 'Expression — compare field to a value  ({{#IF}})', value: 'expression' }
        ];
    }

    get condOperatorOptions() {
        return [
            { label: '== (equals)', value: '==' },
            { label: '!= (not equals)', value: '!=' },
            { label: '> (greater than)', value: '>' },
            { label: '< (less than)', value: '<' },
            { label: '>= (greater or equal)', value: '>=' },
            { label: '<= (less or equal)', value: '<=' }
        ];
    }

    get conditionalFieldOptions() {
        return this.availableFieldTags.map(t => ({ label: t.label, value: t.label }));
    }

    get isCondExpression() { return this.condType === 'expression'; }
    get noCondFieldPath() { return !this.condFieldPath; }

    get filteredCondTags() {
        const term = (this.condTagSearch || '').toLowerCase();
        const tags = this.availableFieldTags;
        if (!term) return tags;
        return tags.filter(t => t.label.toLowerCase().includes(term));
    }
    get hasFilteredCondTags() { return this.filteredCondTags.length > 0; }

    // ── Merge tag computed ────────────────────────────────────────────────────

    get selectedMergeQuery() {
        if (!this.selectedMergeQueryId) return null;
        return (this._draftTemplate.queries || []).find(
            q => (q.queryApiName || q.name) === this.selectedMergeQueryId
        ) || null;
    }

    get selectedMergeQueryIsSelf() {
        const q = this.selectedMergeQuery;
        if (!q) return false;
        // 'self' = parent record, 'up' = parent lookup — neither is a child list
        // Also catch legacy data where soqlObject matches the parent (should be 'self' but stored as 'down')
        const parentObj = this._draftTemplate?.parentObjectApiName;
        return q.relationshipType === 'self'
            || q.relationshipType === 'up'
            || q.queryApiName === 'ParentRecord'
            || (parentObj && q.soqlObject === parentObj);
    }

    get mergeQueryFieldOptions() {
        const q = this.selectedMergeQuery;
        if (!q) return [];
        const fields = extractSoqlFields(q.soqlQuery || '');
        return fields.map(f => ({ label: f, value: f }));
    }

    get noMergeFieldSelected() { return !this.selectedInsertMergeField; }

    // ── CTA tag picker computed ───────────────────────────────────────────────

    get availableFieldTags() {
        return (this._draftTemplate.queries || []).flatMap(q => {
            const fields = extractSoqlFields(q.soqlQuery || '');
            const isSelf = q.relationshipType === 'self' || q.queryApiName === 'ParentRecord';
            const prefix = isSelf ? 'Parent' : (q.queryApiName || q.name);
            return fields.map(f => ({
                label: `${prefix}.${f}`,
                value: `{{${prefix}.${f}}}`
            }));
        });
    }

    get filteredCtaFieldTags() {
        const term = (this.ctaTagSearch || '').toLowerCase();
        if (!term) return this.availableFieldTags;
        return this.availableFieldTags.filter(t => t.label.toLowerCase().includes(term));
    }

    get hasFilteredCtaTags() { return this.filteredCtaFieldTags.length > 0; }

    // ── AI step computed ──────────────────────────────────────────────────────

    get isAiStep1() { return this.aiStep === 1; }
    get isAiStep2() { return this.aiStep === 2; }
    get isAiStep3() { return this.aiStep === 3; }
    get isAiStep4() { return this.aiStep === 4; }
    get isAiStep5() { return this.aiStep === 5; }

    get aiStepClass1() { return 'ai-step-dot' + (this.aiStep === 1 ? ' ai-step-dot_active' : (this.aiStep > 1 ? ' ai-step-dot_done' : '')); }
    get aiStepClass2() { return 'ai-step-dot' + (this.aiStep === 2 ? ' ai-step-dot_active' : (this.aiStep > 2 ? ' ai-step-dot_done' : '')); }
    get aiStepClass3() { return 'ai-step-dot' + (this.aiStep === 3 ? ' ai-step-dot_active' : (this.aiStep > 3 ? ' ai-step-dot_done' : '')); }
    get aiStepClass4() { return 'ai-step-dot' + (this.aiStep === 4 ? ' ai-step-dot_active' : (this.aiStep > 4 ? ' ai-step-dot_done' : '')); }
    get aiStepClass5() { return 'ai-step-dot' + (this.aiStep === 5 ? ' ai-step-dot_active' : ''); }

    get aiCondFilteredTags() {
        const term = (this.aiCondTagSearch || '').toLowerCase();
        return this.availableFieldTags.filter(t => !term || t.label.toLowerCase().includes(term));
    }
    get hasAiCondFilteredTags() { return this.aiCondFilteredTags.length > 0; }

    // ── PDF / output type computed ────────────────────────────────────────────

    get isPdfTemplate() { return this.outputType === 'Document'; }

    get pdfConstraintsChevron() { return this.pdfConstraintsExpanded ? '▴' : '▾'; }
    get sfRulesChevron() { return this.sfRulesExpanded ? '▴' : '▾'; }

    // ── AI prompt computed ────────────────────────────────────────────────────

    get aiCopyBtnClass() {
        return this.promptCopied ? 'ai-copy-btn ai-copy-btn_success' : 'ai-copy-btn';
    }

    get weaveAiPrompt() {
        const desc = this.aiDescription?.trim() || '[describe your document here]';
        const objectName = this._draftTemplate.parentObjectApiName || 'the parent object';
        const subject = this._draftTemplate.subjectTemplate || this._draftTemplate.name || '';

        // Selected parent fields
        const selectedParentFields = (this.aiParentFieldOptions || []).filter(f => f.checked);
        const parentFieldLines = selectedParentFields.length
            ? selectedParentFields.map(f => `  - ${f.label} → {{Parent.${f.value}}}`).join('\n')
            : '  (none selected — go back to Step 2 and choose the fields to include)';

        // Query sections
        const includedQueries = (this.aiQueryConfigs || []).filter(qc => qc.include);
        let querySection = '';
        if (includedQueries.length > 0) {
            querySection = '\n\nQUERY SECTIONS (Related Lists):';
            for (const qc of includedQueries) {
                querySection += `\n\n• Section "${qc.queryName}" — reference as {{Section.${qc.queryId}}}`;
                if (qc.asTable) {
                    const selectedCols = (qc.columns || []).filter(c => c.selected);
                    if (selectedCols.length > 0) {
                        querySection += '\n  Render as a table with these columns (in order):';
                        for (const col of selectedCols) {
                            const header = col.header && col.header !== col.field ? col.header : col.field;
                            querySection += `\n    - Column header: "${header}" → field: {{${col.field}}}`;
                        }
                    }
                } else {
                    querySection += '\n  Include records (not as a full table).';
                }
            }
        }

        // CTA buttons
        let ctaSection = '';
        const ctasToInclude = (this.aiCtas || []).filter(c => c.label?.trim());
        if (ctasToInclude.length > 0) {
            ctaSection = '\n\nCTA BUTTONS TO INCLUDE:';
            for (const cta of ctasToInclude) {
                ctaSection += `\n  - Label: "${cta.label}" → href: ${cta.href || '#'}`;
            }
        }

        // Images
        let imageSection = '';
        const selectedImages = (this.templateImages || []).filter(img => img.aiSelected && img.publicUrl);
        if (selectedImages.length > 0) {
            imageSection = '\n\nIMAGES TO INCLUDE:';
            for (const img of selectedImages) {
                imageSection += `\n  - "${img.name}" → ${img.publicUrl}`;
            }
        }

        // Brand details
        let brandSection = '';
        const bc = this.aiBrandConfig;
        const bd = this.brandDetails;
        const brandName = this._draftTemplate.brandName;
        if (this.hasBrandLinked) {
            brandSection = '\n\nBRAND DETAILS (system-managed):';
            if (brandName || bd?.displayName) brandSection += `\n  Brand: ${brandName || bd?.displayName}`;
            if (bd?.primaryColor) brandSection += `\n  Primary Color: ${bd.primaryColor}`;
            if (bd?.secondaryColor) brandSection += `\n  Secondary Color: ${bd.secondaryColor}`;
            if (bd?.logoUrl) brandSection += `\n  Logo URL: ${bd.logoUrl}`;
            brandSection += '\n  IMPORTANT: Do NOT generate a custom header or footer — the brand header and footer HTML are managed by the system and will be injected automatically around the body content.';
        } else {
            const hasAnyBrand = bc.primaryColor || bc.secondaryColor || bc.headerDescription || bc.footerDescription || bc.logoUrl;
            if (hasAnyBrand) {
                brandSection = '\n\nBRAND STYLE GUIDANCE:';
                if (bc.primaryColor) brandSection += `\n  Primary Color: ${bc.primaryColor}`;
                if (bc.secondaryColor) brandSection += `\n  Secondary Color: ${bc.secondaryColor}`;
                if (bc.logoUrl) brandSection += `\n  Logo URL (use in header/logo area): ${bc.logoUrl}`;
                if (bc.headerDescription) brandSection += `\n  Header design: ${bc.headerDescription}`;
                if (bc.footerDescription) brandSection += `\n  Footer design: ${bc.footerDescription}`;
            }
        }

        let condSection = '';
        const activeConds = (this.aiConditionals || []).filter(c => c.fieldPath);
        if (activeConds.length > 0) {
            condSection = '\n\nCONDITIONAL BLOCKS TO GENERATE:';
            activeConds.forEach((c, i) => {
                condSection += `\n\nConditional ${i + 1}`;
                if (c.description) condSection += `: ${c.description}`;
                if (c.condType === 'truthy') {
                    condSection += `\n  Syntax: {{#${c.fieldPath}}}[content when field has value]{{/${c.fieldPath}}}`;
                } else if (c.condType === 'falsy') {
                    condSection += `\n  Syntax: {{^${c.fieldPath}}}[content when field is empty]{{/${c.fieldPath}}}`;
                } else {
                    const op = c.operator || '==';
                    const val = c.value || '';
                    condSection += `\n  Syntax: {{#IF ${c.fieldPath} ${op} '${val}'}}[if-true content]${c.elseContent ? '{{:else}}[else content]' : ''}{{/IF}}`;
                }
                if (c.ifContent) condSection += `\n  Content when true: ${c.ifContent}`;
                if (c.elseContent && c.condType === 'expression') condSection += `\n  Content when false: ${c.elseContent}`;
            });
            condSection += '\n\nUse these conditional blocks in the generated HTML exactly as specified above.';
        }

        const subjectLine = subject ? `\nDOCUMENT TITLE: ${subject}\n` : '';

        // PDF-specific guardrails injected automatically for Document output type
        const pdfRules = this.isPdfTemplate ? `

PDF RENDERING RULES (this template outputs to PDF — these rules are mandatory):
• NEVER use border="1" on <table> elements — PDF renderers draw black borders that ignore CSS border-color
  ✗ Wrong:  <table border="1" style="border-color:#eeeeee">
  ✓ Correct: <table border="0"> with border:1px solid #eeeeee on each <td>
• Footer sections must have page-break-inside:avoid; break-inside:avoid on the containing <tr> AND <td> so they never split across pages
• Add page-break-inside:avoid to any section that must stay on one page (e.g. a signature block, a totals row)
• Do NOT use position:fixed or position:absolute — unsupported in PDF renderers
• Do NOT use min-height — use padding instead
• Max outer table width: 756px (US Letter minus ~0.5 in side margins)` : '';

        return `You are building an HTML template for Weave, a Salesforce Dynamic Communication Engine.

⚠️ CRITICAL — READ BEFORE WRITING ANYTHING:
Your response must begin IMMEDIATELY with a table or block-level HTML tag (e.g. <table ...).
Do NOT output <!DOCTYPE>, <html>, <head>, <meta>, <body>, <style>, or any document wrapper — not even as a comment.
The very first character of your response must be < and the very first tag must be a content tag.
If you wrap the output in a document structure, it will be REJECTED and cannot be saved.

PROHIBITED TAGS — any of these will block saving:
<meta> <html> <head> <body> <link> <script> <style> <iframe> <object> <embed>
<form> <input> <button> <svg> <math> <video> <audio> <base> <noscript>
<template> <details> <summary> <dialog> <picture> <source>

PROHIBITED PATTERNS — also block saving:
• Any event handler attribute: onclick, onload, onerror, onmouseover, etc.
• javascript: or vbscript: in any href or src
• url() in CSS containing any http/https address
• @import, expression(), -moz-binding:, behavior:
• HTML entities inside tag attributes (e.g. &#x6a;)

ALLOWED TAGS ONLY: <table> <thead> <tbody> <tfoot> <tr> <th> <td> <a> <p> <div> <span>
<img> <h1> <h2> <h3> <h4> <h5> <h6> <ul> <ol> <li> <br> <strong> <em> <u> <blockquote> <hr>
${subjectLine}
DOCUMENT DESCRIPTION:
${desc}

OUTPUT REQUIREMENTS:
• All CSS must be inline style="…" on each element — no <style> blocks anywhere
• Use HTML tables for layout (no flexbox or CSS grid) — required for PDF/email rendering
• Web-safe fonts only: Arial, Helvetica, Georgia, Times New Roman, Courier New
• Design for US Letter (8.5 × 11 in) with ~0.5 in margins
• All colors as hex values (#rrggbb)
• No JavaScript
• Images: use a direct https:// URL in the src attribute (no data: URIs)

WEAVE MERGE TAG SYNTAX:
• Parent record fields: {{Parent.FieldApiName}}
  Examples: {{Parent.Name}}, {{Parent.CloseDate__c}}, {{Parent.Account.BillingCity}}
• Section reference: {{Section.QueryApiName}}
• Inside a section, child record fields use no prefix: {{FieldApiName}}
• Keep merge tags verbatim — do not replace them with sample values

CONDITIONAL SYNTAX (use to show or hide content based on field values):
• Truthy block — show content only when a field has a value:
    {{#Parent.FieldApiName}}content here{{/Parent.FieldApiName}}
• Falsy block — show content only when a field is blank or false:
    {{^Parent.FieldApiName}}content here{{/Parent.FieldApiName}}
• Expression block — compare a field to a value, with optional else branch:
    {{#IF Parent.FieldApiName == 'SomeValue'}}show this{{:else}}show that{{/IF}}
  Supported operators: == != > < >= <=
• Rules: Use field paths exactly as listed in AVAILABLE PARENT FIELDS. Conditionals can wrap any HTML. Do NOT nest conditionals inside each other.

AVAILABLE PARENT FIELDS (${objectName}):
${parentFieldLines}${querySection}${ctaSection}${imageSection}${brandSection}${condSection}${pdfRules}

Generate the complete HTML template now.`;
    }

    // ── Mode handler ──────────────────────────────────────────────────────────

    handleModeChange(event) {
        if (this.mode === 'richtext') {
            const lirt = this.template.querySelector('lightning-input-rich-text');
            if (lirt) this.htmlContent = lirt.value || this.htmlContent;
        }
        this.mode = event.currentTarget.dataset.mode;
        this._closeAllInsertPanels();
    }

    // ── Rich Text handler ─────────────────────────────────────────────────────

    handleRichTextChange(event) {
        this.htmlContent = event.detail.value;
        this._emitHtmlChanged();
    }

    // ── HTML textarea handler ─────────────────────────────────────────────────

    handleHtmlChange(event) {
        this.htmlContent = event.detail.value;
        this._emitHtmlChanged();
    }

    // ── Insert: Image ─────────────────────────────────────────────────────────

    handleInsertImageToggle() {
        const opening = !this.showInsertImage;
        this._closeAllInsertPanels();
        this.showInsertImage = opening;
        if (opening) this._loadImages();
    }

    handleInsertImageClose() {
        this.showInsertImage = false;
        this.insertImageUrl = '';
        this.showManualImageUrl = false;
        this.imgWidth = '';
        this.imgHeight = '';
    }

    handleToggleManualImageUrl() {
        this.showManualImageUrl = !this.showManualImageUrl;
    }

    handleInsertImageUrlChange(event) {
        this.insertImageUrl = event.detail.value;
    }

    handleInsertImageConfirm() {
        const url = this.insertImageUrl?.trim();
        if (!url) return;
        this._insertImageUrl(url);
    }

    handleImgWidthChange(event) { this.imgWidth = event.detail.value; }
    handleImgHeightChange(event) { this.imgHeight = event.detail.value; }

    handleSelectTemplateImage(event) {
        const cvId = event.currentTarget.dataset.cvid;
        const img = this.templateImages.find(i => i.cvId === cvId);
        if (!img) return;
        if (img.publicUrl) {
            this._insertImageUrl(img.publicUrl);
            return;
        }
        // Mark as loading
        this.templateImages = this.templateImages.map(i =>
            i.cvId === cvId ? { ...i, loading: true } : i
        );
        createPublicImageLink({ contentVersionId: cvId })
            .then(url => {
                this.templateImages = this.templateImages.map(i =>
                    i.cvId === cvId ? { ...i, publicUrl: url, loading: false } : i
                );
                this._insertImageUrl(url);
            })
            .catch(() => {
                this.templateImages = this.templateImages.map(i =>
                    i.cvId === cvId ? { ...i, loading: false } : i
                );
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error', message: 'Could not get public URL for this image.', variant: 'error'
                }));
            });
    }

    _insertImageUrl(url) {
        const w = parseInt(this.imgWidth, 10);
        const h = parseInt(this.imgHeight, 10);
        let style = 'max-width:100%;display:block;';
        if (w > 0) style += `width:${w}px;`;
        if (h > 0) style += `height:${h}px;`;
        const widthAttr = w > 0 ? ` width="${w}"` : '';
        const heightAttr = h > 0 ? ` height="${h}"` : '';
        const snippet = `<img src="${url}" alt=""${widthAttr}${heightAttr} style="${style}" />`;
        // Always switch to HTML mode — the rich text editor sanitizes img attributes on any interaction
        if (this.mode === 'richtext') {
            const lirt = this.template.querySelector('lightning-input-rich-text');
            if (lirt) this.htmlContent = lirt.value || this.htmlContent;
            this.mode = 'html';
        }
        this._appendHtml(snippet);
        this.handleInsertImageClose();
    }

    handleImageUploadFinished() {
        this._loadImages();
    }

    // ── Insert: CTA Button ────────────────────────────────────────────────────

    handleInsertCtaToggle() {
        const opening = !this.showInsertCta;
        this._closeAllInsertPanels();
        this.showInsertCta = opening;
    }

    handleInsertCtaClose() {
        this.showInsertCta = false;
        this.ctaLabel = 'Click Here';
        this.ctaHref = '#';
        this.showCtaTagPicker = false;
        this.ctaTagSearch = '';
    }

    handleCtaLabelChange(event) { this.ctaLabel = event.detail.value; }
    handleCtaHrefChange(event)  { this.ctaHref  = event.detail.value; }

    handleToggleCtaTagPicker() {
        this.showCtaTagPicker = !this.showCtaTagPicker;
        this.ctaTagSearch = '';
    }

    handleCtaTagSearch(event) { this.ctaTagSearch = event.target.value; }

    handleInsertCtaFieldTag(event) {
        const tag = event.currentTarget.dataset.tag;
        this.ctaHref = (this.ctaHref || '') + tag;
        this.showCtaTagPicker = false;
        this.ctaTagSearch = '';
    }

    handleInsertCtaConfirm() {
        const label = (this.ctaLabel || '').trim() || 'Click Here';
        const href  = (this.ctaHref  || '').trim() || '#';
        this._appendHtml(
            '<table cellpadding="0" cellspacing="0" border="0" style="margin:16px 0;">' +
            '<tr><td style="background:#1f5f5b;padding:12px 28px;border-radius:6px;text-align:center;">' +
            `<a href="${href}" style="color:#ffffff;font-family:Arial,sans-serif;font-size:14px;font-weight:600;text-decoration:none;">${label}</a>` +
            '</td></tr></table>'
        );
        this.handleInsertCtaClose();
    }

    // ── Insert: Conditional Block ─────────────────────────────────────────────

    handleInsertConditionalToggle() {
        const opening = !this.showInsertConditional;
        this._closeAllInsertPanels();
        this.showInsertConditional = opening;
        if (opening) {
            this.condType = 'truthy';
            this.condFieldPath = '';
            this.condOperator = '==';
            this.condValue = '';
            this.condIfContent = '';
            this.condElseContent = '';
        }
    }

    handleInsertConditionalClose() {
        this.showInsertConditional = false;
        this.showCondIfTagPicker = false;
        this.showCondElseTagPicker = false;
        this.condTagSearch = '';
    }

    handleConditionalModalBackdropClick() { this.showInsertConditional = false; }
    handleConditionalModalInnerClick(event) { event.stopPropagation(); }

    handleCondTypeChange(event) { this.condType = event.detail.value; }
    handleCondFieldChange(event) { this.condFieldPath = event.detail.value; }
    handleCondOperatorChange(event) { this.condOperator = event.detail.value; }
    handleCondValueChange(event) { this.condValue = event.detail.value; }
    handleCondIfContentChange(event) { this.condIfContent = event.detail.value; }
    handleCondElseContentChange(event) { this.condElseContent = event.detail.value; }

    handleCondIfTagPickerToggle() {
        this.showCondIfTagPicker = !this.showCondIfTagPicker;
        this.showCondElseTagPicker = false;
        this.condTagSearch = '';
    }

    handleCondElseTagPickerToggle() {
        this.showCondElseTagPicker = !this.showCondElseTagPicker;
        this.showCondIfTagPicker = false;
        this.condTagSearch = '';
    }

    handleCondTagSearch(event) { this.condTagSearch = event.target.value; }

    handleInsertCondTag(event) {
        const tag = event.currentTarget.dataset.tag;
        const target = event.currentTarget.dataset.target;
        if (target === 'elseContent') {
            this.condElseContent = (this.condElseContent || '') + tag;
            this.showCondElseTagPicker = false;
        } else {
            this.condIfContent = (this.condIfContent || '') + tag;
            this.showCondIfTagPicker = false;
        }
        this.condTagSearch = '';
    }

    handleInsertConditionalConfirm() {
        const field = this.condFieldPath;
        if (!field) return;
        const ifContent = this.condIfContent || '';
        let snippet;
        if (this.condType === 'truthy') {
            snippet = `{{#${field}}}${ifContent}{{/${field}}}`;
        } else if (this.condType === 'falsy') {
            snippet = `{{^${field}}}${ifContent}{{/${field}}}`;
        } else {
            const op = this.condOperator || '==';
            const val = this.condValue || '';
            const elseBlock = this.condElseContent ? `{{:else}}${this.condElseContent}` : '';
            snippet = `{{#IF ${field} ${op} '${val}'}}${ifContent}${elseBlock}{{/IF}}`;
        }
        this._appendHtml(snippet);
        this._closeAllInsertPanels();
    }

    // ── Insert: Merge Tag ─────────────────────────────────────────────────────

    handleInsertMergeToggle() {
        const opening = !this.showInsertMerge;
        this._closeAllInsertPanels();
        this.showInsertMerge = opening;
        if (opening) {
            this.selectedInsertMergeField = '';
            this.selectedMergeQueryId = '';
            this.mergeAsTable = false;
            this.mergeColumns = [];
        }
    }

    handleInsertMergeClose() {
        this.showInsertMerge = false;
        this.selectedInsertMergeField = '';
        this.selectedMergeQueryId = '';
        this.mergeAsTable = false;
        this.mergeColumns = [];
    }

    handleMergeQueryChange(event) {
        this.selectedMergeQueryId = event.detail.value;
        this.mergeAsTable = false;
        this.mergeColumns = [];
        this.selectedInsertMergeField = '';
        const query = (this._draftTemplate.queries || []).find(
            q => (q.queryApiName || q.name) === this.selectedMergeQueryId
        );
        if (query) {
            const fields = extractSoqlFields(query.soqlQuery || '');
            this.mergeColumns = buildMergeColumns(fields);
        }
    }

    handleMergeFieldChange(event) {
        this.selectedInsertMergeField = event.detail.value;
    }

    handleMergeAsTableChange(event) {
        this.mergeAsTable = event.target.checked;
    }

    handleColumnToggle(event) {
        const field = event.target.dataset.field;
        this.mergeColumns = this.mergeColumns.map(c =>
            c.field === field ? { ...c, selected: event.target.checked } : c
        );
    }

    handleColumnHeaderChange(event) {
        const field = event.target.dataset.field;
        const val = event.detail.value;
        this.mergeColumns = this.mergeColumns.map(c =>
            c.field === field ? { ...c, header: val } : c
        );
    }

    handleColumnMove(event) {
        const idx = parseInt(event.currentTarget.dataset.idx, 10);
        const dir = event.currentTarget.dataset.dir;
        const cols = [...this.mergeColumns];
        const swap = dir === 'up' ? idx - 1 : idx + 1;
        if (swap < 0 || swap >= cols.length) return;
        [cols[idx], cols[swap]] = [cols[swap], cols[idx]];
        this.mergeColumns = recomputeFirstLast(cols);
    }

    handleInsertQueryConfirm() {
        if (!this.selectedMergeQueryId) return;
        // Single-field insert for self queries (ParentRecord)
        if (!this.mergeAsTable && this.selectedMergeQueryIsSelf && this.selectedInsertMergeField) {
            this._appendHtml(`{{Parent.${this.selectedInsertMergeField}}}`);
            this.handleInsertMergeClose();
            return;
        }
        // Section / table insert
        this._appendHtml(`{{Section.${this.selectedMergeQueryId}}}`);
        const selectedCols = this.mergeColumns.filter(c => c.selected);
        if (this.mergeAsTable && selectedCols.length > 0) {
            this.dispatchEvent(new CustomEvent('querycolumnconfig', {
                detail: {
                    queryApiName: this.selectedMergeQueryId,
                    columns: selectedCols.map(c => ({ field: c.field, header: c.header }))
                }
            }));
        }
        this.handleInsertMergeClose();
    }

    // ── AI Modal ──────────────────────────────────────────────────────────────

    handleOpenAiModal() {
        this._initAiModal();
        this.showAiModal = true;
        this.aiStep = 1;
        this._loadImages();
    }

    handleCloseAiModal() {
        this.showAiModal = false;
    }

    handleAiNext() {
        if (this.aiStep < 5) this.aiStep += 1;
    }

    handleAiBack() {
        if (this.aiStep > 1) this.aiStep -= 1;
    }

    handleAiModalBackdropClick() {
        this.showAiModal = false;
    }

    handleAiModalInnerClick(event) {
        event.stopPropagation();
    }

    _initAiModal() {
        // Build parent field options from the parent-record query's selected fields (not ALL object fields)
        const parentObj = this._draftTemplate.parentObjectApiName;
        const parentQuery = (this._draftTemplate.queries || []).find(q =>
            q.relationshipType === 'self' ||
            (parentObj && q.soqlObject === parentObj)
        );
        const parentFieldApiNames = parentQuery
            ? extractSoqlFields(parentQuery.soqlQuery || '')
            : [];
        // Build a lookup map from parentFields for label resolution
        const fieldLabelMap = {};
        (this.parentFields || []).forEach(f => { fieldLabelMap[f.value] = f.label; });
        if (parentFieldApiNames.length > 0) {
            this.aiParentFieldOptions = parentFieldApiNames
                .filter(f => f !== 'Id')
                .map(f => ({
                    value: f,
                    label: fieldLabelMap[f] || f,
                    checked: false
                }));
        } else {
            // Fallback: all parent fields except Id
            this.aiParentFieldOptions = (this.parentFields || [])
                .filter(f => f.value !== 'Id')
                .map(f => ({ value: f.value, label: f.label, checked: false }));
        }

        // Build query configs — exclude parent-record queries (those live in Merge Fields)
        this.aiQueryConfigs = (this._draftTemplate.queries || [])
            .filter(q => {
                if (q.relationshipType === 'self') return false;
                const apiName = (q.queryApiName || '').toLowerCase();
                if (apiName === 'parentrecord' || apiName === 'parent_record') return false;
                if (parentObj && q.soqlObject === parentObj) return false;
                return true;
            })
            .map(q => {
                const apiName = q.queryApiName || q.name;
                const fields = extractSoqlFields(q.soqlQuery || '');
                return {
                    queryId: apiName,
                    queryName: q.name,
                    include: false,
                    asTable: false,
                    canBeTable: q.relationshipType === 'down',
                    columns: buildMergeColumns(fields)
                };
            });

        this.aiCtas = [];
        this.aiConditionals = [];
        this.aiCondTagSearch = '';
        this.aiDescription = '';

        // Initialize brand config — colors/logo pre-filled from brandDetails if linked
        const bd = this.brandDetails;
        this.aiBrandConfig = {
            primaryColor: bd?.primaryColor || '',
            secondaryColor: bd?.secondaryColor || '',
            headerDescription: '',
            footerDescription: '',
            logoUrl: bd?.logoUrl || ''
        };
        this.showAiBrandLogoPicker = false;
    }

    handleAiDescriptionChange(event) {
        this.aiDescription = event.detail.value;
    }

    handleAiFieldToggle(event) {
        const field = event.target.dataset.field;
        const checked = event.target.checked;
        this.aiParentFieldOptions = this.aiParentFieldOptions.map(f =>
            f.value === field ? { ...f, checked } : f
        );
    }

    handleAiQueryToggle(event) {
        const qid = event.target.dataset.qid;
        const include = event.target.checked;
        this.aiQueryConfigs = this.aiQueryConfigs.map(qc =>
            qc.queryId === qid ? { ...qc, include } : qc
        );
    }

    handleAiQueryAsTableToggle(event) {
        const qid = event.target.dataset.qid;
        const asTable = event.target.checked;
        this.aiQueryConfigs = this.aiQueryConfigs.map(qc =>
            qc.queryId === qid ? { ...qc, asTable } : qc
        );
    }

    handleAiColToggle(event) {
        const qid = event.target.dataset.qid;
        const field = event.target.dataset.field;
        const selected = event.target.checked;
        this.aiQueryConfigs = this.aiQueryConfigs.map(qc => {
            if (qc.queryId !== qid) return qc;
            return { ...qc, columns: qc.columns.map(c => c.field === field ? { ...c, selected } : c) };
        });
    }

    handleAiColHeaderChange(event) {
        const qid = event.target.dataset.qid;
        const field = event.target.dataset.field;
        const header = event.detail.value;
        this.aiQueryConfigs = this.aiQueryConfigs.map(qc => {
            if (qc.queryId !== qid) return qc;
            return { ...qc, columns: qc.columns.map(c => c.field === field ? { ...c, header } : c) };
        });
    }

    handleAiColMove(event) {
        const qid = event.currentTarget.dataset.qid;
        const idx = parseInt(event.currentTarget.dataset.idx, 10);
        const dir = event.currentTarget.dataset.dir;
        this.aiQueryConfigs = this.aiQueryConfigs.map(qc => {
            if (qc.queryId !== qid) return qc;
            const cols = [...qc.columns];
            const swap = dir === 'up' ? idx - 1 : idx + 1;
            if (swap < 0 || swap >= cols.length) return qc;
            [cols[idx], cols[swap]] = [cols[swap], cols[idx]];
            return { ...qc, columns: recomputeFirstLast(cols) };
        });
    }

    handleAiAddCta() {
        this.aiCtas = [...this.aiCtas, { id: ++_ctaSeq, label: '', href: '' }];
    }

    handleAiCtaChange(event) {
        const idx = parseInt(event.target.dataset.idx, 10);
        const field = event.target.dataset.field;
        const value = event.detail.value;
        this.aiCtas = this.aiCtas.map((c, i) => i === idx ? { ...c, [field]: value } : c);
    }

    handleAiRemoveCta(event) {
        const idx = parseInt(event.currentTarget.dataset.idx, 10);
        this.aiCtas = this.aiCtas.filter((_, i) => i !== idx);
    }

    handleAiBrandChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        this.aiBrandConfig = { ...this.aiBrandConfig, [field]: value };
    }

    handleAiBrandColorChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.aiBrandConfig = { ...this.aiBrandConfig, [field]: value };
    }

    handleToggleAiBrandLogoPicker() {
        this.showAiBrandLogoPicker = !this.showAiBrandLogoPicker;
    }

    handleAiBrandLogoSelect(event) {
        const cvId = event.currentTarget.dataset.cvid;
        const img = this.templateImages.find(i => i.cvId === cvId);
        if (!img) return;
        if (img.publicUrl) {
            this.aiBrandConfig = { ...this.aiBrandConfig, logoUrl: img.publicUrl };
            this.showAiBrandLogoPicker = false;
        } else {
            createPublicImageLink({ contentVersionId: cvId })
                .then(url => {
                    this.templateImages = this.templateImages.map(i =>
                        i.cvId === cvId ? { ...i, publicUrl: url } : i
                    );
                    this.aiBrandConfig = { ...this.aiBrandConfig, logoUrl: url };
                    this.showAiBrandLogoPicker = false;
                });
        }
    }

    handleAiImageToggle(event) {
        const cvId = event.target.dataset.cvid;
        const aiSelected = event.target.checked;
        // If selecting and no publicUrl yet, fetch it
        const img = this.templateImages.find(i => i.cvId === cvId);
        if (aiSelected && img && !img.publicUrl) {
            createPublicImageLink({ contentVersionId: cvId })
                .then(url => {
                    this.templateImages = this.templateImages.map(i =>
                        i.cvId === cvId ? { ...i, publicUrl: url, aiSelected: true } : i
                    );
                })
                .catch(() => {});
        }
        this.templateImages = this.templateImages.map(i =>
            i.cvId === cvId ? { ...i, aiSelected } : i
        );
    }

    handleTogglePdfConstraints() {
        this.pdfConstraintsExpanded = !this.pdfConstraintsExpanded;
    }

    handleToggleSfRules() {
        this.sfRulesExpanded = !this.sfRulesExpanded;
    }

    handleCopyPrompt() {
        const prompt = this.weaveAiPrompt;
        try {
            navigator.clipboard.writeText(prompt)
                .then(() => this._setCopied())
                .catch(() => this._fallbackCopy(prompt));
        } catch {
            this._fallbackCopy(prompt);
        }
    }

    // ── AI Step 3 — Conditional block handlers ────────────────────────────────

    handleAiCondAdd() {
        const id = ++_aiCondSeq;
        this.aiConditionals = [...this.aiConditionals, {
            id,
            num: id,
            description: '',
            condType: 'truthy',
            fieldPath: '',
            operator: '==',
            value: '',
            ifContent: '',
            elseContent: '',
            showIfPicker: false,
            showElsePicker: false,
            isExpression: false
        }];
    }

    handleAiCondRemove(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.aiConditionals = this.aiConditionals.filter(c => c.id !== id);
    }

    _updateAiCond(id, patch) {
        this.aiConditionals = this.aiConditionals.map(c => {
            if (c.id !== id) return c;
            const updated = { ...c, ...patch };
            updated.isExpression = updated.condType === 'expression';
            return updated;
        });
    }

    handleAiCondDescChange(event) {
        this._updateAiCond(Number(event.currentTarget.dataset.id), { description: event.detail.value });
    }

    handleAiCondTypeChange(event) {
        this._updateAiCond(Number(event.currentTarget.dataset.id), { condType: event.detail.value });
    }

    handleAiCondFieldChange(event) {
        this._updateAiCond(Number(event.currentTarget.dataset.id), { fieldPath: event.detail.value });
    }

    handleAiCondOperatorChange(event) {
        this._updateAiCond(Number(event.currentTarget.dataset.id), { operator: event.detail.value });
    }

    handleAiCondValueChange(event) {
        this._updateAiCond(Number(event.currentTarget.dataset.id), { value: event.detail.value });
    }

    handleAiCondIfContentChange(event) {
        this._updateAiCond(Number(event.currentTarget.dataset.id), { ifContent: event.detail.value });
    }

    handleAiCondElseContentChange(event) {
        this._updateAiCond(Number(event.currentTarget.dataset.id), { elseContent: event.detail.value });
    }

    handleAiCondIfPickerToggle(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.aiConditionals = this.aiConditionals.map(c => ({
            ...c,
            showIfPicker: c.id === id ? !c.showIfPicker : false,
            showElsePicker: false
        }));
        this.aiCondTagSearch = '';
    }

    handleAiCondElsePickerToggle(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.aiConditionals = this.aiConditionals.map(c => ({
            ...c,
            showElsePicker: c.id === id ? !c.showElsePicker : false,
            showIfPicker: false
        }));
        this.aiCondTagSearch = '';
    }

    handleAiCondTagSearch(event) {
        this.aiCondTagSearch = event.target.value;
    }

    handleInsertAiCondTag(event) {
        const tag = event.currentTarget.dataset.tag;
        const id = Number(event.currentTarget.dataset.id);
        const target = event.currentTarget.dataset.target;
        this._updateAiCond(id, {
            [target]: ((this.aiConditionals.find(c => c.id === id) || {})[target] || '') + tag,
            showIfPicker: false,
            showElsePicker: false
        });
        this.aiCondTagSearch = '';
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _loadImages() {
        if (!this._draftTemplate.id) return;
        this.isLoadingImages = true;
        getTemplateFiles({ templateId: this._draftTemplate.id, fileType: 'image' })
            .then(files => {
                const existing = new Map(this.templateImages.map(i => [i.cvId, i]));
                this.templateImages = (files || []).map(f => {
                    const prev = existing.get(f.contentVersionId);
                    return {
                        cvId: f.contentVersionId,
                        docId: f.contentDocumentId,
                        name: f.title,
                        fileType: f.fileType,
                        publicUrl: prev?.publicUrl || '',
                        loading: false,
                        aiSelected: prev?.aiSelected || false
                    };
                });
            })
            .catch(() => {})
            .finally(() => { this.isLoadingImages = false; });
    }

    _appendHtml(snippet) {
        const lirt = this.template.querySelector('lightning-input-rich-text');
        const current = (lirt ? lirt.value : null) ?? this.htmlContent ?? '';
        this.htmlContent = current + snippet;
        this._emitHtmlChanged();
    }

    _closeAllInsertPanels() {
        this.showInsertImage = false;
        this.showInsertQuery = false;
        this.showInsertMerge = false;
        this.showInsertCta = false;
        this.showInsertConditional = false;
        this.showCondIfTagPicker = false;
        this.showCondElseTagPicker = false;
        this.condTagSearch = '';
        this.insertImageUrl = '';
        this.showManualImageUrl = false;
        this.imgWidth = '';
        this.imgHeight = '';
        this.selectedInsertMergeField = '';
        this.selectedMergeQueryId = '';
        this.mergeAsTable = false;
        this.mergeColumns = [];
        this.ctaLabel = 'Click Here';
        this.ctaHref = '#';
        this.showCtaTagPicker = false;
        this.ctaTagSearch = '';
    }

    _isHtmlModeComponent(c) {
        if (!c) return false;
        try {
            const cfg = c.configJson ? JSON.parse(c.configJson) : {};
            return cfg.htmlMode === true;
        } catch { return false; }
    }

    _emitHtmlChanged() {
        const existing = (this._draftTemplate.components || []).find(c => this._isHtmlModeComponent(c));
        const otherComps = (this._draftTemplate.components || []).filter(c => !this._isHtmlModeComponent(c));
        const htmlComp = {
            id: existing?.id || null,
            localKey: existing?.localKey || 'html-mode-content',
            name: 'HTML Content',
            componentType: 'HTML Block',
            region: 'Body',
            displayOrder: 0,
            htmlOutput: this.htmlContent,
            configJson: '{"htmlMode":true}',
            canvasMode: false
        };
        this.dispatchEvent(new CustomEvent('componentschanged', {
            detail: { components: [...otherComps, htmlComp] },
            bubbles: false
        }));
    }

    _setCopied() {
        this.promptCopied = true;
        clearTimeout(this._copyTimer);
        this._copyTimer = setTimeout(() => { this.promptCopied = false; }, COPY_RESET_MS);
    }

    _fallbackCopy(text) {
        const ta = document.createElement('textarea');
        ta.value = text;
        ta.style.cssText = 'position:fixed;opacity:0;';
        document.body.appendChild(ta);
        ta.focus();
        ta.select();
        try { document.execCommand('copy'); this._setCopied(); } catch { /* silent */ }
        document.body.removeChild(ta);
    }
}
