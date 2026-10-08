// App shell: sidebar + screens, open notebooks (tabs), preferences.

import { h, storage, hexToRgba, isLight } from './util.js';
import { icon } from './icons.js';
import { toast, closePopovers } from './ui.js';
import { store } from './store.js';
import { Editor } from './editor.js';
import { sidebar, libraryScreen, searchScreen, settingsScreen, newNotebookSheet, importGoodNotesFiles } from './library.js';
import { initTutorial, shouldShowWelcome, shouldShowEditorTour, resetTutorial, welcomeTour, editorTour } from './tour.js';
import { feature } from './features.js';
import { aiScreen } from './aiscreen.js';
import { calculatorScreen, formulasScreen, unitConverterScreen, historyScreen, graphScreen } from './calculator.js';

class App {
  constructor(root) {
    this.root = root;
    this.prefs = storage.get('basis.prefs', { accent: null, theme: 'system' });
    this.route = storage.get('basis.route', { name: 'library' });
    this.editor = null;
    this.screen = null;
    this.tabs = {
      ids: storage.get('basis.tabs', []),
      list: () => this.tabs.ids.filter((id) => store.summary(id)),
      activate: (id) => this.openDocument(id),
      close: (id, silent) => this.closeTab(id, silent),
    };
    this.applyPrefs();
  }

  async start() {
    await store.init();
    this.tabs.ids = this.tabs.list();
    this.nav = sidebar(this);
    this.scrim = h('div', { class: 'scrim', onclick: () => this.root.classList.remove('nav-open') });
    this.menuBtn = h('button', { class: 'icon-btn nav-toggle', 'aria-label': 'Show library', onclick: () => this.root.classList.toggle('nav-open') }, icon('sidebar'));
    this.content = h('main', { class: 'content', id: 'main' });
    this.editorLayer = h('div', { class: 'editor-layer', hidden: true });
    this.root.replaceChildren(this.nav, this.scrim, h('div', { class: 'content-wrap' }, h('div', { class: 'mobile-bar' }, this.menuBtn, h('span', { class: 'wordmark mobile-title', role: 'img', 'aria-label': 'Basis' })), this.content), this.editorLayer);
    if (!store.persistent) toast('This browser blocks storage here, so notebooks won’t be kept after you leave. Use Settings → Back Up.');
    this.renderScreen();
    initTutorial();
    const active = storage.get('basis.activeDoc', null);
    if (active && store.summary(active)) await this.openDocument(active);
    else if (shouldShowWelcome()) setTimeout(() => this.startWelcome(), 450);
    window.addEventListener('keydown', (e) => {
      if (this.editor || document.querySelector('.sheet')) return;
      const t = e.target;
      if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT')) return;
      if ((e.key === 'n' || e.key === 'N') && !e.metaKey && !e.ctrlKey && ['library', 'folder'].includes(this.route.name)) {
        e.preventDefault();
        newNotebookSheet(this, this.route.folderId ?? null);
      }
    });
    window.addEventListener('pagehide', () => this.editor?.saveNow());
    // Drop images or PDFs onto an open notebook.
    window.addEventListener('dragover', (e) => { if (this.editor && e.dataTransfer?.types.includes('Files')) e.preventDefault(); });
    window.addEventListener('drop', (e) => {
      if (!this.editor || !e.dataTransfer?.files.length) return;
      e.preventDefault();
      const f = e.dataTransfer.files[0];
      if (f.type.startsWith('image/')) this.editor.insertImage(f);
    });
  }

  startWelcome() {
    const folderId = this.route.name === 'folder' ? this.route.folderId ?? null : null;
    welcomeTour({ onNewNotebook: () => newNotebookSheet(this, folderId), onImport: () => importGoodNotesFiles(this, folderId) });
  }

  /** Replays the tutorial from Settings. */
  showTutorial() {
    resetTutorial();
    this.go({ name: 'library' });
    setTimeout(() => this.startWelcome(), 150);
  }

  setPrefs(p) {
    this.prefs = { ...this.prefs, ...p };
    storage.set('basis.prefs', this.prefs);
    this.applyPrefs();
  }

  applyPrefs() {
    const de = document.documentElement;
    if (this.prefs.theme === 'light' || this.prefs.theme === 'dark') de.setAttribute('data-theme', this.prefs.theme);
    else de.removeAttribute('data-theme');
    if (this.prefs.accent) {
      de.style.setProperty('--accent', this.prefs.accent);
      de.style.setProperty('--on-accent', isLight(hexToRgba(this.prefs.accent)) ? '#111' : '#fff');
    } else {
      de.style.removeProperty('--accent');
      de.style.removeProperty('--on-accent');
    }
  }

