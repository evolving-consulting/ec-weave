import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import sendEmail from '@salesforce/apex/MCNEmailSendService.sendEmail';

const EMAIL_RE = /^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$/i;

export default class McnEmailSender extends LightningElement {
    @api templateId;
    @api contextData;
    @api recordId;

    // Allow pre-population from parent; also editable inline
    @api
    get recipientEmail() {
        return this._recipientEmail;
    }
    set recipientEmail(val) {
        this._recipientEmail = val;
        this.recipientEmailValue = val || '';
    }

    @track recipientEmailValue = '';
    @track isSending = false;
    @track errorMessage = '';
    @track hasSent = false;
    @track messageId = '';

    _recipientEmail = '';

    get hasError() {
        return !!this.errorMessage;
    }

    get isSendDisabled() {
        return this.isSending || !this._isValidEmail(this.recipientEmailValue) || !this.templateId;
    }

    handleEmailChange(event) {
        this.recipientEmailValue = event.target.value;
        this.errorMessage = '';
    }

    handleSend() {
        if (!this._isValidEmail(this.recipientEmailValue)) {
            this.errorMessage = 'Please enter a valid email address.';
            return;
        }
        if (!this.templateId) {
            this.errorMessage = 'No template is configured for this component.';
            return;
        }

        this.isSending    = true;
        this.errorMessage = '';

        const ctx = this._buildContextJson();

        sendEmail({
            templateId:      this.templateId,
            recipientEmail:  this.recipientEmailValue,
            contextDataJson: ctx
        })
            .then(result => {
                if (result.isSuccess) {
                    this.hasSent   = true;
                    this.messageId = result.messageId || '';
                    this.dispatchEvent(new ShowToastEvent({
                        title:   'Email Sent',
                        message: 'Your email was successfully sent via Marketing Cloud Next.',
                        variant: 'success'
                    }));
                    this.dispatchEvent(new CustomEvent('sent', {
                        detail:   { messageId: result.messageId, status: result.status },
                        bubbles:  true,
                        composed: true
                    }));
                } else {
                    this.errorMessage = result.errorMessage || 'Send failed. Please try again.';
                }
            })
            .catch(error => {
                this.errorMessage = this._extractError(error);
            })
            .finally(() => {
                this.isSending = false;
            });
    }

    handleReset() {
        this.hasSent          = false;
        this.messageId        = '';
        this.recipientEmailValue = '';
        this.errorMessage     = '';
    }

    clearError() {
        this.errorMessage = '';
    }

    _buildContextJson() {
        if (this.contextData) return this.contextData;
        if (this.recordId) return JSON.stringify({ recordId: this.recordId });
        return '{}';
    }

    _isValidEmail(email) {
        return email && EMAIL_RE.test(email);
    }

    _extractError(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'An unexpected error occurred.';
    }
}
