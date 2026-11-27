import { LightningElement, api, track, wire } from 'lwc';
import getAvailableTemplates from '@salesforce/apex/WeaveEmailTemplateController.getAvailableTemplates';
import getRecipientOptions from '@salesforce/apex/WeaveEmailTemplateController.getRecipientOptions';
import getRelatedAttachments from '@salesforce/apex/WeaveEmailTemplateController.getRelatedAttachments';
import renderEmail from '@salesforce/apex/WeaveEmailTemplateController.renderEmail';
import sendEmail from '@salesforce/apex/WeaveEmailTemplateController.sendEmail';
import scheduleEmail from '@salesforce/apex/WeaveEmailTemplateController.scheduleEmail';
import scheduleRecurringEmail from '@salesforce/apex/WeaveEmailTemplateController.scheduleRecurringEmail';
import getObjectApiNameFromRecordId from '@salesforce/apex/WeaveEmailTemplateController.getObjectApiNameFromRecordId';
import getRecordSummary from '@salesforce/apex/WeaveEmailTemplateController.getRecordSummary';
import getActiveSegments from '@salesforce/apex/WeaveEmailTemplateController.getActiveSegments';
import resolveSegmentRecipients from '@salesforce/apex/WeaveEmailTemplateController.resolveSegmentRecipients';
import generatePdf from '@salesforce/apex/WeaveEmailTemplateController.generatePdf';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import {
    FlowAttributeChangeEvent,
    FlowNavigationFinishEvent
} from 'lightning/flowSupport';
import { CurrentPageReference } from 'lightning/navigation';

const EMAIL_REGEX = /^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$/i;
const VIEW_COMPOSE = 'compose';
const VIEW_PREVIEW = 'preview';
const EMAIL_FONT_FAMILY = '"Salesforce Sans", Arial, sans-serif';
const EMAIL_FONT_SIZE = '13px';
const TAB_COMPOSE = 'compose';
const TAB_SCHEDULE = 'schedule';

