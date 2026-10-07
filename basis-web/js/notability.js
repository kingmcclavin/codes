// Best-effort import of Notability `.note` files.
//
// A .note file is a zip with a folder holding Session.plist, an
// NSKeyedArchiver binary plist. Handwriting lives in its spatial hash as
// parallel arrays: per-curve point counts, widths, RGBA colours and styles,
// cubic Bézier points (start, then control, control, end …) and a width
// factor for every on-curve point. Notability notes are one long scroll
// with a locked width; it's cut into pages of the note's paper size.
// Ink, paper style and typed text come across; images and audio don't yet.

import { makeStroke } from './elements.js';
import { makeBackground, makeDocument, makePage } from './model.js';
import { ZipReader } from './goodnotes.js';
import { renderPDFPageImage } from './pdf.js';
import { uuid } from './util.js';

export class NotabilityError extends Error {}

const PAPER = { letter: [8.5, 11], legal: [8.5, 14], a4: [8.27, 11.69], a5: [5.83, 8.27], a3: [11.69, 16.54], tabloid: [11, 17] };

export async function importNotability(file, { folderId = null } = {}) {
  let zip;
  try { zip = await ZipReader.open(new Uint8Array(await file.arrayBuffer())); } catch {
    throw new NotabilityError('This doesn’t look like a Notability file.');
  }
  const sessionName = [...zip.entries.keys()].find((n) => /(^|\/)Session\.plist$/.test(n));
  if (!sessionName) throw new NotabilityError('This doesn’t look like a Notability file.');
  const folder = sessionName.slice(0, sessionName.length - 'Session.plist'.length);
  const root = unarchive(parseBPlist(await zip.file(sessionName)));

  const title = str(root.name) || file.name.replace(/\.note$/i, '') || 'Notability Import';
  const result = { strokes: 0, skipped: 0, text: false };

  // Paper: size, orientation and line style ("Dots:false:true:0.5" = dots every 0.5 in).
  const attrs = root.NBNoteTakingSessionDocumentPaperLayoutModelKey?.documentPaperAttributes || {};
  let [inW, inH] = PAPER[String(attrs.paperSize || 'letter').toLowerCase()] || PAPER.letter;
  if (attrs.paperOrientation === 'landscape') [inW, inH] = [inH, inW];
  const pageW = inW * 72, pageH = inH * 72;
  const bg = paperBackground(String(attrs.lineStyle2 || attrs.lineStyle || ''));

  // Notability lays content out at a locked width (574 pt on iPad); scale to the paper.
  const rich = root.richText || {};
  const docWidth = Number(rich.reflowState?.pageWidthInDocumentCoordsKey) || 574;
  const k = pageW / docWidth;

  const strokes = readCurves(rich['Handwriting Overlay']?.SpatialHash, k, result);

  // Pages: enough to hold every stroke (at least one). A stroke goes on the page its middle is on.
  const pagesNeeded = Math.max(1, ...strokes.map((s) => Math.floor(s.midY / pageH) + 1));
  const pages = [];
  for (let i = 0; i < pagesNeeded; i++) pages.push(makePage({ w: pageW, h: pageH }, bg));
  for (const s of strokes) {
    const i = Math.min(pages.length - 1, Math.max(0, Math.floor(s.midY / pageH)));
    const off = i * pageH;
    pages[i].elements.push(makeStroke(s.samples.map((p) => ({ ...p, y: p.y - off })), s.style));
    result.strokes++;
  }

  // Annotated PDFs: their pages become the paper of the first pages.
  for (const name of zip.entries.keys()) {
    if (!name.startsWith(folder + 'PDFs/') || !/\.pdf$/i.test(name)) continue;
    const bytes = await zip.file(name);
    for (let p = 0; bytes && p < pages.length; p++) {
      try { pages[p].background.image = (await renderPDFPageImage(bytes, p)).asset; } catch { break; }
    }
  }

  // Typed text: placed as one text box at the top of the first page.
  const text = typedText(rich);
  if (text) {
    pages[0].elements.unshift({
      type: 'text', id: uuid(), text,
      style: { fontFamily: 'System', fontSize: 16, color: { r: 0.07, g: 0.07, b: 0.08, a: 1 }, bold: false, italic: false, align: 'left' },
      box: { cx: pageW / 2, cy: 48 + 60, w: pageW - 96, h: 120, rot: 0 },
    });
    result.text = true;
  }
  for (const name of zip.entries.keys()) if (name.startsWith(folder + 'Images/') && !name.endsWith('/')) result.skipped++;

  const doc = makeDocument({ title, size: { w: pageW, h: pageH }, background: bg, folderId });
  doc.pages = pages;
  const created = root.creationDate?.['NS.time'];
  if (typeof created === 'number') doc.createdAt = Math.round((created + 978307200) * 1000); // Apple epoch → Unix ms
  return { doc, ...result };
}

