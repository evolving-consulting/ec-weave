import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import analyzeAll        from '@salesforce/apex/LegacyTemplateMigrationController.analyzeAll';
import migrateToMCN     from '@salesforce/apex/LegacyTemplateMigrationController.migrateToMCN';
import rollback         from '@salesforce/apex/LegacyTemplateMigrationController.rollback';
import generateAnalysisCsv from '@salesforce/apex/LegacyTemplateMigrationController.generateAnalysisCsv';
import buildSummary     from '@salesforce/apex/LegacyTemplateMigrationController.buildSummary';

export default class LegacyTemplateMigration extends LightningElement {

    @track results         = [];
    @track filteredResults = [];
    @track summary         = null;
    @track migrationResult = null;
    @track errorMessage    = null;

    isLoading    = false;
    isMigrating  = false;
    activeFilter = 'All';
    lastMigratedIds = [];

    // ── Computed ──────────────────────────────────────────────────────────────

    get hasSummary()   { return this.summary != null; }
    get hasResults()   { return this.results.length > 0; }
    get migratingCount() { return this.selectedCount; }

    get selectedCount() {
        return this.results.filter(r => r.isSelected && r.recommendation === 'Migrate').length;
    }

    get noReadySelected() {
        return this.selectedCount === 0 || this.isLoading || this.isMigrating;
    }

    get tabAll()    { return this.tabClass('All'); }
    get tabMigrate(){ return this.tabClass('Migrate'); }
    get tabManual() { return this.tabClass('Manual Review'); }
    get tabSkip()   { return this.tabClass('Skip'); }

    tabClass(filter) {
        const base = 'filter-tab';
        return this.activeFilter === filter ? base + ' filter-tab_active' : base;
    }

    // ── Analyze ───────────────────────────────────────────────────────────────

    handleAnalyze() {
        this.isLoading = true;
        this.errorMessage = null;
        this.migrationResult = null;

        analyzeAll()
            .then(raw => {
                this.results = raw.map(r => this.enrichResult(r));
                this.applyFilter();
                return buildSummary({ results: raw });
            })
            .then(s => {
                this.summary = s;
            })
            .catch(e => {
                this.errorMessage = e.body?.message || 'Failed to analyze templates.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ── Filter ────────────────────────────────────────────────────────────────

    handleFilter(evt) {
        this.activeFilter = evt.target.dataset.filter;
        this.applyFilter();
    }

    applyFilter() {
        this.filteredResults = this.activeFilter === 'All'
            ? this.results
            : this.results.filter(r => r.recommendation === this.activeFilter);
    }

    // ── Selection ─────────────────────────────────────────────────────────────

    handleSelectAll(evt) {
        const checked = evt.target.checked;
        this.results = this.results.map(r => ({
            ...r,
            isSelected: checked && r.recommendation === 'Migrate'
        }));
        this.applyFilter();
    }

    handleRowSelect(evt) {
        const id = evt.target.dataset.id;
        this.results = this.results.map(r =>
            r.templateId === id ? { ...r, isSelected: evt.target.checked } : r
        );
        this.applyFilter();
    }

    // ── Migrate ───────────────────────────────────────────────────────────────

    handleMigrateSelected() {
        const ids = this.results
            .filter(r => r.isSelected && r.recommendation === 'Migrate')
            .map(r => r.templateId);

        if (ids.length === 0) return;

        this.isMigrating = true;
        this.lastMigratedIds = ids;

        migrateToMCN({ templateIds: ids })
            .then(result => {
                this.migrationResult = result;
                this.dispatchEvent(new ShowToastEvent({
                    title   : 'Migration Complete',
                    message : result.migrated + ' template(s) migrated to All Channels.',
                    variant : 'success'
                }));
                this.handleAnalyze();
            })
            .catch(e => {
                this.errorMessage = e.body?.message || 'Migration failed.';
            })
            .finally(() => {
                this.isMigrating = false;
            });
    }

    // ── Rollback ──────────────────────────────────────────────────────────────

    handleRollback() {
        if (this.lastMigratedIds.length === 0) return;
        this.isLoading = true;

        rollback({ templateIds: this.lastMigratedIds })
            .then(result => {
                this.migrationResult = null;
                this.dispatchEvent(new ShowToastEvent({
                    title   : 'Rollback Complete',
                    message : result.migrated + ' template(s) restored.',
                    variant : 'success'
                }));
                this.handleAnalyze();
            })
            .catch(e => {
                this.errorMessage = e.body?.message || 'Rollback failed.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ── Export CSV ────────────────────────────────────────────────────────────

    handleExportCsv() {
        generateAnalysisCsv({ results: this.results.map(r => ({
            templateId     : r.templateId,
            templateName   : r.templateName,
            currentChannel : r.currentChannel,
            status         : r.status,
            readinessScore : r.readinessScore,
            recommendation : r.recommendation,
            issues         : r.issues,
            warnings       : r.warnings
        }))})
        .then(csv => {
            const blob = new Blob([csv], { type: 'text/csv' });
            const url  = URL.createObjectURL(blob);
            const a    = document.createElement('a');
            a.href     = url;
            a.download = 'mcn_migration_analysis.csv';
            a.click();
            URL.revokeObjectURL(url);
        })
        .catch(e => {
            this.errorMessage = e.body?.message || 'Export failed.';
        });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    clearError() {
        this.errorMessage = null;
    }

    enrichResult(r) {
        return {
            ...r,
            isSelected        : false,
            issuesSummary     : [...(r.issues || []), ...(r.warnings || [])].slice(0, 2).join('; '),
            scoreClass        : r.readinessScore >= 70 ? 'score-pill score-high'
                              : r.readinessScore >= 40 ? 'score-pill score-mid'
                              : 'score-pill score-low',
            recommendationClass: r.recommendation === 'Migrate'       ? 'rec-pill rec-migrate'
                               : r.recommendation === 'Manual Review' ? 'rec-pill rec-manual'
                               : 'rec-pill rec-skip'
        };
    }
}
