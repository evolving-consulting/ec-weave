import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplates            from '@salesforce/apex/WeaveTemplateBuilderController.getTemplates';
import getActiveEmailTemplates from '@salesforce/apex/WeaveTemplateBuilderController.getActiveEmailTemplates';
import getFieldsForObject      from '@salesforce/apex/WeaveTemplateBuilderController.getFieldsForObject';
import getBulkSends            from '@salesforce/apex/WeaveTemplateBuilderController.getBulkSends';
import createBulkSend          from '@salesforce/apex/WeaveTemplateBuilderController.createBulkSend';
import countBulkSendRecords    from '@salesforce/apex/WeaveTemplateBuilderController.countBulkSendRecords';
import cancelScheduledSend     from '@salesforce/apex/WeaveTemplateBuilderController.cancelScheduledSend';

function statusClass(s) {
    if (s === 'Sent')     return 'status-pill status-pill_active';
    if (s === 'Pending')  return 'status-pill status-pill_draft';
    if (s === 'Running')  return 'status-pill status-pill_draft';
    if (s === 'Failed')   return 'status-pill status-pill_inactive';
    if (s === 'Partial')  return 'status-pill status-pill_draft';
    if (s === 'Cancelled')return 'status-pill status-pill_inactive';
    return 'status-pill';
}

function formatDt(isoStr) {
    if (!isoStr) return '—';
    try {
        return new Date(isoStr).toLocaleString(undefined, {
            month: 'short', day: 'numeric', year: 'numeric',
            hour: 'numeric', minute: '2-digit'
        });
    } catch(e) { return isoStr; }
}

export default class WeaveBulkSendManager extends LightningElement {

    // ── list state ────────────────────────────────────────────────────────
    @track rows = [];
    @track isLoading   = false;
    @track errorMessage = '';
    @track filterStatus = 'All';
    @track searchTerm   = '';

    // ── create form state ─────────────────────────────────────────────────
    @track isCreating  = false;
    @track currentStep = 1;
    @track isSaving    = false;
    @track isLoadingFields = false;

    @track form = {
        templateId: '', templateName: '', outputType: '',
        objectApiName: '', objectLabel: '',
        emailTemplateId: '', emailTemplateName: '',
        documentAction: 'documentOnly',
        scheduleMode: 'once',
        scheduleDate: '', scheduleTime: '09:00',
        recurringDays: [], recurringTime: '09:00',
        recurringStartDate: '', recurringEndType: 'noEnd',
        recurringEndDate: '', recurringMaxSends: '',
        batchSize: 20,
        filterConditions: [],
    };
    @track objectFields = [];
    @track recordCount  = null;

    // ── raw option lists ─────────────────────────────────────────────────
    _allTemplates = [];
    _emailTemplates = [];

    connectedCallback() { this.loadBulkSends(); }

    // ── data loading ─────────────────────────────────────────────────────
    loadBulkSends() {
        this.isLoading = true;
        getBulkSends()
            .then(data => {
                this.rows = (data || []).map(r => ({
                    ...r,
                    statusClass:         statusClass(r.status),
                    scheduledAtFormatted: formatDt(r.scheduledAt),
                    canCancel:           r.status === 'Pending',
                }));
            })
            .catch(e => { this.errorMessage = e.body?.message || 'Could not load bulk sends.'; })
            .finally(() => { this.isLoading = false; });
    }

    // ── computed list ─────────────────────────────────────────────────────
    get filteredRows() {
        let result = this.rows;
        if (this.filterStatus !== 'All') result = result.filter(r => r.status === this.filterStatus);
        if (this.searchTerm) {
            const q = this.searchTerm.toLowerCase();
            result = result.filter(r => (r.templateName || '').toLowerCase().includes(q));
        }
        return result;
    }
    get hasRows() { return this.filteredRows.length > 0; }

