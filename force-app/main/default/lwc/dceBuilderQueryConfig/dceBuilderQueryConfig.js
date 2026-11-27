import { LightningElement, api, track } from 'lwc';
import getFieldsForObject from '@salesforce/apex/DceTemplateBuilderController.getFieldsForObject';
import getRelationshipFields from '@salesforce/apex/DceTemplateBuilderController.getRelationshipFields';

export default class DceBuilderQueryConfig extends LightningElement {
  _section;
  _loadedForObject = '';

  @api get section() { return this._section; }
  set section(value) {
    this._section = value;
    const obj = value?.childObjectApiName;
    if (obj && obj !== this._loadedForObject) {
      this._loadedForObject = obj;
      this._loadFields(obj);
    }
  }

  @api objectOptions = [];
  @api lookupFieldOptions = [];
  @api filterOperatorOptions = [];
  @api sortDirectionOptions = [];
  @api isTextBlock = false;
  @api isRelated = false;

  @track filterDraft = { field: '', operator: '=', value: '' };
  @track fieldSearchTerm = '';
  @track allFields = [];
  @track relationships = [];
  @track expandedRelFields = {};

  get hasChildObject() { return !!this._section?.childObjectApiName; }

  get selectedFieldApiNames() {
    return new Set((this._section?.fields || []).map(f => f.fieldApiName));
  }

  get selectedFieldCount() { return this.selectedFieldApiNames.size; }

  get selectedFieldChips() {
    return (this._section?.fields || []).map(f => ({
      localKey: f.localKey,
      fieldApiName: f.fieldApiName,
      label: f.labelOverride || f.fieldLabel || f.fieldApiName
    }));
  }

  get childFieldOptions() {
    return this.allFields.map(f => ({ label: f.label, value: f.apiName }));
  }

  get visibleDirectFields() {
    const term = (this.fieldSearchTerm || '').toLowerCase();
    const selectedSet = this.selectedFieldApiNames;
    return this.allFields
      .filter(f => !term || f.label.toLowerCase().includes(term) || f.apiName.toLowerCase().includes(term))
      .map(f => ({ ...f, isSelected: selectedSet.has(f.apiName) }));
  }

  get visibleRelGroups() {
    const term = (this.fieldSearchTerm || '').toLowerCase();
    const selectedSet = this.selectedFieldApiNames;
    return this.relationships
      .filter(r => !term || r.label.toLowerCase().includes(term) || r.relationshipName.toLowerCase().includes(term))
      .map(r => {
        const expanded = this.expandedRelFields[r.relationshipName];
        const fields = (expanded?.fields || []).map(f => {
          const qn = `${r.relationshipName}.${f.apiName}`;
          return { ...f, qualifiedApiName: qn, isSelected: selectedSet.has(qn) };
        });
        return {
          ...r,
          isExpanded: !!expanded,
          fieldsLoaded: expanded?.loaded || false,
          fields,
          selectedCount: fields.filter(f => f.isSelected).length,
          toggleIcon: expanded ? '▾' : '▸'
        };
      });
  }

  get isBlankOperator() {
    const op = this.filterDraft.operator;
    return op === 'BLANK' || op === 'NOT_BLANK';
  }

  async _loadFields(objectApiName) {
    if (!objectApiName) return;
    try {
      const [fields, rels] = await Promise.all([
        getFieldsForObject({ objectApiName }),
        getRelationshipFields({ objectApiName })
      ]);
      this.allFields = fields || [];
      this.relationships = rels || [];
      this.expandedRelFields = {};
    } catch (e) {
      console.error('[QueryConfig] Field load error', e);
    }
  }

  handleChildObjectChange(event) {
    const childObjectApiName = event.detail.value;
    this._loadedForObject = '';
    this.allFields = [];
    this.relationships = [];
    this.expandedRelFields = {};
    this.dispatchEvent(new CustomEvent('childobjectchange', {
      bubbles: false,
      detail: { childObjectApiName }
    }));
  }

  handleFieldChange(event) {
    this.dispatchEvent(new CustomEvent('configchange', {
      bubbles: false,
      detail: { [event.target.name]: event.detail.value }
    }));
  }

  handleChecked(event) {
    this.dispatchEvent(new CustomEvent('configchange', {
      bubbles: false,
      detail: { [event.target.name]: event.target.checked }
    }));
  }

  handleFieldSearch(event) {
    this.fieldSearchTerm = event.detail.value;
  }

