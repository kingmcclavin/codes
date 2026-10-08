// Library: folder tree sidebar, notebook list, new-notebook sheet,
// customize / move / rename, search and settings.

import { h, relativeTime, plural, hexToRgba, rgbaToHex, storage } from './util.js';
import { icon } from './icons.js';
import { sheet, askText, confirmDialog, menu, toast, segmented, selectField, swatches, toggle, iconButton, pickFile, saveFile } from './ui.js';
import { store } from './store.js';
import { PAPER_SIZES, TEMPLATES, PAPER_COLORS, LIBRARY_COLORS, sizeFor, makeBackground, makeDocument, makePage, describeSize } from './model.js';
import { renderPageCanvas } from './render.js';
import { importPDF } from './pdf.js';
import { importGoodNotes, ZipReader } from './goodnotes.js';
import { importNotability } from './notability.js';
import { exportBasis, importBasis, isBasisArchive } from './basisfile.js';
import { safeFileName } from './editor.js';
import { calc } from './calc/store.js';
import { VERSION } from './version.js';
import { FEATURES, feature, devUnlocked, unlockDev, lockDev, setFeatureOn } from './features.js';
import { LIBRARY_ICON_GROUPS, libraryIcon, libraryIconName } from './libicons.js';

// ---------- Tiles ----------

export function docTile(color, iconText, size = 36) {
  const c = color || 'var(--accent)';
  return h('span', { class: 'doc-tile', style: { '--tile': c, width: size + 'px', height: Math.round(size * 1.28) + 'px', fontSize: Math.round(size * 0.42) + 'px' }, 'aria-hidden': 'true' },
    h('span', { class: 'doc-tile-spine' }), h('span', { class: 'doc-tile-icon' }, libraryIcon(iconText, Math.max(9, Math.round(size * 0.5)))));
}

export function folderTile(color, iconText, size = 36) {
  return h('span', { class: 'folder-tile', style: { '--tile': color || 'var(--accent)', width: size + 'px', height: Math.round(size * 0.82) + 'px', fontSize: Math.round(size * 0.36) + 'px' }, 'aria-hidden': 'true' },
    h('span', { class: 'folder-tab' }), h('span', { class: 'folder-body' }, size >= 20 ? libraryIcon(iconText, Math.round(size * (size < 30 ? 0.5 : 0.42))) : null));
}

// ---------- Sidebar ----------

