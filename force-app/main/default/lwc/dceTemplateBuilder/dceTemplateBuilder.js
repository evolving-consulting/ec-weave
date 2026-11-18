import { LightningElement, api, track } from "lwc";
import getAvailableObjects from "@salesforce/apex/DceTemplateBuilderController.getAvailableObjects";
import getOrgWideEmailAddresses from "@salesforce/apex/DceTemplateBuilderController.getOrgWideEmailAddresses";
import getTemplates from "@salesforce/apex/DceTemplateBuilderController.getTemplates";
import getFieldsForObject from "@salesforce/apex/DceTemplateBuilderController.getFieldsForObject";
import getRelationshipFields from "@salesforce/apex/DceTemplateBuilderController.getRelationshipFields";
import getUpdateableFieldsForObject from "@salesforce/apex/DceTemplateBuilderController.getUpdateableFieldsForObject";
import getLookupFieldsForChildObject from "@salesforce/apex/DceTemplateBuilderController.getLookupFieldsForChildObject";
import loadTemplate from "@salesforce/apex/DceTemplateBuilderController.loadTemplate";
import saveTemplate from "@salesforce/apex/DceTemplateBuilderController.saveTemplate";
import deleteTemplate from "@salesforce/apex/DceTemplateBuilderController.deleteTemplate";
import previewTemplate from "@salesforce/apex/DceTemplateBuilderController.previewTemplate";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";

const INLINE_HTML_LIMIT = 131072;
const MAX_HTML_LIMIT = 1000000;
const DISPLAY_STYLES = ["Normal", "Bold", "Italic", "Currency", "Percent", "Date", "DateTime", "Number"];
const LINE_STYLES = ["Normal", "Bold", "Italic"];
const STARTER_HEADER = "<p>{{Organization.Name}}</p>";
const STARTER_FOOTER =
  "<br/>\n<p>\nBest regards,<br/>\n{{Sender.FirstName}} {{Sender.LastName}}<br/>\n{{Sender.Email}}<br/>\n{{Sender.Phone}}\n</p>";

const UNIVERSAL_MERGE_FIELDS = [
  { label: "Organization · Name", value: "Organization.Name" },
  { label: "Sender · Email", value: "Sender.Email" },
  { label: "Sender · First Name", value: "Sender.FirstName" },
  { label: "Sender · Last Name", value: "Sender.LastName" },
  { label: "Sender · Phone", value: "Sender.Phone" },
  { label: "Sender · Mobile", value: "Sender.MobilePhone" },
  { label: "Sender · Address", value: "Sender.Address" },
  { label: "Sender · Street", value: "Sender.Street" },
  { label: "Sender · City", value: "Sender.City" },
  { label: "Sender · State/Province", value: "Sender.State" },
  { label: "Sender · Postal Code", value: "Sender.PostalCode" },
  { label: "Sender · Country", value: "Sender.Country" },
  { label: "Record Owner · Name", value: "Owner.Name" },
  { label: "Record Owner · Email", value: "Owner.Email" },
  { label: "Record Owner · First Name", value: "Owner.FirstName" },
  { label: "Record Owner · Last Name", value: "Owner.LastName" },
  { label: "Record Owner · Phone", value: "Owner.Phone" },
  { label: "Record Owner · Mobile", value: "Owner.MobilePhone" },
  { label: "Record Owner · Address", value: "Owner.Address" },
  { label: "Record Owner · Street", value: "Owner.Street" },
  { label: "Record Owner · City", value: "Owner.City" },
  { label: "Record Owner · State/Province", value: "Owner.State" },
  { label: "Record Owner · Postal Code", value: "Owner.PostalCode" },
  { label: "Record Owner · Country", value: "Owner.Country" },
  { label: "Organization · Street", value: "Organization.Street" },
  { label: "Organization · City", value: "Organization.City" },
  { label: "Organization · State/Province", value: "Organization.State" },
  { label: "Organization · Postal Code", value: "Organization.PostalCode" },
  { label: "Organization · Country", value: "Organization.Country" },
  { label: "Organization · Address", value: "Organization.Address" }
];

export default class DceTemplateBuilder extends LightningElement {
  @api recordId;

  @track currentView = "library";
  @track activeTab = "settings";
  @track template = this.newTemplate();
  @track templates = [];
  @track objects = [];
  @track orgWideEmailOptions = [];
  @track parentFields = [];
  @track updateableParentFields = [];
  @track childFields = [];
  @track lookupFields = [];
  @track recipientFields = [];
  @track recipientLookupFields = [];
  @track selectedTemplateId;
  @track selectedSectionKey;
  @track selectedLineKey;
  @track selectedFieldKey;
  @track selectedRecipientKey;
  @track selectedActionKey;
  @track searchTerm = "";
  @track statusFilter = "all";
  @track activeNav = "templates";
  @track showInfoBanner = true;
  @track advanced = false;
  @track isEditMode = false;
  @track isDirty = false;
  @track isLoading = false;
  @track errorMessage = "";
  @track previewRecordId;
  @track previewSubject = "";
  @track previewBody = "";
  @track deletedSectionIds = [];
  @track deletedLineIds = [];
  @track deletedFieldIds = [];
  @track deletedRecipientIds = [];
  @track deletedAttachmentIds = [];
  @track selectedAttachmentKey;
  @track recipientFilterDraft = this.newFilterDraft();
  @track showNewTemplateModal = false;
  @track newTemplateDraft = this._emptyTemplateDraft();
  @track showSectionModal = false;
  @track showHeaderFooterModal = false;
  @track parentRelationships = [];
  @track textSectionSelectedRelName = null;
  @track textSectionRelatedFields = [];
  @track queryBuilderObjects = [];
  @track showQbFieldModal = false;
  @track qbEditingObjectId = null;
  @track qbModalAllFields = [];
  @track qbModalSearch = "";
  @track qbModalTempSelected = [];

  // Drag-and-drop state
  @track dragSourceKey = null;
  @track dragOverKey = null;
  @track isDragFromPalette = false;
  @track paletteDragType = null;
  @track endDropZoneActive = false;

  localCounter = 0;

  async connectedCallback() {
    await Promise.all([this.loadObjects(), this.loadTemplates(), this.loadOrgWideEmailOptions()]);
    if (this.recordId) {
      await this.openTemplateById(this.recordId);
    }
  }

  // ── View / tab getters ─────────────────────────────────────────────────────

  get isLibraryView() { return this.activeNav === "templates" && this.currentView === "library"; }
  get isEditorView() { return this.activeNav === "templates" && this.currentView === "editor"; }

  get isSettingsTab() { return this.activeTab === "settings"; }
  get isHeaderFooterTab() { return this.activeTab === "headerFooter"; }
  get isBodyBuilderTab() { return this.activeTab === "bodyBuilder"; }
  get isRecipientsTab() { return this.activeTab === "recipients"; }
  get isPostSendActionsTab() { return this.activeTab === "postSendActions"; }
  get isAttachmentsTab() { return this.activeTab === "attachments"; }
  get isPreviewTab() { return this.activeTab === "preview"; }
  get isQueryBuilderTab() { return this.activeTab === "queryBuilder"; }

  get isTemplatesNav() { return this.activeNav === "templates"; }
  get isLearningNav() { return this.activeNav === "learning"; }
  get isUpdatesNav() { return this.activeNav === "updates"; }

  get tabClass_settings() { return this._editorTabClass("settings"); }
  get tabClass_headerFooter() { return this._editorTabClass("headerFooter"); }
  get tabClass_bodyBuilder() { return this._editorTabClass("bodyBuilder"); }
  get tabClass_recipients() { return this._editorTabClass("recipients"); }
  get tabClass_postSendActions() { return this._editorTabClass("postSendActions"); }
  get tabClass_attachments() { return this._editorTabClass("attachments"); }
  get tabClass_preview() { return this._editorTabClass("preview"); }
  get tabClass_queryBuilder() { return this._editorTabClass("queryBuilder"); }
  _editorTabClass(tab) {
    return `editor-tab${this.activeTab === tab ? " editor-tab_active" : ""}`;
  }

  get navClassTemplates() { return this._navClass("templates"); }
  get navClassLearning() { return this._navClass("learning"); }
  get navClassUpdates() { return this._navClass("updates"); }
  _navClass(view) {
    return `sidebar-nav-item${this.activeNav === view ? " sidebar-nav-item_active" : ""}`;
  }

  get filterTabClassAll() { return this._filterTabClass("all"); }
  get filterTabClassActive() { return this._filterTabClass("active"); }
  get filterTabClassDraft() { return this._filterTabClass("draft"); }
  get filterTabClassArchived() { return this._filterTabClass("archived"); }
  _filterTabClass(filter) {
    return `filter-tab${this.statusFilter === filter ? " filter-tab_active" : ""}`;
  }

  get mainPanelClass() {
    return `main-panel${this.isEditorView ? " main-panel_editor" : ""}`;
  }

  get canvasClass() {
    return `builder-canvas${this.endDropZoneActive ? "" : ""}`;
  }

  get templateStatusPillClass() {
    const s = (this.template.status || "draft").toLowerCase();
    return `status-pill status-pill_${s}`;
  }

  get selectedSectionTypeBadgeClass() {
    const type = (this.selectedSection?.sectionType || "text").toLowerCase().replace(/ /g, "_");
    return `section-type-badge section-type-badge_${type}`;
  }

