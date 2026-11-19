import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import previewPdfFromHtml from '@salesforce/apex/WeavePdfController.previewPdfFromHtml';

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

export default class WeaveCanvasDesigner extends LightningElement {
    @api parentFields;
    @api previewRecordId;

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
    @track isPreviewingPdf = false;

    // Insert toolbar state
    @track showInsertImage = false;
    @track showInsertQuery = false;
    @track showInsertMerge = false;
    @track insertImageUrl = '';
    @track selectedInsertQueryId = '';
    @track selectedInsertMergeField = '';

    // AI prompt state
    @track promptDescription = '';
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
    get hasNoParentFields() { return !(this.parentFields || []).length; }

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
    get noInsertQuerySelected() { return !this.selectedInsertQueryId; }
    get noInsertMergeSelected() { return !this.selectedInsertMergeField; }

    get insertBtnClassImage() { return 'insert-btn' + (this.showInsertImage ? ' insert-btn_active' : ''); }
    get insertBtnClassQuery() { return 'insert-btn' + (this.showInsertQuery ? ' insert-btn_active' : ''); }
    get insertBtnClassMerge() { return 'insert-btn' + (this.showInsertMerge ? ' insert-btn_active' : ''); }

    // ── AI prompt computed ────────────────────────────────────────────────────

    get copyBtnClass() {
        return this.promptCopied ? 'ai-copy-btn ai-copy-btn_success' : 'ai-copy-btn';
    }

    get weaveAiPrompt() {
        const desc = this.promptDescription?.trim() || '[describe your document here]';
        const objectName = this._draftTemplate.parentObjectApiName || 'the parent object';

        const parentFieldLines = (this.parentFields || [])
            .map(f => `  - ${f.label} → {{Parent.${f.value}}}`)
            .join('\n') || '  No fields available — parent object not set yet';

        const queries = (this._draftTemplate.queries || []);
        let querySection = '';
        if (queries.length > 0) {
            querySection = '\n\nAVAILABLE QUERY SECTIONS (Related Lists):\nEach section loops over related records. Use merge tags inside a section\'s HTML to reference its fields.\n';
            for (const q of queries) {
                const apiName = q.queryApiName || q.name;
                const sectionFields = extractSoqlFields(q.soqlQuery || '');
                querySection += `\n• Section "${q.name}" — reference as {{Section.${apiName}}}\n`;
                if (sectionFields.length > 0) {
                    querySection += `  Fields available inside this section (no prefix needed):\n`;
                    querySection += sectionFields.map(f => `    - {{${f}}}`).join('\n') + '\n';
                }
            }
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
• Section reference (insert a related-list section block): {{Section.QueryApiName}}
• Inside a section, child record fields use no prefix: {{FieldApiName}}
• Use Salesforce field API names exactly as listed below
• Keep merge tags verbatim in the HTML — do not replace them with sample values

AVAILABLE PARENT FIELDS (${objectName}):
${parentFieldLines}${querySection}

Generate the complete HTML template now.`;
    }

    // ── Mode handler ──────────────────────────────────────────────────────────

    handleModeChange(event) {
        // Sync LIRT value before switching away from richtext
        if (this.mode === 'richtext') {
            const lirt = this.template.querySelector('lightning-input-rich-text');
            if (lirt) this.htmlContent = lirt.value || this.htmlContent;
        }
        this.mode = event.currentTarget.dataset.mode;
        this._closeAllInsertPanels();
    }

    // ── Rich Text handlers ────────────────────────────────────────────────────

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
        this.showInsertImage = !this.showInsertImage;
        this.showInsertQuery = false;
        this.showInsertMerge = false;
    }

    handleInsertImageUrlChange(event) {
        this.insertImageUrl = event.detail.value;
    }

    handleInsertImageClose() {
        this.showInsertImage = false;
        this.insertImageUrl = '';
    }

    handleInsertImageConfirm() {
        const url = this.insertImageUrl?.trim();
        if (!url) return;
        this._appendHtml(`<img src="${url}" alt="" style="max-width:100%;display:block;" />`);
        this.showInsertImage = false;
        this.insertImageUrl = '';
    }

    // ── Insert: Query Table ───────────────────────────────────────────────────

    handleInsertQueryToggle() {
        this.showInsertQuery = !this.showInsertQuery;
        this.showInsertImage = false;
        this.showInsertMerge = false;
        this.selectedInsertQueryId = '';
    }

    handleInsertQueryChange(event) {
        this.selectedInsertQueryId = event.detail.value;
    }

    handleInsertQueryClose() {
        this.showInsertQuery = false;
        this.selectedInsertQueryId = '';
    }

    handleInsertQueryConfirm() {
        if (!this.selectedInsertQueryId) return;
        this._appendHtml(`{{Section.${this.selectedInsertQueryId}}}`);
        this.showInsertQuery = false;
        this.selectedInsertQueryId = '';
    }

    // ── Insert: Merge Tag ─────────────────────────────────────────────────────

    handleInsertMergeToggle() {
        this.showInsertMerge = !this.showInsertMerge;
        this.showInsertImage = false;
        this.showInsertQuery = false;
        this.selectedInsertMergeField = '';
    }

    handleInsertMergeChange(event) {
        this.selectedInsertMergeField = event.detail.value;
    }

    handleInsertMergeClose() {
        this.showInsertMerge = false;
        this.selectedInsertMergeField = '';
    }

    handleInsertMergeConfirm() {
        if (!this.selectedInsertMergeField) return;
        this._appendHtml(`{{Parent.${this.selectedInsertMergeField}}}`);
        this.showInsertMerge = false;
        this.selectedInsertMergeField = '';
    }

    // ── Insert: CTA Button ────────────────────────────────────────────────────

    handleInsertCta() {
        this._appendHtml(
            '<table cellpadding="0" cellspacing="0" border="0" style="margin:16px 0;">' +
            '<tr><td style="background:#1f5f5b;padding:12px 28px;border-radius:6px;text-align:center;">' +
            '<a href="#" style="color:#ffffff;font-family:Arial,sans-serif;font-size:14px;font-weight:600;text-decoration:none;">Click Here</a>' +
            '</td></tr></table>'
        );
    }

    // ── AI Prompt handlers ────────────────────────────────────────────────────

    handlePromptDescriptionChange(event) {
        this.promptDescription = event.detail.value;
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

    // ── PDF preview ───────────────────────────────────────────────────────────

    handlePreviewPdf() {
        if (this.isPreviewingPdf) return;
        this.isPreviewingPdf = true;
        const html = this.htmlContent;
        const title = this._draftTemplate.name || 'Preview';
        previewPdfFromHtml({ html, title })
            .then(docId => {
                window.open(`/sfc/servlet.shepherd/document/download/${docId}`, '_blank');
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'PDF Preview Failed',
                    message: error?.body?.message || 'An error occurred generating the PDF.',
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isPreviewingPdf = false;
            });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

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
        this.insertImageUrl = '';
        this.selectedInsertQueryId = '';
        this.selectedInsertMergeField = '';
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
        try {
            document.execCommand('copy');
            this._setCopied();
        } catch { /* silent */ }
        document.body.removeChild(ta);
    }
}
