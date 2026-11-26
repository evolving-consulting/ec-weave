import { LightningElement, api, track } from 'lwc';
import generateCombinedPdf from '@salesforce/apex/WeavePdfController.generateCombinedPdf';
import getPackets from '@salesforce/apex/WeavePacketController.getPackets';
import generatePacket from '@salesforce/apex/WeavePacketController.generatePacket';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class WeavePdfMerger extends LightningElement {
    @api recordId;

    // Ad-hoc tab
    @track items = [{ key: 1, templateId: '', recordId: '' }];
    @track pdfTitle = 'PDF Packet';

    // Packet tab
    @track packets = [];
    @track selectedPacketId = '';
    @track packetRecordId = '';
    @track packetsLoaded = false;

    // Shared
    @track activeTab = 'adhoc';
    @track isLoading = false;
    @track errorMessage = '';
    @track successDocumentId = '';

    itemCounter = 1;

    // ── Computed ──────────────────────────────────────────────────────────────

    get downloadUrl() {
        return this.successDocumentId
            ? '/sfc/servlet.shepherd/document/download/' + this.successDocumentId
            : '#';
    }

    get tabAdhocClass() {
        return this.activeTab === 'adhoc' ? 'tab-btn tab-btn_active' : 'tab-btn';
    }

    get tabPacketClass() {
        return this.activeTab === 'packet' ? 'tab-btn tab-btn_active' : 'tab-btn';
    }

    get isAdhocTab() { return this.activeTab === 'adhoc'; }
    get isPacketTab() { return this.activeTab === 'packet'; }

    get packetOptions() {
        return this.packets.map(p => ({
            label: p.name + (p.status === 'Draft' ? ' (Draft)' : ''),
            value: p.id
        }));
    }

    get noPackets() { return this.packets.length === 0; }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        if (this.recordId) {
            this.items = [{ key: 1, templateId: '', recordId: this.recordId }];
            this.packetRecordId = this.recordId;
        }
    }

    // ── Tab switch ────────────────────────────────────────────────────────────

    handleTabSwitch(event) {
        this.activeTab = event.currentTarget.dataset.tab;
        this.errorMessage = '';
        this.successDocumentId = '';
        if (this.activeTab === 'packet' && !this.packetsLoaded) {
            this.loadPackets();
        }
    }

    loadPackets() {
        getPackets()
            .then(result => {
                this.packets = result;
                this.packetsLoaded = true;
            })
            .catch(err => {
                this.errorMessage = err.body?.message || 'Could not load packets.';
            });
    }

    // ── Ad-hoc tab ────────────────────────────────────────────────────────────

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

    handleTitleChange(event) { this.pdfTitle = event.detail.value; }

    handleGenerate() {
        this.errorMessage = '';
        this.successDocumentId = '';
        const validItems = this.items.filter(i => i.templateId && i.recordId);
        if (validItems.length === 0) {
            this.errorMessage = 'At least one template with a record ID is required.';
            return;
        }
        this.isLoading = true;
        generateCombinedPdf({
            templateIds: validItems.map(i => i.templateId),
            recordIds: validItems.map(i => i.recordId),
            title: this.pdfTitle
        })
            .then(contentDocumentId => {
                this.successDocumentId = contentDocumentId;
                this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'PDF packet generated.', variant: 'success' }));
            })
            .catch(err => { this.errorMessage = err.body?.message || 'Unable to generate PDF.'; })
            .finally(() => { this.isLoading = false; });
    }

    // ── Packet tab ────────────────────────────────────────────────────────────

    handlePacketChange(event) { this.selectedPacketId = event.detail.value; }
    handlePacketRecordIdChange(event) { this.packetRecordId = event.detail.value; }

    handleGeneratePacket() {
        this.errorMessage = '';
        this.successDocumentId = '';
        if (!this.selectedPacketId) {
            this.errorMessage = 'Select a packet before generating.';
            return;
        }
        if (!this.packetRecordId) {
            this.errorMessage = 'A source record ID is required.';
            return;
        }
        this.isLoading = true;
        generatePacket({ packetId: this.selectedPacketId, sourceRecordId: this.packetRecordId })
            .then(contentDocumentId => {
                this.successDocumentId = contentDocumentId;
                this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'PDF packet generated.', variant: 'success' }));
            })
            .catch(err => { this.errorMessage = err.body?.message || 'Unable to generate packet PDF.'; })
            .finally(() => { this.isLoading = false; });
    }
}