  // ── Library computed ───────────────────────────────────────────────────────

  get hasTemplates() { return this.filteredTemplates.length > 0; }
  get hasSections() { return (this.template.sections || []).length > 0; }

  get filteredTemplates() {
    const term = (this.searchTerm || "").toLowerCase();
    const sf = this.statusFilter;
    const filterMap = { active: "Active", draft: "Draft", archived: "Archive" };
    return (this.templates || []).filter((item) => {
      if (sf !== "all" && (item.status || "Draft") !== (filterMap[sf] || sf)) return false;
      if (!term) return true;
      return `${item.name || ""} ${item.parentObjectLabel || ""} ${item.description || ""}`.toLowerCase().includes(term);
    });
  }

  // ── Field / object options ─────────────────────────────────────────────────

  get objectOptions() {
    return this.objects.map((item) => ({ label: item.label, value: item.apiName }));
  }

  get parentFieldOptions() { return this.toFieldOptions(this.parentFields); }

  get headerFooterFieldOptions() {
    return [
      ...UNIVERSAL_MERGE_FIELDS,
      ...this.parentFieldOptions.map((f) => ({ ...f, label: `Record · ${f.label}`, value: `Parent.${f.value}` }))
    ];
  }

  get updateableParentFieldOptions() { return this.toFieldOptions(this.updateableParentFields); }
  get childFieldOptions() { return this.toFieldOptions(this.childFields); }

  get lookupFieldOptions() {
    return this.lookupFields.map((f) => ({ label: this.fieldLabel(f), value: f.apiName }));
  }

  get recipientFieldOptions() { return this.toFieldOptions(this.recipientFields); }

  get recipientLookupFieldOptions() {
    return this.recipientLookupFields.map((f) => ({ label: this.fieldLabel(f), value: f.apiName }));
  }

  // ── Section / canvas computed ──────────────────────────────────────────────

  get sectionsForCanvas() {
    return (this.template.sections || []).map((section) => ({
      ...section,
      isSelected: section.localKey === this.selectedSectionKey,
      isDragging: section.localKey === this.dragSourceKey,
      isDragOver: section.localKey === this.dragOverKey,
      wrapClass: `canvas-section-wrap${section.localKey === this.dragOverKey ? " canvas-section-wrap_drag-over" : ""}`
    }));
  }

  get sectionsForList() {
    return (this.template.sections || []).map((section) => {
      const type = section.sectionType || "Text";
      const typeKey = type.toLowerCase().replace(/ /g, "_");
      return {
        ...section,
        listCardClass: `section-list-card${section.localKey === this.selectedSectionKey ? " section-list-card_selected" : ""}`,
        typeBadgeClass: `section-type-badge section-type-badge_${typeKey}`,
      };
    });
  }

  get endDropZoneClass() {
    return `canvas-end-drop-zone${this.endDropZoneActive ? " canvas-end-drop-zone_active" : ""}`;
  }

  get sectionTokenOptions() {
    return (this.template.sections || [])
      .filter((s) => s.sectionKey)
      .map((s) => ({ label: s.sectionName || s.sectionKey, value: s.sectionKey }));
  }

  get selectedSection() {
    return (this.template.sections || []).find((s) => s.localKey === this.selectedSectionKey);
  }

  get selectedLine() {
    return (this.selectedSection?.lines || []).find((l) => l.localKey === this.selectedLineKey);
  }

  get selectedField() {
    return (this.selectedSection?.fields || []).find((f) => f.localKey === this.selectedFieldKey);
  }

  get selectedRecipient() {
    return (this.template.recipients || []).find((r) => r.localKey === this.selectedRecipientKey);
  }

  get selectedAction() {
    return (this.template.postSendActions || []).find((a) => a.localKey === this.selectedActionKey);
  }

  get selectedAttachment() {
    return (this.template.attachments || []).find((a) => a.localKey === this.selectedAttachmentKey);
  }

  get hasAttachments() { return (this.template.attachments || []).length > 0; }

  get isStaticAttachment() { return this.selectedAttachment?.attachmentSource === "Static File"; }
  get isRelatedRecordAttachment() { return this.selectedAttachment?.attachmentSource === "Related Record Files"; }

  get attachmentSourceOptions() {
    return [
      { label: "Static File", value: "Static File" },
      { label: "Source Record Files", value: "Source Record Files" },
      { label: "Related Record Files", value: "Related Record Files" }
    ];
  }

  get queryOptions() {
    return (this.template.queries || []).map((q) => ({ label: q.name, value: q.id || q.localKey }));
  }

  get isSelectedTextSection() { return this.selectedSection?.sectionType === "Text"; }
  get isSelectedStaticSection() { return this.isSelectedTextSection; }
  get isSelectedColumnsSection() { return this.selectedSection?.sectionType === "Columns"; }
  get isTextSectionVisualMode() { return (this.selectedSection?.textEditorMode || 'Visual') === 'Visual'; }
  get selectedSectionEditorMode() { return this.selectedSection?.textEditorMode || 'Visual'; }
  get hasTextSectionRelFields() { return this.textSectionRelatedFields.length > 0; }
  get parentRelationshipOptions() {
    return this.parentRelationships.map(r => ({ label: r.label, value: r.relationshipName }));
  }
  get textSectionRelatedFieldOptions() {
    return this.textSectionRelatedFields.map(f => ({ label: f.label, value: f.apiName }));
  }

  get isSelectedRepeatingSection() {
    return this.selectedSection?.sectionType === "Text Block" || this.selectedSection?.sectionType === "Related";
  }

  get isSelectedTextBlockSection() { return this.selectedSection?.sectionType === "Text Block"; }
  get isSelectedRelatedSection() { return this.selectedSection?.sectionType === "Related"; }

  get selectedColumnsCountStr() { return String(this.selectedSection?.columnCount || 2); }

  get columnCountOptions() {
    return [{ label: "2", value: "2" }, { label: "3", value: "3" }, { label: "4", value: "4" }];
  }

  get selectedSectionColumns() {
    const count = this.selectedSection?.columnCount || 2;
    const existing = this.selectedSection?.columns || [];
    const cols = [];
    for (let i = 0; i < count; i++) {
      cols.push({
        localKey: existing[i]?.localKey || `col_${i}`,
        colIndex: i + 1,
        content: existing[i]?.content || ""
      });
    }
    return cols;
  }

  // ── Query Builder getters ─────────────────────────────────────────────────

  get hasParentFields() { return this.parentFields.length > 0; }

  get hasCopyPasteTags() {
    return this.queryBuilderObjects.some(o => o.fields.length > 0);
  }

  get queryBuilderFieldCount() {
    return this.queryBuilderObjects.reduce((sum, o) => sum + o.fields.length, 0);
  }

  get qbEditingObject() {
    return this.queryBuilderObjects.find(o => o.id === this.qbEditingObjectId) || null;
  }

  get qbModalFields() {
    const term = (this.qbModalSearch || "").toLowerCase();
    const selectedSet = new Set(this.qbModalTempSelected.map(f => f.apiName));
    return this.qbModalAllFields
      .filter(f => !term || f.label.toLowerCase().includes(term) || f.apiName.toLowerCase().includes(term))
      .map(f => ({ ...f, isSelected: selectedSet.has(f.apiName) }));
  }

  get qbModalFieldsLoading() { return this.showQbFieldModal && this.qbModalAllFields.length === 0; }

  get availableRelatedObjects() {
    const added = new Set(this.queryBuilderObjects.map(o => o.objectApiName));
    return this.parentRelationships
      .filter(r => r.referenceTo && !added.has(r.referenceTo))
      .map(r => ({ label: r.label || r.relationshipName, value: r.referenceTo, relationshipName: r.relationshipName }));
  }

  get hasAvailableRelatedObjects() { return this.availableRelatedObjects.length > 0; }

  get copyPasteTagGroups() {
    return this.queryBuilderObjects
      .filter(o => o.fields.length > 0)
      .map(o => ({ name: o.label, tags: o.fields }));
  }

  get queryBuilderTagOptions() {
    return this.queryBuilderObjects.flatMap(o =>
      o.fields.map(f => ({ label: `${f.label} — ${f.tag}`, value: f.tag }))
    );
  }

  get isParentRecipient() { return this.selectedRecipient?.recipientSourceType === "Parent Field"; }
  get isRelatedRecipient() { return this.selectedRecipient?.recipientSourceType === "Related Records"; }
  get isManualRecipient() { return this.selectedRecipient?.recipientSourceType === "Manual"; }

  get isSelectedUpdateFieldAction() { return this.selectedAction?.actionType === "Update Field"; }
  get isSelectedCreateTaskAction() { return this.selectedAction?.actionType === "Create Task"; }
  get isSelectedSpecificUserTask() { return this.selectedAction?.assignedToType === "Specific User"; }

  // ── Options lists ──────────────────────────────────────────────────────────

  get statusOptions() {
    return [
      { label: "Draft", value: "Draft" },
      { label: "Active", value: "Active" },
      { label: "Archive", value: "Archive" }
    ];
  }

  get isApiNameReadonly() { return !!this.template.id; }

  get editorModeOptions() {
    return [{ label: "Visual", value: "Visual" }, { label: "HTML Source", value: "HTML Source" }];
  }

