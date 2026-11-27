import { LightningElement, api, track } from 'lwc';
import generateCombinedPdf from '@salesforce/apex/WeavePdfController.generateCombinedPdf';
import getPackets from '@salesforce/apex/WeavePacketController.getPackets';
import generatePacket from '@salesforce/apex/WeavePacketController.generatePacket';
import createPublicLink from '@salesforce/apex/WeavePdfController.createPublicLink';
import revokePublicLink from '@salesforce/apex/WeavePdfController.revokePublicLink';
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
    @track successContentVersionId = '';

    // Share state
    @track shareUrl = '';
    @track shareDownloadUrl = '';
    @track shareDistributionId = '';
    @track shareExpiryDays = 0;
    @track isSharing = false;
    @track shareExpiry = '';

    itemCounter = 1;

    // ── Computed ──────────────────────────────────────────────────────────────

    get downloadUrl() {
        return this.successDocumentId
            ? '/sfc/servlet.shepherd/document/download/' + this.successDocumentId
            : '#';
    }

    get hasShareUrl() { return !!this.shareUrl; }
    get showSharePanel() { return !!this.successDocumentId; }

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
        this.successContentVersionId = '';
        this._clearShare();
        if (this.activeTab === 'packet' && !this.packetsLoaded) {
            this.loadPackets();
        }
    }

    _clearShare() {
        this.shareUrl = '';
        this.shareDownloadUrl = '';
        this.shareDistributionId = '';
        this.shareExpiryDays = 0;
        this.shareExpiry = '';
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
        this.successContentVersionId = '';
        this._clearShare();
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
            .then(result => {
                // result is ContentDocumentId — we need ContentVersionId for sharing
                this.successDocumentId = result;
                this.successContentVersionId = null; // resolved lazily via share button
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
        this._clearShare();
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

    // ── Share ─────────────────────────────────────────────────────────────────

    handleExpiryDaysChange(event) {
        this.shareExpiryDays = parseInt(event.detail.value, 10) || 0;
    }

    handleCreateShare() {
        this.isSharing = true;
        this.errorMessage = '';
        createPublicLink({ contentDocumentId: this.successDocumentId, expirationDays: this.shareExpiryDays })
            .then(result => {
                this.shareUrl          = result.publicUrl;
                this.shareDownloadUrl  = result.downloadUrl;
                this.shareDistributionId = result.distributionId;
                this.shareExpiry       = result.expiryDate
                    ? new Date(result.expiryDate).toLocaleDateString()
                    : '';
            })
            .catch(err => { this.errorMessage = err.body?.message || 'Unable to create public link.'; })
            .finally(() => { this.isSharing = false; });
    }

    handleCopyLink() {
        navigator.clipboard.writeText(this.shareUrl)
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({ title: 'Copied', message: 'Link copied to clipboard.', variant: 'success' }));
            })
            .catch(() => {
                this.dispatchEvent(new ShowToastEvent({ title: 'Copy failed', message: 'Please copy the link manually.', variant: 'warning' }));
            });
    }

    handleRevokeShare() {
        if (!this.shareDistributionId) return;
        this.isSharing = true;
        revokePublicLink({ contentDistributionId: this.shareDistributionId })
            .then(() => {
                this._clearShare();
                this.dispatchEvent(new ShowToastEvent({ title: 'Revoked', message: 'Public link removed.', variant: 'success' }));
            })
            .catch(err => { this.errorMessage = err.body?.message || 'Unable to revoke link.'; })
            .finally(() => { this.isSharing = false; });
    }
}
