import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSignatureRequests from '@salesforce/apex/WeaveSignatureAuraController.getSignatureRequests';
import cancelSignatureRequest from '@salesforce/apex/WeaveSignatureAuraController.cancelSignatureRequest';

const STATUS_CLASS = {
    'Draft':       'pill pill_draft',
    'Sent':        'pill pill_sent',
    'In Progress': 'pill pill_progress',
    'Completed':   'pill pill_active',
    'Declined':    'pill pill_error',
    'Canceled':    'pill pill_muted',
    'Expired':     'pill pill_muted'
};

const SIGNER_DOT = {
    'Pending':  'dot dot_muted',
    'Sent':     'dot dot_sent',
    'Opened':   'dot dot_opened',
    'Signed':   'dot dot_signed',
    'Declined': 'dot dot_error',
    'Canceled': 'dot dot_muted'
};

const TERMINAL = new Set(['Completed','Declined','Canceled','Expired']);

export default class WeaveSignatureStatus extends LightningElement {
    @api recordId;
    @api signatureRequestId;

    @track requests = [];
    @track isLoading = true;
    @track isCanceling = false;

    get noRequests()  { return !this.isLoading && !this.requests.length; }
    get canCancel()   { return this.requests.some(r => !TERMINAL.has(r.Status__c)); }

    connectedCallback() { this.loadRequests(); }

    loadRequests() {
        this.isLoading = true;
        getSignatureRequests({
            sourceRecordId: this.recordId || null,
            signatureRequestId: this.signatureRequestId || null
        })
        .then(result => {
            this.requests = result.map(r => ({
                ...r,
                statusClass: STATUS_CLASS[r.Status__c] || 'pill pill_muted',
                formattedExpiry: r.Expiry_Date__c ? 'Expires ' + new Date(r.Expiry_Date__c).toLocaleDateString() : '',
                signerRows: (r.Weave_Signers__r?.records || []).map(s => ({
                    ...s,
                    statusClass: STATUS_CLASS[s.Status__c] || 'pill pill_muted',
                    dotClass: SIGNER_DOT[s.Status__c] || 'dot dot_muted',
                    formattedSignedAt: s.Signed_At__c ? new Date(s.Signed_At__c).toLocaleString() : ''
                }))
            }));
        })
        .catch(err => {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: err?.body?.message, variant: 'error' }));
        })
        .finally(() => { this.isLoading = false; });
    }

    handleCancel() {
        const req = this.requests.find(r => !TERMINAL.has(r.Status__c));
        if (!req) return;
        // eslint-disable-next-line no-alert
        const reason = window.prompt('Reason for canceling (optional):') ?? '';
        this.isCanceling = true;
        cancelSignatureRequest({ requestId: req.Id, cancelReason: reason })
        .then(() => {
            this.dispatchEvent(new ShowToastEvent({ title: 'Canceled', message: 'Signature request canceled.', variant: 'success' }));
            this.loadRequests();
        })
        .catch(err => {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: err?.body?.message, variant: 'error' }));
        })
        .finally(() => { this.isCanceling = false; });
    }
}
