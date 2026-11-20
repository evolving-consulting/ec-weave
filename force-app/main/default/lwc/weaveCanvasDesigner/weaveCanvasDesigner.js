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

export default class WeaveCanvasDesigner extends LightningElement {
    @api parentFields;
    @api previewRecordId;
    @api brandDetails; // {displayName, logoUrl, primaryColor, secondaryColor}

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

    // CTA panel
    @track showInsertCta = false;
    @track ctaLabel = 'Click Here';
    @track ctaHref = '#';

    // Enhanced Merge Tag
    @track showInsertMerge = false;
    @track mergeSource = 'parent';
    @track selectedInsertMergeField = '';
    @track selectedMergeQueryId = '';
    @track mergeAsTable = false;
    @track mergeColumns = [];

    // AI Modal
    @track showAiModal = false;
    @track aiDescription = '';
    @track aiParentFieldOptions = [];
    @track aiQueryConfigs = [];
    @track aiCtas = [];
    @track promptCopied = false;

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

    get draftTemplateId() { return this._draftTemplate.id || ''; }
    get hasDraftTemplateId() { return !!this._draftTemplate.id; }
    get imageAcceptTypes() { return ['.jpg', '.jpeg', '.png', '.gif', '.svg', '.webp']; }

    get insertBtnClassImage() { return 'insert-btn' + (this.showInsertImage ? ' insert-btn_active' : ''); }
    get insertBtnClassMerge() { return 'insert-btn' + (this.showInsertMerge ? ' insert-btn_active' : ''); }
    get insertBtnClassCta()   { return 'insert-btn' + (this.showInsertCta ? ' insert-btn_active' : ''); }

    // ── Merge tag source computed ─────────────────────────────────────────────

    get isMergeSourceParent() { return this.mergeSource === 'parent'; }
    get isMergeSourceQuery()  { return this.mergeSource === 'query'; }

    get mergeSourceTabParent() {
        return 'merge-source-tab' + (this.mergeSource === 'parent' ? ' merge-source-tab_active' : '');
    }
    get mergeSourceTabQuery() {
        return 'merge-source-tab' + (this.mergeSource === 'query' ? ' merge-source-tab_active' : '');
    }

    // ── AI prompt computed ────────────────────────────────────────────────────

    get aiCopyBtnClass() {
        return this.promptCopied ? 'ai-copy-btn ai-copy-btn_success' : 'ai-copy-btn';
    }