function paperBackground(style) {
  const [kind, , , spacing] = style.split(':');
  const template = { Dots: 'dotted', Grid: 'grid', Lines: 'ruled' }[kind] || 'blank';
  const bg = makeBackground(template);
  const inches = parseFloat(spacing);
  if (template !== 'blank' && inches > 0 && inches < 3) bg.spacing = inches * 72;
  return bg;
}

/** Reads the parallel curve arrays into strokes (page-space samples). */
function readCurves(h, k, result) {
  if (!h) return [];
  const n = Number(h.numcurves) || 0;
  if (!n) return [];
  const f32 = (b) => (b ? new Float32Array(b.slice().buffer) : new Float32Array(0));
  const counts = h.curvesnumpoints ? new Int32Array(h.curvesnumpoints.slice().buffer) : null;
  const pts = f32(h.curvespoints), widths = f32(h.curveswidth), frac = f32(h.curvesfractionalwidths);
  const colors = h.curvescolors || new Uint8Array(n * 4);
  const styles = h.curvesstyles || new Uint8Array(n);
  if (!counts) return [];
  const out = [];
  let pi = 0, fi = 0;
  for (let c = 0; c < n; c++) {
    const count = counts[c];
    if (count <= 0 || (pi + count) * 2 > pts.length) { result.skipped++; pi += Math.max(0, count); continue; }
    const P = (i) => ({ x: pts[(pi + i) * 2] * k, y: pts[(pi + i) * 2 + 1] * k });
    const W = (j) => (fi + j < frac.length && frac[fi + j] > 0 ? frac[fi + j] : 1);
    const onCurve = 1 + Math.floor((count - 1) / 3);
    // Flatten the cubic chain; width factors interpolate between on-curve points.
    const samples = [{ ...P(0), m: W(0) }];
    for (let s = 0; s + 3 < count; s += 3) {
      const p0 = P(s), c1 = P(s + 1), c2 = P(s + 2), p1 = P(s + 3);
      const m0 = W(s / 3), m1 = W(s / 3 + 1);
      const len = Math.hypot(c1.x - p0.x, c1.y - p0.y) + Math.hypot(c2.x - c1.x, c2.y - c1.y) + Math.hypot(p1.x - c2.x, p1.y - c2.y);
      const steps = Math.max(2, Math.min(16, Math.ceil(len / 2)));
      for (let j = 1; j <= steps; j++) {
        const t = j / steps, mt = 1 - t;
        samples.push({
          x: mt * mt * mt * p0.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * p1.x,
          y: mt * mt * mt * p0.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * p1.y,
          m: m0 + (m1 - m0) * t,
        });
      }
    }
    if (samples.length === 1) samples.push({ ...samples[0] }); // a dot
    pi += count;
    fi += onCurve;
    const [r, g, b, a] = [colors[c * 4], colors[c * 4 + 1], colors[c * 4 + 2], colors[c * 4 + 3]].map((v) => (v ?? 255) / 255);
    const width = Math.max(0.3, (widths[c] || 2) * k);
    const isHighlighter = a < 0.95 || styles[c] === 1;
    // Per-point width factors map onto the pressure curve (factor ≈ 0.35 + 1.5·force^0.6).
    const mean = samples.reduce((s, p) => s + p.m, 0) / samples.length || 1;
    const force = (m) => Math.pow(Math.min(1, Math.max(0, (Math.min(1.9, Math.max(0.3, m / mean)) - 0.35) / 1.5)), 1 / 0.6);
    const style = {
      kind: isHighlighter ? 'highlighter' : 'fineliner',
      color: { r, g, b, a: 1 },
      width: width * (isHighlighter ? 1 : mean),
      opacity: isHighlighter ? Math.max(0.3, a) : 1,
      pressure: isHighlighter ? 0 : 1, tilt: 0, lineStyle: 'solid',
    };
    const ys = samples.map((p) => p.y);
    out.push({
      style,
      midY: (Math.min(...ys) + Math.max(...ys)) / 2,
      samples: samples.map((p) => ({ x: p.x, y: p.y, force: isHighlighter ? 0.25 : force(p.m), altitude: Math.PI / 2 })),
    });
  }
  return out;
}

function typedText(rich) {
  const pick = (o) => {
    if (!o) return '';
    if (typeof o === 'string') return o;
    if (typeof o['NS.string'] === 'string') return o['NS.string'];
    if (o.stringKey != null) return pick(o.stringKey);
    if (o['NS.bytes']) return new TextDecoder().decode(o['NS.bytes']);
    return '';
  };
  return (pick(rich.attributedString) || pick(rich.NBAttributedBackingString?.NBAttributedBackingStringCodingKey)).replace(/￼/g, '').trim();
}

