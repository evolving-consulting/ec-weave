import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTemplates from '@salesforce/apex/WeaveTemplateBuilderController.getTemplates';
import getAvailableObjects from '@salesforce/apex/WeaveTemplateBuilderController.getAvailableObjects';
import getOrgWideEmailAddresses from '@salesforce/apex/WeaveTemplateBuilderController.getOrgWideEmailAddresses';
import getRelatedObjectsForQuery from '@salesforce/apex/WeaveTemplateBuilderController.getRelatedObjectsForQuery';
import getFieldsForObject from '@salesforce/apex/WeaveTemplateBuilderController.getFieldsForObject';
import getUpdateableFieldsForObject from '@salesforce/apex/WeaveTemplateBuilderController.getUpdateableFieldsForObject';
import loadTemplate from '@salesforce/apex/WeaveTemplateBuilderController.loadTemplate';
import saveTemplate from '@salesforce/apex/WeaveTemplateBuilderController.saveTemplate';
import deleteTemplate from '@salesforce/apex/WeaveTemplateBuilderController.deleteTemplate';
import getTemplateFiles from '@salesforce/apex/WeaveTemplateBuilderController.getTemplateFiles';
import createPublicImageLink from '@salesforce/apex/WeaveTemplateBuilderController.createPublicImageLink';
import deleteTemplateFile from '@salesforce/apex/WeaveTemplateBuilderController.deleteTemplateFile';
import previewTemplate from '@salesforce/apex/WeaveTemplateBuilderController.previewTemplate';
import previewTemplatePdf from '@salesforce/apex/WeaveTemplateBuilderController.previewTemplatePdf';
import sendTestEmail from '@salesforce/apex/WeaveTemplateBuilderController.sendTestEmail';
import createScheduledSend from '@salesforce/apex/WeaveTemplateBuilderController.createScheduledSend';
import scheduleRecurringEmail from '@salesforce/apex/WeaveEmailTemplateController.scheduleRecurringEmail';
import getScheduledSends from '@salesforce/apex/WeaveTemplateBuilderController.getScheduledSends';
import cancelScheduledSend from '@salesforce/apex/WeaveTemplateBuilderController.cancelScheduledSend';
import sendScheduledSendNow from '@salesforce/apex/WeaveTemplateBuilderController.sendScheduledSendNow';
import getBrands from '@salesforce/apex/WeaveTemplateBuilderController.getBrands';
import loadBrand from '@salesforce/apex/WeaveTemplateBuilderController.loadBrand';
import saveBrand from '@salesforce/apex/WeaveTemplateBuilderController.saveBrand';
import deleteBrand from '@salesforce/apex/WeaveTemplateBuilderController.deleteBrand';
import getBrandFiles from '@salesforce/apex/WeaveTemplateBuilderController.getBrandFiles';
import createBrandPublicImageLink from '@salesforce/apex/WeaveTemplateBuilderController.createBrandPublicImageLink';
import deleteBrandFile from '@salesforce/apex/WeaveTemplateBuilderController.deleteBrandFile';
import getActiveSegments from '@salesforce/apex/WeaveTemplateBuilderController.getActiveSegments';
import cloneTemplate from '@salesforce/apex/WeaveTemplateBuilderController.cloneTemplate';
import getSchedulerStatus from '@salesforce/apex/WeaveTemplateBuilderController.getSchedulerStatus';
import activateScheduler from '@salesforce/apex/WeaveTemplateBuilderController.activateScheduler';
import deactivateScheduler from '@salesforce/apex/WeaveTemplateBuilderController.deactivateScheduler';
import getSignerFormFields from '@salesforce/apex/WeaveSignatureAuraController.getSignerFormFields';
import upsertSignerFormField from '@salesforce/apex/WeaveSignatureAuraController.upsertSignerFormField';
import deleteSignerFormField from '@salesforce/apex/WeaveSignatureAuraController.deleteSignerFormField';

const STATUS_OPTIONS = [
  { label: 'Draft', value: 'Draft' },
  { label: 'Active', value: 'Active' },
  { label: 'Inactive', value: 'Inactive' }
];
const COMPONENT_TYPE_OPTIONS = [
  { label: 'Text', value: 'Text' },
  { label: 'Related Table', value: 'Related Table' },
  { label: 'Divider', value: 'Divider' },
  { label: 'Spacer', value: 'Spacer' },
  { label: 'Image', value: 'Image' },
  { label: 'Button', value: 'Button' },
  { label: 'HTML Block', value: 'HTML Block' }
];
const REGION_OPTIONS = [
  { label: 'Header', value: 'Header' },
  { label: 'Body', value: 'Body' },
  { label: 'Footer', value: 'Footer' }
];
const ACTION_TYPE_OPTIONS = [
  { label: 'Update Field', value: 'Update Field' },
  { label: 'Create Task', value: 'Create Task' }
];
const RECIPIENT_TYPE_OPTIONS = [
  { label: 'To', value: 'To' },
  { label: 'CC', value: 'CC' },
  { label: 'BCC', value: 'BCC' }
];
const RECIPIENT_SOURCE_OPTIONS = [
  { label: 'Parent Field', value: 'Parent Field' },
  { label: 'Related Records (from query)', value: 'Related Records' },
  { label: 'Manual (static email)', value: 'Manual' },
  { label: 'Dynamic Segment', value: 'Dynamic Segment' }
];
const VALUE_TYPE_OPTIONS = [
  { label: 'Static Text', value: 'Static' },
  { label: 'Merge Tag / Field', value: 'Merge Tag' }
];
const ASSIGNED_TO_OPTIONS = [
  { label: 'Current User', value: 'Current User' },
  { label: 'Record Owner', value: 'Record Owner' },
  { label: 'Specific User', value: 'Specific User' }
];
const DUE_DATE_OPTIONS = [
  { label: 'Same Day as Send', value: 'Same Day' },
  { label: 'Days After Send', value: 'Days After' }
];
const TASK_STATUS_OPTIONS = [
  { label: 'Completed', value: 'Completed' },
  { label: 'Not Started', value: 'Not Started' },
  { label: 'In Progress', value: 'In Progress' }
];
const TASK_PRIORITY_OPTIONS = [
  { label: 'Normal', value: 'Normal' },
  { label: 'High', value: 'High' },
  { label: 'Low', value: 'Low' }
];
const BUTTON_COLOR_OPTIONS = [
  { label: 'Teal (Default)', value: '#1f5f5b' },
  { label: 'Blue', value: '#0070d2' },
  { label: 'Green', value: '#27ae60' },
  { label: 'Red', value: '#c0392b' },
  { label: 'Orange', value: '#e67e22' },
  { label: 'Gray', value: '#6b7280' }
];

const FROM_EMAIL_TYPE_OPTIONS = [
  { label: 'Current User', value: 'CurrentUser' },
  { label: 'Org Wide Email', value: 'OrgWide' }
];
const OUTPUT_TYPE_OPTIONS = [
  { label: 'Email', value: 'Email' },
  { label: 'Document', value: 'Document' }
];
const SCHEDULE_OUTPUT_TYPE_OPTIONS = [
  { label: 'Email', value: 'Email' },
  { label: 'PDF', value: 'PDF' },
  { label: 'Email + PDF', value: 'Email + PDF' }
];
const DOCUMENT_FORMAT_OPTIONS = [
  { label: 'PDF', value: 'PDF' }
];
const PDF_PAGE_SIZE_OPTIONS = [
  { label: 'Letter (8.5 × 11 in)', value: 'Letter' },
  { label: 'Legal (8.5 × 14 in)', value: 'Legal' },
  { label: 'A4 (8.27 × 11.69 in)', value: 'A4' },
  { label: 'A3 (11.69 × 16.54 in)', value: 'A3' },
  { label: 'A5 (5.83 × 8.27 in)', value: 'A5' },
  { label: 'Custom', value: 'Custom' }
];
const ATTACHMENT_SOURCE_OPTIONS = [
  { label: 'Static File', value: 'Static File' },
  { label: 'Source Record Files', value: 'Source Record Files' },
  { label: 'Related Record Files', value: 'Related Record Files' }
];

let _localKeyCounter = 0;
function nextKey() { return 'local-' + (++_localKeyCounter); }

function parseSoqlObject(soql) {
  if (!soql) return '';
  const match = soql.match(/FROM\s+(\w+)/i);
  return match ? match[1] : '';
}

function emptyTemplate() {
  return {
    id: null, name: '', apiName: '', status: 'Draft',
    parentObjectApiName: '', defaultFromEmail: '', description: '',
    allowUserEditBeforeSend: true, storeEmailHistory: true,
    subjectTemplate: '', subjectVariantB: '',
    brandId: null, brandName: null,
    queries: [], components: [], recipients: [], actions: [],
    deletedQueryIds: [], deletedComponentIds: [], deletedRecipientIds: [], deletedActionIds: [],
    attachments: [], deletedAttachmentIds: [],
    canvasPageSize: 'Letter', canvasOrientation: 'Portrait', templateOutputType: 'Email',
    documentFormat: 'PDF', pdfPageSize: 'Letter', pdfPageWidthIn: null, pdfPageHeightIn: null
  };
}

function emptyBrand() {
  return {
    id: null, name: '', apiName: '', displayName: '', status: 'Active',
    primaryColor: '#1f5f5b', secondaryColor: '#4fb893',
    logoUrl: '', logoContentDocumentId: null,
    orgWideEmailAddress: '', physicalAddress: '',
    unsubscribeUrl: '', unsubscribeLabel: 'Unsubscribe',
    headerHtml: '', headerEditorMode: 'Visual',
    footerHtml: '', footerEditorMode: 'Visual',
    description: ''
  };
}

function statusPillClass(status) {
  const s = (status || 'draft').toLowerCase();
  return 'status-pill status-pill_' + (s === 'active' ? 'active' : s === 'inactive' ? 'archived' : 'draft');
}

export default class WeaveTemplateBuilder extends LightningElement {
  @track templates = [];
  @track draftTemplate = emptyTemplate();
  @track isEditing = false;
  @track isLoading = false;
  @track errorMessage = null;
  @track activeTab = 'settings';
  @track objectOptions = [];
  @track relatedObjectOptions = [];
  @track relatedObjectMeta = {}; // apiName -> { type, connectorField }
  @track orgWideEmailOptions = [];
  @track newComponentType = 'Text';
  @track newComponentRegion = 'Body';
  @track newActionType = 'Update Field';
  @track showQueryModal = false;
  @track editingQuery = {};
  @track editingQueryKey = null;
  @track showComponentModal = false;
  @track editingComponent = {};
  @track editingComponentKey = null;
  @track componentEditorMode = 'rich';
  @track parentFieldsForMergeTags = [];
  @track isLoadingMergeTags = false;
  @track mergeTagSearch = '';
  @track previewRecordId = '';
  @track previewSubject = '';
  @track previewHtml = '';
  @track previewIsLoading = false;
  @track isPreviewingPdf = false;
  @track isSendingTest = false;
  @track scheduleDateTime = '';
  @track scheduleDate = '';
  @track scheduleTime = '09:00';
  @track scheduleType = 'Bulk';
  @track scheduleMode = 'once';
  @track scheduleBulkFilter = '';
  @track scheduleOutputType = 'Email';
  @track isScheduling = false;
  @track recurringDays = [];
  @track recurringTime = '09:00';
  @track recurringStartDate = '';
  @track recurringEndType = 'noEnd';
  @track recurringEndDate = '';
  @track recurringMaxSends = '';
  @track scheduledSends = [];
  @track isLoadingSchedules = false;
  @track libraryFilter = 'all';
  @track searchTerm = '';
  @track showInfoBanner = true;
  @track isDirty = false;
  @track _fromEmailType = null;
  @track showRecipientModal = false;
  @track editingRecipient = {};
  @track editingRecipientKey = null;
  @track showActionModal = false;
  @track editingAction = {};
  @track editingActionKey = null;
  @track updateableFields = [];
  @track _actionFocusedField = null;
  @track templateImages = [];
  @track templateAttachments = [];
  @track isLoadingFiles = false;
  @track signerFormFields = [];
  @track isEditingSignerField = false;
  @track draftSignerField = {};
  @track isSignerFieldLoading = false;
  @track selectedAttachmentRuleKey = null;
  @track sidebarView = 'templates';
  @track brands = [];
  @track draftBrand = emptyBrand();
  @track isBrandEditing = false;
  @track isBrandLoading = false;
  @track brandFilter = 'all';
  @track brandSearchTerm = '';
  @track brandImages = [];
  @track isLoadingBrandFiles = false;
  @track brandHeaderEditorMode = 'Visual';
  @track brandFooterEditorMode = 'Visual';
  @track brandActiveTab = 'identity';
  @track copiedTag = null;
  @track copiedSignerTag = null;
  @track insertedTag = null;
  @track headerRteKey = 1;
  @track footerRteKey = 1;
  @track availableSegments = [];
  @track showCloneModal = false;
  @track cloneSourceId = null;
  @track cloneName = '';
  @track cloneApiName = '';
  @track cloneOutputType = 'Email';
  @track isCloning = false;
  @track schedulerStatus = null;
  @track isLoadingScheduler = false;
  @track selectedFrequency = 'every_hour';
  @track isTogglingScheduler = false;

