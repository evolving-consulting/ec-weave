import { createElement } from 'lwc';
import McnTemplateRenderer from 'c/mcnTemplateRenderer';
import resolveTemplate from '@salesforce/apex/MCNTemplateRenderService.resolveTemplate';

jest.mock(
    '@salesforce/apex/MCNTemplateRenderService.resolveTemplate',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const MOCK_SUCCESS = {
    isSuccess: true,
    subject: 'Hello Jane',
    htmlBody: '<p>Welcome, Jane!</p>',
    plainText: 'Welcome, Jane!'
};

const MOCK_FAILURE = {
    isSuccess: false,
    errorMessage: 'Merge field {{Parent.Name}} could not be resolved.'
};

function flushPromises() {
    return new Promise(resolve => { setTimeout(resolve, 0); });
}

describe('mcnTemplateRenderer', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows empty state when no templateId is set', () => {
        const el = createElement('c-mcn-template-renderer', { is: McnTemplateRenderer });
        document.body.appendChild(el);
        expect(el.shadowRoot.querySelector('.empty-state')).not.toBeNull();
    });

    it('renders subject and HTML body on successful resolve', async () => {
        resolveTemplate.mockResolvedValue(MOCK_SUCCESS);

        const el = createElement('c-mcn-template-renderer', { is: McnTemplateRenderer });
        el.templateId = '001000000000001AAA';
        el.recordId   = '003000000000001AAA';
        document.body.appendChild(el);
        await flushPromises();

        const subject = el.shadowRoot.querySelector('.preview-subject');
        expect(subject).not.toBeNull();
        expect(subject.textContent).toBe('Hello Jane');
    });

    it('shows error banner on failure result', async () => {
        resolveTemplate.mockResolvedValue(MOCK_FAILURE);

        const el = createElement('c-mcn-template-renderer', { is: McnTemplateRenderer });
        el.templateId = '001000000000001AAA';
        document.body.appendChild(el);
        await flushPromises();

        const banner = el.shadowRoot.querySelector('.error-banner');
        expect(banner).not.toBeNull();
        expect(banner.textContent).toContain('Merge field');
    });

    it('shows error banner on Apex exception', async () => {
        resolveTemplate.mockRejectedValue(new Error('Apex callout failed'));

        const el = createElement('c-mcn-template-renderer', { is: McnTemplateRenderer });
        el.templateId = '001000000000001AAA';
        document.body.appendChild(el);
        await flushPromises();

        const banner = el.shadowRoot.querySelector('.error-banner');
        expect(banner).not.toBeNull();
    });

    it('dismiss clears error banner', async () => {
        resolveTemplate.mockResolvedValue(MOCK_FAILURE);

        const el = createElement('c-mcn-template-renderer', { is: McnTemplateRenderer });
        el.templateId = '001000000000001AAA';
        document.body.appendChild(el);
        await flushPromises();

        const dismiss = el.shadowRoot.querySelector('.error-dismiss');
        dismiss.click();
        await flushPromises();

        expect(el.shadowRoot.querySelector('.error-banner')).toBeNull();
    });

    it('passes contextData prop as the JSON payload', async () => {
        resolveTemplate.mockResolvedValue(MOCK_SUCCESS);
        const ctxJson = JSON.stringify({ recordId: '003abc', flowVariables: { greeting: 'Hi' } });

        const el = createElement('c-mcn-template-renderer', { is: McnTemplateRenderer });
        el.templateId   = '001000000000001AAA';
        el.contextData  = ctxJson;
        document.body.appendChild(el);
        await flushPromises();

        expect(resolveTemplate).toHaveBeenCalledWith(
            expect.objectContaining({ contextDataJson: ctxJson })
        );
    });

    it('falls back to recordId context when contextData is absent', async () => {
        resolveTemplate.mockResolvedValue(MOCK_SUCCESS);

        const el = createElement('c-mcn-template-renderer', { is: McnTemplateRenderer });
        el.templateId = '001000000000001AAA';
        el.recordId   = '003000000000001AAA';
        document.body.appendChild(el);
        await flushPromises();

        const call = resolveTemplate.mock.calls[0][0];
        expect(call.contextDataJson).toContain('003000000000001AAA');
    });
});
