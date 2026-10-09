// A notebook open for editing: toolbar, tool options, canvas, page manager,
// page settings, floating calculator, clipboard and autosave.

import { h, debounce, uuid, storage, css, colorsClose, clamp, hexToRgba } from './util.js';
import { icon } from './icons.js';
import {
  sheet, askText, confirmDialog, popover, menu, toast, segmented, selectField, slider, swatches, toggle, iconButton, pickFile, saveFile,
} from './ui.js';
import { CanvasView } from './canvas.js';
import { History, setElements, updatePage } from './history.js';
import {
  TOOLS, INK_KINDS, INK_PALETTE, HIGHLIGHTER_PALETTE, PEN_PRESETS, BALLPOINT_PRESSURE, OLD_BALLPOINT_PRESSURE, HIGHLIGHTER_PRESET, FONT_FAMILIES, PAPER_SIZES, TEMPLATES, PAPER_COLORS,
  sizeFor, matchPaper, makeBackground, makePage, describeSize,
} from './model.js';
import { store } from './store.js';
import { elementBounds, transformElement, recolor, primaryColor, withNewId, layoutText, naturalTextWidth, kindName, isClosedShape, buildStrokePath, packPoints } from './elements.js';
import { renderPageCanvas, fillStrokePath } from './render.js';
import { translateT } from './util.js';
import { calc } from './calc/store.js';
import { calculatorPad } from './calculator.js';
import { importPDF, exportPDF, exportPNG, pdfPageText } from './pdf.js';
import { Recognizer, aiAvailable, findInDocument, pageChunks, hasContent } from './recognize.js';
import { aiConfig, PROVIDERS } from './ai.js';
import { SCRIBBLE_MODES } from './scribble.js';
import { exportBasis } from './basisfile.js';

const TOOL_ICONS = { pen: 'pen', highlighter: 'highlighter', eraser: 'eraser', shapes: 'shapes', lasso: 'lasso', text: 'text' };

// Clipboard shared across notebooks (and kept for this browser session).
let clipboard = null;

export class Editor {
  constructor(doc, { onClose, tabs }) {
    this.doc = doc;
    // Notebooks whose ballpoint is still on the old, very pressure-sensitive default.
    const pen = doc.settings?.pen;
    if (pen?.kind === 'ballpoint' && pen.pressure === OLD_BALLPOINT_PRESSURE) pen.pressure = BALLPOINT_PRESSURE;
    this.onClose = onClose;
    this.tabs = tabs;
    this.history = new History(doc, () => { this.refreshUndo(); });
    this.dirty = false;
    // Autosave once writing pauses; saving a big notebook mid-stroke can stall the ink.
    this.save = debounce(() => (this.canvas?.interaction ? this.save() : this.saveNow()), 1200);
    this.root = h('div', { class: 'editor' });
    this.buildChrome();
    this.canvas = new CanvasView(this, this.canvasHost);
    this.renderOptions();
    this.refreshUndo();
    this.viewChanged();
    this.onKey = (e) => this.handleKey(e);
    window.addEventListener('keydown', this.onKey);
    this.onHide = () => { if (document.visibilityState === 'hidden') this.saveNow(); };
    document.addEventListener('visibilitychange', this.onHide);
    this.onCalc = () => this.floatPad?.refresh();
    calc.addEventListener('change', this.onCalc);
    this.recognizer = new Recognizer(this);
  }

  mount(parent) { parent.append(this.root); this.canvas.resize(); }

  async close() {
    this.canvas.endTextEdit();
    await this.saveNow();
    this.destroy();
  }

  destroy() {
    this.save.cancel?.();
    this.recognizer.stop();
    window.removeEventListener('keydown', this.onKey);
    document.removeEventListener('visibilitychange', this.onHide);
    calc.removeEventListener('change', this.onCalc);
    this.canvas.destroy();
    this.root.remove();
  }

  get settings() { return this.doc.settings; }

  // ---------- Persistence ----------

  documentChanged() {
    this.dirty = true;
    this.save();
    this.recognizer?.schedule();
    this.refreshPageIndicator();
  }

  async saveNow() {
    this.save.flush?.();
    const c = this.canvas;
    if (c) this.doc.view = { pageIndex: c.currentPageIndex, zoom: c.view.zoom, scrollX: c.view.x, scrollY: c.view.y };
    try {
      // Scroll position alone isn't worth syncing; content and recognized handwriting are.
      await store.saveDocument(this.doc, { touch: this.dirty, quiet: !this.dirty && !this.syncDirty });
      this.dirty = false;
      this.syncDirty = false;
    } catch (e) {
      toast('Couldn’t save: ' + (e.message || 'storage is full or unavailable'));
    }
  }

  settingsChanged() {
    this.save();
    this.renderToolbarState();
  }

  // ---------- Chrome ----------

  buildChrome() {
    const back = h('button', { class: 'icon-btn', title: 'Back to library', 'aria-label': 'Back to library', onclick: () => this.onClose() }, icon('back'));
    this.titleBtn = h('button', { class: 'doc-title', title: 'Rename', onclick: () => this.rename() }, this.doc.title || 'Untitled');
    this.toolButtons = {};
    const tools = h('div', { class: 'tool-group', role: 'toolbar', 'aria-label': 'Tools', 'data-tour': 'tools' });
    for (const t of TOOLS) {
      const b = h('button', { class: 'tool-btn', title: `${t.name} (${t.key})`, 'aria-label': t.name, 'aria-pressed': 'false' }, icon(TOOL_ICONS[t.id]), h('span', { class: 'tool-color' }));
      b.addEventListener('click', () => this.selectTool(t.id));
      this.toolButtons[t.id] = b;
      tools.append(b);
    }
    const imgBtn = iconButton('image', 'Insert image', () => this.insertImage());
    this.calcBtn = iconButton('calc', 'Calculator (K)', () => this.toggleCalculator());
    this.calcBtn.dataset.tour = 'calc';
    tools.append(h('span', { class: 'tool-sep' }), imgBtn, this.calcBtn);

    this.undoBtn = iconButton('undo', 'Undo (⌘Z)', () => this.undo());
    this.redoBtn = iconButton('redo', 'Redo (⇧⌘Z)', () => this.redo());
    const pagesBtn = iconButton('pages', 'Pages', () => this.showPageManager());
    const settingsBtn = iconButton('pagesettings', 'Page settings', () => this.showPageSettings());
    const moreBtn = iconButton('more', 'More', () => this.showMoreMenu(moreBtn));
    moreBtn.dataset.tour = 'more';

    this.tabstrip = h('div', { class: 'tabstrip', role: 'tablist', 'aria-label': 'Open notebooks' });
    this.optionsBar = h('div', { class: 'options-bar' });
    this.canvasHost = h('div', { class: 'canvas-host' });
    this.zoomLabel = h('button', { class: 'zoom-label', title: 'Zoom options' }, '100%');
    this.zoomLabel.addEventListener('click', () => menu(this.zoomLabel, [
      { label: 'Fit to Screen Edges', icon: 'fit', hint: 'double-tap', action: () => this.canvas.fitEdges() },
      { label: 'Fit Width with Margin', icon: 'fit', action: () => this.canvas.fitWidth() },
      { label: 'Fit Whole Page', icon: 'pages', action: () => this.canvas.fitPage() },
      'sep',
      ...[50, 100, 150, 200, 400].map((p) => ({ label: `${p}%`, action: () => this.canvas.setZoom(p / 100) })),
    ], { align: 'end' }));
    const zoom = h('div', { class: 'float-pill zoom-pill' },
      iconButton('minus', 'Zoom out', () => this.canvas.zoomBy(1 / 1.25), { size: 18 }), this.zoomLabel, iconButton('plus', 'Zoom in', () => this.canvas.zoomBy(1.25), { size: 18 }));
    this.pageLabel = h('button', { class: 'page-label', title: 'Pages' });
    this.pageLabel.addEventListener('click', () => this.pageLabelMenu());
    this.prevBtn = iconButton('chevronUp', 'Previous page', () => this.canvas.scrollToPage(this.canvas.currentPageIndex - 1), { size: 18 });
    this.nextBtn = iconButton('chevronDown', 'Next page', () => this.canvas.scrollToPage(this.canvas.currentPageIndex + 1), { size: 18 });
    const pageInd = h('div', { class: 'float-pill page-pill', 'data-tour': 'pages' }, this.prevBtn, this.pageLabel, this.nextBtn, iconButton('plus', 'Add page', () => this.addPage(), { size: 18 }));
    this.canvasHost.append(zoom, pageInd);

    this.root.append(
      this.tabstrip,
      h('header', { class: 'editor-toolbar' },
        h('div', { class: 'tb-left' }, back, this.titleBtn),
        tools,
        h('div', { class: 'tb-right' }, this.undoBtn, this.redoBtn, pagesBtn, settingsBtn, moreBtn)),
      this.optionsBar,
      this.canvasHost,
    );
    this.renderTabs();
    this.renderToolbarState();
    if (storage.get('basis.floatingCalc', false)) setTimeout(() => this.toggleCalculator(true), 0);
  }

