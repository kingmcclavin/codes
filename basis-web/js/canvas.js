// The notebook canvas: page layout, zoom and scroll, rendering, and the
// pointer input that drives the tools (pen, highlighter, eraser, shapes,
// lasso, text). Pen and mouse draw; one finger scrolls unless finger drawing
// is on; two fingers pan and pinch-zoom.

import {
  clamp, dist, sub, add, mid, boundsOf, unionRect, expandRect, rectsIntersect, rectContains, rectCenter, css, isLight,
  applyT, concatT, translateT, scaleAboutT, rotateAboutT, angleOf, uuid,
} from './util.js';
import {
  elementBounds, elementBox, hitTest, intersectsPath, enclosedBy, transformElement, buildStrokePath, makeStroke, packPoints,
  shapeKeyPoints, shapeAsStrokes, boxCorners, layoutText, naturalTextWidth, fontString, CARD_PAD, STRIDE,
} from './elements.js';
import { drawBackground, drawElement, drawShape, drawText, fillStrokePath, setImageLoadHandler } from './render.js';
import { recognize } from './recognizer.js';
import { eraseStroke } from './erase.js';
import { isScribble, scribbleErase } from './scribble.js';
import { setElements } from './history.js';
import { fontCss, maxWidth } from './model.js';
import { icon } from './icons.js';
import { renderPDFRegion } from './pdf.js';

const GAP = 28;          // between pages, in page points
const MIN_ZOOM = 0.2, MAX_ZOOM = 8;
const MAX_PAGE_LENGTH = 14400;

export class CanvasView {
  constructor(editor, host) {
    this.editor = editor;
    this.host = host;
    this.dpr = window.devicePixelRatio || 1;
    this.view = { x: 0, y: 0, zoom: 1 };
    this.pointers = new Map();
    this.palms = new Set(); // touch ids rejected as a resting hand
    this.sharp = new Map(); // pageId → sharp render of the visible part of its PDF
    this.interaction = null;   // active tool gesture
    this.gesture = null;       // pan / pinch
    this.selection = null;     // { pageId, ids: Set }
    this.selTransform = null;  // live transform while dragging a selection
    this.hidden = new Set();   // element ids not drawn on the main canvas
    this.textEdit = null;
    this.penSeen = false;
    this.spaceDown = false;
    this.hover = null;

    this.main = document.createElement('canvas');
    this.main.className = 'canvas-main';
    this.overlay = document.createElement('canvas');
    this.overlay.className = 'canvas-overlay';
    this.overlay.setAttribute('aria-label', 'Notebook page. Draw with a pen, mouse, or finger.');
    this.overlay.setAttribute('role', 'img');
    this.overlay.tabIndex = 0;
    host.append(this.main, this.overlay);
    this.ctx = this.main.getContext('2d');
    this.octx = this.overlay.getContext('2d');

    this.layout();
    this.ro = new ResizeObserver(() => this.resize());
    this.ro.observe(host);
    this.buildPullToAdd();
    this.bindInput();
    setImageLoadHandler(() => this.requestRender());
    this.resize();
  }

  destroy() {
    this.destroyed = true;
    clearTimeout(this.sharpTimer);
    this.sharpTask?.cancel();
    this.sharp.clear();
    this.ro.disconnect();
    this.endTextEdit();
    window.removeEventListener('keydown', this.onKeyDown);
    window.removeEventListener('keyup', this.onKeyUp);
    this.main.remove();
    this.overlay.remove();
  }

  get doc() { return this.editor.doc; }
  get settings() { return this.doc.settings; }

  // ---------- Layout & view ----------

  layout() {
    this.tops = [];
    let y = 0;
    this.maxW = 0;
    for (const p of this.doc.pages) {
      this.tops.push(y);
      y += p.h + GAP;
      this.maxW = Math.max(this.maxW, p.w);
    }
    this.totalH = Math.max(0, y - GAP);
  }

  pageOrigin(i) { return { x: -this.doc.pages[i].w / 2, y: this.tops[i] }; }
  pageIndex(id) { return this.doc.pages.findIndex((p) => p.id === id); }

  resize() {
    const r = this.host.getBoundingClientRect();
    this.w = Math.max(1, r.width);
    this.h = Math.max(1, r.height);
    this.dpr = window.devicePixelRatio || 1;
    for (const c of [this.main, this.overlay]) {
      c.width = Math.round(this.w * this.dpr);
      c.height = Math.round(this.h * this.dpr);
      c.style.width = this.w + 'px';
      c.style.height = this.h + 'px';
    }
    if (!this.initialized && this.w > 10) {
      this.initialized = true;
      const v = this.doc.view;
      if (v && v.zoom > 0) {
        this.view = { x: v.scrollX, y: v.scrollY, zoom: v.zoom };
        this.clampView();
      } else {
        this.fitWidth(false);
        if (v?.pageIndex) this.scrollToPage(v.pageIndex, false);
      }
    } else if (this.initialized) {
      this.clampView();
    }
    this.requestRender();
  }

  clampView() {
    const z = this.view.zoom;
    const vw = this.w / z, vh = this.h / z;
    const margin = 80 / z;
    const halfW = this.maxW / 2;
    // Horizontal scrolling only when the page is wider than the screen, and
    // never past its edges; at "fit" or smaller the page stays centered.
    if (this.maxW * z <= this.w + 1) this.view.x = -vw / 2;
    else this.view.x = clamp(this.view.x, -halfW, halfW - vw);
    const minY = -Math.max(margin, 24 / z);
    const maxY = Math.max(minY, this.totalH + Math.max(margin, vh * 0.35) - vh);
    this.view.y = clamp(this.view.y, minY, maxY);
    this.maxY = maxY;
  }

  setZoom(z, anchor = { x: this.w / 2, y: this.h / 2 }) {
    z = clamp(z, MIN_ZOOM, MAX_ZOOM);
    const c = this.screenToContent(anchor);
    this.view.zoom = z;
    this.view.x = c.x - anchor.x / z;
    this.view.y = c.y - anchor.y / z;
    this.clampView();
    this.viewChanged();
  }

  zoomBy(f) { this.setZoom(this.view.zoom * f); }

  /** A quick second finger tap near the first one. Not while a finger is drawing or placing text. */
  isDoubleTap(ptr) {
    if (ptr.type !== 'touch' || this.pointers.size > 0) return false;
    const now = performance.now();
    const isTap = dist(ptr.start, ptr.last) < 10 && now - ptr.t0 < 300 && !this.stoppedMomentum;
    if (!isTap) { this.lastTap = null; return false; }
    const tool = this.settings.tool;
    const fingerInks = this.settings.fingerDrawing && !this.penSeen && ['pen', 'highlighter', 'shapes', 'eraser'].includes(tool);
    if (tool === 'text' || fingerInks) return false;
    const prev = this.lastTap;
    if (prev && now - prev.t < 320 && dist(prev.p, ptr.last) < 40) { this.lastTap = null; return true; }
    this.lastTap = { t: now, p: ptr.last };
    return false;
  }

  /** Zoom so the page's edges touch the screen edges; a second time returns to the previous zoom. */
  toggleFitZoom(anchor) {
    let i = this.pageAtScreen(anchor, GAP);
    if (i < 0) i = this.currentPageIndex;
    const page = this.doc.pages[i];
    const fit = clamp(this.w / page.w, MIN_ZOOM, MAX_ZOOM);
    const c = this.screenToContent(anchor);
    let target;
    if (Math.abs(this.view.zoom - fit) / fit < 0.02) {
      target = this.zoomBeforeFit && Math.abs(this.zoomBeforeFit - fit) / fit >= 0.02 ? this.zoomBeforeFit : clamp((this.w - 32) / this.maxW, MIN_ZOOM, MAX_ZOOM);
      if (Math.abs(target - fit) / fit < 0.02) target = fit * 2;
      this.animateView({ zoom: target, x: c.x - anchor.x / target, y: c.y - anchor.y / target });
    } else {
      this.zoomBeforeFit = this.view.zoom;
      this.animateView({ zoom: fit, x: -page.w / 2, y: c.y - anchor.y / fit });
    }
  }

  fitEdges() {
    const i = this.currentPageIndex, page = this.doc.pages[i];
    const z = clamp(this.w / page.w, MIN_ZOOM, MAX_ZOOM);
    const cy = this.view.y + this.h / 2 / this.view.zoom;
    this.animateView({ zoom: z, x: -page.w / 2, y: cy - this.h / 2 / z });
  }

