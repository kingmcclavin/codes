// Handwriting recognition: pages are turned into images and read by the
// person's own AI (see ai.js). The text is kept on the document (doc.ocr,
// outside undo history) so search works offline afterwards.

import { aiConfig, autoRecognize, transcribeImage, AIError, setLastAIError } from './ai.js';
import { feature } from './features.js';
import { drawBackground, drawElement, preloadAssets } from './render.js';
import { renderPDFRegion } from './pdf.js';
import { elementBounds } from './elements.js';
import { rectsIntersect } from './util.js';
import { toast } from './ui.js';

/** A fingerprint of what's on a page; recognition reruns when it changes. */
export function pageSignature(p) {
  let h = 5381;
  const add = (s) => { for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0; };
  for (const e of p.elements) add(e.id);
  add(`|${p.background.image || ''}|${p.background.pdf?.asset || ''}#${p.background.pdf?.page ?? ''}|${p.w}x${p.h}`);
  return String(h >>> 0);
}

export const hasContent = (p) => p.elements.length > 0 || !!p.background.image || !!p.background.pdf;

/** Pages are read in pieces no taller than ~1.4× their width, so long pages stay legible. */
export function pageChunks(p) {
  const chunkH = Math.min(p.h, Math.max(p.w * 1.4, 400));
  const out = [];
  for (let y = 0; y < p.h - 1; y += chunkH) {
    const r = { x: 0, y, w: p.w, h: Math.min(chunkH, p.h - y) };
    // Skip empty stretches of a page that has no paper image.
    if (!p.background.image && !p.background.pdf && !p.elements.some((e) => rectsIntersect(elementBounds(e), r))) continue;
    out.push(r);
  }
  return out;
}

async function regionImage(page, r) {
  const scale = Math.min(2.5, 1200 / r.w);
  const c = document.createElement('canvas');
  c.width = Math.max(1, Math.round(r.w * scale));
  c.height = Math.max(1, Math.round(r.h * scale));
  const ctx = c.getContext('2d');
  let paperDone = false;
  if (page.background.pdf) {
    try { ctx.drawImage(await renderPDFRegion(page.background.pdf, page.w, r, scale).promise, 0, 0); paperDone = true; } catch { paperDone = false; }
  }
  ctx.setTransform(scale, 0, 0, scale, -r.x * scale, -r.y * scale);
  if (!paperDone) drawBackground(ctx, page, r);
  ctx.save();
  ctx.beginPath(); ctx.rect(0, 0, page.w, page.h); ctx.clip();
  for (const e of page.elements) if (rectsIntersect(elementBounds(e), r)) drawElement(ctx, e, page);
  ctx.restore();
  const blob = await new Promise((res) => c.toBlob(res, 'image/jpeg', 0.85));
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}

/** Reads one page. Resolves to its text. */
export async function recognizePage(page) {
  await preloadAssets([page]);
  const parts = [];
  for (const r of pageChunks(page)) {
    const text = await transcribeImage(await regionImage(page, r));
    if (text) parts.push(text);
  }
  return parts.join('\n');
}

export const aiAvailable = () => feature('ai') && !!aiConfig();

/** Reads pages of the open notebook in the background, a few seconds after writing stops. */
export class Recognizer {
  constructor(editor) {
    this.editor = editor;
    this.doc = editor.doc;
    // Pages edited this session are read automatically; older ones on request.
    this.openSigs = new Map(this.doc.pages.map((p) => [p.id, pageSignature(p)]));
    this.stopped = false;
    this.running = false;
  }

  stale(p) { return hasContent(p) && this.doc.ocr?.[p.id]?.sig !== pageSignature(p); }

  /** Pages whose writing hasn't been read yet (or changed since). */
  pending({ all = false } = {}) {
    return this.doc.pages.filter((p) => this.stale(p) && (all || this.openSigs.get(p.id) !== pageSignature(p)));
  }

  schedule() {
    if (this.stopped || !aiAvailable() || !autoRecognize()) return;
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.run(), 4000);
  }

  stop() { this.stopped = true; clearTimeout(this.timer); }

  /** Reads pending pages one at a time. With `all`, every page that needs it, reporting progress. */
  async run({ all = false, onProgress } = {}) {
    if (this.running || this.stopped || !aiAvailable()) return { done: 0, failed: 0 };
    this.running = true;
    let done = 0, failed = 0, error = null;
    try {
      const queue = this.pending({ all });
      for (let k = 0; k < queue.length && !this.stopped; k++) {
        // Don't compete with writing: wait until the pen is up.
        while (this.editor.canvas?.interaction && !this.stopped) await new Promise((r) => setTimeout(r, 500));
        const p = this.doc.pages.find((x) => x.id === queue[k].id);
        if (!p || !this.stale(p)) continue;
        onProgress?.(k + 1, queue.length);
        const sig = pageSignature(p);
        try {
          const text = await recognizePage(p);
          if (this.stopped) break;
          (this.doc.ocr ||= {})[p.id] = { sig, text, at: Date.now() };
          this.editor.syncDirty = true;
          done++;
          setLastAIError(null);
          this.editor.save();
        } catch (e) {
          failed++;
          error = e.message || String(e);
          console.warn('Handwriting recognition failed', e);
          setLastAIError(error);
          if (e instanceof AIError && e.stop) { if (!all) toast(`Couldn’t read your handwriting: ${error}`); break; }
          if (all) toast(`Page ${this.doc.pages.indexOf(p) + 1}: ${error}`);
        }
      }
    } finally {
      this.running = false;
    }
    if (!all && !this.stopped && !error && this.pending().length) this.schedule(); // more writing arrived meanwhile
    return { done, failed, error };
  }
}

// ---------- Search ----------

/** Lower-case, without LaTeX punctuation, so "y'' + t sin(t)" finds "$y'' + t\sin(t)$". */
export function searchable(s) {
  return String(s || '').toLowerCase().replace(/\\(?:left|right|,|;|!|quad)/g, ' ').replace(/[$\\{}]/g, '').replace(/\s+/g, ' ');
}

/** All searchable text of one page: typed text, calculation cards, recognized handwriting, PDF text. */
export function pageTexts(doc, p) {
  const out = [];
  for (const e of p.elements) if (e.type === 'text' && e.text) out.push({ kind: e.calc ? 'Calculation' : 'Typed text', text: e.text });
  const ink = doc.ocr?.[p.id]?.text;
  if (ink) out.push({ kind: 'Handwriting', text: ink });
  const pdf = doc.pdfText?.[p.id];
  if (pdf) out.push({ kind: 'PDF', text: pdf });
  return out;
}

/** Matches of `query` in a document: [{ page, kind, snippet: [before, match, after] }]. */
export function findInDocument(doc, query) {
  const q = searchable(query).trim();
  if (!q) return [];
  const hits = [];
  doc.pages.forEach((p, i) => {
    for (const t of pageTexts(doc, p)) {
      const flat = searchable(t.text);
      const at = flat.indexOf(q);
      if (at < 0) continue;
      const s = Math.max(0, at - 40);
      hits.push({ page: i, kind: t.kind, snippet: [(s ? '…' : '') + flat.slice(s, at), flat.slice(at, at + q.length), flat.slice(at + q.length, at + q.length + 70) + (at + q.length + 70 < flat.length ? '…' : '')] });
      break; // one result per page
    }
  });
  return hits;
}
