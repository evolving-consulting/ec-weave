import { LightningElement, api } from 'lwc';

export default class WeaveBuilderComponentCard extends LightningElement {
  @api component;

  get cardClass() {
    let cls = 'comp-card';
    if (this.component?.isDragging) cls += ' comp-card_dragging';
    if (this.component?.isDragOver) cls += ' comp-card_drag-over';
    return cls;
  }

  get typeBadgeClass() {
    const type = (this.component?.componentType || 'text')
      .toLowerCase()
      .replace(/ /g, '_');
    return `comp-card__type comp-card__type_${type}`;
  }

  get contentHint() {
    const c = this.component;
    if (!c) return '';
    switch (c.componentType) {
      case 'Text':
      case 'HTML Block': {
        const text = (c.htmlOutput || '').replace(/<[^>]+>/g, '').trim();
        return text.length > 65 ? text.slice(0, 65) + '…' : text || 'No content yet';
      }
      case 'Related Table':
        return c.linkedQueryName ? `Query: ${c.linkedQueryName}` : 'No query linked';
      case 'Field Row':
        return 'Field row component';
      case 'Image':
        return 'Image component';
      case 'Button':
        return 'Button component';
      case 'Divider':
        return '—';
      case 'Spacer':
        return 'Spacer';
      default:
        return '';
    }
  }

  handleEdit(event) {
    event.stopPropagation();
    this.dispatchEvent(new CustomEvent('componentedit', {
      bubbles: true,
      composed: true,
      detail: { key: this.component?.localKey, id: this.component?.id }
    }));
  }

  handleDelete(event) {
    event.stopPropagation();
    this.dispatchEvent(new CustomEvent('componentdelete', {
      bubbles: true,
      composed: true,
      detail: { key: this.component?.localKey, id: this.component?.id }
    }));
  }
}