  // Brand AI Prompt Builder
  @track showBrandAiModal = false;
  @track brandAiStep = 1;
  @track brandAiHeaderDesc = '';
  @track brandAiFooterDesc = '';
  @track brandAiImages = []; // { id, title, publicUrl, imgTag, width, include }
  @track brandPromptCopied = false;
  @track brandSfRulesExpanded = false;
  _brandCopyTimer = null;

  statusOptions = STATUS_OPTIONS;
  fromEmailTypeOptions = FROM_EMAIL_TYPE_OPTIONS;
  outputTypeOptions = OUTPUT_TYPE_OPTIONS;
  scheduleOutputTypeOptions = SCHEDULE_OUTPUT_TYPE_OPTIONS;
  documentFormatOptions = DOCUMENT_FORMAT_OPTIONS;
  pdfPageSizeOptions = PDF_PAGE_SIZE_OPTIONS;
  componentTypeOptions = COMPONENT_TYPE_OPTIONS;
  regionOptions = REGION_OPTIONS;
  actionTypeOptions = ACTION_TYPE_OPTIONS;
  recipientTypeOptions = RECIPIENT_TYPE_OPTIONS;
  recipientSourceOptions = RECIPIENT_SOURCE_OPTIONS;
  valueTypeOptions = VALUE_TYPE_OPTIONS;
  assignedToOptions = ASSIGNED_TO_OPTIONS;
  dueDateOptions = DUE_DATE_OPTIONS;
  taskStatusOptions = TASK_STATUS_OPTIONS;
  taskPriorityOptions = TASK_PRIORITY_OPTIONS;
  buttonColorOptions = BUTTON_COLOR_OPTIONS;

  connectedCallback() { this.loadData(); }

  loadData() {
    this.isLoading = true;
    this.errorMessage = null;
    Promise.all([
      getTemplates(),
      getAvailableObjects(),
      getOrgWideEmailAddresses(),
      getBrands()
    ])
    .then(([templates, objects, emails, brands]) => {
      this.brands = (brands || []).map(b => ({
        ...b,
        primaryColorStyle: 'background-color:' + (b.primaryColor || '#ccc'),
        secondaryColorStyle: 'background-color:' + (b.secondaryColor || '#ccc'),
        lastModifiedDisplay: b.lastModifiedDate ? new Date(b.lastModifiedDate).toLocaleString() : '',
        statusPillClass: 'status-pill ' + ((b.status || '').toLowerCase() === 'active' ? 'status-pill_active' : 'status-pill_draft')
      }));
      const objMap = {};
      (objects || []).forEach(o => { objMap[o.apiName] = o.label; });
      this.objectOptions = (objects || []).map(o => ({ label: o.label + ' (' + o.apiName + ')', value: o.apiName }));
      this.templates = (templates || []).map(t => ({
        ...t,
        statusClass: statusPillClass(t.status),
        statusLabel: t.status || 'Draft',
        parentObjectLabel: objMap[t.parentObjectApiName] || t.parentObjectApiName || '',
        lastModifiedDisplay: t.lastModifiedDate ? new Date(t.lastModifiedDate).toLocaleString() : ''
      }));
      this.orgWideEmailOptions = [{ label: '-- Org Default --', value: '' }]
        .concat((emails || []).map(e => ({ label: e.displayName + ' <' + e.address + '>', value: e.address })));
    })
    .catch(err => { this.errorMessage = this.extractError(err); })
    .finally(() => { this.isLoading = false; });
  }

  // ── View state ──────────────────────────────────────────────────────────────

  get isTemplatesView() { return this.sidebarView === 'templates'; }
  get isBrandsView()    { return this.sidebarView === 'brands' && !this.isBrandEditing; }
  get isBrandEditorView() { return this.sidebarView === 'brands' && this.isBrandEditing; }
  get sidebarNavClassTemplates() { return 'sidebar-nav-btn' + (this.sidebarView === 'templates' ? ' sidebar-nav-btn_active' : ''); }
  get sidebarNavClassBrands()    { return 'sidebar-nav-btn' + (this.sidebarView === 'brands'    ? ' sidebar-nav-btn_active' : ''); }

  get filteredBrands() {
    let list = this.brands;
    if (this.brandFilter !== 'all') list = list.filter(b => (b.status || '').toLowerCase() === this.brandFilter);
    if (this.brandSearchTerm) {
      const t = this.brandSearchTerm.toLowerCase();
      list = list.filter(b => (b.name || '').toLowerCase().includes(t) || (b.displayName || '').toLowerCase().includes(t));
    }
    return list;
  }
  get hasBrands() { return this.filteredBrands.length > 0; }

  get brandOptions() {
    const opts = [{ label: '-- No Brand --', value: '' }];
    (this.brands || []).filter(b => b.status === 'Active').forEach(b => {
      opts.push({ label: b.displayName || b.name, value: b.id });
    });
    return opts;
  }

  get templateHasBrand() { return !!this.draftTemplate.brandId; }
  get selectedBrandName() { return this.draftTemplate.brandName || ''; }

  get templateBrandDetails() {
    if (!this.draftTemplate.brandId) return null;
    // Use draftBrand if it matches the template's selected brand; otherwise return name only
    const bd = this.draftBrand;
    if (bd && bd.id === this.draftTemplate.brandId) {
      return {
        displayName: bd.displayName || '',
        logoUrl: bd.logoUrl || '',
        primaryColor: bd.primaryColor || '',
        secondaryColor: bd.secondaryColor || '',
        headerHtml: bd.headerHtml || '',
        footerHtml: bd.footerHtml || ''
      };
    }
    return { displayName: this.draftTemplate.brandName || '' };
  }

  get brandHeaderEditorIsRich() { return this.brandHeaderEditorMode === 'Visual'; }
  get brandHeaderEditorIsHtml() { return this.brandHeaderEditorMode === 'HTML Source'; }
  get brandFooterEditorIsRich() { return this.brandFooterEditorMode === 'Visual'; }
  get brandFooterEditorIsHtml() { return this.brandFooterEditorMode === 'HTML Source'; }

  get hasBrandImages() { return (this.brandImages || []).length > 0; }
  get brandImagesWithUrls() { return (this.brandImages || []).filter(img => img.publicUrl); }
  get hasBrandImagesWithUrls() { return this.brandImagesWithUrls.length > 0; }

  get brandStaticTags() {
    return [
      { key: 'LogoUrl',         label: '{{Brand.LogoUrl}}',         tag: '{{Brand.LogoUrl}}'         },
      { key: 'DisplayName',     label: '{{Brand.DisplayName}}',     tag: '{{Brand.DisplayName}}'     },
      { key: 'PhysicalAddress', label: '{{Brand.PhysicalAddress}}', tag: '{{Brand.PhysicalAddress}}' },
      { key: 'UnsubscribeLink', label: '{{Brand.UnsubscribeLink}}', tag: '{{Brand.UnsubscribeLink}}' },
      { key: 'ContactEmail',    label: '{{Brand.ContactEmail}}',    tag: '{{Brand.ContactEmail}}'    },
      { key: 'ContactPhone',    label: '{{Brand.ContactPhone}}',    tag: '{{Brand.ContactPhone}}'    }
    ];
  }

  get brandFilterTabClassAll()      { return 'filter-tab' + (this.brandFilter === 'all'      ? ' filter-tab_active' : ''); }
  get brandFilterTabClassActive()   { return 'filter-tab' + (this.brandFilter === 'active'   ? ' filter-tab_active' : ''); }
  get brandFilterTabClassInactive() { return 'filter-tab' + (this.brandFilter === 'inactive' ? ' filter-tab_active' : ''); }

  get brandTabClass_identity() { return 'editor-tab' + (this.brandActiveTab === 'identity' ? ' editor-tab_active' : ''); }
  get brandTabClass_colors()   { return 'editor-tab' + (this.brandActiveTab === 'colors'   ? ' editor-tab_active' : ''); }
  get brandTabClass_contact()  { return 'editor-tab' + (this.brandActiveTab === 'contact'  ? ' editor-tab_active' : ''); }
  get brandTabClass_assets()   { return 'editor-tab' + (this.brandActiveTab === 'assets'   ? ' editor-tab_active' : ''); }
  get brandTabClass_content()  { return 'editor-tab' + (this.brandActiveTab === 'content'  ? ' editor-tab_active' : ''); }
  get isBrandTab_identity() { return this.brandActiveTab === 'identity'; }
  get isBrandTab_colors()   { return this.brandActiveTab === 'colors'; }
  get isBrandTab_contact()  { return this.brandActiveTab === 'contact'; }
  get isBrandTab_assets()   { return this.brandActiveTab === 'assets'; }
  get isBrandTab_content()  { return this.brandActiveTab === 'content'; }
  // Brand AI step classes
  get brandAiStepClass1() { return 'ai-step-dot' + (this.brandAiStep === 1 ? ' ai-step-dot_active' : (this.brandAiStep > 1 ? ' ai-step-dot_done' : '')); }
  get brandAiStepClass2() { return 'ai-step-dot' + (this.brandAiStep === 2 ? ' ai-step-dot_active' : (this.brandAiStep > 2 ? ' ai-step-dot_done' : '')); }
  get brandAiStepClass3() { return 'ai-step-dot' + (this.brandAiStep === 3 ? ' ai-step-dot_active' : ''); }
  get isBrandAiStep1() { return this.brandAiStep === 1; }
  get isBrandAiStep2() { return this.brandAiStep === 2; }
  get isBrandAiStep3() { return this.brandAiStep === 3; }
  get brandSfRulesChevron() { return this.brandSfRulesExpanded ? '▲' : '▼'; }
  get brandAiCopyBtnClass() { return 'ai-copy-btn' + (this.brandPromptCopied ? ' ai-copy-btn_success' : ''); }
  get brandAiCopyBtnLabel() { return this.brandPromptCopied ? '✓ Copied!' : '⌘ Copy Prompt'; }
  get brandAiIncludedImages() { return (this.brandAiImages || []).filter(i => i.include && i.publicUrl); }

  get brandAiPrompt() {
    const bd = this.draftBrand;
    const name = bd.displayName || bd.name || '';
    const primary = bd.primaryColor || '';
    const secondary = bd.secondaryColor || '';
    const logoUrl = bd.logoUrl || '';
    const physical = bd.physicalAddress || '';
    const unsubUrl = bd.unsubscribeUrl || '';
    const unsubLabel = bd.unsubscribeLabel || 'Unsubscribe';
    const contactEmail = bd.contactEmail || '';
    const contactPhone = bd.contactPhone || '';

    const logoLine = logoUrl
      ? `  Logo: <img src="${logoUrl}" width="600" alt="${name}" style="max-width:100%;display:block;">`
      : '  Logo: (none)';

    const unsubLine = unsubUrl
      ? `  Unsubscribe: {{Brand.UnsubscribeLink}} = "${unsubUrl}" / label: "${unsubLabel}"`
      : '';
    const emailLine = contactEmail ? `  Contact Email: {{Brand.ContactEmail}} = "${contactEmail}"` : '';
    const phoneLine = contactPhone ? `  Contact Phone: {{Brand.ContactPhone}} = "${contactPhone}"` : '';

    const extraDetails = [unsubLine, emailLine, phoneLine].filter(Boolean).join('\n');

    const extraTags = [
      unsubUrl ? '  {{Brand.UnsubscribeLink}}' : '',
      contactEmail ? '  {{Brand.ContactEmail}}' : '',
      contactPhone ? '  {{Brand.ContactPhone}}' : ''
    ].filter(Boolean).join('\n');

    const imageLines = this.brandAiIncludedImages
      .map(img => {
        const w = img.width || 600;
        const hAttr = img.height ? ` height="${img.height}"` : '';
        return `  ${img.title}: <img src="${img.publicUrl}" width="${w}"${hAttr} alt="${img.title}" style="max-width:100%;display:block;">`;
      })
      .join('\n');

    const sfRules = `\n\nSALESFORCE HTML RULES — the following will BLOCK saving:\n` +
      `PROHIBITED TAGS: <meta> <html> <head> <body> <link> <script> <style> <iframe> <object> <embed>\n` +
      `  <form> <input> <button> <svg> <math> <video> <audio> <base> <noscript>\n` +
      `  <template> <details> <summary> <dialog> <picture> <source>\n` +
      `PROHIBITED PATTERNS: event handlers (onclick, onload…), javascript:/vbscript: URIs,\n` +
      `  url(https://…) in CSS, @import, expression(), -moz-binding:, behavior:`;

    return `⚠️ CRITICAL — READ BEFORE WRITING ANYTHING:
Your response must begin IMMEDIATELY with an HTML tag (e.g. <table ...).
Do NOT output <!DOCTYPE>, <html>, <head>, <meta>, <body>, <style>, or any document wrapper.
The very first character must be < and the first tag must be a content tag.

PROHIBITED TAGS — any of these will block saving:
<meta> <html> <head> <body> <link> <script> <style> <iframe> <object> <embed>
<form> <input> <button> <svg> <math> <video> <audio> <base> <noscript>
<template> <details> <summary> <dialog> <picture> <source>

PROHIBITED PATTERNS — also block saving:
• Any event handler attribute: onclick, onload, onerror, onmouseover, etc.
• javascript: or vbscript: in any href or src
• url() in CSS containing any http/https address
• @import, expression(), -moz-binding:, behavior:

You are building brand HTML for Weave — HTML injected into every email that uses this brand.
Generate TWO separate HTML blocks, clearly labelled:

  <!-- BRAND_HEADER -->
  ... your header HTML here ...
  <!-- END BRAND_HEADER -->

  <!-- BRAND_FOOTER -->
  ... your footer HTML here ...
  <!-- END BRAND_FOOTER -->

BRAND DETAILS:
  Brand Name: ${name}
  Primary Color: ${primary}
  Secondary Color: ${secondary}
${logoLine}
  Physical Address: {{Brand.PhysicalAddress}} = "${physical}"
${extraDetails}

AVAILABLE MERGE TAGS (use these — do not hardcode values):
  {{Brand.LogoUrl}}
  {{Brand.DisplayName}}
  {{Brand.PhysicalAddress}}
${extraTags}

${imageLines ? `ASSET IMAGE TAGS (use these for images, do not change the src):\n${imageLines}\n` : ''}
HEADER DESCRIPTION:
  ${this.brandAiHeaderDesc || '(none provided)'}

FOOTER DESCRIPTION:
  ${this.brandAiFooterDesc || '(none provided)'}

OUTPUT REQUIREMENTS:
• All CSS must be inline style="…" on each element — no <style> blocks
• Use table-based layout (table, tr, td) — no div-only layouts
• Max outer table width: 600px
• Web-safe fonts only: Arial, Helvetica, Georgia, 'Times New Roman', Verdana
• Use the exact hex color values from BRAND DETAILS above for all inline CSS colors
• Do NOT hardcode the logo src — use {{Brand.LogoUrl}} or the asset tag provided above
${sfRules}

Generate BRAND_HEADER and BRAND_FOOTER now.`;
  }

