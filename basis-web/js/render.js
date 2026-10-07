// Draws page backgrounds and elements into any 2D context in page
// coordinates. Used by the live canvas, thumbnails and export.

import { css, isLight } from './util.js';
import { lineColor, marginColor, dashPattern } from './model.js';
import { strokePath, traceShape, arrowHeads, isClosedShape, layoutText, fontString, CARD_PAD } from './elements.js';
import { store } from './store.js';

// ---------- Image assets ----------

const images = new Map(); // asset id -> HTMLImageElement | 'loading' | 'error'
let onImageLoad = () => {};
export function setImageLoadHandler(fn) { onImageLoad = fn; }

export function assetImage(id) {
  const v = images.get(id);
  if (v instanceof HTMLImageElement) return v;
  if (!v) {
    images.set(id, 'loading');
    const load = (url, fallback) => {
      if (!url) { images.set(id, 'error'); return; }
      const img = new Image();
      img.onload = () => { images.set(id, img); onImageLoad(id); };
      img.onerror = () => (fallback ? fallback() : images.set(id, 'error'));
      img.src = url;
    };
    // Object URL first; if the browser won't load it, retry as a data URL.
    store.assetURL(id).then((url) => load(url, () => store.assetDataURL(id).then((d) => load(d, null))))
      .catch(() => images.set(id, 'error'));
  }
  return null;
}

/** Resolves when every asset referenced by `pages` has loaded (export). */
export async function preloadAssets(pages) {
  const ids = new Set();
  for (const p of pages) {
    if (p.background.image) ids.add(p.background.image);
    for (const e of p.elements) if (e.type === 'image') ids.add(e.asset);
  }
  await Promise.all([...ids].map((id) => new Promise((resolve) => {
    if (assetImage(id)) return resolve();
    const t0 = Date.now();
    const tick = () => (assetImage(id) || images.get(id) === 'error' || Date.now() - t0 > 8000 ? resolve() : setTimeout(tick, 40));
    tick();
  })));
}

// ---------- Background ----------

