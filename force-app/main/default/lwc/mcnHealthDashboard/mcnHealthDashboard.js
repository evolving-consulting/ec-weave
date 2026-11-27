import { LightningElement, track } from 'lwc';
import getHealthMetrics  from '@salesforce/apex/MCNHealthDashboardController.getHealthMetrics';
import getSyncLogs       from '@salesforce/apex/MCNHealthDashboardController.getRecentLogs';

export default class McnHealthDashboard extends LightningElement {

    @track metrics      = null;
    @track recentErrors = [];
    @track errorMessage = null;

    isLoading    = false;
    lastRefresh  = null;

    connectedCallback() {
        this.handleRefresh();
    }

    // ── Computed ──────────────────────────────────────────────────────────────

    get hasMetrics()  { return this.metrics != null; }
    get hasErrors()   { return this.recentErrors.length > 0; }

    get lastRefreshLabel() {
        return this.lastRefresh
            ? new Intl.DateTimeFormat('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' })
                  .format(this.lastRefresh)
            : '—';
    }

    get overallHealthClass() {
        return this.metrics?.isHealthy
            ? 'health-banner health-banner_good'
            : 'health-banner health-banner_alert';
    }

    get healthIcon()   { return this.metrics?.isHealthy ? '✓' : '⚠'; }
    get healthLabel()  { return this.metrics?.isHealthy ? 'Healthy' : 'Alert'; }
    get healthDetail() {
        if (!this.metrics) return '';
        return this.metrics.isHealthy
            ? 'All services operating normally.'
            : 'Error rate ' + this.metrics.errorRatePct + '% exceeds threshold.';
    }

    get syncStatusClass() {
        return this.metrics?.isHealthy ? 'status-dot status-dot_green' : 'status-dot status-dot_red';
    }
    get publishStatusClass() { return this.syncStatusClass; }

    // ── Refresh ───────────────────────────────────────────────────────────────

    handleRefresh() {
        this.isLoading = true;
        this.errorMessage = null;

        Promise.all([
            getHealthMetrics(),
            getSyncLogs({ limitCount: 10 }).catch(() => [])
        ])
        .then(([health, logs]) => {
            this.metrics = this.enrichMetrics(health);
            this.recentErrors = (logs || []).map(l => this.enrichLog(l));
            this.lastRefresh = new Date();
        })
        .catch(e => {
            this.errorMessage = e.body?.message || 'Failed to load health metrics.';
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    clearError() {
        this.errorMessage = null;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    enrichMetrics(h) {
        return {
            ...h,
            publishedLast24h : h.publishedLast24h  ?? '—',
            sentLast24h      : h.sentLast24h        ?? '—',
            errorsLast24h    : h.errorCount         ?? 0,
            errorRatePct     : h.errorRatePct       ?? 0,
            migratedCount    : h.migratedCount      ?? '—',
            lastSyncLabel    : h.checkTime
                ? new Date(h.checkTime).toLocaleString()
                : 'Unknown',
            lastPublishLabel : h.checkTime
                ? new Date(h.checkTime).toLocaleString()
                : 'Unknown'
        };
    }

    enrichLog(log) {
        return {
            id          : log.Id,
            templateName: log.Template__r?.Name || log.Template__c || '—',
            operation   : log.Publish_Type__c || '—',
            errorMessage: log.Error_Message__c || '—',
            createdLabel: log.CreatedDate
                ? new Date(log.CreatedDate).toLocaleString()
                : '—'
        };
    }
}
