import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getActiveSegments from '@salesforce/apex/WeaveRecipientSegmentController.getActiveSegments';
import saveSegment from '@salesforce/apex/WeaveRecipientSegmentController.saveSegment';
import deleteSegment from '@salesforce/apex/WeaveRecipientSegmentController.deleteSegment';
import previewSegmentCount from '@salesforce/apex/WeaveRecipientSegmentController.previewSegmentCount';
import getAvailableObjects from '@salesforce/apex/WeaveTemplateBuilderController.getAvailableObjects';
import getFieldsForObject from '@salesforce/apex/WeaveTemplateBuilderController.getFieldsForObject';

const COLUMNS = [
    { label: 'Name', fieldName: 'Name', type: 'text' },
    { label: 'Object', fieldName: 'Object_API_Name__c', type: 'text' },
    { label: 'Email Field', fieldName: 'Email_Field_API_Name__c', type: 'text' },
    { label: 'SOQL Filter', fieldName: 'SOQL_Filter__c', type: 'text', wrapText: true },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit', name: 'edit' },
                { label: 'Preview Count', name: 'preview' },
                { label: 'Delete', name: 'delete' }
            ]
        }
    }
];

const STATUS_OPTIONS = [
    { label: 'Active', value: 'Active' },
    { label: 'Inactive', value: 'Inactive' }
];

export default class WeaveRecipientSegmentManager extends LightningElement {
    @track segments = [];
    @track isLoading = false;
    @track isEditing = false;
    @track editRecord = {};
    @track previewResult = null;
    @track errorMessage = '';
    @track availableObjects = [];
    @track availableFields = [];

    columns = COLUMNS;
    statusOptions = STATUS_OPTIONS;

    get hasSegments() {
        return this.segments.length > 0;
    }

    get formTitle() {
        return this.editRecord.Id ? 'Edit Segment' : 'New Segment';
    }

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
            .forEach(f => {
                opts.push({ label: f.label + ' (' + f.apiName + ')', value: f.apiName });
            });
        return opts;
    }

    get nameFieldOptions() {
        const opts = [{ label: '-- Select field --', value: '' }];
        (this.availableFields || [])
            .filter(f => ['STRING', 'TEXTAREA', 'PICKLIST', 'REFERENCE'].includes(f.dataType))
            .forEach(f => {
                opts.push({ label: f.label + ' (' + f.apiName + ')', value: f.apiName });
            });
        return opts;
    }

    connectedCallback() {
        this.loadSegments();
        this.loadObjects();
    }

    loadSegments() {
        this.isLoading = true;
        this.errorMessage = '';
        getActiveSegments({ objectApiName: null })
            .then(result => { this.segments = result || []; })
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
        this.previewResult = null;
        this.isEditing = true;
    }

    handleObjectChange(event) {
        const objectApiName = event.detail.value;
        this.editRecord = {
            ...this.editRecord,
            Object_API_Name__c: objectApiName || null,
            Email_Field_API_Name__c: null,
            Name_Field_API_Name__c: null
        };
        this.loadFieldsForObject(objectApiName);
    }

    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        this.editRecord = { ...this.editRecord, [field]: event.detail.value };
    }

    handleRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if (action === 'edit') {
            this.editRecord = { ...row };
            this.previewResult = null;
            this.isEditing = true;
            if (row.Object_API_Name__c) {
                this.loadFieldsForObject(row.Object_API_Name__c);
            }
        } else if (action === 'delete') {
            this.handleDelete(row.Id);
        } else if (action === 'preview') {
            this.handlePreview(row.Id);
        }
    }

    handleDelete(segmentId) {
        // eslint-disable-next-line no-alert
        if (!confirm('Delete this segment?')) return;
        this.isLoading = true;
        deleteSegment({ segmentId })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({ title: 'Deleted', message: 'Segment deleted.', variant: 'success' }));
                this.loadSegments();
            })
            .catch(err => {
                this.errorMessage = (err && err.body && err.body.message) || 'Unable to delete segment.';
                this.isLoading = false;
            });
    }

    handlePreview(segmentId) {
        this.isLoading = true;
        this.previewResult = null;
        previewSegmentCount({ segmentId })
            .then(count => { this.previewResult = count; })
            .catch(err => {
                this.errorMessage = (err && err.body && err.body.message) || 'Unable to preview segment.';
            })
            .finally(() => { this.isLoading = false; });
    }

    handleSave() {
        if (!this.editRecord.Name) { this.errorMessage = 'Segment name is required.'; return; }
        if (!this.editRecord.Object_API_Name__c) { this.errorMessage = 'Object is required.'; return; }
        if (!this.editRecord.Email_Field_API_Name__c) { this.errorMessage = 'Email field is required.'; return; }
        this.errorMessage = '';
        this.isLoading = true;
        saveSegment({ segment: this.editRecord })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Segment saved.', variant: 'success' }));
                this.isEditing = false;
                this.editRecord = {};
                this.availableFields = [];
                this.loadSegments();
            })
            .catch(err => {
                this.errorMessage = (err && err.body && err.body.message) || 'Unable to save segment.';
                this.isLoading = false;
            });
    }

    handleCancel() {
        this.isEditing = false;
        this.editRecord = {};
        this.availableFields = [];
        this.errorMessage = '';
    }
}