  /** Smoothly moves to a view (clamped), keeping the screen point under the finger steady. */
  animateView(to) {
    this.stopMomentum();
    const from = { ...this.view };
    const end = { ...this.view, ...to };
    const saved = this.view;
    this.view = end; this.clampView(); const target = { ...this.view }; this.view = saved;
    cancelAnimationFrame(this.animRaf);
    const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    const t0 = performance.now(), dur = reduce ? 0 : 220;
    const step = (now) => {
      const k = dur ? Math.min(1, (now - t0) / dur) : 1;
      const e = 1 - Math.pow(1 - k, 3);
      // Interpolate the scale geometrically so zooming feels even.
      this.view.zoom = from.zoom * Math.pow(target.zoom / from.zoom, e);
      this.view.x = from.x + (target.x - from.x) * e;
      this.view.y = from.y + (target.y - from.y) * e;
      this.viewChanged();
      if (k < 1) this.animRaf = requestAnimationFrame(step);
    };
    this.animRaf = requestAnimationFrame(step);
  }

  fitWidth(notify = true) {
    const z = clamp((this.w - 32) / this.maxW, MIN_ZOOM, MAX_ZOOM);
    const cur = this.currentPageIndex ?? 0;
    this.view.zoom = z;
    this.view.x = -this.w / 2 / z;
    this.view.y = (this.tops[cur] ?? 0) - 16 / z;
    this.clampView();
    if (notify) this.viewChanged();
  }

  fitPage() {
    const i = this.currentPageIndex ?? 0;
    const p = this.doc.pages[i];
    const z = clamp(Math.min((this.w - 32) / p.w, (this.h - 32) / p.h), MIN_ZOOM, MAX_ZOOM);
    this.view.zoom = z;
    this.view.x = -this.w / 2 / z;
    this.view.y = this.tops[i] + p.h / 2 - this.h / 2 / z;
    this.clampView();
    this.viewChanged();
  }

  scrollToPage(i, notify = true) {
    i = clamp(i, 0, this.doc.pages.length - 1);
    this.view.y = this.tops[i] - 16 / this.view.zoom;
    this.clampView();
    if (notify) this.viewChanged();
  }

  screenToContent(p) { return { x: this.view.x + p.x / this.view.zoom, y: this.view.y + p.y / this.view.zoom }; }
  contentToScreen(p) { return { x: (p.x - this.view.x) * this.view.zoom, y: (p.y - this.view.y) * this.view.zoom }; }
  pageToScreen(i, p) { const o = this.pageOrigin(i); return this.contentToScreen({ x: p.x + o.x, y: p.y + o.y }); }
  screenToPage(i, s) { const c = this.screenToContent(s); const o = this.pageOrigin(i); return { x: c.x - o.x, y: c.y - o.y }; }

  /** Page under a screen point (with a little slack around pages). */
  pageAtScreen(s, slack = 0) {
    const c = this.screenToContent(s);
    for (let i = 0; i < this.doc.pages.length; i++) {
      const p = this.doc.pages[i], o = this.pageOrigin(i);
      if (c.x >= o.x - slack && c.x <= o.x + p.w + slack && c.y >= o.y - slack && c.y <= o.y + p.h + slack) return i;
    }
    return -1;
  }

  get currentPageIndex() {
    if (!this.tops) return 0;
    const cy = this.view.y + this.h / 2 / this.view.zoom;
    let best = 0;
    for (let i = 0; i < this.tops.length; i++) if (this.tops[i] <= cy) best = i;
    return best;
  }

  viewChanged() {
    this.requestRender();
    this.positionTextEditor();
    this.editor.viewChanged();
  }

  // ---------- Rendering ----------

  requestRender() {
    this.needFull = true;
    this.scheduleFrame();
  }

  /** A finished stroke only adds ink on top, so paint just it instead of the whole page. */
  requestAppend(pageId, el) {
    (this.appendQueue ||= []).push({ pageId, el });
    this.scheduleFrame();
  }

  scheduleFrame() {
    if (this.raf) return;
    this.raf = requestAnimationFrame(() => {
      this.raf = null;
      if (this.needFull || !this.appendQueue?.length) this.render(); else this.drawAppended();
      this.needFull = false;
      this.appendQueue = [];
      this.renderOverlay();
    });
  }

  drawAppended() {
    const ctx = this.ctx;
    for (const { pageId, el } of this.appendQueue) {
      const i = this.pageIndex(pageId);
      if (i < 0) continue;
      const p = this.doc.pages[i];
      this.pageTransform(ctx, i);
      ctx.save();
      ctx.beginPath(); ctx.rect(0, 0, p.w, p.h); ctx.clip();
      drawElement(ctx, el, p);
      ctx.restore();
    }
  }

  requestOverlay() {
    if (this.oraf || this.raf) return;
    this.oraf = requestAnimationFrame(() => { this.oraf = null; this.renderOverlay(); });
  }

  pageTransform(ctx, i) {
    const o = this.pageOrigin(i), z = this.view.zoom * this.dpr;
    ctx.setTransform(z, 0, 0, z, (o.x - this.view.x) * z, (o.y - this.view.y) * z);
  }

  visiblePageRect(i) {
    const o = this.pageOrigin(i);
    return { x: this.view.x - o.x, y: this.view.y - o.y, w: this.w / this.view.zoom, h: this.h / this.view.zoom };
  }

