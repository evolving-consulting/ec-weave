import { LightningElement, api } from 'lwc';

export default class DceBuilderSectionCard extends LightningElement {
  @api section;

  get cardClass() {
    let cls = 'section-card';
    if (this.section?.isSelected) cls += ' section-card_selected';
    if (this.section?.isDragging) cls += ' section-card_dragging';
    if (this.section?.isDragOver) cls += ' section-card_drag-over';
    return cls;
  }

  get typeBadgeClass() {
    const type = (this.section?.sectionType || 'text')
      .toLowerCase()
      .replace(/ /g, '_');
    return `section-card__type section-card__type_${type}`;
  }

  get contentHint() {
    const s = this.section;
    if (!s) return '';
    if (s.sectionType === 'Text' || s.sectionType === 'Static Text') {
      const text = (s.staticContent || '').replace(/<[^>]+>/g, '').trim();
      return text.length > 65 ? text.slice(0, 65) + '…' : text || 'No content yet';
    }
    if (s.sectionType === 'Columns') {
      return `${s.columnCount || 2} columns`;
    }
    if (s.sectionType === 'Text Block') {
      const n = (s.lines || []).length;
      return `${n} line${n !== 1 ? 's' : ''} · ${s.childObjectApiName || 'No object selected'}`;
    }
    if (s.sectionType === 'Related') {
      const n = (s.fields || []).length;
      return `${n} column${n !== 1 ? 's' : ''} · ${s.childObjectApiName || 'No object selected'}`;
    }
    return '';
  }

  handleDelete(event) {
    event.stopPropagation();
    this.dispatchEvent(new CustomEvent('sectiondelete', {
      bubbles: true,
      composed: true,
      detail: { key: this.section?.localKey }
    }));
  }
}
