import { LightningElement, api, track } from 'lwc';
import resolveTemplate from '@salesforce/apex/MCNTemplateRenderService.resolveTemplate';

export default class McnTemplateRenderer extends LightningElement {
    @api templateId;
    @api contextData;
    @api recordId;

    @track isLoading = false;
    @track errorMessage = '';
    @track renderedSubject = '';
    @track _htmlBody = '';

    _lastTemplateId;
    _lastContextData;

    get hasError() {
        return !!this.errorMessage;
    }

    get hasContent() {
        return !this.isLoading && !this.hasError && !!this._htmlBody;
    }

    get showEmptyState() {
        return !this.isLoading && !this.hasError && !this._htmlBody;
    }

    connectedCallback() {
        this.renderIfReady();
    }

    // Re-render when inputs change
    renderedCallback() {
        const changed =
            this.templateId !== this._lastTemplateId ||
            this.contextData !== this._lastContextData;

        if (changed && this.templateId) {
            this._lastTemplateId   = this.templateId;
            this._lastContextData  = this.contextData;
            this.renderIfReady();
        }

        if (this._htmlBody) {
            const container = this.template.querySelector('.html-preview');
            if (container) {
                // eslint-disable-next-line @lwc/lwc/no-inner-html
                container.innerHTML = this._htmlBody;
            }
        }
    }

    renderIfReady() {
        if (!this.templateId) return;

        const ctx = this._buildContextJson();
        this.isLoading    = true;
        this.errorMessage = '';
        this._htmlBody    = '';

        resolveTemplate({ templateId: this.templateId, contextDataJson: ctx })
            .then(result => {
                if (result.isSuccess) {
                    this.renderedSubject = result.subject || '';
                    this._htmlBody       = result.htmlBody || '';
                } else {
                    this.errorMessage = result.errorMessage || 'Template render failed.';
                }
            })
            .catch(error => {
                this.errorMessage = this._extractError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    clearError() {
        this.errorMessage = '';
    }

    _buildContextJson() {
        // Allow contextData prop to override; fall back to recordId-only context
        if (this.contextData) return this.contextData;
        if (this.recordId) {
            return JSON.stringify({ recordId: this.recordId });
        }
        return '{}';
    }

    _extractError(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'An unexpected error occurred.';
    }
}
