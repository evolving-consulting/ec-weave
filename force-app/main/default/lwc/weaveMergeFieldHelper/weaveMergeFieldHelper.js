import { LightningElement, api, track } from 'lwc';
import validateTemplateMergeFields from '@salesforce/apex/WeaveTemplateBuilderController.validateTemplateMergeFields';

const DEBOUNCE_MS = 300;

export default class WeaveMergeFieldHelper extends LightningElement {
    @api label = 'Merge Field';
    @api parentObjectApiName;
    @api showInsertButton = false;

    /** Pre-built suggestions: [{ value, label, sourceType }] */
    @api
    get suggestions() { return this._suggestions; }
    set suggestions(val) {
        this._suggestions = Array.isArray(val) ? val : [];
        this._applyFilter();
    }

    @track value = '';
    @track filteredSuggestions = [];
    @track validationMessage = '';
    @track validationClass = 'validation-msg';
    @track validationIcon = '';

    _suggestions = [];
    _debounceTimer;

    get hasSuggestions() {
        return this.filteredSuggestions.length > 0;
    }

    handleInputChange(event) {
        this.value = event.detail.value;
        this._applyFilter();
        this._scheduleValidation();
    }

    handleSuggestionClick(event) {
        const val = event.currentTarget.dataset.value;
        this.value = val;
        this.filteredSuggestions = [];
        this._validate(val);
        this._fireChange(val);
    }

    handleInsert() {
        if (this.value) {
            this.dispatchEvent(new CustomEvent('insert', { detail: { value: this.value } }));
        }
    }

    _applyFilter() {
        if (!this.value || !this._suggestions.length) {
            this.filteredSuggestions = [];
            return;
        }
        const lower = this.value.toLowerCase().replace(/[{}]/g, '').trim();
        this.filteredSuggestions = this._suggestions
            .filter(s => s.value.toLowerCase().includes(lower) || s.label.toLowerCase().includes(lower))
            .slice(0, 8)
            .map(s => ({
                ...s,
                displayTag: s.value,
                badgeClass: 'source-badge source-badge_' + (s.sourceType || 'parent').toLowerCase()
            }));
    }

    _scheduleValidation() {
        clearTimeout(this._debounceTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._debounceTimer = setTimeout(() => {
            this._validate(this.value);
        }, DEBOUNCE_MS);
    }

    _validate(val) {
        if (!val || !val.trim()) {
            this.validationMessage = '';
            return;
        }
        // Wrap bare paths in braces for template validation
        const content = val.startsWith('{{') ? val : '{{' + val + '}}';
        validateTemplateMergeFields({
            templateContent: content,
            parentObjectApiName: this.parentObjectApiName || null
        })
        .then(result => {
            if (result.errors && result.errors.length > 0) {
                this.validationMessage = result.errors[0].message;
                this.validationClass = 'validation-msg validation-msg_error';
                this.validationIcon = '✕';
            } else if (result.warnings && result.warnings.length > 0) {
                this.validationMessage = result.warnings[0].message;
                this.validationClass = 'validation-msg validation-msg_warn';
                this.validationIcon = '⚠';
            } else {
                this.validationMessage = 'Valid merge field';
                this.validationClass = 'validation-msg validation-msg_ok';
                this.validationIcon = '✓';
            }
        })
        .catch(() => {
            this.validationMessage = '';
        });
    }

    _fireChange(val) {
        this.dispatchEvent(new CustomEvent('fieldchange', { detail: { value: val } }));
    }
}
