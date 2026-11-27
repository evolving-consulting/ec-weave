import { LightningElement, api, track } from 'lwc';

const OPERATORS_TEXT    = [
    { label: 'equals',         value: '='        },
    { label: 'not equals',     value: '!='       },
    { label: 'contains',       value: 'LIKE'     },
    { label: 'not contains',   value: 'NOT LIKE' },
];
const OPERATORS_NUMBER  = [
    { label: 'equals',         value: '='  },
    { label: 'not equals',     value: '!=' },
    { label: 'greater than',   value: '>'  },
    { label: 'greater or eq',  value: '>=' },
    { label: 'less than',      value: '<'  },
    { label: 'less or eq',     value: '<=' },
];
const OPERATORS_PICK    = [
    { label: 'equals',     value: '='    },
    { label: 'not equals', value: '!='   },
    { label: 'in',         value: 'IN'   },
    { label: 'not in',     value: 'NOT IN' },
];
const OPERATORS_BOOL    = [{ label: 'equals', value: '=' }];
const OPERATORS_DEFAULT = OPERATORS_TEXT;

const CONJUNCTION_OPTIONS = [
    { label: 'AND', value: 'AND' },
    { label: 'OR',  value: 'OR'  },
];

let _keyCounter = 0;
function nextKey() { return 'cond_' + (++_keyCounter); }

function operatorsForType(dataType) {
    if (!dataType) return OPERATORS_DEFAULT;
    const t = dataType.toUpperCase();
    if (['CURRENCY', 'DOUBLE', 'INTEGER', 'LONG', 'PERCENT'].includes(t)) return OPERATORS_NUMBER;
    if (['DATE', 'DATETIME'].includes(t)) return OPERATORS_NUMBER;
    if (['PICKLIST', 'MULTIPICKLIST'].includes(t)) return OPERATORS_PICK;
    if (t === 'BOOLEAN') return OPERATORS_BOOL;
    return OPERATORS_TEXT;
}

export default class WeaveBulkFilterBuilder extends LightningElement {

    @api
    get fields() { return this._fields; }
    set fields(val) {
        this._fields = val || [];
        this._fieldOptions = this._fields.map(f => ({ label: f.label, value: f.apiName }));
        this._fieldTypeMap  = {};
        this._fields.forEach(f => { this._fieldTypeMap[f.apiName] = f.dataType; });
        this._refreshOperators();
    }

    @track conditions = [];

    _fields = [];
    _fieldOptions = [];
    _fieldTypeMap = {};

    get fieldOptions()       { return this._fieldOptions; }
    get conjunctionOptions() { return CONJUNCTION_OPTIONS; }
    get hasConditions()      { return this.conditions.length > 0; }

    _refreshOperators() {
        this.conditions = this.conditions.map((c, i) => ({
            ...c,
            operatorOptions: operatorsForType(this._fieldTypeMap[c.field]),
            showConjunction: i < this.conditions.length - 1,
        }));
    }

    handleAddCondition() {
        const key = nextKey();
        const updated = [
            ...this.conditions.map((c, i) => ({ ...c, showConjunction: true })),
            { key, field: '', operator: '=', value: '', conjunction: 'AND',
              operatorOptions: OPERATORS_DEFAULT, showConjunction: false },
        ];
        this.conditions = updated;
        this._emit();
    }

    handleRemoveCondition(evt) {
        const key = evt.currentTarget.dataset.key;
        this.conditions = this.conditions
            .filter(c => c.key !== key)
            .map((c, i, arr) => ({ ...c, showConjunction: i < arr.length - 1 }));
        this._emit();
    }

    handleFieldChange(evt) {
        const key = evt.currentTarget.dataset.key;
        const field = evt.detail.value;
        const dataType = this._fieldTypeMap[field] || '';
        const ops = operatorsForType(dataType);
        this.conditions = this.conditions.map(c =>
            c.key === key ? { ...c, field, operatorOptions: ops, operator: ops[0].value } : c
        );
        this._emit();
    }

    handleOperatorChange(evt) {
        const key = evt.currentTarget.dataset.key;
        const operator = evt.detail.value;
        this.conditions = this.conditions.map(c => c.key === key ? { ...c, operator } : c);
        this._emit();
    }

    handleValueChange(evt) {
        const key = evt.currentTarget.dataset.key;
        const value = evt.detail.value;
        this.conditions = this.conditions.map(c => c.key === key ? { ...c, value } : c);
        this._emit();
    }

    handleConjunctionChange(evt) {
        const key = evt.currentTarget.dataset.key;
        const conjunction = evt.detail.value;
        this.conditions = this.conditions.map(c => c.key === key ? { ...c, conjunction } : c);
        this._emit();
    }

    _emit() {
        const payload = this.conditions
            .filter(c => c.field && c.operator)
            .map((c, i, arr) => ({
                field: c.field,
                operator: c.operator,
                value: c.value || '',
                conjunction: i < arr.length - 1 ? (c.conjunction || 'AND') : null,
            }));
        this.dispatchEvent(new CustomEvent('filterchange', { detail: { conditions: payload } }));
    }
}
