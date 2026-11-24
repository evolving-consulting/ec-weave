import { createElement } from 'lwc';
import WeaveDataSourceEditor from 'c/weaveDataSourceEditor';
import getAvailableFlows        from '@salesforce/apex/WeaveTemplateBuilderController.getAvailableFlows';
import getDataCloudConnectors   from '@salesforce/apex/WeaveTemplateBuilderController.getDataCloudConnectors';
import validateTemplateMergeFields from '@salesforce/apex/WeaveTemplateBuilderController.validateTemplateMergeFields';

jest.mock(
    '@salesforce/apex/WeaveTemplateBuilderController.getAvailableFlows',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/WeaveTemplateBuilderController.getDataCloudConnectors',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/WeaveTemplateBuilderController.validateTemplateMergeFields',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const MOCK_FLOWS = [
    { apiName: 'My_Flow', label: 'My Flow' },
    { apiName: 'Other_Flow', label: 'Other Flow' }
];
const MOCK_CONNECTORS = [
    { apiName: 'Contact__dll', label: 'Contact DLO', objectType: '__dll', attributes: [
        { apiName: 'Email', label: 'Email', fieldType: 'STRING' }
    ]}
];
const VALID_RESULT = { isValid: true, errors: [], warnings: [] };
const ERROR_RESULT = { isValid: false, errors: [{ tag: '{{Parent.Bad}}', message: 'Unknown field' }], warnings: [] };

function createElement_() {
    const el = createElement('c-weave-data-source-editor', { is: WeaveDataSourceEditor });
    document.body.appendChild(el);
    return el;
}

afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
});

describe('weaveDataSourceEditor', () => {
    it('renders without errors', () => {
        getAvailableFlows.mockResolvedValue([]);
        getDataCloudConnectors.mockResolvedValue([]);
        const el = createElement_();
        expect(el).toBeTruthy();
    });

    it('shows channels combobox', async () => {
        getAvailableFlows.mockResolvedValue([]);
        getDataCloudConnectors.mockResolvedValue([]);
        const el = createElement_();
        await Promise.resolve();
        const combobox = el.shadowRoot.querySelector('lightning-combobox');
        expect(combobox).toBeTruthy();
    });

    it('shows empty flow state when no rows added', async () => {
        getAvailableFlows.mockResolvedValue(MOCK_FLOWS);
        getDataCloudConnectors.mockResolvedValue([]);
        const el = createElement_();
        await Promise.resolve();
        await Promise.resolve();
        const empty = el.shadowRoot.querySelector('.dse-empty');
        expect(empty).toBeTruthy();
    });

    it('adds a flow variable row on + Add click', async () => {
        getAvailableFlows.mockResolvedValue(MOCK_FLOWS);
        getDataCloudConnectors.mockResolvedValue([]);
        const el = createElement_();
        await Promise.resolve();
        await Promise.resolve();
        const addBtns = el.shadowRoot.querySelectorAll('.btn-add-small');
        addBtns[0].click();
        await Promise.resolve();
        const rows = el.shadowRoot.querySelectorAll('tbody tr');
        expect(rows.length).toBeGreaterThan(0);
    });

    it('fires configchange event on + Add click', async () => {
        getAvailableFlows.mockResolvedValue(MOCK_FLOWS);
        getDataCloudConnectors.mockResolvedValue([]);
        const el = createElement_();
        const handler = jest.fn();
        el.addEventListener('configchange', handler);
        await Promise.resolve();
        await Promise.resolve();
        const addBtns = el.shadowRoot.querySelectorAll('.btn-add-small');
        addBtns[0].click();
        await Promise.resolve();
        expect(handler).toHaveBeenCalled();
    });

    it('shows info banner when Data Cloud is not enabled', async () => {
        getAvailableFlows.mockResolvedValue([]);
        getDataCloudConnectors.mockResolvedValue([]);
        const el = createElement_();
        await Promise.resolve();
        await Promise.resolve();
        const banner = el.shadowRoot.querySelector('.info-banner');
        expect(banner).toBeTruthy();
    });

    it('hides info banner when Data Cloud connectors exist', async () => {
        getAvailableFlows.mockResolvedValue([]);
        getDataCloudConnectors.mockResolvedValue(MOCK_CONNECTORS);
        const el = createElement_();
        await Promise.resolve();
        await Promise.resolve();
        const banner = el.shadowRoot.querySelector('.info-banner');
        expect(banner).toBeNull();
    });

    it('validate button is present', async () => {
        getAvailableFlows.mockResolvedValue([]);
        getDataCloudConnectors.mockResolvedValue([]);
        const el = createElement_();
        await Promise.resolve();
        const btn = el.shadowRoot.querySelector('.btn-primary');
        expect(btn).toBeTruthy();
    });

    it('shows validation ok result', async () => {
        validateTemplateMergeFields.mockResolvedValue(VALID_RESULT);
        getAvailableFlows.mockResolvedValue([]);
        getDataCloudConnectors.mockResolvedValue([]);
        const el = createElement_();
        el.templateContent = '{{Parent.Name}}';
        await Promise.resolve();
        await Promise.resolve();
        const btn = el.shadowRoot.querySelector('.btn-primary');
        btn.click();
        await Promise.resolve();
        await Promise.resolve();
        const ok = el.shadowRoot.querySelector('.validation-ok');
        expect(ok).toBeTruthy();
    });

    it('shows validation error result', async () => {
        validateTemplateMergeFields.mockResolvedValue(ERROR_RESULT);
        getAvailableFlows.mockResolvedValue([]);
        getDataCloudConnectors.mockResolvedValue([]);
        const el = createElement_();
        el.templateContent = '{{Parent.Bad}}';
        await Promise.resolve();
        await Promise.resolve();
        const btn = el.shadowRoot.querySelector('.btn-primary');
        btn.click();
        await Promise.resolve();
        await Promise.resolve();
        const errors = el.shadowRoot.querySelector('.validation-errors');
        expect(errors).toBeTruthy();
    });

    it('getConfig returns current state', async () => {
        getAvailableFlows.mockResolvedValue([]);
        getDataCloudConnectors.mockResolvedValue([]);
        const el = createElement_();
        await Promise.resolve();
        const config = el.getConfig();
        expect(config).toHaveProperty('templateChannels');
        expect(config).toHaveProperty('flowVariables');
        expect(config).toHaveProperty('dataCloudRefs');
    });

    it('loadConfig restores saved state', async () => {
        getAvailableFlows.mockResolvedValue([]);
        getDataCloudConnectors.mockResolvedValue([]);
        const el = createElement_();
        await Promise.resolve();
        el.loadConfig({
            templateChannels: 'All Channels',
            flowVariables: [{ varName: 'promoCode', flowApiName: 'My_Flow' }],
            dataCloudRefs: []
        });
        await Promise.resolve();
        const config = el.getConfig();
        expect(config.templateChannels).toBe('All Channels');
        expect(config.flowVariables[0].varName).toBe('promoCode');
    });
});
