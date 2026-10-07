// Best-effort import of GoodNotes 6 `.goodnotes` files (ported from
// GoodNotesImporter.swift).
//
// The format isn't documented; this reads what's been worked out from real
// files: a zip of protobuf logs. Pages, their paper (the template PDF), pen
// and highlighter strokes (as editable Basis ink) and images come across.
// Typed text boxes and other objects are skipped.

import { uuid } from './util.js';
import { makeStroke } from './elements.js';
import { makeBackground, makeDocument, makePage } from './model.js';
import { store } from './store.js';
import { renderPDFPageImage } from './pdf.js';

export class GoodNotesError extends Error {}

/** Converts a .goodnotes file into a Basis document (assets are stored as it goes). */
export async function importGoodNotes(file, { folderId = null, onProgress = () => {} } = {}) {
  let zip;
  try { zip = await ZipReader.open(new Uint8Array(await file.arrayBuffer())); } catch {
    throw new GoodNotesError('This doesn’t look like a GoodNotes file.');
  }
  const events = await zip.file('index.events.pb');
  if (!events) throw new GoodNotesError('This doesn’t look like a GoodNotes file.');

  let title = file.name.replace(/\.goodnotes$/i, '') || 'GoodNotes Import';
  const templates = new Map();
  const pages = new Map();
  const deleted = new Set();
  const paperChanges = new Map();
  for (const message of delimited(events)) {
    for (const f of fields(message)) {
      if (!f.bytes) continue;
      const m = fields(f.bytes);
      switch (f.number) {
        case 30: { // document: 2.1 = title
          const t = str(msg(m, 2), 1);
          if (t) title = t;
          break;
        }
        case 2: { // page template (paper)
          const id = str(m, 2);
          if (!id) break;
          const size = msg(m, 8);
          templates.set(id, { name: str(m, 9) || '', attachment: str(m, 4), w: flt(size, 1) ?? 612, h: flt(size, 2) ?? 792, pageIndex: Math.max(0, Number(vint(m, 5) ?? 1) - 1) });
          break;
        }
        case 54: { // page
          const id = str(m, 2);
          if (id) pages.set(id, { id, template: str(msg(m, 3), 1), order: str(msg(m, 4), 1) ?? id });
          break;
        }
        case 3: { // page paper changed (e.g. switched to a long page); later events win
          const id = str(m, 2), template = str(msg(m, 3), 1);
          if (id && template) paperChanges.set(id, template);
          break;
        }
        case 56: { // page deleted
          const id = str(m, 2);
          if (id) deleted.add(id);
          break;
        }
      }
    }
  }
  for (const [id, template] of paperChanges) if (pages.has(id) && templates.has(template)) pages.get(id).template = template;
  const ordered = [...pages.values()].filter((p) => !deleted.has(p.id)).sort((a, b) => (a.order < b.order ? -1 : a.order > b.order ? 1 : 0));
  if (!ordered.length) throw new GoodNotesError('No pages could be read from this GoodNotes file.');

  const result = { strokes: 0, images: 0, skipped: 0, paperErrors: [] };
  const paperCache = new Map();
  const imageAssets = new Map();
  const outPages = [];
  for (let n = 0; n < ordered.length; n++) {
    onProgress(n + 1, ordered.length);
    const gn = ordered[n];
    const t = gn.template ? templates.get(gn.template) : null;
    const size = { w: t?.w ?? 612, h: t?.h ?? 792 };
    const bg = makeBackground('blank');
    if (t?.attachment) {
      const key = `${t.attachment}#${t.pageIndex}`;
      if (!paperCache.has(key)) {
        const pdf = await zip.file(`attachments/${t.attachment}`);
        let paper = null;
        if (isPDF(pdf)) {
          try { paper = await renderPDFPageImage(pdf, t.pageIndex); } catch (e) { paper = null; if (!/empty/.test(e.message)) result.paperErrors.push(e.message || String(e)); }
        }
        // GoodNotes sometimes exports built-in paper as an empty placeholder PDF. Use the
        // same paper family from another template in the file (e.g. its long-page version).
        if (!paper) {
          const family = paperFamily(t.name);
          for (const other of templates.values()) {
            if (paper || other === t || !family || paperFamily(other.name) !== family || !other.attachment) continue;
            const bytes = await zip.file(`attachments/${other.attachment}`);
            if (!isPDF(bytes)) continue;
            try { paper = await renderPDFPageImage(bytes, other.pageIndex, { cropAspect: t.h / t.w }); } catch { paper = null; }
          }
        }
        paperCache.set(key, paper);
      }
      const paper = paperCache.get(key);
      if (paper) {
        bg.image = paper.asset;
        bg.color = paper.color;
      }
    }
    const page = makePage(size, bg);
    const notesId = incrementedUUID(gn.id);
    const notes = notesId ? (await zip.file(`notes/${notesId}`)) || (await zip.file(`notes/${notesId.toLowerCase()}`)) : null;
    if (notes) page.elements = await elementsFromNotes(notes, zip, result, imageAssets);
    outPages.push(page);
  }

  const doc = makeDocument({ title, size: { w: outPages[0].w, h: outPages[0].h }, background: makeBackground('blank'), folderId });
  doc.pages = outPages;
  return { doc, ...result };
}

