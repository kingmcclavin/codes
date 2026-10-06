// PDF import (pdf.js) and export (jsPDF), loaded from cdnjs on first use.

import { renderPageCanvas, preloadAssets } from './render.js';
import { store } from './store.js';

const PDFJS = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js';
const PDFJS_WORKER = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
const JSPDF = 'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js';

const loaded = new Map();
const LOAD_ERROR = 'Couldn’t load the PDF library. Check your connection and try again.';

function loadScript(src, ready) {
  if (!loaded.has(src)) {
    loaded.set(src, new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = src;
      s.onload = () => { if (ready()) resolve(); else { loaded.delete(src); s.remove(); reject(new Error(LOAD_ERROR)); } };
      s.onerror = () => { loaded.delete(src); s.remove(); reject(new Error(LOAD_ERROR)); };
      document.head.append(s);
    }));
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