  render() {
    const ctx = this.ctx;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.main.width, this.main.height);
    const vy0 = this.view.y, vy1 = this.view.y + this.h / this.view.zoom;
    for (let i = 0; i < this.doc.pages.length; i++) {
      const p = this.doc.pages[i];
      const top = this.tops[i];
      if (top > vy1 || top + p.h < vy0) continue;
      this.pageTransform(ctx, i);
      // Paper shadow.
      ctx.save();
      ctx.shadowColor = 'rgba(0,0,0,0.18)';
      ctx.shadowBlur = 14 * this.dpr;
      ctx.shadowOffsetY = 3 * this.dpr;
      ctx.fillStyle = css(p.background.color);
      ctx.fillRect(0, 0, p.w, p.h);
      ctx.restore();
      const vis = this.visiblePageRect(i);
      drawBackground(ctx, p, vis, () => this.drawSharp(ctx, p));
      ctx.save();
      ctx.beginPath(); ctx.rect(0, 0, p.w, p.h); ctx.clip();
      const pad = expandRect(vis, 4);
      for (const e of p.elements) {
        if (this.hidden.has(e.id)) continue;
        if (!rectsIntersect(elementBounds(e), pad)) continue;
        if (e.type === 'text' && this.textEdit?.id === e.id) { drawText(ctx, e, { skipText: true }); continue; }
        drawElement(ctx, e, p);
      }
      ctx.restore();
    }
    this.scheduleSharpen();
  }

  // ---------- Sharp PDF pages ----------
  // Imported PDF pages are stored as an image for quick drawing. Once the view
  // settles, the visible part is re-rendered from the PDF at the current zoom.

  sharpKey(p) { const r = p.background.pdf; return r ? `${r.asset}#${r.page}#${p.w}` : null; }

  drawSharp(ctx, p) {
    const t = this.sharp.get(p.id);
    if (t && t.key === this.sharpKey(p)) ctx.drawImage(t.canvas, t.x, t.y, t.w, t.h);
  }

  scheduleSharpen() {
    clearTimeout(this.sharpTimer);
    if (!this.doc.pages.some((p) => p.background.pdf)) return;
    this.sharpTimer = setTimeout(() => this.sharpen(), 200);
  }

  async sharpen() {
    if (this.destroyed) return;
    // Wait until writing, scrolling and zooming have stopped.
    if (this.interaction || this.gesture || this.momentumRaf || this.pointers.size) { this.scheduleSharpen(); return; }
    const need = Math.min(this.view.zoom * this.dpr, 8);
    const vy0 = this.view.y, vy1 = this.view.y + this.h / this.view.zoom;
    const visible = new Set();
    for (let i = 0; i < this.doc.pages.length; i++) {
      const p = this.doc.pages[i];
      if (this.tops[i] > vy1 || this.tops[i] + p.h < vy0) continue;
      visible.add(p.id);
      const key = this.sharpKey(p);
      if (!key || this.sharpFailed?.has(key)) continue;
      const v = this.visiblePageRect(i);
      const vis = { x: Math.max(0, v.x), y: Math.max(0, v.y), w: Math.min(p.w, v.x + v.w) - Math.max(0, v.x), h: Math.min(p.h, v.y + v.h) - Math.max(0, v.y) };
      if (vis.w <= 0 || vis.h <= 0) continue;
      const t = this.sharp.get(p.id);
      const covers = t && t.x <= vis.x + 0.5 && t.y <= vis.y + 0.5 && t.x + t.w >= vis.x + vis.w - 0.5 && t.y + t.h >= vis.y + vis.h - 0.5;
      if (covers && t.key === key && t.ppt >= need * 0.95) continue;
      // Render a bit beyond the view so small scrolls stay sharp, within a pixel budget.
      const m = { x: vis.w * 0.25, y: vis.h * 0.25 };
      let r = { x: Math.max(0, vis.x - m.x), y: Math.max(0, vis.y - m.y) };
      r.w = Math.min(p.w, vis.x + vis.w + m.x) - r.x;
      r.h = Math.min(p.h, vis.y + vis.h + m.y) - r.y;
      const budget = 8e6;
      if (r.w * r.h * need * need > budget) r = vis;
      const ppt = Math.min(need, Math.sqrt(budget / (r.w * r.h)));
      const task = renderPDFRegion(p.background.pdf, p.w, r, ppt);
      this.sharpTask?.cancel();
      this.sharpTask = task;
      let canvas;
      try { canvas = await task.promise; } catch (e) {
        if (!/cancel/i.test(e?.message || e?.name || '')) (this.sharpFailed ||= new Set()).add(key);
        return;
      }
      if (this.destroyed || this.sharpTask !== task) return;
      this.sharp.set(p.id, { canvas, key, ppt, ...r });
      this.requestRender(); // draws it; the next pass picks up any other visible page
      return;
    }
    // Free renders of pages that scrolled away.
    for (const id of [...this.sharp.keys()]) if (!visible.has(id)) this.sharp.delete(id);
  }

  renderOverlay() {
    const ctx = this.octx;
    const it = this.interaction;
    // While writing, repaint only around the new ink: Safari draws canvases on
    // the CPU, so clearing the whole full-screen layer every frame drops frames.
    if (it && it === this.overlayOwner && it.drawIncremental?.(ctx)) return;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, this.overlay.width, this.overlay.height);
    if (it?.draw) it.draw(ctx);
    this.drawSelection(ctx);
    const cursor = this.hover && this.settings.tool === 'eraser' && !it;
    if (cursor) this.drawEraserCursor(ctx, this.hover);
    // The overlay now holds only this gesture's ink, so later frames can patch it.
    this.overlayOwner = it?.drawIncremental && !this.selection && !cursor ? it : null;
  }

  drawEraserCursor(ctx, s) {
    const r = this.settings.eraser.size / 2;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.beginPath();
    ctx.arc(s.x, s.y, r, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(255,255,255,0.35)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(80,80,90,0.9)';
    ctx.lineWidth = 1;
    ctx.stroke();
  }

  // ---------- Input ----------

  bindInput() {
    const el = this.overlay;
    el.addEventListener('pointerdown', (e) => this.onPointerDown(e));
    el.addEventListener('pointermove', (e) => this.onPointerMove(e));
    el.addEventListener('pointerup', (e) => this.onPointerUp(e));
    el.addEventListener('pointercancel', (e) => this.onPointerUp(e, true));
    el.addEventListener('pointerleave', () => { if (this.hover) { this.hover = null; this.requestOverlay(); } });
    el.addEventListener('wheel', (e) => this.onWheel(e), { passive: false });
    el.addEventListener('dblclick', (e) => this.onDoubleClick(e));
    el.addEventListener('contextmenu', (e) => e.preventDefault());
    // iPadOS starts text selection, the magnifier and callouts from a resting
    // palm or a Pencil press unless the touch is cancelled. Pointer events still
    // arrive; double-taps are then detected in onPointerUp instead of dblclick.
    el.addEventListener('touchstart', (e) => {
      if ([...e.changedTouches].some((t) => t.touchType === 'stylus')) this.stylusTouches = true;
      e.preventDefault();
    }, { passive: false });
    // Safari pinch on trackpads.
    el.addEventListener('gesturestart', (e) => { e.preventDefault(); this.gestureZoom = this.view.zoom; });
    el.addEventListener('gesturechange', (e) => { e.preventDefault(); this.setZoom(this.gestureZoom * e.scale, this.local(e)); });
    this.onKeyDown = (e) => { if (e.code === 'Space' && !isTyping(e)) { this.spaceDown = true; } };
    this.onKeyUp = (e) => { if (e.code === 'Space') this.spaceDown = false; };
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('keyup', this.onKeyUp);
  }

  local(e) {
    const r = this.overlay.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }

  sample(e, pageIdx) {
    const s = this.local(e);
    const p = this.screenToPage(pageIdx, s);
    let force = 0.25;
    // A Pencil often reports no pressure as it lands; -1 means "use the next reading".
    if (e.pointerType === 'pen') force = e.pressure > 0 ? e.pressure * 0.5 : -1;
    let altitude = Math.PI / 2;
    if (e.pointerType === 'pen') {
      if (typeof e.altitudeAngle === 'number') altitude = e.altitudeAngle;
      else if (e.tiltX || e.tiltY) {
        const tx = Math.tan((e.tiltX * Math.PI) / 180), ty = Math.tan((e.tiltY * Math.PI) / 180);
        altitude = Math.atan(1 / Math.max(1e-6, Math.hypot(tx, ty)));
      }
    }
    return { x: p.x, y: p.y, force, altitude, t: e.timeStamp };
  }

  onPointerDown(e) {
    this.stoppedMomentum = this.stopMomentum();
    if (this.textEdit && e.target === this.overlay) { this.endTextEdit(); if (this.settings.tool !== 'text') return; }
    this.overlay.focus({ preventScroll: true });
    if (e.pointerType === 'touch' && this.isPalm(e)) { this.palms.add(e.pointerId); return; }
    if (e.pointerType === 'pen') this.rejectPalms();
    try { this.overlay.setPointerCapture?.(e.pointerId); } catch { /* pointer already gone */ }
    const s = this.local(e);
    this.pointers.set(e.pointerId, { type: e.pointerType, start: s, last: s, t0: performance.now() });
    if (e.pointerType === 'pen') this.penSeen = true;

    const touches = [...this.pointers.values()].filter((p) => p.type === 'touch');
    if (e.pointerType === 'touch' && touches.length >= 2) {
      // Second finger: switch to pan/zoom and drop any finger drawing.
      if (this.interaction?.pointerType === 'touch') this.cancelInteraction();
      this.startGesture();
      return;
    }
    const panButton = e.button === 1 || (e.button === 0 && this.spaceDown);
    const fingerDraws = this.settings.fingerDrawing && !this.penSeen;
    if (panButton || (e.pointerType === 'touch' && !fingerDraws && this.settings.tool !== 'text' && this.settings.tool !== 'lasso')) {
      this.startGesture(e.pointerId);
      return;
    }
    if (e.button !== 0 && e.pointerType === 'mouse') return;
    if (this.interaction) return;
    e.preventDefault();
    this.beginTool(e, s);
  }

  // ---------- Palm rejection ----------
  // Once the Pencil has been used, a touch that lands while it's writing (or
  // a moment after) is a resting hand: ignore it.

  isPalm(e) {
    if (!this.penSeen) return false;
    const penDown = [...this.pointers.values()].some((p) => p.type === 'pen');
    // Contact size isn't used: iPad Safari reports fingertips as large as palms.
    const recentPen = performance.now() - (this.lastPenUp || 0) < 300;
    return penDown || recentPen;
  }

  /** The Pencil came down: touches already on the screen were the palm, so undo what they started. */
  rejectPalms() {
    const touchIds = [...this.pointers.entries()].filter(([, p]) => p.type === 'touch').map(([id]) => id);
    if (!touchIds.length) return;
    const g = this.gesture;
    if (g && g.ids.some((id) => touchIds.includes(id))) {
      this.gesture = null;
      if (this.pull) { this.wheelPull = 0; this.setPull(0); }
      // A palm that landed just before the Pencil may have nudged the page; put it back.
      if (performance.now() - g.t0 < 600) { this.view = { ...g.startView }; this.clampView(); this.viewChanged(); }
    }
    if (this.interaction?.pointerType === 'touch') this.cancelInteraction();
    for (const id of touchIds) { this.pointers.delete(id); this.palms.add(id); }
    this.lastTap = null;
  }

  onPointerMove(e) {
    if (this.palms.has(e.pointerId)) return;
    const ptr = this.pointers.get(e.pointerId);
    const s = this.local(e);
    if (!ptr) {
      if (e.pointerType !== 'touch' && this.settings.tool === 'eraser') { this.hover = s; this.requestOverlay(); }
      return;
    }
    ptr.last = s;
    if (this.gesture) { this.updateGesture(); return; }
    if (this.interaction && this.interaction.pointerId === e.pointerId) {
      const events = e.getCoalescedEvents ? e.getCoalescedEvents() : [e];
      this.interaction.move(events.length ? events : [e], e);
      if (this.settings.tool === 'eraser') this.hover = s;
      this.requestOverlay();
    }
  }

  onPointerUp(e, cancelled = false) {
    if (this.palms.delete(e.pointerId)) return;
    const ptr = this.pointers.get(e.pointerId);
    this.pointers.delete(e.pointerId);
    if (!ptr) return;
    if (ptr.type === 'pen') this.lastPenUp = performance.now();
    if (!cancelled && this.stylusTouches && this.isPenDoubleTap(ptr)) this.penDoubleTap = e;
    if (!cancelled && this.isDoubleTap(ptr)) {
      this.gesture = null;
      if (this.interaction?.pointerId === e.pointerId) { const it = this.interaction; this.interaction = null; it.cancel?.(); }
      // Double-tapping a text box edits it; anywhere else zooms.
      const i = this.pageAtScreen(ptr.last);
      if (i >= 0 && this.topElementAt(i, this.screenToPage(i, ptr.last))?.type === 'text') this.onDoubleClick(e);
      else this.toggleFitZoom(ptr.last);
      return;
    }
    if (this.gesture) {
      if (this.pointers.size === 0) this.endGesture(ptr);
      else this.startGesture();
      return;
    }
    if (this.interaction && this.interaction.pointerId === e.pointerId) {
      const it = this.interaction;
      this.interaction = null;
      if (cancelled) it.cancel?.(); else it.end(e);
      // New ink is painted on its own (requestAppend); anything else repaints the page.
      if (it instanceof InkGesture && this.appendQueue?.length) this.requestOverlay(); else this.requestRender();
    }
    if (this.penDoubleTap === e) { this.penDoubleTap = null; this.onDoubleClick(e); }
  }

  /** Two quick Pencil taps in the same spot (stands in for dblclick when Pencil touches are cancelled). */
  isPenDoubleTap(ptr) {
    if (ptr.type !== 'pen') return false;
    const now = performance.now();
    if (!(dist(ptr.start, ptr.last) < 8 && now - ptr.t0 < 300)) { this.lastPenTap = null; return false; }
    const prev = this.lastPenTap;
    if (prev && now - prev.t < 350 && dist(prev.p, ptr.last) < 20) { this.lastPenTap = null; return true; }
    this.lastPenTap = { t: now, p: ptr.last };
    return false;
  }

  cancelInteraction() {
    if (this.interaction) { this.interaction.cancel?.(); this.interaction = null; this.requestRender(); }
  }

  onWheel(e) {
    e.preventDefault();
    this.stopMomentum();
    const s = this.local(e);
    if (e.ctrlKey || e.metaKey) {
      this.setZoom(this.view.zoom * Math.exp(-e.deltaY * (e.deltaMode === 1 ? 0.05 : 0.0022)), s);
      return;
    }
    const k = e.deltaMode === 1 ? 16 : 1;
    let dx = e.deltaX * k, dy = e.deltaY * k;
    if (e.shiftKey && !dx) { dx = dy; dy = 0; }
    // A new wheel/trackpad sequence may pull to add a page only if it starts at the end.
    const now = performance.now();
    if (now - (this.lastWheelT || 0) > 250) this.wheelPullOK = this.view.y >= (this.maxY ?? Infinity) - 1;
    this.lastWheelT = now;
    this.view.x += dx / this.view.zoom;
    const wantY = this.view.y + dy / this.view.zoom;
    this.view.y = wantY;
    this.clampView();
    if (this.wheelPullOK && (wantY > this.maxY + 0.01 || this.wheelPull > 0)) {
      this.wheelPull = Math.max(0, (this.wheelPull || 0) + dy);
      this.overscroll(this.wheelPull);
      clearTimeout(this.wheelTimer);
      this.wheelTimer = setTimeout(() => this.releasePull(), 200);
    }
    this.viewChanged();
  }

  // Pan & pinch
  startGesture(singleId) {
    const pts = [...this.pointers.entries()].filter(([id, p]) => (singleId != null ? id === singleId : p.type === 'touch' || this.pointers.size === 1));
    const pos = pts.map(([, p]) => p.last);
    const center = pos.length > 1 ? mid(pos[0], pos[1]) : pos[0];
    this.gesture = {
      ids: pts.map(([id]) => id),
      startCenter: center,
      startDist: pos.length > 1 ? Math.max(10, dist(pos[0], pos[1])) : 0,
      startView: { ...this.view },
      anchor: this.screenToContent(center),
      moved: false,
      t0: performance.now(),
      samples: [{ t: performance.now(), p: center }],
      stoppedMomentum: this.stoppedMomentum,
    };
  }

  updateGesture() {
    const g = this.gesture;
    const pos = g.ids.map((id) => this.pointers.get(id)?.last).filter(Boolean);
    if (!pos.length) return;
    const center = pos.length > 1 ? mid(pos[0], pos[1]) : pos[0];
    let zoom = g.startView.zoom;
    if (pos.length > 1 && g.startDist) zoom = clamp(g.startView.zoom * (dist(pos[0], pos[1]) / g.startDist), MIN_ZOOM, MAX_ZOOM);
    this.view.zoom = zoom;
    this.view.x = g.anchor.x - center.x / zoom;
    this.view.y = g.anchor.y - center.y / zoom;
    if (dist(center, g.startCenter) > 4 || pos.length > 1) g.moved = true;
    const now = performance.now();
    g.samples.push({ t: now, p: center });
    while (g.samples.length > 2 && now - g.samples[0].t > 100) g.samples.shift();
    const wantY = this.view.y;
    this.clampView();
    if (pos.length === 1 && wantY > this.maxY + 0.01) this.overscroll((wantY - this.maxY) * zoom);
    else if (this.pull) this.setPull(0);
    this.viewChanged();
  }

  // ---------- Pull to add page ----------
  // Dragging past the end of the last page shows "Pull to Add Page": a ring
  // fills as you pull; once full it reads "Release to Add Page".

  get pullThreshold() { return Math.min(140, this.h * 0.22); }

  /** Applies a rubber-banded overscroll for `raw` screen pixels of drag past the end. */
  overscroll(raw) {
    const d = this.h, shown = (1 - 1 / ((raw * 0.55) / d + 1)) * d;
    this.view.y = this.maxY + shown / this.view.zoom;
    this.setPull(shown);
  }

  buildPullToAdd() {
    const r = 27, c = 2 * Math.PI * r;
    this.pullUI = {
      root: document.createElement('div'),
      ring: null, label: document.createElement('div'), circ: c,
    };
    const root = this.pullUI.root;
    root.className = 'pull-add';
    root.setAttribute('aria-hidden', 'true');
    root.innerHTML = `<div class="pull-ghost"></div><div class="pull-arrow"></div>
      <div class="pull-ring"><svg viewBox="0 0 60 60" width="60" height="60"><circle class="pull-fill" cx="30" cy="30" r="${r + 1.5}"/>
      <circle class="pull-track" cx="30" cy="30" r="${r}"/><circle class="pull-progress" cx="30" cy="30" r="${r}" stroke-dasharray="${c}" stroke-dashoffset="${c}" transform="rotate(-90 30 30)"/></svg>
      <span class="pull-icon"></span></div><div class="pull-label"></div>`;
    root.querySelector('.pull-arrow').append(icon('arrowUp', 20));
    root.querySelector('.pull-icon').append(icon('docPlus', 24));
    this.host.append(root);
    this.pull = 0;
    this.pullArmed = false;
  }

  setPull(p) {
    this.pull = p;
    const ui = this.pullUI, root = ui.root;
    if (p <= 1) { root.classList.remove('show', 'armed'); this.pullArmed = false; return; }
    const armed = p >= this.pullThreshold;
    if (armed && !this.pullArmed) navigator.vibrate?.(10);
    this.pullArmed = armed;
    root.classList.add('show');
    root.classList.toggle('armed', armed);
    root.style.opacity = Math.min(1, p / 40);
    root.querySelector('.pull-progress').setAttribute('stroke-dashoffset', String(ui.circ * (1 - Math.min(1, p / this.pullThreshold))));
    root.querySelector('.pull-label').textContent = armed ? 'Release to Add Page' : 'Pull to Add Page';
    // Lay out inside the strip revealed below the last page.
    const last = this.doc.pages.length - 1, page = this.doc.pages[last];
    const tl = this.pageToScreen(last, { x: 0, y: 0 }), br = this.pageToScreen(last, { x: page.w, y: page.h });
    const left = Math.max(0, tl.x), right = Math.min(this.w, br.x);
    const cx = (left + right) / 2;
    const revealTop = Math.min(br.y, this.h - p);
    const midY = revealTop + (this.h - revealTop) * 0.42;
    const ring = root.querySelector('.pull-ring');
    ring.style.transform = `translate(${cx - 30}px, ${midY - 30}px)`;
    root.querySelector('.pull-arrow').style.transform = `translate(${cx - 10}px, ${midY - 58}px)`;
    const label = root.querySelector('.pull-label');
    label.style.transform = `translate(${cx - 120}px, ${midY + 36}px)`;
    const ghostTop = Math.max(midY + 72, this.h - p * 0.45);
    const ghost = root.querySelector('.pull-ghost');
    Object.assign(ghost.style, { left: tl.x + 'px', width: br.x - tl.x + 'px', top: ghostTop + 'px', height: Math.max(br.y - tl.y, 200) + 'px' });
  }

  /** Finger lifted (or wheel stopped): add a page if armed, otherwise spring back. */
  releasePull() {
    this.wheelPull = 0;
    if (!this.pull) return;
    const armed = this.pull >= this.pullThreshold;
    this.setPull(0);
    if (armed) {
      this.editor.addPage(this.doc.pages.length - 1, { animate: true });
    } else {
      this.animateView({ y: this.maxY });
    }
  }

  endGesture(ptr) {
    const g = this.gesture;
    this.gesture = null;
    if (this.pull) { this.releasePull(); return; }
    if (g?.moved && g.ids.length === 1) { this.fling(g); return; }
    // A finger tap (no movement) acts like a tap of the current tool for lasso/text.
    // A touch that only stopped a fling isn't a tap.
    if (g && !g.moved && !g.stoppedMomentum && g.ids.length === 1 && performance.now() - g.t0 < 350 && ptr?.type === 'touch') {
      this.tap(ptr.last);
    }
  }

  // ---------- Momentum scrolling ----------

  /** Keeps scrolling after a flick, slowing down like iOS (≈0.998 per ms). */
  fling(g) {
    const s = g.samples;
    const now = performance.now();
    const first = s[0], last = s[s.length - 1];
    // A finger that paused before lifting doesn't fling.
    if (s.length < 2 || now - last.t > 60) return;
    const dt = Math.max(last.t - first.t, 8);
    let vx = (last.p.x - first.p.x) / dt, vy = (last.p.y - first.p.y) / dt; // screen px per ms
    const speed = Math.hypot(vx, vy);
    if (speed < 0.15) return;
    const max = 6;
    if (speed > max) { vx *= max / speed; vy *= max / speed; }
    this.stopMomentum();
    let prev = now;
    const step = (t) => {
      const elapsed = Math.min(t - prev, 32);
      prev = t;
      const decay = Math.pow(0.998, elapsed);
      vx *= decay; vy *= decay;
      const ox = this.view.x, oy = this.view.y;
      this.view.x -= (vx * elapsed) / this.view.zoom;
      this.view.y -= (vy * elapsed) / this.view.zoom;
      this.clampView();
      // Stop along an axis that ran into an edge.
      if (Math.abs(this.view.x - (ox - (vx * elapsed) / this.view.zoom)) > 0.01) vx = 0;
      if (Math.abs(this.view.y - (oy - (vy * elapsed) / this.view.zoom)) > 0.01) vy = 0;
      this.viewChanged();
      if (Math.hypot(vx, vy) > 0.02) this.momentumRaf = requestAnimationFrame(step);
      else this.momentumRaf = null;
    };
    this.momentumRaf = requestAnimationFrame(step);
  }

  /** Stops a running fling; returns whether one was running. */
  stopMomentum() {
    if (!this.momentumRaf) return false;
    cancelAnimationFrame(this.momentumRaf);
    this.momentumRaf = null;
    return true;
  }

  tap(s) {
    const tool = this.settings.tool;
    const i = this.pageAtScreen(s);
    if (i < 0) { this.clearSelection(); return; }
    const p = this.screenToPage(i, s);
    if (tool === 'lasso' || this.selection) {
      const hit = this.topElementAt(i, p);
      if (hit) this.setSelection(this.doc.pages[i].id, [hit.id]); else this.clearSelection();
    } else if (tool === 'text') {
      this.textTap(i, p);
    }
  }

  onDoubleClick(e) {
    const s = this.local(e);
    const i = this.pageAtScreen(s);
    if (i < 0) return;
    const p = this.screenToPage(i, s);
    const hit = this.topElementAt(i, p);
    if (hit?.type === 'text') {
      this.clearSelection();
      if (hit.calc) this.editor.editCalculation(this.doc.pages[i].id, hit);
      else this.beginTextEdit(i, hit, false);
    } else if (e.pointerType !== 'pen' && ['lasso', 'eraser'].includes(this.settings.tool) && !hit) {
      this.toggleFitZoom(s);
    }
  }

  topElementAt(i, p) {
    const els = this.doc.pages[i].elements;
    const tol = 6 / this.view.zoom;
    for (let k = els.length - 1; k >= 0; k--) if (hitTest(els[k], p, tol)) return els[k];
    return null;
  }

  // ---------- Tools ----------

  beginTool(e, s) {
    const tool = this.settings.tool;
    if (this.selection && tool === 'lasso') {
      const handled = this.beginSelectionDrag(e, s);
      if (handled) return;
    }
    if (this.selection && tool !== 'lasso') this.clearSelection();
    let i = this.pageAtScreen(s, 0);
    if (i < 0) {
      if (tool === 'lasso') this.clearSelection();
      // Begin a pan when touching the desk around pages with a mouse/pen.
      this.startGesture(e.pointerId);
      return;
    }
    const make = {
      pen: () => new InkGesture(this, e, i, 'pen'),
      highlighter: () => new InkGesture(this, e, i, 'highlighter'),
      shapes: () => new InkGesture(this, e, i, 'shapes'),
      eraser: () => new EraserGesture(this, e, i),
      lasso: () => new LassoGesture(this, e, i),
      text: () => new TapGesture(this, e, i, (pp) => this.textTap(i, pp)),
    }[tool];
    this.interaction = make();
    this.interaction.pointerId = e.pointerId;
    this.interaction.pointerType = e.pointerType;
    this.requestOverlay();
  }

  /** Commits element changes on a page as one undo step. */
  commit(label, pageId, fn) {
    const changed = this.editor.history.perform(label, (pages) => setElements(pages, pageId, fn));
    if (changed) this.afterEdit();
    return changed;
  }

  afterEdit(appended) {
    const grew = this.extendPages();
    this.layout();
    if (appended && !grew) this.requestAppend(appended.pageId, appended.el); else this.requestRender();
    this.editor.documentChanged();
  }

  /** Adds one element on top of a page (new ink): same as commit, but redraws only the new element. */
  commitAppend(label, pageId, el) {
    const changed = this.editor.history.perform(label, (pages) => setElements(pages, pageId, (els) => [...els, el]));
    if (changed) this.afterEdit({ pageId, el });
    return changed;
  }

  /** Endless pages grow down (and right) as content nears the edge. Not an undo step. */
  extendPages() {
    let pages = this.doc.pages, changed = false;
    pages = pages.map((p) => {
      if (!p.background.autoExtends) return p;
      let content = null;
      for (const e of p.elements) content = unionRect(content, elementBounds(e));
      if (!content) return p;
      let w = p.w, h = p.h;
      if (content.y + content.h > h - 300 && h < MAX_PAGE_LENGTH) h = Math.min(MAX_PAGE_LENGTH, Math.max(h + 800, content.y + content.h + 600));
      if (content.x + content.w > w - 200 && w < MAX_PAGE_LENGTH) w = Math.min(MAX_PAGE_LENGTH, Math.max(w + 600, content.x + content.w + 400));
      if (w === p.w && h === p.h) return p;
      changed = true;
      return { ...p, w, h };
    });
    if (changed) {
      // Keep the grown size in history entries so undo doesn't shrink the page under the ink.
      const sizes = new Map(pages.map((p) => [p.id, p]));
      const fix = (arr) => arr.map((p) => { const g = sizes.get(p.id); return g && (g.w !== p.w || g.h !== p.h) ? { ...p, w: g.w, h: g.h } : p; });
      for (const s of this.editor.history.undoStack) { s.before = fix(s.before); s.after = fix(s.after); }
      this.doc.pages = pages;
    }
    return changed;
  }

  snapContext(pageIdx) {
    const page = this.doc.pages[pageIdx];
    const snapPoints = [], lines = [];
    for (const e of page.elements) {
      if (e.type !== 'shape') continue;
      snapPoints.push(...shapeKeyPoints(e));
      if (e.geom.kind === 'line') lines.push({ id: e.id, a: e.geom.a, b: e.geom.b });
    }
    return { snapPoints, lines, snapTolerance: 10 / Math.max(this.view.zoom, 0.25) };
  }

  // ---------- Selection ----------

  setSelection(pageId, ids) {
    this.selection = ids.length ? { pageId, ids: new Set(ids) } : null;
    this.editor.selectionChanged();
    this.requestOverlay();
  }

  clearSelection() {
    if (!this.selection) return;
    this.selection = null;
    this.selTransform = null;
    this.hidden.clear();
    this.editor.selectionChanged();
    this.requestRender();
  }

  selectedElements() {
    if (!this.selection) return [];
    const p = this.doc.pages.find((x) => x.id === this.selection.pageId);
    if (!p) return [];
    return p.elements.filter((e) => this.selection.ids.has(e.id));
  }

  selectionFrame() {
    const els = this.selectedElements();
    if (!els.length) return null;
    const i = this.pageIndex(this.selection.pageId);
    if (els.length === 1) {
      const box = elementBox(els[0]);
      if (box) {
        const pad = els[0].type === 'text' && els[0].calc ? CARD_PAD.x : 0;
        return { i, corners: boxCorners({ ...box, w: box.w + 2 * pad, h: box.h + 2 * pad }), rot: box.rot || 0 };
      }
    }
    let r = null;
    for (const e of els) r = unionRect(r, elementBounds(e));
    r = expandRect(r, 2);
    return { i, corners: [{ x: r.x, y: r.y }, { x: r.x + r.w, y: r.y }, { x: r.x + r.w, y: r.y + r.h }, { x: r.x, y: r.y + r.h }], rot: 0 };
  }

  drawSelection(ctx) {
    const f = this.selectionFrame();
    if (!f) return;
    const t = this.selTransform?.t;
    const corners = f.corners.map((c) => this.pageToScreen(f.i, t ? applyT(t, c) : c));
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    // Live transformed copies.
    if (t) {
      this.pageTransform(ctx, f.i);
      // Clip to the page it would land on (the selection can move to another page).
      const j = this.selTransform.target ?? f.i;
      const page = this.doc.pages[j], oi = this.pageOrigin(f.i), oj = this.pageOrigin(j);
      ctx.save();
      ctx.beginPath(); ctx.rect(oj.x - oi.x, oj.y - oi.y, page.w, page.h); ctx.clip();
      for (const e of this.selectedElements()) drawElement(ctx, transformElement(e, t), page);
      ctx.restore();
      ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    }
    const accent = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#2f6bff';
    ctx.beginPath();
    corners.forEach((c, k) => (k ? ctx.lineTo(c.x, c.y) : ctx.moveTo(c.x, c.y)));
    ctx.closePath();
    ctx.setLineDash([5, 4]);
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1.2;
    ctx.stroke();
    ctx.setLineDash([]);
    if (this.selTransform) return;
    const handles = this.selectionHandles(corners);
    ctx.fillStyle = '#fff';
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1.5;
    for (const hd of handles.scale) { ctx.beginPath(); ctx.arc(hd.x, hd.y, 6, 0, Math.PI * 2); ctx.fill(); ctx.stroke(); }
    ctx.beginPath(); ctx.moveTo(handles.topMid.x, handles.topMid.y); ctx.lineTo(handles.rotate.x, handles.rotate.y); ctx.stroke();
    ctx.beginPath(); ctx.arc(handles.rotate.x, handles.rotate.y, 7, 0, Math.PI * 2); ctx.fillStyle = accent; ctx.fill();
  }

  selectionHandles(corners) {
    const topMid = mid(corners[0], corners[1]);
    const c = mid(corners[0], corners[2]);
    const dir = sub(topMid, c);
    const l = Math.hypot(dir.x, dir.y) || 1;
    return { scale: corners, topMid, rotate: add(topMid, { x: (dir.x / l) * 26, y: (dir.y / l) * 26 }), center: c };
  }

  beginSelectionDrag(e, s) {
    const f = this.selectionFrame();
    if (!f) return false;
    const corners = f.corners.map((c) => this.pageToScreen(f.i, c));
    const hd = this.selectionHandles(corners);
    const centerPage = mid(f.corners[0], f.corners[2]);
    let mode = null, ref = null;
    if (dist(s, hd.rotate) < 16) mode = 'rotate';
    else {
      const k = hd.scale.findIndex((c) => dist(s, c) < 14);
      if (k >= 0) { mode = 'scale'; ref = f.corners[(k + 2) % 4]; }
    }
    if (!mode) {
      const poly = corners;
      const inside = pointInQuad(s, poly);
      if (!inside) return false;
      mode = 'move';
    }
    const start = this.screenToPage(f.i, s);
    const ids = this.selection.ids;
    let last = s, edgeRaf = null;
    const update = () => {
      const p = this.screenToPage(f.i, last);
      let t;
      if (mode === 'move') t = translateT(p.x - start.x, p.y - start.y);
      else if (mode === 'scale') {
        const d0 = dist(start, ref), d1 = dist(p, ref);
        t = scaleAboutT(clamp(d1 / Math.max(d0, 1e-3), 0.05, 50), ref);
      } else {
        let a = angleOf(sub(p, centerPage)) - angleOf(sub(start, centerPage));
        const snap = Math.round(a / (Math.PI / 12)) * (Math.PI / 12);
        if (Math.abs(a - snap) < 0.04) a = snap;
        t = rotateAboutT(a, centerPage);
      }
      // Moving can carry the selection onto another page.
      this.selTransform = { t, target: mode === 'move' ? this.dropPage(f, t) : f.i };
      for (const id of ids) this.hidden.add(id);
      this.requestRender();
    };
    // Holding a dragged selection near the top or bottom edge scrolls, to reach other pages.
    const edgeScroll = () => {
      edgeRaf = null;
      if (this.interaction !== it) return;
      const m = 56;
      const dy = last.y < m ? last.y - m : last.y > this.h - m ? last.y - (this.h - m) : 0;
      if (!dy) return;
      const y0 = this.view.y;
      this.view.y += (clamp(dy, -m, m) * 0.4) / this.view.zoom;
      this.clampView();
      if (this.view.y === y0) return;
      this.viewChanged();
      update();
      edgeRaf = requestAnimationFrame(edgeScroll);
    };
    const it = {
      pointerId: e.pointerId,
      pointerType: e.pointerType,
      move: (events) => {
        last = this.local(events[events.length - 1]);
        update();
        if (mode === 'move' && !edgeRaf) edgeRaf = requestAnimationFrame(edgeScroll);
      },
      end: () => {
        cancelAnimationFrame(edgeRaf);
        const t = this.selTransform?.t, target = this.selTransform?.target ?? f.i;
        this.selTransform = null;
        this.hidden.clear();
        if (t && target !== f.i) this.moveSelectionToPage(f.i, target, ids, t);
        else if (t && (Math.abs(t[4]) > 0.01 || Math.abs(t[5]) > 0.01 || Math.abs(t[0] - 1) > 1e-4 || Math.abs(t[1]) > 1e-4)) {
          const label = mode === 'move' ? 'Move' : mode === 'scale' ? 'Resize' : 'Rotate';
          this.commit(label, this.selection.pageId, (els) => els.map((x) => (ids.has(x.id) ? transformElement(x, t) : x)));
          this.editor.selectionChanged();
        }
        this.requestRender();
      },
      cancel: () => { cancelAnimationFrame(edgeRaf); this.selTransform = null; this.hidden.clear(); this.requestRender(); },
    };
    this.interaction = it;
    return true;
  }

  /** The page a selection moved by `t` (in page f.i coordinates) is dropped on: the one under its center, else the nearest. */
  dropPage(f, t) {
    const c = applyT(t, mid(f.corners[0], f.corners[2]));
    const o = this.pageOrigin(f.i);
    const x = c.x + o.x, y = c.y + o.y; // content coordinates
    let best = f.i, bestD = Infinity;
    for (let j = 0; j < this.doc.pages.length; j++) {
      const p = this.doc.pages[j], oj = this.pageOrigin(j);
      const dx = x < oj.x ? oj.x - x : x > oj.x + p.w ? x - oj.x - p.w : 0;
      const dy = y < oj.y ? oj.y - y : y > oj.y + p.h ? y - oj.y - p.h : 0;
      const d = Math.hypot(dx, dy);
      if (d < bestD) { bestD = d; best = j; }
    }
    return best;
  }

  /** Moves selected elements from page i to page j (one undo step), keeping where they were dropped. */
  moveSelectionToPage(i, j, ids, t) {
    const from = this.doc.pages[i], to = this.doc.pages[j];
    const oi = this.pageOrigin(i), oj = this.pageOrigin(j);
    const tt = concatT(t, translateT(oi.x - oj.x, oi.y - oj.y)); // page i → page j coordinates
    const moved = from.elements.filter((x) => ids.has(x.id)).map((x) => transformElement(x, tt));
    const changed = this.editor.history.perform('Move to Page', (pages) =>
      setElements(setElements(pages, from.id, (els) => els.filter((x) => !ids.has(x.id))), to.id, (els) => [...els, ...moved]));
    if (!changed) return;
    this.afterEdit();
    this.setSelection(to.id, moved.map((x) => x.id));
  }

  // ---------- Text ----------

  textTap(i, p) {
    const hit = this.topElementAt(i, p);
    if (hit?.type === 'text') {
      if (hit.calc) this.editor.editCalculation(this.doc.pages[i].id, hit);
      else this.beginTextEdit(i, hit, false);
      return;
    }
    const page = this.doc.pages[i];
    const st = this.settings.text;
    const w = Math.max(80, Math.min(320, page.w - p.x - 16));
    const lh = st.fontSize * 1.3;
    const el = { type: 'text', id: uuid(), text: '', style: structuredClone(st), box: { cx: p.x + w / 2, cy: p.y, w, h: lh, rot: 0 } };
    this.beginTextEdit(i, el, true);
  }

  beginTextEdit(i, el, isNew) {
    this.endTextEdit();
    const page = this.doc.pages[i];
    const ta = document.createElement('textarea');
    ta.className = 'text-editor';
    ta.value = el.text;
    ta.setAttribute('aria-label', 'Text');
    ta.spellcheck = true;
    this.host.append(ta);
    this.textEdit = { id: el.id, pageId: page.id, el, isNew, ta };
    this.editor.textEditingChanged(true);
    const autosize = () => {
      const st = this.textEdit.el.style;
      const lay = layoutText(ta.value || ' ', st, this.textEdit.el.box.w);
      this.textEdit.height = lay.height;
      this.positionTextEditor();
    };
    ta.addEventListener('input', autosize);
    ta.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') { e.preventDefault(); this.endTextEdit(); }
      e.stopPropagation();
    });
    ta.addEventListener('blur', () => setTimeout(() => { if (this.textEdit?.ta === ta && document.activeElement !== ta) this.endTextEdit(); }, 120));
    autosize();
    this.requestRender();
    const focus = () => { ta.focus({ preventScroll: true }); ta.setSelectionRange(ta.value.length, ta.value.length); };
    focus();
    setTimeout(() => { if (this.textEdit?.ta === ta && document.activeElement !== ta) focus(); }, 0);
  }

  /** Applies style changes from the options bar while editing. */
  restyleEditingText(style) {
    if (!this.textEdit) return;
    this.textEdit.el = { ...this.textEdit.el, style: structuredClone(style) };
    const lay = layoutText(this.textEdit.ta.value || ' ', style, this.textEdit.el.box.w);
    this.textEdit.height = lay.height;
    this.positionTextEditor();
  }

  positionTextEditor() {
    const te = this.textEdit;
    if (!te) return;
    const i = this.pageIndex(te.pageId);
    if (i < 0) return;
    const { el, ta } = te;
    const b = el.box, z = this.view.zoom, st = el.style;
    const c = this.pageToScreen(i, { x: b.cx, y: b.cy });
    const w = b.w * z, h0 = b.h * z;
    const h = Math.max(te.height ?? b.h, st.fontSize * 1.3) * z + 4;
    Object.assign(ta.style, {
      left: c.x - w / 2 + 'px', top: c.y - h0 / 2 + 'px', width: w + 'px', height: h + 'px',
      transform: `rotate(${b.rot || 0}rad)`, transformOrigin: `${w / 2}px ${h0 / 2}px`,
      font: `${st.italic ? 'italic ' : ''}${st.bold ? '700 ' : '400 '}${st.fontSize * z}px ${fontCss(st.fontFamily)}`,
      lineHeight: st.fontSize * 1.3 * z + 'px', color: css(st.color), textAlign: st.align === 'justified' ? 'justify' : st.align,
    });
    ta.style.caretColor = isLight(this.doc.pages[i].background.color) ? '#1f4fd8' : '#8fb2ff';
  }

  endTextEdit() {
    const te = this.textEdit;
    if (!te) return;
    this.textEdit = null;
    te.ta.remove();
    this.editor.textEditingChanged(false);
    const text = te.ta.value.replace(/\s+$/, '');
    const st = te.el.style;
    let el = { ...te.el, text };
    if (text) {
      let w = el.box.w;
      if (te.isNew) w = Math.min(w, Math.ceil(naturalTextWidth(text, st)) + 2);
      const lay = layoutText(text, st, w);
      // Keep the top-left corner fixed while the size changes.
      const rot = el.box.rot || 0, c = Math.cos(rot), s = Math.sin(rot);
      const dx = (w - el.box.w) / 2, dy = (lay.height - el.box.h) / 2;
      el.box = { ...el.box, w, h: lay.height, cx: el.box.cx + dx * c - dy * s, cy: el.box.cy + dx * s + dy * c };
    }
    if (te.isNew) {
      if (text) this.commit('Add Text', te.pageId, (els) => [...els, el]);
    } else if (!text) {
      this.commit('Delete Text', te.pageId, (els) => els.filter((x) => x.id !== te.id));
    } else if (text !== te.el.text || JSON.stringify(st) !== JSON.stringify(this.doc.pages.find((p) => p.id === te.pageId)?.elements.find((x) => x.id === te.id)?.style)) {
      this.commit('Edit Text', te.pageId, (els) => els.map((x) => (x.id === te.id ? el : x)));
    }
    this.requestRender();
  }

  // ---------- Inserting ----------

  /** Center of the visible part of the current page, in page coordinates. */
  visibleCenter() {
    const i = this.currentPageIndex;
    const page = this.doc.pages[i];
    const vis = this.visiblePageRect(i);
    const r = { x: Math.max(0, vis.x), y: Math.max(0, vis.y), w: 0, h: 0 };
    r.w = Math.min(page.w, vis.x + vis.w) - r.x;
    r.h = Math.min(page.h, vis.y + vis.h) - r.y;
    return { i, page, p: r.w > 0 && r.h > 0 ? rectCenter(r) : { x: page.w / 2, y: page.h / 2 } };
  }

  insertElement(el, label) {
    const { page } = this.visibleCenter();
    this.commit(label, page.id, (els) => [...els, el]);
    if (this.settings.tool !== 'lasso') this.editor.selectTool('lasso');
    this.setSelection(page.id, [el.id]);
  }
}

