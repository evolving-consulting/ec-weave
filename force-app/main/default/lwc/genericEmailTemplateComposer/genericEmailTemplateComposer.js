import { LightningElement, api, track, wire } from 'lwc';
import getAvailableTemplates from '@salesforce/apex/GenericEmailTemplateController.getAvailableTemplates';
import getRecipientOptions from '@salesforce/apex/GenericEmailTemplateController.getRecipientOptions';
import getRelatedAttachments from '@salesforce/apex/GenericEmailTemplateController.getRelatedAttachments';
import renderEmail from '@salesforce/apex/GenericEmailTemplateController.renderEmail';
import sendEmail from '@salesforce/apex/GenericEmailTemplateController.sendEmail';
import getObjectApiNameFromRecordId from '@salesforce/apex/GenericEmailTemplateController.getObjectApiNameFromRecordId';
import getRecordSummary from '@salesforce/apex/GenericEmailTemplateController.getRecordSummary';
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

export default class GenericEmailTemplateComposer extends LightningElement {
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
    @track sendComplete = false;
    @track showManualRecipientForm = false;
    @track recordSummary = {};
    @track currentView = VIEW_COMPOSE;

    manualRecipientCounter = 0;

    get templateOptions() {
        return this.templates.map((template) => ({
            label: template.name,
            value: template.id
        }));
    }

    get hasTemplates() {
        return this.templates.length > 0;
    }

    get hasMultipleTemplates() {
        return this.templates.length > 1;
    }

    get hasSelectedTemplate() {
        return Boolean(this.effectiveTemplateId);
    }

    get isComposeView() {
        return this.hasSelectedTemplate && this.currentView === VIEW_COMPOSE;
    }

    get isPreviewView() {
        return this.hasSelectedTemplate && this.currentView === VIEW_PREVIEW;
    }

    get hasNoTemplates() {
        return !this.isLoading && this.templates.length === 0 && !this.errorMessage;
    }

    get showAutoSelectedBadge() {
        return this.templates.length === 1 && Boolean(this.selectedTemplateId);
    }

    get selectedTemplateName() {
        return this.selectedTemplate?.name || 'Select a template';
    }

    get templateContextLine() {
        if (!this.selectedTemplate) {
            return 'Choose a template to generate this email.';
        }
        return this.selectedTemplate.parentObjectApiName
            ? `Used for ${this.selectedTemplate.parentObjectApiName}`
            : 'Configuration-driven email template';
    }

    get recordDisplayName() {
        return this.recordSummary?.recordName || this.effectiveRecordId || 'Current record';
    }

    get recordContextLine() {
        return this.recordSummary?.objectLabel || this.objectApiName || 'Record context';
    }

    get showSelectedTemplateDescription() {
        return this.selectedTemplate?.description;
    }

    get showSelectedTemplateSubject() {
        return this.selectedTemplate?.subjectTemplate;
    }

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

    get toRecipientCards() {
        return this.selectedToRecipients.map((recipient) => this.toRecipientCard(recipient));
    }

    get ccRecipientCards() {
        return this.selectedCcRecipients.map((recipient) => this.toRecipientCard(recipient));
    }

    get bccRecipientCards() {
        return this.selectedBccRecipients.map((recipient) => this.toRecipientCard(recipient));
    }

    get availableRecipientCards() {
        return this.configuredRecipients
            .filter((recipient) => !recipient.selected && !recipient.required)
            .map((recipient) => ({
                ...this.toRecipientCard(recipient),
                addLabel: `Add ${recipient.name || recipient.email}`
            }));
    }

    get hasAvailableRecipients() {
        return this.availableRecipientCards.length > 0;
    }

    get hasSelectedToRecipient() {
        return this.selectedToRecipients.length > 0;
    }

    get hasRecipientOptions() {
        return this.configuredRecipients.length > 0;
    }

    get hasNoRecipientOptions() {
        return !this.isLoading && !this.hasRecipientOptions;
    }

    get recipientTypeOptions() {
        return [
            { label: 'To', value: 'To' },
            { label: 'CC', value: 'CC' },
            { label: 'BCC', value: 'BCC' }
        ];
    }

    get hasAttachments() {
        return this.attachments.length > 0;
    }

