import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import previewPdfFromHtml from '@salesforce/apex/WeavePdfController.previewPdfFromHtml';

const INCH_PX = 96;
const LETTER = { w: 816, h: 1056 };
const A4 = { w: 794, h: 1123 };

const FONT_OPTIONS = [
    { label: 'Arial', value: 'Arial' },
    { label: 'Helvetica', value: 'Helvetica' },
    { label: 'Times New Roman', value: 'Times New Roman' },
    { label: 'Georgia', value: 'Georgia' },
    { label: 'Courier New', value: 'Courier New' }
];

function mkUuid() {
    try { return crypto.randomUUID(); }
    catch { return 'new-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8); }
}

function snapGrid(val) {
    const grid = 0.125;
    return Math.round(val / grid) * grid;
}

function stripHtml(html) {
    return (html || '').replace(/<[^>]+>/g, '').trim();
}

export default class WeaveCanvasDesigner extends LightningElement {
    @api parentFields;
    @api previewRecordId;

    _draftTemplate = {};
    _boxesLoaded = false;

    @api
    get draftTemplate() { return this._draftTemplate; }
    set draftTemplate(val) {
        this._draftTemplate = val || {};
        if (!this._boxesLoaded) {
            this._loadBoxes();
            this._boxesLoaded = true;
        }
    }

    @track mode = 'email';
    @track activeTool = 'select';
    @track boxes = [];
    @track selectedBoxId = null;
    @track gridSnap = true;
    @track undoStack = [];
    @track redoStack = [];
    @track isPreviewingPdf = false;
    @track pageCount = 1;

    _dragging = false;
    _dragBoxId = null;
    _dragStartClientX = 0;
    _dragStartClientY = 0;
    _dragBoxStartX = 0;
    _dragBoxStartY = 0;
    _didMove = false;
    _savedBoxesBeforeDrag = null;

    fontOptions = FONT_OPTIONS;

    // ── Computed ─────────────────────────────────────────────────────────────

    get isEmailMode() { return this.mode === 'email'; }
    get isDocumentMode() { return this.mode === 'document'; }

    get emailModeClass() {
        return 'mode-tab' + (this.mode === 'email' ? ' mode-tab_active' : '');
    }
    get documentModeClass() {
        return 'mode-tab' + (this.mode === 'document' ? ' mode-tab_active' : '');
    }

    get emailRegionGroups() {
        const comps = (this._draftTemplate.components || []).filter(c => !c.canvasMode);
        return ['Header', 'Body', 'Footer'].map(region => ({
            region,
            hasComponents: comps.some(c => c.region === region),
            components: comps
                .filter(c => c.region === region)
                .sort((a, b) => (a.displayOrder || 0) - (b.displayOrder || 0))
        }));
    }

    get hasEmailComponents() {
        return (this._draftTemplate.components || []).some(c => !c.canvasMode);
    }

    get artboardWidth() {
        const size = this._draftTemplate.canvasPageSize || 'Letter';
        const orient = this._draftTemplate.canvasOrientation || 'Portrait';
        const base = size === 'A4' ? A4 : LETTER;
        return orient === 'Landscape' ? base.h : base.w;
    }

    get artboardHeight() {
        const size = this._draftTemplate.canvasPageSize || 'Letter';
        const orient = this._draftTemplate.canvasOrientation || 'Portrait';
        const base = size === 'A4' ? A4 : LETTER;
        return orient === 'Landscape' ? base.w : base.h;
    }

    get artboardStyle() {
        return `width:${this.artboardWidth}px;height:${this.artboardHeight}px;`;
    }

    get artboardClass() {
        return this.activeTool === 'select' ? 'artboard-page' : 'artboard-page artboard-page_creating';
    }

    get pageGroups() {
        const maxPage = Math.max(
            this.pageCount,
            this.boxes.reduce((m, b) => Math.max(m, b.page || 1), 1)
        );
        const groups = [];
        for (let p = 1; p <= maxPage; p++) {
            groups.push({
                pageNum: p,
                pageKey: 'page-' + p,
                boxes: this.boxes
                    .filter(b => (b.page || 1) === p)
                    .map(b => {
                        const left = Math.round(b.x * INCH_PX);
                        const top = Math.round(b.y * INCH_PX);
                        const w = Math.round(b.w * INCH_PX);
                        const h = Math.round(b.h * INCH_PX);
                        const isSelected = b.id === this.selectedBoxId;
                        const text = stripHtml(b.html);
                        return {
                            id: b.id,
                            typeLabel: (b.type || 'box').charAt(0).toUpperCase() + (b.type || 'box').slice(1),
                            previewText: text.length > 60 ? text.slice(0, 60) + '…' : text,
                            boxClass: 'canvas-box canvas-box_' + (b.type || 'shape') + (isSelected ? ' canvas-box_selected' : ''),
                            style: `left:${left}px;top:${top}px;width:${w}px;height:${h}px;font-family:${b.font || 'Arial'},sans-serif;`
                        };
                    })
            });
        }
        return groups;
    }

    get selectedBox() {
        if (!this.selectedBoxId) return null;
        return this.boxes.find(b => b.id === this.selectedBoxId) || null;
    }

    get cannotUndo() { return this.undoStack.length === 0; }
    get cannotRedo() { return this.redoStack.length === 0; }

    get toolClass_select() { return 'tool-btn' + (this.activeTool === 'select' ? ' tool-btn_active' : ''); }
    get toolClass_text()   { return 'tool-btn' + (this.activeTool === 'text'   ? ' tool-btn_active' : ''); }
    get toolClass_table()  { return 'tool-btn' + (this.activeTool === 'table'  ? ' tool-btn_active' : ''); }
    get toolClass_image()  { return 'tool-btn' + (this.activeTool === 'image'  ? ' tool-btn_active' : ''); }
    get toolClass_shape()  { return 'tool-btn' + (this.activeTool === 'shape'  ? ' tool-btn_active' : ''); }

    // ── Initialisation ────────────────────────────────────────────────────────

    _loadBoxes() {
        const canvasComps = (this._draftTemplate.components || []).filter(c => c.canvasMode);
        this.boxes = canvasComps.map(c => {
            let font = 'Arial';
            let showCondition = null;
            try {
                if (c.configJson) {
                    const cfg = JSON.parse(c.configJson);
                    font = cfg.font || 'Arial';
                    showCondition = cfg.showCondition || null;
                }
            } catch { /* ignore malformed json */ }
            return {
                id: c.id || c.localKey || mkUuid(),
                type: c.componentType === 'Text'          ? 'text'
                    : c.componentType === 'Related Table' ? 'table'
                    : c.componentType === 'Image'         ? 'image'
                    : 'shape',
                page: c.canvasPage || 1,
                x: c.canvasX || 0.5,
                y: c.canvasY || 0.5,
                w: c.canvasW || 3.0,
                h: c.canvasH || 1.0,
                html: c.htmlOutput || '',
                font,
                queryId: c.linkedQueryId || null,
                showCondition
            };
        });
        if (this.boxes.length) {
            this.pageCount = this.boxes.reduce((m, b) => Math.max(m, b.page || 1), 1);
        }
    }

    // ── Mode / tool ───────────────────────────────────────────────────────────

    handleModeChange(event) {
        this.mode = event.currentTarget.dataset.mode;
        this.selectedBoxId = null;
    }

    handleToolChange(event) {
        this.activeTool = event.currentTarget.dataset.tool;
    }

    handleSnapToggle(event) {
        this.gridSnap = event.target.checked;
    }

    // ── Artboard interactions ─────────────────────────────────────────────────

    handleArtboardMouseDown(event) {
        if (this.activeTool === 'select') {
            if (event.target === event.currentTarget) {
                this.selectedBoxId = null;
            }
            return;
        }
        const rect = event.currentTarget.getBoundingClientRect();
        const pageNum = parseInt(event.currentTarget.dataset.page, 10) || 1;
        let xIn = (event.clientX - rect.left) / INCH_PX;
        let yIn = (event.clientY - rect.top) / INCH_PX;
        if (this.gridSnap) { xIn = snapGrid(xIn); yIn = snapGrid(yIn); }
        xIn = Math.max(0, parseFloat(xIn.toFixed(3)));
        yIn = Math.max(0, parseFloat(yIn.toFixed(3)));
        this._pushUndo();
        const newBox = {
            id: mkUuid(),
            type: this.activeTool,
            page: pageNum,
            x: xIn,
            y: yIn,
            w: 3.0,
            h: 1.0,
            html: '',
            font: 'Arial',
            queryId: null,
            showCondition: null
        };
        this.boxes = [...this.boxes, newBox];
        this.selectedBoxId = newBox.id;
        this.activeTool = 'select';
        this._emitComponentsChanged();
    }

    handleBoxMouseDown(event) {
        event.stopPropagation();
        const boxId = event.currentTarget.dataset.boxid;
        this.selectedBoxId = boxId;
        if (this.activeTool !== 'select') return;
        this._dragging = true;
        this._didMove = false;
        this._dragBoxId = boxId;
        this._dragStartClientX = event.clientX;
        this._dragStartClientY = event.clientY;
        this._savedBoxesBeforeDrag = JSON.parse(JSON.stringify(this.boxes));
        const box = this.boxes.find(b => b.id === boxId);
        if (box) {
            this._dragBoxStartX = box.x;
            this._dragBoxStartY = box.y;
        }
    }

    handleWorkspaceMouseMove(event) {
        if (!this._dragging) return;
        this._didMove = true;
        const dx = (event.clientX - this._dragStartClientX) / INCH_PX;
        const dy = (event.clientY - this._dragStartClientY) / INCH_PX;
        let newX = Math.max(0, this._dragBoxStartX + dx);
        let newY = Math.max(0, this._dragBoxStartY + dy);
        if (this.gridSnap) { newX = snapGrid(newX); newY = snapGrid(newY); }
        newX = parseFloat(newX.toFixed(3));
        newY = parseFloat(newY.toFixed(3));
        this.boxes = this.boxes.map(b => {
            return b.id === this._dragBoxId ? { ...b, x: newX, y: newY } : b;
        });
    }

    handleWorkspaceMouseUp() {
        if (this._dragging && this._didMove && this._savedBoxesBeforeDrag) {
            this.undoStack = [...this.undoStack.slice(-49), this._savedBoxesBeforeDrag];
            this.redoStack = [];
            this._emitComponentsChanged();
        }
        this._dragging = false;
        this._dragBoxId = null;
        this._didMove = false;
        this._savedBoxesBeforeDrag = null;
    }

    // ── Properties panel ──────────────────────────────────────────────────────

    handleBoxPropChange(event) {
        const prop = event.currentTarget.dataset.prop;
        let val = event.detail.value;
        if (['x', 'y', 'w', 'h'].includes(prop)) {
            val = parseFloat(val) || 0;
            if (this.gridSnap) { val = snapGrid(val); }
            val = parseFloat(val.toFixed(3));
        }
        this._pushUndo();
        this.boxes = this.boxes.map(b => {
            return b.id === this.selectedBoxId ? { ...b, [prop]: val } : b;
        });
        this._emitComponentsChanged();
    }

    handleDeleteBox() {
        if (!this.selectedBoxId) return;
        this._pushUndo();
        this.boxes = this.boxes.filter(b => b.id !== this.selectedBoxId);
        this.selectedBoxId = null;
        this._emitComponentsChanged();
    }

    handleDeselect() {
        this.selectedBoxId = null;
    }

    // ── Pages ─────────────────────────────────────────────────────────────────

    handleAddPage() {
        const maxPage = Math.max(
            this.pageCount,
            this.boxes.reduce((m, b) => Math.max(m, b.page || 1), 1)
        );
        this.pageCount = maxPage + 1;
    }

    // ── Undo / redo ───────────────────────────────────────────────────────────

    handleUndo() {
        if (!this.undoStack.length) return;
        this.redoStack = [...this.redoStack.slice(-49), JSON.parse(JSON.stringify(this.boxes))];
        this.boxes = this.undoStack[this.undoStack.length - 1];
        this.undoStack = this.undoStack.slice(0, -1);
        this._emitComponentsChanged();
    }

    handleRedo() {
        if (!this.redoStack.length) return;
        this.undoStack = [...this.undoStack.slice(-49), JSON.parse(JSON.stringify(this.boxes))];
        this.boxes = this.redoStack[this.redoStack.length - 1];
        this.redoStack = this.redoStack.slice(0, -1);
        this._emitComponentsChanged();
    }

    // ── PDF preview ───────────────────────────────────────────────────────────

    handlePreviewPdf() {
        if (this.isPreviewingPdf) return;
        this.isPreviewingPdf = true;
        const html = this._serializeArtboardToHtml();
        const title = this._draftTemplate.name || 'Preview';
        previewPdfFromHtml({ html, title })
            .then(docId => {
                window.open(`/sfc/servlet.shepherd/document/download/${docId}`, '_blank');
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'PDF Preview Failed',
                    message: error?.body?.message || 'An error occurred generating the PDF.',
                    variant: 'error'
                }));
            })
            .finally(() => {
                this.isPreviewingPdf = false;
            });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _pushUndo() {
        this.undoStack = [...this.undoStack.slice(-49), JSON.parse(JSON.stringify(this.boxes))];
        this.redoStack = [];
    }

    _emitComponentsChanged() {
        const canvasComponents = this.boxes.map((box, index) => ({
            id: (box.id && !box.id.startsWith('new-')) ? box.id : null,
            localKey: box.id,
            name: box.type + ' ' + (index + 1),
            componentType: box.type === 'text'  ? 'Text'
                         : box.type === 'table' ? 'Related Table'
                         : box.type === 'image' ? 'Image'
                         : 'Shape',
            region: 'Body',
            displayOrder: index,
            htmlOutput: box.html,
            configJson: JSON.stringify({ font: box.font, showCondition: box.showCondition }),
            canvasMode: true,
            canvasX: box.x,
            canvasY: box.y,
            canvasW: box.w,
            canvasH: box.h,
            canvasPage: box.page,
            linkedQueryId: box.queryId || null
        }));
        const nonCanvasComponents = (this._draftTemplate.components || []).filter(c => !c.canvasMode);
        this.dispatchEvent(new CustomEvent('componentschanged', {
            detail: { components: [...nonCanvasComponents, ...canvasComponents] },
            bubbles: false
        }));
    }

    _serializeArtboardToHtml() {
        const aw = this.artboardWidth;
        const ah = this.artboardHeight;
        const maxPage = Math.max(
            this.pageCount,
            this.boxes.reduce((m, b) => Math.max(m, b.page || 1), 1)
        );
        let fullHtml = '';
        for (let p = 1; p <= maxPage; p++) {
            const pageBoxes = this.boxes.filter(b => (b.page || 1) === p);
            let pageHtml = `<div style="position:relative;width:${aw}px;height:${ah}px;background:white;overflow:hidden;page-break-after:always;">`;
            for (const box of pageBoxes) {
                const left = Math.round(box.x * INCH_PX);
                const top  = Math.round(box.y * INCH_PX);
                const w    = Math.round(box.w * INCH_PX);
                const h    = Math.round(box.h * INCH_PX);
                pageHtml += `<div style="position:absolute;left:${left}px;top:${top}px;width:${w}px;height:${h}px;font-family:${box.font || 'Arial'},sans-serif;overflow:hidden;">${box.html || ''}</div>`;
            }
            pageHtml += '</div>';
            fullHtml += pageHtml;
        }
        return fullHtml;
    }
}