const str = (v) => (typeof v === 'string' ? v : '');

// ---------- Binary property lists ----------

/** Parses an Apple binary plist (bplist00) into JS values. UIDs become {uid}. */
export function parseBPlist(b) {
  if (!b || String.fromCharCode(...b.subarray(0, 8)) !== 'bplist00') throw new NotabilityError('Unreadable Notability data.');
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const t = b.length - 32;
  const offSize = b[t + 6], refSize = b[t + 7];
  const numObjects = Number(dv.getBigUint64(t + 8)), top = Number(dv.getBigUint64(t + 16)), tableOff = Number(dv.getBigUint64(t + 24));
  const uint = (at, size) => { let v = 0; for (let i = 0; i < size; i++) v = v * 256 + b[at + i]; return v; };
  const offsets = Array.from({ length: numObjects }, (_, i) => uint(tableOff + i * offSize, offSize));
  const cache = new Map();
  const read = (ref, depth = 0) => {
    if (depth > 512) throw new NotabilityError('Notability data is nested too deeply.');
    if (cache.has(ref)) return cache.get(ref);
    let at = offsets[ref];
    const marker = b[at], type = marker >> 4, info = marker & 15;
    const length = () => {
      if (info !== 15) { at += 1; return info; }
      const intMarker = b[at + 1], size = 1 << (intMarker & 15);
      const n = uint(at + 2, size);
      at += 2 + size;
      return n;
    };
    let v;
    switch (type) {
      case 0: v = info === 8 ? false : info === 9 ? true : null; break;
      case 1: { const size = 1 << info; v = size === 8 ? Number(dv.getBigInt64(at + 1)) : uint(at + 1, size); break; }
      case 2: v = info === 2 ? dv.getFloat32(at + 1) : dv.getFloat64(at + 1); break;
      case 3: v = { 'NS.time': dv.getFloat64(at + 1) }; break;
      case 4: { const n = length(); v = b.subarray(at, at + n); break; }
      case 5: { const n = length(); v = String.fromCharCode(...b.subarray(at, at + n)); break; }
      case 6: { const n = length(); let s = ''; for (let i = 0; i < n; i++) s += String.fromCharCode(dv.getUint16(at + i * 2)); v = s; break; }
      case 8: v = { uid: uint(at + 1, info + 1) }; break;
      case 10: case 12: {
        const n = length(); const start = at;
        v = [];
        cache.set(ref, v);
        for (let i = 0; i < n; i++) v.push(read(uint(start + i * refSize, refSize), depth + 1));
        return v;
      }
      case 13: {
        const n = length(); const start = at;
        v = {};
        cache.set(ref, v);
        for (let i = 0; i < n; i++) {
          const key = read(uint(start + i * refSize, refSize), depth + 1);
          v[key] = read(uint(start + (n + i) * refSize, refSize), depth + 1);
        }
        return v;
      }
      default: v = null;
    }
    cache.set(ref, v);
    return v;
  };
  return read(top);
}

/** Resolves an NSKeyedArchiver graph: UIDs become objects; arrays and dicts unwrap. */
export function unarchive(plist) {
  const objs = plist?.$objects;
  if (!Array.isArray(objs)) throw new NotabilityError('Unreadable Notability data.');
  const done = new Map();
  const resolve = (v, depth = 0) => {
    if (depth > 256) return null;
    if (v && typeof v === 'object' && 'uid' in v && Object.keys(v).length === 1) {
      if (done.has(v.uid)) return done.get(v.uid);
      const raw = objs[v.uid];
      if (raw === '$null') return null;
      if (!raw || typeof raw !== 'object' || raw instanceof Uint8Array) { done.set(v.uid, raw); return raw; }
      if (Array.isArray(raw['NS.objects']) && !raw['NS.keys']) {
        const arr = [];
        done.set(v.uid, arr);
        for (const x of raw['NS.objects']) arr.push(resolve(x, depth + 1));
        return arr;
      }
      const out = {};
      done.set(v.uid, out);
      if (Array.isArray(raw['NS.keys'])) {
        raw['NS.keys'].forEach((key, i) => { out[resolve(key, depth + 1)] = resolve(raw['NS.objects'][i], depth + 1); });
      } else {
        for (const [key, val] of Object.entries(raw)) if (key !== '$class') out[key] = resolve(val, depth + 1);
      }
      return out;
    }
    return v;
  };
  const topKey = Object.keys(plist.$top || {})[0];
  return resolve(plist.$top[topKey]) || {};
}