function pointInQuad(p, q) {
  let inside = false;
  for (let i = 0, j = q.length - 1; i < q.length; j = i++) {
    if ((q[i].y > p.y) !== (q[j].y > p.y) && p.x < ((q[j].x - q[i].x) * (p.y - q[i].y)) / (q[j].y - q[i].y) + q[i].x) inside = !inside;
  }
  return inside;
}

function isTyping(e) {
  const t = e.target;
  return t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable);
}

// ---------- Gestures ----------

/** Pen, highlighter and shapes: collects samples; hold still to snap to a shape. */
class InkGesture {
  constructor(view, e, i, mode) {
    this.view = view;
    this.i = i;
    this.page = view.doc.pages[i];
    this.mode = mode;
    const st = view.settings;
    this.style = mode === 'highlighter' ? st.highlighter : st.pen;
    this.samples = [view.sample(e, i)];
    this.snapped = null;
    this.lastMoveScreen = view.local(e);
    this.armHold();
  }

  armHold() {
    clearTimeout(this.holdTimer);
    const st = this.view.settings;
    if (this.mode === 'shapes' || !st.holdToSnap || this.snapped) return;
    this.holdTimer = setTimeout(() => this.trySnap(), st.holdDuration * 1000);
  }

  trySnap() {
    if (this.samples.length < 3) return;
    const pts = this.samples.map((s) => ({ x: s.x, y: s.y }));
    if (this.mode === 'highlighter') {
      // Highlighters straighten into a line.
      this.snapped = { kind: 'line', geom: { kind: 'line', a: pts[0], b: pts[pts.length - 1] } };
    } else {
      const r = recognize(pts, this.view.snapContext(this.i));
      if (!r || r.kind !== 'shape') return;
      this.snapped = { kind: 'shape', geom: r.geom, arrows: r.arrows };
    }
    this.view.requestOverlay();
  }

