import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableFlows        from '@salesforce/apex/WeaveTemplateBuilderController.getAvailableFlows';
import getDataCloudConnectors   from '@salesforce/apex/WeaveTemplateBuilderController.getDataCloudConnectors';
import getDataCloudAttributes   from '@salesforce/apex/WeaveTemplateBuilderController.getDataCloudAttributes';
import validateTemplateMergeFields from '@salesforce/apex/WeaveTemplateBuilderController.validateTemplateMergeFields';

const CHANNEL_OPTIONS = [
    { label: 'Salesforce Email',                value: 'Salesforce Email' },
    { label: 'Salesforce Email and Document',   value: 'Salesforce Email and Document' },
    { label: 'All Channels',                    value: 'All Channels' },
];

let _rowId = 0;
function nextId() { return ++_rowId; }

export default class WeaveDataSourceEditor extends LightningElement {
    /** Template HTML content — used for validation */
    @api templateContent = '';
    @api parentObjectApiName;

    @track templateChannels = 'Salesforce Email';
    @track flowVarRows = [];
    @track dcRefRows   = [];
    @track flowOptions = [{ label: '— any flow —', value: '' }];
    @track dcObjectOptions = [];
    @track dcConnectors = [];
    @track isLoadingFlows = true;
    @track isLoadingDc    = true;
    @track dataCloudEnabled = false;
    @track validationResult = null;
    @track isValidating = false;

    channelOptions = CHANNEL_OPTIONS;

    // ── Wire: load flows ──────────────────────────────────────────────────────

    @wire(getAvailableFlows)
    wiredFlows({ data, error }) {
        this.isLoadingFlows = false;
        if (data) {
            const opts = data.map(f => ({ label: f.label, value: f.apiName }));
            this.flowOptions = [{ label: '— any flow —', value: '' }, ...opts];
        }
        if (error) {
            // Non-fatal: flow picker shows only the blank option
        }
    }

    // ── Wire: load Data Cloud connectors ──────────────────────────────────────

    @wire(getDataCloudConnectors)
    wiredDc({ data, error }) {
        this.isLoadingDc = false;
        if (data) {
            this.dcConnectors = data;
            this.dataCloudEnabled = data.length > 0;
            this.dcObjectOptions = data.map(c => ({ label: c.label + ' (' + c.objectType + ')', value: c.apiName }));
        }
        if (error) {
            this.dataCloudEnabled = false;
        }
    }

    // ── Computed ──────────────────────────────────────────────────────────────

    get hasFlowVars()  { return this.flowVarRows.length > 0; }
    get hasDcRefs()    { return this.dcRefRows.length > 0; }
    get errorCount()   { return this.validationResult ? this.validationResult.errors.length : 0; }
    get warningCount() { return this.validationResult ? this.validationResult.warnings.length : 0; }
    get hasValidationWarnings() { return this.warningCount > 0; }
    get validateButtonLabel() { return this.isValidating ? 'Validating…' : 'Validate'; }

    // ── Handlers: channels ────────────────────────────────────────────────────

    handleChannelsChange(event) {
        this.templateChannels = event.detail.value;
        this._fireChange();
    }

    // ── Handlers: flow variables ──────────────────────────────────────────────

    handleAddFlowVar() {
        const id = nextId();
        this.flowVarRows = [...this.flowVarRows, {
            id, varName: '', flowApiName: '', mergeTag: '{{Flow.}}'
        }];
    }

    handleFlowVarChange(event) {
        const id    = Number(event.currentTarget.dataset.id);
        const field = event.currentTarget.dataset.field;
        const val   = event.detail.value;
        this.flowVarRows = this.flowVarRows.map(row => {
            if (row.id !== id) return row;
            const updated = { ...row, [field]: val };
            updated.mergeTag = updated.varName ? '{{Flow.' + updated.varName + '}}' : '{{Flow.}}';
            return updated;
        });
        this._fireChange();
    }