export function sidebar(app) {
  const nav = h('nav', { class: 'sidebar', 'aria-label': 'Library' });
  const render = () => {
    const sel = app.route;
    const item = (route, iconName, label, badge) => {
      const on = sel.name === route.name && (route.folderId ?? null) === (sel.folderId ?? null);
      const b = h('button', { class: `side-item ${on ? 'on' : ''}`, 'aria-current': on ? 'page' : null, onclick: () => app.go(route) },
        icon(iconName, 19), h('span', { class: 'side-label' }, label), badge != null ? h('span', { class: 'side-badge' }, String(badge)) : null);
      return b;
    };
    const folderRows = [];
    const expanded = storage.get('basis.expandedFolders', {});
    const addFolders = (parentId, depth) => {
      for (const f of store.subfolders(parentId)) {
        const kids = store.subfolders(f.id);
        const on = sel.name === 'folder' && sel.folderId === f.id;
        const open = expanded[f.id] ?? true;
        const row = h('div', { class: `side-item folder-row ${on ? 'on' : ''}`, style: { paddingLeft: 10 + depth * 16 + 'px' } },
          kids.length ? h('button', { class: `disclosure ${open ? 'open' : ''}`, 'aria-label': open ? 'Collapse' : 'Expand', onclick: (e) => { e.stopPropagation(); expanded[f.id] = !open; storage.set('basis.expandedFolders', expanded); render(); } }, icon('chevronRight', 14)) : h('span', { class: 'disclosure-spacer' }),
          h('button', { class: 'folder-link', onclick: () => app.go({ name: 'folder', folderId: f.id }) }, folderTile(f.color, f.icon, 20), h('span', { class: 'side-label' }, f.name), h('span', { class: 'side-badge' }, String(store.documentsIn(f.id).length))));
        dropTarget(row, f.id);
        folderRows.push(row);
        if (kids.length && open) addFolders(f.id, depth + 1);
      }
    };
    addFolders(null, 0);
    const all = item({ name: 'library', folderId: null }, 'tray', 'All Notes', store.documentsIn(null).length);
    dropTarget(all, null);
    nav.replaceChildren(
      h('div', { class: 'brand' }, h('img', { src: 'icons/favicon.png', alt: '', width: 28, height: 28 }), h('span', { class: 'wordmark', role: 'img', 'aria-label': 'Basis' })),
      h('div', { class: 'side-group' }, item({ name: 'search' }, 'search', 'Search'), item({ name: 'calculator' }, 'calc', 'Calculator')),
      feature('toolbox') ? h('div', { class: 'side-head' }, 'Toolbox') : null,
      feature('toolbox') ? h('div', { class: 'side-group' },
        item({ name: 'formulas' }, 'function', 'Formulas'),
        item({ name: 'units' }, 'convert', 'Unit Converter'),
        item({ name: 'graphs' }, 'graph', 'Graphs'),
        item({ name: 'history' }, 'history', 'History')) : null,
      h('div', { class: 'side-head' }, 'Notes'),
      h('div', { class: 'side-group' }, all),
      h('div', { class: 'side-head' }, 'Folders'),
      h('div', { class: 'side-group' }, ...folderRows,
        h('button', { class: 'side-item add', onclick: async () => {
          const name = await askText({ title: 'New Folder', label: 'Name', value: '', placeholder: 'Folder name', confirm: 'Create' });
          if (name == null) return;
          const f = await store.createFolder(name, app.route.name === 'folder' ? app.route.folderId : null);
          app.go({ name: 'folder', folderId: f.id });
        } }, icon('plus', 19), h('span', { class: 'side-label' }, 'New Folder'))),
      app.tabs.list().length ? h('div', { class: 'side-head' }, 'Open') : null,
      app.tabs.list().length ? h('div', { class: 'side-group' }, ...app.tabs.list().map((id) => {
        const s = store.summary(id);
        return h('button', { class: 'side-item', onclick: () => app.openDocument(id) }, docTile(s?.color, s?.icon, 14), h('span', { class: 'side-label' }, s?.title || 'Untitled'));
      })) : null,
      h('div', { class: 'side-foot' }, item({ name: 'settings' }, 'settings', 'Settings')),
    );
  };
  function dropTarget(el, folderId) {
    el.addEventListener('dragover', (e) => { if (e.dataTransfer.types.includes('text/basis-item')) { e.preventDefault(); el.classList.add('drop'); } });
    el.addEventListener('dragleave', () => el.classList.remove('drop'));
    el.addEventListener('drop', async (e) => {
      el.classList.remove('drop');
      const payload = e.dataTransfer.getData('text/basis-item');
      if (!payload) return;
      e.preventDefault();
      const [kind, id] = payload.split(':');
      if (kind === 'doc') await store.moveDocument(id, folderId);
      else if (kind === 'folder' && id !== folderId) await store.moveFolder(id, folderId);
    });
  }
  store.addEventListener('change', render);
  nav.render = render;
  render();
  return nav;
}

// ---------- Library list ----------