const isPDF = (b) => !!b && b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46; // %PDF

/** "CC365888-…_standard_1_3 - Black" and "CC365888-…_455_5000_1_3 - Black" are the same paper. */
function paperFamily(name) {
  const parts = String(name || '').split('_');
  return parts.length >= 2 ? `${parts[0]}|${parts[parts.length - 1]}` : '';
}

/** A page's ink lives in `notes/<page id + 1>`. */
export function incrementedUUID(s) {
  const hex = String(s).replace(/-/g, '');
  if (!/^[0-9a-fA-F]{32}$/.test(hex)) return null;
  const bytes = hex.match(/../g).map((x) => parseInt(x, 16));
  for (let i = 15; i >= 0; i--) {
    bytes[i] = (bytes[i] + 1) & 255;
    if (bytes[i] !== 0) break;
  }
  const h = bytes.map((b) => b.toString(16).padStart(2, '0')).join('').toUpperCase();
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

/** Notes files are logs of (header, body) records. A header with field 3 set
 *  marks an erased object; the last record for an id wins. */
async function elementsFromNotes(data, zip, result, imageAssets) {
  const order = [];
  const latest = new Map();
  const erased = new Set();
  // Elements (lasso groups) that ink can live inside: id → origin and scale. Last record wins.
  const containers = new Map();
  for (const message of delimited(data)) {
    const c = msg(fields(message), 20);
    const id = str(c, 1), t = msg(c, 20);
    if (id && t) containers.set(id, { x: flt(msg(t, 1), 1) ?? 0, y: flt(msg(t, 1), 2) ?? 0, scale: flt(t, 3) || 1 });
  }
  for (const message of delimited(data)) {
    const fs = fields(message);
    const headerId = str(fs, 1);
    if (headerId && msg(fs, 2)) {
      if (Number(vint(fs, 3) ?? 0) !== 0) erased.add(headerId); else erased.delete(headerId);
      continue;
    }
    const strokeBody = msg(fs, 7);
    const strokeId = str(strokeBody, 1);
    if (strokeBody && strokeId) {
      const s = strokeFrom(strokeBody, containers);
      if (s) {
        if (!latest.has(strokeId)) order.push(strokeId);
        latest.set(strokeId, s);
      } else erased.add(strokeId);
      continue;
    }
    const imageBody = msg(fs, 1);
    const imageId = str(imageBody, 1), attachment = str(imageBody, 4);
    if (imageBody && imageId && attachment) {
      const rect = msg(imageBody, 2), origin = msg(rect, 1), size = msg(rect, 2);
      const file = origin && size ? await zip.file(`attachments/${attachment}`) : null;
      if (!file) { result.skipped++; continue; }
      if (!imageAssets.has(attachment)) {
        const isPNG = file[0] === 0x89 && file[1] === 0x50 && file[2] === 0x4e && file[3] === 0x47;
        imageAssets.set(attachment, await store.putAsset(new Blob([file], { type: isPNG ? 'image/png' : 'image/jpeg' })));
      }
      const x = flt(origin, 1) ?? 0, y = flt(origin, 2) ?? 0, w = flt(size, 1) ?? 100, h = flt(size, 2) ?? 100;
      if (!latest.has(imageId)) order.push(imageId);
      latest.set(imageId, { type: 'image', id: uuid(), asset: imageAssets.get(attachment), box: { cx: x + w / 2, cy: y + h / 2, w, h, rot: 0 }, opacity: 1 });
    }
  }
  const out = [];
  for (const id of order) {
    if (erased.has(id) || !latest.has(id)) continue;
    const e = latest.get(id);
    if (e.type === 'stroke') result.strokes++; else result.images++;
    out.push(e);
  }
  return out;
}

/** Stroke body: 2 = compressed geometry, 4 = RGBA colour. */
function strokeFrom(body, containers = new Map()) {
  const blob = bytesOf(body, 2);
  const raw = blob && decodeAppleLZ4(blob);
  const geometry = raw && parseStrokeGeometry(raw);
  if (!geometry || !geometry.points.length) return null;
  const rgba = msg(body, 4);
  const r = flt(rgba, 1) ?? 0, g = flt(rgba, 2) ?? 0, b = flt(rgba, 3) ?? 0, a = flt(rgba, 4) ?? 1;
  const isHighlighter = a < 0.95 || geometry.width >= 12;
  const style = {
    kind: isHighlighter ? 'highlighter' : 'fineliner',
    color: { r, g, b, a: isHighlighter ? 1 : a },
    width: Math.max(0.3, geometry.width * (containerScale(body, containers))),
    opacity: isHighlighter ? Math.max(0.3, a) : 1,
    pressure: 0, tilt: 0, lineStyle: 'solid',
  };
  // Field 6 is a translation GoodNotes records when ink is moved with the
  // lasso. Ink inside an element (field 100 → a container record) is stored
  // relative to it: page position = container origin + scale × (points + offset).
  const move = msg(body, 6);
  let dx = flt(move, 1) ?? 0, dy = flt(move, 2) ?? 0;
  let ox = 0, oy = 0, k = 1;
  const parent = str(msg(body, 100), 1);
  if (parent && containers.has(parent)) ({ x: ox, y: oy, scale: k } = containers.get(parent));
  const pts = geometry.points.map((p) => ({ x: ox + k * (p.x + dx), y: oy + k * (p.y + dy), force: 0.25 }));
  if (pts.length === 1) pts.push({ ...pts[0] }); // a dot
  return makeStroke(pts, style);
}

function containerScale(body, containers) {
  const parent = str(msg(body, 100), 1);
  return parent && containers.has(parent) ? containers.get(parent).scale : 1;
}

/** GoodNotes stroke geometry ("tpl" record): a start point followed by
 *  quadratic segments (control, end), plus the pen width. */
export function parseStrokeGeometry(b) {
  if (b.length <= 12 || b[0] !== 0x74 || b[1] !== 0x70 || b[2] !== 0x6c || b[3] !== 0) return null;
  let i = 8;
  const nul = b.indexOf(0, i);
  if (nul < 0) return null;
  const signature = new TextDecoder().decode(b.subarray(i, nul));
  // Only the layout seen in GoodNotes 6 files is understood.
  if (!signature.startsWith('vuA(v)A(S(uu))A(S(uuuu))')) return null;
  i = nul + 1;
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const u16 = () => { if (i + 2 > b.length) return null; const v = dv.getUint16(i, true); i += 2; return v; };
  const u32 = () => { if (i + 4 > b.length) return null; const v = dv.getUint32(i, true); i += 4; return v; };
  const f32 = () => { if (i + 4 > b.length) return null; const v = dv.getFloat32(i, true); i += 4; return v; };
  if (u16() == null) return null;
  const w = f32(), typeCount = u32();
  if (w == null || typeCount == null || typeCount >= 1e6) return null;
  i += typeCount * 2;
  const startCount = u32();
  if (startCount == null || startCount > 1) return null;
  const pts = [];
  if (startCount === 1) {
    const x = f32(), y = f32();
    if (x == null || y == null) return null;
    pts.push({ x, y });
  }
  const segments = u32();
  if (segments == null || segments >= 1e6) return null;
  for (let s = 0; s < segments; s++) {
    const cx = f32(), cy = f32(), ex = f32(), ey = f32();
    const p0 = pts[pts.length - 1];
    if (ex == null || ey == null || cx == null || cy == null || !p0) return null;
    // Sample the quadratic curve: enough points for smooth ink.
    const steps = Math.max(2, Math.min(12, Math.floor((Math.hypot(cx - p0.x, cy - p0.y) + Math.hypot(ex - cx, ey - cy)) / 2)));
    for (let k = 1; k <= steps; k++) {
      const t = k / steps, mt = 1 - t;
      pts.push({ x: mt * mt * p0.x + 2 * mt * t * cx + t * t * ex, y: mt * mt * p0.y + 2 * mt * t * cy + t * t * ey });
    }
  }
  if (!Number.isFinite(w) || !pts.every((p) => Number.isFinite(p.x) && Number.isFinite(p.y))) return null;
  return { width: w, points: pts };
}

// ---------- Protobuf (just enough to read) ----------

function readVarint(b, pos) {
  let result = 0n, shift = 0n;
  while (pos.i < b.length && shift < 64n) {
    const c = b[pos.i++];
    result |= BigInt(c & 0x7f) << shift;
    if ((c & 0x80) === 0) return result;
    shift += 7n;
  }
  return null;
}

/** Messages each prefixed by a varint length. */
export function delimited(b) {
  const out = [];
  const pos = { i: 0 };
  while (pos.i < b.length) {
    const n = readVarint(b, pos);
    if (n == null || n > BigInt(b.length - pos.i)) break;
    out.push(b.subarray(pos.i, pos.i + Number(n)));
    pos.i += Number(n);
  }
  return out;
}

export function fields(b) {
  const out = [];
  if (!b) return out;
  const pos = { i: 0 };
  while (pos.i < b.length) {
    const key = readVarint(b, pos);
    if (key == null) break;
    const number = Number(key >> 3n);
    if (number <= 0) break;
    switch (Number(key & 7n)) {
      case 0: { const v = readVarint(b, pos); if (v == null) return out; out.push({ number, varint: v }); break; }
      case 1: if (pos.i + 8 > b.length) return out; pos.i += 8; break;
      case 2: {
        const n = readVarint(b, pos);
        if (n == null || n > BigInt(b.length - pos.i)) return out;
        out.push({ number, bytes: b.subarray(pos.i, pos.i + Number(n)) });
        pos.i += Number(n);
        break;
      }
      case 5: {
        if (pos.i + 4 > b.length) return out;
        out.push({ number, fixed32: new DataView(b.buffer, b.byteOffset + pos.i, 4).getFloat32(0, true) });
        pos.i += 4;
        break;
      }
      default: return out;
    }
  }
  return out;
}

const bytesOf = (fs, n) => fs?.find((f) => f.number === n && f.bytes)?.bytes ?? null;
const str = (fs, n) => { const b = bytesOf(fs, n); return b ? new TextDecoder().decode(b) : null; };
const msg = (fs, n) => { const b = bytesOf(fs, n); return b ? fields(b) : null; };
const vint = (fs, n) => fs?.find((f) => f.number === n && f.varint != null)?.varint ?? null;
const flt = (fs, n) => fs?.find((f) => f.number === n && f.fixed32 != null)?.fixed32 ?? null;

// ---------- LZ4 (Apple "bv41" frames) ----------

export function decodeAppleLZ4(b) {
  const out = [];
  let i = 0;
  const u32 = (at) => (b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)) >>> 0;
  const magic = (at) => String.fromCharCode(b[at], b[at + 1], b[at + 2], b[at + 3]);
  while (i + 4 <= b.length) {
    const m = magic(i);
    if (m === 'bv4$') break;
    if (m === 'bv41') {
      if (i + 12 > b.length) return null;
      const size = u32(i + 4), compressed = u32(i + 8);
      if (i + 12 + compressed > b.length || size >= 50e6) return null;
      const block = decodeBlock(b, i + 12, i + 12 + compressed, size);
      if (!block) return null;
      for (const x of block) out.push(x);
      i += 12 + compressed;
    } else if (m === 'bv4-') {
      if (i + 8 > b.length) return null;
      const size = u32(i + 4);
      if (i + 8 + size > b.length) return null;
      for (let k = 0; k < size; k++) out.push(b[i + 8 + k]);
      i += 8 + size;
    } else return null;
  }
  return out.length ? Uint8Array.from(out) : null;
}