  get isHeaderVisualMode() { return this.template.headerEditorMode !== "HTML Source"; }
  get isBodyVisualMode() { return this.template.bodyEditorMode !== "HTML Source"; }
  get isFooterVisualMode() { return this.template.footerEditorMode !== "HTML Source"; }

  get headerUsesOverflow() { return this.contentLength("headerContent") > INLINE_HTML_LIMIT; }
  get bodyUsesOverflow() { return this.contentLength("bodyTemplate") > INLINE_HTML_LIMIT; }
  get footerUsesOverflow() { return this.contentLength("footerContent") > INLINE_HTML_LIMIT; }

  get headerCharacterCount() { return this.characterCountLabel("headerContent"); }
  get bodyCharacterCount() { return this.characterCountLabel("bodyTemplate"); }
  get footerCharacterCount() { return this.characterCountLabel("footerContent"); }

  get headerCountClass() { return this.characterCountClass("headerContent"); }
  get bodyCountClass() { return this.characterCountClass("bodyTemplate"); }
  get footerCountClass() { return this.characterCountClass("footerContent"); }

  get showStarterHeaderButton() { return !String(this.template.headerContent || "").trim(); }
  get showStarterFooterButton() { return !String(this.template.footerContent || "").trim(); }

  get previewDisabled() { return !this.template.id || !this.previewRecordId; }

  get lineDisplayStyleOptions() { return LINE_STYLES.map((s) => ({ label: s, value: s })); }
  get displayStyleOptions() { return DISPLAY_STYLES.map((s) => ({ label: s, value: s })); }

  get sortDirectionOptions() {
    return [{ label: "Ascending", value: "ASC" }, { label: "Descending", value: "DESC" }];
  }

  get filterOperatorOptions() {
    return [
      { label: "equals", value: "=" },
      { label: "not equals", value: "!=" },
      { label: "is blank", value: "BLANK" },
      { label: "is not blank", value: "NOT_BLANK" },
      { label: "greater than", value: ">" },
      { label: "greater or equal", value: ">=" },
      { label: "less than", value: "<" },
      { label: "less or equal", value: "<=" }
    ];
  }

  get recipientSourceOptions() {
    return [
      { label: "Parent Field", value: "Parent Field" },
      { label: "Related Records", value: "Related Records" },
      { label: "Manual", value: "Manual" }
    ];
  }

  get recipientTypeOptions() {
    return [{ label: "To", value: "To" }, { label: "CC", value: "CC" }, { label: "BCC", value: "BCC" }];
  }

  get postSendActionTypeOptions() {
    return [{ label: "Update Field", value: "Update Field" }, { label: "Create Task", value: "Create Task" }];
  }

  get postSendValueTypeOptions() {
    return [
      { label: "Static Value", value: "Static" },
      { label: "Boolean", value: "Boolean" },
      { label: "Current Date", value: "Current Date" },
      { label: "Current DateTime", value: "Current DateTime" },
      { label: "Merge Field", value: "Merge Field" }
    ];
  }

  get taskAssignedToOptions() {
    return [
      { label: "Triggering Record Owner", value: "Triggering Record Owner" },
      { label: "Current User", value: "Current User" },
      { label: "Specific User", value: "Specific User" }
    ];
  }

  get taskDueDateStrategyOptions() {
    return [{ label: "Email Sent Date + X Days", value: "Email Sent Date + X Days" }];
  }

  get taskStatusOptions() {
    return [
      { label: "Not Started", value: "Not Started" },
      { label: "In Progress", value: "In Progress" },
      { label: "Completed", value: "Completed" },
      { label: "Waiting on someone else", value: "Waiting on someone else" },
      { label: "Deferred", value: "Deferred" }
    ];
  }

  get taskPriorityOptions() {
    return [{ label: "High", value: "High" }, { label: "Normal", value: "Normal" }, { label: "Low", value: "Low" }];
  }

  // ── Apex loaders ──────────────────────────────────────────────────────────

  async loadObjects() {
    try { this.objects = await getAvailableObjects(); }
    catch (error) { this.handleError(error, "Unable to load objects."); }
  }

  async loadOrgWideEmailOptions() {
    try {
      const addresses = await getOrgWideEmailAddresses();
      this.orgWideEmailOptions = [
        { label: "Use current user's default email", value: "" },
        ...(addresses || []).map((item) => ({
          label: item.label || `${item.displayName || item.address} <${item.address}>`,
          value: item.address
        }))
      ];
    } catch (error) { this.handleError(error, "Unable to load org-wide email addresses."); }
  }

  async loadTemplates() {
    this.isLoading = true;
    try {
      const rows = await getTemplates();
      this.templates = (rows || []).map((item) => {
        const status = item.status || (item.active ? "Active" : item.archived ? "Archive" : "Draft");
        const statusLabel = status === "Archive" ? "Archived" : status;
        return {
          ...item,
          status,
          statusLabel,
          statusClass: `status-pill status-pill_${statusLabel.toLowerCase()}`,
          lastModifiedDisplay: item.lastModifiedDate ? new Date(item.lastModifiedDate).toLocaleString() : ""
        };
      });
    } catch (error) { this.handleError(error, "Unable to load templates."); }
    finally { this.isLoading = false; }
  }

  async loadFields(objectApiName, target = "parent") {
    if (!objectApiName) return;
    const fields = await getFieldsForObject({ objectApiName });
    if (target === "child") this.childFields = fields;
    else if (target === "recipient") this.recipientFields = fields;
    else this.parentFields = fields;
  }

  async loadUpdateableParentFields(objectApiName) {
    if (!objectApiName) return;
    this.updateableParentFields = await getUpdateableFieldsForObject({ objectApiName });
  }

  async loadParentRelationships(objectApiName) {
    if (!objectApiName) return;
    this.parentRelationships = await getRelationshipFields({ objectApiName });
  }

