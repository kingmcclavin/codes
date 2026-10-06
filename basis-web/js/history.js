// Undo/redo. Pages and their element arrays are immutable values, so a step
// only stores the page arrays before and after the change.

const LIMIT = 200;

export class History {
  constructor(doc, onChange) {
    this.doc = doc;
    this.onChange = onChange;
    this.undoStack = [];
    this.redoStack = [];
  }

  /** Records a change already applied to doc.pages. */
  record(label, before) {
    if (before === this.doc.pages) return;
    this.undoStack.push({ label, before, after: this.doc.pages });
    if (this.undoStack.length > LIMIT) this.undoStack.shift();
    this.redoStack = [];
    this.onChange('record');
  }

  /** Applies `fn(pages) -> newPages` and records it. */
  perform(label, fn) {
    const before = this.doc.pages;
    const after = fn(before);
    if (!after || after === before) return false;
    this.doc.pages = after;
    this.record(label, before);
    return true;
  }

  get canUndo() { return this.undoStack.length > 0; }
  get canRedo() { return this.redoStack.length > 0; }

  undo() {
    const s = this.undoStack.pop();
    if (!s) return null;
    this.doc.pages = s.before;
    this.redoStack.push(s);
    this.onChange('undo');
    return s.label;
  }

  redo() {
    const s = this.redoStack.pop();
    if (!s) return null;
    this.doc.pages = s.after;
    this.undoStack.push(s);
    this.onChange('redo');
    return s.label;
  }
}

/** Returns a new pages array with page `pageId` replaced by `fn(page)`. */
export function updatePage(pages, pageId, fn) {
  const i = pages.findIndex((p) => p.id === pageId);
  if (i < 0) return pages;
  const np = fn(pages[i]);
  if (np === pages[i]) return pages;
  const out = pages.slice();
  out[i] = np;
  return out;
}

export function setElements(pages, pageId, fn) {
  return updatePage(pages, pageId, (p) => {
    const els = fn(p.elements);
    return els === p.elements ? p : { ...p, elements: els };
  });
}