function decodeBlock(src, start, end, expected) {
  const out = new Uint8Array(expected);
  let o = 0, i = start;
  while (i < end) {
    const token = src[i++];
    let literal = token >> 4;
    if (literal === 15) { while (i < end) { const x = src[i++]; literal += x; if (x !== 255) break; } }
    if (i + literal > end || o + literal > expected) return null;
    out.set(src.subarray(i, i + literal), o);
    o += literal; i += literal;
    if (i >= end) break;
    if (i + 2 > end) return null;
    const offset = src[i] | (src[i + 1] << 8);
    i += 2;
    let match = token & 15;
    if (match === 15) { while (i < end) { const x = src[i++]; match += x; if (x !== 255) break; } }
    match += 4;
    if (offset <= 0 || offset > o || o + match > expected) return null;
    for (let k = 0; k < match; k++) { out[o] = out[o - offset]; o++; }
  }
  return out.subarray(0, o);
}

// ---------- Zip (stored and deflate entries) ----------

export class ZipReader {
  static async open(b) {
    const z = new ZipReader();
    z.b = b;
    z.entries = new Map();
    const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
    const u16 = (at) => dv.getUint16(at, true), u32 = (at) => dv.getUint32(at, true);
    if (b.length < 22) throw new Error('not a zip');
    let eocd = -1;
    for (let k = b.length - 22; k >= Math.max(0, b.length - 65557); k--) {
      if (b[k] === 0x50 && b[k + 1] === 0x4b && b[k + 2] === 0x05 && b[k + 3] === 0x06) { eocd = k; break; }
    }
    if (eocd < 0) throw new Error('not a zip');
    const count = u16(eocd + 10);
    let p = u32(eocd + 16);
    for (let n = 0; n < count; n++) {
      if (p + 46 > b.length || u32(p) !== 0x02014b50) throw new Error('bad zip');
      const method = u16(p + 10), compressed = u32(p + 20), size = u32(p + 24);
      const nameLen = u16(p + 28), extra = u16(p + 30), comment = u16(p + 32), local = u32(p + 42);
      const name = new TextDecoder().decode(b.subarray(p + 46, p + 46 + nameLen));
      z.entries.set(name, { local, method, compressed, size });
      p += 46 + nameLen + extra + comment;
    }
    z.dv = dv;
    return z;
  }

  async file(name) {
    const e = this.entries.get(name);
    if (!e || e.local + 30 > this.b.length) return null;
    const nameLen = this.dv.getUint16(e.local + 26, true), extra = this.dv.getUint16(e.local + 28, true);
    const start = e.local + 30 + nameLen + extra;
    if (start + e.compressed > this.b.length) return null;
    const payload = this.b.subarray(start, start + e.compressed);
    if (e.method === 0) return payload;
    if (e.method !== 8) return null;
    if (e.size === 0) return new Uint8Array(0);
    if (typeof DecompressionStream === 'undefined') throw new GoodNotesError('This browser can’t unzip GoodNotes files. Update Safari or use Chrome.');
    const stream = new Blob([payload]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }
}
