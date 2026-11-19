import { LightningElement, api, track } from 'lwc';
import generateCombinedPdf from '@salesforce/apex/WeavePdfController.generateCombinedPdf';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class WeavePdfMerger extends LightningElement {
    @api recordId;

    @track items = [{ key: 1, templateId: '', recordId: '' }];
    @track pdfTitle = 'PDF Packet';
    @track isLoading = false;
    @track errorMessage = '';
    @track successDocumentId = '';

    itemCounter = 1;

    get downloadUrl() {
        if (!this.successDocumentId) return '#';
        return '/sfc/servlet.shepherd/document/download/' + this.successDocumentId;
    }

    connectedCallback() {
        if (this.recordId) {
            this.items = [{ key: 1, templateId: '', recordId: this.recordId }];
        }
    }

    handleAddItem() {
        this.itemCounter++;
        this.items = [...this.items, { key: this.itemCounter, templateId: '', recordId: this.recordId || '' }];
    }

    handleRemoveItem(event) {
        const key = Number(event.currentTarget.dataset.key);
        this.items = this.items.filter(i => i.key !== key);
        if (this.items.length === 0) {
            this.itemCounter++;
            this.items = [{ key: this.itemCounter, templateId: '', recordId: this.recordId || '' }];
        }
    }

    handleItemChange(event) {
        const key = Number(event.currentTarget.dataset.key);
        const field = event.currentTarget.dataset.field;
        this.items = this.items.map(i => i.key === key ? { ...i, [field]: event.detail.value } : i);
    }

    handleTitleChange(event) {
        this.pdfTitle = event.detail.value;
    }

    handleGenerate() {
        this.errorMessage = '';
        this.successDocumentId = '';

        const validItems = this.items.filter(i => i.templateId && i.recordId);
        if (validItems.length === 0) {
            this.errorMessage = 'At least one template with a record ID is required.';
            return;
        }

        const templateIds = validItems.map(i => i.templateId);
        const recordIds = validItems.map(i => i.recordId);

        this.isLoading = true;
        generateCombinedPdf({ templateIds, recordIds, title: this.pdfTitle })
            .then(contentDocumentId => {
                this.successDocumentId = contentDocumentId;
                this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'PDF packet generated.', variant: 'success' }));
            })
            .catch(err => {
                this.errorMessage = (err && err.body && err.body.message) || 'Unable to generate PDF.';
            })
            .finally(() => { this.isLoading = false; });
    }
}