    get selectedAttachments() {
        return this.attachments.filter((attachment) => attachment.selected === true);
    }

    get selectedAttachmentCount() {
        return this.selectedAttachments.length;
    }

    get hasSelectedAttachments() {
        return this.selectedAttachments.length > 0;
    }

    get toRecipientEmails() {
        return this.selectedToRecipients.map((recipient) => recipient.email);
    }

    get ccRecipientEmails() {
        return this.selectedCcRecipients.map((recipient) => recipient.email);
    }

    get bccRecipientEmails() {
        return this.selectedBccRecipients.map((recipient) => recipient.email);
    }

    get hasCcRecipients() {
        return this.ccRecipientEmails.length > 0;
    }

    get hasBccRecipients() {
        return this.bccRecipientEmails.length > 0;
    }

    get ccRecipientDisplay() {
        return this.hasCcRecipients ? this.ccRecipientEmails.join(', ') : 'None';
    }

    get bccRecipientDisplay() {
        return this.hasBccRecipients ? this.bccRecipientEmails.join(', ') : 'None';
    }

    get toRecipientDisplay() {
        return this.toRecipientEmails.length ? this.toRecipientEmails.join(', ') : 'None';
    }

    get disableSendButton() {
        return (
            this.isLoading ||
            this.isSending ||
            !this.effectiveTemplateId ||
            !this.hasSelectedToRecipient ||
            String(this.renderedSubject || '').trim().length === 0 ||
            String(this.renderedBody || '').trim().length === 0
        );
    }

    get disablePreviewButton() {
        return this.disableSendButton;
    }

    get effectiveTemplateId() {
        return this.selectedTemplateId || this.selectedTemplate?.id || this.templateId || null;
    }

    get effectiveRecordId() {
        const value = this._recordId || this.flowRecordId || this._pageReferenceRecordId || null;
        return value ? String(value).trim() : null;
    }

    get isFlowMode() {
        return this.flowMode === true || this.flowMode === 'true';
    }

    get isQuickActionMode() {
        return !this.isFlowMode;
    }

    get shouldFinishFlowOnSend() {
        return this.finishFlowOnSend === true || this.finishFlowOnSend === 'true';
    }

    get hasManualRecipients() {
        return this.manualRecipients.length > 0;
    }

    get hasBlankRenderedContent() {
        return !this.isLoading && (!this.renderedSubject || !this.renderedBody);
    }

    connectedCallback() {
        this._isConnected = true;
        this.initializeWhenReady();
    }

    async initializeWhenReady() {
        if (!this._isConnected || this._hasInitialized) {
            return;
        }

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
        if (!recordId) {
            return;
        }

        try {
            this.recordSummary = await getRecordSummary({ recordId });
        } catch (error) {
            this.recordSummary = {
                recordName: recordId,
                objectLabel: this.objectApiName
            };
        }
    }

    async resolveObjectApiNameFromRecordId() {
        const recordId = this.effectiveRecordId;
        if (!recordId || this.objectApiName) {
            return;
        }

        try {
            this.objectApiName = await getObjectApiNameFromRecordId({ recordId });
        } catch (error) {
            const message = this.getErrorMessage(error) || 'Unable to determine object type from this record.';
            this.setError(message);
        }
    }

