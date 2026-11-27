import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createSignatureRequest from '@salesforce/apex/WeaveSignatureAuraController.createSignatureRequest';

const SIGNING_MODE_OPTIONS = [
    { label: 'Parallel (all at once)', value: 'Parallel' },
    { label: 'Sequential (one at a time)', value: 'Sequential' }
];

export default class WeaveSignatureSender extends LightningElement {
    @api templateId;
    @api sourceRecordId;
    @api contentVersionId;

    @track isOpen = false;
    @track signers = [];
    @track signingMode = 'Parallel';
    @track expiryDays = 30;
    @track isLoading = false;
    @track errorMessage = '';

    signingModeOptions = SIGNING_MODE_OPTIONS;
    _keyCounter = 0;

    get isSequential() { return this.signingMode === 'Sequential'; }

    @api open() {
        this.isOpen = true;
        this.signers = [];
        this.errorMessage = '';
        this.addSigner();
    }

    addSigner() {
        this._keyCounter++;
        this.signers = [...this.signers, {
            key: this._keyCounter,
            name: '', email: '', role: '',
            signOrder: this.signers.length + 1,
            displayOrder: this.signers.length + 1
        }];
    }

    removeSigner(evt) {
        const idx = parseInt(evt.currentTarget.dataset.index, 10);
        const updated = this.signers.filter((_, i) => i !== idx);
        this.signers = updated.map((s, i) => ({ ...s, signOrder: i + 1, displayOrder: i + 1 }));
    }

    handleModeChange(evt)  { this.signingMode = evt.detail.value; }
    handleInputChange(evt) { this[evt.currentTarget.dataset.field] = evt.detail.value; }

    handleSignerChange(evt) {
        const idx   = parseInt(evt.currentTarget.dataset.index, 10);
        const field = evt.currentTarget.dataset.field;
        this.signers = this.signers.map((s, i) =>
            i === idx ? { ...s, [field]: field === 'signOrder' ? parseInt(evt.detail.value, 10) : evt.detail.value } : s
        );
    }

    handleClose() { this.isOpen = false; }
    clearError()  { this.errorMessage = ''; }

    handleSend() {
        if (!this.validate()) return;
        this.isLoading = true;
        this.errorMessage = '';

        const signerInputs = this.signers.map(s => ({
            name: s.name, email: s.email, role: s.role, signOrder: s.signOrder
        }));

        createSignatureRequest({
            templateId: this.templateId,
            sourceRecordId: this.sourceRecordId,
            contentVersionId: this.contentVersionId || null,
            signingMode: this.signingMode,
            expiryDays: parseInt(this.expiryDays, 10),
            signerInputsJson: JSON.stringify(signerInputs)
        })
        .then(() => {
            this.dispatchEvent(new ShowToastEvent({ title: 'Sent', message: 'Signature request sent to all signers.', variant: 'success' }));
            this.dispatchEvent(new CustomEvent('sent'));
            this.isOpen = false;
        })
        .catch(err => {
            this.errorMessage = err?.body?.message || 'Failed to send signature request.';
        })
        .finally(() => { this.isLoading = false; });
    }

    validate() {
        if (!this.signers.length) { this.errorMessage = 'Add at least one signer.'; return false; }
        for (const s of this.signers) {
            if (!s.name?.trim())  { this.errorMessage = 'All signers need a name.'; return false; }
            if (!s.email?.trim()) { this.errorMessage = 'All signers need an email.'; return false; }
            if (!s.role?.trim())  { this.errorMessage = 'All signers need a role (must match a {{@Role}} tag in the template).'; return false; }
        }
        return true;
    }
}
