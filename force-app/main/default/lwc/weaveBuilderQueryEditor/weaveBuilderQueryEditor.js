import { LightningElement, api, track } from 'lwc';
import getFieldsForObject from '@salesforce/apex/WeaveTemplateBuilderController.getFieldsForObject';
import getLookupFieldsForChildObject from '@salesforce/apex/WeaveTemplateBuilderController.getLookupFieldsForChildObject';

const SORT_DIRECTION_OPTIONS = [
  { label: 'Ascending', value: 'ASC' },
  { label: 'Descending', value: 'DESC' }
];

export default class WeaveBuilderQueryEditor extends LightningElement {
  @api relatedObjectOptions = [];
  @api relatedObjectMeta = {};
  @api parentObjectApiName;

  @track _query = {};
  @track _loadedObjectApiName = null;
  @track availableFields = [];
  @track parentLookupFieldOptions = [];
  @track fieldSearchTerm = '';
  @track sortField = '';
  @track sortDirection = 'ASC';
  @track queryLimit = 50;
  @track filterClause = '';
  @track isLoadingFields = false;

  sortDirectionOptions = SORT_DIRECTION_OPTIONS;

  @api
  get query() { return this._query; }
  set query(value) {
    const newQuery = value ? { ...value } : {};
    const prevObject = this._query ? this._query.soqlObject : null;
    this._query = newQuery;
    // Only reload fields when the object actually changes — avoids infinite loop
    if (newQuery.soqlObject && newQuery.soqlObject !== this._loadedObjectApiName) {
      this._loadedObjectApiName = newQuery.soqlObject;
      this.loadFields(newQuery.soqlObject, this.getSelectedFieldsFromSoql());
    }
    this.parseSoqlForSelections();
  }

  get hasObject() { return !!this._query.soqlObject; }

  get sortFieldOptions() {
    const none = [{ label: '-- None --', value: '' }];
    return none.concat(this.availableFields.filter(f => f.isSortable).map(f => ({ label: f.label, value: f.apiName })));
  }

  get selectedFields() {
    return this.availableFields.filter(f => f.isSelected);
  }

  get unselectedFilteredFields() {
    const term = (this.fieldSearchTerm || '').toLowerCase();
    return this.availableFields.filter(f => {
      if (f.isSelected) return false;
      if (!term) return true;
      return f.label.toLowerCase().includes(term) || f.apiName.toLowerCase().includes(term);
    });
  }

  get hasSelectedFields() { return this.selectedFields.length > 0; }
  get hasUnselectedFields() { return this.unselectedFilteredFields.length > 0; }

  get generatedSoql() {
    const selectedFields = this.availableFields.filter(f => f.isSelected).map(f => f.apiName);
    if (!this._query.soqlObject || selectedFields.length === 0) return '';
    let soql = `SELECT ${selectedFields.join(', ')} FROM ${this._query.soqlObject}`;
    if (this.filterClause && this.filterClause.trim()) soql += ` WHERE ${this.filterClause.trim()}`;
    if (this.sortField) soql += ` ORDER BY ${this.sortField} ${this.sortDirection}`;
    if (this.queryLimit) soql += ` LIMIT ${this.queryLimit}`;
    return soql;
  }

  loadFields(objectApiName, initialSelectedFields) {
    this.isLoadingFields = true;
    const selectedSet = new Set(initialSelectedFields || []);
    // If no prior selection, default to Id only
    const defaultIdOnly = selectedSet.size === 0;

    getFieldsForObject({ objectApiName })
      .then(fields => {
        this.availableFields = fields.map(f => ({
          ...f,
          isSelected: defaultIdOnly ? f.apiName === 'Id' : selectedSet.has(f.apiName)
        }));
        this.loadParentLookupFields(objectApiName);
        this.emitChange();
      })
      .catch(() => { this.availableFields = []; })
      .finally(() => { this.isLoadingFields = false; });
  }

  get _relType() {
    if (this._query.relationshipType) return this._query.relationshipType;
    const meta = this.relatedObjectMeta || {};
    return (this._query.soqlObject && meta[this._query.soqlObject]) ? meta[this._query.soqlObject].type : 'down';
  }

  get isUpRelationship() { return this._relType === 'up'; }
  get isDownRelationship() { return this._relType !== 'up'; }