  renderTabs() {
    const ids = this.tabs?.list() || [];
    this.tabstrip.hidden = ids.length < 2;
    this.tabstrip.replaceChildren(...ids.map((id) => {
      const active = id === this.doc.id;
      const title = id === this.doc.id ? this.doc.title : store.summary(id)?.title || 'Untitled';
      const tab = h('div', { class: `tab ${active ? 'on' : ''}`, role: 'tab', 'aria-selected': String(active) },
        h('button', { class: 'tab-title', onclick: () => !active && this.tabs.activate(id) }, title || 'Untitled'),
        h('button', { class: 'tab-close', 'aria-label': `Close ${title}`, onclick: () => this.tabs.close(id) }, icon('close', 12)));
      return tab;
    }));
  }

  renderToolbarState() {
    const st = this.settings;
    for (const [id, b] of Object.entries(this.toolButtons)) {
      const on = st.tool === id;
      b.classList.toggle('on', on);
      b.setAttribute('aria-pressed', String(on));
      const c = id === 'pen' ? st.pen.color : id === 'highlighter' ? st.highlighter.color : id === 'shapes' ? st.shape.strokeColor : null;
      b.querySelector('.tool-color').style.background = c ? css({ ...c, a: 1 }) : 'transparent';
    }
    this.canvasHost.dataset.tool = st.tool;
  }

  refreshUndo() {
    if (!this.undoBtn) return;
    this.undoBtn.disabled = !this.history.canUndo;
    this.redoBtn.disabled = !this.history.canRedo;
  }

  viewChanged() {
    if (!this.canvas) return;
    this.zoomLabel.textContent = Math.round(this.canvas.view.zoom * 100) + '%';
    this.refreshPageIndicator();
  }

  refreshPageIndicator() {
    const i = this.canvas.currentPageIndex, n = this.doc.pages.length;
    const section = this.sectionAt(i);
    this.pageLabel.replaceChildren(section ? h('span', { class: 'section-name' }, section.title) : null, h('span', { class: 'mono' }, `${i + 1} / ${n}`));
    this.prevBtn.disabled = i <= 0;
    this.nextBtn.disabled = i >= n - 1;
  }

  sections() { return this.doc.pages.map((p, i) => (p.background.section ? { title: p.background.section, start: i } : null)).filter(Boolean); }
  sectionAt(i) { return this.sections().filter((s) => s.start <= i).pop() || null; }

  pageLabelMenu() {
    const secs = this.sections();
    if (!secs.length) { this.showPageManager(); return; }
    menu(this.pageLabel, [
      ...secs.map((s) => ({ label: `${s.title} (p. ${s.start + 1})`, icon: 'bookmark', action: () => this.canvas.scrollToPage(s.start) })),
      'sep',
      { label: 'All Pages…', icon: 'pages', action: () => this.showPageManager() },
    ], { align: 'center' });
  }

  async rename() {
    const t = await askText({ title: 'Rename Notebook', value: this.doc.title, confirm: 'Rename' });
    if (t == null || !t.trim()) return;
    this.doc.title = t.trim();
    this.titleBtn.textContent = this.doc.title;
    this.documentChanged();
    this.renderTabs();
  }

  // ---------- Tools & options ----------

  selectTool(id) {
    if (this.canvas.textEdit && id !== 'text') this.canvas.endTextEdit();
    if (id === this.settings.tool) {
      if (id === 'pen' || id === 'highlighter') this.showPenSettings(this.toolButtons[id]);
      return;
    }
    this.previousTool = this.settings.tool;
    if (id !== 'lasso') this.canvas.clearSelection();
    this.settings.tool = id;
    this.settingsChanged();
    this.renderOptions();
    this.canvas.requestOverlay();
  }

  get activeInk() { return this.settings.tool === 'highlighter' ? this.settings.highlighter : this.settings.pen; }
  set activeInk(st) { if (this.settings.tool === 'highlighter') this.settings.highlighter = st; else this.settings.pen = st; }

  currentColor() {
    const st = this.settings;
    switch (st.tool) {
      case 'highlighter': return st.highlighter.color;
      case 'shapes': return st.shape.strokeColor;
      case 'text': return st.text.color;
      case 'lasso': { const els = this.canvas.selectedElements(); return els.map(primaryColor).find(Boolean) || st.pen.color; }
      default: return st.pen.color;
    }
  }

  useColor(c, transient = false) {
    const st = this.settings;
    if (!transient) noteRecentColor(c);
    switch (st.tool) {
      case 'highlighter': st.highlighter.color = c; break;
      case 'shapes': st.shape.strokeColor = c; if (st.shape.fill) st.shape.fill = { ...c, a: st.shape.fill.a }; break;
      case 'text': st.text.color = c; this.canvas.restyleEditingText(st.text); break;
      case 'lasso': if (!transient) this.applyToSelection('Color', (e) => recolor(e, c)); return;
      default: st.pen.color = c;
    }
    this.settingsChanged();
  }

  colorStrip(palette = INK_PALETTE) {
    const recents = storage.get('basis.recentColors', []).filter((c) => !palette.some((p) => colorsClose(p, c))).slice(0, 5);
    return swatches(palette, this.currentColor(), (c, transient) => this.useColor(c, transient), { extra: recents });
  }

