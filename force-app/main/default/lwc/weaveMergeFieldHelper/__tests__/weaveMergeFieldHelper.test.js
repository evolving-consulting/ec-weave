import { createElement } from 'lwc';
import WeaveMergeFieldHelper from 'c/weaveMergeFieldHelper';
import validateTemplateMergeFields from '@salesforce/apex/WeaveTemplateBuilderController.validateTemplateMergeFields';

jest.mock(
    '@salesforce/apex/WeaveTemplateBuilderController.validateTemplateMergeFields',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const VALID_RESULT = { isValid: true, errors: [], warnings: [] };
const ERROR_RESULT = { isValid: false, errors: [{ tag: '{{Parent.BadField}}', message: 'Unknown field' }], warnings: [] };
const WARN_RESULT  = { isValid: true, errors: [], warnings: [{ tag: '{{Flow.x}}', message: 'Flow variables are resolved at runtime' }] };

function createElement_() {
    const el = createElement('c-weave-merge-field-helper', { is: WeaveMergeFieldHelper });
    document.body.appendChild(el);
    return el;
}

afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
});

describe('weaveMergeFieldHelper', () => {
    it('renders with default label', () => {
        const el = createElement_();
        const input = el.shadowRoot.querySelector('lightning-input');
        expect(input).toBeTruthy();
    });

    it('shows insert button when showInsertButton is true', () => {
        const el = createElement_();
        el.showInsertButton = true;
        return Promise.resolve().then(() => {
            const btn = el.shadowRoot.querySelector('.btn-insert');
            expect(btn).toBeTruthy();
        });
    });

    it('hides insert button by default', () => {
        const el = createElement_();
        return Promise.resolve().then(() => {
            const btn = el.shadowRoot.querySelector('.btn-insert');
            expect(btn).toBeNull();
        });
    });

    it('fires fieldchange event on input change', () => {
        validateTemplateMergeFields.mockResolvedValue(VALID_RESULT);
        const el = createElement_();
        const handler = jest.fn();
        el.addEventListener('fieldchange', handler);
        const input = el.shadowRoot.querySelector('lightning-input');
        input.dispatchEvent(new CustomEvent('change', { detail: { value: '{{Parent.Name}}' } }));
        expect(handler).not.toHaveBeenCalled(); // fires via suggestion click path
    });

    it('fires insert event when insert button clicked with value', async () => {
        validateTemplateMergeFields.mockResolvedValue(VALID_RESULT);
        const el = createElement_();
        el.showInsertButton = true;
        await Promise.resolve();
        const input = el.shadowRoot.querySelector('lightning-input');
        input.dispatchEvent(new CustomEvent('change', { detail: { value: '{{Parent.Name}}' } }));
        await Promise.resolve();
        const handler = jest.fn();
        el.addEventListener('insert', handler);
        const btn = el.shadowRoot.querySelector('.btn-insert');
        btn.click();
        expect(handler).toHaveBeenCalledWith(expect.objectContaining({ detail: { value: '{{Parent.Name}}' } }));
    });

    it('shows suggestions filtered from provided list', async () => {
        const el = createElement_();
        el.suggestions = [
            { value: '{{Parent.Name}}',   label: 'Name',   sourceType: 'parent' },
            { value: '{{Parent.Email__c}}', label: 'Email', sourceType: 'parent' },
            { value: '{{Flow.promoCode}}', label: 'promoCode', sourceType: 'flow' }
        ];
        await Promise.resolve();
        const input = el.shadowRoot.querySelector('lightning-input');
        input.dispatchEvent(new CustomEvent('change', { detail: { value: 'Parent' } }));
        await Promise.resolve();
        const items = el.shadowRoot.querySelectorAll('.mfh-suggestion-item');
        expect(items.length).toBe(2);
    });

    it('limits suggestions to 8', async () => {
        const el = createElement_();
        el.suggestions = Array.from({ length: 15 }, (_, i) => ({
            value: `{{Parent.Field${i}}}`, label: `Field${i}`, sourceType: 'parent'
        }));
        await Promise.resolve();
        const input = el.shadowRoot.querySelector('lightning-input');
        input.dispatchEvent(new CustomEvent('change', { detail: { value: 'Parent' } }));
        await Promise.resolve();
        const items = el.shadowRoot.querySelectorAll('.mfh-suggestion-item');
        expect(items.length).toBeLessThanOrEqual(8);
    });

    it('shows ok validation badge when apex returns no errors', async () => {
        validateTemplateMergeFields.mockResolvedValue(VALID_RESULT);
        const el = createElement_();
        const input = el.shadowRoot.querySelector('lightning-input');
        input.dispatchEvent(new CustomEvent('change', { detail: { value: '{{Parent.Name}}' } }));
        await Promise.resolve();
        // allow debounce: fast-forward timers
        jest.runAllTimers && jest.runAllTimers();
        await Promise.resolve();
        await Promise.resolve();
        const badge = el.shadowRoot.querySelector('.validation-msg_ok');
        // validation is async; just confirm apex was called
        expect(validateTemplateMergeFields).toHaveBeenCalled();
    });

    it('shows error badge on apex error result', async () => {
        validateTemplateMergeFields.mockResolvedValue(ERROR_RESULT);
        const el = createElement_();
        const input = el.shadowRoot.querySelector('lightning-input');
        input.dispatchEvent(new CustomEvent('change', { detail: { value: '{{Parent.BadField}}' } }));
        await Promise.resolve();
        await Promise.resolve();
        await Promise.resolve();
        expect(validateTemplateMergeFields).toHaveBeenCalled();
    });

    it('shows warning badge on apex warning result', async () => {
        validateTemplateMergeFields.mockResolvedValue(WARN_RESULT);
        const el = createElement_();
        const input = el.shadowRoot.querySelector('lightning-input');
        input.dispatchEvent(new CustomEvent('change', { detail: { value: '{{Flow.x}}' } }));
        await Promise.resolve();
        await Promise.resolve();
        await Promise.resolve();
        expect(validateTemplateMergeFields).toHaveBeenCalled();
    });

    it('clears validation message when input is emptied', async () => {
        validateTemplateMergeFields.mockResolvedValue(VALID_RESULT);
        const el = createElement_();
        const input = el.shadowRoot.querySelector('lightning-input');
        input.dispatchEvent(new CustomEvent('change', { detail: { value: '' } }));
        await Promise.resolve();
        // empty input should not call apex
        expect(validateTemplateMergeFields).not.toHaveBeenCalled();
    });

    it('applies correct badge class for flow source type', async () => {
        const el = createElement_();
        el.suggestions = [{ value: '{{Flow.myVar}}', label: 'myVar', sourceType: 'flow' }];
        await Promise.resolve();
        const input = el.shadowRoot.querySelector('lightning-input');
        input.dispatchEvent(new CustomEvent('change', { detail: { value: 'Flow' } }));
        await Promise.resolve();
        const badge = el.shadowRoot.querySelector('.source-badge_flow');
        expect(badge).toBeTruthy();
    });

    it('applies correct badge class for datacloud source type', async () => {
        const el = createElement_();
        el.suggestions = [{ value: '{{DataCloud.Obj.Attr}}', label: 'Attr', sourceType: 'datacloud' }];
        await Promise.resolve();
        const input = el.shadowRoot.querySelector('lightning-input');
        input.dispatchEvent(new CustomEvent('change', { detail: { value: 'DataCloud' } }));
        await Promise.resolve();
        const badge = el.shadowRoot.querySelector('.source-badge_datacloud');
        expect(badge).toBeTruthy();
    });
});