    handleRemoveFlowVar(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.flowVarRows = this.flowVarRows.filter(r => r.id !== id);
        this._fireChange();
    }

    // ── Handlers: Data Cloud refs ─────────────────────────────────────────────

    handleAddDcRef() {
        const id = nextId();
        this.dcRefRows = [...this.dcRefRows, {
            id, objectApiName: '', attributeName: '', mergeTag: '{{DataCloud..}}',
            attributeOptions: []
        }];
    }

    handleDcRefChange(event) {
        const id    = Number(event.currentTarget.dataset.id);
        const field = event.currentTarget.dataset.field;
        const val   = event.detail.value;

        this.dcRefRows = this.dcRefRows.map(row => {
            if (row.id !== id) return row;
            const updated = { ...row, [field]: val };
            if (field === 'objectApiName') {
                updated.attributeName   = '';
                updated.attributeOptions = this._getAttrOptions(val);
            }
            updated.mergeTag = this._buildDcTag(updated.objectApiName, updated.attributeName);
            return updated;
        });
        this._fireChange();
    }

    handleRemoveDcRef(event) {
        const id = Number(event.currentTarget.dataset.id);
        this.dcRefRows = this.dcRefRows.filter(r => r.id !== id);
        this._fireChange();
    }

    // ── Validation ────────────────────────────────────────────────────────────

    handleValidate() {
        if (!this.templateContent) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'No Content', message: 'Template content is empty — nothing to validate.',
                variant: 'warning'
            }));
            return;
        }
        this.isValidating = true;
        this.validationResult = null;
        validateTemplateMergeFields({
            templateContent: this.templateContent,
            parentObjectApiName: this.parentObjectApiName || null
        })
        .then(result => { this.validationResult = result; })
        .catch(err => {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Validation Failed',
                message: err.body ? err.body.message : 'An error occurred during validation.',
                variant: 'error'
            }));
        })
        .finally(() => { this.isValidating = false; });
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /** Returns current data source config as a plain object for the parent to store */
    @api
    getConfig() {
        return {
            templateChannels: this.templateChannels,
            flowVariables: this.flowVarRows.map(r => ({ varName: r.varName, flowApiName: r.flowApiName })),
            dataCloudRefs: this.dcRefRows.map(r => ({ objectApiName: r.objectApiName, attributeName: r.attributeName }))
        };
    }

    @api
    loadConfig(config) {
        if (!config) return;
        if (config.templateChannels) this.templateChannels = config.templateChannels;
        if (Array.isArray(config.flowVariables)) {
            this.flowVarRows = config.flowVariables.map(v => ({
                id: nextId(), varName: v.varName || '', flowApiName: v.flowApiName || '',
                mergeTag: v.varName ? '{{Flow.' + v.varName + '}}' : '{{Flow.}}'
            }));
        }
        if (Array.isArray(config.dataCloudRefs)) {
            this.dcRefRows = config.dataCloudRefs.map(r => ({
                id: nextId(),
                objectApiName: r.objectApiName || '', attributeName: r.attributeName || '',
                attributeOptions: this._getAttrOptions(r.objectApiName),
                mergeTag: this._buildDcTag(r.objectApiName, r.attributeName)
            }));
        }
    }

    // ── Utilities ─────────────────────────────────────────────────────────────

    _getAttrOptions(objectApiName) {
        if (!objectApiName) return [];
        const connector = this.dcConnectors.find(c => c.apiName === objectApiName);
        if (!connector || !connector.attributes) return [];
        return connector.attributes.map(a => ({ label: a.label + ' (' + a.fieldType + ')', value: a.apiName }));
    }

    _buildDcTag(obj, attr) {
        if (!obj && !attr) return '{{DataCloud..}}';
        return '{{DataCloud.' + (obj || '') + '.' + (attr || '') + '}}';
    }

    _fireChange() {
        this.dispatchEvent(new CustomEvent('configchange', { detail: this.getConfig() }));
    }
}