export function libraryScreen(app, folderId) {
  let query = '';
  const listHost = h('div', { class: 'library-list' });
  const search = h('input', { class: 'field search', type: 'search', id: 'lib-search', placeholder: 'Search all notebooks', 'aria-label': 'Search all notebooks' });
  search.addEventListener('input', () => { query = search.value.trim().toLowerCase(); render(); });
  const newBtn = h('button', { class: 'btn primary', 'aria-haspopup': 'menu', 'data-tour': 'new' }, icon('plus', 18), 'New');
  newBtn.addEventListener('click', () => menu(newBtn, [
    { label: 'New Notebook', icon: 'docPlus', hint: 'N', action: () => newNotebookSheet(app, folderId) },
    { label: 'New Folder', icon: 'folderPlus', action: () => newFolder() },
    { label: 'Import PDF…', icon: 'import', action: () => importPDFNotebook(app, folderId) },
    { label: 'Import GoodNotes or Notability File…', icon: 'import', action: () => importGoodNotesFiles(app, folderId) },
    { label: 'Import Basis Notebook (.basis)…', icon: 'import', action: () => importBasisFiles(app, folderId) },
  ], { align: 'end' }));
  const folder = store.folder(folderId);
  const up = folder ? h('button', { class: 'btn ghost', onclick: () => app.go(folder.parentId ? { name: 'folder', folderId: folder.parentId } : { name: 'library' }) }, icon('back', 18), store.folder(folder.parentId)?.name || 'All Notes') : null;
  const folderMore = folder ? iconButton('more', 'Folder actions', (e) => folderMenu(e.currentTarget, folder)) : null;
  const title = h('h1', {}, folder ? folder.name : 'All Notes');
  const root = h('section', { class: 'screen library' },
    h('header', { class: 'screen-header' }, h('div', { class: 'title-block' }, up, title), h('div', { class: 'header-actions' }, folderMore, newBtn)),
    search, listHost);

  async function newFolder() {
    const name = await askText({ title: 'New Folder', label: 'Name', placeholder: 'Folder name', confirm: 'Create' });
    if (name != null) await store.createFolder(name, folderId);
  }

  function folderMenu(anchor, f) {
    menu(anchor, [
      { label: 'Rename', icon: 'pencilLine', action: async () => { const n = await askText({ title: 'Rename Folder', value: f.name, confirm: 'Rename' }); if (n?.trim()) store.updateFolder(f.id, { name: n.trim() }); } },
      { label: 'Customize…', icon: 'palette', action: () => customizeSheet({ kind: 'folder', id: f.id }) },
      { label: 'Move to…', icon: 'move', action: () => moveSheet({ kind: 'folder', id: f.id }) },
      'sep',
      { label: 'Delete', icon: 'trash', danger: true, action: async () => {
        const n = store.totalDocumentCount(f.id);
        const ok = await confirmDialog({ title: n ? `Delete “${f.name}” and ${plural(n, 'notebook')}?` : `Delete “${f.name}”?`, message: 'Everything inside it will be deleted. This can’t be undone.', confirm: 'Delete Folder' });
        if (ok) { await store.deleteFolder(f.id); if (app.route.folderId === f.id) app.go({ name: 'library' }); }
      } },
    ], { align: 'end' });
  }

  function docMenu(anchor, d) {
    menu(anchor, [
      { label: 'Open', icon: 'pen', action: () => app.openDocument(d.id) },
      { label: 'Rename', icon: 'pencilLine', action: async () => { const n = await askText({ title: 'Rename Notebook', value: d.title, confirm: 'Rename' }); if (n?.trim()) store.rename(d.id, n.trim()); } },
      { label: 'Customize…', icon: 'palette', action: () => customizeSheet({ kind: 'doc', id: d.id }) },
      { label: 'Move to…', icon: 'move', action: () => moveSheet({ kind: 'doc', id: d.id }) },
      { label: 'Duplicate', icon: 'duplicate', action: () => store.duplicate(d.id) },
      { label: 'Export as Basis Notebook (.basis)', icon: 'export', action: async () => {
        const doc = await store.loadDocument(d.id);
        if (!doc) return;
        toast('Preparing notebook…');
        try { if (saveFile(await exportBasis(doc), `${safeFileName(doc.title)}.basis`)) toast('Notebook exported'); } catch (e) { toast(e.message || 'Export failed.'); }
      } },
      'sep',
      { label: 'Delete', icon: 'trash', danger: true, action: async () => {
        if (await confirmDialog({ title: `Delete “${d.title}”?`, message: 'The notebook and its pages will be deleted. This can’t be undone.' })) { app.tabs.close(d.id, true); await store.deleteDocument(d.id); }
      } },
    ], { align: 'end' });
  }

  const location = (fid) => ['All Notes', ...store.pathTo(fid).map((f) => f.name)].join(' › ');

  function render() {
    const folders = query ? store.folders.filter((f) => f.name.toLowerCase().includes(query)) : store.subfolders(folderId);
    const docs = query ? store.allDocuments().filter((d) => d.title.toLowerCase().includes(query)) : store.documentsIn(folderId);
    if (!folders.length && !docs.length) {
      listHost.replaceChildren(query ? h('div', { class: 'empty-state' }, h('p', {}, `No notebooks match “${search.value}”.`)) : h('div', { class: 'empty-state' },
        icon(folderId ? 'folder' : 'pen', 44),
        h('h2', {}, folderId ? 'This folder is empty' : 'No notebooks yet'),
        h('p', { class: 'muted' }, 'Create a notebook to start writing, or import a PDF to annotate.'),
        h('div', { class: 'row-actions center' },
          h('button', { class: 'btn primary', onclick: () => newNotebookSheet(app, folderId) }, icon('docPlus', 18), 'New Notebook'),
          h('button', { class: 'btn', onclick: newFolder }, icon('folderPlus', 18), 'New Folder'))));
      return;
    }
    const parts = [];
    if (folders.length) {
      parts.push(h('h2', { class: 'list-title' }, 'Folders'));
      parts.push(h('div', { class: 'rows' }, ...folders.map((f) => {
        const count = store.itemCount(f.id);
        const more = iconButton('more', `${f.name} actions`, (e) => { e.stopPropagation(); folderMenu(more, f); }, { cls: 'small' });
        const row = h('div', { class: 'row', draggable: 'true' },
          h('button', { class: 'row-main', onclick: () => app.go({ name: 'folder', folderId: f.id }) },
            folderTile(f.color, f.icon, 38),
            h('span', { class: 'row-text' }, h('span', { class: 'row-title' }, f.name), h('span', { class: 'row-sub' }, query ? location(f.parentId) : plural(count, 'item')))),
          more, icon('chevronRight', 16, 'row-chevron'));
        row.addEventListener('dragstart', (e) => e.dataTransfer.setData('text/basis-item', `folder:${f.id}`));
        row.addEventListener('dragover', (e) => { if (e.dataTransfer.types.includes('text/basis-item')) { e.preventDefault(); row.classList.add('drop'); } });
        row.addEventListener('dragleave', () => row.classList.remove('drop'));
        row.addEventListener('drop', async (e) => {
          row.classList.remove('drop');
          const [kind, id] = (e.dataTransfer.getData('text/basis-item') || '').split(':');
          e.preventDefault();
          if (kind === 'doc') await store.moveDocument(id, f.id); else if (kind === 'folder' && id !== f.id) await store.moveFolder(id, f.id);
        });
        return row;
      })));
    }
    if (docs.length) {
      parts.push(h('h2', { class: 'list-title' }, 'Notebooks'));
      parts.push(h('div', { class: 'rows' }, ...docs.map((d) => {
        const more = iconButton('more', `${d.title} actions`, (e) => { e.stopPropagation(); docMenu(more, d); }, { cls: 'small' });
        const row = h('div', { class: 'row', draggable: 'true' },
          h('button', { class: 'row-main', onclick: () => app.openDocument(d.id) },
            docTile(d.color, d.icon, 32),
            h('span', { class: 'row-text' }, h('span', { class: 'row-title' }, d.title || 'Untitled'),
              h('span', { class: 'row-sub' }, query ? location(d.folderId) : `${plural(d.pageCount, 'page')} · ${describeSize(d.pageSize)}`))),
          h('span', { class: 'row-date' }, relativeTime(d.modifiedAt)), more);
        row.addEventListener('dragstart', (e) => e.dataTransfer.setData('text/basis-item', `doc:${d.id}`));
        return row;
      })));
    }
    listHost.replaceChildren(...parts);
  }

  const onChange = () => { title.textContent = store.folder(folderId)?.name || 'All Notes'; render(); };
  store.addEventListener('change', onChange);
  root.cleanup = () => store.removeEventListener('change', onChange);
  render();
  return root;
}