export function drawBackground(ctx, page, clip) {
  const bg = page.background;
  const W = page.w, H = page.h;
  const r = intersect(clip || { x: 0, y: 0, w: W, h: H }, { x: 0, y: 0, w: W, h: H });
  if (!r) return;
  const minX = r.x, minY = r.y, maxX = r.x + r.w, maxY = r.y + r.h;
  ctx.save();
  ctx.fillStyle = css(bg.color);
  ctx.fillRect(minX, minY, r.w, r.h);

  if (bg.image) {
    const img = assetImage(bg.image);
    if (img) {
      const s = Math.min(W / img.naturalWidth, H / img.naturalHeight);
      const w = img.naturalWidth * s, h = img.naturalHeight * s;
      ctx.drawImage(img, (W - w) / 2, (H - h) / 2, w, h);
    }
  }

  const spacing = Math.max(bg.spacing, 4);
  ctx.strokeStyle = css(lineColor(bg));
  ctx.lineWidth = 0.5;

  const hLines = (step, top = 0) => {
    if (step <= 0) return;
    for (let y = top + Math.max(0, Math.ceil((minY - top) / step)) * step; y <= maxY; y += step) { ctx.moveTo(minX, y); ctx.lineTo(maxX, y); }
  };
  const vLines = (step) => { for (let x = Math.ceil(minX / step) * step; x <= maxX; x += step) { ctx.moveTo(x, minY); ctx.lineTo(x, maxY); } };
  const line = (x1, y1, x2, y2) => { ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); };

  ctx.beginPath();
  switch (bg.template) {
    case 'ruled': {
      hLines(spacing, spacing * 3);
      ctx.stroke();
      const mx = Math.min(72, W * 0.12);
      if (minX <= mx && maxX >= mx) {
        ctx.beginPath(); ctx.strokeStyle = css(marginColor(bg)); ctx.lineWidth = 0.75; line(mx, minY, mx, maxY); ctx.stroke();
      }
      break;
    }
    case 'grid': hLines(spacing); vLines(spacing); ctx.stroke(); break;
    case 'dotted': {
      const lc = lineColor(bg);
      ctx.fillStyle = css({ ...lc, a: Math.min(1, lc.a * 1.8) });
      const rad = 0.9;
      for (let y = Math.ceil(minY / spacing) * spacing; y <= maxY + rad; y += spacing) {
        for (let x = Math.ceil(minX / spacing) * spacing; x <= maxX + rad; x += spacing) { ctx.moveTo(x + rad, y); ctx.arc(x, y, rad, 0, Math.PI * 2); }
      }
      ctx.fill();
      break;
    }
    case 'isometric': {
      vLines(spacing * Math.sqrt(3) / 2);
      const slope = Math.tan(Math.PI / 6), span = r.w * slope;
      for (const sign of [1, -1]) {
        const cs = [minY - sign * slope * minX, minY - sign * slope * maxX, maxY - sign * slope * minX, maxY - sign * slope * maxX];
        for (let c = Math.floor((Math.min(...cs) - span) / spacing) * spacing; c <= Math.max(...cs) + span; c += spacing) {
          line(minX, sign * slope * minX + c, maxX, sign * slope * maxX + c);
        }
      }
      ctx.stroke();
      break;
    }
    case 'cornell': {
      const top = Math.min(110, H * 0.12), summary = Math.min(170, H * 0.2), cue = W * 0.3, noteBottom = H - summary;
      ctx.save();
      ctx.beginPath(); ctx.rect(cue, top, W - cue, noteBottom - top); ctx.clip();
      ctx.beginPath(); hLines(spacing, top + spacing); ctx.stroke();
      ctx.restore();
      ctx.beginPath(); ctx.strokeStyle = css(marginColor(bg)); ctx.lineWidth = 1;
      line(0, top, W, top); line(cue, top, cue, noteBottom); line(0, noteBottom, W, noteBottom);
      ctx.stroke();
      break;
    }
    case 'lab': {
      const header = Math.min(96, H * 0.1);
      ctx.strokeStyle = css(marginColor(bg)); ctx.lineWidth = 1;
      line(0, header, W, header);
      for (const f of [0.34, 0.67]) line(W * f, header * 0.25, W * f, header);
      ctx.stroke();
      ctx.save();
      ctx.beginPath(); ctx.rect(0, header, W, H - header); ctx.clip();
      ctx.strokeStyle = css(lineColor(bg));
      ctx.beginPath(); ctx.lineWidth = 0.35; hLines(spacing, header); vLines(spacing); ctx.stroke();
      ctx.beginPath(); ctx.lineWidth = 0.8; hLines(spacing * 5, header); vLines(spacing * 5); ctx.stroke();
      ctx.restore();
      break;
    }
    case 'engineering': {
      ctx.lineWidth = 0.35; hLines(spacing / 5); vLines(spacing / 5); ctx.stroke();
      ctx.beginPath(); ctx.lineWidth = 0.9; hLines(spacing); vLines(spacing); ctx.stroke();
      break;
    }
  }
  ctx.restore();
}

function intersect(a, b) {
  const x = Math.max(a.x, b.x), y = Math.max(a.y, b.y);
  const x2 = Math.min(a.x + a.w, b.x + b.w), y2 = Math.min(a.y + a.h, b.y + b.h);
  return x2 > x && y2 > y ? { x, y, w: x2 - x, h: y2 - y } : null;
}

// ---------- Elements ----------

export function drawElement(ctx, e, page) {
  switch (e.type) {
    case 'stroke': return drawStroke(ctx, e, page);
    case 'shape': return drawShape(ctx, e);
    case 'image': return drawImage(ctx, e);
    case 'text': return drawText(ctx, e);
  }
}

export function fillStrokePath(ctx, path, style, darkPaper) {
  ctx.save();
  if (style.kind === 'highlighter' && !darkPaper) ctx.globalCompositeOperation = 'multiply';
  const color = css(style.color, style.opacity);
  if (path.__stroked) {
    ctx.strokeStyle = color;
    ctx.lineWidth = Math.max(path.__stroked.width, 0.1);
    ctx.lineCap = path.__stroked.dash && style.lineStyle === 'dotted' ? 'round' : path.__stroked.cap;
    ctx.lineJoin = 'round';
    if (path.__stroked.dash) ctx.setLineDash(path.__stroked.dash);
    ctx.stroke(path);
  } else {
    ctx.fillStyle = color;
    ctx.fill(path, 'nonzero');
  }
  ctx.restore();
}

function drawStroke(ctx, e, page) {
  fillStrokePath(ctx, strokePath(e), e.style, page && !isLight(page.background.color));
}

