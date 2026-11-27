import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSegments from '@salesforce/apex/WeaveRecipientSegmentController.getSegments';
import saveSegment from '@salesforce/apex/WeaveRecipientSegmentController.saveSegment';
import deleteSegment from '@salesforce/apex/WeaveRecipientSegmentController.deleteSegment';
import previewSegmentByData from '@salesforce/apex/WeaveRecipientSegmentController.previewSegmentByData';
import getAvailableObjects from '@salesforce/apex/WeaveTemplateBuilderController.getAvailableObjects';
import getFieldsForObject from '@salesforce/apex/WeaveTemplateBuilderController.getFieldsForObject';

const STATUS_OPTIONS = [
    { label: 'Active', value: 'Active' },
    { label: 'Inactive', value: 'Inactive' }
];

function computeStatusClass(status) {
    if (status === 'Active') return 'status-pill status-pill_active';
    if (status === 'Inactive') return 'status-pill status-pill_inactive';
    return 'status-pill status-pill_draft';
}

export default class WeaveRecipientSegmentManager extends LightningElement {
    @track segments = [];
    @track isLoading = false;
    @track showModal = false;
    @track editRecord = {};
    @track previewData = null;
    @track isPreviewLoading = false;
    @track errorMessage = '';
    @track modalErrorMessage = '';
    @track availableObjects = [];
    @track availableFields = [];
    @track filterStatus = 'All';
    @track searchTerm = '';

    statusOptions = STATUS_OPTIONS;
    _soqlLastCursor = 0;
    _soqlNeedsSync = false;

    get filteredSegments() {
        return this.segments.filter(s => {
            const matchesStatus = this.filterStatus === 'All' || s.Status__c === this.filterStatus;
            const term = this.searchTerm ? this.searchTerm.toLowerCase() : '';
            const matchesSearch = !term ||
                (s.Name && s.Name.toLowerCase().includes(term)) ||
                (s.Object_API_Name__c && s.Object_API_Name__c.toLowerCase().includes(term));
            return matchesStatus && matchesSearch;
        });
    }

    get hasFilteredSegments() { return this.filteredSegments.length > 0; }
    get formTitle() { return this.editRecord.Id ? 'Edit Segment' : 'New Segment'; }
    get filterTabAll() { return 'filter-tab' + (this.filterStatus === 'All' ? ' filter-tab_active' : ''); }
    get filterTabActive() { return 'filter-tab' + (this.filterStatus === 'Active' ? ' filter-tab_active' : ''); }
    get filterTabInactive() { return 'filter-tab' + (this.filterStatus === 'Inactive' ? ' filter-tab_active' : ''); }

    get objectOptions() {
        const opts = [{ label: '-- Select object --', value: '' }];
        (this.availableObjects || []).forEach(o => {
            opts.push({ label: o.label + ' (' + o.apiName + ')', value: o.apiName });
        });
        return opts;
    }

    get emailFieldOptions() {
        const opts = [{ label: '-- Select field --', value: '' }];
        (this.availableFields || [])
            .filter(f => f.dataType === 'EMAIL' || f.dataType === 'STRING')
            .forEach(f => opts.push({ label: f.label + ' (' + f.apiName + ')', value: f.apiName }));
        return opts;
    }

    get nameFieldOptions() {
        const opts = [{ label: '-- Select field --', value: '' }];
        (this.availableFields || [])
            .filter(f => ['STRING', 'TEXTAREA', 'PICKLIST', 'REFERENCE'].includes(f.dataType))
            .forEach(f => opts.push({ label: f.label + ' (' + f.apiName + ')', value: f.apiName }));
        return opts;
    }

    get hasAvailableFields() { return this.availableFields && this.availableFields.length > 0; }
    get hasPreviewData() { return this.previewData !== null; }
    get hasPreviewRecords() { return this.previewData && this.previewData.sampleRecords && this.previewData.sampleRecords.length > 0; }
    get hasMoreThanSample() { return this.previewData && this.previewData.totalCount > (this.previewData.sampleRecords || []).length; }
    get previewButtonLabel() { return this.isPreviewLoading ? 'Loading…' : 'Run Preview'; }

    renderedCallback() {
        if (this._soqlNeedsSync) {
            const ta = this.template.querySelector('.soql-textarea');
            if (ta) {
                ta.value = this.editRecord.SOQL_Filter__c || '';
                this._soqlNeedsSync = false;
            }
        }
    }

    connectedCallback() {
        this.loadSegments();
        this.loadObjects();
    }

    loadSegments() {
        this.isLoading = true;
        this.errorMessage = '';
        getSegments()
            .then(result => {
                this.segments = (result || []).map(s => ({ ...s, statusClass: computeStatusClass(s.Status__c) }));
            })
            .catch(err => {
                this.errorMessage = (err && err.body && err.body.message) || 'Unable to load recipient segments.';
            })
            .finally(() => { this.isLoading = false; });
    }

    loadObjects() {
        getAvailableObjects()
            .then(result => { this.availableObjects = result || []; })
            .catch(() => { this.availableObjects = []; });
    }

    loadFieldsForObject(objectApiName) {
        if (!objectApiName) { this.availableFields = []; return; }
        getFieldsForObject({ objectApiName })
            .then(result => { this.availableFields = result || []; })
            .catch(() => { this.availableFields = []; });
    }

