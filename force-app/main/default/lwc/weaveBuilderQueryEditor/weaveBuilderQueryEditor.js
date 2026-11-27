import { LightningElement, api, track } from 'lwc';
import getFieldsForObject from '@salesforce/apex/WeaveTemplateBuilderController.getFieldsForObject';
import getLookupFieldsForChildObject from '@salesforce/apex/WeaveTemplateBuilderController.getLookupFieldsForChildObject';
import getRelationshipFields from '@salesforce/apex/WeaveTemplateBuilderController.getRelationshipFields';

const SORT_DIRECTION_OPTIONS = [
  { label: 'Ascending', value: 'ASC' },
  { label: 'Descending', value: 'DESC' }
];

// Lookup relationships to skip — they're redundant or noise in the field picker
// Note: Owner, CreatedBy, LastModifiedBy are intentionally included so users can traverse them
const SYSTEM_RELATIONSHIP_NAMES = new Set([
  'RecordType', 'Master', 'UserRole', 'Profile', 'Currency'
]);

const FILTER_OPERATOR_OPTIONS = [
  { label: 'equals (=)', value: '=' },
  { label: 'not equals (!=)', value: '!=' },
  { label: 'less than (<)', value: '<' },
  { label: 'less than or equal (<=)', value: '<=' },
  { label: 'greater than (>)', value: '>' },
  { label: 'greater than or equal (>=)', value: '>=' },
  { label: 'LIKE', value: 'LIKE' },
  { label: 'IN', value: 'IN' },
  { label: 'NOT IN', value: 'NOT IN' },
  { label: 'IS NULL', value: 'IS NULL' },
  { label: 'IS NOT NULL', value: 'IS NOT NULL' },
];

const FILTER_CONNECTOR_OPTIONS = [
  { label: 'AND', value: 'AND' },
  { label: 'OR', value: 'OR' },
];

const NULL_OPS = new Set(['IS NULL', 'IS NOT NULL']);

let _sortRowSeq = 0;
let _filterRowSeq = 0;

export default class WeaveBuilderQueryEditor extends LightningElement {
  @api relatedObjectOptions = [];
  @api relatedObjectMeta = {};
  @api parentObjectApiName;
  @api parentQueryOptions = [];

  @track _query = {};
  @track _loadedObjectApiName = null;
  @track availableFields = [];
  @track relatedFieldGroups = [];
  @track parentLookupFieldOptions = [];
  @track fieldSearchTerm = '';
  @track sortRows = [];
  @track queryLimit = 50;
  @track filterClause = '';
  @track filterRows = [];
  @track isLoadingFields = false;

  sortDirectionOptions = SORT_DIRECTION_OPTIONS;
  filterOperatorOptions = FILTER_OPERATOR_OPTIONS;
  filterConnectorOptions = FILTER_CONNECTOR_OPTIONS;

  @api
  get query() { return this._query; }
  set query(value) {
    const newQuery = value ? { ...value } : {};
    this._query = newQuery;
    if (newQuery.soqlObject && newQuery.soqlObject !== this._loadedObjectApiName) {
      this._loadedObjectApiName = newQuery.soqlObject;
      this.loadFields(newQuery.soqlObject, this.getSelectedFieldsFromSoql());
    }
    this.parseSoqlForSelections();
  }

  get hasObject() { return !!this._query.soqlObject; }

  get hasParentQueryOptions() {
    return Array.isArray(this.parentQueryOptions) && this.parentQueryOptions.length > 1;
  }

  get sortFieldOptions() {
    const none = [{ label: '-- None --', value: '' }];
    return none.concat(this.availableFields.filter(f => f.isSortable).map(f => ({ label: f.label, value: f.apiName })));
  }

  // All selected fields — direct + relationship
  get selectedFields() {
    const direct = this.availableFields.filter(f => f.isSelected);
    const rel = this.relatedFieldGroups.flatMap(g => g.fields.filter(f => f.isSelected));
    return [...direct, ...rel];
  }

  get unselectedFilteredFields() {
    const term = (this.fieldSearchTerm || '').toLowerCase();
    return this.availableFields.filter(f => {
      if (f.isSelected) return false;
      if (!term) return true;
      return f.label.toLowerCase().includes(term) || f.apiName.toLowerCase().includes(term);
    });
  }

  // Relationship groups filtered by search term, only showing unselected fields
  get filteredRelatedFieldGroups() {
    const term = (this.fieldSearchTerm || '').toLowerCase();
    return this.relatedFieldGroups.map(g => ({
      ...g,
      visibleFields: g.fields.filter(f => {
        if (f.isSelected) return false;
        if (!term) return true;
        return f.label.toLowerCase().includes(term) || f.apiName.toLowerCase().includes(term);
      })
    })).filter(g => g.visibleFields.length > 0);
  }

