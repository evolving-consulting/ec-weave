import { createElement } from 'lwc';
import McnEmailSender from 'c/mcnEmailSender';
import sendEmail from '@salesforce/apex/MCNEmailSendService.sendEmail';

jest.mock(
    '@salesforce/apex/MCNEmailSendService.sendEmail',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock('lightning/platformShowToastEvent', () => ({
    ShowToastEvent: class ShowToastEvent {
        constructor(opts) { Object.assign(this, opts); }
    }
}), { virtual: true });

function flushPromises() {
    return new Promise(resolve => setTimeout(resolve, 0));
}

function setInput(el, selector, value) {
    const input = el.shadowRoot.querySelector(selector);
    input.value = value;
    input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('mcnEmailSender', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    // ── Rendering ─────────────────────────────────────────────────────────────

    it('renders send button', () => {
        const el = createElement('c-mcn-email-sender', { is: McnEmailSender });
        el.templateId = '001000000000001AAA';
        document.body.appendChild(el);
        expect(el.shadowRoot.querySelector('.btn-primary')).not.toBeNull();
    });

    it('send button is disabled when no email is entered', () => {
        const el = createElement('c-mcn-email-sender', { is: McnEmailSender });
        el.templateId = '001000000000001AAA';
        document.body.appendChild(el);
        const btn = el.shadowRoot.querySelector('.btn-primary');
        expect(btn.disabled).toBe(true);
    });

    it('send button is disabled when no templateId', () => {
        const el = createElement('c-mcn-email-sender', { is: McnEmailSender });
        el.recipientEmail = 'test@example.com';
        document.body.appendChild(el);
        const btn = el.shadowRoot.querySelector('.btn-primary');
        expect(btn.disabled).toBe(true);
    });

    // ── Success ───────────────────────────────────────────────────────────────

    it('shows success banner after successful send', async () => {
        sendEmail.mockResolvedValue({ isSuccess: true, messageId: 'msg-123', status: 'Sent' });

        const el = createElement('c-mcn-email-sender', { is: McnEmailSender });
        el.templateId     = '001000000000001AAA';
        el.recipientEmail = 'test@example.com';
        document.body.appendChild(el);
        await flushPromises();

        const btn = el.shadowRoot.querySelector('.btn-primary');
        btn.click();
        await flushPromises();

        expect(el.shadowRoot.querySelector('.success-banner')).not.toBeNull();
    });

    it('transitions to sent state after successful send', async () => {
        sendEmail.mockResolvedValue({ isSuccess: true, messageId: 'msg-456', status: 'Sent' });

        const el = createElement('c-mcn-email-sender', { is: McnEmailSender });
        el.templateId     = '001000000000001AAA';
        el.recipientEmail = 'valid@test.com';
        document.body.appendChild(el);
        await flushPromises();

        el.shadowRoot.querySelector('.btn-primary').click();
        await flushPromises();

        // hasSent = true means send button is hidden and success banner shown
        expect(el.shadowRoot.querySelector('.success-banner')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.btn-primary')).toBeNull();
    });

    // ── Error ─────────────────────────────────────────────────────────────────

    it('shows error banner on send failure', async () => {
        sendEmail.mockResolvedValue({ isSuccess: false, errorMessage: 'Template not found.' });

        const el = createElement('c-mcn-email-sender', { is: McnEmailSender });
        el.templateId     = '001000000000001AAA';
        el.recipientEmail = 'err@test.com';
        document.body.appendChild(el);
        await flushPromises();

        el.shadowRoot.querySelector('.btn-primary').click();
        await flushPromises();

        const banner = el.shadowRoot.querySelector('.error-banner');
        expect(banner).not.toBeNull();
        expect(banner.textContent).toContain('Template not found');
    });

    it('shows error banner on Apex exception', async () => {
        sendEmail.mockRejectedValue(new Error('Callout failed'));

        const el = createElement('c-mcn-email-sender', { is: McnEmailSender });
        el.templateId     = '001000000000001AAA';
        el.recipientEmail = 'err@test.com';
        document.body.appendChild(el);
        await flushPromises();

        el.shadowRoot.querySelector('.btn-primary').click();
        await flushPromises();

        expect(el.shadowRoot.querySelector('.error-banner')).not.toBeNull();
    });

    it('dismiss button clears error', async () => {
        sendEmail.mockRejectedValue(new Error('Oops'));

        const el = createElement('c-mcn-email-sender', { is: McnEmailSender });
        el.templateId     = '001000000000001AAA';
        el.recipientEmail = 'err@test.com';
        document.body.appendChild(el);
        await flushPromises();

        el.shadowRoot.querySelector('.btn-primary').click();
        await flushPromises();

        el.shadowRoot.querySelector('.error-dismiss').click();
        await flushPromises();

        expect(el.shadowRoot.querySelector('.error-banner')).toBeNull();
    });

    // ── Reset ─────────────────────────────────────────────────────────────────

    it('Send Another button resets to initial state', async () => {
        sendEmail.mockResolvedValue({ isSuccess: true, messageId: 'x', status: 'Sent' });

        const el = createElement('c-mcn-email-sender', { is: McnEmailSender });
        el.templateId     = '001000000000001AAA';
        el.recipientEmail = 'go@test.com';
        document.body.appendChild(el);
        await flushPromises();

        el.shadowRoot.querySelector('.btn-primary').click();
        await flushPromises();

        el.shadowRoot.querySelector('.btn-secondary').click();
        await flushPromises();

        expect(el.shadowRoot.querySelector('.btn-primary')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.success-banner')).toBeNull();
    });

    // ── Status display ────────────────────────────────────────────────────────

    it('displays message ID in success banner', async () => {
        sendEmail.mockResolvedValue({ isSuccess: true, messageId: 'mcn-id-789', status: 'Sent' });

        const el = createElement('c-mcn-email-sender', { is: McnEmailSender });
        el.templateId     = '001000000000001AAA';
        el.recipientEmail = 'id@test.com';
        document.body.appendChild(el);
        await flushPromises();

        el.shadowRoot.querySelector('.btn-primary').click();
        await flushPromises();

        const idSpan = el.shadowRoot.querySelector('.message-id');
        expect(idSpan).not.toBeNull();
        expect(idSpan.textContent).toContain('mcn-id-789');
    });
});