  get brandStatusPillClass() {
    const s = (this.draftBrand.status || '').toLowerCase();
    return 'status-pill' + (s === 'active' ? ' status-pill_active' : ' status-pill_draft');
  }

  get isSegmentsView()   { return this.sidebarView === 'segments'; }
  get sidebarNavClassSegments() { return 'sidebar-nav-btn' + (this.sidebarView === 'segments' ? ' sidebar-nav-btn_active' : ''); }
  get isBulkSendView()   { return this.sidebarView === 'bulkSend'; }
  get sidebarNavClassBulkSend()  { return 'sidebar-nav-btn' + (this.sidebarView === 'bulkSend'   ? ' sidebar-nav-btn_active' : ''); }
  get isSchedulerView()  { return this.sidebarView === 'scheduler'; }
  get sidebarNavClassScheduler() { return 'sidebar-nav-btn' + (this.sidebarView === 'scheduler' ? ' sidebar-nav-btn_active' : ''); }
  get isResourcesView()  { return this.sidebarView === 'resources'; }
  get sidebarNavClassResources() { return 'sidebar-nav-btn' + (this.sidebarView === 'resources' ? ' sidebar-nav-btn_active' : ''); }

  get schedulerIsActive() { return !!(this.schedulerStatus && this.schedulerStatus.isActive); }
  get schedulerStatusLabel() { return this.schedulerIsActive ? 'Active' : 'Inactive'; }
  get schedulerStatusPillClass() { return this.schedulerIsActive ? 'status-pill status-pill_active' : 'status-pill status-pill_draft'; }
  get schedulerNextFireTime() {
    if (!this.schedulerStatus || !this.schedulerStatus.nextFireTime) return null;
    return new Date(this.schedulerStatus.nextFireTime).toLocaleString();
  }
  get schedulerCronExpression() { return this.schedulerStatus ? this.schedulerStatus.cronExpression : null; }
  get schedulerFrequencyLabel() {
    const opt = this.frequencyOptions.find(o => o.value === (this.schedulerStatus && this.schedulerStatus.frequency));
    return opt ? opt.label : (this.schedulerStatus && this.schedulerStatus.cronExpression) || '';
  }
  get frequencyOptions() {
    return [
      { label: 'Every 5 minutes',  value: 'every_5_min' },
      { label: 'Every 10 minutes', value: 'every_10_min' },
      { label: 'Every 15 minutes', value: 'every_15_min' },
      { label: 'Every 30 minutes', value: 'every_30_min' },
      { label: 'Every hour',       value: 'every_hour' },
      { label: 'Every 6 hours',    value: 'every_6_hours' },
      { label: 'Every 12 hours',   value: 'every_12_hours' },
      { label: 'Daily (8 AM)',     value: 'daily' }
    ];
  }

  get isLibraryView() { return !this.isEditing && this.isTemplatesView; }
  get isEditorView() { return this.isEditing; }
  get mainPanelClass() { return 'main-panel' + ((this.isEditorView || this.isBrandEditorView) ? ' main-panel_editor' : ''); }

  get filteredTemplates() {
    let list = this.templates;
    if (this.libraryFilter !== 'all') {
      list = list.filter(t => (t.status || '').toLowerCase() === this.libraryFilter);
    }
    if (this.searchTerm) {
      const term = this.searchTerm.toLowerCase();
      list = list.filter(t =>
        (t.name || '').toLowerCase().includes(term) ||
        (t.parentObjectApiName || '').toLowerCase().includes(term)
      );
    }
    return list;
  }

  get hasTemplates() { return this.filteredTemplates.length > 0; }
  get hasId() { return !!this.draftTemplate.id; }
  get hasQueries() { return (this.draftTemplate.queries || []).length > 0; }

  get parentQueryOptions() {
    return [{ label: '-- None (root query) --', value: '' }].concat(
      (this.draftTemplate.queries || []).map(q => ({
        label: q.name,
        value: q.localKey || q.queryApiName || ''
      }))
    );
  }

  get queryListItems() {
    const queries = this.draftTemplate.queries || [];
    const keyToName = {};
    queries.forEach(q => { keyToName[q.localKey || q.queryApiName || ''] = q.name; });
    return queries.map(q => {
      const parentKey = q.parentQueryLocalKey || '';
      const parentName = parentKey ? keyToName[parentKey] : null;
      return {
        ...q,
        isChild: !!parentName,
        parentQueryName: parentName || '',
        cardClass: parentName ? 'item-card item-card--child' : 'item-card'
      };
    });
  }
  get hasRecipients() { return (this.draftTemplate.recipients || []).length > 0; }
  get hasActions() { return (this.draftTemplate.actions || []).length > 0; }

  get templateStatusPillClass() { return statusPillClass(this.draftTemplate.status); }

  get fromEmailType() {
    if (this._fromEmailType !== null) return this._fromEmailType;
    return this.draftTemplate.defaultFromEmail ? 'OrgWide' : 'CurrentUser';
  }
  get isFromCurrentUser() { return this.fromEmailType === 'CurrentUser'; }
  get isFromOrgWide() { return this.fromEmailType === 'OrgWide'; }
  get showDocumentFormat() { return this.draftTemplate.templateOutputType === 'Document'; }
  get showCustomPdfSize() { return this.draftTemplate.pdfPageSize === 'Custom'; }
  get isDocumentTemplate() { return this.draftTemplate.templateOutputType === 'Document'; }
  get isEmailTemplate() { return this.draftTemplate.templateOutputType !== 'Document'; }

  // ── Filter tab class getters ────────────────────────────────────────────────

  get filterTabClassAll()      { return 'filter-tab' + (this.libraryFilter === 'all'      ? ' filter-tab_active' : ''); }
  get filterTabClassActive()   { return 'filter-tab' + (this.libraryFilter === 'active'   ? ' filter-tab_active' : ''); }
  get filterTabClassDraft()    { return 'filter-tab' + (this.libraryFilter === 'draft'    ? ' filter-tab_active' : ''); }
  get filterTabClassArchived() { return 'filter-tab' + (this.libraryFilter === 'archived' ? ' filter-tab_active' : ''); }

  // ── Editor tab class getters ────────────────────────────────────────────────

  get isTab_settings()   { return this.activeTab === 'settings'; }
  get isTab_queries()    { return this.activeTab === 'queries'; }
  get isTab_body()       { return this.activeTab === 'body'; }
  get isTab_recipients() { return this.activeTab === 'recipients'; }
  get isTab_actions()    { return this.activeTab === 'actions'; }
  get isTab_preview()    { return this.activeTab === 'preview'; }

  get tabClass_settings()   { return 'editor-tab' + (this.activeTab === 'settings'   ? ' editor-tab_active' : ''); }
  get tabClass_queries()    { return 'editor-tab' + (this.activeTab === 'queries'    ? ' editor-tab_active' : ''); }
  get tabClass_body()       { return 'editor-tab' + (this.activeTab === 'body'       ? ' editor-tab_active' : ''); }
  get tabClass_recipients() { return 'editor-tab' + (this.activeTab === 'recipients' ? ' editor-tab_active' : ''); }
  get tabClass_actions()    { return 'editor-tab' + (this.activeTab === 'actions'    ? ' editor-tab_active' : ''); }
  get tabClass_preview()    { return 'editor-tab' + (this.activeTab === 'preview'    ? ' editor-tab_active' : ''); }

  get componentEditorIsRich() { return this.componentEditorMode === 'rich'; }
  get componentEditorIsHtml() { return this.componentEditorMode === 'html'; }
  get componentEditorToggleLabel() { return this.componentEditorMode === 'rich' ? '< > HTML' : 'Rich Text'; }

  get mergeTagGroups() {
    const term = (this.mergeTagSearch || '').toLowerCase();
    const groups = [];

    // Parent fields
    const parentFields = this.parentFieldsForMergeTags.filter(f =>
      !term || f.label.toLowerCase().includes(term) || f.apiName.toLowerCase().includes(term)
    );
    if (parentFields.length > 0 || !term) {
      groups.push({
        key: 'parent',
        label: 'Parent — ' + (this.draftTemplate.parentObjectApiName || ''),
        prefix: 'Parent',
        fields: parentFields,
        hasFields: parentFields.length > 0
      });
    }

    // Query fields (for related records — single-record lookups)
    (this.draftTemplate.queries || []).forEach(q => {
      const rawFields = this._parseFieldsFromSoql(q.soqlQuery || '');
      const tagPrefix = q.name || 'Query';
      const fields = rawFields
        .map(f => ({ label: f, apiName: f, tag: '{{' + tagPrefix + '.' + f + '}}' }))
        .filter(f => !term || f.label.toLowerCase().includes(term));
      if (fields.length > 0 || !term) {
        groups.push({
          key: q.localKey,
          label: q.name + ' (' + (q.soqlObject || '') + ')',
          prefix: tagPrefix,
          fields,
          hasFields: fields.length > 0
        });
      }
    });

    // Build tag property on parent group now that prefix is known
    groups.forEach(g => {
      if (!g.fields[0]?.tag) {
        g.fields = g.fields.map(f => ({
          ...f,
          tag: '{{' + g.prefix + '.' + f.apiName + '}}'
        }));
      }
    });

    return groups;
  }

  _parseFieldsFromSoql(soql) {
    const match = soql.match(/SELECT\s+(.+?)\s+FROM/i);
    if (!match) return [];
    return match[1].split(',').map(f => f.trim()).filter(Boolean);
  }

  loadParentFieldsForMergeTags() {
    const obj = this.draftTemplate.parentObjectApiName;
    if (!obj || this.parentFieldsForMergeTags.length > 0) return;
    this.isLoadingMergeTags = true;
    getFieldsForObject({ objectApiName: obj })
      .then(fields => { this.parentFieldsForMergeTags = fields; })
      .catch(() => { this.parentFieldsForMergeTags = []; })
      .finally(() => { this.isLoadingMergeTags = false; });
  }