    get weaveAiPrompt() {
        const desc = this.aiDescription?.trim() || '[describe your document here]';
        const objectName = this._draftTemplate.parentObjectApiName || 'the parent object';

        // Selected parent fields
        const selectedParentFields = (this.aiParentFieldOptions || []).filter(f => f.checked);
        const parentFieldLines = selectedParentFields.length
            ? selectedParentFields.map(f => `  - ${f.label} → {{Parent.${f.value}}}`).join('\n')
            : (this.parentFields || []).map(f => `  - ${f.label} → {{Parent.${f.value}}}`).join('\n')
              || '  No fields available — parent object not set yet';

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
        const bd = this.brandDetails;
        const brandName = this._draftTemplate.brandName;
        if (bd || brandName) {
            brandSection = '\n\nBRAND DETAILS:';
            if (brandName) brandSection += `\n  Brand: ${brandName}`;
            if (bd?.displayName) brandSection += `\n  Display Name: ${bd.displayName}`;
            if (bd?.primaryColor) brandSection += `\n  Primary Color: ${bd.primaryColor}`;
            if (bd?.secondaryColor) brandSection += `\n  Secondary Color: ${bd.secondaryColor}`;
            if (bd?.logoUrl) brandSection += `\n  Logo URL: ${bd.logoUrl}`;
        }

        return `You are building an HTML template for Weave, a Salesforce Dynamic Communication Engine.

DOCUMENT DESCRIPTION:
${desc}

OUTPUT REQUIREMENTS:
• Return ONLY the HTML body content — no <html>, <head>, <body>, or <style> tags
• Inline CSS only
• Use HTML tables for layout (no flexbox or CSS grid) — required for PDF/email rendering
• Web-safe fonts only: Arial, Helvetica, Georgia, Times New Roman, Courier New
• Design for US Letter (8.5 × 11 in) with ~0.5 in margins
• All colors as hex values (#rrggbb)
• No JavaScript

WEAVE MERGE TAG SYNTAX:
• Parent record fields: {{Parent.FieldApiName}}
  Examples: {{Parent.Name}}, {{Parent.CloseDate__c}}, {{Parent.Account.BillingCity}}
• Section reference: {{Section.QueryApiName}}
• Inside a section, child record fields use no prefix: {{FieldApiName}}
• Keep merge tags verbatim — do not replace them with sample values

AVAILABLE PARENT FIELDS (${objectName}):
${parentFieldLines}${querySection}${ctaSection}${imageSection}${brandSection}

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
        this._appendHtml(`<img src="${url}" alt="" style="max-width:100%;display:block;" />`);
        this.handleInsertImageClose();
    }

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
        this._appendHtml(`<img src="${url}" alt="" style="max-width:100%;display:block;" />`);
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
    }

    handleCtaLabelChange(event) { this.ctaLabel = event.detail.value; }
    handleCtaHrefChange(event)  { this.ctaHref  = event.detail.value; }

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

    // ── Insert: Merge Tag ─────────────────────────────────────────────────────

    handleInsertMergeToggle() {
        const opening = !this.showInsertMerge;
        this._closeAllInsertPanels();
        this.showInsertMerge = opening;
        if (opening) {
            this.mergeSource = 'parent';
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

    handleMergeSourceChange(event) {
        this.mergeSource = event.currentTarget.dataset.source;
        this.selectedInsertMergeField = '';
        this.selectedMergeQueryId = '';
        this.mergeAsTable = false;
        this.mergeColumns = [];
    }

    handleInsertMergeChange(event) {
        this.selectedInsertMergeField = event.detail.value;
    }

    handleInsertMergeParentConfirm() {
        if (!this.selectedInsertMergeField) return;
        this._appendHtml(`{{Parent.${this.selectedInsertMergeField}}}`);
        this.handleInsertMergeClose();
    }

    handleMergeQueryChange(event) {
        this.selectedMergeQueryId = event.detail.value;
        this.mergeAsTable = false;
        this.mergeColumns = [];
        // Build column list from the selected query's SOQL
        const query = (this._draftTemplate.queries || []).find(
            q => (q.queryApiName || q.name) === this.selectedMergeQueryId
        );
        if (query) {
            const fields = extractSoqlFields(query.soqlQuery || '');
            this.mergeColumns = buildMergeColumns(fields);
        }
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
        this._appendHtml(`{{Section.${this.selectedMergeQueryId}}}`);
        // Emit column config upward for future renderer use
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
        this._loadImages();
    }

    handleCloseAiModal() {
        this.showAiModal = false;
    }

    handleAiModalBackdropClick() {
        this.showAiModal = false;
    }

    handleAiModalInnerClick(event) {
        event.stopPropagation();
    }

    _initAiModal() {
        // Build parent field options (all selected by default)
        this.aiParentFieldOptions = (this.parentFields || []).map(f => ({
            value: f.value,
            label: f.label,
            checked: true
        }));

        // Build query configs
        this.aiQueryConfigs = (this._draftTemplate.queries || []).map(q => {
            const apiName = q.queryApiName || q.name;
            const fields = extractSoqlFields(q.soqlQuery || '');
            return {
                queryId: apiName,
                queryName: q.name,
                include: false,
                asTable: false,
                columns: buildMergeColumns(fields)
            };
        });

        this.aiCtas = [];
        this.aiDescription = '';
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
        this.insertImageUrl = '';
        this.showManualImageUrl = false;
        this.selectedInsertMergeField = '';
        this.selectedMergeQueryId = '';
        this.mergeAsTable = false;
        this.mergeColumns = [];
        this.ctaLabel = 'Click Here';
        this.ctaHref = '#';
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