  loadParentLookupFields(childObjectApiName) {
    if (!this.parentObjectApiName || !childObjectApiName) return;

    // 1-level-up: connector field lives on the PARENT — auto-set, no call needed
    const meta = this.relatedObjectMeta || {};
    const objMeta = meta[childObjectApiName];
    if (objMeta && objMeta.type === 'up') {
      this.parentLookupFieldOptions = [{ label: objMeta.connectorField + ' (on ' + this.parentObjectApiName + ')', value: objMeta.connectorField }];
      if (!this._query.parentLookupField) {
        this._query = { ...this._query, parentLookupField: objMeta.connectorField, relationshipType: 'up' };
        this.emitChange();
      }
      return;
    }

    // Self (parent queried directly)
    if (childObjectApiName === this.parentObjectApiName) {
      this.parentLookupFieldOptions = [{ label: 'Id (implicit parent context)', value: 'Id' }];
      if (!this._query.parentLookupField) {
        this._query = { ...this._query, parentLookupField: 'Id', relationshipType: 'self' };
      }
      return;
    }

    // 1-level-down: lookup field on the child object
    getLookupFieldsForChildObject({ childObjectApiName, parentObjectApiName: this.parentObjectApiName })
      .then(fields => {
        this.parentLookupFieldOptions = fields.map(f => ({ label: f.label + ' (' + f.apiName + ')', value: f.apiName }));
        if (!this._query.parentLookupField && fields.length === 1) {
          this._query = { ...this._query, parentLookupField: fields[0].apiName, relationshipType: 'down' };
          this.emitChange();
        }
      })
      .catch(() => { this.parentLookupFieldOptions = []; });
  }

  getSelectedFieldsFromSoql() {
    const soql = this._query.soqlQuery || '';
    const match = soql.match(/SELECT\s+(.+?)\s+FROM/i);
    if (!match) return [];
    return match[1].split(',').map(f => f.trim());
  }

  parseSoqlForSelections() {
    const soql = this._query.soqlQuery || '';
    const sortMatch = soql.match(/ORDER BY\s+(\w+)\s+(ASC|DESC)/i);
    if (sortMatch) { this.sortField = sortMatch[1]; this.sortDirection = sortMatch[2].toUpperCase(); }
    const limitMatch = soql.match(/LIMIT\s+(\d+)/i);
    if (limitMatch) this.queryLimit = parseInt(limitMatch[1], 10);
    const whereMatch = soql.match(/WHERE\s+(.+?)(?:\s+ORDER BY|\s+LIMIT|$)/i);
    this.filterClause = whereMatch ? whereMatch[1].trim() : '';
  }

  handleObjectChange(event) {
    const objectApiName = event.detail.value;
    const meta = this.relatedObjectMeta || {};
    const objMeta = meta[objectApiName] || {};
    this._loadedObjectApiName = objectApiName;
    this._query = {
      ...this._query,
      soqlObject: objectApiName,
      parentLookupField: '',
      relationshipType: objMeta.type || 'down'
    };
    this.availableFields = [];
    this.fieldSearchTerm = '';
    this.sortField = '';
    this.loadFields(objectApiName, []);
  }

  handleFieldSelect(event) {
    const fieldApiName = event.currentTarget.dataset.field;
    this.availableFields = this.availableFields.map(f =>
      f.apiName === fieldApiName ? { ...f, isSelected: true } : f
    );
    this.emitChange();
  }

  handleFieldDeselect(event) {
    const fieldApiName = event.currentTarget.dataset.field;
    if (fieldApiName === 'Id') return; // Id cannot be deselected
    this.availableFields = this.availableFields.map(f =>
      f.apiName === fieldApiName ? { ...f, isSelected: false } : f
    );
    this.emitChange();
  }

  handleSearchChange(event) {
    this.fieldSearchTerm = event.target.value;
  }

  handleFilterChange(event) {
    this.filterClause = event.target.value;
    this.emitChange();
  }

  handleSortFieldChange(event) {
    this.sortField = event.detail.value;
    this.emitChange();
  }

  handleSortDirectionChange(event) {
    this.sortDirection = event.detail.value;
    this.emitChange();
  }

  handleLimitChange(event) {
    this.queryLimit = parseInt(event.detail.value, 10) || 50;
    this.emitChange();
  }

  handleParentLookupChange(event) {
    this._query = { ...this._query, parentLookupField: event.detail.value };
    this.emitChange();
  }

  emitChange() {
    this.dispatchEvent(new CustomEvent('querychange', {
      detail: {
        ...this._query,
        soqlQuery: this.generatedSoql
      }
    }));
  }
}