    async loadTemplates() {
        if (!this.validateRequiredInputs()) {
            return;
        }

        this.isLoading = true;
        this.clearError();
        this.templates = [];
        const currentTemplateId = this.effectiveTemplateId;

        try {
            const templates = await getAvailableTemplates({
                parentObjectApiName: this.objectApiName
            });
            this.templates = templates || [];

            const flowTemplate = this.templateId
                ? this.templates.find((template) => template.id === this.templateId)
                : null;
            const currentTemplate = currentTemplateId
                ? this.templates.find((template) => template.id === currentTemplateId)
                : null;

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
        this.selectedTemplate = this.templates.find((template) => template.id === value) || null;
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
        if (!forceRefresh && (this.renderedSubject || this.renderedBody)) {
            return;
        }

        const templateId = this.effectiveTemplateId;

        if (!templateId) {
            const message = 'Please select an email template before previewing.';
            this.setError(message);
            this.showToast('Template required', message, 'error');
            return;
        }

        this.isLoading = true;
        this.clearError();

        try {
            const result = await renderEmail({
                templateId,
                recordId: this.effectiveRecordId
            });
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
            const message = 'Please select an email template before continuing.';
            this.setError(message);
            this.showToast('Template required', message, 'error');
            return;
        }

        this.isLoading = true;
        this.clearError();
        this.recipients = [];
        this.manualRecipients = [];

        try {
            const options = await getRecipientOptions({
                templateId,
                recordId: this.effectiveRecordId
            });
            const normalizedOptions = (options || []).map((recipient, index) => ({
                ...recipient,
                id: recipient.id || `recipient-${index}`,
                localKey: `${recipient.id || 'recipient'}-${index}`,
                selected: recipient.required ? true : Boolean(recipient.selected),
                required: Boolean(recipient.required),
                allowMultiple: Boolean(recipient.allowMultiple),
                recipientType: recipient.recipientType || 'To',
                sourceType: recipient.sourceType || recipient.source || 'Configured'
            }));

            this.recipients = normalizedOptions.filter((recipient) => recipient.sourceType !== 'Manual');
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
        if (!recordId) {
            return;
        }

        try {
            const relatedAttachments = await getRelatedAttachments({ recordId });
            const selectedByDocumentId = new Map(
                (this.attachments || []).map((attachment) => [attachment.contentDocumentId, attachment.selected])
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

    handleRecipientSelectedChange(event) {
        const recipientId = event.target.dataset.id;
        const selected = event.target.checked;

        this.recipients = this.recipients.map((recipient) => {
            if (recipient.localKey !== recipientId) {
                return recipient;
            }
            if (recipient.required && !selected) {
                this.setError('Required recipients cannot be deselected.');
                this.showToast('Required recipient', 'Required recipients cannot be deselected.', 'error');
                return { ...recipient, selected: true };
            }
            this.clearError();
            return { ...recipient, selected };
        });
    }

    handleRecipientTypeChange(event) {
        const recipientId = event.target.dataset.id;
        const recipientType = event.detail.value;
        this.recipients = this.recipients.map((recipient) =>
            recipient.localKey === recipientId ? { ...recipient, recipientType } : recipient
        );
        this.manualRecipients = this.manualRecipients.map((recipient) =>
            recipient.id === recipientId ? { ...recipient, recipientType } : recipient
        );
        this.clearError();
    }

    handleManualEmailChange(event) {
        this.manualEmail = event.detail.value;
    }

    handleManualTypeChange(event) {
        this.manualRecipientType = event.detail.value;
    }

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
        if (!email) {
            this.setError('Manual recipient email is required.');
            return;
        }
        if (!this.isValidEmail(email)) {
            const message = `Invalid email address: ${email}`;
            this.setError(message);
            this.showToast('Invalid email', message, 'error');
            return;
        }
        if (this.hasDuplicateRecipientEmail(email)) {
            const message = `Recipient already added: ${email}`;
            this.setError(message);
            this.showToast('Duplicate recipient', message, 'error');
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
        this.manualRecipients = this.manualRecipients.filter((recipient) => recipient.id !== recipientId);
        this.clearError();
    }

    handleRemoveRecipient(event) {
        const recipientId = event.target.dataset.id;
        const configuredRecipient = this.configuredRecipients.find((recipient) => recipient.localKey === recipientId);
        if (configuredRecipient) {
            if (configuredRecipient.required) {
                this.setError('Required recipients cannot be removed.');
                this.showToast('Required recipient', 'Required recipients cannot be removed.', 'error');
                return;
            }
            this.recipients = this.recipients.map((recipient) =>
                recipient.localKey === recipientId ? { ...recipient, selected: false } : recipient
            );
        } else {
            this.manualRecipients = this.manualRecipients.filter((recipient) => recipient.id !== recipientId);
        }
        this.clearError();
    }

    handleAddConfiguredRecipient(event) {
        const recipientId = event.target.dataset.id;
        this.recipients = this.recipients.map((recipient) =>
            recipient.localKey === recipientId ? { ...recipient, selected: true } : recipient
        );
        this.clearError();
    }

    handleAttachmentSelectedChange(event) {
        const contentDocumentId = event.target.dataset.id;
        const selected = event.target.checked;
        this.attachments = this.attachments.map((attachment) =>
            attachment.contentDocumentId === contentDocumentId ? { ...attachment, selected } : attachment
        );
        this.clearError();
    }

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files || [];
        const existingDocumentIds = new Set(this.attachments.map((attachment) => attachment.contentDocumentId));
        const uploadedAttachments = uploadedFiles
            .filter((file) => file.documentId && !existingDocumentIds.has(file.documentId))
            .map((file) => ({
                id: file.documentId,
                contentDocumentId: file.documentId,
                contentVersionId: null,
                title: file.name,
                displayTitle: file.name,
                fileExtension: '',
                contentSize: null,
                displaySize: '',
                displayMeta: 'Uploaded',
                selected: true,
                source: 'Uploaded'
            }));

        this.attachments = [...this.attachments, ...uploadedAttachments];
        if (uploadedFiles.length > 0) {
            this.showToast('Upload complete', `${uploadedFiles.length} file${uploadedFiles.length === 1 ? '' : 's'} uploaded.`, 'success');
            this.loadRelatedAttachments();
        }
        this.clearError();
    }

    validateRecipients() {
        for (const recipient of this.allSelectedRecipients) {
            if (!this.isValidEmail(recipient.email)) {
                const message = `Invalid email address: ${recipient.email || ''}`;
                this.setError(message);
                this.showToast('Invalid email', message, 'error');
                return false;
            }
        }

        if (!this.hasSelectedToRecipient) {
            const message = 'At least one To recipient is required.';
            this.setError(message);
            this.showToast('Recipient required', message, 'error');
            return false;
        }

        this.clearError();
        return true;
    }

    buildSendRecipientPayload() {
        const toRecipients = this.selectedToRecipients.map((recipient) => this.toRecipientInput(recipient));
        const ccRecipients = this.selectedCcRecipients.map((recipient) => this.toRecipientInput(recipient));
        const bccRecipients = this.selectedBccRecipients.map((recipient) => this.toRecipientInput(recipient));
        return { toRecipients, ccRecipients, bccRecipients };
    }

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

    handleContinueToPreview() {
        this.clearError();
        if (!this.validatePreview()) {
            return;
        }
        this.currentView = VIEW_PREVIEW;
    }

    handleBackToCompose() {
        this.currentView = VIEW_COMPOSE;
        this.clearError();
    }

    async handleRegenerate() {
        if (this.hasManualEdits) {
            const confirmed = window.confirm('Regenerating will overwrite your manual edits. Continue?');
            if (!confirmed) {
                return;
            }
        }

        await this.loadPreview(true);
    }

    validatePreview() {
        if (String(this.renderedSubject || '').trim().length === 0) {
            const message = 'Email subject is required.';
            this.setError(message);
            this.showToast('Subject required', message, 'error');
            return false;
        }
        if (String(this.renderedBody || '').trim().length === 0) {
            const message = 'Email body is required.';
            this.setError(message);
            this.showToast('Body required', message, 'error');
            return false;
        }
        if (!this.validateRecipients()) {
            return false;
        }

        this.clearError();
        return true;
    }

    async handleSend() {
        if (this.isSending) {
            return;
        }

        this.clearError();
        if (!this.validateRecipients() || !this.validatePreview()) {
            return;
        }

        const templateId = this.effectiveTemplateId;
        const recordId = this.effectiveRecordId;

        if (!recordId) {
            const message = 'Record Id is required.';
            this.setError(message);
            this.showToast('Unable to send email', message, 'error');
            return;
        }

        const recipientPayload = this.buildSendRecipientPayload();
        const normalizedHtmlBody = this.normalizeEmailHtml(this.renderedBody);
        const request = {
            templateId: templateId || null,
            recordId: recordId,
            subject: this.renderedSubject,
            htmlBody: normalizedHtmlBody,
            toRecipients: recipientPayload.toRecipients,
            ccRecipients: recipientPayload.ccRecipients,
            bccRecipients: recipientPayload.bccRecipients,
            attachmentContentDocumentIds: this.selectedAttachments.map((attachment) => attachment.contentDocumentId),
            storeHistory: null
        };

        this.isSending = true;
        this.isLoading = true;
        this.renderedBody = normalizedHtmlBody;

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
                try {
                    this.dispatchEvent(new CloseActionScreenEvent());
                } catch (closeError) {
                    // Record page usage does not always have an action modal to close.
                }
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

    async refreshHostRecord(recordId) {
        if (!recordId) {
            return;
        }

        try {
            await notifyRecordUpdateAvailable([{ recordId }]);
            this.dispatchEvent(new RefreshEvent());
        } catch (refreshError) {
            // Refresh is best-effort; the email has already been sent successfully.
            console.warn('DCE host record refresh failed:', refreshError);
        }
    }

    handleCancel() {
        this.cancelled = true;
        this.emailSent = false;
        this.dispatchEvent(new FlowAttributeChangeEvent('cancelled', this.cancelled));
        this.dispatchEvent(new FlowAttributeChangeEvent('emailSent', this.emailSent));

        if (this.isFlowMode) {
            this.dispatchEvent(new FlowNavigationFinishEvent());
        } else if (this.isQuickActionMode) {
            try {
                this.dispatchEvent(new CloseActionScreenEvent());
            } catch (closeError) {
                this.showToast('Cancelled', 'Email sending was cancelled.', 'info');
            }
        } else {
            this.showToast('Cancelled', 'Email sending was cancelled.', 'info');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    setError(message) {
        this.errorMessage = message;
    }

    clearError() {
        this.errorMessage = '';
    }

    validateRequiredInputs() {
        if (!this.effectiveRecordId) {
            this.setError('Record Id is required. Pass recordId into this component from Flow.');
            return false;
        }
        if (!this.objectApiName) {
            this.setError('Object API Name is required and could not be determined from the record.');
            return false;
        }
        return true;
    }

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'Unexpected error';
    }

    isValidEmail(email) {
        return Boolean(email && EMAIL_REGEX.test(email.trim()));
    }

    hasDuplicateRecipientEmail(email) {
        const normalizedEmail = String(email || '').trim().toLowerCase();
        return this.allSelectedRecipients.some(
            (recipient) => String(recipient.email || '').trim().toLowerCase() === normalizedEmail
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
        if (normalized === 'CC') {
            return 'CC';
        }
        if (normalized === 'BCC') {
            return 'BCC';
        }
        return 'To';
    }

    toRecipientCard(recipient) {
        const displayName = recipient.name || recipient.email || 'Recipient';
        const source = recipient.source || recipient.sourceType || 'Manual';
        const detailParts = [];
        if (recipient.email && recipient.email !== displayName) {
            detailParts.push(recipient.email);
        }
        if (source) {
            detailParts.push(source);
        }

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
        if (!source) {
            return '?';
        }

        const words = source
            .replace(/[^A-Z0-9@._ -]/gi, '')
            .split(/\s+/)
            .filter(Boolean);

        if (words.length >= 2) {
            return `${words[0][0]}${words[1][0]}`.toUpperCase();
        }
        return source.substring(0, 2).toUpperCase();
    }

    formatAttachmentTitle(attachment) {
        const title = attachment?.title || 'Untitled file';
        const extension = attachment?.fileExtension;
        if (!extension || title.toLowerCase().endsWith(`.${extension.toLowerCase()}`)) {
            return title;
        }
        return `${title}.${extension}`;
    }

    formatFileSize(bytes) {
        if (!bytes && bytes !== 0) {
            return '';
        }
        if (bytes < 1024) {
            return `${bytes} B`;
        }
        if (bytes < 1048576) {
            return `${(bytes / 1024).toFixed(1)} KB`;
        }
        return `${(bytes / 1048576).toFixed(1)} MB`;
    }

    formatAttachmentMeta(attachment) {
        const source = attachment?.source || 'Related';
        const size = this.formatFileSize(attachment?.contentSize);
        return size ? `${source} - ${size}` : source;
    }

    normalizeEmailHtml(html) {
        if (!html) {
            return '';
        }
        if (typeof document === 'undefined') {
            return html;
        }

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

        if (hasSingleStandardWrapper) {
            return;
        }

        const wrapper = document.createElement('div');
        while (container.firstChild) {
            wrapper.appendChild(container.firstChild);
        }
        container.appendChild(wrapper);
    }

    applyStandardEmailTypography(root) {
        const elements = [root, ...Array.from(root.querySelectorAll('*'))];
        elements.forEach((element) => {
            if (!element?.style) {
                return;
            }

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