  move(events) {
    for (const ev of events) {
      const s = this.view.sample(ev, this.i);
      const last = this.samples[this.samples.length - 1];
      if (s.force < 0) s.force = last.force;
      else if (last.force < 0) for (const q of this.samples) if (q.force < 0) q.force = s.force;
      if (Math.abs(s.x - last.x) < 0.05 && Math.abs(s.y - last.y) < 0.05) continue;
      this.samples.push(s);
    }
    const scr = this.view.local(events[events.length - 1]);
    if (dist(scr, this.lastMoveScreen) > 3) {
      this.lastMoveScreen = scr;
      if (this.snapped) {
        // After snapping, dragging stretches a line's free end.
        if (this.snapped.geom.kind === 'line') {
          const s = this.samples[this.samples.length - 1];
          this.snapped.geom = { ...this.snapped.geom, b: { x: s.x, y: s.y } };
        }
      } else this.armHold();
    }
  }

  shapeStyle() {
    const st = this.view.settings;
    if (this.mode === 'shapes') return structuredClone(st.shape);
    return { strokeColor: { ...this.style.color }, lineWidth: Math.max(0.5, this.style.width), opacity: this.style.opacity, fill: null, lineStyle: this.style.lineStyle };
  }

  end() {
    clearTimeout(this.holdTimer);
    const v = this.view, pageId = this.page.id;
    if (this.snapped) {
      if (this.snapped.kind === 'line' && this.mode === 'highlighter') {
        const g = this.snapped.geom;
        const stroke = makeStroke([{ ...g.a, force: 0.25 }, { ...g.b, force: 0.25 }], this.style);
        v.commit('Highlight', pageId, (els) => [...els, stroke]);
      } else {
        const shape = { type: 'shape', id: uuid(), geom: this.snapped.geom, style: this.shapeStyle(), arrows: this.snapped.arrows || { start: false, end: false } };
        v.commit('Shape', pageId, (els) => [...els, shape]);
      }
      return;
    }
    if (this.mode === 'shapes') {
      const pts = this.samples.map((s) => ({ x: s.x, y: s.y }));
      if (pts.length < 2) return;
      const r = recognize(pts, v.snapContext(this.i), { allowCurve: true });
      if (r?.kind === 'arrowhead') {
        v.commit('Arrow', pageId, (els) => els.map((x) => (x.id === r.lineId ? { ...x, arrows: { ...x.arrows, [r.atEnd ? 'end' : 'start']: true } } : x)));
      } else if (r?.kind === 'shape') {
        const shape = { type: 'shape', id: uuid(), geom: r.geom, style: this.shapeStyle(), arrows: r.arrows };
        v.commit('Shape', pageId, (els) => [...els, shape]);
      }
      return;
    }
    const st = v.settings;
    if (this.mode === 'pen' && st.scribbleToErase !== false && this.samples.length >= 12) {
      const pts = this.samples.map((s) => ({ x: s.x, y: s.y }));
      if (isScribble(pts, this.samples.map((s) => s.t / 1000), v.view.zoom)) {
        const tolerance = Math.max(this.style.width / 2, 1.5) + 2 / Math.max(v.view.zoom, 0.01);
        const page = v.doc.pages.find((p) => p.id === pageId);
        const result = scribbleErase(pts, page.elements, st.scribbleMode || 'strokes', tolerance);
        if (result) { v.commit('Scribble Erase', pageId, () => result); return; }
      }
    }
    for (const q of this.samples) if (q.force < 0) q.force = 0.25;
    const stroke = makeStroke(this.samples, this.style);
    v.commitAppend(this.mode === 'highlighter' ? 'Highlight' : 'Ink', pageId, stroke);
  }

