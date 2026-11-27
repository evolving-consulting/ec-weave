import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getConfig from '@salesforce/apex/WeaveSignatureConfigService.getConfig';
import saveConfig from '@salesforce/apex/WeaveSignatureConfigService.saveConfig';
import getSetupStatus from '@salesforce/apex/WeaveSignatureConfigService.getSetupStatus';
import getEmailTemplates from '@salesforce/apex/WeaveSignatureEmailTemplateService.getEmailTemplates';
import saveEmailTemplate from '@salesforce/apex/WeaveSignatureEmailTemplateService.saveEmailTemplate';
import resetToDefault from '@salesforce/apex/WeaveSignatureEmailTemplateService.resetToDefault';
import getBrands from '@salesforce/apex/WeaveTemplateBuilderController.getBrands';
import getOrgWideEmails from '@salesforce/apex/WeaveSignatureConfigService.getOrgWideEmailAddresses';

const MERGE_TOKENS = [
  '{SignerName}', '{SenderName}', '{CompanyName}', '{DocumentTitle}',
  '{RoleName}', '{Message}', '{ActionButton}', '{DocumentInfo}',
  '{SecurityNote}', '{SignatureUrl}', '{ExpirationHours}', '{LogoUrl}',
  '{VerificationCode}'
];

const RICH_TEXT_FORMATS = [
  'font', 'size', 'bold', 'italic', 'underline', 'strike',
  'list', 'indent', 'align', 'link', 'image', 'clean', 'table'
];

export default class WeaveSignatureSettings extends LightningElement {
  @track config = {};
  @track setupStatus = { checks: [], allPassed: false };
  @track activeTab = 'status';
  @track errorMessage = '';

  @track brands = [];
  @track selectedBrandId = null;
  @track emailTemplates = [];
  @track activeEmailType = 'Signature Request';
  @track activeTemplate = null;
  @track previewHtml = '';

  @track orgWideEmailOptions = [];

  @track isLoadingStatus  = false;
  @track isSavingSettings = false;
  @track isLoadingTemplate = false;
  @track isSavingTemplate  = false;
  @track isLoadingPreview  = false;

  get mergeTokens() { return MERGE_TOKENS; }
  get richTextFormats() { return RICH_TEXT_FORMATS; }

  get isStatusTab()   { return this.activeTab === 'status'; }
  get isSiteTab()     { return this.activeTab === 'site'; }
  get isLinksTab()    { return this.activeTab === 'links'; }
  get isRemindersTab(){ return this.activeTab === 'reminders'; }
  get isVerifyTab()   { return this.activeTab === 'verify'; }

  get accordionClassStatus()    { return 'accordion-btn' + (this.activeTab === 'status'    ? ' accordion-btn_open' : ''); }
  get accordionClassSite()      { return 'accordion-btn' + (this.activeTab === 'site'      ? ' accordion-btn_open' : ''); }
  get accordionClassLinks()     { return 'accordion-btn' + (this.activeTab === 'links'     ? ' accordion-btn_open' : ''); }
  get accordionClassReminders() { return 'accordion-btn' + (this.activeTab === 'reminders' ? ' accordion-btn_open' : ''); }
  get accordionClassVerify()    { return 'accordion-btn' + (this.activeTab === 'verify'    ? ' accordion-btn_open' : ''); }

  get accordionChevronStatus()    { return this.activeTab === 'status'    ? '▼' : '▶'; }
  get accordionChevronSite()      { return this.activeTab === 'site'      ? '▼' : '▶'; }
  get accordionChevronLinks()     { return this.activeTab === 'links'     ? '▼' : '▶'; }
  get accordionChevronReminders() { return this.activeTab === 'reminders' ? '▼' : '▶'; }
  get accordionChevronVerify()    { return this.activeTab === 'verify'    ? '▼' : '▶'; }

  get emailTypeClassRequest()      { return 'email-type-btn' + (this.activeEmailType === 'Signature Request' ? ' email-type-btn_active' : ''); }
  get emailTypeClassReminder()     { return 'email-type-btn' + (this.activeEmailType === 'Reminder'          ? ' email-type-btn_active' : ''); }
  get emailTypeClassVerification() { return 'email-type-btn' + (this.activeEmailType === 'Verification'      ? ' email-type-btn_active' : ''); }
  get emailTypeClassCompletion()   { return 'email-type-btn' + (this.activeEmailType === 'Completion'        ? ' email-type-btn_active' : ''); }

