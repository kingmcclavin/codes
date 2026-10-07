// PDF import (pdf.js) and export (jsPDF), loaded from cdnjs on first use.

import { renderPageCanvas, preloadAssets } from './render.js';
import { store } from './store.js';

const PDFJS = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js';
const PDFJS_WORKER = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
const JSPDF = 'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js';

const loaded = new Map();
const LOAD_ERROR = 'Couldn’t load the PDF library. Check your connection and try again.';

// Bundled copies ship with the app (works offline and where the CDN is
// blocked); the CDN is the fallback.
const LOCAL = {
  [PDFJS]: 'vendor/pdf.min.js',
  [PDFJS_WORKER]: 'vendor/pdf.worker.min.js',
  [JSPDF]: 'vendor/jspdf.umd.min.js',
};

function addScript(src, ready) {
  return new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = src;
    s.onload = () => { if (ready()) resolve(); else { s.remove(); reject(new Error(LOAD_ERROR)); } };
    s.onerror = () => { s.remove(); reject(new Error(LOAD_ERROR)); };
    document.head.append(s);
  });
}

function loadScript(src, ready) {
  if (ready()) return Promise.resolve();
  if (!loaded.has(src)) {
    const p = addScript(new URL(LOCAL[src], document.baseURI).href, ready).catch(() => addScript(src, ready));
    loaded.set(src, p.catch((e) => { loaded.delete(src); throw e; }));
  }
  return loaded.get(src);
}

async function pdfjs() {
  await loadScript(PDFJS, () => !!window.pdfjsLib);
  // Loading the worker as a script lets pdf.js run it on the main thread,
  // which also works where cross-origin workers are blocked.
  await loadScript(PDFJS_WORKER, () => !!window.pdfjsWorker);
  return window.pdfjsLib;
}

/** Renders every page of a PDF file into page images. Returns pages for a document. */
export async function importPDF(file, onProgress = () => {}) {
  const lib = await pdfjs();
  const data = new Uint8Array(await file.arrayBuffer());
  const pdf = await lib.getDocument({ data, isEvalSupported: false }).promise;
  const pages = [];
  for (let n = 1; n <= pdf.numPages; n++) {
    onProgress(n, pdf.numPages);
    const page = await pdf.getPage(n);
    const vp1 = page.getViewport({ scale: 1 });
    const scale = Math.min(2.5, 2400 / Math.max(vp1.width, vp1.height));
    const vp = page.getViewport({ scale });
    const canvas = document.createElement('canvas');
    canvas.width = Math.ceil(vp.width);
    canvas.height = Math.ceil(vp.height);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    await page.render({ canvasContext: ctx, viewport: vp }).promise;
    const blob = await new Promise((r) => canvas.toBlob(r, 'image/jpeg', 0.9));
    const asset = await store.putAsset(blob);
    pages.push({ w: vp1.width, h: vp1.height, asset });
  }
  return pages;
}

/** Renders one page of PDF bytes into a stored page image; also returns the paper's average color. */
export async function renderPDFPageImage(data, pageIndex = 0, { cropAspect = 0 } = {}) {
  const lib = await pdfjs();
  const pdf = await lib.getDocument({ data: data.slice(), isEvalSupported: false }).promise;
  const page = await pdf.getPage(Math.min(pdf.numPages, pageIndex + 1));
  const vp1 = page.getViewport({ scale: 1 });
  if (vp1.width < 2 || vp1.height < 2) { pdf.destroy?.(); throw new Error('empty paper'); }
  // Sharp at page width, within Safari's canvas limit (about 16 megapixels).
  const shownH = cropAspect > 0 ? Math.min(vp1.height, vp1.width * cropAspect) : vp1.height;
  const scale = Math.min(2.5, 2400 / vp1.width, Math.sqrt(12e6 / (vp1.width * shownH)));
  const vp = page.getViewport({ scale });
  const canvas = document.createElement('canvas');
  canvas.width = Math.ceil(vp.width);
  canvas.height = Math.ceil(shownH * scale);
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  await page.render({ canvasContext: ctx, viewport: vp }).promise;
  // With cropAspect only the top of the page is drawn (the canvas clips the rest).
  const canvas2 = canvas;
  // Average colour of the paper (dark paper keeps light ink readable).
  const small = document.createElement('canvas');
  small.width = small.height = 16;
  const sctx = small.getContext('2d', { willReadFrequently: true });
  sctx.drawImage(canvas2, 0, 0, 16, 16);
  const px = sctx.getImageData(0, 0, 16, 16).data;
  let r = 0, g = 0, b = 0;
  for (let i = 0; i < px.length; i += 4) { r += px[i]; g += px[i + 1]; b += px[i + 2]; }
  const n = (px.length / 4) * 255;
  const blob = await new Promise((res) => canvas2.toBlob(res, 'image/jpeg', 0.9));
  const asset = await store.putAsset(blob);
  pdf.destroy?.();
  return { asset, color: { r: r / n, g: g / n, b: b / n, a: 1 } };
}

/** Wraps an image in a one-page PDF of the given size (points). */
export async function imageToPDF(blob, w, h) {
  await loadScript(JSPDF, () => !!window.jspdf);
  const { jsPDF } = window.jspdf;
  const url = await new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(r.result); r.onerror = () => rej(r.error); r.readAsDataURL(blob); });
  const pdf = new jsPDF({ unit: 'pt', format: [w, h], orientation: w > h ? 'l' : 'p', compress: true });
  pdf.addImage(url, blob.type === 'image/png' ? 'PNG' : 'JPEG', 0, 0, w, h, undefined, 'FAST');
  return new Uint8Array(pdf.output('arraybuffer'));
}

/** Exports pages to a PDF blob (each page as a high-resolution image). */
export async function exportPDF(doc, onProgress = () => {}) {
  await loadScript(JSPDF, () => !!window.jspdf);
  const { jsPDF } = window.jspdf;
  await preloadAssets(doc.pages);
  let pdf = null;
  doc.pages.forEach((p, i) => {
    onProgress(i + 1, doc.pages.length);
    const orientation = p.w > p.h ? 'l' : 'p';
    if (!pdf) pdf = new jsPDF({ unit: 'pt', format: [p.w, p.h], orientation, compress: true });
    else pdf.addPage([p.w, p.h], orientation);
    const canvas = renderPageCanvas(p, 2.5, 24e6);
    pdf.addImage(canvas.toDataURL('image/jpeg', 0.92), 'JPEG', 0, 0, p.w, p.h, undefined, 'FAST');
  });
  pdf.setProperties({ title: doc.title, creator: 'Basis' });
  return pdf.output('blob');
}

export async function exportPNG(page) {
  await preloadAssets([page]);
  const canvas = renderPageCanvas(page, 3, 30e6);
  return new Promise((r) => canvas.toBlob(r, 'image/png'));
}