  get queryOptionsForComponent() {
    return (this.draftTemplate.queries || []).map(q => ({ label: q.name, value: q.localKey }));
  }
  get editingComponentIsText()         { return this.editingComponent.componentType === 'Text'; }
  get editingComponentIsHtmlBlock()    { return this.editingComponent.componentType === 'HTML Block'; }
  get editingComponentIsRelatedTable() { return this.editingComponent.componentType === 'Related Table'; }
  get editingComponentIsButton()       { return this.editingComponent.componentType === 'Button'; }
  get editingComponentIsImage()        { return this.editingComponent.componentType === 'Image'; }
  get editingComponentHasContent()     { return this.editingComponentIsText || this.editingComponentIsHtmlBlock || this.editingComponentIsButton; }
  get editingComponentButtonConfig()   { return this._parseComponentConfig(this.editingComponent.configJson); }
  get isTab_files()      { return this.activeTab === 'files'; }
  get tabClass_files()   { return 'editor-tab' + (this.activeTab === 'files'     ? ' editor-tab_active' : ''); }
  get isTab_schedules()    { return this.activeTab === 'schedules'; }
  get tabClass_schedules() { return 'editor-tab' + (this.activeTab === 'schedules'   ? ' editor-tab_active' : ''); }
  get isTab_datasources()    { return this.activeTab === 'datasources'; }
  get tabClass_datasources() { return 'editor-tab' + (this.activeTab === 'datasources' ? ' editor-tab_active' : ''); }
  get isTab_signerfields()    { return this.activeTab === 'signerfields'; }
  get tabClass_signerfields() { return 'editor-tab' + (this.activeTab === 'signerfields' ? ' editor-tab_active' : ''); }
  get signerFieldTypeOptions() {
    return [
      { label: 'Text', value: 'Text' }, { label: 'Number', value: 'Number' },
      { label: 'Currency', value: 'Currency' }, { label: 'Date', value: 'Date' },
      { label: 'Checkbox', value: 'Checkbox' }, { label: 'Picklist', value: 'Picklist' }
    ];
  }
  get allComponentHtml() {
    return (this.draftTemplate.components || []).map(c => c.htmlContent || '').join('\n');
  }
  get scheduleModeOptions() { return [{ label: 'Send Once', value: 'once' }, { label: 'Recurring', value: 'recurring' }]; }
  get isScheduleModeOnce() { return this.scheduleMode === 'once'; }
  get isScheduleModeRecurring() { return this.scheduleMode === 'recurring'; }
  get schedModeTabOnce() { return this.scheduleMode === 'once' ? 'filter-tab filter-tab_active' : 'filter-tab'; }
  get schedModeTabRecurring() { return this.scheduleMode === 'recurring' ? 'filter-tab filter-tab_active' : 'filter-tab'; }
  get isRecurringEndByDate() { return this.recurringEndType === 'endDate'; }
  get isRecurringEndByMaxSends() { return this.recurringEndType === 'maxSends'; }
  get minScheduleDate() {
    const d = new Date();
    return d.toISOString().substring(0, 10);
  }
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
  get hasScheduledSends() { return this.scheduledSends && this.scheduledSends.length > 0; }
  get templateHasId() { return !!this.draftTemplate.id; }
  get hasAttachmentRules() { return (this.draftTemplate.attachments || []).length > 0; }
  get selectedAttachmentRule() {
    if (!this.selectedAttachmentRuleKey) return null;
    return (this.draftTemplate.attachments || []).find(ac => ac.localKey === this.selectedAttachmentRuleKey) || null;
  }
  get isAttachmentRuleStatic() { return (this.selectedAttachmentRule?.attachmentSource || 'Static File') === 'Static File'; }
  get isAttachmentRuleRelated() { return (this.selectedAttachmentRule?.attachmentSource || '') === 'Related Record Files'; }
  get isAttachmentRuleDynamic() { return !this.isAttachmentRuleStatic; }
  get attachmentSourceOptions() { return ATTACHMENT_SOURCE_OPTIONS; }
  get queryOptions() { return (this.draftTemplate.queries || []).map(q => ({ label: q.name || q.soqlQuery, value: q.localKey })); }
  get updateableFieldOptions() {
    return (this.updateableFields || []).map(f => ({ label: f.label + ' (' + f.apiName + ')', value: f.apiName }));
  }
  get signerFieldTargetFieldOptions() {
    return (this.updateableFields || []).map(f => ({ label: f.label + ' (' + f.apiName + ')', value: f.apiName }));
  }
  get hasSignerFieldTargetOptions() { return this.signerFieldTargetFieldOptions.length > 0; }
  get parentFieldOptions() {
    return (this.parentFieldsForMergeTags || []).map(f => ({ label: f.label + ' (' + f.apiName + ')', value: f.apiName }));
  }
  get editingRecipientIsParentField()      { return (this.editingRecipient.recipientSourceType || '') === 'Parent Field'; }
  get editingRecipientIsRelatedRecords()   { return (this.editingRecipient.recipientSourceType || '') === 'Related Records'; }
  get editingRecipientIsManual()           { return (this.editingRecipient.recipientSourceType || '') === 'Manual'; }
  get editingRecipientIsDynamicSegment()   { return (this.editingRecipient.recipientSourceType || '') === 'Dynamic Segment'; }
  get segmentComboboxOptions() {
    const opts = [{ label: '-- Select a Segment --', value: '' }];
    (this.availableSegments || []).forEach(s => {
      opts.push({ label: s.Name + ' (' + s.Object_API_Name__c + ')', value: s.Id });
    });
    return opts;
  }
  get hasAvailableSegments() { return (this.availableSegments || []).length > 0; }
  get recipientLinkedQueryFieldOptions() {
    return (this.editingRecipient._linkedQueryFields || []).map(f => ({ label: f, value: f }));
  }
  get recipientHasLinkedQueryFields() {
    return (this.editingRecipient._linkedQueryFields || []).length > 0;
  }
  get templateQueryOptions() {
    return (this.draftTemplate.queries || []).map(q => ({ label: q.name, value: q.localKey }));
  }
  get editingActionIsUpdateField() { return (this.editingAction.actionType || '') === 'Update Field'; }
  get editingActionIsCreateTask() { return (this.editingAction.actionType || '') === 'Create Task'; }
  get editingActionDueDateIsDays() { return (this.editingAction.dueDateStrategy || '') === 'Days After'; }
  get editingActionAssignedSpecific() { return (this.editingAction.assignedToType || '') === 'Specific User'; }
  get editingActionShowsMergeTags() {
    return this.editingActionIsCreateTask || this.editingActionIsUpdateField;
  }
  get actionModalContainerClass() {
    return 'modal-container' + (this.editingActionShowsMergeTags ? ' modal-container_wide' : '');
  }
  get actionModalBodyClass() {
    return 'modal-body' + (this.editingActionShowsMergeTags ? ' modal-body_cols' : '');
  }
  get actionModalLeftClass() {
    return this.editingActionShowsMergeTags ? 'comp-modal-left' : '';
  }

  get regionGroups() {
    const groups = [
      { region: 'Header', components: [], hasComponents: false },
      { region: 'Body', components: [], hasComponents: false },
      { region: 'Footer', components: [], hasComponents: false }
    ];
    (this.draftTemplate.components || []).forEach(c => {
      const group = groups.find(g => g.region === c.region);
      if (group) group.components.push(c);
    });
    groups.forEach(g => { g.hasComponents = g.components.length > 0; });
    return groups;
  }

  // ── Library handlers ────────────────────────────────────────────────────────

  handleStatusFilter(event) { this.libraryFilter = event.currentTarget.dataset.filter; }
  handleSearch(event) { this.searchTerm = event.detail.value; }
  dismissInfoBanner() { this.showInfoBanner = false; }

  backToLibrary() {
    this.isEditing = false;
    this.isDirty = false;
    this.loadData();
  }

  handleNew() {
    this.draftTemplate = emptyTemplate();
    this.relatedObjectOptions = [];
    this.activeTab = 'settings';
    this.previewSubject = '';
    this.previewHtml = '';
    this.isDirty = false;
    this._fromEmailType = null;
    this.isEditing = true;
  }

  openTemplate(event) {
    const templateId = event.currentTarget.dataset.id;
    this.loadTemplateById(templateId);
  }

  handleTemplateClick(event) {
    const templateId = event.currentTarget.dataset.id;
    this.loadTemplateById(templateId);
  }

  loadTemplateById(templateId) {
    this.isLoading = true;
    loadTemplate({ templateId })
      .then(dto => {
        this.draftTemplate = {
          ...emptyTemplate(),
          ...dto,
          queries: (dto.queries || []).map(q => ({
            ...q,
            localKey: q.localKey || nextKey(),
            soqlObject: q.soqlObject || parseSoqlObject(q.soqlQuery)
          })),
          components: (dto.components || []).map(c => ({ ...c, localKey: c.localKey || nextKey() })),
          recipients: (dto.recipients || []).map(r => ({ ...r, localKey: r.localKey || nextKey() })),
          actions: (dto.actions || []).map(a => ({
            ...a,
            localKey: a.localKey || nextKey(),
            isUpdateField: a.actionType === 'Update Field',
            isCreateTask: a.actionType === 'Create Task'
          })),
          attachments: (dto.attachments || []).map(ac => {
            const lk = ac.localKey || nextKey();
            const linkedQ = ac.linkedQueryId
              ? (dto.queries || []).find(q => q.id === ac.linkedQueryId)
              : null;
            return { ...ac, localKey: lk, _linkedQueryLocalKey: linkedQ ? linkedQ.localKey : null };
          }),
          deletedQueryIds: [], deletedComponentIds: [], deletedRecipientIds: [], deletedActionIds: [],
          deletedAttachmentIds: []
        };
        this.selectedAttachmentRuleKey = null;
        this.activeTab = 'settings';
        this.isDirty = false;
        this._fromEmailType = null;
        this.isEditing = true;
        if (dto.parentObjectApiName) {
          this.loadRelatedObjects(dto.parentObjectApiName);
          this.loadSegmentsForObject();
        }
        if (dto.brandId) {
          loadBrand({ brandId: dto.brandId })
            .then(b => { this.draftBrand = { ...emptyBrand(), ...b }; })
            .catch(() => {});
        }
      })
      .catch(err => { this.errorMessage = this.extractError(err); })
      .finally(() => { this.isLoading = false; });
  }

  loadSegmentsForObject() {
    getActiveSegments({ objectApiName: '' })
      .then(segments => { this.availableSegments = segments || []; })
      .catch(() => { this.availableSegments = []; });
  }

  handleBack() { this.backToLibrary(); }

  handleTabClick(event) {
    this.activeTab = event.currentTarget.dataset.tab;
    this.errorMessage = null;
    if (this.activeTab === 'files') this.loadTemplateFiles();
    if (this.activeTab === 'schedules') this.loadScheduledSends();
    if (this.activeTab === 'body') this.loadParentFieldsForMergeTags();
    if (this.activeTab === 'signerfields') {
      this.loadSignerFormFields();
      // Load updateable fields for write-back field picker if not already loaded
      const obj = this.draftTemplate.parentObjectApiName;
      if (obj && !this.updateableFields.length) {
        getUpdateableFieldsForObject({ objectApiName: obj })
          .then(fields => { this.updateableFields = fields || []; })
          .catch(() => { this.updateableFields = []; });
      }
    }
  }

  loadSignerFormFields() {
    if (!this.draftTemplate.id) return;
    this.isSignerFieldLoading = true;
    getSignerFormFields({ templateId: this.draftTemplate.id })
      .then(fields => {
        this.signerFormFields = (fields || []).map(f => ({
          ...f, key: f.Id,
          fieldTypeLabel: f.Field_Type__c || 'Text',
          computedMergeTag: f.mergeTag || ''
        }));
      })
      .catch(() => {})
      .finally(() => { this.isSignerFieldLoading = false; });
  }

  handleSignerFieldNew() {
    this.draftSignerField = { templateId: this.draftTemplate.id, fieldType: 'Text', required: false, writeBack: false, onCertificate: false };
    this.isEditingSignerField = true;
  }

  handleSignerFieldEdit(evt) {
    const id = evt.currentTarget.dataset.id;
    const f  = this.signerFormFields.find(x => x.Id === id);
    if (!f) return;
    this.draftSignerField = {
      Id: f.Id, templateId: this.draftTemplate.id,
      tagLabel: f.Tag_Label__c, signerRole: f.Signer_Role__c,
      fieldType: f.Field_Type__c, targetFieldApiName: f.Target_Field_Api_Name__c,
      required: f.Required__c, writeBack: f.Write_Back__c, onCertificate: f.On_Certificate__c,
      picklistValues: f.Picklist_Values__c, displayOrder: f.Display_Order__c
    };
    this.isEditingSignerField = true;
  }

  handleSignerFieldFieldChange(evt) {
    const field = evt.currentTarget.dataset.field;
    const value = evt.detail ? (evt.detail.checked !== undefined ? evt.detail.checked : evt.detail.value) : evt.target.value;
    this.draftSignerField = { ...this.draftSignerField, [field]: value };
  }

  handleSignerFieldSave() {
    this.isSignerFieldLoading = true;
    upsertSignerFormField({ fieldJson: JSON.stringify(this.draftSignerField) })
      .then(() => {
        this.isEditingSignerField = false;
        this.loadSignerFormFields();
      })
      .catch(err => { this.errorMessage = this.extractError(err); })
      .finally(() => { this.isSignerFieldLoading = false; });
  }

  handleSignerFieldCancel() { this.isEditingSignerField = false; }

  handleSignerFieldDelete(evt) {
    const id = evt.currentTarget.dataset.id;
    // eslint-disable-next-line no-alert
    if (!window.confirm('Delete this signer field?')) return;
    deleteSignerFormField({ fieldId: id })
      .then(() => { this.loadSignerFormFields(); })
      .catch(err => { this.errorMessage = this.extractError(err); });
  }

  handleDataSourceConfigChange(event) {
    const config = event.detail;
    if (!config) return;
    this.draftTemplate = {
      ...this.draftTemplate,
      templateChannels: config.templateChannels || this.draftTemplate.templateChannels,
      dataSourceConfig: JSON.stringify(config)
    };
    this.isDirty = true;
  }

  loadRelatedObjects(parentObjectApiName) {
    if (!parentObjectApiName) { this.relatedObjectOptions = []; this.relatedObjectMeta = {}; return; }
    getRelatedObjectsForQuery({ parentObjectApiName })
      .then(objects => {
        const list = objects || [];
        this.relatedObjectOptions = list.map(o => {
          let label = o.label + ' (' + o.apiName + ')';
          if (o.relationshipType === 'up') label += ' ↑ via ' + o.connectorField;
          return { label, value: o.apiName };
        });
        const meta = {};
        list.forEach(o => { meta[o.apiName] = { type: o.relationshipType || 'down', connectorField: o.connectorField || '' }; });
        this.relatedObjectMeta = meta;
      })
      .catch(() => { this.relatedObjectOptions = []; this.relatedObjectMeta = {}; });
  }