  get saveSettingsLabel()  { return this.isSavingSettings  ? 'Saving…' : 'Save Settings'; }
  get saveTemplateLabel()  { return this.isSavingTemplate  ? 'Saving…' : 'Save'; }

  get brandOptions() {
    const opts = [{ label: '— Default (all brands) —', value: null }];
    return opts.concat((this.brands || []).map(b => ({ label: b.displayName || b.name, value: b.id })));
  }

  connectedCallback() {
    this.loadAll();
  }

  loadAll() {
    this.isLoadingStatus = true;
    Promise.all([
      getConfig(),
      getSetupStatus(),
      getBrands(),
      getOrgWideEmails ? getOrgWideEmails() : Promise.resolve([])
    ])
      .then(([cfg, status, brands, owes]) => {
        this.config = cfg || {};
        const rawStatus = status || { checks: [], allPassed: false };
        this.setupStatus = {
          ...rawStatus,
          checks: (rawStatus.checks || []).map(c => ({
            ...c,
            rowClass:  'check-row'  + (c.passed ? ' check-row_pass'  : ' check-row_fail'),
            iconClass: 'check-icon' + (c.passed ? ' check-icon_pass' : ' check-icon_fail'),
            iconLabel: c.passed ? '✓' : '✕'
          }))
        };
        this.brands = brands || [];
        this.orgWideEmailOptions = (owes || []).map(e => ({ label: e.label || e.address, value: e.address }));
        this.isLoadingStatus = false;
      })
      .catch(e => {
        this.errorMessage = e.body?.message || 'Failed to load settings.';
        this.isLoadingStatus = false;
      });

    this.loadEmailTemplates();
  }

  loadEmailTemplates() {
    this.isLoadingTemplate = true;
    getEmailTemplates({ brandId: this.selectedBrandId })
      .then(templates => {
        this.emailTemplates = templates || [];
        this.syncActiveTemplate();
        this.isLoadingTemplate = false;
      })
      .catch(e => {
        this.errorMessage = e.body?.message || 'Failed to load email templates.';
        this.isLoadingTemplate = false;
      });
  }

  syncActiveTemplate() {
    this.activeTemplate = (this.emailTemplates || []).find(t => t.emailType === this.activeEmailType) || null;
    this.previewHtml = '';
  }

  // ─── Settings handlers ────────────────────────────────────────────────────

  handleTabChange(evt) { this.activeTab = evt.currentTarget.dataset.tab; }

  handleConfigChange(evt) {
    const field = evt.currentTarget.dataset.field;
    this.config = { ...this.config, [field]: evt.detail.value };
  }

  handleToggleChange(evt) {
    const field = evt.currentTarget.dataset.field;
    this.config = { ...this.config, [field]: evt.detail.checked };
  }

  handleSaveSettings() {
    this.isSavingSettings = true;
    saveConfig({ dtoJson: JSON.stringify(this.config) })
      .then(saved => {
        this.config = saved;
        this.isSavingSettings = false;
        this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Signature settings saved.', variant: 'success' }));
      })
      .catch(e => {
        this.errorMessage = e.body?.message || 'Failed to save settings.';
        this.isSavingSettings = false;
      });
  }

  handleRecheck() {
    this.isLoadingStatus = true;
    getSetupStatus()
      .then(status => {
        const s = status || { checks: [], allPassed: false };
        this.setupStatus = {
          ...s,
          checks: (s.checks || []).map(c => ({
            ...c,
            rowClass:  'check-row'  + (c.passed ? ' check-row_pass'  : ' check-row_fail'),
            iconClass: 'check-icon' + (c.passed ? ' check-icon_pass' : ' check-icon_fail'),
            iconLabel: c.passed ? '✓' : '✕'
          }))
        };
        this.isLoadingStatus = false;
      })
      .catch(e => { this.errorMessage = e.body?.message || 'Check failed.'; this.isLoadingStatus = false; });
  }

