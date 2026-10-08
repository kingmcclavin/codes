// Persistence: IndexedDB holds documents, small library summaries, folders
// and image assets. Everything stays in this browser; Backup exports it.

import { uuid } from './util.js';

const DB_NAME = 'basis';
const DB_VERSION = 1;

function openDB() {
  return new Promise((resolve, reject) => {
    let req;
    try { req = indexedDB.open(DB_NAME, DB_VERSION); } catch (e) { reject(e); return; }
    req.onupgradeneeded = () => {
      const db = req.result;
      for (const name of ['docs', 'summaries', 'folders', 'assets', 'kv']) {
        if (!db.objectStoreNames.contains(name)) db.createObjectStore(name, { keyPath: name === 'kv' ? 'key' : 'id' });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

/** Falls back to an in-memory store when IndexedDB is unavailable (private mode, sandbox). */
class MemoryDB {
  constructor() { this.stores = { docs: new Map(), summaries: new Map(), folders: new Map(), assets: new Map(), kv: new Map() }; }
  async get(store, id) { return this.stores[store].get(id); }
  async getAll(store) { return [...this.stores[store].values()]; }
  async put(store, value) { this.stores[store].set(value.id ?? value.key, value); }
  async delete(store, id) { this.stores[store].delete(id); }
}

class IDB {
  constructor(db) { this.db = db; }
  tx(store, mode, fn) {
    return new Promise((resolve, reject) => {
      const t = this.db.transaction(store, mode);
      const req = fn(t.objectStore(store));
      t.oncomplete = () => resolve(req?.result);
      t.onerror = () => reject(t.error);
      t.onabort = () => reject(t.error);
    });
  }
  get(store, id) { return this.tx(store, 'readonly', (s) => s.get(id)); }
  getAll(store) { return this.tx(store, 'readonly', (s) => s.getAll()); }
  put(store, value) { return this.tx(store, 'readwrite', (s) => s.put(value)); }
  delete(store, id) { return this.tx(store, 'readwrite', (s) => s.delete(id)); }
}

export function summarize(doc) {
  const first = doc.pages[0];
  return {
    id: doc.id,
    title: doc.title,
    createdAt: doc.createdAt,
    modifiedAt: doc.modifiedAt,
    folderId: doc.folderId ?? null,
    color: doc.color ?? null,
    icon: doc.icon ?? null,
    pageCount: doc.pages.length,
    pageSize: { w: first.w, h: first.h },
    // Typed text, for search.
    text: doc.pages.flatMap((p) => p.elements.filter((e) => e.type === 'text').map((e) => e.text)).join('\n').slice(0, 4000),
    sections: doc.pages.map((p, i) => (p.background.section ? { title: p.background.section, page: i } : null)).filter(Boolean),
  };
}

class Store extends EventTarget {
  constructor() {
    super();
    this.db = null;
    this.persistent = true;
    this.summaries = [];
    this.folders = [];
    this.assetURLs = new Map();
  }

  async init() {
    try {
      this.db = new IDB(await openDB());
      await this.db.getAll('folders'); // probe
    } catch {
      this.db = new MemoryDB();
      this.persistent = false;
    }
    this.summaries = (await this.db.getAll('summaries')) || [];
    this.folders = (await this.db.getAll('folders')) || [];
    this.changed();
  }

  changed() { this.dispatchEvent(new Event('change')); }

  // ---------- Documents ----------

  documentsIn(folderId) {
    return this.summaries.filter((s) => (s.folderId ?? null) === (folderId ?? null)).sort((a, b) => b.modifiedAt - a.modifiedAt);
  }

  allDocuments() { return [...this.summaries].sort((a, b) => b.modifiedAt - a.modifiedAt); }

  summary(id) { return this.summaries.find((s) => s.id === id); }

  async loadDocument(id) { return this.db.get('docs', id); }

  async saveDocument(doc, { touch = true } = {}) {
    if (touch) doc.modifiedAt = Date.now();
    await this.db.put('docs', doc);
    const s = summarize(doc);
    await this.db.put('summaries', s);
    const i = this.summaries.findIndex((x) => x.id === s.id);
    if (i >= 0) this.summaries[i] = s; else this.summaries.push(s);
    this.changed();
  }

  async updateSummaryFields(id, fields) {
    const doc = await this.loadDocument(id);
    if (!doc) return;
    Object.assign(doc, fields);
    await this.saveDocument(doc, { touch: false });
  }

  rename(id, title) { return this.updateSummaryFields(id, { title }); }
  moveDocument(id, folderId) { return this.updateSummaryFields(id, { folderId: folderId ?? null }); }
  setDocumentAppearance(id, color, icon) { return this.updateSummaryFields(id, { color, icon }); }

  async duplicate(id) {
    const doc = await this.loadDocument(id);
    if (!doc) return null;
    const copy = structuredClone(doc);
    copy.id = uuid();
    copy.title = doc.title + ' Copy';
    copy.createdAt = Date.now();
    copy.pages = copy.pages.map((p) => ({ ...p, id: uuid(), elements: p.elements.map((e) => ({ ...e, id: uuid() })) }));
    await this.saveDocument(copy);
    return copy.id;
  }

  async deleteDocument(id) {
    const doc = await this.loadDocument(id);
    await this.db.delete('docs', id);
    await this.db.delete('summaries', id);
    this.summaries = this.summaries.filter((s) => s.id !== id);
    if (doc) {
      // Duplicated notebooks share images and PDFs; keep any another notebook still uses.
      const own = collectAssetIds(doc);
      for (const s of this.summaries) {
        if (!own.size) break;
        const other = await this.loadDocument(s.id);
        if (other) for (const a of collectAssetIds(other)) own.delete(a);
      }
      for (const a of own) await this.deleteAsset(a);
    }
    this.changed();
  }

  // ---------- Folders ----------

  folder(id) { return id ? this.folders.find((f) => f.id === id) : null; }

  subfolders(parentId) {
    return this.folders.filter((f) => (f.parentId ?? null) === (parentId ?? null)).sort((a, b) => a.name.localeCompare(b.name));
  }

  pathTo(folderId) {
    const path = [];
    let f = this.folder(folderId);
    while (f) { path.unshift(f); f = this.folder(f.parentId); }
    return path;
  }

  descendants(folderId) {
    const out = new Set([folderId]);
    let grew = true;
    while (grew) {
      grew = false;
      for (const f of this.folders) if (f.parentId && out.has(f.parentId) && !out.has(f.id)) { out.add(f.id); grew = true; }
    }
    return out;
  }

  itemCount(folderId) { return this.subfolders(folderId).length + this.documentsIn(folderId).length; }

  totalDocumentCount(folderId) {
    const ids = this.descendants(folderId);
    return this.summaries.filter((s) => s.folderId && ids.has(s.folderId)).length;
  }

  async createFolder(name, parentId = null) {
    const f = { id: uuid(), name: name.trim() || 'New Folder', parentId: parentId ?? null, color: null, icon: null, createdAt: Date.now() };
    await this.db.put('folders', f);
    this.folders.push(f);
    this.changed();
    return f;
  }

  async updateFolder(id, fields) {
    const f = this.folder(id);
    if (!f) return;
    Object.assign(f, fields);
    await this.db.put('folders', f);
    this.changed();
  }

  async moveFolder(id, parentId) {
    if (parentId && this.descendants(id).has(parentId)) return; // never inside itself
    await this.updateFolder(id, { parentId: parentId ?? null });
  }

  async deleteFolder(id) {
    const ids = this.descendants(id);
    for (const s of this.summaries.filter((s) => s.folderId && ids.has(s.folderId))) await this.deleteDocument(s.id);
    for (const fid of ids) await this.db.delete('folders', fid);
    this.folders = this.folders.filter((f) => !ids.has(f.id));
    this.changed();
  }

  // ---------- Assets (images, imported PDF pages) ----------

  // Assets are stored as raw bytes, not Blobs: Safari often can't display
  // a Blob read back from IndexedDB ("WebKitBlobResource error 1").
  async putAsset(blob) {
    const id = uuid();
    await this.db.put('assets', { id, data: await blob.arrayBuffer(), type: blob.type });
    return id;
  }

  async assetBlob(id) {
    const rec = await this.db.get('assets', id);
    if (!rec) return null;
    if (rec.data) return new Blob([rec.data], { type: rec.type || '' });
    if (!rec.blob) return null;
    // Older records kept a Blob; copy it into bytes (and migrate) so Safari can use it.
    try {
      const data = await rec.blob.arrayBuffer();
      await this.db.put('assets', { id, data, type: rec.type || rec.blob.type });
      return new Blob([data], { type: rec.type || rec.blob.type });
    } catch {
      return null;
    }
  }

  async assetURL(id) {
    if (this.assetURLs.has(id)) return this.assetURLs.get(id);
    const blob = await this.assetBlob(id);
    if (!blob) return null;
    const url = URL.createObjectURL(blob);
    this.assetURLs.set(id, url);
    return url;
  }

  /** Data URL fallback for viewers that refuse blob: images. */
  async assetDataURL(id) {
    const blob = await this.assetBlob(id);
    return blob ? blobToDataURL(blob) : null;
  }

  async deleteAsset(id) {
    await this.db.delete('assets', id);
    const url = this.assetURLs.get(id);
    if (url) { URL.revokeObjectURL(url); this.assetURLs.delete(id); }
  }

  // ---------- Key/value (calculator data, preferences that must survive) ----------

  async kvGet(key, fallback) { return (await this.db.get('kv', key))?.value ?? fallback; }
  async kvSet(key, value) { await this.db.put('kv', { key, value }); }

  // ---------- Backup ----------

  async exportBackup(extra = {}) {
    const docs = [];
    for (const s of this.summaries) {
      const d = await this.loadDocument(s.id);
      if (d) docs.push(encodeDoc(d));
    }
    const assets = {};
    for (const d of docs) for (const id of collectAssetIds(d)) {
      const blob = await this.assetBlob(id);
      if (blob) assets[id] = await blobToDataURL(blob);
    }
    return JSON.stringify({ format: 'basis-backup', version: 1, exportedAt: new Date().toISOString(), folders: this.folders, docs, assets, ...extra });
  }

  async importBackup(text) {
    const data = JSON.parse(text);
    if (data.format !== 'basis-backup') throw new Error('This file isn’t a Basis backup.');
    for (const [id, url] of Object.entries(data.assets || {})) {
      // Decode the data URL by hand (fetch of data: URLs can be blocked).
      const comma = url.indexOf(',');
      const type = /^data:([^;,]*)/.exec(url)?.[1] || '';
      const bin = atob(url.slice(comma + 1));
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      await this.db.put('assets', { id, data: bytes.buffer, type });
    }
    for (const f of data.folders || []) {
      await this.db.put('folders', f);
      const i = this.folders.findIndex((x) => x.id === f.id);
      if (i >= 0) this.folders[i] = f; else this.folders.push(f);
    }
    for (const raw of data.docs || []) await this.saveDocument(decodeDoc(raw), { touch: false });
    this.changed();
    return { docs: (data.docs || []).length, folders: (data.folders || []).length, extra: data };
  }
}

export function collectAssetIds(doc) {
  const ids = new Set();
  for (const p of doc.pages) {
    if (p.background.image) ids.add(p.background.image);
    if (p.background.pdf?.asset) ids.add(p.background.pdf.asset);
    for (const e of p.elements) if (e.type === 'image') ids.add(e.asset);
  }
  return ids;
}

function blobToDataURL(blob) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = () => reject(r.error);
    r.readAsDataURL(blob);
  });
}

// Stroke points are Float32Arrays; JSON needs plain arrays.
function encodeDoc(d) {
  const c = structuredClone(d);
  for (const p of c.pages) for (const e of p.elements) if (e.type === 'stroke') e.pts = Array.from(e.pts, (v) => Math.round(v * 100) / 100);
  return c;
}
function decodeDoc(d) {
  for (const p of d.pages) for (const e of p.elements) if (e.type === 'stroke') e.pts = Float32Array.from(e.pts);
  return d;
}

export const store = new Store();