    handleNew() {
        this.editRecord = { Status__c: 'Active' };
        this.availableFields = [];
        this.previewData = null;
        this.modalErrorMessage = '';
        this.showModal = true;
        this._soqlNeedsSync = true;
    }

    handleEdit(event) {
        const segId = event.currentTarget.dataset.segid;
        const seg = this.segments.find(s => s.Id === segId);
        if (!seg) return;
        this.editRecord = { ...seg };
        this.previewData = null;
        this.modalErrorMessage = '';
        this.showModal = true;
        this._soqlNeedsSync = true;
        if (seg.Object_API_Name__c) this.loadFieldsForObject(seg.Object_API_Name__c);
    }

    handleDeleteRow(event) {
        const segId = event.currentTarget.dataset.segid;
        // eslint-disable-next-line no-alert
        if (!confirm('Delete this segment?')) return;
        this.isLoading = true;
        deleteSegment({ segmentId: segId })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({ title: 'Deleted', message: 'Segment deleted.', variant: 'success' }));
                this.loadSegments();
            })
            .catch(err => {
                this.errorMessage = (err && err.body && err.body.message) || 'Unable to delete segment.';
                this.isLoading = false;
            });
    }

    handleObjectChange(event) {
        const objectApiName = event.detail.value;
        this.editRecord = {
            ...this.editRecord,
            Object_API_Name__c: objectApiName || null,
            Email_Field_API_Name__c: null,
            Name_Field_API_Name__c: null,
            SOQL_Filter__c: null
        };
        this.previewData = null;
        this._soqlNeedsSync = true;
        this.loadFieldsForObject(objectApiName);
    }

    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this.editRecord = { ...this.editRecord, [field]: event.detail.value };
    }

    handleSoqlChange(event) {
        this.editRecord = { ...this.editRecord, SOQL_Filter__c: event.target.value };
    }

    handleSoqlBlur(event) {
        this._soqlLastCursor = event.target.selectionStart;
    }

    handleSoqlCursorSave(event) {
        this._soqlLastCursor = event.target.selectionStart;
    }

    handleInsertField(event) {
        const field = event.currentTarget.dataset.field;
        const ta = this.template.querySelector('.soql-textarea');
        const current = ta ? ta.value : (this.editRecord.SOQL_Filter__c || '');
        const pos = this._soqlLastCursor;
        const newVal = current.slice(0, pos) + field + current.slice(pos);
        this.editRecord = { ...this.editRecord, SOQL_Filter__c: newVal };
        if (ta) {
            ta.value = newVal;
            const newCursor = pos + field.length;
            this._soqlLastCursor = newCursor;
            ta.focus();
            ta.setSelectionRange(newCursor, newCursor);
        }
    }

    handleRunPreview() {
        if (!this.editRecord.Object_API_Name__c) {
            this.modalErrorMessage = 'Select an object before previewing.';
            return;
        }
        if (!this.editRecord.Email_Field_API_Name__c) {
            this.modalErrorMessage = 'Select an email field before previewing.';
            return;
        }
        const ta = this.template.querySelector('.soql-textarea');
        const soqlFilter = ta ? ta.value : (this.editRecord.SOQL_Filter__c || '');
        this.editRecord = { ...this.editRecord, SOQL_Filter__c: soqlFilter };
        this.isPreviewLoading = true;
        this.previewData = null;
        this.modalErrorMessage = '';
        previewSegmentByData({
            objectApiName: this.editRecord.Object_API_Name__c,
            emailField: this.editRecord.Email_Field_API_Name__c,
            nameField: this.editRecord.Name_Field_API_Name__c || null,
            soqlFilter: soqlFilter || null
        })
        .then(result => { this.previewData = result; })
        .catch(err => { this.modalErrorMessage = (err && err.body && err.body.message) || 'Unable to preview segment.'; })
        .finally(() => { this.isPreviewLoading = false; });
    }

    handleStatusFilter(event) {
        this.filterStatus = event.currentTarget.dataset.status;
    }

    handleSearch(event) {
        this.searchTerm = event.detail.value;
    }

    handleDismissError() { this.errorMessage = ''; }
    handleDismissModalError() { this.modalErrorMessage = ''; }

    handleSave() {
        if (!this.editRecord.Name) { this.modalErrorMessage = 'Segment name is required.'; return; }
        if (!this.editRecord.Object_API_Name__c) { this.modalErrorMessage = 'Object is required.'; return; }
        if (!this.editRecord.Email_Field_API_Name__c) { this.modalErrorMessage = 'Email field is required.'; return; }
        if (!this.editRecord.Name_Field_API_Name__c) { this.modalErrorMessage = 'Name field is required.'; return; }
        const ta = this.template.querySelector('.soql-textarea');
        if (ta) this.editRecord = { ...this.editRecord, SOQL_Filter__c: ta.value };
        this.modalErrorMessage = '';
        this.isLoading = true;
        saveSegment({ segment: this.editRecord })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Segment saved.', variant: 'success' }));
                this.showModal = false;
                this.editRecord = {};
                this.availableFields = [];
                this.previewData = null;
                this.loadSegments();
            })
            .catch(err => {
                this.modalErrorMessage = (err && err.body && err.body.message) || 'Unable to save segment.';
                this.isLoading = false;
            });
    }

    handleCancel() {
        this.showModal = false;
        this.editRecord = {};
        this.availableFields = [];
        this.modalErrorMessage = '';
        this.previewData = null;
        this._soqlNeedsSync = false;
    }
}