    // ── filter tab classes ────────────────────────────────────────────────
    _filterTab(s) { return 'filter-tab-btn' + (this.filterStatus === s ? ' filter-tab-btn_active' : ''); }
    get filterTabAll()     { return this._filterTab('All'); }
    get filterTabPending() { return this._filterTab('Pending'); }
    get filterTabRunning() { return this._filterTab('Running'); }
    get filterTabSent()    { return this._filterTab('Sent'); }
    get filterTabFailed()  { return this._filterTab('Failed'); }

    // ── step state ────────────────────────────────────────────────────────
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }

    // Document template: outputType from template is 'Document' or 'Both'
    get isDocumentTemplate() { return this.form.outputType === 'Document' || this.form.outputType === 'Both'; }
    // needsEmailTemplate: Email+PDF original type, OR document+email sub-option chosen
    get needsEmailTemplate() {
        if (this.form.outputType === 'Email + PDF') return true;
        if (this.isDocumentTemplate && this.form.documentAction === 'documentEmail') return true;
        return false;
    }

    get docActionTabDocument() { return 'filter-tab-btn' + (this.form.documentAction === 'documentOnly' ? ' filter-tab-btn_active' : ''); }
    get docActionTabEmail()    { return 'filter-tab-btn' + (this.form.documentAction === 'documentEmail' ? ' filter-tab-btn_active' : ''); }

    // Schedule mode
    get isScheduleOnce()      { return this.form.scheduleMode === 'once'; }
    get isScheduleRecurring() { return this.form.scheduleMode === 'recurring'; }
    get schedModeTabOnce()     { return 'filter-tab-btn' + (this.form.scheduleMode === 'once'      ? ' filter-tab-btn_active' : ''); }
    get schedModeTabRecurring(){ return 'filter-tab-btn' + (this.form.scheduleMode === 'recurring' ? ' filter-tab-btn_active' : ''); }
    get isRecurringEndByDate()     { return this.form.recurringEndType === 'endDate'; }
    get isRecurringEndByMaxSends() { return this.form.recurringEndType === 'maxSends'; }

    get dayOfWeekOptions() {
        return [
            { label: 'Sun', value: 'sun' }, { label: 'Mon', value: 'mon' },
            { label: 'Tue', value: 'tue' }, { label: 'Wed', value: 'wed' },
            { label: 'Thu', value: 'thu' }, { label: 'Fri', value: 'fri' },
            { label: 'Sat', value: 'sat' }
        ];
    }
    get recurringEndTypeOptions() {
        return [
            { label: 'No end', value: 'noEnd' },
            { label: 'End on date', value: 'endDate' },
            { label: 'Stop after X sends', value: 'maxSends' }
        ];
    }
    get scheduleModeSummary() {
        if (this.form.scheduleMode === 'recurring') {
            const days = (this.form.recurringDays || []).join(', ');
            return 'Recurring — ' + (days || '(no days selected)') + ' at ' + (this.form.recurringTime || '09:00');
        }
        return 'Send Once — ' + (this.form.scheduleDate || '(no date)') + ' at ' + (this.form.scheduleTime || '09:00');
    }

    _stepCls(n) { return 'step-label' + (this.currentStep === n ? ' step-label_active' : (this.currentStep > n ? ' step-label_done' : '')); }
    get stepClass1() { return this._stepCls(1); }
    get stepClass2() { return this._stepCls(2); }
    get stepClass3() { return this._stepCls(3); }

    get step1Invalid() {
        if (!this.form.templateId) return true;
        if (this.needsEmailTemplate && !this.form.emailTemplateId) return true;
        return false;
    }

    get hasFilterConditions() { return this.form.filterConditions && this.form.filterConditions.length > 0; }
    get filterConditionCount() { return this.form.filterConditions ? this.form.filterConditions.length : 0; }

    // ── template options ──────────────────────────────────────────────────
    get templateOptions() {
        return this._allTemplates
            .filter(t => t.status === 'Active')
            .map(t => ({
                label: t.name + (t.templateOutputType ? '  (' + t.templateOutputType + ')' : ''),
                value: t.id
            }));
    }
    get emailTemplateOptions() {
        return this._emailTemplates.map(t => ({ label: t.name, value: t.id }));
    }

    // ── handlers: list ────────────────────────────────────────────────────
    handleStatusFilter(evt) { this.filterStatus = evt.currentTarget.dataset.status; }
    handleSearch(evt)        { this.searchTerm = evt.detail.value; }
    handleDismissError()     { this.errorMessage = ''; }

    handleCancel(evt) {
        const id = evt.currentTarget.dataset.id;
        cancelScheduledSend({ scheduledSendId: id })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({ title: 'Cancelled', message: 'Bulk send cancelled.', variant: 'success' }));
                this.loadBulkSends();
            })
            .catch(e => { this.errorMessage = e.body?.message || 'Could not cancel.'; });
    }

    // ── handlers: create form ────────────────────────────────────────────
    handleNew() {
        this.form = {
            templateId: '', templateName: '', outputType: '',
            objectApiName: '', objectLabel: '',
            emailTemplateId: '', emailTemplateName: '',
            documentAction: 'documentOnly',
            scheduleMode: 'once',
            scheduleDate: '', scheduleTime: '09:00',
            recurringDays: [], recurringTime: '09:00',
            recurringStartDate: '', recurringEndType: 'noEnd',
            recurringEndDate: '', recurringMaxSends: '',
            batchSize: 20, filterConditions: []
        };
        this.objectFields = [];
        this.recordCount  = null;
        this.currentStep  = 1;
        this.isCreating   = true;
        this._loadTemplatesIfNeeded();
    }
    handleCancelCreate() { this.isCreating = false; }

    _loadTemplatesIfNeeded() {
        if (this._allTemplates.length) return;
        getTemplates()
            .then(data => { this._allTemplates = data || []; })
            .catch(() => {});
        getActiveEmailTemplates()
            .then(data => { this._emailTemplates = data || []; })
            .catch(() => {});
    }

    handleTemplateChange(evt) {
        const id = evt.detail.value;
        const tmpl = this._allTemplates.find(t => t.id === id);
        if (!tmpl) return;
        const rawType = tmpl.templateOutputType || 'Email';
        this.form = {
            ...this.form,
            templateId:    id,
            templateName:  tmpl.name,
            outputType:    rawType,
            objectApiName: tmpl.parentObjectApiName || '',
            objectLabel:   tmpl.parentObjectLabel   || tmpl.parentObjectApiName || '',
            emailTemplateId:   '',
            emailTemplateName: '',
            documentAction: 'documentOnly',
        };
    }

    handleDocumentAction(evt) {
        const action = evt.currentTarget.dataset.action;
        this.form = { ...this.form, documentAction: action, emailTemplateId: '', emailTemplateName: '' };
    }

    handleEmailTemplateChange(evt) {
        const id = evt.detail.value;
        const tmpl = this._emailTemplates.find(t => t.id === id);
        this.form = { ...this.form, emailTemplateId: id, emailTemplateName: tmpl ? tmpl.name : '' };
    }

    handleStep1Next() {
        if (this.step1Invalid) return;
        this.currentStep = 2;
        this._loadFieldsForObject();
    }

    _loadFieldsForObject() {
        if (!this.form.objectApiName) return;
        this.isLoadingFields = true;
        getFieldsForObject({ objectApiName: this.form.objectApiName })
            .then(data => { this.objectFields = data || []; })
            .catch(() => { this.objectFields = []; })
            .finally(() => { this.isLoadingFields = false; });
    }

    handleFilterChange(evt) {
        this.form = { ...this.form, filterConditions: evt.detail.conditions };
        this._refreshCount();
    }

    _countDebounceTimer;
    _refreshCount() {
        clearTimeout(this._countDebounceTimer);
        this._countDebounceTimer = setTimeout(() => {
            const condJson = JSON.stringify(this.form.filterConditions);
            countBulkSendRecords({ objectApiName: this.form.objectApiName, filterConditionsJson: condJson })
                .then(count => { this.recordCount = count; })
                .catch(() => { this.recordCount = null; });
        }, 600);
    }

    handleStep2Next() { this.currentStep = 3; }
    handleStepBack()  { this.currentStep = this.currentStep - 1; }

    handleScheduleModeChange(evt) { this.form = { ...this.form, scheduleMode: evt.currentTarget.dataset.mode }; }
    handleScheduleDateChange(evt) { this.form = { ...this.form, scheduleDate: evt.detail.value }; }
    handleScheduleTimeChange(evt) { this.form = { ...this.form, scheduleTime: evt.detail.value }; }
    handleRecurringDaysChange(evt)     { this.form = { ...this.form, recurringDays: evt.detail.value }; }
    handleRecurringTimeChange(evt)     { this.form = { ...this.form, recurringTime: evt.detail.value }; }
    handleRecurringStartDateChange(evt){ this.form = { ...this.form, recurringStartDate: evt.detail.value }; }
    handleRecurringEndTypeChange(evt)  { this.form = { ...this.form, recurringEndType: evt.detail.value }; }
    handleRecurringEndDateChange(evt)  { this.form = { ...this.form, recurringEndDate: evt.detail.value }; }
    handleRecurringMaxSendsChange(evt) { this.form = { ...this.form, recurringMaxSends: evt.detail.value }; }
    handleBatchSizeChange(evt)         { this.form = { ...this.form, batchSize: parseInt(evt.detail.value, 10) || 20 }; }

    handleSave() {
        // Resolve effective output type
        let effectiveOutputType = this.form.outputType;
        if (this.isDocumentTemplate) {
            effectiveOutputType = this.form.documentAction === 'documentEmail' ? 'Email + PDF' : 'PDF';
        }

        const isRecurring = this.form.scheduleMode === 'recurring';

        // Validate schedule inputs
        if (!isRecurring) {
            if (!this.form.scheduleDate || !this.form.scheduleTime) {
                this.errorMessage = 'Please set a scheduled date and time.';
                return;
            }
        } else {
            if (!this.form.recurringDays || this.form.recurringDays.length === 0) {
                this.errorMessage = 'Select at least one day of the week.';
                return;
            }
            if (!this.form.recurringStartDate) {
                this.errorMessage = 'Select a start date for the recurring send.';
                return;
            }
        }

        this.isSaving = true;
        this.errorMessage = '';

        let recurringConfigJson = null;
        if (isRecurring) {
            recurringConfigJson = JSON.stringify({
                daysOfWeek: this.form.recurringDays,
                timeOfDay:  this.form.recurringTime || '09:00',
                startDate:  this.form.recurringStartDate,
                endType:    this.form.recurringEndType,
                endDate:    this.form.recurringEndType === 'endDate'   ? this.form.recurringEndDate   : null,
                maxSends:   this.form.recurringEndType === 'maxSends'  ? Number(this.form.recurringMaxSends) : null,
            });
        }

        const payload = {
            templateId:           this.form.templateId,
            emailTemplateId:      (this.needsEmailTemplate ? this.form.emailTemplateId : null) || null,
            outputType:           effectiveOutputType,
            scheduleMode:         this.form.scheduleMode,
            scheduledAt:          isRecurring ? null : (this.form.scheduleDate + 'T' + this.form.scheduleTime),
            recurringConfigJson:  recurringConfigJson,
            filterConditionsJson: JSON.stringify(this.form.filterConditions),
            batchSize:            this.form.batchSize,
        };
        createBulkSend({ bulkSendJson: JSON.stringify(payload) })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Scheduled', message: 'Bulk send scheduled.', variant: 'success'
                }));
                this.loadBulkSends();
                this.isCreating = false;
            })
            .catch(e => { this.errorMessage = e.body?.message || 'Could not schedule bulk send.'; })
            .finally(() => { this.isSaving = false; });
    }
}