// ---------- New notebook ----------

export function newNotebookSheet(app, folderId, defaults = {}) {
  const last = storage.get('basis.newNotebook', { paper: 'letter', orientation: 'portrait', template: 'ruled', color: 0 });
  const state = { title: '', ...last, cover: null, ...defaults };
  const title = h('input', { class: 'field big', id: 'nn-title', placeholder: 'Untitled', 'aria-label': 'Title' });
  const preview = h('canvas', { class: 'template-preview' });
  const drawPreview = () => {
    const size = sizeFor(PAPER_SIZES.find((p) => p.id === state.paper), state.orientation);
    const c = renderPageCanvas({ w: size.w, h: size.h, background: makeBackground(state.template, PAPER_COLORS[state.color].c), elements: [] }, (220 / Math.max(size.w, size.h)) * 2, 500000);
    preview.width = c.width; preview.height = c.height;
    preview.getContext('2d').drawImage(c, 0, 0);
  };
  const templates = h('div', { class: 'template-grid', role: 'radiogroup', 'aria-label': 'Template' });
  const renderTemplates = () => templates.replaceChildren(...TEMPLATES.map((t) => {
    const c = renderPageCanvas({ w: 120, h: 156, background: { ...makeBackground(t.id, PAPER_COLORS[state.color].c), spacing: t.id === 'engineering' ? 36 : t.spacing * 0.6 }, elements: [] }, 1, 50000);
    c.className = 'template-thumb';
    const on = state.template === t.id;
    const b = h('button', { class: `template-btn ${on ? 'on' : ''}`, role: 'radio', 'aria-checked': String(on) }, c, h('span', {}, t.name));
    b.addEventListener('click', () => { state.template = t.id; renderTemplates(); drawPreview(); });
    return b;
  }));
  const create = async () => {
    const paper = PAPER_SIZES.find((p) => p.id === state.paper);
    const doc = makeDocument({
      title: title.value.trim() || 'Untitled',
      size: sizeFor(paper, state.orientation),
      background: makeBackground(state.template, PAPER_COLORS[state.color].c),
      folderId: folderId ?? null,
      color: state.cover,
    });
    storage.set('basis.newNotebook', { paper: state.paper, orientation: state.orientation, template: state.template, color: state.color });
    await store.saveDocument(doc);
    app.openDocument(doc.id);
  };
  sheet({
    title: 'New Notebook',
    wide: true,
    actions: { confirm: 'Create', onConfirm: () => { create(); return true; } },
    build(body, close) {
      title.addEventListener('keydown', (e) => { if (e.key === 'Enter') { create(); close(true); } });
      renderTemplates();
      body.append(h('div', { class: 'settings-split' },
        h('div', { class: 'settings-form' },
          title,
          h('label', { class: 'form-row', for: 'nn-paper' }, h('span', { class: 'form-label' }, 'Size'),
            selectField('nn-paper', ['Paper', 'Screen', 'Other'].map((cat) => ({ group: cat, options: PAPER_SIZES.filter((p) => p.cat === cat).map((p) => ({ value: p.id, label: `${p.name} · ${p.sub}` })) })), state.paper, (v) => { state.paper = v; drawPreview(); })),
          h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Orientation'), segmented([{ value: 'portrait', label: 'Portrait' }, { value: 'landscape', label: 'Landscape' }], state.orientation, (v) => { state.orientation = v; drawPreview(); })),
          h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Paper'), segmented(PAPER_COLORS.map((p, i) => ({ value: i, label: p.name })), state.color, (v) => { state.color = v; renderTemplates(); drawPreview(); })),
          h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Template'), templates),
          h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Cover color'), swatches(LIBRARY_COLORS.map((c) => hexToRgba(c)), null, (c) => { state.cover = rgbaToHex(c); }, { custom: false }))),
        h('div', { class: 'settings-preview' }, preview)));
      drawPreview();
    },
  });
}

async function importPDFNotebook(app, folderId) {
  const files = await pickFile('application/pdf', true);
  if (!files.length) return;
  let opened = null;
  for (const file of files) {
    toast(`Importing ${file.name}…`);
    try {
      const pages = await importPDF(file, (n, t) => toast(`Importing page ${n} of ${t}…`));
      const doc = makeDocument({ title: file.name.replace(/\.pdf$/i, ''), size: { w: pages[0].w, h: pages[0].h }, background: makeBackground('blank'), folderId });
      doc.pages = pages.map((p) => makePage({ w: p.w, h: p.h }, { ...makeBackground('blank'), image: p.asset, pdf: p.pdf }));
      await store.saveDocument(doc);
      opened = doc.id;
    } catch (e) {
      toast(e.message || `Couldn’t import ${file.name}.`);
    }
  }
  if (opened) app.openDocument(opened);
}

/** Imports .basis notebooks (from this app or the Basis iPad app). */
async function importBasisFiles(app, folderId, picked) {
  const files = picked || await pickFile('', true);
  if (!files.length) return;
  let opened = null, count = 0;
  for (const f of files) {
    const file = f.file || f, parsed = f.json;
    try {
      const json = parsed || JSON.parse(await file.text());
      toast(`Importing ${file.name}…`);
      const doc = await importBasis(json, { folderId, onProgress: (n, t) => toast(`Importing ${file.name}: page ${n} of ${t}…`) });
      await store.saveDocument(doc);
      opened = doc.id;
      count++;
    } catch (e) {
      toast(/JSON|Unexpected/.test(e.message) ? `“${file.name}” isn’t a Basis notebook.` : e.message);
    }
  }
  if (count) toast(`Imported ${plural(count, 'notebook')}`);
  if (files.length === 1 && opened) app.openDocument(opened);
}

/** Converts .goodnotes files into Basis notebooks in this folder. */
export async function importGoodNotesFiles(app, folderId, picked) {
  // No accept filter: iPadOS greys out file types it doesn't know.
  const files = picked || await pickFile('', true);
  if (!files.length) return;
  const lines = [];
  let opened = null;
  for (const file of files) {
    const name = file.name.replace(/\.(goodnotes|note)$/i, '');
    try {
      toast(`Importing ${name}…`);
      // Both are zips: Notability notes hold a Session.plist, GoodNotes files an event log.
      let isNotability = /\.note$/i.test(file.name);
      try { isNotability = [...(await ZipReader.open(new Uint8Array(await file.arrayBuffer()))).entries.keys()].some((n) => /(^|\/)Session\.plist$/.test(n)); } catch { /* reported by the importer */ }
      const r = isNotability
        ? await importNotability(file, { folderId })
        : await importGoodNotes(file, { folderId, onProgress: (n, t) => toast(`Importing ${name}: page ${n} of ${t}…`) });
      await store.saveDocument(r.doc);
      opened = r.doc.id;
      let line = `${name} (${isNotability ? 'Notability' : 'GoodNotes'}): ${plural(r.doc.pages.length, 'page')}, ${plural(r.strokes, 'stroke')}`;
      if (r.images) line += `, ${plural(r.images, 'image')}`;
      if (r.text) line += ', typed text';
      if (r.skipped) line += ` (${plural(r.skipped, 'item')} couldn’t be brought over)`;
      if (r.paperErrors?.length) line += `. The paper on some pages couldn’t be drawn (${r.paperErrors[0]})`;
      lines.push(line);
    } catch (e) {
      lines.push(`${name}: ${e.message || 'couldn’t be imported.'}`);
    }
  }
  sheet({
    title: 'Import',
    className: 'compact',
    build(body, close) {
      body.append(...lines.map((l) => h('p', { class: 'dialog-message' }, l)),
        h('p', { class: 'muted small' }, 'Handwriting comes in as Basis ink you can erase and edit. GoodNotes text boxes and Notability images and audio aren’t imported yet.'),
        h('div', { class: 'dialog-actions' }, h('button', { class: 'btn primary', onclick: () => close(true) }, 'OK')));
    },
  });
  if (files.length === 1 && opened) app.openDocument(opened);
}

// ---------- Customize & move ----------

function customizeSheet(item) {
  const isFolder = item.kind === 'folder';
  const cur = isFolder ? store.folder(item.id) : store.summary(item.id);
  let color = cur?.color || null, ic = cur?.icon || null;
  const previewHost = h('div', { class: 'customize-preview' });
  const renderPreview = () => previewHost.replaceChildren(isFolder ? folderTile(color, ic, 90) : docTile(color, ic, 76));
  ic = libraryIconName(ic);
  const icons = h('div', { class: 'icon-picker' });
  const cell = (x) => {
    const b = h('button', { class: `icon-cell ${ic === x ? 'on' : ''}`, 'aria-label': x || 'No icon', 'aria-pressed': String(ic === x) }, x ? libraryIcon(x, 22) : h('span', { class: 'icon-none' }, 'None'));
    b.addEventListener('click', () => { ic = x; renderIcons(); renderPreview(); });
    return b;
  };
  const renderIcons = () => icons.replaceChildren(
    h('div', { class: 'icon-grid' }, cell(null)),
    ...LIBRARY_ICON_GROUPS.flatMap(([label, names]) => [h('h3', { class: 'icon-group-title' }, label), h('div', { class: 'icon-grid' }, ...names.map(cell))]));
  sheet({
    title: 'Customize',
    actions: {
      confirm: 'Done',
      onConfirm: () => { if (isFolder) store.updateFolder(item.id, { color, icon: ic }); else store.setDocumentAppearance(item.id, color, ic); },
    },
    build(body) {
      renderPreview(); renderIcons();
      const colors = swatches(LIBRARY_COLORS.map((c) => hexToRgba(c)), color ? hexToRgba(color) : null, (c) => { color = rgbaToHex(c); renderPreview(); });
      body.append(previewHost,
        h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Color'), colors, h('button', { class: 'btn ghost small', onclick: () => { color = null; colors.setValue(null); renderPreview(); } }, 'Use accent color')),
        h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Icon'), icons));
    },
  });
}

function moveSheet(item) {
  const excluded = item.kind === 'folder' ? store.descendants(item.id) : new Set();
  const current = item.kind === 'doc' ? store.summary(item.id)?.folderId ?? null : store.folder(item.id)?.parentId ?? null;
  sheet({
    title: 'Move to…',
    build(body, close) {
      const rows = [{ id: null, name: 'All Notes', depth: 0 }];
      const add = (parent, depth) => { for (const f of store.subfolders(parent)) if (!excluded.has(f.id)) { rows.push({ id: f.id, name: f.name, depth, f }); add(f.id, depth + 1); } };
      add(null, 1);
      body.append(h('div', { class: 'list' }, ...rows.map((r) => h('button', { class: 'list-row button', style: { paddingLeft: 12 + r.depth * 18 + 'px' }, onclick: async () => {
        if (item.kind === 'doc') await store.moveDocument(item.id, r.id); else await store.moveFolder(item.id, r.id);
        close(true);
      } }, r.id ? folderTile(r.f.color, r.f.icon, 22) : icon('tray', 20), h('span', { class: 'list-main' }, r.name), r.id === current ? icon('check', 18) : null))));
    },
  });
}

// ---------- Search ----------

export function searchScreen(app) {
  const input = h('input', { class: 'field search big', type: 'search', id: 'global-search', placeholder: feature('toolbox') ? 'Search notebooks, typed text, sections, formulas' : 'Search notebooks, typed text and sections', 'aria-label': 'Search' });
  const results = h('div', { class: 'search-results' });
  const root = h('section', { class: 'screen search-screen' }, h('header', { class: 'screen-header' }, h('h1', {}, 'Search')), input, results);
  const snippet = (text, q) => {
    const i = text.toLowerCase().indexOf(q);
    if (i < 0) return null;
    const s = Math.max(0, i - 40);
    return h('span', { class: 'snippet' }, (s ? '…' : '') + text.slice(s, i), h('mark', {}, text.slice(i, i + q.length)), text.slice(i + q.length, i + q.length + 60) + '…');
  };
  const render = () => {
    const q = input.value.trim().toLowerCase();
    if (!q) { results.replaceChildren(h('p', { class: 'muted' }, 'Search looks through notebook titles, typed text and calculation cards, section names, folders' + (feature('toolbox') ? ' and formulas.' : '.'))); return; }
    const groups = [];
    const docs = store.allDocuments().filter((d) => d.title.toLowerCase().includes(q) || d.text?.toLowerCase().includes(q) || d.sections?.some((s) => s.title.toLowerCase().includes(q)));
    if (docs.length) groups.push(h('h2', { class: 'list-title' }, 'Notebooks'), h('div', { class: 'rows' }, ...docs.map((d) => {
      const sec = d.sections?.find((s) => s.title.toLowerCase().includes(q));
      return h('div', { class: 'row' }, h('button', { class: 'row-main', onclick: () => app.openDocument(d.id, sec?.page) }, docTile(d.color, d.icon, 28),
        h('span', { class: 'row-text' }, h('span', { class: 'row-title' }, d.title), d.title.toLowerCase().includes(q) ? h('span', { class: 'row-sub' }, relativeTime(d.modifiedAt)) : sec ? h('span', { class: 'row-sub' }, `Section “${sec.title}” · page ${sec.page + 1}`) : h('span', { class: 'row-sub' }, snippet(d.text || '', q)))));
    })));
    const folders = store.folders.filter((f) => f.name.toLowerCase().includes(q));
    if (folders.length) groups.push(h('h2', { class: 'list-title' }, 'Folders'), h('div', { class: 'rows' }, ...folders.map((f) => h('div', { class: 'row' }, h('button', { class: 'row-main', onclick: () => app.go({ name: 'folder', folderId: f.id }) }, folderTile(f.color, f.icon, 28), h('span', { class: 'row-text' }, h('span', { class: 'row-title' }, f.name)))))));
    const formulas = !feature('toolbox') ? [] : calc.allFormulas.filter((f) => f.name.toLowerCase().includes(q) || f.summary?.toLowerCase().includes(q));
    if (formulas.length) groups.push(h('h2', { class: 'list-title' }, 'Formulas'), h('div', { class: 'rows' }, ...formulas.map((f) => h('div', { class: 'row' }, h('button', { class: 'row-main', onclick: () => { storage.set('basis.selectedFormula', f.id); app.go({ name: 'formulas' }); } }, icon('function', 22), h('span', { class: 'row-text' }, h('span', { class: 'row-title' }, f.name), h('span', { class: 'row-sub' }, `${f.category} · ${f.summary || ''}`)))))));
    results.replaceChildren(...(groups.length ? groups : [h('p', { class: 'muted' }, `Nothing matches “${input.value}”.`)]));
  };
  input.addEventListener('input', render);
  render();
  setTimeout(() => input.focus(), 50);
  return root;
}

// ---------- Settings ----------

// Tapping the version five times asks for the Developer Mode password.
function versionLine() {
  let taps = 0, timer = 0;
  const el = h('p', { class: 'version' }, `Basis Version ${VERSION}`, devUnlocked() ? ' · Developer Mode' : '');
  el.addEventListener('click', async () => {
    clearTimeout(timer);
    timer = setTimeout(() => { taps = 0; }, 1500);
    if (++taps < 5 || devUnlocked()) return;
    taps = 0;
    const password = await askText({ title: 'Developer Mode', label: 'Password', confirm: 'Unlock', type: 'password' });
    if (!password) return;
    try {
      if (await unlockDev(password)) location.reload();
      else toast('That password isn’t right.');
    } catch (e) { toast(e.message); }
  });
  return el;
}

function developerGroup() {
  const entries = Object.entries(FEATURES).filter(([, f]) => f.status !== 'released');
  const label = { testing: 'Testing', pro: 'Pro' };
  return h('div', { class: 'settings-group' },
    h('h2', { class: 'list-title' }, 'Developer Mode'),
    h('p', { class: 'muted' }, 'Features that are still being tested, or are for Pro, show up on this device only. Switch one off to see Basis as everyone else does.'),
    entries.length
      ? h('div', { class: 'dev-features' }, ...entries.map(([id, f]) => h('div', { class: 'dev-feature' },
        toggle(`dev-${id}`, `${f.name} (${label[f.status] || f.status})`, feature(id), (on) => { setFeatureOn(id, on); location.reload(); }),
        f.note ? h('p', { class: 'muted small' }, f.note) : null)))
      : h('p', { class: 'muted small' }, 'Nothing is in testing right now.'),
    h('div', { class: 'row-actions' }, h('button', { class: 'btn', onclick: () => { lockDev(); location.reload(); } }, 'Turn Off Developer Mode')));
}


export function settingsScreen(app) {
  const prefs = app.prefs;
  const accent = swatches(LIBRARY_COLORS.map((c) => hexToRgba(c)), hexToRgba(prefs.accent || '#2f6bff'), (c) => app.setPrefs({ accent: rgbaToHex(c) }));
  const theme = segmented([{ value: 'system', label: 'System' }, { value: 'light', label: 'Light' }, { value: 'dark', label: 'Dark' }], prefs.theme || 'system', (v) => app.setPrefs({ theme: v }));
  const usage = h('span', { class: 'muted' }, 'Calculating…');
  if (navigator.storage?.estimate) navigator.storage.estimate().then((e) => { usage.textContent = `${(e.usage / 1e6).toFixed(1)} MB used`; }).catch(() => { usage.textContent = ''; });
  else usage.textContent = '';
  const root = h('section', { class: 'screen settings-screen' },
    h('header', { class: 'screen-header' }, h('h1', {}, 'Settings')),
    h('div', { class: 'settings-group' },
      h('h2', { class: 'list-title' }, 'Appearance'),
      h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Accent color'), accent, h('button', { class: 'btn ghost small', onclick: () => { app.setPrefs({ accent: null }); accent.setValue(hexToRgba('#2f6bff')); } }, 'Use default blue')),
      h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Theme'), theme)),
    h('div', { class: 'settings-group' },
      h('h2', { class: 'list-title' }, 'Your data'),
      h('p', { class: 'muted' }, store.persistent
        ? 'Notebooks are saved in this browser on this device. Make a backup to move them to another browser or keep a copy.'
        : 'This browser isn’t letting Basis save data, so notebooks last only until you close the page. Make a backup before leaving.'),
      h('div', { class: 'form-row inline' }, h('span', {}, `${plural(store.summaries.length, 'notebook')}, ${plural(store.folders.length, 'folder')}`), usage),
      h('div', { class: 'row-actions' },
        h('button', { class: 'btn', onclick: async () => {
          toast('Preparing backup…');
          const json = await store.exportBackup({ calculator: calc.exportData() });
          if (saveFile(new Blob([json], { type: 'application/json' }), `Basis Backup ${new Date().toISOString().slice(0, 10)}.json`)) toast('Backup saved');
        } }, icon('export', 18), 'Back Up Everything'),
        h('button', { class: 'btn', onclick: async () => {
          // Any file type: iPadOS greys out types a picker doesn't list.
          // Basis backups (.json) restore; GoodNotes files (zips) import.
          const files = await pickFile('', true);
          if (!files.length) return;
          const goodnotes = [];
          for (const file of files) {
            const head = new Uint8Array(await file.slice(0, 2).arrayBuffer());
            if (head[0] === 0x50 && head[1] === 0x4b) { goodnotes.push(file); continue; } // "PK" zip
            try {
              const text = await file.text();
              const json = JSON.parse(text);
              if (isBasisArchive(json)) { await importBasisFiles(app, null, [{ file, json }]); continue; }
              const r = await store.importBackup(text);
              if (r.extra.calculator) calc.importData(r.extra.calculator);
              toast(`Restored ${plural(r.docs, 'notebook')} and ${plural(r.folders, 'folder')}`);
            } catch (e) { toast(/JSON|Unexpected/.test(e.message) ? `“${file.name}” isn’t a file Basis can open.` : e.message); }
          }
          if (goodnotes.length) importGoodNotesFiles(app, null, goodnotes);
        } }, icon('import', 18), 'Restore from Backup…'),
        h('button', { class: 'btn', onclick: () => importGoodNotesFiles(app, null) }, icon('import', 18), 'Import GoodNotes or Notability File…')),
      h('p', { class: 'muted small' }, 'Restore accepts Basis backups (.json), Basis notebooks (.basis), GoodNotes files (.goodnotes) and Notability notes (.note).')),
    h('div', { class: 'settings-group' },
      h('h2', { class: 'list-title' }, 'Help'),
      h('p', { class: 'muted' }, 'Take the tour of Basis again. The notebook tour plays the next time you open a notebook.'),
      h('div', { class: 'row-actions' }, h('button', { class: 'btn', onclick: () => app.showTutorial() }, icon('play', 18), 'Show Tutorial'))),
    h('div', { class: 'settings-group' },
      h('h2', { class: 'list-title' }, 'Shortcuts'),
      h('dl', { class: 'shortcuts' },
        ...[['1 – 6', 'Pen, Highlighter, Eraser, Shapes, Lasso, Text'], ['E', 'Toggle eraser'], ['K', 'Floating calculator'], ['⌘/Ctrl Z', 'Undo (add Shift to redo)'],
          ['⌘/Ctrl C, X, V, D', 'Copy, cut, paste, duplicate selection'], ['Delete', 'Delete selection'], ['⌘/Ctrl + / −', 'Zoom'], ['Space + drag', 'Scroll with a mouse'],
          ['Two fingers', 'Scroll and pinch to zoom'], ['Double-tap', 'Zoom so the page fills the screen edge to edge; again to zoom back'], ['Hold still', 'Snap a pen stroke to a shape'], ['Scribble', 'Scribble fast over ink with the pen to erase it']].flatMap(([k, v]) => [h('dt', {}, h('kbd', {}, k)), h('dd', {}, v)]))),
    devUnlocked() ? developerGroup() : null,
    versionLine(),
    h('p', { class: 'muted small about' }, `Basis for the web. Pens with pressure and tilt, shape recognition, vector erasing, templates, live calculation cards${feature('toolbox') ? ', formulas and unit conversion' : ''} — all stored locally.`),
  );
  return root;
}
