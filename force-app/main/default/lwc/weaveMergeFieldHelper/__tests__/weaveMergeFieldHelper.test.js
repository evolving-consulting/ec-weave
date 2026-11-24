import { createElement } from 'lwc';
import WeaveMergeFieldHelper from 'c/weaveMergeFieldHelper';
import validateTemplateMergeFields from '@salesforce/apex/WeaveTemplateBuilderController.validateTemplateMergeFields';

jest.mock(
    '@salesforce/apex/WeaveTemplateBuilderController.validateTemplateMergeFields',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const VALID_RESULT = { isValid: true,  errors: [],                                                       warnings: [] };
const ERROR_RESULT = { isValid: false, errors: [{ tag: '{{Parent.BadField}}', message: 'Unknown field' }], warnings: [] };
const WARN_RESULT  = { isValid: true,  errors: [],  warnings: [{ tag: '{{Flow.x}}', message: 'Resolved at runtime' }] };

function createElement_() {
    const el = createElement('c-weave-merge-field-helper', { is: WeaveMergeFieldHelper });
    document.body.appendChild(el);
    return el;
}

// Dispatch a change event carrying detail.value (LWC lightning-input pattern)
function dispatchChange(el, value) {
    const input = el.shadowRoot.querySelector('lightning-input');
    input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
    jest.useRealTimers();
});

describe('weaveMergeFieldHelper', () => {
    it('renders with an input element', () => {
        const el = createElement_();
        expect(el.shadowRoot.querySelector('lightning-input')).toBeTruthy();
    });

    it('shows insert button when showInsertButton is true', async () => {
        const el = createElement_();
        el.showInsertButton = true;
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.btn-insert')).toBeTruthy();
    });

    it('hides insert button by default', async () => {
        const el = createElement_();
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.btn-insert')).toBeNull();
    });

    it('fires insert event when insert button clicked with value', async () => {
        validateTemplateMergeFields.mockResolvedValue(VALID_RESULT);
        jest.useFakeTimers();
        const el = createElement_();
        el.showInsertButton = true;
        await Promise.resolve();
        dispatchChange(el, '{{Parent.Name}}');
        const handler = jest.fn();
        el.addEventListener('insert', handler);
        el.shadowRoot.querySelector('.btn-insert').click();
        expect(handler).toHaveBeenCalledWith(
            expect.objectContaining({ detail: { value: '{{Parent.Name}}' } })
        );
    });

    it('shows suggestions filtered from provided list', async () => {
        const el = createElement_();
        el.suggestions = [
            { value: '{{Parent.Name}}',   label: 'Name',  sourceType: 'parent' },
            { value: '{{Parent.Email__c}}', label: 'Email', sourceType: 'parent' },
            { value: '{{Flow.promoCode}}', label: 'promoCode', sourceType: 'flow' }
        ];
        await Promise.resolve();
        dispatchChange(el, 'Parent');
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
        dispatchChange(el, 'Parent');
        await Promise.resolve();
        expect(el.shadowRoot.querySelectorAll('.mfh-suggestion-item').length).toBeLessThanOrEqual(8);
    });

    it('fires fieldchange event when suggestion is clicked', async () => {
        const el = createElement_();
        el.suggestions = [{ value: '{{Parent.Name}}', label: 'Name', sourceType: 'parent' }];
        await Promise.resolve();
        dispatchChange(el, 'Parent');
        await Promise.resolve();
        const handler = jest.fn();
        el.addEventListener('fieldchange', handler);
        el.shadowRoot.querySelector('.mfh-suggestion-item').click();
        expect(handler).toHaveBeenCalled();
    });

    it('calls apex validateTemplateMergeFields after debounce', async () => {
        validateTemplateMergeFields.mockResolvedValue(VALID_RESULT);
        jest.useFakeTimers();
        const el = createElement_();
        dispatchChange(el, '{{Parent.Name}}');
        jest.runAllTimers();
        await Promise.resolve();
        expect(validateTemplateMergeFields).toHaveBeenCalledWith(
            expect.objectContaining({ templateContent: '{{Parent.Name}}' })
        );
    });

    it('shows ok validation message after valid result', async () => {
        validateTemplateMergeFields.mockResolvedValue(VALID_RESULT);
        jest.useFakeTimers();
        const el = createElement_();
        dispatchChange(el, '{{Parent.Name}}');
        jest.runAllTimers();
        await Promise.resolve();
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.validation-msg_ok')).toBeTruthy();
    });

    it('shows error validation message after error result', async () => {
        validateTemplateMergeFields.mockResolvedValue(ERROR_RESULT);
        jest.useFakeTimers();
        const el = createElement_();
        dispatchChange(el, '{{Parent.BadField}}');
        jest.runAllTimers();
        await Promise.resolve();
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.validation-msg_error')).toBeTruthy();
    });

    it('shows warning validation message after warning result', async () => {
        validateTemplateMergeFields.mockResolvedValue(WARN_RESULT);
        jest.useFakeTimers();
        const el = createElement_();
        dispatchChange(el, '{{Flow.x}}');
        jest.runAllTimers();
        await Promise.resolve();
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.validation-msg_warn')).toBeTruthy();
    });

    it('does not call apex when input is empty', async () => {
        jest.useFakeTimers();
        const el = createElement_();
        dispatchChange(el, '');
        jest.runAllTimers();
        await Promise.resolve();
        expect(validateTemplateMergeFields).not.toHaveBeenCalled();
    });

    it('applies source-badge_flow class for flow suggestions', async () => {
        const el = createElement_();
        el.suggestions = [{ value: '{{Flow.myVar}}', label: 'myVar', sourceType: 'flow' }];
        await Promise.resolve();
        dispatchChange(el, 'Flow');
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.source-badge_flow')).toBeTruthy();
    });

    it('applies source-badge_datacloud class for datacloud suggestions', async () => {
        const el = createElement_();
        el.suggestions = [{ value: '{{DataCloud.Obj.Attr}}', label: 'Attr', sourceType: 'datacloud' }];
        await Promise.resolve();
        dispatchChange(el, 'DataCloud');
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.source-badge_datacloud')).toBeTruthy();
    });
});
