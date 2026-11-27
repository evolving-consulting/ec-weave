import { createElement } from 'lwc';
import WeaveDataSourceEditor from 'c/weaveDataSourceEditor';
import getAvailableFlows        from '@salesforce/apex/WeaveTemplateBuilderController.getAvailableFlows';
import getDataCloudConnectors   from '@salesforce/apex/WeaveTemplateBuilderController.getDataCloudConnectors';
import validateTemplateMergeFields from '@salesforce/apex/WeaveTemplateBuilderController.validateTemplateMergeFields';
import { registerApexTestWireAdapter } from '@salesforce/wire-service-jest-util';

// Only mock the imperative apex call; let sfdx-lwc-jest auto-resolve the @wire ones
// so registerApexTestWireAdapter can intercept them correctly.
jest.mock(
    '@salesforce/apex/WeaveTemplateBuilderController.validateTemplateMergeFields',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// Register wire adapters at module level (before any createElement)
const getAvailableFlowsAdapter      = registerApexTestWireAdapter(getAvailableFlows);
const getDataCloudConnectorsAdapter = registerApexTestWireAdapter(getDataCloudConnectors);

const MOCK_FLOWS = [
    { apiName: 'My_Flow',    label: 'My Flow' },
    { apiName: 'Other_Flow', label: 'Other Flow' }
];
const MOCK_CONNECTORS = [
    { apiName: 'Contact__dll', label: 'Contact DLO', objectType: '__dll', attributes: [
        { apiName: 'Email', label: 'Email', fieldType: 'STRING' }
    ]}
];
const VALID_RESULT = { isValid: true,  errors: [],                                                   warnings: [] };
const ERROR_RESULT = { isValid: false, errors: [{ tag: '{{Parent.Bad}}', message: 'Unknown field' }], warnings: [] };

function createElement_() {
    const el = createElement('c-weave-data-source-editor', { is: WeaveDataSourceEditor });
    document.body.appendChild(el);
    return el;
}

// Create element, emit wire data, flush rendering
async function createAndEmit({ flows = [], connectors = [] } = {}) {
    const el = createElement_();
    getAvailableFlowsAdapter.emit(flows);
    getDataCloudConnectorsAdapter.emit(connectors);
    // Two flush cycles: wire → state update → re-render
    await Promise.resolve();
    await Promise.resolve();
    return el;
}

afterEach(() => {
    while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
});

describe('weaveDataSourceEditor', () => {
    it('renders without errors', async () => {
        const el = await createAndEmit();
        expect(el).toBeTruthy();
    });

    it('shows channels combobox', async () => {
        const el = await createAndEmit();
        const combobox = el.shadowRoot.querySelector('lightning-combobox');
        expect(combobox).toBeTruthy();
    });

    it('shows empty flow state when no rows added', async () => {
        const el = await createAndEmit({ flows: MOCK_FLOWS });
        const empty = el.shadowRoot.querySelector('.dse-empty');
        expect(empty).toBeTruthy();
    });

    it('adds a flow variable row on + Add click', async () => {
        const el = await createAndEmit({ flows: MOCK_FLOWS });
        const addBtns = el.shadowRoot.querySelectorAll('.btn-add-small');
        addBtns[0].click();
        await Promise.resolve();
        const rows = el.shadowRoot.querySelectorAll('tbody tr');
        expect(rows.length).toBeGreaterThan(0);
    });

    it('updates getConfig after + Add click', async () => {
        const el = await createAndEmit({ flows: MOCK_FLOWS });
        const addBtns = el.shadowRoot.querySelectorAll('.btn-add-small');
        addBtns[0].click();
        await Promise.resolve();
        const config = el.getConfig();
        expect(config.flowVariables.length).toBe(1);
    });

    it('shows info banner when Data Cloud is not enabled', async () => {
        const el = await createAndEmit({ connectors: [] });
        const banner = el.shadowRoot.querySelector('.info-banner');
        expect(banner).toBeTruthy();
    });

    it('hides info banner when Data Cloud connectors exist', async () => {
        const el = await createAndEmit({ connectors: MOCK_CONNECTORS });
        const banner = el.shadowRoot.querySelector('.info-banner');
        expect(banner).toBeNull();
    });

    it('validate button is present', async () => {
        const el = await createAndEmit();
        const btn = el.shadowRoot.querySelector('.btn-primary');
        expect(btn).toBeTruthy();
    });

    it('shows validation ok result', async () => {
        validateTemplateMergeFields.mockResolvedValue(VALID_RESULT);
        const el = await createAndEmit();
        el.templateContent = '{{Parent.Name}}';
        await Promise.resolve();
        el.shadowRoot.querySelector('.btn-primary').click();
        await Promise.resolve();
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.validation-ok')).toBeTruthy();
    });

    it('shows validation error result', async () => {
        validateTemplateMergeFields.mockResolvedValue(ERROR_RESULT);
        const el = await createAndEmit();
        el.templateContent = '{{Parent.Bad}}';
        await Promise.resolve();
        el.shadowRoot.querySelector('.btn-primary').click();
        await Promise.resolve();
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.validation-errors')).toBeTruthy();
    });

    it('getConfig returns current state', async () => {
        const el = await createAndEmit();
        const config = el.getConfig();
        expect(config).toHaveProperty('templateChannels');
        expect(config).toHaveProperty('flowVariables');
        expect(config).toHaveProperty('dataCloudRefs');
    });

    it('loadConfig restores saved state', async () => {
        const el = await createAndEmit();
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