  handleFieldChange(event) {
    const field = event.target.dataset.field;
    const value = event.detail.value;
    this.draftTemplate = { ...this.draftTemplate, [field]: value };
    this.isDirty = true;
    if (field === 'parentObjectApiName' && value) {
      this.loadRelatedObjects(value);
      this.loadSegmentsForObject();
      // Auto-create a ParentRecord query for new templates
      if (!this.draftTemplate.id) {
        const hasParentQuery = this.draftTemplate.queries.some(q =>
          q.queryApiName === 'ParentRecord' || q.relationshipType === 'self'
        );
        if (!hasParentQuery) {
          const parentQuery = {
            id: null, localKey: nextKey(), name: 'Parent Record',
            soqlQuery: `SELECT Id FROM ${value} LIMIT 1`,
            soqlObject: value, queryApiName: 'ParentRecord',
            parentLookupField: 'Id', relationshipType: 'self',
            parentQueryId: null, parentQueryLocalKey: null
          };
          this.draftTemplate = {
            ...this.draftTemplate,
            queries: [parentQuery, ...this.draftTemplate.queries]
          };
        }
      }
    }
  }

  handleCheckboxChange(event) {
    const field = event.target.dataset.field;
    this.draftTemplate = { ...this.draftTemplate, [field]: event.target.checked };
    this.isDirty = true;
  }

  handleFromEmailTypeChange(event) {
    const type = event.detail.value;
    this._fromEmailType = type;
    if (type === 'CurrentUser') {
      this.draftTemplate = { ...this.draftTemplate, defaultFromEmail: '' };
    } else {
      // Switch to OrgWide — keep existing address if any
      this.draftTemplate = { ...this.draftTemplate, defaultFromEmail: this.draftTemplate.defaultFromEmail || '' };
    }
    this.isDirty = true;
  }

  handleSave() { this.doSave(); }

  handleSaveActivate() {
    this.draftTemplate = { ...this.draftTemplate, status: 'Active' };
    this.doSave();
  }

  doSave() {
    if (!this.draftTemplate.name) {
      this.errorMessage = 'Template name is required.';
      return;
    }
    if (!this.draftTemplate.parentObjectApiName) {
      this.errorMessage = 'Parent object is required.';
      return;
    }
    this.isLoading = true;
    // Reset email-only fields for Document templates
    let draft = this.draftTemplate;
    if (draft.templateOutputType === 'Document') {
      draft = { ...draft, allowUserEditBeforeSend: false, storeEmailHistory: false, defaultFromEmail: '' };
    }
    const payload = JSON.stringify(draft);
    saveTemplate({ templateJson: payload })
      .then(dto => {
        this.draftTemplate = {
          ...emptyTemplate(),
          ...dto,
          queries: (dto.queries || []).map(q => ({
            ...q,
            localKey: q.localKey || nextKey(),
            soqlObject: q.soqlObject || parseSoqlObject(q.soqlQuery)
          })),
          components: (dto.components || []).map(c => ({ ...c, localKey: c.localKey || nextKey() })),
          recipients: (dto.recipients || []).map(r => ({ ...r, localKey: r.localKey || nextKey() })),
          actions: (dto.actions || []).map(a => ({
            ...a,
            localKey: a.localKey || nextKey(),
            isUpdateField: a.actionType === 'Update Field',
            isCreateTask: a.actionType === 'Create Task'
          })),
          attachments: (dto.attachments || []).map(ac => {
            const lk = ac.localKey || nextKey();
            const linkedQ = ac.linkedQueryId
              ? (dto.queries || []).find(q => q.id === ac.linkedQueryId)
              : null;
            return { ...ac, localKey: lk, _linkedQueryLocalKey: linkedQ ? linkedQ.localKey : null };
          }),
          deletedQueryIds: [], deletedComponentIds: [], deletedRecipientIds: [], deletedActionIds: [],
          deletedAttachmentIds: []
        };
        this.selectedAttachmentRuleKey = null;
        this.isDirty = false;
        this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Template saved successfully.', variant: 'success' }));
      })
      .catch(err => { this.errorMessage = this.extractError(err); })
      .finally(() => { this.isLoading = false; });
  }

  deleteTemplateFromLibrary(event) {
    event.stopPropagation();
    const templateId = event.currentTarget.dataset.id;
    if (!confirm('Delete this template? This cannot be undone.')) return;
    this.isLoading = true;
    deleteTemplate({ templateId })
      .then(() => {
        this.templates = this.templates.filter(t => t.id !== templateId);
        this.dispatchEvent(new ShowToastEvent({ title: 'Deleted', message: 'Template deleted.', variant: 'success' }));
      })
      .catch(err => { this.errorMessage = this.extractError(err); })
      .finally(() => { this.isLoading = false; });
  }

  handleDeleteTemplate(event) { this.deleteTemplateFromLibrary(event); }

  handleCloneOpen(event) {
    event.stopPropagation();
    const templateId = event.currentTarget.dataset.id;
    const tmpl = this.templates.find(t => t.id === templateId);
    this.cloneSourceId = templateId;
    this.cloneName = (tmpl ? tmpl.name : '') + ' (Copy)';
    this.cloneApiName = '';
    this.cloneOutputType = tmpl?.outputType || 'Email';
    this.showCloneModal = true;
  }

  handleCloneFieldChange(event) {
    const field = event.target.dataset.field;
    this[field] = event.detail.value;
  }

  handleCloneModalClose() { this.showCloneModal = false; }

  handleCloneConfirm() {
    if (!this.cloneName || !this.cloneApiName) {
      this.errorMessage = 'Name and API Name are required to clone.';
      return;
    }
    this.isCloning = true;
    this.errorMessage = null;
    cloneTemplate({
      templateId: this.cloneSourceId,
      newName: this.cloneName,
      newApiName: this.cloneApiName,
      newOutputType: this.cloneOutputType
    })
      .then(newTemplateId => {
        this.showCloneModal = false;
        this.dispatchEvent(new ShowToastEvent({ title: 'Cloned', message: 'Template cloned successfully.', variant: 'success' }));
        this.loadData();
        this.loadTemplateById(newTemplateId);
      })
      .catch(err => { this.errorMessage = this.extractError(err); })
      .finally(() => { this.isCloning = false; });
  }

  // ── Queries ─────────────────────────────────────────────────────────────────

  handleAddQuery() {
    const parentObj = this.draftTemplate.parentObjectApiName || '';
    this.editingQuery = {
      name: '',
      soqlQuery: parentObj ? `SELECT Id FROM ${parentObj} LIMIT 50` : '',
      soqlObject: parentObj,
      parentLookupField: 'Id',
      localKey: nextKey()
    };
    this.editingQueryKey = this.editingQuery.localKey;
    this.showQueryModal = true;
  }

  handleEditQuery(event) {
    const key = event.currentTarget.dataset.key;
    const q = this.draftTemplate.queries.find(x => x.localKey === key);
    if (q) {
      this.editingQuery = { ...q };
      this.editingQueryKey = key;
      this.showQueryModal = true;
    }
  }

  handleDeleteQuery(event) {
    const key = event.currentTarget.dataset.key;
    const q = this.draftTemplate.queries.find(x => x.localKey === key);
    const updatedQueries = this.draftTemplate.queries.filter(x => x.localKey !== key);
    const deletedIds = q?.id ? [...this.draftTemplate.deletedQueryIds, q.id] : [...this.draftTemplate.deletedQueryIds];
    this.draftTemplate = { ...this.draftTemplate, queries: updatedQueries, deletedQueryIds: deletedIds };
    this.isDirty = true;
  }

  handleQueryNameChange(event) {
    this.editingQuery = { ...this.editingQuery, name: event.detail.value };
  }

  handleQueryEditorChange(event) {
    this.editingQuery = { ...this.editingQuery, ...event.detail };
  }

  handleQueryModalSave() {
    if (!this.editingQuery.name) return;
    const existing = this.draftTemplate.queries.find(q => q.localKey === this.editingQueryKey);
    let updatedQueries;
    if (existing) {
      updatedQueries = this.draftTemplate.queries.map(q => q.localKey === this.editingQueryKey ? { ...this.editingQuery } : q);
    } else {
      updatedQueries = [...this.draftTemplate.queries, { ...this.editingQuery }];
    }
    this.draftTemplate = { ...this.draftTemplate, queries: updatedQueries };
    this.isDirty = true;
    this.showQueryModal = false;
    this.editingQuery = {};
  }

  handleQueryModalClose() {
    this.showQueryModal = false;
    this.editingQuery = {};
  }

  // ── Components ───────────────────────────────────────────────────────────────

  handleComponentTypeSelect(event) { this.newComponentType = event.detail.value; }
  handleRegionSelect(event) { this.newComponentRegion = event.detail.value; }

  handleCanvasComponentsChanged(event) {
    this.draftTemplate = { ...this.draftTemplate, components: event.detail.components };
    this.isDirty = true;
  }

  handleAddComponent() {
    const newComp = {
      id: null,
      localKey: nextKey(),
      name: this.newComponentType + ' ' + (this.draftTemplate.components.length + 1),
      componentType: this.newComponentType,
      region: this.newComponentRegion,
      displayOrder: this.draftTemplate.components.filter(c => c.region === this.newComponentRegion).length + 1,
      linkedQueryId: null,
      linkedQueryName: null,
      configJson: null,
      htmlOutput: ''
    };
    this.draftTemplate = { ...this.draftTemplate, components: [...this.draftTemplate.components, newComp] };
    this.isDirty = true;
  }

  handleEditComponent(event) {
    const key = event.detail.key;
    const comp = this.draftTemplate.components.find(c => c.localKey === key);
    if (comp) {
      this.editingComponent = { ...comp };
      this.editingComponentKey = key;
      this.componentEditorMode = 'rich';
      this.mergeTagSearch = '';
      this.showComponentModal = true;
      if (comp.componentType === 'Text' || comp.componentType === 'HTML Block' || comp.componentType === 'Button') {
        this.loadParentFieldsForMergeTags();
      }
      // Auto-build columns if Related Table has a linked query but no columns yet
      if (comp.componentType === 'Related Table' && comp._linkedQueryLocalKey) {
        const cfg = this._parseComponentConfig(comp.configJson);
        if (!cfg.columns || cfg.columns.length === 0) {
          const q = this.draftTemplate.queries.find(x => x.localKey === comp._linkedQueryLocalKey);
          if (q) {
            const fields = this._parseFieldsFromSoql(q.soqlQuery || '');
            const columns = fields.map((apiName, idx) => ({ apiName, label: apiName, order: idx + 1 }));
            this.editingComponent = {
              ...this.editingComponent,
              configJson: JSON.stringify({ ...cfg, columns })
            };
          }
        }
      }
    }
  }

  handleToggleEditorMode() {
    this.componentEditorMode = this.componentEditorMode === 'rich' ? 'html' : 'rich';
  }

  handleRichTextChange(event) {
    this.editingComponent = { ...this.editingComponent, htmlOutput: event.detail.value };
  }

  handleMergeTagSearch(event) {
    this.mergeTagSearch = event.target.value;
  }

  handleInsertMergeTag(event) {
    const tag = event.currentTarget.dataset.tag;
    // Button: append tag to URL in configJson
    if (this.editingComponentIsButton) {
      const cfg = this._parseComponentConfig(this.editingComponent.configJson);
      cfg.url = (cfg.url || '') + tag;
      this.editingComponent = { ...this.editingComponent, configJson: JSON.stringify(cfg) };
      return;
    }
    if (this.componentEditorMode === 'rich') {
      const rt = this.template.querySelector('lightning-input-rich-text');
      if (rt) {
        rt.insertTextAtCursor(tag);
        return;
      }
    }
    // HTML mode or fallback: append at end
    const current = this.editingComponent.htmlOutput || '';
    this.editingComponent = { ...this.editingComponent, htmlOutput: current + tag };
  }

  handleCopyMergeTag(event) {
    event.stopPropagation();
    const tag = event.currentTarget.dataset.tag;
    navigator.clipboard?.writeText(tag);
  }

  handleComponentFieldChange(event) {
    const field = event.target.dataset.field;
    this.editingComponent = { ...this.editingComponent, [field]: event.detail.value };
  }

  handleComponentLinkedQueryChange(event) {
    const selectedKey = event.detail.value;
    const q = this.draftTemplate.queries.find(x => x.localKey === selectedKey);
    const fields = this._parseFieldsFromSoql(q?.soqlQuery || '');
    const existingCfg = this._parseComponentConfig(this.editingComponent.configJson);
    const existingCols = existingCfg.columns || [];
    // Merge: keep existing labels/order for fields still present, add new ones, drop removed
    const colMap = {};
    existingCols.forEach(c => { colMap[c.apiName] = c; });
    const columns = fields.map((apiName, idx) => colMap[apiName]
      ? { ...colMap[apiName] }
      : { apiName, label: apiName, order: idx + 1 }
    );
    columns.forEach((c, i) => { c.order = i + 1; });
    this.editingComponent = {
      ...this.editingComponent,
      linkedQueryId: q?.id || null,
      linkedQueryName: q?.name || '',
      _linkedQueryLocalKey: selectedKey,
      configJson: JSON.stringify({ ...existingCfg, columns })
    };
  }