export function drawShape(ctx, s) {
  ctx.save();
  ctx.globalAlpha *= s.style.opacity ?? 1;
  if (s.style.fill && isClosedShape(s)) {
    ctx.beginPath(); traceShape(ctx, s, false);
    ctx.fillStyle = css(s.style.fill); ctx.fill();
  }
  ctx.beginPath(); traceShape(ctx, s, true);
  ctx.strokeStyle = css(s.style.strokeColor);
  ctx.lineWidth = s.style.lineWidth;
  ctx.lineJoin = 'round'; ctx.lineCap = 'round';
  const dash = dashPattern(s.style.lineStyle, s.style.lineWidth);
  if (dash) ctx.setLineDash(dash);
  ctx.stroke();
  ctx.setLineDash([]);
  const heads = arrowHeads(s);
  if (heads.length) {
    ctx.beginPath();
    for (const t of heads) { ctx.moveTo(t[0].x, t[0].y); ctx.lineTo(t[1].x, t[1].y); ctx.lineTo(t[2].x, t[2].y); ctx.closePath(); }
    ctx.fillStyle = css(s.style.strokeColor);
    ctx.fill(); ctx.stroke();
  }
  ctx.restore();
}

function drawImage(ctx, e) {
  const b = e.box;
  ctx.save();
  ctx.translate(b.cx, b.cy); ctx.rotate(b.rot || 0);
  ctx.globalAlpha *= e.opacity ?? 1;
  const img = assetImage(e.asset);
  if (img) ctx.drawImage(img, -b.w / 2, -b.h / 2, b.w, b.h);
  else { ctx.fillStyle = 'rgba(128,128,128,0.25)'; ctx.fillRect(-b.w / 2, -b.h / 2, b.w, b.h); }
  ctx.restore();
}

export function drawText(ctx, e, { skipText = false } = {}) {
  const b = e.box, st = e.style;
  ctx.save();
  ctx.translate(b.cx, b.cy); ctx.rotate(b.rot || 0);
  if (e.calc) {
    const w = b.w + CARD_PAD.x * 2, h = b.h + CARD_PAD.y * 2;
    ctx.beginPath();
    roundRect(ctx, -w / 2, -h / 2, w, h, 8);
    ctx.fillStyle = css({ ...st.color, a: 0.06 });
    ctx.fill();
    ctx.strokeStyle = css({ ...st.color, a: 0.28 });
    ctx.lineWidth = 0.75;
    ctx.stroke();
  }
  if (!skipText) {
    const lay = layoutText(e.text, st, b.w);
    ctx.font = fontString(st);
    ctx.fillStyle = css(st.color);
    ctx.textBaseline = 'alphabetic';
    const ascent = st.fontSize * 0.95;
    lay.lines.forEach((line, i) => {
      const y = -b.h / 2 + i * lay.lineHeight + ascent + (lay.lineHeight - st.fontSize * 1.2) / 2;
      let x = -b.w / 2;
      const lw = ctx.measureText(line).width;
      if (st.align === 'center') x = -lw / 2;
      else if (st.align === 'right') x = b.w / 2 - lw;
      if (st.align === 'justified' && i < lay.lines.length - 1 && line.includes(' ')) {
        const words = line.split(' '), total = words.reduce((s, w) => s + ctx.measureText(w).width, 0);
        const gap = (b.w - total) / (words.length - 1);
        let cx = -b.w / 2;
        for (const w of words) { ctx.fillText(w, cx, y); cx += ctx.measureText(w).width + gap; }
      } else {
        ctx.fillText(line, x, y);
      }
    });
  }
  ctx.restore();
}

export function roundRect(ctx, x, y, w, h, r) {
  r = Math.min(r, w / 2, h / 2);
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

/** Renders a whole page at `scale` into a new canvas (thumbnails, export). */
export function renderPageCanvas(page, scale, maxPixels = 16e6) {
  let s = scale;
  if (page.w * page.h * s * s > maxPixels) s = Math.sqrt(maxPixels / (page.w * page.h));
  const c = document.createElement('canvas');
  c.width = Math.max(1, Math.round(page.w * s));
  c.height = Math.max(1, Math.round(page.h * s));
  const ctx = c.getContext('2d');
  ctx.scale(s, s);
  drawBackground(ctx, page, null);
  ctx.save();
  ctx.beginPath(); ctx.rect(0, 0, page.w, page.h); ctx.clip();
  for (const e of page.elements) drawElement(ctx, e, page);
  ctx.restore();
  return c;
}