  cancel() { clearTimeout(this.holdTimer); }

  draw(ctx) {
    const v = this.view;
    v.pageTransform(ctx, this.i);
    ctx.save();
    ctx.beginPath(); ctx.rect(0, 0, this.page.w, this.page.h); ctx.clip();
    if (this.snapped) {
      if (this.snapped.kind === 'line' && this.mode === 'highlighter') {
        const g = this.snapped.geom;
        fillStrokePath(ctx, buildStrokePath(packPoints([{ ...g.a }, { ...g.b }]), this.style), this.style, !isLight(this.page.background.color));
      } else {
        drawShape(ctx, { type: 'shape', geom: this.snapped.geom, style: this.shapeStyle(), arrows: this.snapped.arrows || {} });
      }
    } else if (this.mode === 'shapes') {
      const st = v.settings.shape;
      ctx.beginPath();
      this.samples.forEach((s, k) => (k ? ctx.lineTo(s.x, s.y) : ctx.moveTo(s.x, s.y)));
      ctx.strokeStyle = css(st.strokeColor, 0.55);
      ctx.lineWidth = st.lineWidth;
      ctx.lineCap = ctx.lineJoin = 'round';
      ctx.stroke();
    } else {
      const path = buildStrokePath(packPoints(this.samples), this.style);
      fillStrokePath(ctx, path, this.style, !isLight(this.page.background.color));
      this.pathKind = !!path.__stroked;
      this.drawnTo = this.samples.length;
    }
    ctx.restore();
  }

