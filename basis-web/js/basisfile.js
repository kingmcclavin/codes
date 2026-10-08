// `.basis` notebook files, compatible with the Basis iPad app: one JSON
// NotebookArchive (manifest, every page with its ink as vectors, and the
// images/PDFs it uses as base64), exactly as Swift's JSONEncoder writes it.
// Exported notebooks restore in the iPad app; its .basis files import here.

import { uuid, hexToRgba, rgbaToHex } from './util.js';
import { STRIDE, makeStroke } from './elements.js';
import { makeBackground, makePage, makeDocument, defaultSettings } from './model.js';
import { store } from './store.js';
import { imageToPDF, renderPDFPageImage } from './pdf.js';

const ARCHIVE_VERSION = 1, FORMAT_VERSION = 1;

// Web font ids ↔ the iPad app's font families.
const FONT_TO_IOS = { System: 'System', Serif: 'New York', Helvetica: 'Helvetica Neue', Georgia: 'Georgia', Times: 'Times New Roman', Mono: 'Menlo', Courier: 'Courier New', Handwriting: 'Noteworthy' };
const FONT_FROM_IOS = { ...Object.fromEntries(Object.entries(FONT_TO_IOS).map(([k, v]) => [v, k])), 'Avenir Next': 'Helvetica', 'Marker Felt': 'Handwriting', 'Chalkboard SE': 'Handwriting' };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const swiftUUID = (id) => (UUID_RE.test(id) ? id.toUpperCase() : uuid().toUpperCase());
// Swift's .iso8601 date strategy has no fractional seconds.
const swiftDate = (ms) => new Date(ms || Date.now()).toISOString().replace(/\.\d{3}Z$/, 'Z');
const rgba = (c) => ({ r: c?.r ?? 0, g: c?.g ?? 0, b: c?.b ?? 0, a: c?.a ?? 1 });
const P = (p) => [p.x, p.y];