  async toggleRelGroup(event) {
    event.stopPropagation();
    const relName = event.currentTarget.dataset.rel;
    if (this.expandedRelFields[relName]) {
      const updated = { ...this.expandedRelFields };
      delete updated[relName];
      this.expandedRelFields = updated;
      return;
    }
    this.expandedRelFields = { ...this.expandedRelFields, [relName]: { fields: [], loaded: false } };
    const rel = this.relationships.find(r => r.relationshipName === relName);
    if (rel?.referenceTo) {
      try {
        const fields = await getFieldsForObject({ objectApiName: rel.referenceTo });
        if (this.expandedRelFields[relName]) {
          this.expandedRelFields = {
            ...this.expandedRelFields,
            [relName]: { fields: fields || [], loaded: true }
          };
        }
      } catch (e) {
        console.error('[QueryConfig] Rel field load error', e);
      }
    }
  }

  toggleField(event) {
    const apiName = event.currentTarget.dataset.apiName;
    const isChecked = event.target.checked;
    const currentFields = [...(this._section?.fields || [])];

    if (isChecked) {
      let fieldLabel;
      if (apiName.includes('.')) {
        const [relName, fieldApiName] = apiName.split('.');
        const rel = this.relationships.find(r => r.relationshipName === relName);
        const relField = this.expandedRelFields[relName]?.fields?.find(f => f.apiName === fieldApiName);
        fieldLabel = relField ? `${rel?.label || relName}: ${relField.label}` : apiName;
      } else {
        const f = this.allFields.find(f => f.apiName === apiName);
        fieldLabel = f?.label || apiName;
      }
      currentFields.push({
        localKey: `new_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
        fieldApiName: apiName,
        fieldLabel,
        labelOverride: null,
        displayStyle: 'Normal',
        tableColumnWidth: null,
        renderOnlyIfNotBlank: false,
        active: true,
        showLabel: true,
        displayOrder: currentFields.length + 1
      });
    } else {
      const idx = currentFields.findIndex(f => f.fieldApiName === apiName);
      if (idx >= 0) {
        const removed = currentFields[idx];
        if (removed?.id) {
          this.dispatchEvent(new CustomEvent('fielddelete', {
            bubbles: false,
            detail: { fieldId: removed.id }
          }));
        }
        currentFields.splice(idx, 1);
      }
    }

    this.dispatchEvent(new CustomEvent('configchange', {
      bubbles: false,
      detail: { fields: currentFields }
    }));
  }

  removeFieldChip(event) {
    event.stopPropagation();
    const localKey = event.currentTarget.dataset.localKey;
    const removedField = (this._section?.fields || []).find(f => f.localKey === localKey);
    if (removedField?.id) {
      this.dispatchEvent(new CustomEvent('fielddelete', {
        bubbles: false,
        detail: { fieldId: removedField.id }
      }));
    }
    const fields = (this._section?.fields || []).filter(f => f.localKey !== localKey);
    this.dispatchEvent(new CustomEvent('configchange', {
      bubbles: false,
      detail: { fields }
    }));
  }

  handleFilterDraftChange(event) {
    this.filterDraft = { ...this.filterDraft, [event.target.name]: event.detail.value };
  }

  addFilter() {
    const condition = this._buildCondition(this.filterDraft);
    if (!condition) return;
    const existing = this._section?.filterLogic;
    this.dispatchEvent(new CustomEvent('configchange', {
      bubbles: false,
      detail: { filterLogic: existing ? `${existing} AND ${condition}` : condition }
    }));
    this.filterDraft = { field: '', operator: '=', value: '' };
  }

  clearFilter() {
    this.dispatchEvent(new CustomEvent('configchange', {
      bubbles: false,
      detail: { filterLogic: '' }
    }));
  }

  _buildCondition(draft) {
    if (!draft?.field || !draft?.operator) return null;
    if (draft.operator === 'BLANK') return `${draft.field} = null`;
    if (draft.operator === 'NOT_BLANK') return `${draft.field} != null`;
    const raw = String(draft.value || '').trim();
    if (!raw) return null;
    const lower = raw.toLowerCase();
    const literal =
      lower === 'true' || lower === 'false' || lower === 'null' || !Number.isNaN(Number(raw))
        ? raw
        : `'${raw.replace(/'/g, "\\'")}'`;
    return `${draft.field} ${draft.operator} ${literal}`;
  }
}
