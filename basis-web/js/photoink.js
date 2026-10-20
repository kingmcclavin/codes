// Handwriting from Photo: pick a photo of paper notes, crop it, and the
// writing comes in as ink strokes (see inkscan.js). Runs on the device.

import { h, clamp, css, debounce, storage } from './util.js';
import { sheet, segmented, slider, toggle, toast, pickFile, cropStage } from './ui.js';
import { preparePhoto, traceInk } from './inkscan.js';
import { makeStroke } from './elements.js';

const KEY = 'basis.photoInk';
const defaults = () => ({ sensitivity: 0.5, removeLines: true, colors: 'pen', thickness: 'photo', place: 'new' });

export async function handwritingFromPhoto(editor, file) {
  if (!file) [file] = await pickFile('image/*');
  if (!file) return;
  const url = URL.createObjectURL(file);
  const img = new Image();
  try {
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = url; });
  } catch { URL.revokeObjectURL(url); toast('That photo couldn’t be read.'); return; }

  const opts = { ...defaults(), ...storage.get(KEY, {}) };
  const save = () => storage.set(KEY, opts);
  const cur = editor.doc.pages[editor.canvas.currentPageIndex];
  if (!cur.elements.length && !cur.background.image && !cur.background.pdf) opts.place = 'here';
  const pen = editor.settings.pen;
  const paperColor = cur.background.color || { r: 1, g: 1, b: 1, a: 1 };

  let prep = null, strokes = [];
  const status = h('span', { class: 'muted small photoink-status' }, 'Finding writing…');
  const preview = h('canvas', { class: 'photoink-preview' });
  const crop = cropStage(url, { x: 0, y: 0, w: 1, h: 1 }, { onChange: () => { prep = null; }, onCommit: () => { prep = null; run(); } });
  crop.box.append(preview);

  const colorOf = (s) => (opts.colors === 'photo' && s.color ? { ...s.color, a: 1 } : { ...pen.color, a: 1 });
  const draw = () => {
    const d = window.devicePixelRatio || 1, bw = crop.box.clientWidth, bh = crop.box.clientHeight;
    if (!prep || !bw) return;
    preview.width = Math.round(bw * d); preview.height = Math.round(bh * d);
    const ctx = preview.getContext('2d'), k = preview.width / prep.W;
    ctx.fillStyle = css(paperColor, 0.92);
    ctx.fillRect(0, 0, preview.width, preview.height);
    ctx.lineCap = ctx.lineJoin = 'round';
    for (const s of strokes) {
      ctx.strokeStyle = ctx.fillStyle = css(colorOf(s));
      ctx.lineWidth = Math.max(1, (opts.thickness === 'pen' ? pen.width / scaleFor(prep).k : s.width) * k);
      if (s.pts.length === 1) { ctx.beginPath(); ctx.arc(s.pts[0].x * k, s.pts[0].y * k, ctx.lineWidth / 2, 0, Math.PI * 2); ctx.fill(); continue; }
      ctx.beginPath();
      s.pts.forEach((p, i) => (i ? ctx.lineTo(p.x * k, p.y * k) : ctx.moveTo(p.x * k, p.y * k)));
      ctx.stroke();
    }
  };
  const run = debounce(() => {
    status.textContent = 'Finding writing…';
    // Let the status paint before the work.
    requestAnimationFrame(() => setTimeout(() => {
      try {
        if (!prep) prep = preparePhoto(img, crop.rect);
        strokes = traceInk(prep, opts);
        status.textContent = strokes.length ? `${strokes.length} stroke${strokes.length === 1 ? '' : 's'} found.` : 'No writing found. Try a higher sensitivity.';
      } catch (e) {
        console.warn(e); strokes = []; status.textContent = 'This photo couldn’t be read.';
      }
      draw();
    }, 0));
  }, 150);

  // Page size the ink will land on, and the photo-pixel → page scale.
  const target = () => (opts.place === 'new' ? editor.blankPageLike(editor.canvas.currentPageIndex) : cur);
  function scaleFor(p) {
    const page = target(), m = page.w * 0.06;
    const k = Math.min((page.w - 2 * m) / p.W, (page.h - 2 * m) / p.H);
    return { page, m, k };
  }

  const insert = () => {
    if (!strokes.length) { toast('No writing found in this photo.'); return false; }
    const { page, m, k } = scaleFor(prep);
    let ox, oy;
    if (opts.place === 'new') { ox = (page.w - prep.W * k) / 2; oy = m; } else {
      const c = editor.canvas.visibleCenter().p;
      ox = clamp(c.x - (prep.W * k) / 2, 0, Math.max(0, page.w - prep.W * k));
      oy = clamp(c.y - (prep.H * k) / 2, 0, Math.max(0, page.h - prep.H * k));
    }
    const els = strokes.map((s) => makeStroke(
      s.pts.map((q) => ({ x: ox + q.x * k, y: oy + q.y * k, force: 0.25, altitude: Math.PI / 2 })),
      { ...pen, kind: 'ballpoint', color: colorOf(s), width: opts.thickness === 'pen' ? pen.width : clamp(s.width * k, 0.4, 8), opacity: 1, pressure: 0, tilt: 0, lineStyle: 'solid' },
    ));
    if (opts.place === 'new') {
      const at = editor.canvas.currentPageIndex + 1;
      page.elements = els;
      editor.history.perform('Handwriting from Photo', (pages) => [...pages.slice(0, at), page, ...pages.slice(at)]);
      editor.afterHistory();
      editor.canvas.scrollToPage(at);
    } else {
      editor.canvas.commit('Handwriting from Photo', page.id, (list) => [...list, ...els]);
    }
    editor.selectTool('lasso');
    editor.canvas.setSelection(page.id, els.map((e) => e.id));
    toast(`Added ${els.length} stroke${els.length === 1 ? '' : 's'}. Drag to move them, or lasso part of it.`);
    return true;
  };

  const sens = slider('photoink-sens', { min: 0, max: 1, step: 0.05, value: opts.sensitivity, format: (v) => (v < 0.3 ? 'Bold only' : v > 0.7 ? 'Faint too' : 'Normal'), onInput: (v) => { opts.sensitivity = v; save(); run(); } });
  await sheet({
    title: 'Handwriting from Photo',
    wide: true,
    className: 'photoink',
    actions: { confirm: 'Add Ink', onConfirm: () => insert() },
    onClose: () => URL.revokeObjectURL(url),
    build: (body) => {
      body.append(
        h('div', { class: 'crop-wrap' }, crop.stage),
        h('div', { class: 'crop-foot' },
          h('span', { class: 'muted small' }, 'Crop to the writing. Flat, even light works best.'), status),
        h('div', { class: 'photoink-opts' },
          h('label', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Sensitivity'), sens.el),
          h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Ink color'),
            segmented([{ value: 'pen', label: 'My pen color' }, { value: 'photo', label: 'Colors from photo' }], opts.colors, (v) => { opts.colors = v; save(); draw(); }, { label: 'Ink color' })),
          h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Thickness'),
            segmented([{ value: 'photo', label: 'As written' }, { value: 'pen', label: 'My pen' }], opts.thickness, (v) => { opts.thickness = v; save(); draw(); }, { label: 'Thickness' })),
          h('div', { class: 'form-row' }, h('span', { class: 'form-label' }, 'Add to'),
            segmented([{ value: 'new', label: 'New page' }, { value: 'here', label: 'This page' }], opts.place, (v) => { opts.place = v; save(); }, { label: 'Add to' })),
          toggle('photoink-lines', 'Ignore notebook lines', opts.removeLines, (v) => { opts.removeLines = v; save(); run(); })),
      );
      if (img.complete) run(); else crop.img.addEventListener('load', run, { once: true });
      crop.img.addEventListener('load', draw);
    },
  });
}