function toBase64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
function fromBase64(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// ---------- Export ----------

export async function exportBasis(doc, onProgress = () => {}) {
  const assets = {};
  const addAsset = async (id, ext, crop = null) => {
    const name = crop ? `${id}-crop-${[crop.x, crop.y, crop.w, crop.h].map((v) => Math.round(v * 1e4)).join('-')}.png` : `${id}.${ext}`;
    if (!assets[name]) {
      const blob = await store.assetBlob(id);
      if (!blob) return null;
      // The iPad app has no crop setting, so a cropped image is exported as just the cropped part.
      const out = crop ? await cropBlob(blob, crop) : blob;
      if (!out) return null;
      assets[name] = toBase64(new Uint8Array(await out.arrayBuffer()));
    }
    return name;
  };
  const pages = [];
  for (let i = 0; i < doc.pages.length; i++) {
    onProgress(i + 1, doc.pages.length);
    const p = doc.pages[i];
    const bg = p.background;
    const background = { color: rgba(bg.color), template: bg.template || 'blank', spacing: bg.spacing ?? 24 };
    if (bg.section) background.section = bg.section;
    if (bg.autoExtends) background.autoExtends = true;
    if (bg.image) {
      // The iPad app draws page backgrounds from PDFs, so wrap the page image in one.
      const name = `page-${bg.image}.pdf`;
      if (!assets[name]) {
        const blob = await store.assetBlob(bg.image);
        if (blob) assets[name] = toBase64(await imageToPDF(blob, p.w, p.h));
      }
      if (assets[name]) background.pdf = { assetName: name, pageIndex: 0 };
    }
    const elements = [];
    for (const e of p.elements) {
      const out = await exportElement(e, addAsset);
      if (out) elements.push(out);
    }
    pages.push({ id: swiftUUID(p.id), size: [p.w, p.h], background, elements });
  }
  const manifest = {
    formatVersion: FORMAT_VERSION,
    id: swiftUUID(doc.id),
    title: doc.title || 'Untitled',
    createdAt: swiftDate(doc.createdAt),
    modifiedAt: swiftDate(doc.modifiedAt),
    pageIDs: pages.map((p) => p.id),
    firstPageSize: pages[0].size,
    toolSettings: {},
    viewState: { pageIndex: 0, zoomScale: 0, contentOffset: [0, 0] },
  };
  if (doc.color) manifest.color = rgba(hexToRgba(doc.color));
  const archive = { archiveVersion: ARCHIVE_VERSION, manifest, pages, assets };
  return new Blob([JSON.stringify(archive)], { type: 'application/json' });
}

function box(b) { return { center: [b.cx, b.cy], size: [b.w, b.h], rotation: b.rot || 0 }; }

async function exportElement(e, addAsset) {
  switch (e.type) {
    case 'stroke': {
      // Swift packs 6 little-endian floats per point: x, y, force, altitude, azimuth, t.
      const n = e.pts.length / STRIDE;
      const packed = new Float32Array(n * 6);
      for (let i = 0; i < n; i++) {
        packed[i * 6] = e.pts[i * 4]; packed[i * 6 + 1] = e.pts[i * 4 + 1];
        packed[i * 6 + 2] = e.pts[i * 4 + 2]; packed[i * 6 + 3] = e.pts[i * 4 + 3];
      }
      const s = e.style;
      return {
        type: 'stroke',
        stroke: {
          id: swiftUUID(e.id),
          style: { kind: s.kind, color: rgba(s.color), width: s.width, opacity: s.opacity ?? 1, pressureSensitivity: s.pressure ?? 0, tiltSensitivity: s.tilt ?? 0, lineStyle: s.lineStyle || 'solid' },
          createdAt: swiftDate(),
          points: toBase64(new Uint8Array(packed.buffer)),
        },
      };
    }
    case 'shape': {
      const g = e.geom;
      let geometry;
      if (g.kind === 'line') geometry = { line: { start: P(g.a), end: P(g.b) } };
      else if (g.kind === 'ellipse') geometry = { ellipse: { _0: box(g.box) } };
      else if (g.kind === 'rect') geometry = { rectangle: { _0: box(g.box) } };
      else if (g.kind === 'polygon') geometry = { polygon: { points: g.pts.map(P), closed: !!g.closed } };
      else geometry = { curve: { points: g.pts.map(P) } };
      const st = e.style;
      const style = { strokeColor: rgba(st.strokeColor), lineWidth: st.lineWidth, opacity: st.opacity ?? 1, lineStyle: st.lineStyle || 'solid' };
      if (st.fill) style.fillColor = rgba(st.fill);
      return { type: 'shape', shape: { id: swiftUUID(e.id), geometry, style, arrows: { start: !!e.arrows?.start, end: !!e.arrows?.end } } };
    }
    case 'image': {
      const blob = await store.assetBlob(e.asset);
      const ext = blob?.type === 'image/png' ? 'png' : 'jpg';
      const assetName = await addAsset(e.asset, ext, e.crop || null);
      if (!assetName) return null;
      return { type: 'image', image: { id: swiftUUID(e.id), assetName, box: box(e.box), opacity: e.opacity ?? 1 } };
    }
    case 'text': {
      const st = e.style;
      const text = {
        id: swiftUUID(e.id),
        text: e.text,
        style: { fontFamily: FONT_TO_IOS[st.fontFamily] || 'System', fontSize: st.fontSize, color: rgba(st.color), bold: !!st.bold, italic: !!st.italic, alignment: st.align || 'left' },
        box: box(e.box),
      };
      // Calculation cards stay live in the iPad app as typed-expression blocks.
      if (e.calc?.source) text.calculation = { formula: { name: 'Calculation', expression: e.calc.source }, showsTitle: false };
      return { type: 'text', text };
    }
  }
  return null;
}

// ---------- Import ----------

export function isBasisArchive(json) {
  return json && typeof json === 'object' && json.manifest && Array.isArray(json.pages) && 'archiveVersion' in json;
}

const pt = (a) => ({ x: a?.[0] ?? 0, y: a?.[1] ?? 0 });
const unbox = (b) => ({ cx: b?.center?.[0] ?? 0, cy: b?.center?.[1] ?? 0, w: b?.size?.[0] ?? 0, h: b?.size?.[1] ?? 0, rot: b?.rotation ?? 0 });

/** Builds a Basis web document from a parsed .basis archive (assets are stored as it goes). */
export async function importBasis(archive, { folderId = null, onProgress = () => {} } = {}) {
  if (!isBasisArchive(archive)) throw new Error('This file isn’t a Basis notebook.');
  if ((archive.archiveVersion ?? 1) > ARCHIVE_VERSION || (archive.manifest.formatVersion ?? 1) > FORMAT_VERSION) {
    throw new Error('This notebook was made by a newer version of Basis.');
  }
  const assetBytes = (name) => (archive.assets?.[name] ? fromBase64(archive.assets[name]) : null);
  const imageAssets = new Map();
  const pdfPages = new Map();
  const m = archive.manifest;
  const pages = [];
  for (let i = 0; i < archive.pages.length; i++) {
    onProgress(i + 1, archive.pages.length);
    const pd = archive.pages[i];
    const b = pd.background || {};
    const bg = makeBackground(b.template || 'blank', b.color ? rgba(b.color) : undefined, b.spacing);
    bg.section = b.section || null;
    bg.autoExtends = !!b.autoExtends;
    if (b.pdf?.assetName) {
      const key = `${b.pdf.assetName}#${b.pdf.pageIndex || 0}`;
      if (!pdfPages.has(key)) {
        const bytes = assetBytes(b.pdf.assetName);
        let res = null;
        if (bytes) { try { res = await renderPDFPageImage(bytes, b.pdf.pageIndex || 0); } catch { res = null; } }
        pdfPages.set(key, res);
      }
      if (pdfPages.get(key)) { bg.image = pdfPages.get(key).asset; bg.pdf = pdfPages.get(key).pdf; }
    }
    const page = makePage({ w: pd.size?.[0] ?? 612, h: pd.size?.[1] ?? 792 }, bg);
    page.id = pd.id || page.id;
    for (const raw of pd.elements || []) {
      const e = await importElement(raw, assetBytes, imageAssets);
      if (e) page.elements.push(e);
    }
    pages.push(page);
  }
  if (!pages.length) pages.push(makePage({ w: m.firstPageSize?.[0] ?? 612, h: m.firstPageSize?.[1] ?? 792 }, makeBackground('blank')));
  const doc = makeDocument({ title: m.title || 'Untitled', size: { w: pages[0].w, h: pages[0].h }, background: makeBackground('blank'), folderId, color: m.color ? rgbaToHex(m.color) : null });
  doc.pages = pages;
  doc.settings = defaultSettings();
  const created = Date.parse(m.createdAt);
  if (!Number.isNaN(created)) doc.createdAt = created;
  // Keep the notebook's id unless this library already has it (then import a copy).
  if (m.id && !store.summary(String(m.id).toLowerCase())) doc.id = String(m.id).toLowerCase();
  return doc;
}

async function cropBlob(blob, c) {
  try {
    const img = await createImageBitmap(blob);
    const sx = Math.round(c.x * img.width), sy = Math.round(c.y * img.height);
    const sw = Math.max(1, Math.round(c.w * img.width)), sh = Math.max(1, Math.round(c.h * img.height));
    const canvas = document.createElement('canvas');
    canvas.width = sw; canvas.height = sh;
    canvas.getContext('2d').drawImage(img, sx, sy, sw, sh, 0, 0, sw, sh);
    img.close?.();
    return await new Promise((res) => canvas.toBlob(res, 'image/png'));
  } catch {
    return null;
  }
}

async function importElement(raw, assetBytes, imageAssets) {
  switch (raw?.type) {
    case 'stroke': {
      const s = raw.stroke, st = s.style || {};
      const bytes = fromBase64(s.points || '');
      const f = new Float32Array(bytes.buffer, 0, Math.floor(bytes.length / 4));
      const samples = [];
      for (let i = 0; i + 3 < f.length; i += 6) samples.push({ x: f[i], y: f[i + 1], force: f[i + 2], altitude: f[i + 3] });
      if (!samples.length) return null;
      const style = { kind: st.kind || 'fineliner', color: rgba(st.color), width: st.width ?? 1.5, opacity: st.opacity ?? 1, pressure: st.pressureSensitivity ?? 0, tilt: st.tiltSensitivity ?? 0, lineStyle: st.lineStyle || 'solid' };
      return { ...makeStroke(samples, style), id: s.id || uuid() };
    }
    case 'shape': {
      const s = raw.shape, g = s.geometry || {};
      let geom = null;
      if (g.line) geom = { kind: 'line', a: pt(g.line.start), b: pt(g.line.end) };
      else if (g.ellipse) geom = { kind: 'ellipse', box: unbox(g.ellipse._0) };
      else if (g.rectangle) geom = { kind: 'rect', box: unbox(g.rectangle._0) };
      else if (g.polygon) geom = { kind: 'polygon', pts: (g.polygon.points || []).map(pt), closed: !!g.polygon.closed };
      else if (g.curve) geom = { kind: 'curve', pts: (g.curve.points || []).map(pt) };
      if (!geom) return null;
      const st = s.style || {};
      return {
        type: 'shape', id: s.id || uuid(), geom,
        style: { strokeColor: rgba(st.strokeColor), lineWidth: st.lineWidth ?? 2, opacity: st.opacity ?? 1, fill: st.fillColor ? rgba(st.fillColor) : null, lineStyle: st.lineStyle || 'solid' },
        arrows: { start: !!s.arrows?.start, end: !!s.arrows?.end },
      };
    }
    case 'image': {
      const im = raw.image;
      if (!imageAssets.has(im.assetName)) {
        const bytes = assetBytes(im.assetName);
        if (!bytes) return null;
        const isPNG = bytes[0] === 0x89 && bytes[1] === 0x50;
        imageAssets.set(im.assetName, await store.putAsset(new Blob([bytes], { type: isPNG ? 'image/png' : 'image/jpeg' })));
      }
      return { type: 'image', id: im.id || uuid(), asset: imageAssets.get(im.assetName), box: unbox(im.box), opacity: im.opacity ?? 1 };
    }
    case 'text': {
      const t = raw.text, st = t.style || {};
      const el = {
        type: 'text', id: t.id || uuid(), text: t.text || '',
        style: { fontFamily: FONT_FROM_IOS[st.fontFamily] || 'System', fontSize: st.fontSize ?? 18, color: rgba(st.color), bold: !!st.bold, italic: !!st.italic, align: st.alignment || 'left' },
        box: unbox(t.box),
      };
      const c = t.calculation;
      if (c?.formula?.expression) {
        // Saved-formula cards keep their inputs as "name = value" lines.
        const inputs = Object.entries(c.inputs || {}).map(([k, v]) => `${k} = ${v}`);
        el.calc = { source: [...inputs, c.formula.expression].join('\n') };
      }
      return el;
    }
  }
  return null;
}