  _parseComponentConfig(configJson) {
    if (!configJson) return {};
    try { return JSON.parse(configJson); } catch (e) { return {}; }
  }

  get editingComponentColumns() {
    const cfg = this._parseComponentConfig(this.editingComponent.configJson);
    return (cfg.columns || []).map((c, idx) => ({
      ...c,
      _idx: idx,
      _isFirst: idx === 0,
      _isLast: idx === (cfg.columns.length - 1)
    }));
  }

  get editingComponentHasLinkedQuery() {
    return !!this.editingComponent._linkedQueryLocalKey;
  }

  _updateComponentColumns(updater) {
    const cfg = this._parseComponentConfig(this.editingComponent.configJson);
    const columns = updater(cfg.columns || []);
    columns.forEach((c, i) => { c.order = i + 1; });
    this.editingComponent = {
      ...this.editingComponent,
      configJson: JSON.stringify({ ...cfg, columns })
    };
  }

  handleColumnLabelChange(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    const value = event.target.value;
    this._updateComponentColumns(cols => cols.map((c, i) => i === idx ? { ...c, label: value } : c));
  }

  handleColumnRemove(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    this._updateComponentColumns(cols => cols.filter((_, i) => i !== idx));
  }

  handleColumnMoveUp(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    if (idx === 0) return;
    this._updateComponentColumns(cols => {
      const arr = [...cols];
      [arr[idx - 1], arr[idx]] = [arr[idx], arr[idx - 1]];
      return arr;
    });
  }

  handleColumnMoveDown(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    this._updateComponentColumns(cols => {
      const arr = [...cols];
      if (idx >= arr.length - 1) return arr;
      [arr[idx], arr[idx + 1]] = [arr[idx + 1], arr[idx]];
      return arr;
    });
  }

  handleButtonConfigChange(event) {
    const field = event.target.dataset.field;
    const value = event.detail.value;
    const cfg = this._parseComponentConfig(this.editingComponent.configJson);
    this.editingComponent = {
      ...this.editingComponent,
      configJson: JSON.stringify({ ...cfg, [field]: value })
    };
  }

  handleComponentModalSave() {
    this.draftTemplate = {
      ...this.draftTemplate,
      components: this.draftTemplate.components.map(c =>
        c.localKey === this.editingComponentKey ? { ...this.editingComponent } : c
      )
    };
    this.isDirty = true;
    this.showComponentModal = false;
    this.editingComponent = {};
  }

  handleComponentModalClose() {
    this.showComponentModal = false;
    this.editingComponent = {};
  }

  handleDeleteComponent(event) {
    const key = event.detail.key;
    const comp = this.draftTemplate.components.find(c => c.localKey === key);
    const updated = this.draftTemplate.components.filter(c => c.localKey !== key);
    const deletedIds = comp?.id ? [...this.draftTemplate.deletedComponentIds, comp.id] : [...this.draftTemplate.deletedComponentIds];
    this.draftTemplate = { ...this.draftTemplate, components: updated, deletedComponentIds: deletedIds };
    this.isDirty = true;
  }

  // ── Recipients ───────────────────────────────────────────────────────────────

  handleAddRecipient() {
    const newR = {
      id: null, localKey: nextKey(), recipientType: 'To',
      recipientSourceType: 'Parent Field', active: true,
      defaultSelected: true, required: false, allowMultiple: true,
      displayOrder: this.draftTemplate.recipients.length + 1,
      emailFieldApiName: '', nameFieldApiName: '', filterLogic: ''
    };
    this.draftTemplate = { ...this.draftTemplate, recipients: [...this.draftTemplate.recipients, newR] };
    this.isDirty = true;
    // Open modal to edit immediately
    this.editingRecipient = { ...newR };
    this.editingRecipientKey = newR.localKey;
    this.showRecipientModal = true;
    this._ensureParentFields();
  }

  handleEditRecipient(event) {
    const key = event.currentTarget.dataset.key;
    const r = this.draftTemplate.recipients.find(x => x.localKey === key);
    if (r) {
      let editingR = { ...r };
      if (r.recipientSourceType === 'Related Records' && r._linkedQueryLocalKey) {
        const q = this.draftTemplate.queries.find(x => x.localKey === r._linkedQueryLocalKey);
        if (q) editingR._linkedQueryFields = this._parseFieldsFromSoql(q.soqlQuery || '');
      }
      this.editingRecipient = editingR;
      this.editingRecipientKey = key;
      this.showRecipientModal = true;
      this._ensureParentFields();
    }
  }

  _ensureParentFields() {
    if (this.parentFieldsForMergeTags.length === 0) this.loadParentFieldsForMergeTags();
  }

  handleRecipientFieldChange(event) {
    const field = event.target.dataset.field;
    const value = event.detail.value;
    this.editingRecipient = { ...this.editingRecipient, [field]: value };
    if (field === 'recipientSourceType' && value === 'Dynamic Segment') {
      this.loadSegmentsForObject();
    }
  }

  handleRecipientQuerySelect(event) {
    const localKey = event.detail.value;
    const q = this.draftTemplate.queries.find(x => x.localKey === localKey);
    const queryFields = this._parseFieldsFromSoql(q?.soqlQuery || '');
    this.editingRecipient = {
      ...this.editingRecipient,
      _linkedQueryLocalKey: localKey,
      _linkedQueryFields: queryFields,
      sourceObjectApiName: q?.soqlObject || '',
      parentLookupFieldApiName: q?.parentLookupField || '',
      emailFieldApiName: '',
      nameFieldApiName: ''
    };
  }

  handleRecipientSegmentChange(event) {
    const segmentId = event.detail.value;
    const seg = (this.availableSegments || []).find(s => s.Id === segmentId);
    this.editingRecipient = {
      ...this.editingRecipient,
      segmentId: segmentId || null,
      segmentName: seg ? seg.Name : null
    };
  }

  handleRecipientCheckboxChange(event) {
    const field = event.target.dataset.field;
    this.editingRecipient = { ...this.editingRecipient, [field]: event.target.checked };
  }

  handleRecipientModalSave() {
    const updated = this.draftTemplate.recipients.map(r =>
      r.localKey === this.editingRecipientKey ? { ...this.editingRecipient } : r
    );
    this.draftTemplate = { ...this.draftTemplate, recipients: updated };
    this.isDirty = true;
    this.showRecipientModal = false;
    this.editingRecipient = {};
  }

  handleRecipientModalClose() {
    this.showRecipientModal = false;
    this.editingRecipient = {};
  }

  handleDeleteRecipient(event) {
    const key = event.currentTarget.dataset.key;
    const r = this.draftTemplate.recipients.find(x => x.localKey === key);
    const updated = this.draftTemplate.recipients.filter(x => x.localKey !== key);
    const deletedIds = r?.id ? [...this.draftTemplate.deletedRecipientIds, r.id] : [...this.draftTemplate.deletedRecipientIds];
    this.draftTemplate = { ...this.draftTemplate, recipients: updated, deletedRecipientIds: deletedIds };
    this.isDirty = true;
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  handleActionTypeSelect(event) { this.newActionType = event.detail.value; }

  handleAddAction() {
    const newA = {
      id: null, localKey: nextKey(), active: true,
      actionType: this.newActionType,
      runOrder: this.draftTemplate.actions.length + 1,
      isUpdateField: this.newActionType === 'Update Field',
      isCreateTask: this.newActionType === 'Create Task',
      valueType: 'Static', assignedToType: 'Current User',
      dueDateStrategy: 'Same Day', taskStatus: 'Completed', taskPriority: 'Normal',
      fieldApiName: '', value: '', taskSubject: '', taskDescription: '', daysAfterSend: 1
    };
    this.draftTemplate = { ...this.draftTemplate, actions: [...this.draftTemplate.actions, newA] };
    this.isDirty = true;
    this.editingAction = { ...newA };
    this.editingActionKey = newA.localKey;
    this.showActionModal = true;
    this._loadUpdateableFields();
    this._ensureParentFields();
  }

  handleEditAction(event) {
    const key = event.currentTarget.dataset.key;
    const a = this.draftTemplate.actions.find(x => x.localKey === key);
    if (a) {
      this.editingAction = { ...a };
      this.editingActionKey = key;
      this.showActionModal = true;
      this._loadUpdateableFields();
      this._ensureParentFields();
    }
  }

  handleActionMergeTagFocus(event) {
    this._actionFocusedField = event.target.dataset.field;
  }

  handleInsertActionMergeTag(event) {
    event.stopPropagation();
    const tag = event.currentTarget.dataset.tag;
    const defaultField = this.editingActionIsCreateTask ? 'taskSubject' : 'value';
    const field = this._actionFocusedField || defaultField;
    const isTextarea = field === 'taskDescription';
    const sel = isTextarea
      ? `lightning-textarea[data-field="${field}"]`
      : `lightning-input[data-field="${field}"]`;
    const lwcEl = this.template.querySelector(sel);
    const nativeEl = lwcEl?.querySelector(isTextarea ? 'textarea' : 'input');
    if (nativeEl) {
      const start = nativeEl.selectionStart ?? nativeEl.value.length;
      const end = nativeEl.selectionEnd ?? nativeEl.value.length;
      const val = nativeEl.value || '';
      const newVal = val.slice(0, start) + tag + val.slice(end);
      this.editingAction = { ...this.editingAction, [field]: newVal };
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => {
        nativeEl.focus();
        nativeEl.setSelectionRange(start + tag.length, start + tag.length);
      }, 0);
      return;
    }
    this.editingAction = { ...this.editingAction, [field]: (this.editingAction[field] || '') + tag };
  }

  handleCopyActionMergeTag(event) {
    event.stopPropagation();
    navigator.clipboard?.writeText(event.currentTarget.dataset.tag);
  }

  _loadUpdateableFields() {
    const obj = this.draftTemplate.parentObjectApiName;
    if (!obj || this.updateableFields.length > 0) return;
    getUpdateableFieldsForObject({ objectApiName: obj })
      .then(fields => { this.updateableFields = fields || []; })
      .catch(() => { this.updateableFields = []; });
  }

  handleActionFieldChange(event) {
    const field = event.target.dataset.field;
    this.editingAction = { ...this.editingAction, [field]: event.detail.value };
  }

  handleActionNumberChange(event) {
    const field = event.target.dataset.field;
    this.editingAction = { ...this.editingAction, [field]: Number(event.detail.value) };
  }

  handleActionCheckboxChange(event) {
    const field = event.target.dataset.field;
    this.editingAction = { ...this.editingAction, [field]: event.target.checked };
  }

  handleActionModalSave() {
    const updated = this.draftTemplate.actions.map(a =>
      a.localKey === this.editingActionKey ? {
        ...this.editingAction,
        isUpdateField: this.editingAction.actionType === 'Update Field',
        isCreateTask: this.editingAction.actionType === 'Create Task'
      } : a
    );
    this.draftTemplate = { ...this.draftTemplate, actions: updated };
    this.isDirty = true;
    this.showActionModal = false;
    this.editingAction = {};
  }

  handleActionModalClose() {
    this.showActionModal = false;
    this.editingAction = {};
  }

  handleDeleteAction(event) {
    const key = event.currentTarget.dataset.key;
    const a = this.draftTemplate.actions.find(x => x.localKey === key);
    const updated = this.draftTemplate.actions.filter(x => x.localKey !== key);
    const deletedIds = a?.id ? [...this.draftTemplate.deletedActionIds, a.id] : [...this.draftTemplate.deletedActionIds];
    this.draftTemplate = { ...this.draftTemplate, actions: updated, deletedActionIds: deletedIds };
    this.isDirty = true;
  }

  handleActionActiveToggle(event) {
    const key = event.currentTarget.dataset.key;
    this.draftTemplate = {
      ...this.draftTemplate,
      actions: this.draftTemplate.actions.map(a =>
        a.localKey === key ? { ...a, active: event.target.checked } : a
      )
    };
    this.isDirty = true;
  }

  // ── Preview ──────────────────────────────────────────────────────────────────

  handlePreviewRecordChange(event) {
    const detail = event.detail || {};
    this.previewRecordId = detail.value || detail.recordId || (typeof detail === 'string' ? detail : '');
  }

  handlePreview() {
    if (!this.previewRecordId || !this.draftTemplate.id) {
      this.errorMessage = 'Save the template and select a record to preview.';
      return;
    }
    this.errorMessage = '';
    this.previewIsLoading = true;
    this.previewSubject = '';
    this.previewHtml = '';
    previewTemplate({ templateId: this.draftTemplate.id, recordId: this.previewRecordId })
      .then(result => {
        this.previewSubject = result.subject;
        this.previewHtml = result.htmlBody;
      })
      .catch(err => {
        this.errorMessage = err.body?.message || 'Preview failed.';
      })
      .finally(() => { this.previewIsLoading = false; });
  }