  get hasSelectedFields() { return this.selectedFields.length > 0; }
  get hasUnselectedFields() { return this.unselectedFilteredFields.length > 0; }
  get hasRelatedFieldGroups() { return this.filteredRelatedFieldGroups.length > 0; }
  get hasFilterRows() { return this.filterRows.length > 0; }

  get filterFieldOptions() {
    const opts = this.availableFields.map(f => ({
      label: f.label + ' (' + f.apiName + ')',
      value: f.apiName
    }));
    this.relatedFieldGroups.forEach(g => {
      g.fields.forEach(f => {
        opts.push({ label: g.groupLabel + ': ' + f.label, value: f.apiName });
      });
    });
    return opts;
  }

  get filterRowsDisplay() {
    return this.filterRows.map((r, i) => ({
      ...r,
      isFirst: i === 0,
      isNullOp: NULL_OPS.has(r.operator)
    }));
  }

  get filterWhereClause() {
    if (this.filterRows.length > 0) {
      return this.filterRows
        .filter(r => r.field && r.operator)
        .map((r, i) => {
          const prefix = i === 0 ? '' : (r.connector || 'AND') + ' ';
          if (NULL_OPS.has(r.operator)) return prefix + r.field + ' ' + r.operator;
          return prefix + r.field + ' ' + r.operator + ' ' + r.value;
        })
        .join(' ');
    }
    return this.filterClause ? this.filterClause.trim() : '';
  }

  get generatedSoql() {
    const selectedFields = this.selectedFields.map(f => f.apiName);
    if (!this._query.soqlObject || selectedFields.length === 0) return '';
    let soql = `SELECT ${selectedFields.join(', ')} FROM ${this._query.soqlObject}`;
    const where = this.filterWhereClause;
    if (where) soql += ` WHERE ${where}`;
    const activeSortRows = (this.sortRows || []).filter(r => r.field);
    if (activeSortRows.length > 0) {
      soql += ' ORDER BY ' + activeSortRows.map(r => `${r.field} ${r.dir}`).join(', ');
    }
    if (this.queryLimit) soql += ` LIMIT ${this.queryLimit}`;
    return soql;
  }

  loadFields(objectApiName, initialSelectedFields) {
    this.isLoadingFields = true;
    const selectedSet = new Set(initialSelectedFields || []);
    const defaultIdOnly = selectedSet.size === 0;

    getFieldsForObject({ objectApiName })
      .then(fields => {
        this.availableFields = fields.map(f => ({
          ...f,
          isSelected: defaultIdOnly ? f.apiName === 'Id' : selectedSet.has(f.apiName)
        }));
        this.loadParentLookupFields(objectApiName);
        this.loadRelationshipFieldGroups(objectApiName, selectedSet);
        this.emitChange();
      })
      .catch(() => { this.availableFields = []; })
      .finally(() => { this.isLoadingFields = false; });
  }