  /**
   * Repaints just the end of the stroke: the samples added since the last
   * frame plus the few before them that smoothing moves. Returns false when a
   * full redraw is needed instead.
   */
  drawIncremental(ctx) {
    if (this.snapped || this.mode === 'shapes' || this.drawnTo == null) return false;
    const n = this.samples.length;
    if (n === this.drawnTo) return true;
    const path = buildStrokePath(packPoints(this.samples), this.style);
    if (!!path.__stroked !== this.pathKind) return false; // the whole stroke changed look
    const v = this.view, o = v.pageOrigin(this.i), z = v.view.zoom, d = v.dpr;
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    // Width smoothing reaches back along the stroke, so repaint the last ~15 pt too.
    let from = Math.max(0, this.drawnTo - 1), back = 0;
    while (from > 0 && (back < 15 || this.drawnTo - from < 8)) {
      back += Math.hypot(this.samples[from].x - this.samples[from - 1].x, this.samples[from].y - this.samples[from - 1].y);
      from--;
    }
    for (let k = from; k < n; k++) {
      const q = this.samples[k];
      if (q.x < x0) x0 = q.x; if (q.x > x1) x1 = q.x;
      if (q.y < y0) y0 = q.y; if (q.y > y1) y1 = q.y;
    }
    const pad = maxWidth(this.style) / 2 + 2;
    const rx = Math.floor(((o.x + x0 - pad - v.view.x) * z) * d) - 2;
    const ry = Math.floor(((o.y + y0 - pad - v.view.y) * z) * d) - 2;
    const rw = Math.ceil((x1 - x0 + pad * 2) * z * d) + 4;
    const rh = Math.ceil((y1 - y0 + pad * 2) * z * d) + 4;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.save();
    ctx.beginPath(); ctx.rect(rx, ry, rw, rh); ctx.clip();
    ctx.clearRect(rx, ry, rw, rh);
    v.pageTransform(ctx, this.i);
    ctx.beginPath(); ctx.rect(0, 0, this.page.w, this.page.h); ctx.clip();
    fillStrokePath(ctx, path, this.style, !isLight(this.page.background.color));
    ctx.restore();
    this.drawnTo = n;
    return true;
  }
}