  renderOptions() {
    const st = this.settings;
    const bar = this.optionsBar;
    const sep = () => h('span', { class: 'opt-sep' });
    bar.replaceChildren();
    switch (st.tool) {
      case 'pen':
      case 'highlighter': {
        const isHL = st.tool === 'highlighter';
        const ink = this.activeInk;
        const presetBtn = h('button', { class: 'opt-btn', 'aria-haspopup': 'menu' }, icon(isHL ? 'highlighter' : 'pen', 18), h('span', {}, INK_KINDS[ink.kind].name), icon('chevronDown', 14));
        presetBtn.addEventListener('click', () => {
          const custom = storage.get('basis.penPresets', []).filter((p) => (p.style.kind === 'highlighter') === isHL);
          menu(presetBtn, [
            { header: 'Presets' },
            ...(isHL ? [HIGHLIGHTER_PRESET] : PEN_PRESETS).map((p) => ({ label: p.name, action: () => { this.activeInk = { ...structuredClone(p.style), color: isHL ? this.activeInk.color : this.activeInk.color }; this.settingsChanged(); this.renderOptions(); } })),
            custom.length ? { header: 'My Presets' } : null,
            ...custom.map((p) => ({ label: p.name, action: () => { this.activeInk = structuredClone(p.style); this.settingsChanged(); this.renderOptions(); } })),
            custom.length ? 'sep' : null,
            ...custom.map((p) => ({ label: `Delete “${p.name}”`, icon: 'trash', danger: true, action: () => storage.set('basis.penPresets', storage.get('basis.penPresets', []).filter((x) => x.id !== p.id)) })),
          ]);
        });
        const widths = INK_KINDS[ink.kind].quick;
        const widthGroup = h('div', { class: 'width-group', role: 'radiogroup', 'aria-label': 'Thickness' });
        const renderWidths = () => widthGroup.replaceChildren(...widths.map((w, i) => {
          const b = h('button', { class: `width-dot ${Math.abs(this.activeInk.width - w) < 0.05 ? 'on' : ''}`, 'aria-label': `Thickness ${w}`, title: `${w} pt` }, h('span', { style: { width: 4 + i * 5 + 'px', height: 4 + i * 5 + 'px' } }));
          b.addEventListener('click', () => { this.activeInk.width = w; this.settingsChanged(); renderWidths(); });
          return b;
        }));
        renderWidths();
        const settingsBtn = h('button', { class: 'opt-btn', title: 'Pen settings' }, icon('sliders', 18), h('span', {}, `${this.activeInk.width.toFixed(this.activeInk.width < 10 ? 1 : 0)} pt`));
        settingsBtn.addEventListener('click', () => this.showPenSettings(settingsBtn));
        bar.append(presetBtn, sep(), this.colorStrip(isHL ? HIGHLIGHTER_PALETTE : INK_PALETTE), sep(), widthGroup, settingsBtn);
        if (!isHL) bar.append(sep(), h('span', { class: 'opt-hint' }, [st.holdToSnap ? 'Hold at the end of a stroke to snap it to a shape.' : '', st.scribbleToErase !== false ? 'Scribble over ink to erase it.' : ''].filter(Boolean).join(' ')));
        break;
      }
      case 'eraser': {
        const scribbleMode = selectField('scribble-mode', SCRIBBLE_MODES, st.scribbleMode || 'strokes', (v) => { st.scribbleMode = v; this.settingsChanged(); });
        scribbleMode.classList.add('compact');
        scribbleMode.setAttribute('aria-label', 'Scribble erases');
        scribbleMode.disabled = st.scribbleToErase === false;
        bar.append(
          segmented([{ value: 'object', label: 'Stroke' }, { value: 'partial', label: 'Pixel' }], st.eraser.mode, (v) => { st.eraser.mode = v; this.settingsChanged(); }, { label: 'Eraser mode' }),
          sep(),
          h('span', { class: 'opt-label' }, 'Size'),
          slider('eraser-size', { min: 8, max: 80, step: 1, value: st.eraser.size, format: (v) => `${v}px`, onInput: (v) => { st.eraser.size = v; this.settingsChanged(); } }).el,
          sep(),
          toggle('hl-only', 'Highlighter only', st.eraser.highlighterOnly, (v) => { st.eraser.highlighterOnly = v; this.settingsChanged(); }),
          sep(),
          toggle('scribble-erase', 'Scribble to erase', st.scribbleToErase !== false, (v) => { st.scribbleToErase = v; this.settingsChanged(); scribbleMode.disabled = !v; }),
          scribbleMode,
        );
        break;
      }
      case 'shapes': {
        const fillBtn = h('button', { class: 'opt-btn' }, h('span', {}, st.shape.fill ? (st.shape.fill.a < 0.5 ? 'Light fill' : 'Solid fill') : 'No fill'), icon('chevronDown', 14));
        fillBtn.addEventListener('click', () => menu(fillBtn, [
          { label: 'No Fill', checked: !st.shape.fill, action: () => { st.shape.fill = null; this.settingsChanged(); this.renderOptions(); } },
          { label: 'Light Fill', checked: !!st.shape.fill && st.shape.fill.a < 0.5, action: () => { st.shape.fill = { ...st.shape.strokeColor, a: 0.18 }; this.settingsChanged(); this.renderOptions(); } },
          { label: 'Solid Fill', checked: !!st.shape.fill && st.shape.fill.a >= 0.5, action: () => { st.shape.fill = { ...st.shape.strokeColor }; this.settingsChanged(); this.renderOptions(); } },
        ]));
        bar.append(this.colorStrip(), sep(),
          h('span', { class: 'opt-label' }, 'Width'),
          slider('shape-width', { min: 0.5, max: 16, step: 0.5, value: st.shape.lineWidth, format: (v) => `${v} pt`, onInput: (v) => { st.shape.lineWidth = v; this.settingsChanged(); } }).el,
          sep(), fillBtn,
          segmented([{ value: 'solid', label: 'Solid' }, { value: 'dashed', label: 'Dashed' }, { value: 'dotted', label: 'Dotted' }], st.shape.lineStyle, (v) => { st.shape.lineStyle = v; this.settingsChanged(); }, { label: 'Line style' }),
          sep(), h('span', { class: 'opt-hint' }, 'Draw a rough shape — it snaps when you lift.'));
        break;
      }
      case 'lasso': {
        const els = this.canvas?.selectedElements() || [];
        if (els.length) {
          const kinds = [...new Set(els.map(kindName))];
          bar.append(
            h('span', { class: 'opt-label strong' }, `${els.length} selected`), h('span', { class: 'opt-hint' }, kinds.slice(0, 3).join(', ')), sep(),
            iconButton('cut', 'Cut (⌘X)', () => this.cut(), { size: 18 }),
            iconButton('copy', 'Copy (⌘C)', () => this.copy(), { size: 18 }),
            iconButton('duplicate', 'Duplicate (⌘D)', () => this.duplicateSelection(), { size: 18 }),
            iconButton('trash', 'Delete (⌫)', () => this.deleteSelection(), { size: 18, cls: 'danger' }),
            els.length === 1 && els[0].type === 'image' ? h('button', { class: 'opt-btn', onclick: () => this.cropImage() }, icon('crop', 18), h('span', {}, 'Crop')) : null,
            sep(),
            els.some((e) => e.type !== 'image') ? this.colorStrip() : null,
            h('button', { class: 'opt-btn', onclick: (e) => this.showSelectionStyle(e.currentTarget) }, icon('sliders', 18), h('span', {}, 'Style')),
          );
        } else {
          bar.append(h('span', { class: 'opt-hint' }, 'Circle items to select them, or tap an item. Double-tap text to edit it.'));
        }
        if (clipboard?.elements?.length) bar.append(sep(), h('button', { class: 'opt-btn', onclick: () => this.paste() }, icon('paste', 18), h('span', {}, 'Paste')));
        break;
      }
      case 'text': {
        const t = st.text;
        const restyle = () => { this.settingsChanged(); this.canvas.restyleEditingText(t); };
        const font = selectField('text-font', FONT_FAMILIES.map((f) => ({ value: f.id, label: f.id })), t.fontFamily, (v) => { t.fontFamily = v; restyle(); });
        font.classList.add('compact');
        const size = h('input', { type: 'number', class: 'field compact num', id: 'text-size', min: 6, max: 144, value: t.fontSize, 'aria-label': 'Font size' });
        size.addEventListener('input', () => { const v = clamp(Number(size.value) || 18, 6, 144); t.fontSize = v; restyle(); });
        const bold = h('button', { class: `icon-btn ${t.bold ? 'on' : ''}`, 'aria-pressed': String(t.bold), title: 'Bold' }, icon('bold', 18));
        bold.addEventListener('click', () => { t.bold = !t.bold; bold.classList.toggle('on', t.bold); restyle(); });
        const italic = h('button', { class: `icon-btn ${t.italic ? 'on' : ''}`, 'aria-pressed': String(t.italic), title: 'Italic' }, icon('italic', 18));
        italic.addEventListener('click', () => { t.italic = !t.italic; italic.classList.toggle('on', t.italic); restyle(); });
        bar.append(font, size, h('span', { class: 'opt-label' }, 'pt'), sep(), this.colorStrip(), sep(), bold, italic,
          segmented([{ value: 'left', icon: 'alignLeft', title: 'Left' }, { value: 'center', icon: 'alignCenter', title: 'Center' }, { value: 'right', icon: 'alignRight', title: 'Right' }, { value: 'justified', icon: 'alignJustify', title: 'Justify' }], t.align, (v) => { t.align = v; restyle(); }, { label: 'Alignment' }),
          this.canvas?.textEdit ? h('button', { class: 'btn primary small', onclick: () => this.canvas.endTextEdit() }, 'Done') : h('span', { class: 'opt-hint' }, 'Tap the page to add text.'));
        break;
      }
    }
  }