  loadRelationshipFieldGroups(objectApiName, selectedSet) {
    this.relatedFieldGroups = [];
    getRelationshipFields({ objectApiName })
      .then(lookupFields => {
        const toLoad = (lookupFields || []).filter(f =>
          f.referenceTo && f.referenceTo.length === 1 &&
          f.relationshipName &&
          !SYSTEM_RELATIONSHIP_NAMES.has(f.relationshipName)
        );
        const promises = toLoad.map(f =>
          getFieldsForObject({ objectApiName: f.referenceTo[0] })
            .then(relFields => ({
              groupLabel: f.label.replace(/ ID$/i, '').replace(/ Id$/i, ''),
              relationshipName: f.relationshipName,
              expanded: false,
              fields: relFields
                .filter(rf => rf.apiName !== 'Id')
                .map(rf => ({
                  apiName: f.relationshipName + '.' + rf.apiName,
                  label: rf.label,
                  isSelected: selectedSet ? selectedSet.has(f.relationshipName + '.' + rf.apiName) : false,
                  isId: false
                }))
            }))
            .catch(() => null)
        );
        return Promise.all(promises);
      })
      .then(groups => {
        this.relatedFieldGroups = (groups || []).filter(g => g && g.fields.length > 0);
      })
      .catch(() => { this.relatedFieldGroups = []; });
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

    if (childObjectApiName === this.parentObjectApiName) {
      this.parentLookupFieldOptions = [{ label: 'Id (implicit parent context)', value: 'Id' }];
      if (!this._query.parentLookupField) {
        this._query = { ...this._query, parentLookupField: 'Id', relationshipType: 'self' };
      }
      return;
    }

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
    // Parse multi-column ORDER BY
    this.sortRows = [];
    const orderByMatch = soql.match(/ORDER BY\s+(.+?)(?:\s+LIMIT|$)/i);
    if (orderByMatch) {
      this.sortRows = orderByMatch[1].trim().split(',').map(clause => {
        const parts = clause.trim().split(/\s+/);
        return { id: ++_sortRowSeq, field: parts[0] || '', dir: (parts[1] || 'ASC').toUpperCase() };
      }).filter(r => r.field);
    }
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
    this.relatedFieldGroups = [];
    this.fieldSearchTerm = '';
    this.sortRows = [];
    this.filterRows = [];
    this.filterClause = '';
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
    if (fieldApiName === 'Id') return;
    // Check direct fields first
    const inDirect = this.availableFields.some(f => f.apiName === fieldApiName);
    if (inDirect) {
      this.availableFields = this.availableFields.map(f =>
        f.apiName === fieldApiName ? { ...f, isSelected: false } : f
      );
    } else {
      // Relationship field deselect
      this.relatedFieldGroups = this.relatedFieldGroups.map(g => ({
        ...g,
        fields: g.fields.map(f => f.apiName === fieldApiName ? { ...f, isSelected: false } : f)
      }));
    }
    this.emitChange();
  }

  handleRelFieldSelect(event) {
    const fieldApiName = event.currentTarget.dataset.field;
    const relName = event.currentTarget.dataset.rel;
    this.relatedFieldGroups = this.relatedFieldGroups.map(g =>
      g.relationshipName === relName
        ? { ...g, fields: g.fields.map(f => f.apiName === fieldApiName ? { ...f, isSelected: true } : f) }
        : g
    );
    this.emitChange();
  }

  handleToggleRelGroup(event) {
    const relName = event.currentTarget.dataset.rel;
    this.relatedFieldGroups = this.relatedFieldGroups.map(g =>
      g.relationshipName === relName ? { ...g, expanded: !g.expanded } : g
    );
  }

  handleSearchChange(event) {
    this.fieldSearchTerm = event.target.value;
  }

  handleFilterChange(event) {
    this.filterClause = event.target.value;
    this.emitChange();
  }

  handleFilterRowAdd() {
    this.filterRows = [...this.filterRows, { id: ++_filterRowSeq, connector: 'AND', field: '', operator: '=', value: '' }];
  }

  handleFilterRowRemove(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    this.filterRows = this.filterRows.filter(r => r.id !== idx);
    this.emitChange();
  }

  handleFilterRowFieldChange(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    this.filterRows = this.filterRows.map(r => r.id === idx ? { ...r, field: event.detail.value } : r);
    this.emitChange();
  }

  handleFilterRowOperatorChange(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    this.filterRows = this.filterRows.map(r => r.id === idx ? { ...r, operator: event.detail.value } : r);
    this.emitChange();
  }

  handleFilterRowValueChange(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    this.filterRows = this.filterRows.map(r => r.id === idx ? { ...r, value: event.target.value } : r);
    this.emitChange();
  }

  handleFilterRowConnectorChange(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    this.filterRows = this.filterRows.map(r => r.id === idx ? { ...r, connector: event.detail.value } : r);
    this.emitChange();
  }

  handleSortRowFieldChange(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    this.sortRows = this.sortRows.map(r => r.id === idx ? { ...r, field: event.detail.value } : r);
    this.emitChange();
  }

  handleSortRowDirChange(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    this.sortRows = this.sortRows.map(r => r.id === idx ? { ...r, dir: event.detail.value } : r);
    this.emitChange();
  }

  handleSortRowRemove(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10);
    this.sortRows = this.sortRows.filter(r => r.id !== idx);
    this.emitChange();
  }

  handleSortRowAdd() {
    this.sortRows = [...this.sortRows, { id: ++_sortRowSeq, field: '', dir: 'ASC' }];
  }

  handleLimitChange(event) {
    this.queryLimit = parseInt(event.detail.value, 10) || 50;
    this.emitChange();
  }

  handleParentLookupChange(event) {
    this._query = { ...this._query, parentLookupField: event.detail.value };
    this.emitChange();
  }

  handleParentQuerySelectorChange(event) {
    this._query = { ...this._query, parentQueryLocalKey: event.detail.value || null };
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