export default class WeaveEmailComposer extends LightningElement {
    _recordId;
    _pageReferenceRecordId;
    _isConnected = false;
    _hasInitialized = false;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        if (value) {
            this._recordId = value;
            this.initializeWhenReady();
        }
    }

    @api objectApiName;
    @api flowRecordId;
    @api templateId;
    @api flowMode = false;
    @api hideFlowFooter = false;
    @api finishFlowOnSend = false;
    @api emailSent = false;
    @api cancelled = false;

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        const stateRecordId =
            pageRef?.state?.recordId ||
            pageRef?.state?.c__recordId ||
            pageRef?.attributes?.recordId ||
            null;

        if (stateRecordId) {
            this._pageReferenceRecordId = stateRecordId;
            if (!this._recordId) {
                this._recordId = stateRecordId;
            }
            this.initializeWhenReady();
        }
    }

    @track templates = [];
    @track recipients = [];
    @track manualRecipients = [];
    @track selectedTemplateId;
    @track selectedTemplate;
    @track renderedSubject = '';
    @track renderedBody = '';
    @track plainTextBody = '';
    @track isLoading = false;
    @track errorMessage = '';
    @track hasManualEdits = false;
    @track manualEmail = '';
    @track manualRecipientType = 'To';
    @track attachments = [];
    @track isSending = false;
    @track isScheduling = false;
    @track sendComplete = false;
    @track showManualRecipientForm = false;
    @track recordSummary = {};
    @track currentView = VIEW_COMPOSE;
    @track sectionCollapsed = { recipients: true, attachments: true, subject: true, message: false };
    @track segments = [];
    @track selectedSegmentId = '';
    @track isLoadingSegment = false;
    @track isGeneratingPdf = false;
    @track pdfContentDocumentId = '';

    // Tab state
    @track activeTab = TAB_COMPOSE;

    // Schedule — once
    @track scheduleType = 'once';
    @track scheduleDate = '';
    @track scheduleTime = '09:00';

    // Schedule — recurring
    @track recurringDays = [];
    @track recurringTime = '09:00';
    @track recurringStartDate = '';
    @track recurringEndType = 'noEnd';
    @track recurringEndDate = '';
    @track recurringMaxSends = '';

    manualRecipientCounter = 0;

    // ─── Tab ───────────────────────────────────────────────────────────────────

    get isComposeTab() { return this.activeTab === TAB_COMPOSE; }
    get isScheduleTab() { return this.activeTab === TAB_SCHEDULE; }

    get composeTabClass() {
        return 'composer-tab-btn' + (this.activeTab === TAB_COMPOSE ? ' composer-tab-btn--active' : '');
    }

    get scheduleTabClass() {
        return 'composer-tab-btn' + (this.activeTab === TAB_SCHEDULE ? ' composer-tab-btn--active' : '');
    }

    handleSelectComposeTab() { this.activeTab = TAB_COMPOSE; }
    handleSelectScheduleTab() { this.activeTab = TAB_SCHEDULE; }

    // ─── Schedule options ──────────────────────────────────────────────────────

    get scheduleTypeOptions() {
        return [
            { label: 'Send Once', value: 'once' },
            { label: 'Recurring', value: 'recurring' }
        ];
    }

    get dayOfWeekOptions() {
        return [
            { label: 'Sun', value: 'sun' },
            { label: 'Mon', value: 'mon' },
            { label: 'Tue', value: 'tue' },
            { label: 'Wed', value: 'wed' },
            { label: 'Thu', value: 'thu' },
            { label: 'Fri', value: 'fri' },
            { label: 'Sat', value: 'sat' }
        ];
    }

    get recurringEndTypeOptions() {
        return [
            { label: 'No end date', value: 'noEnd' },
            { label: 'End by date', value: 'endDate' },
            { label: 'Stop after X sends', value: 'maxSends' }
        ];
    }

    get isScheduleOnce() { return this.scheduleType === 'once'; }
    get isScheduleRecurring() { return this.scheduleType === 'recurring'; }
    get isEndByDate() { return this.recurringEndType === 'endDate'; }
    get isEndByMaxSends() { return this.recurringEndType === 'maxSends'; }

    get minScheduleDate() {
        const d = new Date();
        const pad = (n) => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    }

    get disableScheduleOnceButton() {
        return this.disableSendButton || !this.scheduleDate || !this.scheduleTime;
    }

    get disableScheduleRecurringButton() {
        return (
            this.disableSendButton ||
            this.recurringDays.length === 0 ||
            !this.recurringTime ||
            !this.recurringStartDate ||
            (this.isEndByDate && !this.recurringEndDate) ||
            (this.isEndByMaxSends && (!this.recurringMaxSends || Number(this.recurringMaxSends) < 1))
        );
    }

    get disableScheduleButton() {
        return this.isScheduleOnce ? this.disableScheduleOnceButton : this.disableScheduleRecurringButton;
    }

    // ─── Schedule handlers ─────────────────────────────────────────────────────

    handleScheduleTypeChange(event) { this.scheduleType = event.detail.value; }
    handleScheduleDateChange(event) { this.scheduleDate = event.detail.value; this.clearError(); }
    handleScheduleTimeChange(event) { this.scheduleTime = event.detail.value; this.clearError(); }
    handleRecurringDaysChange(event) { this.recurringDays = event.detail.value; this.clearError(); }
    handleRecurringTimeChange(event) { this.recurringTime = event.detail.value; this.clearError(); }
    handleRecurringStartDateChange(event) { this.recurringStartDate = event.detail.value; this.clearError(); }
    handleRecurringEndTypeChange(event) { this.recurringEndType = event.detail.value; this.clearError(); }
    handleRecurringEndDateChange(event) { this.recurringEndDate = event.detail.value; this.clearError(); }
    handleRecurringMaxSendsChange(event) { this.recurringMaxSends = event.detail.value; this.clearError(); }

    // ─── Section collapse ──────────────────────────────────────────────────────

    get isRecipientsCollapsed() { return this.sectionCollapsed.recipients; }
    get isAttachmentsCollapsed() { return this.sectionCollapsed.attachments; }
    get isSubjectCollapsed() { return this.sectionCollapsed.subject; }
    get isMessageCollapsed() { return this.sectionCollapsed.message; }

    get recipientsChevronIcon() { return this.sectionCollapsed.recipients ? 'utility:chevronright' : 'utility:chevrondown'; }
    get attachmentsChevronIcon() { return this.sectionCollapsed.attachments ? 'utility:chevronright' : 'utility:chevrondown'; }
    get subjectChevronIcon() { return this.sectionCollapsed.subject ? 'utility:chevronright' : 'utility:chevrondown'; }
    get messageChevronIcon() { return this.sectionCollapsed.message ? 'utility:chevronright' : 'utility:chevrondown'; }

    get recipientsSectionHeadingClass() { return 'section-heading' + (this.sectionCollapsed.recipients ? ' section-heading--collapsed' : ''); }
    get attachmentsSectionHeadingClass() { return 'section-heading' + (this.sectionCollapsed.attachments ? ' section-heading--collapsed' : ''); }
    get subjectSectionHeadingClass() { return 'section-heading' + (this.sectionCollapsed.subject ? ' section-heading--collapsed' : ''); }
    get messageSectionHeadingClass() { return 'section-heading' + (this.sectionCollapsed.message ? ' section-heading--collapsed' : ''); }

    handleToggleSection(event) {
        const section = event.currentTarget.dataset.section;
        if (!section) return;
        this.sectionCollapsed = { ...this.sectionCollapsed, [section]: !this.sectionCollapsed[section] };
    }

    // ─── Template / record ─────────────────────────────────────────────────────

    get templateOptions() {
        return this.templates.map((template) => ({
            label: template.name,
            value: template.id
        }));
    }

    get hasTemplates() { return this.templates.length > 0; }
    get hasMultipleTemplates() { return this.templates.length > 1; }
    get hasSelectedTemplate() { return Boolean(this.effectiveTemplateId); }
    get isComposeView() { return this.hasSelectedTemplate; }
    get hasNoTemplates() { return !this.isLoading && this.templates.length === 0 && !this.errorMessage; }
    get showAutoSelectedBadge() { return this.templates.length === 1 && Boolean(this.selectedTemplateId); }
    get selectedTemplateName() { return this.selectedTemplate?.name || 'Select a template'; }

    get templateContextLine() {
        if (!this.selectedTemplate) return 'Choose a template to generate this email.';
        return this.selectedTemplate.parentObjectApiName
            ? `Used for ${this.selectedTemplate.parentObjectApiName}`
            : 'Configuration-driven email template';
    }

    get recordDisplayName() { return this.recordSummary?.recordName || this.effectiveRecordId || 'Current record'; }
    get recordContextLine() { return this.recordSummary?.objectLabel || this.objectApiName || 'Record context'; }
    get showSelectedTemplateDescription() { return this.selectedTemplate?.description; }
    get showSelectedTemplateSubject() { return this.selectedTemplate?.subjectTemplate; }

    // ─── Recipients ────────────────────────────────────────────────────────────

    get configuredRecipients() {
        return this.recipients.filter((recipient) => recipient.sourceType !== 'Manual');
    }

    get allSelectedRecipients() {
        return [...(this.configuredRecipients || []), ...(this.manualRecipients || [])].filter(
            (recipient) => recipient && (recipient.selected === true || recipient.required === true)
        );
    }

    get selectedToRecipients() {
        return this.allSelectedRecipients.filter(
            (recipient) => this.normalizeRecipientType(recipient.recipientType) === 'To'
        );
    }

    get selectedCcRecipients() {
        return this.allSelectedRecipients.filter(
            (recipient) => this.normalizeRecipientType(recipient.recipientType) === 'CC'
        );
    }

    get selectedBccRecipients() {
        return this.allSelectedRecipients.filter(
            (recipient) => this.normalizeRecipientType(recipient.recipientType) === 'BCC'
        );
    }

    get toRecipientCards() { return this.selectedToRecipients.map((r) => this.toRecipientCard(r)); }
    get ccRecipientCards() { return this.selectedCcRecipients.map((r) => this.toRecipientCard(r)); }
    get bccRecipientCards() { return this.selectedBccRecipients.map((r) => this.toRecipientCard(r)); }

    get availableRecipientCards() {
        return this.configuredRecipients
            .filter((recipient) => !recipient.selected && !recipient.required)
            .map((recipient) => ({
                ...this.toRecipientCard(recipient),
                addLabel: `Add ${recipient.name || recipient.email}`
            }));
    }

    get hasAvailableRecipients() { return this.availableRecipientCards.length > 0; }
    get hasSelectedToRecipient() { return this.selectedToRecipients.length > 0; }
    get hasRecipientOptions() { return this.configuredRecipients.length > 0; }
    get hasNoRecipientOptions() { return !this.isLoading && !this.hasRecipientOptions; }

    get recipientTypeOptions() {
        return [
            { label: 'To', value: 'To' },
            { label: 'CC', value: 'CC' },
            { label: 'BCC', value: 'BCC' }
        ];
    }

    // ─── Attachments ───────────────────────────────────────────────────────────

    get hasAttachments() { return this.attachments.length > 0; }
    get selectedAttachments() { return this.attachments.filter((a) => a.selected === true); }
    get selectedAttachmentCount() { return this.selectedAttachments.length; }
    get hasSelectedAttachments() { return this.selectedAttachments.length > 0; }

    get toRecipientEmails() { return this.selectedToRecipients.map((r) => r.email); }
    get ccRecipientEmails() { return this.selectedCcRecipients.map((r) => r.email); }
    get bccRecipientEmails() { return this.selectedBccRecipients.map((r) => r.email); }
    get hasCcRecipients() { return this.ccRecipientEmails.length > 0; }
    get hasBccRecipients() { return this.bccRecipientEmails.length > 0; }
    get ccRecipientDisplay() { return this.hasCcRecipients ? this.ccRecipientEmails.join(', ') : 'None'; }
    get bccRecipientDisplay() { return this.hasBccRecipients ? this.bccRecipientEmails.join(', ') : 'None'; }
    get toRecipientDisplay() { return this.toRecipientEmails.length ? this.toRecipientEmails.join(', ') : 'None'; }

    // ─── Send state ────────────────────────────────────────────────────────────

    get disableSendButton() {
        return (
            this.isLoading ||
            this.isSending ||
            this.isScheduling ||
            !this.effectiveTemplateId ||
            !this.hasSelectedToRecipient ||
            String(this.renderedSubject || '').trim().length === 0 ||
            String(this.renderedBody || '').trim().length === 0
        );
    }

    get disablePreviewButton() { return this.disableSendButton; }

    get effectiveTemplateId() {
        return this.selectedTemplateId || this.selectedTemplate?.id || this.templateId || null;
    }

    get effectiveRecordId() {
        const value = this._recordId || this.flowRecordId || this._pageReferenceRecordId || null;
        return value ? String(value).trim() : null;
    }

    get isFlowMode() { return this.flowMode === true || this.flowMode === 'true'; }
    get isQuickActionMode() { return !this.isFlowMode; }
    get shouldFinishFlowOnSend() { return this.finishFlowOnSend === true || this.finishFlowOnSend === 'true'; }
    get hasManualRecipients() { return this.manualRecipients.length > 0; }

    get segmentOptions() {
        const opts = [{ label: '-- Load from Segment --', value: '' }];
        this.segments.forEach(s => opts.push({ label: s.Name, value: s.Id }));
        return opts;
    }

    get hasSegments() { return this.segments.length > 0; }

    get showPdfButtons() {
        return this.selectedTemplate?.templateOutputType === 'Both';
    }

    get pdfDownloadUrl() {
        if (!this.pdfContentDocumentId) return '#';
        return '/sfc/servlet.shepherd/document/download/' + this.pdfContentDocumentId;
    }

    get hasBlankRenderedContent() {
        return !this.isLoading && (!this.renderedSubject || !this.renderedBody);
    }

    // ─── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        this._isConnected = true;
        this.initializeWhenReady();
    }

    async initializeWhenReady() {
        if (!this._isConnected || this._hasInitialized) return;

        const providedRecordId = this._recordId || this.flowRecordId || this._pageReferenceRecordId;
        if (providedRecordId && !this._recordId) {
            this._recordId = providedRecordId;
        }

        if (!this.effectiveRecordId) {
            this.setError('Waiting for record context...');
            return;
        }

        if (!this.objectApiName) {
            await this.resolveObjectApiNameFromRecordId();
        }

        if (!this.objectApiName) {
            this.setError('Object API Name is required and could not be determined from the record.');
            return;
        }

        this._hasInitialized = true;
        this.clearError();
        await this.loadRecordSummary();
        await this.loadTemplates();
    }

    async loadRecordSummary() {
        const recordId = this.effectiveRecordId;
        if (!recordId) return;
        try {
            this.recordSummary = await getRecordSummary({ recordId });
        } catch (error) {
            this.recordSummary = { recordName: recordId, objectLabel: this.objectApiName };
        }
    }

    async resolveObjectApiNameFromRecordId() {
        const recordId = this.effectiveRecordId;
        if (!recordId || this.objectApiName) return;
        try {
            this.objectApiName = await getObjectApiNameFromRecordId({ recordId });
        } catch (error) {
            this.setError(this.getErrorMessage(error) || 'Unable to determine object type from this record.');
        }
    }

    async loadTemplates() {
        if (!this.validateRequiredInputs()) return;

        this.isLoading = true;
        this.clearError();
        this.templates = [];
        const currentTemplateId = this.effectiveTemplateId;

        try {
            const templates = await getAvailableTemplates({ parentObjectApiName: this.objectApiName });
            this.templates = templates || [];
            this.loadSegments();

            const flowTemplate = this.templateId ? this.templates.find((t) => t.id === this.templateId) : null;
            const currentTemplate = currentTemplateId ? this.templates.find((t) => t.id === currentTemplateId) : null;

            if (this.templateId) {
                this.selectedTemplateId = this.templateId;
                this.selectedTemplate = flowTemplate || null;
            } else if (currentTemplate) {
                this.selectedTemplateId = currentTemplate.id;
                this.selectedTemplate = currentTemplate;
            } else if (this.templates.length === 1) {
                this.selectedTemplateId = this.templates[0].id;
                this.selectedTemplate = this.templates[0];
                this.templateId = this.selectedTemplateId;
            } else {
                this.selectedTemplateId = undefined;
                this.selectedTemplate = undefined;
            }

            if (this.effectiveTemplateId) {
                await this.loadCompositionData();
            }
        } catch (error) {
            const message = this.getErrorMessage(error);
            this.setError('Unable to load templates. Please contact your administrator.');
            this.showToast('Unable to load templates', message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleTemplateChange(event) {
        const value = event.detail.value;
        this.selectedTemplateId = value;
        this.templateId = value;
        this.selectedTemplate = this.templates.find((t) => t.id === value) || null;
        this.hasManualEdits = false;
        this.recipients = [];
        this.manualRecipients = [];
        this.attachments = [];
        this.renderedSubject = '';
        this.renderedBody = '';
        this.plainTextBody = '';
        this.showManualRecipientForm = false;
        this.currentView = VIEW_COMPOSE;
        this.clearError();
        if (this.effectiveTemplateId) {
            await this.loadCompositionData();
        }
    }

    async loadCompositionData() {
        await this.loadRecipients();
        await this.loadRelatedAttachments();
        await this.loadPreview(true);
    }

    async loadPreview(forceRefresh) {
        if (!forceRefresh && (this.renderedSubject || this.renderedBody)) return;

        const templateId = this.effectiveTemplateId;
        if (!templateId) {
            this.setError('Please select an email template before previewing.');
            return;
        }

        this.isLoading = true;
        this.clearError();

        try {
            const result = await renderEmail({ templateId, recordId: this.effectiveRecordId });
            this.renderedSubject = result?.subject || '';
            this.renderedBody = this.normalizeEmailHtml(result?.htmlBody || '');
            this.plainTextBody = result?.plainTextBody || '';
            this.hasManualEdits = false;
        } catch (error) {
            const message = this.getErrorMessage(error);
            this.setError(message);
            this.showToast('Unable to render email', message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async loadRecipients() {
        const templateId = this.effectiveTemplateId;
        if (!templateId) {
            this.setError('Please select an email template before continuing.');
            return;
        }

        this.isLoading = true;
        this.clearError();
        this.recipients = [];
        this.manualRecipients = [];

        try {
            const options = await getRecipientOptions({ templateId, recordId: this.effectiveRecordId });
            this.recipients = (options || []).map((recipient, index) => ({
                ...recipient,
                id: recipient.id || `recipient-${index}`,
                localKey: `${recipient.id || 'recipient'}-${index}`,
                selected: recipient.required ? true : Boolean(recipient.selected),
                required: Boolean(recipient.required),
                allowMultiple: Boolean(recipient.allowMultiple),
                recipientType: recipient.recipientType || 'To',
                sourceType: recipient.sourceType || recipient.source || 'Configured'
            })).filter((r) => r.sourceType !== 'Manual');
        } catch (error) {
            const message = this.getErrorMessage(error);
            this.setError(message);
            this.showToast('Unable to load recipients', message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async loadRelatedAttachments() {
        const recordId = this.effectiveRecordId;
        if (!recordId) return;

        try {
            const relatedAttachments = await getRelatedAttachments({ recordId });
            const selectedByDocumentId = new Map(
                (this.attachments || []).map((a) => [a.contentDocumentId, a.selected])
            );
            this.attachments = (relatedAttachments || []).map((attachment) => ({
                ...attachment,
                id: attachment.contentDocumentId,
                displayTitle: this.formatAttachmentTitle(attachment),
                displaySize: this.formatFileSize(attachment.contentSize),
                displayMeta: this.formatAttachmentMeta(attachment),
                selected: selectedByDocumentId.has(attachment.contentDocumentId)
                    ? selectedByDocumentId.get(attachment.contentDocumentId)
                    : attachment.selected !== false,
                source: attachment.source || 'Related'
            }));
        } catch (error) {
            const message = this.getErrorMessage(error);
            this.setError(message);
            this.showToast('Unable to load attachments', message, 'error');
        }
    }

    // ─── Recipient handlers ────────────────────────────────────────────────────

    handleRecipientSelectedChange(event) {
        const recipientId = event.target.dataset.id;
        const selected = event.target.checked;
        this.recipients = this.recipients.map((recipient) => {
            if (recipient.localKey !== recipientId) return recipient;
            if (recipient.required && !selected) {
                this.setError('Required recipients cannot be deselected.');
                return { ...recipient, selected: true };
            }
            this.clearError();
            return { ...recipient, selected };
        });
    }

    handleRecipientTypeChange(event) {
        const recipientId = event.target.dataset.id;
        const recipientType = event.detail.value;
        this.recipients = this.recipients.map((r) =>
            r.localKey === recipientId ? { ...r, recipientType } : r
        );
        this.manualRecipients = this.manualRecipients.map((r) =>
            r.id === recipientId ? { ...r, recipientType } : r
        );
        this.clearError();
    }

    handleManualEmailChange(event) { this.manualEmail = event.detail.value; }
    handleManualTypeChange(event) { this.manualRecipientType = event.detail.value; }

    handleShowManualRecipient() {
        this.showManualRecipientForm = true;
        this.manualRecipientType = this.manualRecipientType || 'To';
        this.clearError();
    }

    handleShowManualRecipientForType(event) {
        this.manualRecipientType = event.target.dataset.type || 'To';
        this.showManualRecipientForm = true;
        this.clearError();
    }

    handleHideManualRecipient() {
        this.showManualRecipientForm = false;
        this.manualEmail = '';
        this.manualRecipientType = 'To';
        this.clearError();
    }

    handleAddManualRecipient() {
        const email = (this.manualEmail || '').trim();
        if (!email) { this.setError('Manual recipient email is required.'); return; }
        if (!this.isValidEmail(email)) {
            this.setError(`Invalid email address: ${email}`);
            return;
        }
        if (this.hasDuplicateRecipientEmail(email)) {
            this.setError(`Recipient already added: ${email}`);
            return;
        }
        this.manualRecipientCounter += 1;
        this.manualRecipients = [
            ...this.manualRecipients,
            {
                id: `manual-${Date.now()}-${this.manualRecipientCounter}`,
                name: email,
                email,
                recipientType: this.manualRecipientType || 'To',
                source: 'Manual',
                selected: true,
                required: false,
                sourceType: 'Manual'
            }
        ];
        this.manualEmail = '';
        this.manualRecipientType = 'To';
        this.showManualRecipientForm = false;
        this.clearError();
    }

    handleRemoveManualRecipient(event) {
        const recipientId = event.target.dataset.id;
        this.manualRecipients = this.manualRecipients.filter((r) => r.id !== recipientId);
        this.clearError();
    }

    handleRemoveRecipient(event) {
        const recipientId = event.target.dataset.id;
        const configured = this.configuredRecipients.find((r) => r.localKey === recipientId);
        if (configured) {
            if (configured.required) {
                this.setError('Required recipients cannot be removed.');
                return;
            }
            this.recipients = this.recipients.map((r) =>
                r.localKey === recipientId ? { ...r, selected: false } : r
            );
        } else {
            this.manualRecipients = this.manualRecipients.filter((r) => r.id !== recipientId);
        }
        this.clearError();
    }

    handleAddConfiguredRecipient(event) {
        const recipientId = event.target.dataset.id;
        this.recipients = this.recipients.map((r) =>
            r.localKey === recipientId ? { ...r, selected: true } : r
        );
        this.clearError();
    }

    // ─── Segments ──────────────────────────────────────────────────────────────

    loadSegments() {
        const objApiName = this.objectApiName || (this.selectedTemplate && this.selectedTemplate.parentObjectApiName) || '';
        getActiveSegments({ objectApiName: objApiName })
            .then(result => { this.segments = result || []; })
            .catch(() => { this.segments = []; });
    }

    handleSegmentChange(event) {
        const segId = event.detail.value;
        this.selectedSegmentId = segId;
        if (!segId) return;
        this.isLoadingSegment = true;
        resolveSegmentRecipients({ segmentId: segId })
            .then(resolved => {
                if (resolved && resolved.length > 0) {
                    const existing = new Set(this.allSelectedRecipients.map(r => (r.email || '').toLowerCase()));
                    const toAdd = resolved.filter(r => r.email && !existing.has(r.email.toLowerCase()));
                    this.manualRecipients = [...this.manualRecipients, ...toAdd.map(r => ({
                        ...r,
                        id: 'seg-' + (++this.manualRecipientCounter) + '-' + (r.id || r.email)
                    }))];
                    this.dispatchEvent(new ShowToastEvent({ title: 'Segment Loaded', message: toAdd.length + ' recipient(s) added.', variant: 'success' }));
                } else {
                    this.dispatchEvent(new ShowToastEvent({ title: 'No Recipients', message: 'No matching recipients found in this segment.', variant: 'warning' }));
                }
                this.selectedSegmentId = '';
            })
            .catch(err => {
                this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: (err && err.body && err.body.message) || 'Unable to load segment.', variant: 'error' }));
                this.selectedSegmentId = '';
            })
            .finally(() => { this.isLoadingSegment = false; });
    }

    // ─── PDF ───────────────────────────────────────────────────────────────────

    handleSavePdf() {
        if (!this.effectiveTemplateId || !this.effectiveRecordId) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: 'Template and record are required.', variant: 'error' }));
            return;
        }
        this.isGeneratingPdf = true;
        this.pdfContentDocumentId = '';
        generatePdf({ templateId: this.effectiveTemplateId, recordId: this.effectiveRecordId })
            .then(docId => {
                this.pdfContentDocumentId = docId;
                this.dispatchEvent(new ShowToastEvent({ title: 'PDF Saved', message: 'PDF has been saved to this record.', variant: 'success' }));
            })
            .catch(err => {
                this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: (err && err.body && err.body.message) || 'Unable to generate PDF.', variant: 'error' }));
            })
            .finally(() => { this.isGeneratingPdf = false; });
    }

    handleDownloadPdf() {
        if (!this.effectiveTemplateId || !this.effectiveRecordId) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: 'Template and record are required.', variant: 'error' }));
            return;
        }
        this.isGeneratingPdf = true;
        this.pdfContentDocumentId = '';
        generatePdf({ templateId: this.effectiveTemplateId, recordId: this.effectiveRecordId })
            .then(docId => {
                this.pdfContentDocumentId = docId;
                const link = document.createElement('a');
                link.href = '/sfc/servlet.shepherd/document/download/' + docId;
                link.target = '_blank';
                document.body.appendChild(link);
                link.click();
                document.body.removeChild(link);
            })
            .catch(err => {
                this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: (err && err.body && err.body.message) || 'Unable to generate PDF.', variant: 'error' }));
            })
            .finally(() => { this.isGeneratingPdf = false; });
    }

    // ─── Attachment handlers ───────────────────────────────────────────────────

    handleAttachmentSelectedChange(event) {
        const contentDocumentId = event.target.dataset.id;
        const selected = event.target.checked;
        this.attachments = this.attachments.map((a) =>
            a.contentDocumentId === contentDocumentId ? { ...a, selected } : a
        );
        this.clearError();
    }

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files || [];
        const existingDocumentIds = new Set(this.attachments.map((a) => a.contentDocumentId));
        const newAttachments = uploadedFiles
            .filter((f) => f.documentId && !existingDocumentIds.has(f.documentId))
            .map((f) => ({
                id: f.documentId,
                contentDocumentId: f.documentId,
                contentVersionId: null,
                title: f.name,
                displayTitle: f.name,
                fileExtension: '',
                contentSize: null,
                displaySize: '',
                displayMeta: 'Uploaded',
                selected: true,
                source: 'Uploaded'
            }));
        this.attachments = [...this.attachments, ...newAttachments];
        if (uploadedFiles.length > 0) {
            this.showToast('Upload complete', `${uploadedFiles.length} file(s) uploaded.`, 'success');
            this.loadRelatedAttachments();
        }
        this.clearError();
    }

    // ─── Compose handlers ──────────────────────────────────────────────────────

    handleSubjectChange(event) {
        this.renderedSubject = event.detail.value;
        this.hasManualEdits = true;
        this.clearError();
    }

    handleBodyChange(event) {
        this.renderedBody = this.normalizeEmailHtml(event.detail.value);
        this.hasManualEdits = true;
        this.clearError();
    }

    async handleRegenerate() {
        if (this.hasManualEdits) {
            const confirmed = window.confirm('Regenerating will overwrite your manual edits. Continue?');
            if (!confirmed) return;
        }
        await this.loadPreview(true);
    }

    // ─── Send ──────────────────────────────────────────────────────────────────

    validateRecipients() {
        for (const recipient of this.allSelectedRecipients) {
            if (!this.isValidEmail(recipient.email)) {
                this.setError(`Invalid email address: ${recipient.email || ''}`);
                return false;
            }
        }
        if (!this.hasSelectedToRecipient) {
            this.setError('At least one To recipient is required.');
            return false;
        }
        this.clearError();
        return true;
    }

    buildSendRecipientPayload() {
        return {
            toRecipients: this.selectedToRecipients.map((r) => this.toRecipientInput(r)),
            ccRecipients: this.selectedCcRecipients.map((r) => this.toRecipientInput(r)),
            bccRecipients: this.selectedBccRecipients.map((r) => this.toRecipientInput(r))
        };
    }

    validatePreview() {
        if (String(this.renderedSubject || '').trim().length === 0) {
            this.setError('Email subject is required.');
            return false;
        }
        if (String(this.renderedBody || '').trim().length === 0) {
            this.setError('Email body is required.');
            return false;
        }
        if (!this.validateRecipients()) return false;
        this.clearError();
        return true;
    }

    buildEmailRequest() {
        const recipientPayload = this.buildSendRecipientPayload();
        const normalizedHtmlBody = this.normalizeEmailHtml(this.renderedBody);
        return {
            templateId: this.effectiveTemplateId || null,
            recordId: this.effectiveRecordId,
            subject: this.renderedSubject,
            htmlBody: normalizedHtmlBody,
            toRecipients: recipientPayload.toRecipients,
            ccRecipients: recipientPayload.ccRecipients,
            bccRecipients: recipientPayload.bccRecipients,
            attachmentContentDocumentIds: this.selectedAttachments.map((a) => a.contentDocumentId),
            storeHistory: null
        };
    }

    async handleSend() {
        if (this.isSending) return;
        this.clearError();
        if (!this.validateRecipients() || !this.validatePreview()) return;

        const recordId = this.effectiveRecordId;
        if (!recordId) { this.setError('Record Id is required.'); return; }

        const request = this.buildEmailRequest();
        this.isSending = true;
        this.isLoading = true;
        this.renderedBody = request.htmlBody;

        try {
            const sendResult = await sendEmail({ request });
            this.emailSent = true;
            this.cancelled = false;
            this.sendComplete = true;
            this.dispatchEvent(new FlowAttributeChangeEvent('emailSent', this.emailSent));
            this.dispatchEvent(new FlowAttributeChangeEvent('cancelled', this.cancelled));
            await this.refreshHostRecord(recordId);
            const warnings = sendResult?.warnings || [];
            this.showToast(
                warnings.length ? 'Email sent with warnings' : 'Success',
                warnings.length ? warnings.join(' ') : 'Email sent successfully.',
                warnings.length ? 'warning' : 'success'
            );
            if (this.isFlowMode && this.shouldFinishFlowOnSend) {
                this.dispatchEvent(new FlowNavigationFinishEvent());
            } else if (this.isQuickActionMode) {
                try { this.dispatchEvent(new CloseActionScreenEvent()); } catch (e) { /* best-effort */ }
            }
        } catch (error) {
            const message = this.getErrorMessage(error) || 'Unable to send email. Please contact your administrator.';
            this.setError(message);
            this.showToast('Unable to send email', message, 'error');
        } finally {
            this.isSending = false;
            this.isLoading = false;
        }
    }

    async handleScheduleSend() {
        if (this.isScheduling) return;
        this.clearError();
        if (!this.validateRecipients() || !this.validatePreview()) return;

        if (this.isScheduleOnce) {
            await this._sendOnce();
        } else {
            await this._sendRecurring();
        }
    }

    async _sendOnce() {
        if (!this.scheduleDate || !this.scheduleTime) {
            this.setError('Please select a date and time for the scheduled send.');
            return;
        }

        const scheduledDate = new Date(`${this.scheduleDate}T${this.scheduleTime}`);
        if (isNaN(scheduledDate.getTime()) || scheduledDate <= new Date(Date.now() + 5 * 60 * 1000)) {
            this.setError('Scheduled time must be at least 5 minutes from now.');
            return;
        }

        const recordId = this.effectiveRecordId;
        if (!recordId) { this.setError('Record Id is required.'); return; }

        const request = this.buildEmailRequest();
        this.isScheduling = true;
        this.isLoading = true;

        try {
            await scheduleEmail({ request, scheduledAtMs: scheduledDate.getTime() });
            const formattedDate = scheduledDate.toLocaleString();
            this.scheduleDate = '';
            this.scheduleTime = '09:00';
            this.showToast('Email Scheduled', `Your email is scheduled to send on ${formattedDate}.`, 'success');
            if (this.isFlowMode && this.shouldFinishFlowOnSend) {
                this.dispatchEvent(new FlowNavigationFinishEvent());
            } else if (this.isQuickActionMode) {
                try { this.dispatchEvent(new CloseActionScreenEvent()); } catch (e) { /* best-effort */ }
            }
        } catch (error) {
            const message = this.getErrorMessage(error) || 'Unable to schedule email. Please contact your administrator.';
            this.setError(message);
            this.showToast('Unable to schedule email', message, 'error');
        } finally {
            this.isScheduling = false;
            this.isLoading = false;
        }
    }

    async _sendRecurring() {
        if (this.recurringDays.length === 0) {
            this.setError('Please select at least one day of the week.');
            return;
        }
        if (!this.recurringTime) {
            this.setError('Please select a time for the recurring send.');
            return;
        }
        if (!this.recurringStartDate) {
            this.setError('Please select a start date.');
            return;
        }
        if (this.isEndByDate && !this.recurringEndDate) {
            this.setError('Please select an end date.');
            return;
        }
        if (this.isEndByMaxSends && (!this.recurringMaxSends || Number(this.recurringMaxSends) < 1)) {
            this.setError('Please enter a valid number of sends (minimum 1).');
            return;
        }

        const recordId = this.effectiveRecordId;
        if (!recordId) { this.setError('Record Id is required.'); return; }

        const request = this.buildEmailRequest();
        const recurringConfigJson = JSON.stringify({
            daysOfWeek: this.recurringDays,
            timeOfDay: this.recurringTime,
            startDate: this.recurringStartDate,
            endType: this.recurringEndType,
            endDate: this.isEndByDate ? this.recurringEndDate : null,
            maxSends: this.isEndByMaxSends ? Number(this.recurringMaxSends) : null
        });

        this.isScheduling = true;
        this.isLoading = true;

        try {
            await scheduleRecurringEmail({ request, recurringConfigJson });
            this.showToast(
                'Recurring Schedule Created',
                `Email will send on selected days starting ${this.recurringStartDate}.`,
                'success'
            );
            this.recurringDays = [];
            this.recurringStartDate = '';
            this.recurringEndDate = '';
            this.recurringMaxSends = '';
            this.recurringEndType = 'noEnd';
            this.activeTab = TAB_COMPOSE;
            if (this.isFlowMode && this.shouldFinishFlowOnSend) {
                this.dispatchEvent(new FlowNavigationFinishEvent());
            } else if (this.isQuickActionMode) {
                try { this.dispatchEvent(new CloseActionScreenEvent()); } catch (e) { /* best-effort */ }
            }
        } catch (error) {
            const message = this.getErrorMessage(error) || 'Unable to create recurring schedule. Please contact your administrator.';
            this.setError(message);
            this.showToast('Unable to schedule email', message, 'error');
        } finally {
            this.isScheduling = false;
            this.isLoading = false;
        }
    }

    // ─── Misc ──────────────────────────────────────────────────────────────────

    async refreshHostRecord(recordId) {
        if (!recordId) return;
        try {
            await notifyRecordUpdateAvailable([{ recordId }]);
            this.dispatchEvent(new RefreshEvent());
        } catch (e) { /* best-effort */ }
    }

    handleCancel() {
        this.cancelled = true;
        this.emailSent = false;
        this.dispatchEvent(new FlowAttributeChangeEvent('cancelled', this.cancelled));
        this.dispatchEvent(new FlowAttributeChangeEvent('emailSent', this.emailSent));
        if (this.isFlowMode) {
            this.dispatchEvent(new FlowNavigationFinishEvent());
        } else if (this.isQuickActionMode) {
            try { this.dispatchEvent(new CloseActionScreenEvent()); } catch (e) {
                this.showToast('Cancelled', 'Email sending was cancelled.', 'info');
            }
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    setError(message) { this.errorMessage = message; }
    clearError() { this.errorMessage = ''; }

    validateRequiredInputs() {
        if (!this.effectiveRecordId) {
            this.setError('Record Id is required.');
            return false;
        }
        if (!this.objectApiName) {
            this.setError('Object API Name is required and could not be determined from the record.');
            return false;
        }
        return true;
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }

    isValidEmail(email) {
        return Boolean(email && EMAIL_REGEX.test(email.trim()));
    }

    hasDuplicateRecipientEmail(email) {
        const normalized = String(email || '').trim().toLowerCase();
        return this.allSelectedRecipients.some(
            (r) => String(r.email || '').trim().toLowerCase() === normalized
        );
    }

    toRecipientInput(recipient) {
        return {
            name: recipient.name,
            email: recipient.email,
            recipientType: this.normalizeRecipientType(recipient.recipientType)
        };
    }

    normalizeRecipientType(value) {
        const normalized = String(value || 'To').trim().toUpperCase();
        if (normalized === 'CC') return 'CC';
        if (normalized === 'BCC') return 'BCC';
        return 'To';
    }

    toRecipientCard(recipient) {
        const displayName = recipient.name || recipient.email || 'Recipient';
        const source = recipient.source || recipient.sourceType || 'Manual';
        const detailParts = [];
        if (recipient.email && recipient.email !== displayName) detailParts.push(recipient.email);
        if (source) detailParts.push(source);
        return {
            ...recipient,
            cardKey: recipient.localKey || recipient.id,
            displayName,
            detailText: detailParts.join(' - '),
            initials: this.getInitials(displayName, recipient.email),
            recipientType: this.normalizeRecipientType(recipient.recipientType)
        };
    }

    getInitials(name, email) {
        const source = String(name || email || '?').trim();
        if (!source) return '?';
        const words = source.replace(/[^A-Z0-9@._ -]/gi, '').split(/\s+/).filter(Boolean);
        if (words.length >= 2) return `${words[0][0]}${words[1][0]}`.toUpperCase();
        return source.substring(0, 2).toUpperCase();
    }

    formatAttachmentTitle(attachment) {
        const title = attachment?.title || 'Untitled file';
        const ext = attachment?.fileExtension;
        if (!ext || title.toLowerCase().endsWith(`.${ext.toLowerCase()}`)) return title;
        return `${title}.${ext}`;
    }

    formatFileSize(bytes) {
        if (!bytes && bytes !== 0) return '';
        if (bytes < 1024) return `${bytes} B`;
        if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
        return `${(bytes / 1048576).toFixed(1)} MB`;
    }

    formatAttachmentMeta(attachment) {
        const source = attachment?.source || 'Related';
        const size = this.formatFileSize(attachment?.contentSize);
        return size ? `${source} - ${size}` : source;
    }

    normalizeEmailHtml(html) {
        if (!html) return '';
        if (typeof document === 'undefined') return html;
        const container = document.createElement('div');
        container.innerHTML = html;
        this.ensureStandardEmailWrapper(container);
        this.applyStandardEmailTypography(container);
        return container.innerHTML;
    }

    ensureStandardEmailWrapper(container) {
        const firstElement = container.firstElementChild;
        const hasSingleStandardWrapper =
            container.childNodes.length === 1 &&
            firstElement?.tagName === 'DIV' &&
            firstElement.style.fontSize === EMAIL_FONT_SIZE &&
            firstElement.style.fontFamily?.includes('Salesforce Sans');
        if (hasSingleStandardWrapper) return;
        const wrapper = document.createElement('div');
        while (container.firstChild) wrapper.appendChild(container.firstChild);
        container.appendChild(wrapper);
    }

    applyStandardEmailTypography(root) {
        const elements = [root, ...Array.from(root.querySelectorAll('*'))];
        elements.forEach((element) => {
            if (!element?.style) return;
            element.style.fontFamily = EMAIL_FONT_FAMILY;
            element.style.fontSize = EMAIL_FONT_SIZE;
            element.style.lineHeight = '1.5';
            if (/^H[1-6]$/i.test(element.tagName)) {
                element.style.fontWeight = '700';
                element.style.margin = '0 0 0.5rem';
            }
        });
    }
}