  handlePreviewPdf() {
    if (!this.previewRecordId || !this.draftTemplate.id) {
      this.errorMessage = 'Select a record to preview the PDF.';
      return;
    }
    this.isPreviewingPdf = true;
    this.errorMessage = '';
    previewTemplatePdf({ templateId: this.draftTemplate.id, recordId: this.previewRecordId })
      .then(docId => {
        const url = '/sfc/servlet.shepherd/document/download/' + docId;
        window.open(url, '_blank');
      })
      .catch(err => { this.errorMessage = err.body?.message || 'PDF preview failed.'; })
      .finally(() => { this.isPreviewingPdf = false; });
  }

  handleSendTestEmail() {
    if (!this.previewRecordId || !this.draftTemplate.id) {
      this.errorMessage = 'Save the template and select a record before sending a test email.';
      return;
    }
    this.isSendingTest = true;
    this.errorMessage = '';
    sendTestEmail({ templateId: this.draftTemplate.id, recordId: this.previewRecordId })
      .then(() => {
        this.dispatchEvent(new ShowToastEvent({ title: 'Test email sent', message: 'Check your inbox.', variant: 'success' }));
      })
      .catch(err => { this.errorMessage = err.body?.message || 'Test email failed.'; })
      .finally(() => { this.isSendingTest = false; });
  }

  handleScheduleDateTimeChange(event) {
    this.scheduleDateTime = event.target.value;
  }

  handleScheduleDateChange(event) {
    this.scheduleDate = event.detail.value;
  }

  handleScheduleTimeChange(event) {
    this.scheduleTime = event.detail.value;
  }

  handleScheduleModeChange(event) {
    this.scheduleMode = event.detail.value;
  }

  handleScheduleModeToggle(event) {
    this.scheduleMode = event.currentTarget.dataset.value;
  }

  handleBulkFilterChange(event) {
    this.scheduleBulkFilter = event.target.value;
  }

  handleScheduleOutputTypeChange(event) {
    this.scheduleOutputType = event.detail.value;
  }

  handleRecurringDaysChange(event) {
    this.recurringDays = event.detail.value;
  }

  handleRecurringTimeChange(event) {
    this.recurringTime = event.detail.value;
  }

  handleRecurringStartDateChange(event) {
    this.recurringStartDate = event.detail.value;
  }

  handleRecurringEndTypeChange(event) {
    this.recurringEndType = event.detail.value;
  }

  handleRecurringEndDateChange(event) {
    this.recurringEndDate = event.detail.value;
  }

  handleRecurringMaxSendsChange(event) {
    this.recurringMaxSends = event.detail.value;
  }

  handleCreateScheduledSend() {
    if (!this.draftTemplate.id) {
      this.errorMessage = 'Save the template before scheduling.';
      return;
    }
    if (!this.scheduleDate || !this.scheduleTime) {
      this.errorMessage = 'Select a date and time before scheduling.';
      return;
    }
    const scheduledDateTimeStr = this.scheduleDate + 'T' + this.scheduleTime;
    this.isScheduling = true;
    this.errorMessage = '';
    createScheduledSend({
      templateId: this.draftTemplate.id,
      scheduledDateTime: scheduledDateTimeStr,
      sendType: 'Bulk',
      recordId: null,
      filterClause: this.scheduleBulkFilter || null,
      outputType: this.scheduleOutputType
    })
      .then(() => {
        this.dispatchEvent(new ShowToastEvent({ title: 'Send scheduled', message: 'Scheduled for ' + scheduledDateTimeStr, variant: 'success' }));
        this.scheduleDate = '';
        this.scheduleBulkFilter = '';
        this.scheduleOutputType = 'Email';
        this.loadScheduledSends();
      })
      .catch(err => { this.errorMessage = err.body?.message || 'Scheduling failed.'; })
      .finally(() => { this.isScheduling = false; });
  }

  handleCreateRecurringSchedule() {
    if (!this.draftTemplate.id) {
      this.errorMessage = 'Save the template before scheduling.';
      return;
    }
    if (!this.recurringDays || this.recurringDays.length === 0) {
      this.errorMessage = 'Select at least one day of the week.';
      return;
    }
    if (!this.recurringStartDate) {
      this.errorMessage = 'Select a start date.';
      return;
    }
    const recurringConfigJson = JSON.stringify({
      daysOfWeek: this.recurringDays,
      timeOfDay: this.recurringTime,
      startDate: this.recurringStartDate,
      endType: this.recurringEndType,
      endDate: this.recurringEndType === 'endDate' ? this.recurringEndDate : null,
      maxSends: this.recurringEndType === 'maxSends' ? Number(this.recurringMaxSends) : null,
      filterClause: this.scheduleBulkFilter || null
    });
    const request = {
      templateId: this.draftTemplate.id,
      recordId: null,
      subject: this.draftTemplate.subjectTemplate || this.draftTemplate.name || 'Email',
      htmlBody: null,
      toRecipients: [],
      ccRecipients: [],
      bccRecipients: [],
      attachmentContentDocumentIds: [],
      storeHistory: null
    };
    this.isScheduling = true;
    this.errorMessage = '';
    scheduleRecurringEmail({ request, recurringConfigJson })
      .then(() => {
        this.dispatchEvent(new ShowToastEvent({ title: 'Recurring schedule created', message: 'First send will occur on ' + this.recurringStartDate, variant: 'success' }));
        this.recurringDays = [];
        this.recurringStartDate = '';
        this.recurringEndDate = '';
        this.recurringMaxSends = '';
        this.recurringEndType = 'noEnd';
        this.loadScheduledSends();
      })
      .catch(err => { this.errorMessage = err.body?.message || 'Failed to create recurring schedule.'; })
      .finally(() => { this.isScheduling = false; });
  }

  loadScheduledSends() {
    if (!this.draftTemplate.id) return;
    this.isLoadingSchedules = true;
    getScheduledSends({ templateId: this.draftTemplate.id })
      .then(rows => {
        this.scheduledSends = (rows || []).map(r => ({
          ...r,
          isPending: r.status === 'Pending',
          statusClass: 'sched-status sched-status_' + (r.status || 'pending').toLowerCase()
        }));
      })
      .catch(() => { this.scheduledSends = []; })
      .finally(() => { this.isLoadingSchedules = false; });
  }

  handleCancelScheduledSend(event) {
    const sendId = event.currentTarget.dataset.id;
    cancelScheduledSend({ scheduledSendId: sendId })
      .then(() => {
        this.dispatchEvent(new ShowToastEvent({ title: 'Cancelled', message: 'Scheduled send cancelled.', variant: 'success' }));
        this.loadScheduledSends();
      })
      .catch(err => { this.errorMessage = err.body?.message || 'Cancel failed.'; });
  }

  handleSendScheduledSendNow(event) {
    const sendId = event.currentTarget.dataset.id;
    sendScheduledSendNow({ scheduledSendId: sendId })
      .then(() => {
        this.dispatchEvent(new ShowToastEvent({ title: 'Sent', message: 'Send executed successfully.', variant: 'success' }));
        this.loadScheduledSends();
      })
      .catch(err => { this.errorMessage = err.body?.message || 'Send failed.'; });
  }

  // ── Files / Attachments ──────────────────────────────────────────────────────

  loadTemplateFiles() {
    if (!this.draftTemplate.id) return;
    this.isLoadingFiles = true;
    Promise.all([
      getTemplateFiles({ templateId: this.draftTemplate.id, fileType: 'image' }),
      getTemplateFiles({ templateId: this.draftTemplate.id, fileType: 'attachment' })
    ])
    .then(([images, attachments]) => {
      this.templateImages = images || [];
      this.templateAttachments = attachments || [];
    })
    .catch(() => {})
    .finally(() => { this.isLoadingFiles = false; });
  }

  handleImageUploadFinished() { this.loadTemplateFiles(); }
  handleAttachmentUploadFinished() { this.loadTemplateFiles(); }

  handleGetPublicUrl(event) {
    const contentVersionId = event.currentTarget.dataset.cvid;
    createPublicImageLink({ contentVersionId })
      .then(url => {
        navigator.clipboard?.writeText(url);
        this.dispatchEvent(new ShowToastEvent({ title: 'Copied!', message: 'Public image URL copied to clipboard.', variant: 'success' }));
      })
      .catch(err => { this.errorMessage = this.extractError(err); });
  }

  handleDeleteFile(event) {
    const contentDocumentId = event.currentTarget.dataset.cdid;
    if (!confirm('Delete this file? This cannot be undone.')) return;
    deleteTemplateFile({ contentDocumentId })
      .then(() => { this.loadTemplateFiles(); })
      .catch(err => { this.errorMessage = this.extractError(err); });
  }

  // ── Attachment Rules ─────────────────────────────────────────────────────────

  handleAddAttachmentRule() {
    const newRule = {
      id: null,
      localKey: nextKey(),
      active: true,
      displayOrder: (this.draftTemplate.attachments || []).length + 1,
      attachmentSource: 'Static File',
      staticContentDocumentId: '',
      linkedQueryId: null,
      linkedQueryName: '',
      _linkedQueryLocalKey: null,
      fileTitleFilter: '',
      maxAttachments: 5
    };
    this.draftTemplate = { ...this.draftTemplate, attachments: [...(this.draftTemplate.attachments || []), newRule] };
    this.selectedAttachmentRuleKey = newRule.localKey;
    this.isDirty = true;
  }

  handleSelectAttachmentRule(event) {
    const key = event.currentTarget.dataset.key;
    this.selectedAttachmentRuleKey = this.selectedAttachmentRuleKey === key ? null : key;
  }

  handleDeleteAttachmentRule(event) {
    event.stopPropagation();
    const key = event.currentTarget.dataset.key;
    const rule = (this.draftTemplate.attachments || []).find(ac => ac.localKey === key);
    const updated = (this.draftTemplate.attachments || []).filter(ac => ac.localKey !== key);
    const deletedIds = rule?.id ? [...(this.draftTemplate.deletedAttachmentIds || []), rule.id] : [...(this.draftTemplate.deletedAttachmentIds || [])];
    if (this.selectedAttachmentRuleKey === key) this.selectedAttachmentRuleKey = null;
    this.draftTemplate = { ...this.draftTemplate, attachments: updated, deletedAttachmentIds: deletedIds };
    this.isDirty = true;
  }

  handleAttachmentRuleChange(event) {
    const key = event.currentTarget.dataset.key;
    const field = event.currentTarget.dataset.field;
    const value = event.detail.value;
    this.draftTemplate = {
      ...this.draftTemplate,
      attachments: (this.draftTemplate.attachments || []).map(ac =>
        ac.localKey === key ? { ...ac, [field]: value } : ac
      )
    };
    this.isDirty = true;
  }

  handleAttachmentRuleNumberChange(event) {
    const key = event.currentTarget.dataset.key;
    const field = event.currentTarget.dataset.field;
    const value = Number(event.detail.value);
    this.draftTemplate = {
      ...this.draftTemplate,
      attachments: (this.draftTemplate.attachments || []).map(ac =>
        ac.localKey === key ? { ...ac, [field]: value } : ac
      )
    };
    this.isDirty = true;
  }

  handleAttachmentRuleChecked(event) {
    const key = event.currentTarget.dataset.key;
    const field = event.currentTarget.dataset.field;
    this.draftTemplate = {
      ...this.draftTemplate,
      attachments: (this.draftTemplate.attachments || []).map(ac =>
        ac.localKey === key ? { ...ac, [field]: event.target.checked } : ac
      )
    };
    this.isDirty = true;
  }

  handleAttachmentRuleLinkedQueryChange(event) {
    const key = event.currentTarget.dataset.key;
    const selectedKey = event.detail.value;
    const q = (this.draftTemplate.queries || []).find(x => x.localKey === selectedKey);
    this.draftTemplate = {
      ...this.draftTemplate,
      attachments: (this.draftTemplate.attachments || []).map(ac =>
        ac.localKey === key ? { ...ac, linkedQueryId: q?.id || null, linkedQueryName: q?.name || '', _linkedQueryLocalKey: selectedKey } : ac
      )
    };
    this.isDirty = true;
  }

  clearError() { this.errorMessage = null; }

  extractError(err) {
    return err?.body?.message || err?.message || 'An unexpected error occurred.';
  }

  // ── Brand handlers ─────────────────────────────────────────────────────────

  handleSidebarNav(event) {
    const view = event.currentTarget.dataset.view;
    this.sidebarView = view;
    this.isEditing = false;
    this.isBrandEditing = false;
    this.errorMessage = null;
    if (view === 'brands') this._refreshBrands();
    if (view === 'scheduler') this.loadSchedulerStatus();
  }

  _refreshBrands() {
    getBrands()
      .then(brands => {
        this.brands = (brands || []).map(b => ({
          ...b,
          primaryColorStyle: 'background-color:' + (b.primaryColor || '#ccc'),
          secondaryColorStyle: 'background-color:' + (b.secondaryColor || '#ccc'),
          lastModifiedDisplay: b.lastModifiedDate ? new Date(b.lastModifiedDate).toLocaleString() : '',
          statusPillClass: 'status-pill ' + ((b.status || '').toLowerCase() === 'active' ? 'status-pill_active' : 'status-pill_draft')
        }));
      })
      .catch(() => {});
  }