  go(route) {
    this.route = route;
    storage.set('basis.route', route);
    this.root.classList.remove('nav-open');
    if (this.editor) this.closeEditor();
    this.renderScreen();
    this.nav.render();
  }

  renderScreen() {
    this.screen?.cleanup?.();
    closePopovers();
    const r = this.route;
    const insertIntoNote = (source) => this.insertIntoNote(source);
    const open = { calculator: () => this.go({ name: 'calculator' }) };
    let s;
    // Toolbox screens are Pro; without it, fall back to the library.
    let name = ['formulas', 'units', 'graphs', 'history'].includes(r.name) && !feature('toolbox') ? 'library' : r.name;
    if (name === 'ai' && !feature('ai')) name = 'library';
    switch (name) {
      case 'folder': s = store.folder(r.folderId) ? libraryScreen(this, r.folderId) : libraryScreen(this, null); break;
      case 'search': s = searchScreen(this); break;
      case 'calculator': s = calculatorScreen({ insertIntoNote }); break;
      case 'formulas': s = formulasScreen({ insertIntoNote }); break;
      case 'units': s = unitConverterScreen(); break;
      case 'graphs': s = graphScreen(); break;
      case 'history': s = historyScreen({ insertIntoNote, openCalculator: open.calculator }); break;
      case 'settings': s = settingsScreen(this); break;
      case 'ai': s = aiScreen(this); break;
      default: s = libraryScreen(this, null);
    }
    this.screen = s;
    this.content.replaceChildren(s);
    this.content.scrollTop = 0;
  }

  async openDocument(id, pageIndex) {
    const doc = await store.loadDocument(id);
    if (!doc) { toast('That notebook couldn’t be opened.'); return; }
    if (this.editor?.doc.id === id) { if (pageIndex != null) this.editor.canvas.scrollToPage(pageIndex); return; }
    if (this.editor) await this.closeEditor(false);
    if (!this.tabs.ids.includes(id)) this.tabs.ids.push(id);
    storage.set('basis.tabs', this.tabs.ids);
    storage.set('basis.activeDoc', id);
    this.root.classList.remove('nav-open');
    if (pageIndex != null) doc.view = { ...doc.view, pageIndex, zoom: 0 };
    this.editor = new Editor(doc, { onClose: () => this.closeEditor(), tabs: this.tabs });
    this.editorLayer.hidden = false;
    this.root.classList.add('editing');
    this.editor.mount(this.editorLayer);
    this.nav.render();
    if (shouldShowEditorTour()) { const ed = this.editor; setTimeout(() => { if (this.editor === ed) editorTour(ed); }, 500); }
    if (this.pendingCard) {
      const src = this.pendingCard;
      this.pendingCard = null;
      setTimeout(() => this.editor?.insertCalculation(src), 120);
    }
  }

  async closeEditor(showLibrary = true) {
    const ed = this.editor;
    if (!ed) return;
    this.editor = null;
    await ed.close();
    if (showLibrary) {
      storage.set('basis.activeDoc', null);
      this.editorLayer.hidden = true;
      this.root.classList.remove('editing');
      this.renderScreen();
      this.nav.render();
    }
  }

  async closeTab(id, silent) {
    this.tabs.ids = this.tabs.ids.filter((x) => x !== id);
    storage.set('basis.tabs', this.tabs.ids);
    if (this.editor?.doc.id === id) {
      const next = this.tabs.list().slice(-1)[0];
      if (next && !silent) await this.openDocument(next);
      else await this.closeEditor();
    } else this.editor?.renderTabs();
    this.nav.render();
  }

  /** Sends a calculation to the most recently used notebook. */
  insertIntoNote(source) {
    const target = this.tabs.list().slice(-1)[0];
    if (!target) { toast('Open a notebook first, then insert from the calculator.'); return; }
    this.pendingCard = source;
    this.openDocument(target);
  }
}

const app = new App(document.getElementById('app'));
window.__app = app;
const hideSplash = () => {
  const splash = document.getElementById('splash');
  if (!splash) return;
  splash.classList.add('done');
  setTimeout(() => splash.remove(), 400);
};
app.start().then(hideSplash, (e) => {
  console.error(e);
  document.getElementById('app').textContent = 'Basis couldn’t start: ' + e.message;
  hideSplash();
});

if ('serviceWorker' in navigator && location.protocol.startsWith('http') && !location.hostname.endsWith('claude.ai') && !location.hostname.includes('claudeusercontent')) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