  showPenSettings(anchor) {
    const isHL = this.settings.tool === 'highlighter';
    popover(anchor, (pop) => {
      pop.classList.add('pen-settings');
      const ink = this.activeInk;
      const preview = h('canvas', { class: 'stroke-preview', width: 640, height: 120, 'aria-hidden': 'true' });
      const drawPreview = () => {
        const ctx = preview.getContext('2d');
        ctx.setTransform(2, 0, 0, 2, 0, 0);
        ctx.clearRect(0, 0, 320, 60);
        ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, 320, 60);
        const pts = [];
        for (let k = 0; k <= 60; k++) {
          const t = k / 60;
          pts.push({ x: 20 + t * 280, y: 30 + Math.sin(t * Math.PI * 2) * 13, force: 0.08 + 0.5 * Math.sin(t * Math.PI), altitude: Math.PI / 2 - t * 1.1 });
        }
        fillStrokePath(ctx, buildStrokePath(packPoints(pts), this.activeInk), this.activeInk, false);
      };
      const changed = () => { this.settingsChanged(); drawPreview(); };
      const kindSel = isHL ? null : selectField('pen-kind', Object.entries(INK_KINDS).filter(([k]) => k !== 'highlighter').map(([k, v]) => ({ value: k, label: v.name })), ink.kind, (v) => { ink.kind = v; changed(); this.renderOptions(); });
      const range = INK_KINDS[ink.kind].range;
      pop.append(
        preview,
        kindSel ? h('label', { class: 'form-row', for: 'pen-kind' }, h('span', { class: 'form-label' }, 'Pen type'), kindSel) : null,
        h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Thickness'), slider('pen-w', { min: range[0], max: range[1], step: 0.1, value: ink.width, format: (v) => `${v.toFixed(1)} pt`, onInput: (v) => { ink.width = v; changed(); } }).el),
        h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Opacity'), slider('pen-o', { min: 0.1, max: 1, step: 0.01, value: ink.opacity, format: (v) => `${Math.round(v * 100)}%`, onInput: (v) => { ink.opacity = v; changed(); } }).el),
        isHL ? null : h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Pressure sensitivity'), slider('pen-p', { min: 0, max: 1, step: 0.01, value: ink.pressure, format: (v) => `${Math.round(v * 100)}%`, onInput: (v) => { ink.pressure = v; changed(); } }).el),
        isHL ? null : h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Tilt shading'), slider('pen-t', { min: 0, max: 1, step: 0.01, value: ink.tilt, format: (v) => `${Math.round(v * 100)}%`, onInput: (v) => { ink.tilt = v; changed(); } }).el),
        h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Line style'), segmented([{ value: 'solid', label: 'Solid' }, { value: 'dashed', label: 'Dashed' }, { value: 'dotted', label: 'Dotted' }], ink.lineStyle, (v) => { ink.lineStyle = v; changed(); })),
        h('button', { class: 'btn', onclick: async () => {
          const name = await askText({ title: 'Save Preset', value: INK_KINDS[ink.kind].name, confirm: 'Save' });
          if (name == null) return;
          storage.set('basis.penPresets', [...storage.get('basis.penPresets', []), { id: uuid(), name: name.trim() || 'Preset', style: structuredClone(ink) }]);
          toast('Preset saved');
        } }, icon('bookmark', 18), 'Save as Preset…'),
      );
      setTimeout(drawPreview, 0);
    }, { className: 'wide' });
  }

  // ---------- Selection ----------

  selectionChanged() {
    if (this.settings.tool === 'lasso') this.renderOptions();
  }

  textEditingChanged() {
    if (this.settings.tool === 'text') this.renderOptions();
  }

  applyToSelection(label, fn) {
    const sel = this.canvas.selection;
    if (!sel) return;
    this.canvas.commit(label, sel.pageId, (els) => els.map((e) => (sel.ids.has(e.id) ? fn(e) : e)));
    this.renderOptions();
  }

  showSelectionStyle(anchor) {
    popover(anchor, (pop) => {
      pop.classList.add('pen-settings');
      const els = this.canvas.selectedElements();
      const ink = els.filter((e) => e.type === 'stroke' || e.type === 'shape');
      const first = ink[0];
      if (first) {
        const w = first.type === 'stroke' ? first.style.width : first.style.lineWidth;
        pop.append(h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Thickness'),
          slider('sel-w', { min: 0.3, max: 40, step: 0.1, value: w, format: (v) => `${v.toFixed(1)} pt`, onInput: (v) => this.applyToSelection('Thickness', (e) => (e.type === 'stroke' ? { ...e, style: { ...e.style, width: v } } : e.type === 'shape' ? { ...e, style: { ...e.style, lineWidth: v } } : e)) }).el));
        const ls = first.style.lineStyle || 'solid';
        pop.append(h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Line style'),
          segmented([{ value: 'solid', label: 'Solid' }, { value: 'dashed', label: 'Dashed' }, { value: 'dotted', label: 'Dotted' }], ls, (v) => this.applyToSelection('Line Style', (e) => (e.type === 'stroke' || e.type === 'shape' ? { ...e, style: { ...e.style, lineStyle: v } } : e)))));
      }
      const op = els.find((e) => e.type !== 'text');
      if (op) {
        const o = op.type === 'image' ? op.opacity ?? 1 : op.style.opacity ?? 1;
        pop.append(h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Opacity'),
          slider('sel-o', { min: 0.1, max: 1, step: 0.01, value: o, format: (v) => `${Math.round(v * 100)}%`, onInput: (v) => this.applyToSelection('Opacity', (e) => (e.type === 'image' ? { ...e, opacity: v } : e.type === 'text' ? e : { ...e, style: { ...e.style, opacity: v } })) }).el));
      }
      const closed = els.filter((e) => e.type === 'shape' && isClosedShape(e));
      if (closed.length) {
        const f = closed[0].style.fill;
        pop.append(h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Fill'),
          segmented([{ value: 'none', label: 'None' }, { value: 'light', label: 'Light' }, { value: 'solid', label: 'Solid' }], !f ? 'none' : f.a < 0.5 ? 'light' : 'solid',
            (v) => this.applyToSelection('Fill', (e) => (e.type === 'shape' && isClosedShape(e) ? { ...e, style: { ...e.style, fill: v === 'none' ? null : { ...e.style.strokeColor, a: v === 'light' ? 0.18 : 1 } } } : e)))));
      }
      const lines = els.filter((e) => e.type === 'shape' && e.geom.kind === 'line');
      if (lines.length) {
        const a = lines[0].arrows || {};
        pop.append(h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Arrows'),
          segmented([{ value: 'none', label: 'None' }, { value: 'end', label: '→' }, { value: 'start', label: '←' }, { value: 'both', label: '↔' }], a.start && a.end ? 'both' : a.end ? 'end' : a.start ? 'start' : 'none',
            (v) => this.applyToSelection('Arrows', (e) => (e.type === 'shape' && e.geom.kind === 'line' ? { ...e, arrows: { start: v === 'start' || v === 'both', end: v === 'end' || v === 'both' } } : e)))));
      }
      pop.append(h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Arrange'),
        h('div', { class: 'row-actions' },
          h('button', { class: 'btn small', onclick: () => this.arrange(true) }, 'Bring to Front'),
          h('button', { class: 'btn small', onclick: () => this.arrange(false) }, 'Send to Back'))));
    }, { className: 'wide' });
  }

  arrange(front) {
    const sel = this.canvas.selection;
    if (!sel) return;
    this.canvas.commit(front ? 'Bring to Front' : 'Send to Back', sel.pageId, (els) => {
      const a = els.filter((e) => sel.ids.has(e.id)), b = els.filter((e) => !sel.ids.has(e.id));
      return front ? [...b, ...a] : [...a, ...b];
    });
  }

  copy() {
    const els = this.canvas.selectedElements();
    if (!els.length) return;
    clipboard = { elements: els.map((e) => structuredClone(e)) };
    toast(`Copied ${els.length} item${els.length === 1 ? '' : 's'}`);
    this.renderOptions();
  }

  cut() {
    this.copy();
    this.deleteSelection('Cut');
  }

  deleteSelection(label = 'Delete') {
    const sel = this.canvas.selection;
    if (!sel) return;
    this.canvas.commit(label, sel.pageId, (els) => els.filter((e) => !sel.ids.has(e.id)));
    this.canvas.clearSelection();
  }

  duplicateSelection() {
    const sel = this.canvas.selection;
    if (!sel) return;
    const copies = this.canvas.selectedElements().map((e) => transformElement(withNewId(e), translateT(18, 18)));
    this.canvas.commit('Duplicate', sel.pageId, (els) => [...els, ...copies]);
    this.canvas.setSelection(sel.pageId, copies.map((e) => e.id));
  }

  paste() {
    if (!clipboard?.elements?.length) return;
    const { page, p } = this.canvas.visibleCenter();
    let r = null;
    for (const e of clipboard.elements) {
      const b = elementBounds(e);
      r = r ? { x: Math.min(r.x, b.x), y: Math.min(r.y, b.y), x2: Math.max(r.x2, b.x + b.w), y2: Math.max(r.y2, b.y + b.h) } : { x: b.x, y: b.y, x2: b.x + b.w, y2: b.y + b.h };
    }
    const t = translateT(p.x - (r.x + r.x2) / 2, p.y - (r.y + r.y2) / 2);
    const copies = clipboard.elements.map((e) => transformElement(withNewId(e), t));
    if (this.settings.tool !== 'lasso') this.selectTool('lasso');
    this.canvas.commit('Paste', page.id, (els) => [...els, ...copies]);
    this.canvas.setSelection(page.id, copies.map((e) => e.id));
  }

  // ---------- Undo ----------

  undo() {
    this.canvas.cancelInteraction();
    this.canvas.endTextEdit();
    this.canvas.clearSelection();
    if (this.history.undo()) this.afterHistory();
  }

  redo() {
    this.canvas.cancelInteraction();
    this.canvas.endTextEdit();
    this.canvas.clearSelection();
    if (this.history.redo()) this.afterHistory();
  }

  afterHistory() {
    this.canvas.layout();
    this.canvas.clampView();
    this.canvas.requestRender();
    this.documentChanged();
  }

  // ---------- Keyboard ----------

  handleKey(e) {
    if (!this.root.isConnected || document.querySelector('.sheet')) return;
    const t = e.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable)) return;
    const mod = e.metaKey || e.ctrlKey;
    const k = e.key.toLowerCase();
    if (mod && k === 'z') { e.preventDefault(); if (e.shiftKey) this.redo(); else this.undo(); return; }
    if (mod && k === 'y') { e.preventDefault(); this.redo(); return; }
    if (mod && k === 'c') { if (this.canvas.selection) { e.preventDefault(); this.copy(); } return; }
    if (mod && k === 'x') { if (this.canvas.selection) { e.preventDefault(); this.cut(); } return; }
    if (mod && k === 'v') { if (clipboard) { e.preventDefault(); this.paste(); } return; }
    if (mod && k === 'd') { if (this.canvas.selection) { e.preventDefault(); this.duplicateSelection(); } return; }
    if (mod && k === 'a' && this.settings.tool === 'lasso') {
      e.preventDefault();
      const page = this.doc.pages[this.canvas.currentPageIndex];
      this.canvas.setSelection(page.id, page.elements.map((x) => x.id));
      return;
    }
    if (mod && k === 'f') { e.preventDefault(); this.findInNotebook(); return; }
    if (mod && (k === '=' || k === '+')) { e.preventDefault(); this.canvas.zoomBy(1.25); return; }
    if (mod && k === '-') { e.preventDefault(); this.canvas.zoomBy(0.8); return; }
    if (mod && k === '0') { e.preventDefault(); this.canvas.fitWidth(); return; }
    if (mod) return;
    if ((k === 'backspace' || k === 'delete') && this.canvas.selection) { e.preventDefault(); this.deleteSelection(); return; }
    if (k === 'escape') { this.canvas.clearSelection(); return; }
    const tool = TOOLS.find((x) => x.key === e.key);
    if (tool) { this.selectTool(tool.id); return; }
    if (k === 'e') { this.selectTool(this.settings.tool === 'eraser' ? this.previousTool || 'pen' : 'eraser'); return; }
    if (k === 'k') { this.toggleCalculator(); return; }
    if (k === 'pagedown') { this.canvas.scrollToPage(this.canvas.currentPageIndex + 1); return; }
    if (k === 'pageup') { this.canvas.scrollToPage(this.canvas.currentPageIndex - 1); }
  }

  // ---------- Pages ----------

  blankPageLike(index) {
    const ref = this.doc.pages[clamp(index, 0, this.doc.pages.length - 1)];
    const bg = { ...structuredClone(ref.background), image: null, pdf: null, section: null };
    return makePage({ w: ref.w, h: ref.h }, bg);
  }

  addPage(after = this.canvas.currentPageIndex, { animate = false } = {}) {
    const page = this.blankPageLike(after);
    this.history.perform('Add Page', (pages) => [...pages.slice(0, after + 1), page, ...pages.slice(after + 1)]);
    this.afterHistory();
    if (animate) this.canvas.animateView({ y: this.canvas.tops[after + 1] - 16 / this.canvas.view.zoom });
    else this.canvas.scrollToPage(after + 1);
  }

  duplicatePage(i) {
    const p = this.doc.pages[i];
    const copy = { ...structuredClone({ ...p, elements: [] }), id: uuid(), elements: p.elements.map(withNewId) };
    copy.background.section = null;
    this.history.perform('Duplicate Page', (pages) => [...pages.slice(0, i + 1), copy, ...pages.slice(i + 1)]);
    this.afterHistory();
  }

  deletePage(i) {
    if (this.doc.pages.length <= 1) { toast('A notebook needs at least one page.'); return; }
    this.canvas.clearSelection();
    this.history.perform('Delete Page', (pages) => pages.filter((_, k) => k !== i));
    this.afterHistory();
  }

  movePage(from, to) {
    if (from === to || to < 0 || to >= this.doc.pages.length) return;
    this.history.perform('Move Page', (pages) => {
      const out = pages.slice();
      const [p] = out.splice(from, 1);
      out.splice(to, 0, p);
      return out;
    });
    this.afterHistory();
  }

  setSection(i, title) {
    const t = title?.trim() || null;
    const page = this.doc.pages[i];
    if ((page.background.section || null) === t) return;
    this.history.perform(t ? 'Section' : 'Remove Section', (pages) => updatePage(pages, page.id, (p) => ({ ...p, background: { ...p.background, section: t } })));
    this.afterHistory();
  }

  showPageManager() {
    sheet({
      title: 'Pages',
      wide: true,
      build: (body, close) => {
        const grid = h('div', { class: 'page-grid' });
        body.append(grid);
        const render = () => {
          const cur = this.canvas.currentPageIndex;
          const secs = this.sections();
          grid.replaceChildren(...this.doc.pages.map((p, i) => {
            const scale = 150 / Math.max(p.w, p.h * 0.75);
            const thumb = renderPageCanvas(p, scale * (window.devicePixelRatio || 1), 600000);
            thumb.className = 'page-thumb-canvas';
            const more = iconButton('more', `Page ${i + 1} actions`, () => menu(more, [
              { label: 'Add Page After', icon: 'plus', action: () => { this.addPage(i); render(); } },
              { label: 'Duplicate', icon: 'duplicate', action: () => { this.duplicatePage(i); render(); } },
              { label: p.background.section ? 'Rename Section…' : 'Start Section Here…', icon: 'bookmark', action: async () => { const t = await askText({ title: 'Section', label: 'Section title', value: p.background.section || '', confirm: 'Save' }); if (t != null) { this.setSection(i, t); render(); } } },
              p.background.section ? { label: 'Remove Section', action: () => { this.setSection(i, null); render(); } } : null,
              'sep',
              { label: 'Move Up', icon: 'arrowUp', disabled: i === 0, action: () => { this.movePage(i, i - 1); render(); } },
              { label: 'Move Down', icon: 'arrowDown', disabled: i === this.doc.pages.length - 1, action: () => { this.movePage(i, i + 1); render(); } },
              'sep',
              { label: 'Delete Page', icon: 'trash', danger: true, disabled: this.doc.pages.length <= 1, action: async () => { if (await confirmDialog({ title: `Delete page ${i + 1}?`, message: 'You can undo this from the toolbar.' })) { this.deletePage(i); render(); } } },
            ], { align: 'end' }), { cls: 'small' });
            const section = secs.find((s) => s.start === i);
            const card = h('div', { class: `page-card ${i === cur ? 'on' : ''}`, draggable: 'true' },
              h('button', { class: 'page-thumb', 'aria-label': `Go to page ${i + 1}`, onclick: () => { close(); this.canvas.scrollToPage(i); } }, thumb),
              h('div', { class: 'page-card-foot' }, h('span', { class: 'mono' }, String(i + 1)), section ? h('span', { class: 'section-chip' }, icon('bookmark', 12), section.title) : h('span'), more));
            card.addEventListener('dragstart', (e) => { e.dataTransfer.setData('text/plain', String(i)); card.classList.add('dragging'); });
            card.addEventListener('dragend', () => card.classList.remove('dragging'));
            card.addEventListener('dragover', (e) => { e.preventDefault(); card.classList.add('drop'); });
            card.addEventListener('dragleave', () => card.classList.remove('drop'));
            card.addEventListener('drop', (e) => { e.preventDefault(); const from = Number(e.dataTransfer.getData('text/plain')); this.movePage(from, i); render(); });
            return card;
          }), h('button', { class: 'page-card add', onclick: () => { this.addPage(this.doc.pages.length - 1); render(); } }, icon('plus', 28), h('span', {}, 'Add Page')));
        };
        render();
      },
    });
  }

  showPageSettings() {
    const page = this.doc.pages[this.canvas.currentPageIndex];
    const match = matchPaper({ w: page.w, h: page.h });
    const state = {
      paper: match?.paper.id || 'custom',
      orientation: match?.orientation || (page.w > page.h ? 'landscape' : 'portrait'),
      w: page.w, h: page.h,
      bg: structuredClone(page.background),
      all: false,
    };
    sheet({
      title: 'Page Settings',
      wide: true,
      actions: {
        confirm: 'Apply',
        onConfirm: () => {
          const size = state.paper === 'custom' ? { w: clamp(state.w, 72, 14400), h: clamp(state.h, 72, 14400) } : sizeFor(PAPER_SIZES.find((p) => p.id === state.paper), state.orientation);
          this.applyPageSettings(size, state.bg, state.all);
          return true;
        },
      },
      build: (body) => {
        const preview = h('canvas', { class: 'template-preview', 'aria-hidden': 'true' });
        const drawPreview = () => {
          const size = state.paper === 'custom' ? { w: state.w, h: state.h } : sizeFor(PAPER_SIZES.find((p) => p.id === state.paper), state.orientation);
          const c = renderPageCanvas({ w: size.w, h: size.h, background: { ...state.bg, image: null }, elements: [] }, 180 / Math.max(size.w, size.h) * 2, 400000);
          preview.width = c.width; preview.height = c.height;
          preview.getContext('2d').drawImage(c, 0, 0);
          preview.style.aspectRatio = `${size.w} / ${size.h}`;
        };
        const paperSel = selectField('ps-paper', [
          ...['Paper', 'Screen', 'Other'].map((cat) => ({ group: cat, options: PAPER_SIZES.filter((p) => p.cat === cat).map((p) => ({ value: p.id, label: `${p.name} · ${p.sub}` })) })),
          { group: 'Custom', options: [{ value: 'custom', label: 'Custom size…' }] },
        ], state.paper, (v) => { state.paper = v; customRow.hidden = v !== 'custom'; drawPreview(); });
        const wIn = h('input', { type: 'number', class: 'field num', id: 'ps-w', value: Math.round(state.w), min: 72, max: 14400, 'aria-label': 'Width in points' });
        const hIn = h('input', { type: 'number', class: 'field num', id: 'ps-h', value: Math.round(state.h), min: 72, max: 14400, 'aria-label': 'Height in points' });
        wIn.addEventListener('input', () => { state.w = Number(wIn.value) || state.w; drawPreview(); });
        hIn.addEventListener('input', () => { state.h = Number(hIn.value) || state.h; drawPreview(); });
        const customRow = h('div', { class: 'form-row inline', hidden: state.paper !== 'custom' }, wIn, h('span', {}, '×'), hIn, h('span', { class: 'muted' }, 'pt (72 pt = 1 in)'));
        const orient = segmented([{ value: 'portrait', label: 'Portrait' }, { value: 'landscape', label: 'Landscape' }], state.orientation, (v) => { state.orientation = v; drawPreview(); });
        const templates = h('div', { class: 'template-grid', role: 'radiogroup', 'aria-label': 'Template' });
        const spacing = slider('ps-spacing', { min: 6, max: 96, step: 1, value: state.bg.spacing, format: (v) => `${v} pt`, onInput: (v) => { state.bg.spacing = v; drawPreview(); } });
        const renderTemplates = () => templates.replaceChildren(...TEMPLATES.map((t) => {
          const c = renderPageCanvas({ w: 120, h: 156, background: { ...state.bg, template: t.id, spacing: t.id === 'engineering' ? 36 : t.spacing * 0.6, image: null }, elements: [] }, 1, 50000);
          c.className = 'template-thumb';
          const b = h('button', { class: `template-btn ${state.bg.template === t.id ? 'on' : ''}`, role: 'radio', 'aria-checked': String(state.bg.template === t.id) }, c, h('span', {}, t.name));
          b.addEventListener('click', () => { state.bg.template = t.id; state.bg.spacing = t.spacing; spacing.set(t.spacing); renderTemplates(); drawPreview(); });
          return b;
        }));
        const colors = swatches(PAPER_COLORS.map((p) => p.c), state.bg.color, (c) => { state.bg.color = { ...c, a: 1 }; renderTemplates(); drawPreview(); });
        renderTemplates();
        body.append(
          h('div', { class: 'settings-split' },
            h('div', { class: 'settings-form' },
              h('label', { class: 'form-row', for: 'ps-paper' }, h('span', { class: 'form-label' }, 'Size'), paperSel),
              customRow,
              h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Orientation'), orient),
              h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Paper color'), colors),
              h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Template'), templates),
              h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Line spacing'), spacing.el),
              toggle('ps-endless', 'Endless page (grows as you write)', !!state.bg.autoExtends, (v) => { state.bg.autoExtends = v; }),
              toggle('ps-all', `Apply to all ${this.doc.pages.length} pages`, false, (v) => { state.all = v; }),
            ),
            h('div', { class: 'settings-preview' }, preview, h('p', { class: 'muted small' }, 'Imported PDF pages keep their size and content.'))),
        );
        drawPreview();
      },
    });
  }

  applyPageSettings(size, bg, all) {
    const cur = this.doc.pages[this.canvas.currentPageIndex];
    this.history.perform('Page Settings', (pages) => pages.map((p) => {
      if (!all && p.id !== cur.id) return p;
      const background = { ...structuredClone(bg), section: p.background.section, image: p.background.image, pdf: p.background.pdf ?? null };
      if (p.background.image) return { ...p, background };
      return { ...p, w: size.w, h: size.h, background };
    }));
    this.afterHistory();
  }

  // ---------- Menus & inserts ----------

  // ---------- Crop ----------

  /** Crops the selected image. Non-destructive: the whole image is kept, so it can be re-cropped or reset. */
  async cropImage() {
    const sel = this.canvas.selection;
    const el = this.canvas.selectedElements()[0];
    if (!sel || !el || el.type !== 'image') return;
    const url = (await store.assetURL(el.asset)) || (await store.assetDataURL(el.asset));
    if (!url) { toast('This image couldn’t be loaded.'); return; }
    const full = { x: 0, y: 0, w: 1, h: 1 };
    let r = { ...(el.crop || full) };
    const img = h('img', { class: 'crop-img', src: url, alt: '', draggable: 'false' });
    const box = h('div', { class: 'crop-box' }, ...['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'].map((d) => h('span', { class: `crop-handle ${d}`, 'data-dir': d })));
    const stage = h('div', { class: 'crop-stage' }, h('div', { class: 'crop-inner' }, img, box));
    const place = () => Object.assign(box.style, { left: r.x * 100 + '%', top: r.y * 100 + '%', width: r.w * 100 + '%', height: r.h * 100 + '%' });
    place();
    const MIN = 0.03;
    box.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      box.setPointerCapture(e.pointerId);
      const dir = e.target.dataset.dir || 'move';
      const W = img.clientWidth, H = img.clientHeight, x0 = e.clientX, y0 = e.clientY, start = { ...r };
      const onMove = (m) => {
        const dx = (m.clientX - x0) / W, dy = (m.clientY - y0) / H;
        let { x, y, w, h: hh } = start;
        if (dir === 'move') {
          x = clamp(x + dx, 0, 1 - w); y = clamp(y + dy, 0, 1 - hh);
        } else {
          if (dir.includes('w')) { const nx = clamp(x + dx, 0, x + w - MIN); w += x - nx; x = nx; }
          if (dir.includes('e')) w = clamp(w + dx, MIN, 1 - x);
          if (dir.includes('n')) { const ny = clamp(y + dy, 0, y + hh - MIN); hh += y - ny; y = ny; }
          if (dir.includes('s')) hh = clamp(hh + dy, MIN, 1 - y);
        }
        r = { x, y, w, h: hh };
        place();
      };
      const onUp = () => { box.removeEventListener('pointermove', onMove); box.removeEventListener('pointerup', onUp); box.removeEventListener('pointercancel', onUp); };
      box.addEventListener('pointermove', onMove);
      box.addEventListener('pointerup', onUp);
      box.addEventListener('pointercancel', onUp);
    });
    const apply = () => {
      const c0 = el.crop || full;
      const round = (v) => Math.round(v * 1e4) / 1e4;
      const c1 = { x: round(r.x), y: round(r.y), w: round(r.w), h: round(r.h) };
      if (['x', 'y', 'w', 'h'].every((k) => Math.abs(c1[k] - c0[k]) < 1e-4)) return;
      // Keep the visible part where it is on the page: the box shrinks or grows around it.
      const b = el.box, sx = b.w / c0.w, sy = b.h / c0.h;
      const dx = (c1.x + c1.w / 2 - (c0.x + c0.w / 2)) * sx, dy = (c1.y + c1.h / 2 - (c0.y + c0.h / 2)) * sy;
      const rot = b.rot || 0, cos = Math.cos(rot), sin = Math.sin(rot);
      const nb = { ...b, cx: b.cx + dx * cos - dy * sin, cy: b.cy + dx * sin + dy * cos, w: c1.w * sx, h: c1.h * sy };
      const isFull = c1.x <= 1e-4 && c1.y <= 1e-4 && c1.w >= 0.9999 && c1.h >= 0.9999;
      this.canvas.commit('Crop', sel.pageId, (els) => els.map((x) => {
        if (x.id !== el.id) return x;
        const { crop, ...rest } = x;
        return isFull ? { ...rest, box: nb } : { ...rest, crop: c1, box: nb };
      }));
      this.canvas.setSelection(sel.pageId, [el.id]);
    };
    sheet({
      title: 'Crop Image',
      wide: true,
      actions: { confirm: 'Done', onConfirm: () => { apply(); } },
      build: (body) => body.append(
        h('div', { class: 'crop-wrap' }, stage),
        h('div', { class: 'crop-foot' },
          h('span', { class: 'muted small' }, 'Drag the corners or edges to crop. Drag inside to move the frame.'),
          h('button', { class: 'btn ghost small', onclick: () => { r = { ...full }; place(); } }, 'Reset'))),
    });
  }

  // ---------- Search ----------

  /** Search typed text, calculation cards, recognized handwriting and PDF text; tap a result to go to its page. */
  findInNotebook() {
    const doc = this.doc;
    const input = h('input', { class: 'field search', type: 'search', id: 'find-in-notebook', placeholder: 'Find in this notebook', 'aria-label': 'Find in this notebook' });
    const results = h('div', { class: 'find-results' });
    const ai = aiAvailable();
    const unread = () => doc.pages.filter((p) => hasContent(p) && !doc.ocr?.[p.id]).length;
    const footer = h('p', { class: 'muted small' });
    const renderFooter = () => {
      const n = unread();
      footer.textContent = !ai
        ? 'Finds typed text, calculation cards and text in PDFs. Connect AI in the AI tab to search handwriting too.'
        : n ? `Handwriting on ${n} page${n === 1 ? '' : 's'} hasn’t been read yet. Use Make Notebook Searchable in the ⋯ menu.` : 'Finds handwriting, typed text, calculation cards and PDF text.';
    };
    sheet({
      title: 'Find in Notebook',
      build: (body, close) => {
        const render = () => {
          const q = input.value.trim();
          if (!q) { results.replaceChildren(); return; }
          const hits = findInDocument(doc, q);
          results.replaceChildren(...(hits.length ? hits.map((x) => h('button', { class: 'find-hit', onclick: () => { close(); this.canvas.scrollToPage(x.page); } },
            h('span', { class: 'find-page' }, `Page ${x.page + 1}`, h('span', { class: 'muted small' }, ` · ${x.kind}`)),
            h('span', { class: 'snippet' }, x.snippet[0], h('mark', {}, x.snippet[1]), x.snippet[2]))) : [h('p', { class: 'muted' }, `Nothing on these pages matches “${q}”.`)]));
        };
        input.addEventListener('input', render);
        body.append(input, results, footer);
        renderFooter();
        // PDF text layers are read once, then kept with the notebook.
        (async () => {
          let added = false;
          for (const p of doc.pages) {
            if (!p.background.pdf || doc.pdfText?.[p.id] != null) continue;
            try { (doc.pdfText ||= {})[p.id] = await pdfPageText(p.background.pdf); added = true; } catch { /* unreadable PDF: skip */ }
          }
          if (added) { this.save(); render(); }
        })();
      },
    });
  }

  /** Reads every page that hasn't been read yet, after showing roughly what it costs. */
  async makeSearchable() {
    const cfg = aiConfig();
    if (!cfg) return;
    const pages = this.recognizer.pending({ all: true });
    if (!pages.length) { toast('Every page in this notebook is already searchable.'); return; }
    const pieces = pages.reduce((n, p) => n + pageChunks(p).length, 0);
    const per = { 'claude-opus-5-5': 0.02, 'claude-sonnet-5-5': 0.01, 'claude-haiku-5-5': 0.002 }[cfg.model];
    const cost = cfg.provider === 'gemini'
      ? 'On Gemini’s free tier this is usually free, within its daily limits.'
      : `This will cost roughly $${Math.max(0.01, pieces * per).toFixed(2)} on your Anthropic account.`;
    const ok = await confirmDialog({
      title: 'Make Notebook Searchable?',
      message: `${PROVIDERS[cfg.provider].name} will read the handwriting on ${pages.length} page${pages.length === 1 ? '' : 's'} so you can search it. ${cost} Keep this notebook open until it finishes.`,
      confirm: 'Read Pages', destructive: false,
    });
    if (!ok) return;
    const { done, failed, error } = await this.recognizer.run({ all: true, onProgress: (n, total) => toast(`Reading page ${n} of ${total}…`) });
    if (!failed) { if (done) toast(`Done. ${done} page${done === 1 ? ' is' : 's are'} now searchable.`); return; }
    // Keep the reason on screen (toasts vanish) so it can be fixed.
    sheet({
      title: done ? 'Some Pages Couldn’t Be Read' : 'Pages Couldn’t Be Read',
      className: 'compact',
      build: (body, close) => body.append(
        h('p', { class: 'dialog-message' }, `${done ? `Read ${done} page${done === 1 ? '' : 's'}. ` : ''}${failed} page${failed === 1 ? '' : 's'} couldn’t be read.`),
        h('p', { class: 'dialog-message' }, h('b', {}, 'Reason: '), error),
        h('p', { class: 'muted small' }, 'You can check your key with Test Connection in the AI tab, then try again.'),
        h('div', { class: 'dialog-actions' }, h('button', { class: 'btn primary', onclick: () => close(true) }, 'OK'))),
    });
  }

  showMoreMenu(anchor) {
    const st = this.settings;
    menu(anchor, [
      { label: 'Add Page', icon: 'plus', action: () => this.addPage() },
      { label: 'Insert Calculation Card…', icon: 'function', action: () => this.newCalculation() },
      { label: 'Insert Image…', icon: 'image', action: () => this.insertImage() },
      { label: 'Import PDF Pages…', icon: 'import', action: () => this.importPDFPages() },
      'sep',
      { label: 'Find in Notebook…', icon: 'search', hint: '⌘F', action: () => this.findInNotebook() },
      aiAvailable() ? { label: 'Make Notebook Searchable…', icon: 'sparkle', action: () => this.makeSearchable() } : null,
      'sep',
      { label: 'Export PDF', icon: 'export', action: () => this.exportPDF() },
      { label: 'Export Page as PNG', icon: 'export', action: () => this.exportPNG() },
      { label: 'Export as Basis Notebook (.basis)', icon: 'export', action: () => this.exportBasisFile() },
      'sep',
      { label: 'Scribble to Erase', checked: st.scribbleToErase !== false, action: () => { st.scribbleToErase = st.scribbleToErase === false; this.settingsChanged(); this.renderOptions(); toast(st.scribbleToErase ? 'Scribble quickly over ink with the pen to erase it.' : 'Scribble to erase is off.'); } },
      { header: 'Scribble erases' },
      ...SCRIBBLE_MODES.map((m) => ({ label: m.label, checked: (st.scribbleMode || 'strokes') === m.value, action: () => { st.scribbleMode = m.value; this.settingsChanged(); this.renderOptions(); } })),
      'sep',
      { label: 'Hold to Snap Shapes', checked: st.holdToSnap, keepOpen: false, action: () => { st.holdToSnap = !st.holdToSnap; this.settingsChanged(); this.renderOptions(); } },
      { label: 'Draw with Finger', checked: st.fingerDrawing, action: () => { st.fingerDrawing = !st.fingerDrawing; this.canvas.penSeen = false; this.settingsChanged(); toast(st.fingerDrawing ? 'One finger draws; two fingers scroll and zoom.' : 'One finger scrolls; draw with a pen or mouse.'); } },
      { header: 'Hold duration' },
      ...[[0.35, 'Short (0.35 s)'], [0.5, 'Medium (0.5 s)'], [0.8, 'Long (0.8 s)']].map(([v, label]) => ({ label, checked: st.holdDuration === v, action: () => { st.holdDuration = v; this.settingsChanged(); } })),
    ], { align: 'end' });
  }

  async insertImage(file) {
    if (!file) [file] = await pickFile('image/*');
    if (!file) return;
    const img = new Image();
    const url = URL.createObjectURL(file);
    try {
      await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = url; });
    } catch { toast('That image couldn’t be read.'); return; }
    // Downscale very large photos before storing.
    let blob = file;
    const maxSide = 2400;
    if (Math.max(img.naturalWidth, img.naturalHeight) > maxSide || file.size > 3e6) {
      const s = Math.min(1, maxSide / Math.max(img.naturalWidth, img.naturalHeight));
      const c = document.createElement('canvas');
      c.width = Math.round(img.naturalWidth * s); c.height = Math.round(img.naturalHeight * s);
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      blob = await new Promise((r) => c.toBlob(r, file.type === 'image/png' ? 'image/png' : 'image/jpeg', 0.9));
    }
    URL.revokeObjectURL(url);
    const asset = await store.putAsset(blob);
    const { page, p } = this.canvas.visibleCenter();
    const maxW = page.w * 0.6, maxH = page.h * 0.5;
    const s = Math.min(1, maxW / img.naturalWidth, maxH / img.naturalHeight);
    const el = { type: 'image', id: uuid(), asset, box: { cx: p.x, cy: p.y, w: img.naturalWidth * s, h: img.naturalHeight * s, rot: 0 }, opacity: 1 };
    this.canvas.insertElement(el, 'Insert Image');
  }

  async importPDFPages() {
    const [file] = await pickFile('application/pdf');
    if (!file) return;
    toast('Importing PDF…');
    try {
      const imported = await importPDF(file, (n, total) => toast(`Importing page ${n} of ${total}…`));
      const at = this.canvas.currentPageIndex + 1;
      const ref = this.doc.pages[this.canvas.currentPageIndex].background;
      const pages = imported.map((x) => makePage({ w: x.w, h: x.h }, { ...makeBackground('blank', ref.color), image: x.asset, pdf: x.pdf, color: { r: 1, g: 1, b: 1, a: 1 } }));
      this.history.perform('Import PDF', (ps) => [...ps.slice(0, at), ...pages, ...ps.slice(at)]);
      this.afterHistory();
      this.canvas.scrollToPage(at);
      toast(`Imported ${pages.length} page${pages.length === 1 ? '' : 's'}`);
    } catch (e) {
      toast(e.message || 'That PDF couldn’t be imported.');
    }
  }

  async exportPDF() {
    await this.saveNow();
    toast('Preparing PDF…');
    try {
      const blob = await exportPDF(this.doc, (n, t) => toast(`Rendering page ${n} of ${t}…`));
      if (saveFile(blob, `${this.doc.title || 'Notebook'}.pdf`)) toast('PDF exported');
    } catch (e) { toast(e.message || 'Export failed.'); }
  }

  async exportBasisFile() {
    await this.saveNow();
    toast('Preparing notebook…');
    try {
      const blob = await exportBasis(this.doc, (n, t) => toast(`Packing page ${n} of ${t}…`));
      if (saveFile(blob, `${safeFileName(this.doc.title)}.basis`)) toast('Notebook exported');
    } catch (e) { toast(e.message || 'Export failed.'); }
  }

  async exportPNG() {
    const page = this.doc.pages[this.canvas.currentPageIndex];
    const blob = await exportPNG(page);
    if (saveFile(blob, `${this.doc.title || 'Notebook'} – page ${this.canvas.currentPageIndex + 1}.png`)) toast('Image exported');
  }

  // ---------- Calculations ----------

  toggleCalculator(force) {
    const show = force ?? !this.floatCalc;
    storage.set('basis.floatingCalc', show);
    this.calcBtn.classList.toggle('on', show);
    if (!show) { this.floatCalc?.remove(); this.floatCalc = null; this.floatPad = null; return; }
    if (this.floatCalc) return;
    const pos = storage.get('basis.floatingCalcPos', { x: 0.62, y: 0.06 });
    let collapsed = storage.get('basis.floatingCalcCollapsed', false);
    this.floatPad = calculatorPad({ compact: true, onInsert: (expr) => this.insertCalculation(expr) });
    const collapseBtn = iconButton(collapsed ? 'chevronDown' : 'chevronUp', collapsed ? 'Expand' : 'Collapse', () => {
      collapsed = !collapsed;
      storage.set('basis.floatingCalcCollapsed', collapsed);
      this.floatPad.hidden = collapsed;
      collapseBtn.replaceChildren(icon(collapsed ? 'chevronDown' : 'chevronUp', 18));
    }, { size: 18, cls: 'small' });
    const handle = h('div', { class: 'float-calc-head' }, h('span', { class: 'grip' }), h('span', { class: 'float-calc-title' }, 'Calculator'), collapseBtn, iconButton('close', 'Hide calculator', () => this.toggleCalculator(false), { size: 18, cls: 'small' }));
    this.floatPad.hidden = collapsed;
    this.floatCalc = h('div', { class: 'float-calc', role: 'dialog', 'aria-label': 'Calculator' }, handle, this.floatPad);
    this.canvasHost.append(this.floatCalc);
    const place = () => {
      const W = this.canvasHost.clientWidth, H = this.canvasHost.clientHeight, w = this.floatCalc.offsetWidth;
      this.floatCalc.style.left = clamp(pos.x * W, 0, Math.max(0, W - w)) + 'px';
      this.floatCalc.style.top = clamp(pos.y * H, 0, Math.max(0, H - 60)) + 'px';
    };
    place();
    let drag = null;
    handle.addEventListener('pointerdown', (e) => {
      if (e.target.closest('button')) return;
      handle.setPointerCapture(e.pointerId);
      drag = { x: e.clientX, y: e.clientY, left: this.floatCalc.offsetLeft, top: this.floatCalc.offsetTop };
    });
    handle.addEventListener('pointermove', (e) => {
      if (!drag) return;
      const W = this.canvasHost.clientWidth, H = this.canvasHost.clientHeight;
      const x = clamp(drag.left + e.clientX - drag.x, 0, W - this.floatCalc.offsetWidth), y = clamp(drag.top + e.clientY - drag.y, 0, H - 60);
      this.floatCalc.style.left = x + 'px'; this.floatCalc.style.top = y + 'px';
      pos.x = x / W; pos.y = y / H;
    });
    handle.addEventListener('pointerup', () => { drag = null; storage.set('basis.floatingCalcPos', pos); });
  }

  cardStyle() {
    const t = this.settings.text;
    return { fontFamily: 'Mono', fontSize: 15, color: this.settings.pen.color.r + this.settings.pen.color.g + this.settings.pen.color.b > 2.7 ? t.color : { ...this.settings.pen.color, a: 1 }, bold: false, italic: false, align: 'left' };
  }

  /** Inserts a live calculation card. */
  insertCalculation(source, at) {
    const text = calc.renderCard(source);
    const style = this.cardStyle();
    const w = Math.min(420, Math.ceil(naturalTextWidth(text, style)) + 4);
    const lay = layoutText(text, style, w);
    const { page, p } = at || this.canvas.visibleCenter();
    const el = { type: 'text', id: uuid(), text, style, calc: { source }, box: { cx: Math.min(p.x, page.w - w / 2 - 12), cy: p.y, w, h: lay.height, rot: 0 } };
    this.canvas.insertElement(el, 'Insert Calculation');
  }

  newCalculation(initial = '') { this.calculationSheet(initial, null); }

  editCalculation(pageId, el) { this.calculationSheet(el.calc.source, { pageId, el }); }

  calculationSheet(source, existing) {
    const input = h('textarea', { class: 'field mono', id: 'calc-card-src', rows: 5, spellcheck: 'false', placeholder: 'One calculation per line, e.g.\nm = 2\nv = 3\nKE = ½ m v²' }, source);
    const preview = h('pre', { class: 'calc-card-preview', 'aria-live': 'polite' });
    const refresh = () => { preview.textContent = input.value.trim() ? calc.renderCard(input.value) : 'Results appear here.'; };
    input.addEventListener('input', refresh);
    sheet({
      title: existing ? 'Edit Calculation' : 'Calculation Card',
      actions: {
        confirm: existing ? 'Update' : 'Insert',
        onConfirm: () => {
          const src = input.value.trim();
          if (!src) return true;
          if (existing) {
            const text = calc.renderCard(src);
            const style = existing.el.style;
            const w = Math.max(existing.el.box.w, Math.min(460, Math.ceil(naturalTextWidth(text, style)) + 4));
            const lay = layoutText(text, style, w);
            const b = existing.el.box;
            const el = { ...existing.el, text, calc: { source: src }, box: { ...b, w, h: lay.height, cx: b.cx + (w - b.w) / 2, cy: b.cy + (lay.height - b.h) / 2 } };
            this.canvas.commit('Edit Calculation', existing.pageId, (els) => els.map((x) => (x.id === el.id ? el : x)));
          } else this.insertCalculation(src);
          return true;
        },
      },
      build: (body) => {
        body.append(input, h('h3', { class: 'section-label' }, 'Preview'), preview,
          h('p', { class: 'muted small' }, 'Cards recalculate when you edit them. Calculator variables and saved formulas work here too.'));
        refresh();
      },
    });
  }
}

export function safeFileName(name) {
  const s = String(name || '').replace(/[\/:*?"<>|]/g, '-').trim().replace(/^\.+/, '');
  return (s || 'Untitled').slice(0, 120);
}

function noteRecentColor(c) {
  const list = storage.get('basis.recentColors', []).filter((x) => !colorsClose(x, c));
  const all = [...INK_PALETTE, ...HIGHLIGHTER_PALETTE];
  if (all.some((p) => colorsClose(p, c))) return;
  storage.set('basis.recentColors', [c, ...list].slice(0, 8));
}

export { describeSize, hexToRgba };