/** Stroke eraser and vector "pixel" eraser. One undo step per gesture. */
class EraserGesture {
  constructor(view, e, i) {
    this.view = view;
    this.i = i;
    this.pageId = view.doc.pages[i].id;
    this.before = view.doc.pages;
    this.last = view.sample(e, i);
    this.erase([this.last]);
  }

  move(events) {
    const pts = events.map((ev) => this.view.sample(ev, this.i));
    this.erase([this.last, ...pts]);
    this.last = pts[pts.length - 1];
  }

  erase(path) {
    const v = this.view;
    const st = v.settings.eraser;
    const r = st.size / 2 / v.view.zoom;
    const page = v.doc.pages.find((p) => p.id === this.pageId);
    const region = expandRect(boundsOf(path), r + 2);
    let changed = false;
    const out = [];
    for (const e of page.elements) {
      if (!rectsIntersect(expandRect(elementBounds(e), e.type === 'stroke' ? maxWidth(e.style) : 0), region)
        || (st.highlighterOnly && !(e.type === 'stroke' && e.style.kind === 'highlighter'))) { out.push(e); continue; }
      if (st.mode === 'object') {
        if (intersectsPath(e, path, r)) { changed = true; continue; }
        out.push(e);
      } else if (e.type === 'stroke') {
        const res = eraseStroke(e, path, r);
        if (res) { changed = true; out.push(...res); } else out.push(e);
      } else if (e.type === 'shape') {
        if (!intersectsPath(e, path, r)) { out.push(e); continue; }
        changed = true;
        for (const s of shapeAsStrokes(e)) out.push(...(eraseStroke(s, path, r) ?? [s]));
      } else out.push(e);
    }
    if (changed) {
      v.doc.pages = setElements(v.doc.pages, this.pageId, () => out);
      v.requestRender();
    }
  }

  end() {
    const v = this.view;
    if (v.doc.pages !== this.before) {
      v.editor.history.record('Erase', this.before);
      v.afterEdit();
    }
  }

  cancel() { this.end(); }
  draw(ctx) { if (this.view.hover) this.view.drawEraserCursor(ctx, this.view.hover); }
}

/** Freehand lasso: encloses elements to select them; a tap selects one. */
class LassoGesture {
  constructor(view, e, i) {
    this.view = view;
    this.i = i;
    this.pts = [view.screenToPage(i, view.local(e))];
    this.startScreen = view.local(e);
    this.maxDist = 0;
    view.clearSelection();
  }

  move(events) {
    for (const ev of events) {
      const s = this.view.local(ev);
      this.maxDist = Math.max(this.maxDist, dist(s, this.startScreen));
      this.pts.push(this.view.screenToPage(this.i, s));
    }
  }

  end() {
    const v = this.view, page = v.doc.pages[this.i];
    if (this.maxDist < 6 || this.pts.length < 3) {
      const hit = v.topElementAt(this.i, this.pts[0]);
      if (hit) v.setSelection(page.id, [hit.id]);
      return;
    }
    const ids = page.elements.filter((e) => enclosedBy(e, this.pts)).map((e) => e.id);
    v.setSelection(page.id, ids);
  }

  draw(ctx) {
    const v = this.view;
    v.pageTransform(ctx, this.i);
    ctx.beginPath();
    this.pts.forEach((p, k) => (k ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
    ctx.setLineDash([6 / v.view.zoom, 5 / v.view.zoom]);
    ctx.strokeStyle = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#2f6bff';
    ctx.lineWidth = 1.5 / v.view.zoom;
    ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = 'rgba(47,107,255,0.06)';
    ctx.fill();
  }
}

class TapGesture {
  constructor(view, e, i, onTap) {
    this.view = view; this.i = i; this.onTap = onTap;
    this.start = view.local(e);
    this.moved = false;
  }
  move(events) { if (dist(this.view.local(events[events.length - 1]), this.start) > 6) this.moved = true; }
  end() { if (!this.moved) this.onTap(this.view.screenToPage(this.i, this.start)); }
}

export { STRIDE, fontString, concatT };
