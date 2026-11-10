import { LightningElement, api, track } from "lwc";
import getAvailableObjects from "@salesforce/apex/DceTemplateBuilderController.getAvailableObjects";
import getOrgWideEmailAddresses from "@salesforce/apex/DceTemplateBuilderController.getOrgWideEmailAddresses";
import getTemplates from "@salesforce/apex/DceTemplateBuilderController.getTemplates";
import getFieldsForObject from "@salesforce/apex/DceTemplateBuilderController.getFieldsForObject";
import getUpdateableFieldsForObject from "@salesforce/apex/DceTemplateBuilderController.getUpdateableFieldsForObject";
import getLookupFieldsForChildObject from "@salesforce/apex/DceTemplateBuilderController.getLookupFieldsForChildObject";
import loadTemplate from "@salesforce/apex/DceTemplateBuilderController.loadTemplate";
import saveTemplate from "@salesforce/apex/DceTemplateBuilderController.saveTemplate";
import deleteTemplate from "@salesforce/apex/DceTemplateBuilderController.deleteTemplate";
import previewTemplate from "@salesforce/apex/DceTemplateBuilderController.previewTemplate";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";

const STEPS = [
  "library",
  "details",
  "sections",
  "lines",
  "body",
  "recipients",
  "postSendActions",
  "preview"
];
const INLINE_HTML_LIMIT = 131072;
const MAX_HTML_LIMIT = 1000000;
const DISPLAY_STYLES = [
  "Normal",
  "Bold",
  "Italic",
  "Currency",
  "Percent",
  "Date",
  "DateTime",
  "Number"
];
const LINE_STYLES = ["Normal", "Bold", "Italic"];
const STARTER_HEADER = "<p>{{Organization.Name}}</p>";
const STARTER_FOOTER =
  "<br/>\n" +
  "<p>\n" +
  "Best regards,<br/>\n" +
  "{{Sender.FirstName}} {{Sender.LastName}}<br/>\n" +
  "{{Sender.Email}}<br/>\n" +
  "{{Sender.Phone}}\n" +
  "</p>";

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

  @track currentStep = "library";
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
  @track sectionFilterDraft = this.newFilterDraft();
  @track recipientFilterDraft = this.newFilterDraft();

  localCounter = 0;

  async connectedCallback() {
    await Promise.all([
      this.loadObjects(),
      this.loadTemplates(),
      this.loadOrgWideEmailOptions()
    ]);
    if (this.recordId) {
      await this.openTemplateById(this.recordId, "details");
    }
  }

  get stepItems() {
    return [
      { label: "Template Library", value: "library" },
      { label: "Template Details", value: "details" },
      { label: "Add Sections", value: "sections" },
      { label: "Section Lines", value: "lines" },
      { label: "Email Body", value: "body" },
      { label: "Recipients", value: "recipients" },
      { label: "Post-Send Actions", value: "postSendActions" },
      { label: "Preview & Save", value: "preview" }
    ];
  }

  get isLibraryStep() {
    return this.currentStep === "library";
  }
  get isDetailsStep() {
    return this.currentStep === "details";
  }
  get isSectionsStep() {
    return this.currentStep === "sections";
  }
  get isLinesStep() {
    return this.currentStep === "lines";
  }
  get isBodyStep() {
    return this.currentStep === "body";
  }
  get isRecipientsStep() {
    return this.currentStep === "recipients";
  }
  get isPostSendActionsStep() {
    return this.currentStep === "postSendActions";
  }
  get isPreviewStep() {
    return this.currentStep === "preview";
  }
  get isFirstStep() {
    return this.currentStep === "library";
  }
  get isLastStep() {
    return this.currentStep === "preview";
  }
  get showWizardChrome() {
    return !this.isLibraryStep;
  }
  get title() {
    return this.isEditMode
      ? `Editing: ${this.template.name || "Communication Template"}`
      : "New Communication Template";
  }
  get detailContinueLabel() {
    return this.isEditMode ? "Update & Continue" : "Create & Continue";
  }
  get hasTemplates() {
    return this.filteredTemplates.length > 0;
  }
  get hasSections() {
    return (this.template.sections || []).length > 0;
  }
  get hasLineSections() {
    return this.lineSectionOptions.length > 0;
  }
  get hasRecipients() {
    return (this.template.recipients || []).length > 0;
  }
  get previewDisabled() {
    return !this.template.id || !this.previewRecordId;
  }
  get activeLabel() {
    return this.template.active ? "Active" : "Draft";
  }
  get showStarterHeaderButton() {
    return !String(this.template.headerContent || "").trim();
  }
  get showStarterFooterButton() {
    return !String(this.template.footerContent || "").trim();
  }
  get editorModeOptions() {
    return [
      { label: "Visual", value: "Visual" },
      { label: "HTML Source", value: "HTML Source" }
    ];
  }
  get isHeaderVisualMode() {
    return this.template.headerEditorMode !== "HTML Source";
  }
  get isBodyVisualMode() {
    return this.template.bodyEditorMode !== "HTML Source";
  }
  get isFooterVisualMode() {
    return this.template.footerEditorMode !== "HTML Source";
  }
  get headerUsesOverflow() {
    return this.contentLength("headerContent") > INLINE_HTML_LIMIT;
  }
  get bodyUsesOverflow() {
    return this.contentLength("bodyTemplate") > INLINE_HTML_LIMIT;
  }
  get footerUsesOverflow() {
    return this.contentLength("footerContent") > INLINE_HTML_LIMIT;
  }
  get headerCharacterCount() {
    return this.characterCountLabel("headerContent");
  }
  get bodyCharacterCount() {
    return this.characterCountLabel("bodyTemplate");
  }
  get footerCharacterCount() {
    return this.characterCountLabel("footerContent");
  }
  get headerCountClass() {
    return this.characterCountClass("headerContent");
  }
  get bodyCountClass() {
    return this.characterCountClass("bodyTemplate");
  }
  get footerCountClass() {
    return this.characterCountClass("footerContent");
  }

  get filteredTemplates() {
    const term = (this.searchTerm || "").toLowerCase();
    return (this.templates || []).filter((item) => {
      if (!term) return true;
      return `${item.name || ""} ${item.parentObjectLabel || ""} ${item.description || ""}`
        .toLowerCase()
        .includes(term);
    });
  }

  get objectOptions() {
    return this.objects.map((item) => ({
      label: item.label,
      value: item.apiName
    }));
  }

  get parentFieldOptions() {
    return this.toFieldOptions(this.parentFields);
  }

  get headerFooterFieldOptions() {
    return [
      ...UNIVERSAL_MERGE_FIELDS,
      ...this.parentFieldOptions.map((field) => ({
        ...field,
        label: `Record · ${field.label}`,
        value: `Parent.${field.value}`
      }))
    ];
  }

  get updateableParentFieldOptions() {
    return this.toFieldOptions(this.updateableParentFields);
  }

  get childFieldOptions() {
    return this.toFieldOptions(this.childFields);
  }

  get lookupFieldOptions() {
    return this.lookupFields.map((field) => ({
      label: this.fieldLabel(field),
      value: field.apiName
    }));
  }

  get recipientFieldOptions() {
    return this.toFieldOptions(this.recipientFields);
  }

  get recipientLookupFieldOptions() {
    return this.recipientLookupFields.map((field) => ({
      label: this.fieldLabel(field),
      value: field.apiName
    }));
  }

  get sectionOptions() {
    return (this.template.sections || []).map((section) => ({
      label: section.sectionName || "Untitled Section",
      value: section.localKey
    }));
  }

  get lineSectionOptions() {
    return (this.template.sections || [])
      .filter(
        (section) =>
          section.sectionType === "Text Block" ||
          section.sectionType === "Table"
      )
      .map((section) => ({
        label: `${section.sectionName || "Section"} (${section.sectionType})`,
        value: section.localKey
      }));
  }

  get sectionTokenOptions() {
    return (this.template.sections || [])
      .filter((section) => section.sectionKey)
      .map((section) => ({
        label: section.sectionName || section.sectionKey,
        value: section.sectionKey
      }));
  }

  get selectedSection() {
    return (this.template.sections || []).find(
      (section) => section.localKey === this.selectedSectionKey
    );
  }

  get selectedLine() {
    return (this.selectedSection?.lines || []).find(
      (line) => line.localKey === this.selectedLineKey
    );
  }

  get selectedField() {
    return (this.selectedSection?.fields || []).find(
      (field) => field.localKey === this.selectedFieldKey
    );
  }

  get selectedRecipient() {
    return (this.template.recipients || []).find(
      (recipient) => recipient.localKey === this.selectedRecipientKey
    );
  }

  get selectedAction() {
    return (this.template.postSendActions || []).find(
      (action) => action.localKey === this.selectedActionKey
    );
  }

  get isSelectedStaticSection() {
    return this.selectedSection?.sectionType === "Static Text";
  }

  get isSelectedRepeatingSection() {
    return (
      this.selectedSection?.sectionType === "Text Block" ||
      this.selectedSection?.sectionType === "Table"
    );
  }

  get isSelectedTextBlockSection() {
    return this.selectedSection?.sectionType === "Text Block";
  }

  get isSelectedTableSection() {
    return this.selectedSection?.sectionType === "Table";
  }

  get selectedSectionIsTextBlock() {
    return this.selectedSection?.sectionType === "Text Block";
  }

  get selectedSectionIsTable() {
    return this.selectedSection?.sectionType === "Table";
  }

  get isParentRecipient() {
    return this.selectedRecipient?.recipientSourceType === "Parent Field";
  }

  get isRelatedRecipient() {
    return this.selectedRecipient?.recipientSourceType === "Related Records";
  }

  get isManualRecipient() {
    return this.selectedRecipient?.recipientSourceType === "Manual";
  }

  get isSelectedUpdateFieldAction() {
    return this.selectedAction?.actionType === "Update Field";
  }

  get isSelectedCreateTaskAction() {
    return this.selectedAction?.actionType === "Create Task";
  }

  get isSelectedSpecificUserTask() {
    return this.selectedAction?.assignedToType === "Specific User";
  }

  get sectionTypeOptions() {
    return [
      { label: "Static Text", value: "Static Text" },
      { label: "Text Block", value: "Text Block" },
      { label: "Table", value: "Table" }
    ];
  }

  get sortDirectionOptions() {
    return [
      { label: "Ascending", value: "ASC" },
      { label: "Descending", value: "DESC" }
    ];
  }

  get lineDisplayStyleOptions() {
    return LINE_STYLES.map((style) => ({ label: style, value: style }));
  }

  get displayStyleOptions() {
    return DISPLAY_STYLES.map((style) => ({ label: style, value: style }));
  }

  get recipientSourceOptions() {
    return [
      { label: "Parent Field", value: "Parent Field" },
      { label: "Related Records", value: "Related Records" },
      { label: "Manual", value: "Manual" }
    ];
  }

  get recipientTypeOptions() {
    return [
      { label: "To", value: "To" },
      { label: "CC", value: "CC" },
      { label: "BCC", value: "BCC" }
    ];
  }

  get postSendActionTypeOptions() {
    return [
      { label: "Update Field", value: "Update Field" },
      { label: "Create Task", value: "Create Task" }
    ];
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
    return [
      { label: "Email Sent Date + X Days", value: "Email Sent Date + X Days" }
    ];
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
    return [
      { label: "High", value: "High" },
      { label: "Normal", value: "Normal" },
      { label: "Low", value: "Low" }
    ];
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

  async loadObjects() {
    try {
      this.objects = await getAvailableObjects();
    } catch (error) {
      this.handleError(error, "Unable to load objects.");
    }
  }

  async loadOrgWideEmailOptions() {
    try {
      const addresses = await getOrgWideEmailAddresses();
      this.orgWideEmailOptions = [
        { label: "Use current user's default email", value: "" },
        ...(addresses || []).map((item) => ({
          label:
            item.label ||
            `${item.displayName || item.address} <${item.address}>`,
          value: item.address
        }))
      ];
    } catch (error) {
      this.handleError(error, "Unable to load org-wide email addresses.");
    }
  }

  async loadTemplates() {
    this.isLoading = true;
    try {
      const rows = await getTemplates();
      this.templates = (rows || []).map((item) => ({
        ...item,
        statusLabel: item.active ? "Active" : "Draft",
        lastModifiedDisplay: item.lastModifiedDate
          ? new Date(item.lastModifiedDate).toLocaleString()
          : ""
      }));
    } catch (error) {
      this.handleError(error, "Unable to load templates.");
    } finally {
      this.isLoading = false;
    }
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
    this.updateableParentFields = await getUpdateableFieldsForObject({
      objectApiName
    });
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

  async openTemplate(event) {
    await this.openTemplateById(event.currentTarget.dataset.id, "details");
  }

  async openTemplateById(templateId, targetStep = "details") {
    if (
      this.isDirty &&
      !(await LightningConfirm.open({
        message: "You have unsaved changes. Continue and discard them?",
        label: "Discard unsaved changes?",
        theme: "warning"
      }))
    )
      return;
    this.isLoading = true;
    try {
      const loaded = await loadTemplate({ templateId });
      this.template = this.normalizeTemplate(loaded);
      this.selectedTemplateId = this.template.id;
      this.isEditMode = true;
      this.isDirty = false;
      this.clearDeletedIds();
      this.currentStep = targetStep;
      this.selectedSectionKey = this.template.sections[0]?.localKey;
      this.selectedRecipientKey = this.template.recipients[0]?.localKey;
      this.selectedActionKey = this.template.postSendActions[0]?.localKey;
      this.previewSubject = "";
      this.previewBody = "";
      if (this.template.parentObjectApiName) {
        await this.loadFields(this.template.parentObjectApiName);
        await this.loadUpdateableParentFields(
          this.template.parentObjectApiName
        );
      }
      if (this.selectedSection?.childObjectApiName) {
        await this.loadFields(this.selectedSection.childObjectApiName, "child");
        await this.loadLookupFields(this.selectedSection.childObjectApiName);
      }
      this.clearError();
    } catch (error) {
      this.handleError(error, "Unable to open template.");
    } finally {
      this.isLoading = false;
    }
  }

  async deleteTemplateFromLibrary(event) {
    const templateId = event.currentTarget.dataset.id;
    if (
      !(await LightningConfirm.open({
        message:
          "Delete this template and its configuration records? This cannot be undone.",
        label: "Delete template?",
        theme: "warning"
      }))
    )
      return;
    this.isLoading = true;
    try {
      await deleteTemplate({ templateId });
      if (this.selectedTemplateId === templateId) await this.startNewTemplate();
      await this.loadTemplates();
      this.showToast("Deleted", "Template deleted.", "success");
    } catch (error) {
      this.handleError(error, "Unable to delete template.");
    } finally {
      this.isLoading = false;
    }
  }

  async startNewTemplate() {
    if (
      this.isDirty &&
      !(await LightningConfirm.open({
        message: "You have unsaved changes. Continue and discard them?",
        label: "Discard unsaved changes?",
        theme: "warning"
      }))
    )
      return;
    this.template = this.normalizeTemplate(this.newTemplate());
    this.selectedTemplateId = null;
    this.isEditMode = false;
    this.isDirty = false;
    this.clearDeletedIds();
    this.selectedSectionKey = null;
    this.selectedLineKey = null;
    this.selectedFieldKey = null;
    this.selectedRecipientKey = null;
    this.selectedActionKey = null;
    this.previewRecordId = null;
    this.previewSubject = "";
    this.previewBody = "";
    this.currentStep = "details";
    this.clearError();
  }

  goToStep(event) {
    this.currentStep = event.currentTarget.value;
    this.prepareStep();
  }

  handleBack() {
    const index = STEPS.indexOf(this.currentStep);
    if (index > 0) {
      this.currentStep = STEPS[index - 1];
      this.prepareStep();
    }
  }

  handleNext() {
    if (this.currentStep === "details") {
      const message = this.validateDetails();
      if (message) {
        this.setError(message);
        return;
      }
    }
    const index = STEPS.indexOf(this.currentStep);
    if (index < STEPS.length - 1) {
      this.currentStep = STEPS[index + 1];
      this.prepareStep();
    }
  }

  async prepareStep() {
    if (
      this.currentStep === "sections" &&
      this.selectedSection?.childObjectApiName
    ) {
      await this.loadFields(this.selectedSection.childObjectApiName, "child");
      await this.loadLookupFields(this.selectedSection.childObjectApiName);
    }
    if (
      this.currentStep === "lines" &&
      !this.selectedSectionKey &&
      this.lineSectionOptions.length
    ) {
      this.selectedSectionKey = this.lineSectionOptions[0].value;
      if (this.selectedSection?.childObjectApiName)
        await this.loadFields(this.selectedSection.childObjectApiName, "child");
    }
    if (this.currentStep === "recipients" && this.selectedRecipient) {
      await this.prepareRecipientMetadata();
    }
    if (
      this.currentStep === "postSendActions" &&
      this.template.parentObjectApiName &&
      !this.updateableParentFields.length
    ) {
      await this.loadUpdateableParentFields(this.template.parentObjectApiName);
    }
  }

  handleSearch(event) {
    this.searchTerm = event.detail.value;
  }

  toggleAdvanced(event) {
    this.advanced = event.target.checked;
  }

  handleTemplateChange(event) {
    const name = event.target.name;
    const value = event.detail?.value ?? event.target.value ?? "";
    this.updateTemplate({ [name]: value });
  }

  handleTemplateChecked(event) {
    this.updateTemplate({ [event.target.name]: event.target.checked });
  }

  insertStarterHeader() {
    this.updateTemplate({ headerContent: STARTER_HEADER });
  }

  insertStarterFooter() {
    this.updateTemplate({ footerContent: STARTER_FOOTER });
  }

  insertHeaderField(event) {
    this.insertRegionField("headerContent", event.detail.value);
  }

  insertFooterField(event) {
    this.insertRegionField("footerContent", event.detail.value);
  }

  insertRegionField(regionName, fieldPath) {
    if (!fieldPath) return;
    const token = fieldPath.startsWith("Parent.")
      ? `{{${fieldPath}}}`
      : `{{${fieldPath}}}`;
    this.updateTemplate({
      [regionName]: `${this.template[regionName] || ""}${token}`
    });
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

  addSection() {
    const order = this.template.sections.length + 1;
    const section = {
      localKey: this.nextKey("section"),
      name: `Section ${order}`,
      sectionName: `Section ${order}`,
      sectionKey: `Section${order}`,
      active: true,
      displayOrder: order,
      sectionType: "Static Text",
      staticContent: "",
      sortDirection: "ASC",
      repeatLabel: "Option",
      includeAutoNumber: false,
      autoNumberStart: 1,
      lines: [],
      fields: []
    };
    this.template = {
      ...this.template,
      sections: [...this.template.sections, section]
    };
    this.selectedSectionKey = section.localKey;
    this.markDirty();
  }

  selectSection(event) {
    this.selectedSectionKey =
      event.currentTarget.dataset.key || event.detail.value;
    this.selectedLineKey = null;
    this.selectedFieldKey = null;
    this.prepareStep();
  }

  async handleSectionChange(event) {
    const name = event.target.name;
    const value = event.detail.value;
    const changes = { [name]: value };
    if (name === "sectionName") changes.sectionKey = this.toKey(value);
    if (name === "childObjectApiName") {
      changes.childObjectLabel = this.objectLabel(value);
      changes.parentLookupFieldApiName = null;
      changes.sortFieldApiName = null;
    }
    this.updateSelectedSection(changes);
    if (name === "childObjectApiName") {
      await this.loadFields(value, "child");
      await this.loadLookupFields(value);
    }
  }

  handleSectionChecked(event) {
    this.updateSelectedSection({ [event.target.name]: event.target.checked });
  }

  deleteSection(event) {
    const key = event.currentTarget.dataset.key;
    const section = this.template.sections.find(
      (item) => item.localKey === key
    );
    if (section?.id)
      this.deletedSectionIds = [...this.deletedSectionIds, section.id];
    (section?.lines || []).forEach((line) => {
      if (line.id) this.deletedLineIds = [...this.deletedLineIds, line.id];
    });
    (section?.fields || []).forEach((field) => {
      if (field.id) this.deletedFieldIds = [...this.deletedFieldIds, field.id];
    });
    this.template = {
      ...this.template,
      sections: this.template.sections.filter((item) => item.localKey !== key)
    };
    this.selectedSectionKey = this.template.sections[0]?.localKey;
    this.markDirty();
  }

  handleSectionFilterChange(event) {
    this.sectionFilterDraft = {
      ...this.sectionFilterDraft,
      [event.target.name]: event.detail.value
    };
  }

  addSectionFilterCondition() {
    const condition = this.buildFilterCondition(this.sectionFilterDraft);
    if (!condition) return;
    const existing = this.selectedSection?.filterLogic;
    this.updateSelectedSection({
      filterLogic: existing ? `${existing} AND ${condition}` : condition
    });
    this.sectionFilterDraft = this.newFilterDraft();
  }

  clearSectionFilter() {
    this.updateSelectedSection({ filterLogic: "" });
  }

  handleLineSectionChange(event) {
    this.selectedSectionKey = event.detail.value;
    this.selectedLineKey = null;
    this.selectedFieldKey = null;
    this.decorateSelectedLineItems();
    if (this.selectedSection?.childObjectApiName)
      this.loadFields(this.selectedSection.childObjectApiName, "child");
  }

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
    this.updateSelectedSection({
      lines: [...(this.selectedSection.lines || []), line]
    });
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
    const value =
      event.target.type === "checkbox"
        ? event.target.checked
        : event.detail.value;
    const lines = (this.selectedSection.lines || []).map((line) => {
      return line.localKey === key ? { ...line, [name]: value } : line;
    });
    this.updateSelectedSection({ lines });
  }

  insertChildFieldIntoLine(event) {
    if (!this.selectedLineKey) return;
    const token = `{{${event.detail.value}}}`;
    const lines = this.selectedSection.lines.map((line) => {
      return line.localKey === this.selectedLineKey
        ? { ...line, lineTemplate: `${line.lineTemplate || ""}${token}` }
        : line;
    });
    this.updateSelectedSection({ lines });
  }

  deleteLine(event) {
    const key = event.currentTarget.dataset.key;
    const line = this.selectedSection.lines.find(
      (item) => item.localKey === key
    );
    if (line?.id) this.deletedLineIds = [...this.deletedLineIds, line.id];
    this.updateSelectedSection({
      lines: this.selectedSection.lines.filter((item) => item.localKey !== key)
    });
    this.selectedLineKey = null;
    this.decorateSelectedLineItems();
  }

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
    this.updateSelectedSection({
      fields: [...(this.selectedSection.fields || []), field]
    });
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
    const value =
      event.target.type === "checkbox"
        ? event.target.checked
        : event.detail.value;
    const selectedField = this.childFields.find(
      (field) => field.apiName === value
    );
    const fields = (this.selectedSection.fields || []).map((field) => {
      return field.localKey === key
        ? {
            ...field,
            [name]: value,
            fieldLabel:
              name === "fieldApiName" ? selectedField?.label : field.fieldLabel
          }
        : field;
    });
    this.updateSelectedSection({ fields });
  }

  deleteField(event) {
    const key = event.currentTarget.dataset.key;
    const field = this.selectedSection.fields.find(
      (item) => item.localKey === key
    );
    if (field?.id) this.deletedFieldIds = [...this.deletedFieldIds, field.id];
    this.updateSelectedSection({
      fields: this.selectedSection.fields.filter(
        (item) => item.localKey !== key
      )
    });
    this.selectedFieldKey = null;
    this.decorateSelectedLineItems();
  }

  insertSubjectField(event) {
    this.updateTemplate({
      subjectTemplate: `${this.template.subjectTemplate || ""}{{Parent.${event.detail.value}}}`
    });
  }

  insertBodyField(event) {
    this.updateTemplate({
      bodyTemplate: `${this.template.bodyTemplate || ""}{{Parent.${event.detail.value}}}`
    });
  }

  insertSectionToken(event) {
    this.updateTemplate({
      bodyTemplate: `${this.template.bodyTemplate || ""}{{Section.${event.detail.value}}}`
    });
  }

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
    this.template = {
      ...this.template,
      recipients: [...this.template.recipients, recipient]
    };
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
    const sourceObject =
      recipient.recipientSourceType === "Related Records"
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
    const key = event.currentTarget.dataset.key;
    const recipient = this.template.recipients.find(
      (item) => item.localKey === key
    );
    if (recipient?.id)
      this.deletedRecipientIds = [...this.deletedRecipientIds, recipient.id];
    this.template = {
      ...this.template,
      recipients: this.template.recipients.filter(
        (item) => item.localKey !== key
      )
    };
    this.selectedRecipientKey = this.template.recipients[0]?.localKey;
    this.markDirty();
  }

  handleRecipientFilterChange(event) {
    this.recipientFilterDraft = {
      ...this.recipientFilterDraft,
      [event.target.name]: event.detail.value
    };
  }

  addRecipientFilterCondition() {
    const condition = this.buildFilterCondition(this.recipientFilterDraft);
    if (!condition) return;
    const existing = this.selectedRecipient?.filterLogic;
    this.updateSelectedRecipient({
      filterLogic: existing ? `${existing} AND ${condition}` : condition
    });
    this.recipientFilterDraft = this.newFilterDraft();
  }

  clearRecipientFilter() {
    this.updateSelectedRecipient({ filterLogic: "" });
  }

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
    this.template = {
      ...this.template,
      postSendActions: [...(this.template.postSendActions || []), action]
    };
    this.selectedActionKey = action.localKey;
    this.markDirty();
  }

  selectPostSendAction(event) {
    this.selectedActionKey = event.currentTarget.dataset.key;
    this.template = {
      ...this.template,
      postSendActions: (this.template.postSendActions || []).map((action) => ({
        ...action,
        expanded:
          action.localKey === this.selectedActionKey
            ? !action.expanded
            : action.expanded
      }))
    };
  }

  handlePostSendActionChange(event) {
    const name = event.target.name;
    const value = event.detail.value;
    const changes = { [name]: value };
    if (name === "actionType") {
      Object.assign(changes, this.defaultActionValues(value));
    }
    if (name === "fieldApiName") {
      const field = this.updateableParentFields.find(
        (item) => item.apiName === value
      );
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
    this.updateSelectedAction({
      valueType: "Merge Field",
      value: `${this.selectedAction?.value || ""}${token}`
    });
  }

  deletePostSendAction(event) {
    event.stopPropagation();
    const key = event.currentTarget.dataset.key;
    const actions = (this.template.postSendActions || [])
      .filter((action) => action.localKey !== key)
      .map((action, index) => ({ ...action, runOrder: index + 1 }));
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
    const index = actions.findIndex((action) => action.localKey === key);
    const target = index + direction;
    if (index < 0 || target < 0 || target >= actions.length) return;
    [actions[index], actions[target]] = [actions[target], actions[index]];
    this.template = {
      ...this.template,
      postSendActions: actions.map((action, orderIndex) => ({
        ...action,
        runOrder: orderIndex + 1
      }))
    };
    this.selectedActionKey = key;
    this.markDirty();
  }

  updateSelectedAction(changes) {
    const actions = (this.template.postSendActions || []).map((action) => {
      return action.localKey === this.selectedActionKey
        ? { ...action, ...changes }
        : action;
    });
    this.template = { ...this.template, postSendActions: actions };
    this.markDirty();
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
    return {
      fieldApiName: "",
      fieldLabel: "",
      valueType: "Static",
      value: ""
    };
  }

  handlePreviewRecordChange(event) {
    this.previewRecordId = event.detail.recordId;
  }

  async refreshPreview() {
    if (!this.template.id) {
      this.setError("Save the template before previewing.");
      return;
    }
    if (!this.previewRecordId) {
      this.setError("Select a preview record.");
      return;
    }
    this.isLoading = true;
    try {
      const rendered = await previewTemplate({
        templateId: this.template.id,
        recordId: this.previewRecordId
      });
      this.previewSubject = rendered?.subject || "";
      this.previewBody = rendered?.htmlBody || "";
      this.clearError();
    } catch (error) {
      this.handleError(error, "Unable to refresh preview.");
    } finally {
      this.isLoading = false;
    }
  }

  async saveFinal() {
    const message = this.validateBeforeSave();
    if (message) {
      this.setError(message);
      this.showToast("Review needed", message, "error");
      return;
    }
    this.isLoading = true;
    try {
      const saved = await saveTemplate({
        templateDto: this.buildSavePayload()
      });
      this.template = this.normalizeTemplate(saved);
      this.selectedTemplateId = this.template.id;
      this.isEditMode = true;
      this.isDirty = false;
      this.clearDeletedIds();
      await this.loadTemplates();
      this.showToast("Saved", "Template saved successfully.", "success");
      this.clearError();
    } catch (error) {
      this.handleError(error, "Unable to save template.");
    } finally {
      this.isLoading = false;
    }
  }

  updateSelectedSection(changes) {
    const sections = this.template.sections.map((section) => {
      return section.localKey === this.selectedSectionKey
        ? { ...section, ...changes }
        : section;
    });
    this.template = { ...this.template, sections };
    this.markDirty();
  }

  updateSelectedRecipient(changes) {
    const recipients = this.template.recipients.map((recipient) => {
      return recipient.localKey === this.selectedRecipientKey
        ? { ...recipient, ...changes }
        : recipient;
    });
    this.template = { ...this.template, recipients };
    this.markDirty();
  }

  decorateSelectedLineItems() {
    if (!this.selectedSectionKey) return;
    const sections = this.template.sections.map((section) => {
      if (section.localKey !== this.selectedSectionKey) return section;
      return {
        ...section,
        lines: (section.lines || []).map((line) => ({
          ...line,
          isSelected: line.localKey === this.selectedLineKey
        })),
        fields: (section.fields || []).map((field) => ({
          ...field,
          isSelected: field.localKey === this.selectedFieldKey
        }))
      };
    });
    this.template = { ...this.template, sections };
  }

  buildSavePayload() {
    return {
      ...this.template,
      deletedSectionIds: this.deletedSectionIds,
      deletedLineIds: this.deletedLineIds,
      deletedFieldIds: this.deletedFieldIds,
      deletedRecipientIds: this.deletedRecipientIds
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
    if (!this.template.subjectTemplate?.trim())
      return "Subject template is required.";
    if (!this.template.bodyTemplate?.trim())
      return "Body template is required.";
    for (const [label, value] of [
      ["Header", this.template.headerContent],
      ["Body", this.template.bodyTemplate],
      ["Footer", this.template.footerContent]
    ]) {
      if (String(value || "").length > MAX_HTML_LIMIT) {
        return `${label} HTML exceeds the supported limit of ${MAX_HTML_LIMIT.toLocaleString()} characters.`;
      }
    }
    for (const section of this.template.sections || []) {
      if (!section.sectionKey?.trim())
        return "Section key is required for every section.";
      if (!section.sectionType)
        return "Section type is required for every section.";
      if (
        section.sectionType === "Static Text" &&
        !section.staticContent?.trim()
      )
        return "Static Text sections require static content.";
      if (
        (section.sectionType === "Text Block" ||
          section.sectionType === "Table") &&
        !section.childObjectApiName
      )
        return "Repeating sections require a child object.";
      if (
        (section.sectionType === "Text Block" ||
          section.sectionType === "Table") &&
        !section.parentLookupFieldApiName
      )
        return "Repeating sections require a parent lookup field.";
      if (section.sectionType === "Table" && !(section.fields || []).length)
        return "Table sections require at least one column.";
    }
    for (const recipient of this.template.recipients || []) {
      if (!recipient.recipientSourceType)
        return "Recipient source type is required.";
      if (!recipient.recipientType) return "Recipient type is required.";
      if (
        recipient.recipientSourceType === "Parent Field" &&
        (!recipient.nameFieldApiName || !recipient.emailFieldApiName)
      )
        return "Parent Field recipients require name and email fields.";
      if (
        recipient.recipientSourceType === "Related Records" &&
        (!recipient.sourceObjectApiName ||
          !recipient.parentLookupFieldApiName ||
          !recipient.nameFieldApiName ||
          !recipient.emailFieldApiName)
      )
        return "Related Record recipients require source object, lookup field, name field, and email field.";
    }
    for (const action of this.template.postSendActions || []) {
      if (!action.actionType) return "Post-send action type is required.";
      if (
        action.actionType === "Update Field" &&
        (!action.fieldApiName || !action.valueType)
      )
        return "Update Field actions require a field and value type.";
      if (action.actionType === "Create Task" && !action.subject?.trim())
        return "Create Task actions require a subject.";
      if (
        action.actionType === "Create Task" &&
        action.assignedToType === "Specific User" &&
        !action.assignedUserId
      )
        return "Specific User task assignment requires a user.";
    }
    return null;
  }

  normalizeTemplate(template) {
    const normalized = { ...this.newTemplate(), ...(template || {}) };
    normalized.headerContent = normalized.headerContent || "";
    normalized.footerContent = normalized.footerContent || "";
    normalized.sections = (normalized.sections || []).map((section) => ({
      ...section,
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
    normalized.postSendActions = (normalized.postSendActions || []).map(
      (action, index) => ({
        ...this.defaultActionValues(action.actionType || "Update Field"),
        ...action,
        id: action.id || this.nextKey("postSendActionId"),
        localKey:
          action.localKey || action.id || this.nextKey("postSendAction"),
        runOrder: action.runOrder || index + 1,
        active: action.active !== false,
        expanded: action.expanded === true
      })
    );
    return normalized;
  }

  newTemplate() {
    return {
      name: "",
      active: true,
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
      postSendActions: []
    };
  }

  toFieldOptions(fields) {
    return (fields || []).map((field) => ({
      label: this.fieldLabel(field),
      value: field.apiName
    }));
  }

  contentLength(fieldName) {
    return String(this.template?.[fieldName] || "").length;
  }

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
    return (
      this.objects.find((item) => item.apiName === apiName)?.label || apiName
    );
  }

  toKey(value) {
    return (value || "Section").replace(/[^A-Za-z0-9]/g, "");
  }

  nextKey(prefix) {
    this.localCounter += 1;
    return `${prefix}-${Date.now()}-${this.localCounter}`;
  }

  newFilterDraft() {
    return { field: "", operator: "=", value: "" };
  }

  buildFilterCondition(draft) {
    if (!draft?.field || !draft?.operator) {
      this.setError("Choose a field and operator before adding a filter.");
      return null;
    }
    if (draft.operator === "BLANK") return `${draft.field} = null`;
    if (draft.operator === "NOT_BLANK") return `${draft.field} != null`;
    if (
      draft.value === undefined ||
      draft.value === null ||
      String(draft.value).trim() === ""
    ) {
      this.setError("Enter a value for this filter.");
      return null;
    }
    const value = String(draft.value).trim();
    const lower = value.toLowerCase();
    const literal =
      lower === "true" ||
      lower === "false" ||
      lower === "null" ||
      !Number.isNaN(Number(value))
        ? value
        : `'${value.replace(/'/g, "\\'")}'`;
    this.clearError();
    return `${draft.field} ${draft.operator} ${literal}`;
  }

  clearDeletedIds() {
    this.deletedSectionIds = [];
    this.deletedLineIds = [];
    this.deletedFieldIds = [];
    this.deletedRecipientIds = [];
  }

  markDirty() {
    this.isDirty = true;
  }

  setError(message) {
    this.errorMessage = message;
  }

  clearError() {
    this.errorMessage = "";
  }

  handleError(error, fallback) {
    const message = error?.body?.message || error?.message || fallback;
    this.setError(message);
    this.showToast("Error", message, "error");
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