  async loadLookupFields(childObjectApiName, target = "section") {
    if (!childObjectApiName || !this.template.parentObjectApiName) return;
    const fields = await getLookupFieldsForChildObject({
      childObjectApiName,
      parentObjectApiName: this.template.parentObjectApiName
    });
    if (target === "recipient") this.recipientLookupFields = fields;
    else this.lookupFields = fields;
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  handleNavClick(event) {
    this.activeNav = event.currentTarget.dataset.view;
  }

  handleTabClick(event) {
    const tab = event.currentTarget.dataset.tab;
    this.activeTab = tab;
    this._prepareTab(tab);
  }

  async _prepareTab(tab) {
    if (tab === "recipients" && this.selectedRecipient) {
      await this.prepareRecipientMetadata();
    }
    if (tab === "postSendActions" && this.template.parentObjectApiName && !this.updateableParentFields.length) {
      await this.loadUpdateableParentFields(this.template.parentObjectApiName);
    }
    if (tab === "queryBuilder" && this.template.parentObjectApiName && this.queryBuilderObjects.length === 0) {
      await this._initQueryBuilderObjects();
    }
  }

  async _initQueryBuilderObjects() {
    const parentApiName = this.template.parentObjectApiName;
    if (!parentApiName) return;
    const fields = await getFieldsForObject({ objectApiName: parentApiName });
    const idField = (fields || []).find(f => f.apiName === "Id");
    const parentLabel = this.objects.find(o => o.apiName === parentApiName)?.label || parentApiName;
    this.queryBuilderObjects = [{
      id: "qbobj_parent",
      objectApiName: parentApiName,
      label: parentLabel,
      isParent: true,
      tagPrefix: "Parent",
      fields: idField ? [{ apiName: "Id", label: idField.label || "ID", tag: "{{Parent.Id}}" }] : []
    }];
  }

  async backToLibrary() {
    if (
      this.isDirty &&
      !(await LightningConfirm.open({
        message: "You have unsaved changes. Continue and discard them?",
        label: "Discard unsaved changes?",
        theme: "warning"
      }))
    ) return;
    this.currentView = "library";
    this.isDirty = false;
    await this.loadTemplates();
  }

  _enterEditor() {
    this.currentView = "editor";
    this.activeTab = "settings";
  }

  goToHeaderFooterTab() {
    this.activeTab = "headerFooter";
  }

  // ── Library actions ───────────────────────────────────────────────────────

  handleStatusFilter(event) { this.statusFilter = event.currentTarget.dataset.filter; }
  handleSearch(event) { this.searchTerm = event.detail.value; }
  dismissInfoBanner() { this.showInfoBanner = false; }
  handleTalkToEC() { this.dispatchEvent(new CustomEvent("talktoec")); }

  async openTemplate(event) {
    await this.openTemplateById(event.currentTarget.dataset.id);
  }

  async openTemplateById(templateId) {
    if (
      this.isDirty &&
      !(await LightningConfirm.open({
        message: "You have unsaved changes. Continue and discard them?",
        label: "Discard unsaved changes?",
        theme: "warning"
      }))
    ) return;
    this.isLoading = true;
    try {
      const loaded = await loadTemplate({ templateId });
      this.template = this.normalizeTemplate(loaded);
      this.selectedTemplateId = this.template.id;
      this.isEditMode = true;
      this.isDirty = false;
      this.clearDeletedIds();
      this.selectedSectionKey = this.template.sections[0]?.localKey;
      this.selectedRecipientKey = this.template.recipients[0]?.localKey;
      this.selectedActionKey = this.template.postSendActions[0]?.localKey;
      this.previewSubject = "";
      this.previewBody = "";
      if (this.template.parentObjectApiName) {
        await Promise.all([
          this.loadFields(this.template.parentObjectApiName),
          this.loadUpdateableParentFields(this.template.parentObjectApiName),
          this.loadParentRelationships(this.template.parentObjectApiName),
        ]);
      }
      if (this.selectedSection?.childObjectApiName) {
        await this.loadFields(this.selectedSection.childObjectApiName, "child");
        await this.loadLookupFields(this.selectedSection.childObjectApiName);
      }
      this._enterEditor();
      this.clearError();
    } catch (error) {
      this.handleError(error, "Unable to open template.");
    } finally { this.isLoading = false; }
  }

  async deleteTemplateFromLibrary(event) {
    const templateId = event.currentTarget.dataset.id;
    if (
      !(await LightningConfirm.open({
        message: "Delete this template and its configuration records? This cannot be undone.",
        label: "Delete template?",
        theme: "warning"
      }))
    ) return;
    this.isLoading = true;
    try {
      await deleteTemplate({ templateId });
      await this.loadTemplates();
      this.showToast("Deleted", "Template deleted.", "success");
    } catch (error) { this.handleError(error, "Unable to delete template."); }
    finally { this.isLoading = false; }
  }

  async cloneTemplate(event) {
    const templateId = event.currentTarget.dataset.id;
    this.isLoading = true;
    try {
      const loaded = await loadTemplate({ templateId });
      const clone = this.normalizeTemplate(loaded);
      clone.id = null;
      clone.name = `${clone.name} (Copy)`;
      clone.sections.forEach((s) => {
        s.id = null;
        (s.lines || []).forEach((l) => { l.id = null; });
        (s.fields || []).forEach((f) => { f.id = null; });
      });
      (clone.recipients || []).forEach((r) => { r.id = null; });
      (clone.postSendActions || []).forEach((a) => { a.id = null; });
      (clone.attachments || []).forEach((a) => { a.id = null; });
      this.template = clone;
      this.isEditMode = false;
      this.isDirty = true;
      this.clearDeletedIds();
      if (clone.parentObjectApiName) {
        await this.loadFields(clone.parentObjectApiName);
        await this.loadUpdateableParentFields(clone.parentObjectApiName);
      }
      this._enterEditor();
      this.clearError();
    } catch (error) { this.handleError(error, "Unable to clone template."); }
    finally { this.isLoading = false; }
  }

  // ── New template modal ────────────────────────────────────────────────────

  openNewTemplateModal() {
    this.newTemplateDraft = this._emptyTemplateDraft();
    this.showNewTemplateModal = true;
  }

  closeNewTemplateModal() { this.showNewTemplateModal = false; }

  handleNewTemplateNameChange(event) {
    const name = event.detail.value || "";
    this.newTemplateDraft = { ...this.newTemplateDraft, name, apiName: name.replace(/ /g, "_") };
  }

  handleNewTemplateDraftChange(event) {
    const fieldName = event.target.name;
    const value = event.detail?.value ?? event.target.value ?? "";
    this.newTemplateDraft = { ...this.newTemplateDraft, [fieldName]: value };
  }

  handleNewTemplateDraftChecked(event) {
    this.newTemplateDraft = { ...this.newTemplateDraft, [event.target.name]: event.target.checked };
  }

  async confirmNewTemplate() {
    if (!this.newTemplateDraft.name?.trim()) { this.setError("Template name is required."); return; }
    if (!this.newTemplateDraft.parentObjectApiName) { this.setError("Parent object is required."); return; }
    if (
      this.isDirty &&
      !(await LightningConfirm.open({
        message: "You have unsaved changes. Continue and discard them?",
        label: "Discard unsaved changes?",
        theme: "warning"
      }))
    ) return;
    this.showNewTemplateModal = false;
    this.template = this.normalizeTemplate({
      ...this.newTemplate(),
      name: this.newTemplateDraft.name,
      apiName: this.newTemplateDraft.apiName,
      description: this.newTemplateDraft.description,
      parentObjectApiName: this.newTemplateDraft.parentObjectApiName,
      defaultFromEmail: this.newTemplateDraft.defaultFromEmail,
      storeEmailHistory: this.newTemplateDraft.storeEmailHistory,
      allowUserEditBeforeSend: this.newTemplateDraft.allowUserEditBeforeSend,
      status: "Draft"
    });
    this.selectedTemplateId = null;
    this.isEditMode = false;
    this.isDirty = true;
    this.clearDeletedIds();
    this.selectedSectionKey = null;
    this.selectedLineKey = null;
    this.selectedFieldKey = null;
    this.selectedRecipientKey = null;
    this.selectedActionKey = null;
    this.selectedAttachmentKey = null;
    this.previewRecordId = null;
    this.previewSubject = "";
    this.previewBody = "";
    this.clearError();
    if (this.newTemplateDraft.parentObjectApiName) {
      await Promise.all([
        this.loadFields(this.newTemplateDraft.parentObjectApiName),
        this.loadUpdateableParentFields(this.newTemplateDraft.parentObjectApiName),
        this.loadParentRelationships(this.newTemplateDraft.parentObjectApiName),
      ]);
    }
    this._enterEditor();
  }

  // ── Template field handlers ───────────────────────────────────────────────

  handleTemplateChange(event) {
    const name = event.target.name;
    const value = event.detail?.value ?? event.target.value ?? "";
    this.updateTemplate({ [name]: value });
  }

  handleTemplateChecked(event) {
    this.updateTemplate({ [event.target.name]: event.target.checked });
  }

  async handleParentObjectChange(event) {
    this.updateTemplate({
      parentObjectApiName: event.detail.value,
      parentObjectLabel: this.objectLabel(event.detail.value)
    });
    await this.loadFields(this.template.parentObjectApiName);
    await this.loadUpdateableParentFields(this.template.parentObjectApiName);
  }

  updateTemplate(changes) {
    this.template = { ...this.template, ...changes };
    this.markDirty();
  }

  insertStarterHeader() { this.updateTemplate({ headerContent: STARTER_HEADER }); }
  insertStarterFooter() { this.updateTemplate({ footerContent: STARTER_FOOTER }); }

  insertHeaderField(event) { this._insertRegionField("headerContent", event.detail.value); }
  insertFooterField(event) { this._insertRegionField("footerContent", event.detail.value); }

  _insertRegionField(regionName, fieldPath) {
    if (!fieldPath) return;
    const token = fieldPath.startsWith("Parent.") ? `{{${fieldPath}}}` : `{{${fieldPath}}}`;
    this.updateTemplate({ [regionName]: `${this.template[regionName] || ""}${token}` });
  }

  insertSubjectField(event) {
    this.updateTemplate({ subjectTemplate: `${this.template.subjectTemplate || ""}{{Parent.${event.detail.value}}}` });
  }

  insertBodyField(event) {
    this.updateTemplate({ bodyTemplate: `${this.template.bodyTemplate || ""}{{Parent.${event.detail.value}}}` });
  }

  insertSectionToken(event) {
    this.updateTemplate({ bodyTemplate: `${this.template.bodyTemplate || ""}{{Section.${event.detail.value}}}` });
  }

  // ── Canvas section click / select / deselect ──────────────────────────────

  handleCanvasSectionClick(event) {
    const key = event.currentTarget.dataset.key;
    this.selectedSectionKey = key;
    this.selectedLineKey = null;
    this.selectedFieldKey = null;
    if (this.selectedSection?.childObjectApiName) {
      this.loadFields(this.selectedSection.childObjectApiName, "child");
      this.loadLookupFields(this.selectedSection.childObjectApiName);
    }
    this.decorateSelectedLineItems();
  }

  clearSectionSelection() {
    this.selectedSectionKey = null;
    this.selectedLineKey = null;
    this.selectedFieldKey = null;
    this.showSectionModal = false;
  }

  closeSectionModal() {
    this.showSectionModal = false;
  }

  openHeaderFooterModal() {
    this.showHeaderFooterModal = true;
  }

  closeHeaderFooterModal() {
    this.showHeaderFooterModal = false;
  }

  // ── Drag-and-drop: palette ────────────────────────────────────────────────

  handlePaletteDragStart(event) {
    this.isDragFromPalette = true;
    this.paletteDragType = event.currentTarget.dataset.type;
    this.dragSourceKey = null;
    event.dataTransfer.effectAllowed = "copy";
    event.dataTransfer.setData("text/plain", this.paletteDragType);
  }

  handlePaletteAddClick(event) {
    this.addSectionOfType(event.currentTarget.dataset.type);
  }

  // ── Drag-and-drop: canvas section cards ──────────────────────────────────

  handleSectionDragStart(event) {
    this.isDragFromPalette = false;
    this.dragSourceKey = event.currentTarget.dataset.key;
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", this.dragSourceKey);
  }

  handleSectionDragOver(event) {
    event.preventDefault();
    event.dataTransfer.dropEffect = this.isDragFromPalette ? "copy" : "move";
    const key = event.currentTarget.dataset.key;
    if (this.dragOverKey !== key) this.dragOverKey = key;
    this.endDropZoneActive = false;
  }

  handleSectionDragLeave(event) {
    if (!event.currentTarget.contains(event.relatedTarget)) {
      this.dragOverKey = null;
    }
  }

  handleSectionDrop(event) {
    event.preventDefault();
    const targetKey = event.currentTarget.dataset.key;
    if (this.isDragFromPalette) {
      this.insertSectionBefore(this.paletteDragType, targetKey);
    } else if (this.dragSourceKey && this.dragSourceKey !== targetKey) {
      this.reorderSections(this.dragSourceKey, targetKey);
    }
    this._clearDragState();
  }

  // ── Drag-and-drop: canvas background ─────────────────────────────────────

  handleCanvasDragOver(event) {
    event.preventDefault();
    event.dataTransfer.dropEffect = this.isDragFromPalette ? "copy" : "move";
  }

  handleCanvasDragLeave() { /* handled by child zones */ }

  handleCanvasDrop(event) {
    // only fires when drop lands on canvas itself (not a card or end zone)
    if (event.target === event.currentTarget) {
      event.preventDefault();
      if (this.isDragFromPalette) this.addSectionOfType(this.paletteDragType);
      else if (this.dragSourceKey) this.reorderSections(this.dragSourceKey, null);
      this._clearDragState();
    }
  }

  // ── Drag-and-drop: end drop zone ─────────────────────────────────────────

  handleEndDropZoneDragOver(event) {
    event.preventDefault();
    this.endDropZoneActive = true;
    this.dragOverKey = null;
  }

  handleEndDropZoneDragLeave() { this.endDropZoneActive = false; }

  handleEndDropZoneDrop(event) {
    event.preventDefault();
    if (this.isDragFromPalette) this.addSectionOfType(this.paletteDragType);
    else if (this.dragSourceKey) this.reorderSections(this.dragSourceKey, null);
    this._clearDragState();
  }

  _clearDragState() {
    this.dragSourceKey = null;
    this.dragOverKey = null;
    this.isDragFromPalette = false;
    this.paletteDragType = null;
    this.endDropZoneActive = false;
  }

  // ── Section mutation ──────────────────────────────────────────────────────

  addSectionOfType(type) {
    if (type === "Columns") { this.addColumnsSection(2); return; }
    const order = this.template.sections.length + 1;
    const section = {
      localKey: this.nextKey("section"),
      name: `Section ${order}`,
      sectionName: `Section ${order}`,
      sectionKey: `Section${order}`,
      active: true,
      displayOrder: order,
      sectionType: type || "Text",
      textEditorMode: "Visual",
      staticContent: "",
      sortDirection: "ASC",
      repeatLabel: "Option",
      includeAutoNumber: false,
      autoNumberStart: 1,
      lines: [],
      fields: []
    };
    this.template = { ...this.template, sections: [...this.template.sections, section] };
    this.selectedSectionKey = section.localKey;
    this.markDirty();
  }

  insertSectionBefore(type, beforeKey) {
    if (type === "Columns") { this.addColumnsSection(2); return; }
    const order = this.template.sections.length + 1;
    const newSection = {
      localKey: this.nextKey("section"),
      name: `Section ${order}`,
      sectionName: `Section ${order}`,
      sectionKey: `Section${order}`,
      active: true,
      displayOrder: order,
      sectionType: type || "Text",
      textEditorMode: "Visual",
      staticContent: "",
      sortDirection: "ASC",
      repeatLabel: "Option",
      includeAutoNumber: false,
      autoNumberStart: 1,
      lines: [],
      fields: []
    };
    const idx = this.template.sections.findIndex((s) => s.localKey === beforeKey);
    const sections = [...this.template.sections];
    sections.splice(idx >= 0 ? idx : sections.length, 0, newSection);
    this.template = { ...this.template, sections: this._resequence(sections) };
    this.selectedSectionKey = newSection.localKey;
    this.markDirty();
  }

  reorderSections(sourceKey, targetKey) {
    const sections = [...this.template.sections];
    const sourceIdx = sections.findIndex((s) => s.localKey === sourceKey);
    if (sourceIdx < 0) return;
    const [moved] = sections.splice(sourceIdx, 1);
    if (targetKey) {
      const targetIdx = sections.findIndex((s) => s.localKey === targetKey);
      sections.splice(targetIdx >= 0 ? targetIdx : sections.length, 0, moved);
    } else {
      sections.push(moved);
    }
    this.template = { ...this.template, sections: this._resequence(sections) };
    this.markDirty();
  }

  _resequence(sections) {
    return sections.map((s, i) => ({ ...s, displayOrder: i + 1 }));
  }

  handleSectionDeleteFromCanvas(event) {
    const key = event.detail.key;
    const section = this.template.sections.find((s) => s.localKey === key);
    if (section?.id) this.deletedSectionIds = [...this.deletedSectionIds, section.id];
    (section?.lines || []).forEach((l) => { if (l.id) this.deletedLineIds = [...this.deletedLineIds, l.id]; });
    (section?.fields || []).forEach((f) => { if (f.id) this.deletedFieldIds = [...this.deletedFieldIds, f.id]; });
    const sections = this.template.sections.filter((s) => s.localKey !== key);
    this.template = { ...this.template, sections: this._resequence(sections) };
    if (this.selectedSectionKey === key) {
      this.selectedSectionKey = sections[0]?.localKey;
      this.selectedLineKey = null;
      this.selectedFieldKey = null;
    }
    this.markDirty();
  }

  handleSectionChange(event) {
    const name = event.target.name;
    const value = event.detail.value;
    const changes = { [name]: value };
    if (name === "sectionName") changes.sectionKey = this.toKey(value);
    this.updateSelectedSection(changes);
  }

  handleSectionChecked(event) {
    this.updateSelectedSection({ [event.target.name]: event.target.checked });
  }

  // ── Query config events from dceBuilderQueryConfig ────────────────────────

  handleQueryConfigChange(event) {
    this.updateSelectedSection(event.detail);
  }

  async handleSectionChildObjectChange(event) {
    const { childObjectApiName } = event.detail;
    this.updateSelectedSection({
      childObjectApiName,
      childObjectLabel: this.objectLabel(childObjectApiName),
      parentLookupFieldApiName: null,
      sortFieldApiName: null
    });
    if (childObjectApiName) {
      await this.loadFields(childObjectApiName, "child");
      await this.loadLookupFields(childObjectApiName);
    }
  }

  // ── Sections tab list handlers ────────────────────────────────────────────

  selectSectionFromList(event) {
    const key = event.currentTarget.dataset.key;
    if (!key) return;
    this.selectedSectionKey = key;
    this.selectedLineKey = null;
    this.selectedFieldKey = null;
    if (this.selectedSection?.childObjectApiName) {
      this.loadFields(this.selectedSection.childObjectApiName, "child");
      this.loadLookupFields(this.selectedSection.childObjectApiName);
    }
    this.decorateSelectedLineItems();
  }

  addSectionFromList(event) {
    this.addSectionOfType(event.currentTarget.dataset.type);
  }

  deleteSectionFromList(event) {
    event.stopPropagation();
    const key = event.currentTarget.dataset.key;
    this.handleSectionDeleteFromCanvas({ detail: { key } });
  }

  moveSectionUp(event) {
    event.stopPropagation();
    this._moveSectionInList(event.currentTarget.dataset.key, -1);
  }

  moveSectionDown(event) {
    event.stopPropagation();
    this._moveSectionInList(event.currentTarget.dataset.key, 1);
  }

  _moveSectionInList(key, direction) {
    const sections = [...this.template.sections];
    const idx = sections.findIndex((s) => s.localKey === key);
    const target = idx + direction;
    if (idx < 0 || target < 0 || target >= sections.length) return;
    [sections[idx], sections[target]] = [sections[target], sections[idx]];
    this.template = { ...this.template, sections: this._resequence(sections) };
    this.markDirty();
  }

  stopPropagation(event) { event.stopPropagation(); }

  // ── Text section: editor mode + field insertion ───────────────────────────

  handleSectionEditorModeChange(event) {
    this.updateSelectedSection({ textEditorMode: event.detail.value });
  }

  async handleTextSectionRelChange(event) {
    this.textSectionSelectedRelName = event.detail.value;
    if (this.textSectionSelectedRelName) {
      const rel = this.parentRelationships.find(r => r.relationshipName === this.textSectionSelectedRelName);
      if (rel?.referenceTo) {
        this.textSectionRelatedFields = await getFieldsForObject({ objectApiName: rel.referenceTo }) || [];
      }
    } else {
      this.textSectionRelatedFields = [];
    }
  }

  insertParentFieldIntoSection(event) {
    if (!event.detail.value) return;
    const token = `{{Parent.${event.detail.value}}}`;
    this.updateSelectedSection({ staticContent: `${this.selectedSection?.staticContent || ""}${token}` });
  }

  insertRelatedFieldIntoSection(event) {
    if (!event.detail.value || !this.textSectionSelectedRelName) return;
    const token = `{{${this.textSectionSelectedRelName}.${event.detail.value}}}`;
    this.updateSelectedSection({ staticContent: `${this.selectedSection?.staticContent || ""}${token}` });
  }

  // ── Field delete from dceBuilderQueryConfig ───────────────────────────────

  handleQueryFieldDelete(event) {
    const { fieldId } = event.detail;
    if (fieldId && !this.deletedFieldIds.includes(fieldId)) {
      this.deletedFieldIds = [...this.deletedFieldIds, fieldId];
    }
  }

  // ── Query Builder ─────────────────────────────────────────────────────────

  async handleQbEditObject(event) {
    const id = event.currentTarget.dataset.id;
    const obj = this.queryBuilderObjects.find(o => o.id === id);
    if (!obj) return;
    this.qbEditingObjectId = id;
    this.qbModalTempSelected = [...obj.fields];
    this.qbModalSearch = "";
    this.qbModalAllFields = [];
    this.showQbFieldModal = true;
    const fields = await getFieldsForObject({ objectApiName: obj.objectApiName });
    this.qbModalAllFields = fields || [];
  }

  handleQbModalSearch(event) {
    this.qbModalSearch = event.detail.value;
  }

  toggleQbModalField(event) {
    const apiName = event.target.dataset.apiname;
    const label = event.target.dataset.label;
    const checked = event.target.checked;
    const obj = this.qbEditingObject;
    const prefix = obj?.tagPrefix || obj?.objectApiName || "Parent";
    if (checked) {
      this.qbModalTempSelected = [...this.qbModalTempSelected, {
        apiName,
        label,
        tag: `{{${prefix}.${apiName}}}`
      }];
    } else {
      this.qbModalTempSelected = this.qbModalTempSelected.filter(f => f.apiName !== apiName);
    }
  }

  handleQbModalSave() {
    const idx = this.queryBuilderObjects.findIndex(o => o.id === this.qbEditingObjectId);
    if (idx >= 0) {
      const updated = [...this.queryBuilderObjects];
      updated[idx] = { ...updated[idx], fields: this.qbModalTempSelected };
      this.queryBuilderObjects = updated;
    }
    this._closeQbModal();
  }

  handleQbModalCancel() {
    this._closeQbModal();
  }

  _closeQbModal() {
    this.showQbFieldModal = false;
    this.qbEditingObjectId = null;
    this.qbModalTempSelected = [];
    this.qbModalAllFields = [];
    this.qbModalSearch = "";
  }

  async handleQbAddRelatedObject(event) {
    const objectApiName = event.detail.value;
    if (!objectApiName) return;
    const rel = this.parentRelationships.find(r => r.referenceTo === objectApiName);
    if (!rel) return;
    const id = `qbobj_${Date.now()}`;
    const newObj = {
      id,
      objectApiName,
      label: rel.label || rel.relationshipName,
      isParent: false,
      tagPrefix: rel.relationshipName,
      fields: []
    };
    this.queryBuilderObjects = [...this.queryBuilderObjects, newObj];
    this.qbEditingObjectId = id;
    this.qbModalTempSelected = [];
    this.qbModalSearch = "";
    this.qbModalAllFields = [];
    this.showQbFieldModal = true;
    const fields = await getFieldsForObject({ objectApiName });
    this.qbModalAllFields = fields || [];
  }

  handleQbRemoveObject(event) {
    event.stopPropagation();
    const id = event.currentTarget.dataset.id;
    this.queryBuilderObjects = this.queryBuilderObjects.filter(o => o.id !== id);
  }

  copyMergeTag(event) {
    const tag = event.currentTarget.dataset.tag;
    try {
      const el = document.createElement("textarea");
      el.value = tag;
      el.style.position = "fixed";
      el.style.opacity = "0";
      document.body.appendChild(el);
      el.select();
      document.execCommand("copy");
      document.body.removeChild(el);
      this.showToast("Copied", `${tag} copied to clipboard`, "success");
    } catch (_e) {
      this.showToast("Tag", tag, "info");
    }
  }

  insertTagIntoSection(event) {
    if (!event.detail.value) return;
    this.updateSelectedSection({ staticContent: `${this.selectedSection?.staticContent || ""}${event.detail.value}` });
  }

  // ── Columns section ───────────────────────────────────────────────────────

  handleColumnsAdd(event) {
    const cols = parseInt(event.currentTarget.dataset.columns, 10) || 2;
    this.addColumnsSection(cols);
  }

  addColumnsSection(columnCount) {
    const order = this.template.sections.length + 1;
    const columns = [];
    for (let i = 0; i < columnCount; i++) {
      columns.push({ localKey: this.nextKey("col"), colIndex: i + 1, content: "" });
    }
    const section = {
      localKey: this.nextKey("section"),
      name: `Section ${order}`,
      sectionName: `Section ${order}`,
      sectionKey: `Section${order}`,
      active: true,
      displayOrder: order,
      sectionType: "Columns",
      columnCount,
      columns,
      lines: [],
      fields: []
    };
    this.template = { ...this.template, sections: [...this.template.sections, section] };
    this.selectedSectionKey = section.localKey;
    this.markDirty();
  }

  handleColumnCountChange(event) {
    const count = parseInt(event.detail.value, 10);
    const existing = this.selectedSection?.columns || [];
    const columns = [];
    for (let i = 0; i < count; i++) {
      columns.push(existing[i] || { localKey: this.nextKey("col"), colIndex: i + 1, content: "" });
    }
    this.updateSelectedSection({ columnCount: count, columns });
  }

  handleColumnContentChange(event) {
    const colKey = event.target.dataset.colKey;
    const content = event.detail.value;
    const columns = (this.selectedSection.columns || []).map(col =>
      col.localKey === colKey ? { ...col, content } : col
    );
    this.updateSelectedSection({ columns });
  }

  // ── Lines ─────────────────────────────────────────────────────────────────

  addLine() {
    const order = (this.selectedSection?.lines || []).length + 1;
    const line = {
      localKey: this.nextKey("line"),
      name: `Line ${order}`,
      displayOrder: order,
      active: true,
      lineTemplate: "",
      displayStyle: "Normal",
      renderOnlyIfNotBlank: false
    };
    this.updateSelectedSection({ lines: [...(this.selectedSection.lines || []), line] });
    this.selectedLineKey = line.localKey;
    this.selectedFieldKey = null;
    this.decorateSelectedLineItems();
  }

  selectLine(event) {
    this.selectedLineKey = event.currentTarget.dataset.key;
    this.selectedFieldKey = null;
    this.decorateSelectedLineItems();
  }

  handleLineChange(event) {
    const key = event.target.dataset.key || this.selectedLineKey;
    const name = event.target.name;
    const value = event.target.type === "checkbox" ? event.target.checked : event.detail.value;
    const lines = (this.selectedSection.lines || []).map((l) =>
      l.localKey === key ? { ...l, [name]: value } : l
    );
    this.updateSelectedSection({ lines });
  }

  insertChildFieldIntoLine(event) {
    if (!this.selectedLineKey) return;
    const token = `{{${event.detail.value}}}`;
    const lines = this.selectedSection.lines.map((l) =>
      l.localKey === this.selectedLineKey ? { ...l, lineTemplate: `${l.lineTemplate || ""}${token}` } : l
    );
    this.updateSelectedSection({ lines });
  }

  deleteLine(event) {
    event.stopPropagation();
    const key = event.currentTarget.dataset.key;
    const line = this.selectedSection.lines.find((l) => l.localKey === key);
    if (line?.id) this.deletedLineIds = [...this.deletedLineIds, line.id];
    this.updateSelectedSection({ lines: this.selectedSection.lines.filter((l) => l.localKey !== key) });
    this.selectedLineKey = null;
    this.decorateSelectedLineItems();
  }

  // ── Fields (Related columns) ───────────────────────────────────────────────

  addField() {
    const order = (this.selectedSection?.fields || []).length + 1;
    const field = {
      localKey: this.nextKey("field"),
      name: `Column ${order}`,
      displayOrder: order,
      active: true,
      showLabel: true,
      displayStyle: "Normal",
      renderOnlyIfNotBlank: true
    };
    this.updateSelectedSection({ fields: [...(this.selectedSection.fields || []), field] });
    this.selectedFieldKey = field.localKey;
    this.selectedLineKey = null;
    this.decorateSelectedLineItems();
  }

  selectField(event) {
    this.selectedFieldKey = event.currentTarget.dataset.key;
    this.selectedLineKey = null;
    this.decorateSelectedLineItems();
  }

  handleFieldChange(event) {
    const key = event.target.dataset.key || this.selectedFieldKey;
    const name = event.target.name;
    const value = event.target.type === "checkbox" ? event.target.checked : event.detail.value;
    const selectedField = this.childFields.find((f) => f.apiName === value);
    const fields = (this.selectedSection.fields || []).map((f) =>
      f.localKey === key
        ? { ...f, [name]: value, fieldLabel: name === "fieldApiName" ? selectedField?.label : f.fieldLabel }
        : f
    );
    this.updateSelectedSection({ fields });
  }

  deleteField(event) {
    event.stopPropagation();
    const key = event.currentTarget.dataset.key;
    const field = this.selectedSection.fields.find((f) => f.localKey === key);
    if (field?.id) this.deletedFieldIds = [...this.deletedFieldIds, field.id];
    this.updateSelectedSection({ fields: this.selectedSection.fields.filter((f) => f.localKey !== key) });
    this.selectedFieldKey = null;
    this.decorateSelectedLineItems();
  }

  // ── Recipients ────────────────────────────────────────────────────────────

  addRecipient() {
    const order = this.template.recipients.length + 1;
    const recipient = {
      localKey: this.nextKey("recipient"),
      name: `Recipient Rule ${order}`,
      active: true,
      displayOrder: order,
      recipientSourceType: "Manual",
      recipientType: "To",
      defaultSelected: false,
      allowMultiple: true,
      required: false
    };
    this.template = { ...this.template, recipients: [...this.template.recipients, recipient] };
    this.selectedRecipientKey = recipient.localKey;
    this.markDirty();
  }

  async selectRecipient(event) {
    this.selectedRecipientKey = event.currentTarget.dataset.key;
    await this.prepareRecipientMetadata();
  }

  async prepareRecipientMetadata() {
    const recipient = this.selectedRecipient;
    if (!recipient) return;
    const sourceObject = recipient.recipientSourceType === "Related Records"
      ? recipient.sourceObjectApiName
      : this.template.parentObjectApiName;
    if (sourceObject) {
      await this.loadFields(sourceObject, "recipient");
      if (recipient.recipientSourceType === "Related Records")
        await this.loadLookupFields(sourceObject, "recipient");
    }
  }

  async handleRecipientChange(event) {
    const name = event.target.name;
    const value = event.detail.value;
    const changes = { [name]: value };
    if (name === "sourceObjectApiName") {
      changes.sourceObjectLabel = this.objectLabel(value);
      changes.parentLookupFieldApiName = null;
      changes.nameFieldApiName = null;
      changes.emailFieldApiName = null;
    }
    this.updateSelectedRecipient(changes);
    if (name === "recipientSourceType" || name === "sourceObjectApiName")
      await this.prepareRecipientMetadata();
  }

  handleRecipientChecked(event) {
    this.updateSelectedRecipient({ [event.target.name]: event.target.checked });
  }

  deleteRecipient(event) {
    event.stopPropagation();
    const key = event.currentTarget.dataset.key;
    const recipient = this.template.recipients.find((r) => r.localKey === key);
    if (recipient?.id) this.deletedRecipientIds = [...this.deletedRecipientIds, recipient.id];
    this.template = {
      ...this.template,
      recipients: this.template.recipients.filter((r) => r.localKey !== key)
    };
    this.selectedRecipientKey = this.template.recipients[0]?.localKey;
    this.markDirty();
  }

  handleRecipientFilterChange(event) {
    this.recipientFilterDraft = { ...this.recipientFilterDraft, [event.target.name]: event.detail.value };
  }

  addRecipientFilterCondition() {
    const condition = this.buildFilterCondition(this.recipientFilterDraft);
    if (!condition) return;
    const existing = this.selectedRecipient?.filterLogic;
    this.updateSelectedRecipient({ filterLogic: existing ? `${existing} AND ${condition}` : condition });
    this.recipientFilterDraft = this.newFilterDraft();
  }

  clearRecipientFilter() { this.updateSelectedRecipient({ filterLogic: "" }); }

  // ── Post-send actions ─────────────────────────────────────────────────────

  addPostSendAction() {
    const order = (this.template.postSendActions || []).length + 1;
    const action = {
      id: this.nextKey("postSendActionId"),
      localKey: this.nextKey("postSendAction"),
      active: true,
      runOrder: order,
      actionType: "Update Field",
      valueType: "Static",
      value: "",
      assignedToType: "Current User",
      dueDateStrategy: "Email Sent Date + X Days",
      daysAfterSend: 0,
      status: "Not Started",
      priority: "Normal",
      expanded: true
    };
    this.template = { ...this.template, postSendActions: [...(this.template.postSendActions || []), action] };
    this.selectedActionKey = action.localKey;
    this.markDirty();
  }

  selectPostSendAction(event) {
    this.selectedActionKey = event.currentTarget.dataset.key;
  }

  handlePostSendActionChange(event) {
    const name = event.target.name;
    const value = event.detail.value;
    const changes = { [name]: value };
    if (name === "actionType") Object.assign(changes, this.defaultActionValues(value));
    if (name === "fieldApiName") {
      const field = this.updateableParentFields.find((f) => f.apiName === value);
      changes.fieldLabel = field?.label;
    }
    this.updateSelectedAction(changes);
  }

  handlePostSendActionChecked(event) {
    this.updateSelectedAction({ [event.target.name]: event.target.checked });
  }

  handleAssignedUserChange(event) {
    this.updateSelectedAction({ assignedUserId: event.detail.recordId });
  }

  insertPostSendActionMergeField(event) {
    if (!this.selectedActionKey || !event.detail.value) return;
    const token = `{{Parent.${event.detail.value}}}`;
    this.updateSelectedAction({ valueType: "Merge Field", value: `${this.selectedAction?.value || ""}${token}` });
  }

  deletePostSendAction(event) {
    event.stopPropagation();
    const key = event.currentTarget.dataset.key;
    const actions = (this.template.postSendActions || [])
      .filter((a) => a.localKey !== key)
      .map((a, i) => ({ ...a, runOrder: i + 1 }));
    this.template = { ...this.template, postSendActions: actions };
    this.selectedActionKey = actions[0]?.localKey;
    this.markDirty();
  }

  movePostSendActionUp(event) {
    event.stopPropagation();
    this.movePostSendAction(event.currentTarget.dataset.key, -1);
  }

  movePostSendActionDown(event) {
    event.stopPropagation();
    this.movePostSendAction(event.currentTarget.dataset.key, 1);
  }

  movePostSendAction(key, direction) {
    const actions = [...(this.template.postSendActions || [])];
    const index = actions.findIndex((a) => a.localKey === key);
    const target = index + direction;
    if (index < 0 || target < 0 || target >= actions.length) return;
    [actions[index], actions[target]] = [actions[target], actions[index]];
    this.template = {
      ...this.template,
      postSendActions: actions.map((a, i) => ({ ...a, runOrder: i + 1 }))
    };
    this.selectedActionKey = key;
    this.markDirty();
  }

  // ── Preview ───────────────────────────────────────────────────────────────

  handlePreviewRecordChange(event) { this.previewRecordId = event.detail.recordId; }

  async refreshPreview() {
    if (!this.template.id) { this.setError("Save the template before previewing."); return; }
    if (!this.previewRecordId) { this.setError("Select a preview record."); return; }
    this.isLoading = true;
    try {
      const rendered = await previewTemplate({ templateId: this.template.id, recordId: this.previewRecordId });
      this.previewSubject = rendered?.subject || "";
      this.previewBody = rendered?.htmlBody || "";
      this.clearError();
    } catch (error) { this.handleError(error, "Unable to refresh preview."); }
    finally { this.isLoading = false; }
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  async saveFinal() {
    const message = this.validateBeforeSave();
    if (message) { this.setError(message); this.showToast("Review needed", message, "error"); return; }
    this.isLoading = true;
    try {
      const saved = await saveTemplate({ templateDto: this.buildSavePayload() });
      this.template = this.normalizeTemplate(saved);
      this.selectedTemplateId = this.template.id;
      this.isEditMode = true;
      this.isDirty = false;
      this.clearDeletedIds();
      await this.loadTemplates();
      this.showToast("Saved", "Template saved successfully.", "success");
      this.clearError();
    } catch (error) { this.handleError(error, "Unable to save template."); }
    finally { this.isLoading = false; }
  }

  // ── Shared update helpers ─────────────────────────────────────────────────

  updateSelectedSection(changes) {
    const sections = this.template.sections.map((s) =>
      s.localKey === this.selectedSectionKey ? { ...s, ...changes } : s
    );
    this.template = { ...this.template, sections };
    this.markDirty();
  }

  updateSelectedRecipient(changes) {
    const recipients = this.template.recipients.map((r) =>
      r.localKey === this.selectedRecipientKey ? { ...r, ...changes } : r
    );
    this.template = { ...this.template, recipients };
    this.markDirty();
  }

  updateSelectedAction(changes) {
    const actions = (this.template.postSendActions || []).map((a) =>
      a.localKey === this.selectedActionKey ? { ...a, ...changes } : a
    );
    this.template = { ...this.template, postSendActions: actions };
    this.markDirty();
  }

  decorateSelectedLineItems() {
    if (!this.selectedSectionKey) return;
    const sections = this.template.sections.map((section) => {
      if (section.localKey !== this.selectedSectionKey) return section;
      return {
        ...section,
        lines: (section.lines || []).map((l) => ({ ...l, isSelected: l.localKey === this.selectedLineKey })),
        fields: (section.fields || []).map((f) => ({ ...f, isSelected: f.localKey === this.selectedFieldKey }))
      };
    });
    this.template = { ...this.template, sections };
  }

  defaultActionValues(actionType) {
    if (actionType === "Create Task") {
      return {
        subject: "Follow up with {{Parent.Name}}",
        assignedToType: "Current User",
        dueDateStrategy: "Email Sent Date + X Days",
        daysAfterSend: 0,
        status: "Not Started",
        priority: "Normal",
        comments: ""
      };
    }
    return { fieldApiName: "", fieldLabel: "", valueType: "Static", value: "" };
  }

  // ── Normalize / validate / build payload ──────────────────────────────────

  buildSavePayload() {
    const status = this.template.status || "Draft";
    return {
      ...this.template,
      active: status === "Active",
      archived: status === "Archive",
      deletedSectionIds: this.deletedSectionIds,
      deletedLineIds: this.deletedLineIds,
      deletedFieldIds: this.deletedFieldIds,
      deletedRecipientIds: this.deletedRecipientIds,
      deletedAttachmentIds: this.deletedAttachmentIds
    };
  }

  validateDetails() {
    if (!this.template.name?.trim()) return "Template name is required.";
    if (!this.template.parentObjectApiName) return "Parent object is required.";
    return null;
  }

  validateBeforeSave() {
    const detailsError = this.validateDetails();
    if (detailsError) return detailsError;
    if (!this.template.subjectTemplate?.trim()) return "Subject template is required.";
    if (!this.template.bodyTemplate?.trim()) return "Body template is required.";
    for (const [label, value] of [
      ["Header", this.template.headerContent],
      ["Body", this.template.bodyTemplate],
      ["Footer", this.template.footerContent]
    ]) {
      if (String(value || "").length > MAX_HTML_LIMIT)
        return `${label} HTML exceeds the supported limit of ${MAX_HTML_LIMIT.toLocaleString()} characters.`;
    }
    for (const section of this.template.sections || []) {
      if (!section.sectionKey?.trim()) return "Section key is required for every section.";
      if (!section.sectionType) return "Section type is required for every section.";
      if (section.sectionType === "Text" && !section.staticContent?.trim())
        return "Text sections require content.";
      if (
        (section.sectionType === "Text Block" || section.sectionType === "Related") &&
        !section.childObjectApiName
      ) return "Repeating sections require a child object.";
      if (
        (section.sectionType === "Text Block" || section.sectionType === "Related") &&
        !section.parentLookupFieldApiName
      ) return "Repeating sections require a parent lookup field.";
      if (section.sectionType === "Related" && !(section.fields || []).length)
        return "Related sections require at least one column.";
    }
    for (const recipient of this.template.recipients || []) {
      if (!recipient.recipientSourceType) return "Recipient source type is required.";
      if (!recipient.recipientType) return "Recipient type is required.";
      if (
        recipient.recipientSourceType === "Parent Field" &&
        (!recipient.nameFieldApiName || !recipient.emailFieldApiName)
      ) return "Parent Field recipients require name and email fields.";
      if (
        recipient.recipientSourceType === "Related Records" &&
        (!recipient.sourceObjectApiName || !recipient.parentLookupFieldApiName ||
          !recipient.nameFieldApiName || !recipient.emailFieldApiName)
      ) return "Related Record recipients require source object, lookup field, name field, and email field.";
    }
    for (const action of this.template.postSendActions || []) {
      if (!action.actionType) return "Post-send action type is required.";
      if (action.actionType === "Update Field" && (!action.fieldApiName || !action.valueType))
        return "Update Field actions require a field and value type.";
      if (action.actionType === "Create Task" && !action.subject?.trim())
        return "Create Task actions require a subject.";
      if (action.actionType === "Create Task" && action.assignedToType === "Specific User" && !action.assignedUserId)
        return "Specific User task assignment requires a user.";
    }
    return null;
  }

  normalizeTemplate(template) {
    const normalized = { ...this.newTemplate(), ...(template || {}) };
    if (!normalized.status) {
      normalized.status = normalized.active ? "Active" : normalized.archived ? "Archive" : "Draft";
    }
    normalized.headerContent = normalized.headerContent || "";
    normalized.footerContent = normalized.footerContent || "";
    normalized.sections = (normalized.sections || []).map((section) => ({
      ...section,
      // Migrate legacy types
      sectionType: section.sectionType === "Table" ? "Related" : section.sectionType === "Static Text" ? "Text" : section.sectionType,
      textEditorMode: section.textEditorMode || "Visual",
      localKey: section.localKey || section.id || this.nextKey("section"),
      lines: (section.lines || []).map((line) => ({
        ...line,
        localKey: line.localKey || line.id || this.nextKey("line")
      })),
      fields: (section.fields || []).map((field) => ({
        ...field,
        localKey: field.localKey || field.id || this.nextKey("field")
      }))
    }));
    normalized.recipients = (normalized.recipients || []).map((recipient) => ({
      ...recipient,
      localKey: recipient.localKey || recipient.id || this.nextKey("recipient")
    }));
    normalized.postSendActions = (normalized.postSendActions || []).map((action, index) => ({
      ...this.defaultActionValues(action.actionType || "Update Field"),
      ...action,
      id: action.id || this.nextKey("postSendActionId"),
      localKey: action.localKey || action.id || this.nextKey("postSendAction"),
      runOrder: action.runOrder || index + 1,
      active: action.active !== false,
      expanded: action.expanded === true
    }));
    normalized.attachments = (normalized.attachments || []).map((att) => ({
      ...att,
      localKey: att.localKey || att.id || this.nextKey("attachment"),
      active: att.active !== false,
      maxAttachments: att.maxAttachments != null ? att.maxAttachments : 5
    }));
    return normalized;
  }

  newTemplate() {
    return {
      name: "",
      apiName: "",
      status: "Draft",
      parentObjectApiName: "",
      subjectTemplate: "",
      bodyTemplate: "",
      headerContent: "",
      footerContent: "",
      headerEditorMode: "Visual",
      bodyEditorMode: "Visual",
      footerEditorMode: "Visual",
      description: "",
      allowUserEditBeforeSend: true,
      storeEmailHistory: true,
      sections: [],
      recipients: [],
      postSendActions: [],
      attachments: []
    };
  }

  _emptyTemplateDraft() {
    return {
      name: "",
      apiName: "",
      description: "",
      parentObjectApiName: "",
      defaultFromEmail: "",
      storeEmailHistory: true,
      allowUserEditBeforeSend: true
    };
  }

  // ── Utility helpers ───────────────────────────────────────────────────────

  toFieldOptions(fields) {
    return (fields || []).map((f) => ({ label: this.fieldLabel(f), value: f.apiName }));
  }

  contentLength(fieldName) { return String(this.template?.[fieldName] || "").length; }

  characterCountLabel(fieldName) {
    return `${this.contentLength(fieldName).toLocaleString()} / ${MAX_HTML_LIMIT.toLocaleString()} characters`;
  }

  characterCountClass(fieldName) {
    return this.contentLength(fieldName) > MAX_HTML_LIMIT
      ? "character-count character-count_error"
      : "character-count";
  }

  fieldLabel(field) {
    return this.advanced ? `${field.label} (${field.apiName})` : field.label;
  }

  objectLabel(apiName) {
    return this.objects.find((o) => o.apiName === apiName)?.label || apiName;
  }

  toKey(value) { return (value || "Section").replace(/[^A-Za-z0-9]/g, ""); }

  nextKey(prefix) {
    this.localCounter += 1;
    return `${prefix}-${Date.now()}-${this.localCounter}`;
  }

  newFilterDraft() { return { field: "", operator: "=", value: "" }; }

  buildFilterCondition(draft) {
    if (!draft?.field || !draft?.operator) {
      this.setError("Choose a field and operator before adding a filter.");
      return null;
    }
    if (draft.operator === "BLANK") return `${draft.field} = null`;
    if (draft.operator === "NOT_BLANK") return `${draft.field} != null`;
    if (draft.value === undefined || draft.value === null || String(draft.value).trim() === "") {
      this.setError("Enter a value for this filter.");
      return null;
    }
    const value = String(draft.value).trim();
    const lower = value.toLowerCase();
    const literal =
      lower === "true" || lower === "false" || lower === "null" || !Number.isNaN(Number(value))
        ? value
        : `'${value.replace(/'/g, "\\'")}'`;
    this.clearError();
    return `${draft.field} ${draft.operator} ${literal}`;
  }

  // ── Attachments ───────────────────────────────────────────────────────────

  addAttachment() {
    const att = {
      id: null,
      localKey: this.nextKey("attachment"),
      active: true,
      displayOrder: (this.template.attachments || []).length + 1,
      attachmentSource: "Static File",
      staticContentDocumentId: "",
      linkedQueryId: null,
      linkedQueryName: null,
      fileTitleFilter: "",
      maxAttachments: 5
    };
    this.template = { ...this.template, attachments: [...(this.template.attachments || []), att] };
    this.selectedAttachmentKey = att.localKey;
    this.markDirty();
  }

  selectAttachment(event) {
    this.selectedAttachmentKey = event.currentTarget.dataset.key;
  }

  deleteAttachment(event) {
    event.stopPropagation();
    const key = event.currentTarget.dataset.key;
    const att = (this.template.attachments || []).find((a) => a.localKey === key);
    if (att?.id) this.deletedAttachmentIds = [...this.deletedAttachmentIds, att.id];
    const remaining = (this.template.attachments || []).filter((a) => a.localKey !== key);
    this.template = { ...this.template, attachments: remaining };
    this.selectedAttachmentKey = remaining[0]?.localKey;
    this.markDirty();
  }

  handleAttachmentChange(event) {
    const { name, value } = event.target;
    this.template = {
      ...this.template,
      attachments: (this.template.attachments || []).map((a) =>
        a.localKey === this.selectedAttachmentKey ? { ...a, [name]: value } : a
      )
    };
    this.markDirty();
  }

  handleAttachmentChecked(event) {
    const { name, checked } = event.target;
    this.template = {
      ...this.template,
      attachments: (this.template.attachments || []).map((a) =>
        a.localKey === this.selectedAttachmentKey ? { ...a, [name]: checked } : a
      )
    };
    this.markDirty();
  }

  clearDeletedIds() {
    this.deletedSectionIds = [];
    this.deletedLineIds = [];
    this.deletedFieldIds = [];
    this.deletedRecipientIds = [];
    this.deletedAttachmentIds = [];
  }

  markDirty() { this.isDirty = true; }
  setError(message) { this.errorMessage = message; }
  clearError() { this.errorMessage = ""; }

  handleError(error, fallback) {
    const message = error?.body?.message || error?.message || fallback;
    this.setError(message);
    this.showToast("Error", message, "error");
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