  // ─── Email template handlers ──────────────────────────────────────────────

  handleBrandSelect(evt) {
    this.selectedBrandId = evt.detail.value || null;
    this.loadEmailTemplates();
  }

  handleEmailTypeChange(evt) {
    this.activeEmailType = evt.currentTarget.dataset.type;
    this.syncActiveTemplate();
  }

  handleTemplateFieldChange(evt) {
    const field = evt.currentTarget.dataset.field;
    this.activeTemplate = { ...this.activeTemplate, [field]: evt.detail.value };
  }

  handleBodyChange(evt) {
    this.activeTemplate = { ...this.activeTemplate, body: evt.detail.value };
  }

  handleToggleTemplate(evt) {
    const field = evt.currentTarget.dataset.field;
    this.activeTemplate = { ...this.activeTemplate, [field]: evt.detail.checked };
  }

  handleInsertToken(evt) {
    const token = evt.currentTarget.dataset.token;
    const richText = this.template.querySelector('lightning-input-rich-text');
    if (richText) {
      richText.setRangeText(token);
    } else {
      this.activeTemplate = { ...this.activeTemplate, body: (this.activeTemplate.body || '') + token };
    }
  }

  handleSaveTemplate() {
    if (!this.activeTemplate) return;
    this.isSavingTemplate = true;
    const dto = { ...this.activeTemplate, brandId: this.selectedBrandId };
    saveEmailTemplate({ dtoJson: JSON.stringify(dto) })
      .then(saved => {
        const idx = this.emailTemplates.findIndex(t => t.emailType === this.activeEmailType);
        if (idx >= 0) {
          const updated = [...this.emailTemplates];
          updated[idx] = saved;
          this.emailTemplates = updated;
        }
        this.activeTemplate = saved;
        this.isSavingTemplate = false;
        this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Email template saved.', variant: 'success' }));
      })
      .catch(e => {
        this.errorMessage = e.body?.message || 'Failed to save template.';
        this.isSavingTemplate = false;
      });
  }

  handleResetTemplate() {
    if (!this.activeTemplate?.id) {
      this.syncActiveTemplate();
      return;
    }
    resetToDefault({ templateId: this.activeTemplate.id })
      .then(() => {
        this.dispatchEvent(new ShowToastEvent({ title: 'Reset', message: 'Template reset to default.', variant: 'success' }));
        this.loadEmailTemplates();
      })
      .catch(e => { this.errorMessage = e.body?.message || 'Reset failed.'; });
  }

  handleRefreshPreview() {
    if (!this.activeTemplate) return;
    this.isLoadingPreview = true;
    // Build a simple sample preview — just show subject + body with sample tokens replaced
    const sample = {
      SignerName: 'Jordan Rivera', SenderName: 'Kriss Lugo', CompanyName: 'Evolving Consulting',
      DocumentTitle: 'Master Services Agreement', RoleName: 'Authorized Signer',
      Message: 'Please review and sign the attached agreement at your earliest convenience.',
      ActionButton: '<div style="margin:16px 0"><a href="#" style="background:#1f5f5b;color:#fff;padding:12px 24px;border-radius:6px;text-decoration:none;font-weight:600;">Review &amp; Sign Document</a></div>',
      DocumentInfo: '<div style="border-left:4px solid #1f5f5b;padding:12px 16px;margin:16px 0;background:#f9fafb;"><strong>Master Services Agreement</strong><br/>Your role: <strong>Authorized Signer</strong></div>',
      SecurityNote: '<p style="color:#6b7280;font-size:12px;">This link is unique to you and will expire in 48 hours.</p>',
      SignatureUrl: 'https://example.com/sign?token=SAMPLE-TOKEN',
      ExpirationHours: '48', LogoUrl: '', VerificationCode: '482913'
    };
    let preview = this.activeTemplate.body || '';
    Object.keys(sample).forEach(k => { preview = preview.split('{' + k + '}').join(sample[k]); });
    this.previewHtml = preview;
    this.isLoadingPreview = false;
  }

  clearError() { this.errorMessage = ''; }
}