  handleNewBrand() {
    this.draftBrand = emptyBrand();
    this.brandHeaderEditorMode = 'Visual';
    this.brandFooterEditorMode = 'Visual';
    this.brandImages = [];
    this.brandActiveTab = 'identity';
    this.isBrandEditing = true;
  }

  handleEditBrand(event) {
    const brandId = event.currentTarget.dataset.id;
    this.isBrandLoading = true;
    this.isBrandEditing = true;
    loadBrand({ brandId })
      .then(brand => {
        this.draftBrand = { ...emptyBrand(), ...brand };
        this.brandHeaderEditorMode = brand.headerEditorMode || 'Visual';
        this.brandFooterEditorMode = brand.footerEditorMode || 'Visual';
        return getBrandFiles({ brandId });
      })
      .then(files => { this.brandImages = this._mapBrandFiles(files); })
      .catch(err => { this.showToast('Error', this.extractError(err), 'error'); this.isBrandEditing = false; })
      .finally(() => { this.isBrandLoading = false; });
  }

  handleBackToBrandLibrary() {
    this.isBrandEditing = false;
    this.draftBrand = emptyBrand();
    this._refreshBrands();
  }

  handleBrandFieldChange(event) {
    const field = event.currentTarget.dataset.field;
    const value = event.detail ? event.detail.value : event.target.value;
    this.draftBrand = { ...this.draftBrand, [field]: value };
  }

  handleBrandHeaderModeToggle() {
    this.brandHeaderEditorMode = this.brandHeaderEditorMode === 'Visual' ? 'HTML Source' : 'Visual';
    this.draftBrand = { ...this.draftBrand, headerEditorMode: this.brandHeaderEditorMode };
  }

  handleBrandFooterModeToggle() {
    this.brandFooterEditorMode = this.brandFooterEditorMode === 'Visual' ? 'HTML Source' : 'Visual';
    this.draftBrand = { ...this.draftBrand, footerEditorMode: this.brandFooterEditorMode };
  }

  handleBrandHeaderRichChange(event) {
    this.draftBrand = { ...this.draftBrand, headerHtml: event.detail.value };
  }

  handleBrandFooterRichChange(event) {
    this.draftBrand = { ...this.draftBrand, footerHtml: event.detail.value };
  }

  handleSaveBrand() {
    if (!this.draftBrand.name) { this.showToast('Error', 'Brand name is required.', 'error'); return; }
    this.isBrandLoading = true;
    saveBrand({ brandJson: JSON.stringify(this.draftBrand) })
      .then(saved => {
        this.draftBrand = { ...emptyBrand(), ...saved };
        this.brandHeaderEditorMode = saved.headerEditorMode || 'Visual';
        this.brandFooterEditorMode = saved.footerEditorMode || 'Visual';
        this._refreshBrands();
        this.showToast('Success', 'Brand saved.', 'success');
        return getBrandFiles({ brandId: saved.id });
      })
      .then(files => { this.brandImages = this._mapBrandFiles(files); })
      .catch(err => { this.showToast('Error', this.extractError(err), 'error'); })
      .finally(() => { this.isBrandLoading = false; });
  }

  handleDeleteBrand(event) {
    const brandId = event.currentTarget.dataset.id;
    deleteBrand({ brandId })
      .then(() => { this._refreshBrands(); this.showToast('Success', 'Brand deleted.', 'success'); })
      .catch(err => { this.showToast('Error', this.extractError(err), 'error'); });
  }

  _mapBrandFiles(files) {
    return (files || []).map(f => {
      if (!f.publicUrl) return f;
      const w = f.imgWidth || '600';
      const imgTag = `<img src="${f.publicUrl}" alt="${f.title}" width="${w}" style="max-width:100%;display:block;" />`;
      return { ...f, imgWidth: w, imgTag };
    });
  }

  // ── Brand AI Prompt Builder ──────────────────────────────────────────────────

  handleOpenBrandAiModal() {
    this.brandAiStep = 1;
    this.brandAiHeaderDesc = '';
    this.brandAiFooterDesc = '';
    this.brandPromptCopied = false;
    this.brandSfRulesExpanded = false;
    this.brandAiImages = (this.brandImages || [])
      .filter(img => img.publicUrl)
      .map(img => ({ ...img, width: 600, height: '', include: true }));
    this.showBrandAiModal = true;
  }

  handleCloseBrandAiModal() { this.showBrandAiModal = false; }
  handleBrandAiModalBackdropClick() { this.showBrandAiModal = false; }
  handleBrandAiModalInnerClick(event) { event.stopPropagation(); }

  handleBrandAiNext() {
    if (this.brandAiStep < 2) this.brandAiStep += 1;
  }
  handleBrandAiBack() {
    if (this.brandAiStep > 1) this.brandAiStep -= 1;
  }

  handleBrandAiHeaderDescChange(event) { this.brandAiHeaderDesc = event.detail.value; }
  handleBrandAiFooterDescChange(event) { this.brandAiFooterDesc = event.detail.value; }

  handleBrandAiImageWidthChange(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    const val = parseInt(event.target.value, 10) || 600;
    this.brandAiImages = this.brandAiImages.map((img, i) => i === idx ? { ...img, width: val } : img);
  }

  handleBrandAiImageHeightChange(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    const raw = event.target.value.trim();
    const val = raw === '' ? '' : (parseInt(raw, 10) || '');
    this.brandAiImages = this.brandAiImages.map((img, i) => i === idx ? { ...img, height: val } : img);
  }

  handleBrandAiImageToggle(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    const checked = event.target.checked;
    this.brandAiImages = this.brandAiImages.map((img, i) => i === idx ? { ...img, include: checked } : img);
  }

  handleCopyBrandPrompt() {
    const text = this.brandAiPrompt;
    navigator.clipboard.writeText(text).then(() => {
      this.brandPromptCopied = true;
      if (this._brandCopyTimer) clearTimeout(this._brandCopyTimer);
      this._brandCopyTimer = setTimeout(() => { this.brandPromptCopied = false; }, 2000);
    }).catch(() => {});
  }

  handleCopyBrandImageTag(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    const img = this.brandAiImages[idx];
    if (!img || !img.publicUrl) return;
    const hAttr = img.height ? ` height="${img.height}"` : '';
    const tag = `<img src="${img.publicUrl}" width="${img.width || 600}"${hAttr} alt="${img.title}" style="max-width:100%;display:block;">`;
    navigator.clipboard.writeText(tag).catch(() => {});
  }

  handleToggleBrandSfRules() { this.brandSfRulesExpanded = !this.brandSfRulesExpanded; }

  handleBrandTabClick(event) { this.brandActiveTab = event.currentTarget.dataset.tab; }
  handleBrandColorPickerChange(event) {
    const field = event.currentTarget.dataset.field;
    this.draftBrand = { ...this.draftBrand, [field]: event.target.value };
  }
  handleBrandFilterChange(event) { this.brandFilter = event.currentTarget.dataset.filter; }
  handleBrandSearch(event) { this.brandSearchTerm = event.detail.value; }

  handleSignerTagCopy(event) {
    const tag = event.currentTarget.dataset.tag;
    if (!tag) return;
    navigator.clipboard.writeText(tag).then(() => {
      this.copiedSignerTag = tag;
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => { this.copiedSignerTag = null; }, 1800);
    }).catch(() => {
      this.showToast('Copy failed', 'Could not copy to clipboard.', 'error');
    });
  }

  handleBrandTagCopy(event) {
    const tag = event.currentTarget.dataset.tag;
    if (!tag) return;

    // For <img> tags on the header/footer tab in Visual mode, insert directly into the editor
    if (tag.startsWith('<img') && (this.brandActiveTab === 'header' || this.brandActiveTab === 'footer')) {
      const isHeader = this.brandActiveTab === 'header';
      const editorMode = isHeader
        ? (this.draftBrand.headerEditorMode || 'Visual')
        : (this.draftBrand.footerEditorMode || 'Visual');
      if (editorMode === 'Visual') {
        if (isHeader) {
          this.draftBrand = { ...this.draftBrand, headerHtml: (this.draftBrand.headerHtml || '') + tag };
          this.headerRteKey += 1;
        } else {
          this.draftBrand = { ...this.draftBrand, footerHtml: (this.draftBrand.footerHtml || '') + tag };
          this.footerRteKey += 1;
        }
        this.insertedTag = tag;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.insertedTag = null; }, 1800);
        return;
      }
    }

    navigator.clipboard.writeText(tag).then(() => {
      this.copiedTag = tag;
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => { this.copiedTag = null; }, 1800);
    }).catch(() => {
      this.showToast('Copy failed', 'Could not copy to clipboard.', 'error');
    });
  }

  handleBrandImageWidthChange(event) {
    const contentDocumentId = event.currentTarget.dataset.docId;
    const w = event.target.value || '600';
    this.brandImages = this.brandImages.map(img => {
      if (img.contentDocumentId !== contentDocumentId || !img.publicUrl) return img;
      const imgTag = `<img src="${img.publicUrl}" alt="${img.title}" width="${w}" style="max-width:100%;display:block;" />`;
      return { ...img, imgWidth: w, imgTag };
    });
  }

  handleCreateBrandPublicImageLink(event) {
    const contentVersionId = event.currentTarget.dataset.versionId;
    const brandId = this.draftBrand.id;
    if (!brandId || !contentVersionId) return;
    createBrandPublicImageLink({ brandId, contentVersionId })
      .then(url => {
        this.brandImages = this.brandImages.map(img => {
          if (img.contentVersionId !== contentVersionId) return img;
          const w = img.imgWidth || '600';
          const imgTag = `<img src="${url}" alt="${img.title}" width="${w}" style="max-width:100%;display:block;" />`;
          return { ...img, publicUrl: url, imgWidth: w, imgTag };
        });
        if (!this.draftBrand.logoUrl && !this.draftBrand.logoContentDocumentId) {
          const img = this.brandImages.find(i => i.contentVersionId === contentVersionId);
          if (img) {
            this.draftBrand = { ...this.draftBrand, logoUrl: url, logoContentDocumentId: img.contentDocumentId };
          }
        }
        this.showToast('Success', 'Public image link created.', 'success');
      })
      .catch(err => { this.showToast('Error', this.extractError(err), 'error'); });
  }

  handleDeleteBrandFile(event) {
    const contentDocumentId = event.currentTarget.dataset.docId;
    deleteBrandFile({ contentDocumentId })
      .then(() => {
        this.brandImages = this.brandImages.filter(img => img.contentDocumentId !== contentDocumentId);
        this.showToast('Success', 'File deleted.', 'success');
      })
      .catch(err => { this.showToast('Error', this.extractError(err), 'error'); });
  }

  handleTemplateBrandChange(event) {
    const brandId = event.detail.value || null;
    const brand = brandId ? (this.brands || []).find(b => b.id === brandId) : null;
    this.draftTemplate = {
      ...this.draftTemplate,
      brandId: brandId,
      brandName: brand ? (brand.displayName || brand.name) : null
    };
    this.isDirty = true;
    // Load full brand details so the AI prompt builder can use them
    if (brandId) {
      loadBrand({ brandId })
        .then(b => { this.draftBrand = { ...emptyBrand(), ...b }; })
        .catch(() => {
          // Fall back to summary fields already in the brands list
          if (brand) {
            this.draftBrand = { ...emptyBrand(), id: brand.id, displayName: brand.displayName || brand.name,
              primaryColor: brand.primaryColor || '', secondaryColor: brand.secondaryColor || '',
              logoUrl: brand.logoUrl || '' };
          }
        });
    } else {
      this.draftBrand = emptyBrand();
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  // ── Scheduler ────────────────────────────────────────────────────────────────

  loadSchedulerStatus() {
    this.isLoadingScheduler = true;
    getSchedulerStatus()
      .then(status => {
        this.schedulerStatus = status;
        if (status && status.frequency) {
          this.selectedFrequency = status.frequency;
        }
      })
      .catch(err => { this.errorMessage = this.extractError(err); })
      .finally(() => { this.isLoadingScheduler = false; });
  }

  handleSchedulerFrequencyChange(event) {
    this.selectedFrequency = event.detail.value;
  }

  handleActivateScheduler() {
    this.isTogglingScheduler = true;
    this.errorMessage = null;
    activateScheduler({ frequency: this.selectedFrequency })
      .then(status => {
        this.schedulerStatus = status;
        this.dispatchEvent(new ShowToastEvent({ title: 'Scheduler activated', message: 'The automated send job is now running.', variant: 'success' }));
      })
      .catch(err => { this.errorMessage = this.extractError(err); })
      .finally(() => { this.isTogglingScheduler = false; });
  }

  handleDeactivateScheduler() {
    this.isTogglingScheduler = true;
    this.errorMessage = null;
    deactivateScheduler()
      .then(() => {
        this.schedulerStatus = { isActive: false, jobId: null, cronExpression: null, nextFireTime: null, frequency: null };
        this.dispatchEvent(new ShowToastEvent({ title: 'Scheduler deactivated', message: 'The automated send job has been stopped.', variant: 'success' }));
      })
      .catch(err => { this.errorMessage = this.extractError(err); })
      .finally(() => { this.isTogglingScheduler = false; });
  }
}
