// Page elements: strokes, shapes, images and text. Elements are treated as
// immutable values; edits replace them, which keeps undo cheap and lets
// caches key on object identity.

import {
  add, sub, mul, dist, norm, perp, angleOf, mid, lerp, unit, cross, clamp,
  boundsOf, expandRect, rectsIntersect, rectContains, rectDiagonal,
  distToSegment, distToPolyline, segSegDistance, polygonContains,
  applyT, scaleFactorT, rotationT, uuid,
} from './util.js';
import { widthAt, maxWidth, dashPattern, fontCss } from './model.js';

export const STRIDE = 4; // x, y, force, altitude

export function strokePoints(e) {
  const out = [];
  for (let i = 0; i < e.pts.length; i += STRIDE) out.push({ x: e.pts[i], y: e.pts[i + 1] });
  return out;
}

export function packPoints(samples) {
  const a = new Float32Array(samples.length * STRIDE);
  samples.forEach((s, i) => {
    a[i * 4] = s.x; a[i * 4 + 1] = s.y; a[i * 4 + 2] = s.force ?? 0.25; a[i * 4 + 3] = s.altitude ?? Math.PI / 2;
  });
  return a;
}

export function makeStroke(samples, style) {
  return { type: 'stroke', id: uuid(), style: structuredClone(style), pts: packPoints(samples) };
}

// ---------- Box geometry (oriented rectangles) ----------

export const boxCorners = (b) => {
  const c = Math.cos(b.rot || 0), s = Math.sin(b.rot || 0), hw = b.w / 2, hh = b.h / 2;
  return [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]].map(([x, y]) => ({ x: b.cx + x * c - y * s, y: b.cy + x * s + y * c }));
};

export function boxContains(b, p, tol = 0) {
  const c = Math.cos(-(b.rot || 0)), s = Math.sin(-(b.rot || 0));
  const dx = p.x - b.cx, dy = p.y - b.cy;
  const lx = dx * c - dy * s, ly = dx * s + dy * c;
  return Math.abs(lx) <= b.w / 2 + tol && Math.abs(ly) <= b.h / 2 + tol;
}

function boxApply(b, t) {
  const c = applyT(t, { x: b.cx, y: b.cy });
  const k = scaleFactorT(t);
  return { cx: c.x, cy: c.y, w: b.w * k, h: b.h * k, rot: (b.rot || 0) + rotationT(t) };
}

// ---------- Text layout ----------

let measureCtx = null;
function mctx() {
  if (!measureCtx) measureCtx = document.createElement('canvas').getContext('2d');
  return measureCtx;
}

export const fontString = (st) => `${st.italic ? 'italic ' : ''}${st.bold ? '700 ' : '400 '}${st.fontSize}px ${fontCss(st.fontFamily)}`;

/** Word-wraps text into lines that fit `width`. */
export function layoutText(text, style, width) {
  const ctx = mctx();
  ctx.font = fontString(style);
  const lineHeight = style.fontSize * 1.3;
  const lines = [];
  for (const para of String(text).split('\n')) {
    const words = para.split(/(\s+)/);
    let line = '';
    for (const w of words) {
      const test = line + w;
      if (line && ctx.measureText(test).width > width && w.trim()) {
        lines.push(line.trimEnd());
        line = w.trimStart();
        // Break single words that are longer than the line.
        while (ctx.measureText(line).width > width && line.length > 1) {
          let n = line.length;
          while (n > 1 && ctx.measureText(line.slice(0, n)).width > width) n--;
          lines.push(line.slice(0, n));
          line = line.slice(n);
        }
      } else {
        line = test;
      }
    }
    lines.push(line);
  }
  return { lines, lineHeight, height: Math.max(lineHeight, lines.length * lineHeight) };
}

export function naturalTextWidth(text, style) {
  const ctx = mctx();
  ctx.font = fontString(style);
  return Math.max(...String(text).split('\n').map((l) => ctx.measureText(l).width), style.fontSize);
}

export const CARD_PAD = { x: 10, y: 8 };

// ---------- Bounds ----------

const boundsCache = new WeakMap();

export function elementBounds(e) {
  let b = boundsCache.get(e);
  if (b) return b;
  switch (e.type) {
    case 'stroke': {
      const pts = strokePoints(e);
      let mw = 0;
      for (let i = 0; i < e.pts.length; i += STRIDE) mw = Math.max(mw, widthAt(e.style, e.pts[i + 2], e.pts[i + 3]));
      b = boundsOf(pts, mw / 2 + 1);
      break;
    }
    case 'shape': {
      const pts = shapeOutline(e, 4).flat();
      for (const tri of arrowHeads(e)) pts.push(...tri);
      b = boundsOf(pts, e.style.lineWidth / 2 + 1);
      break;
    }
    case 'image':
      b = boundsOf(boxCorners(e.box), 0);
      break;
    case 'text': {
      const pad = e.calc ? CARD_PAD : { x: 0, y: 0 };
      b = boundsOf(boxCorners({ ...e.box, w: e.box.w + 2 * pad.x + 4, h: e.box.h + 2 * pad.y + 4 }), 2);
      break;
    }
  }
  b = b || { x: 0, y: 0, w: 0, h: 0 };
  boundsCache.set(e, b);
  return b;
}

/** Oriented box for elements that have one (single-selection handles). */
export function elementBox(e) {
  if (e.type === 'image' || e.type === 'text') return e.box;
  if (e.type === 'shape' && (e.geom.kind === 'rect' || e.geom.kind === 'ellipse')) return e.geom.box;
  return null;
}

// ---------- Shapes ----------

export const arrowHeadLength = (s) => Math.max(10, s.style.lineWidth * 4.5);

export function shapeDisplayName(s) {
  const g = s.geom;
  switch (g.kind) {
    case 'line': return s.arrows?.start || s.arrows?.end ? 'Arrow' : 'Line';
    case 'ellipse': return Math.abs(g.box.w - g.box.h) < 0.5 ? 'Circle' : 'Ellipse';
    case 'rect': return Math.abs(g.box.w - g.box.h) < 0.5 ? 'Square' : 'Rectangle';
    case 'polygon':
      if (!g.closed) return 'Polyline';
      return ({ 3: 'Triangle', 4: 'Quadrilateral', 5: 'Pentagon', 6: 'Hexagon' })[g.pts.length] || 'Polygon';
    default: return 'Curve';
  }
}

export const isClosedShape = (s) => s.geom.kind === 'ellipse' || s.geom.kind === 'rect' || (s.geom.kind === 'polygon' && s.geom.closed);

/** Builds the shape's centerline into a Path2D (or a 2D context path). */
export function traceShape(target, s, trimForArrows = true) {
  const g = s.geom;
  switch (g.kind) {
    case 'line': {
      let a = g.a, b = g.b;
      if (trimForArrows) {
        const dir = norm(sub(b, a)), l = dist(a, b);
        const trim = Math.min(arrowHeadLength(s) * 0.6, l * 0.4);
        if (s.arrows?.end) b = sub(b, mul(dir, trim));
        if (s.arrows?.start) a = add(a, mul(dir, trim));
      }
      target.moveTo(a.x, a.y);
      target.lineTo(b.x, b.y);
      break;
    }
    case 'ellipse':
      target.moveTo(g.box.cx + (g.box.w / 2) * Math.cos(g.box.rot), g.box.cy + (g.box.w / 2) * Math.sin(g.box.rot));
      target.ellipse(g.box.cx, g.box.cy, Math.max(0.01, g.box.w / 2), Math.max(0.01, g.box.h / 2), g.box.rot, 0, Math.PI * 2);
      target.closePath();
      break;
    case 'rect': {
      const c = boxCorners(g.box);
      target.moveTo(c[0].x, c[0].y);
      for (let i = 1; i < 4; i++) target.lineTo(c[i].x, c[i].y);
      target.closePath();
      break;
    }
    case 'polygon':
      if (!g.pts.length) break;
      target.moveTo(g.pts[0].x, g.pts[0].y);
      for (const p of g.pts.slice(1)) target.lineTo(p.x, p.y);
      if (g.closed) target.closePath();
      break;
    case 'curve': {
      const p = g.pts;
      if (!p.length) break;
      target.moveTo(p[0].x, p[0].y);
      let i = 1;
      for (; i + 2 < p.length; i += 3) target.bezierCurveTo(p[i].x, p[i].y, p[i + 1].x, p[i + 1].y, p[i + 2].x, p[i + 2].y);
      for (; i < p.length; i++) target.lineTo(p[i].x, p[i].y);
      break;
    }
  }
}

/** Flattened outline polylines (page coordinates). */
export function shapeOutline(s, spacing = 2) {
  const g = s.geom;
  switch (g.kind) {
    case 'line': return [[g.a, g.b]];
    case 'rect': { const c = boxCorners(g.box); return [[...c, c[0]]]; }
    case 'ellipse': {
      const n = Math.max(24, Math.ceil((Math.PI * (g.box.w + g.box.h) / 2) / spacing));
      const co = Math.cos(g.box.rot), si = Math.sin(g.box.rot);
      const out = [];
      for (let i = 0; i <= n; i++) {
        const t = (i / n) * Math.PI * 2, x = (g.box.w / 2) * Math.cos(t), y = (g.box.h / 2) * Math.sin(t);
        out.push({ x: g.box.cx + x * co - y * si, y: g.box.cy + x * si + y * co });
      }
      return [out];
    }
    case 'polygon': return [g.closed ? [...g.pts, g.pts[0]] : g.pts];
    case 'curve': {
      const p = g.pts, out = [p[0]];
      let i = 1;
      for (; i + 2 < p.length; i += 3) {
        const p0 = p[i - 1], c1 = p[i], c2 = p[i + 1], p1 = p[i + 2];
        const n = Math.max(4, Math.ceil((dist(p0, c1) + dist(c1, c2) + dist(c2, p1)) / spacing));
        for (let k = 1; k <= n; k++) {
          const t = k / n, mt = 1 - t;
          out.push({
            x: mt * mt * mt * p0.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * p1.x,
            y: mt * mt * mt * p0.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * p1.y,
          });
        }
      }
      for (; i < p.length; i++) out.push(p[i]);
      return [out];
    }
  }
  return [];
}

export function arrowHeads(s) {
  const g = s.geom;
  if (g.kind !== 'line' || dist(g.a, g.b) < 0.5) return [];
  const head = (tip, from) => {
    const dir = norm(sub(tip, from));
    const l = Math.min(arrowHeadLength(s), dist(tip, from) * 0.6);
    const base = sub(tip, mul(dir, l)), half = l * 0.5;
    return [tip, add(base, mul(perp(dir), half)), sub(base, mul(perp(dir), half))];
  };
  const out = [];
  if (s.arrows?.end) out.push(head(g.b, g.a));
  if (s.arrows?.start) out.push(head(g.a, g.b));
  return out;
}

export function shapeKeyPoints(s) {
  const g = s.geom;
  switch (g.kind) {
    case 'line': return [g.a, g.b];
    case 'rect': return [...boxCorners(g.box), { x: g.box.cx, y: g.box.cy }];
    case 'ellipse': {
      const u = unit(g.box.rot), v = perp(u), c = { x: g.box.cx, y: g.box.cy };
      return [c, add(c, mul(u, g.box.w / 2)), sub(c, mul(u, g.box.w / 2)), add(c, mul(v, g.box.h / 2)), sub(c, mul(v, g.box.h / 2))];
    }
    case 'polygon': return g.pts;
    default: return [g.pts[0], g.pts[g.pts.length - 1]];
  }
}

/** Converts a shape's outline into plain ink strokes (for the pixel eraser). */
export function shapeAsStrokes(s) {
  const style = { kind: 'fineliner', color: s.style.strokeColor, width: s.style.lineWidth, opacity: s.style.opacity, pressure: 0, tilt: 0, lineStyle: s.style.lineStyle };
  const lines = shapeOutline(s, 1.5).map((l) => densifyPolyline(l, 1.5));
  for (const tri of arrowHeads(s)) lines.push([...tri, tri[0]]);
  return lines.filter((l) => l.length > 1).map((l) => makeStroke(l, style));
}

function densifyPolyline(pts, spacing) {
  const out = [pts[0]];
  for (let i = 1; i < pts.length; i++) {
    const n = Math.max(1, Math.ceil(dist(pts[i - 1], pts[i]) / spacing));
    for (let k = 1; k <= n; k++) out.push(lerp(pts[i - 1], pts[i], k / n));
  }
  return out;
}

// ---------- Hit testing ----------

export function hitTest(e, p, tol) {
  if (!rectContains(expandRect(elementBounds(e), tol), p)) return false;
  switch (e.type) {
    case 'stroke': {
      const n = e.pts.length / STRIDE;
      const P = (i) => ({ x: e.pts[i * 4], y: e.pts[i * 4 + 1] });
      if (n === 1) return dist(P(0), p) <= e.style.width / 2 + tol;
      for (let i = 1; i < n; i++) {
        const w = Math.max(widthAt(e.style, e.pts[(i - 1) * 4 + 2], e.pts[(i - 1) * 4 + 3]), widthAt(e.style, e.pts[i * 4 + 2], e.pts[i * 4 + 3]));
        if (distToSegment(p, P(i - 1), P(i)) <= w / 2 + tol) return true;
      }
      return false;
    }
    case 'shape': {
      if (e.style.fill && isClosedShape(e) && polygonContains(shapeOutline(e, 4)[0], p)) return true;
      const t = e.style.lineWidth / 2 + tol;
      if (shapeOutline(e, 3).some((l) => distToPolyline(p, l) <= t)) return true;
      return arrowHeads(e).some((tri) => polygonContains(tri, p));
    }
    case 'image': return boxContains(e.box, p, tol);
    case 'text': return boxContains(e.box, p, tol + (e.calc ? CARD_PAD.x : 0));
  }
  return false;
}

/** Whether a circle of `radius` swept along `path` touches the element. */
export function intersectsPath(e, path, radius) {
  if (!path.length) return false;
  const pb = expandRect(boundsOf(path), radius);
  if (!rectsIntersect(elementBounds(e), pb)) return false;
  switch (e.type) {
    case 'stroke': {
      const pts = strokePoints(e);
      const tol = radius + e.style.width / 2;
      if (path.length === 1) return hitTest(e, path[0], radius);
      if (pts.length === 1) return distToPolyline(pts[0], path) <= tol;
      for (let i = 1; i < path.length; i++) {
        const a = path[i - 1], b = path[i];
        for (let k = 1; k < pts.length; k++) if (segSegDistance(a, b, pts[k - 1], pts[k]) <= tol) return true;
      }
      return false;
    }
    case 'shape': {
      const tol = radius + e.style.lineWidth / 2;
      for (const line of shapeOutline(e, Math.max(1, radius))) for (const q of line) if (distToPolyline(q, path) <= tol) return true;
      if (e.style.fill && isClosedShape(e)) { const o = shapeOutline(e, 4)[0]; return path.some((q) => polygonContains(o, q)); }
      return false;
    }
    default: return path.some((q) => boxContains(e.box, q, radius));
  }
}

function samplePoints(e) {
  switch (e.type) {
    case 'stroke': {
      const pts = strokePoints(e);
      if (pts.length <= 64) return pts;
      const step = pts.length / 64;
      return Array.from({ length: 64 }, (_, i) => pts[Math.floor(i * step)]);
    }
    case 'shape': return shapeOutline(e, Math.max(4, rectDiagonal(elementBounds(e)) / 48)).flat();
    default: return [...boxCorners(e.box), { x: e.box.cx, y: e.box.cy }];
  }
}

/** Lasso containment: most of the element must be inside the polygon. */
export function enclosedBy(e, poly) {
  const s = samplePoints(e);
  if (!s.length) return false;
  const inside = s.reduce((n, p) => n + (polygonContains(poly, p) ? 1 : 0), 0);
  if (e.type === 'stroke') return inside / s.length >= 0.6;
  if (e.type === 'shape') return inside / s.length >= 0.75;
  return polygonContains(poly, { x: e.box.cx, y: e.box.cy }) && inside >= 3;
}

// ---------- Transforms & restyling ----------

export function transformElement(e, t) {
  const k = scaleFactorT(t);
  switch (e.type) {
    case 'stroke': {
      const pts = new Float32Array(e.pts);
      for (let i = 0; i < pts.length; i += STRIDE) {
        const q = applyT(t, { x: pts[i], y: pts[i + 1] });
        pts[i] = q.x; pts[i + 1] = q.y;
      }
      return { ...e, pts, style: { ...e.style, width: e.style.width * k } };
    }
    case 'shape': {
      const g = e.geom, T = (p) => applyT(t, p);
      let geom;
      if (g.kind === 'line') geom = { kind: 'line', a: T(g.a), b: T(g.b) };
      else if (g.kind === 'rect' || g.kind === 'ellipse') geom = { kind: g.kind, box: boxApply(g.box, t) };
      else geom = { ...g, pts: g.pts.map(T) };
      return { ...e, geom, style: { ...e.style, lineWidth: e.style.lineWidth * k } };
    }
    case 'image': return { ...e, box: boxApply(e.box, t) };
    case 'text': return { ...e, box: boxApply(e.box, t), style: { ...e.style, fontSize: Math.max(4, e.style.fontSize * k) } };
  }
  return e;
}

export function primaryColor(e) {
  if (e.type === 'stroke') return e.style.color;
  if (e.type === 'shape') return e.style.strokeColor;
  if (e.type === 'text') return e.style.color;
  return null;
}

export function recolor(e, color) {
  if (e.type === 'stroke') return { ...e, style: { ...e.style, color: { ...color, a: e.style.color.a } } };
  if (e.type === 'shape') {
    const fill = e.style.fill ? { ...color, a: e.style.fill.a } : null;
    return { ...e, style: { ...e.style, strokeColor: color, fill } };
  }
  if (e.type === 'text') return { ...e, style: { ...e.style, color } };
  return e;
}

export const withNewId = (e) => ({ ...e, id: uuid() });

export function kindName(e) {
  if (e.type === 'stroke') return e.style.kind === 'highlighter' ? 'Highlight' : 'Ink';
  if (e.type === 'shape') return shapeDisplayName(e);
  if (e.type === 'image') return 'Image';
  return e.calc ? 'Calculation' : 'Text';
}

// ---------- Stroke outline (resolution independent) ----------

const pathCache = new WeakMap();

export function strokePath(e) {
  let p = pathCache.get(e);
  if (!p) { p = buildStrokePath(e.pts, e.style); pathCache.set(e, p); }
  return p;
}

/** Converts samples into a fillable outline: variable width as an offset
 *  outline with round caps; constant, dashed and highlighter strokes as a
 *  stroked smooth centerline. */
export function buildStrokePath(pts, style, path = new Path2D()) {
  let s = [];
  for (let i = 0; i < pts.length; i += STRIDE) {
    const q = { p: { x: pts[i], y: pts[i + 1] }, w: widthAt(style, pts[i + 2] < 0 ? 0.25 : pts[i + 2], pts[i + 3]) };
    const last = s[s.length - 1];
    if (last && (last.p.x - q.p.x) ** 2 + (last.p.y - q.p.y) ** 2 < 0.0025) { last.w = Math.max(last.w, q.w); continue; }
    s.push(q);
  }
  const isHL = style.kind === 'highlighter';
  if (!s.length) return path;
  if (s.length === 1) {
    const r = Math.max(s[0].w / 2, 0.2);
    if (isHL) path.rect(s[0].p.x - r * 0.35, s[0].p.y - r, r * 0.7, 2 * r);
    else { path.moveTo(s[0].p.x + r, s[0].p.y); path.arc(s[0].p.x, s[0].p.y, r, 0, Math.PI * 2); }
    return path;
  }
  s = smoothSamples(s);
  const ws = s.map((q) => q.w);
  const minW = Math.min(...ws), maxW = Math.max(...ws);
  const constant = maxW - minW < Math.max(0.04, maxW * 0.04);
  if (style.lineStyle !== 'solid' || isHL || constant) {
    path.__stroked = {
      width: style.lineStyle === 'solid' && !isHL ? (minW + maxW) / 2 : style.width,
      cap: isHL ? 'butt' : 'round',
      dash: dashPattern(style.lineStyle, style.lineStyle === 'solid' && !isHL ? (minW + maxW) / 2 : style.width),
    };
    traceCenterline(path, s.map((q) => q.p));
    return path;
  }
  // Split at sharp reversals so each run gets clean round caps; all runs
  // share orientation so the non-zero fill unions them.
  let run = [s[0]];
  for (let i = 1; i < s.length; i++) {
    run.push(s[i]);
    if (i < s.length - 1) {
      const a = norm(sub(s[i].p, s[i - 1].p)), b = norm(sub(s[i + 1].p, s[i].p));
      if (a.x * b.x + a.y * b.y < -0.2) { appendOutline(path, run); run = [s[i]]; }
    }
  }
  appendOutline(path, run);
  return path;
}

// Pencil pressure jitters from sample to sample, which made ink look lumpy.
// Smooth widths over distance along the stroke (forward and backward, so
// there's no lag), and keep the first and last bits from bulging where the
// Pencil lands and lifts.
const WIDTH_SMOOTHING = 3; // pt along the stroke

function smoothWidths(s) {
  const n = s.length;
  if (n < 3) return;
  const w = s.map((q) => q.w);
  const sorted = w.slice().sort((a, b) => a - b);
  const median = sorted[n >> 1];
  for (const k of [0, 1, n - 2, n - 1]) w[k] = Math.min(w[k], median);
  const f = new Array(n), b = new Array(n);
  f[0] = w[0];
  for (let i = 1; i < n; i++) {
    const a = 1 - Math.exp(-Math.hypot(s[i].p.x - s[i - 1].p.x, s[i].p.y - s[i - 1].p.y) / WIDTH_SMOOTHING);
    f[i] = f[i - 1] + (w[i] - f[i - 1]) * a;
  }
  b[n - 1] = w[n - 1];
  for (let i = n - 2; i >= 0; i--) {
    const a = 1 - Math.exp(-Math.hypot(s[i].p.x - s[i + 1].p.x, s[i].p.y - s[i + 1].p.y) / WIDTH_SMOOTHING);
    b[i] = b[i + 1] + (w[i] - b[i + 1]) * a;
  }
  for (let i = 0; i < n; i++) s[i].w = (f[i] + b[i]) / 2;
}

function smoothSamples(s) {
  if (s.length <= 2) return s;
  s = s.map((q) => ({ p: { ...q.p }, w: q.w }));
  for (let pass = 0; pass < 2; pass++) {
    const next = s.map((q) => ({ p: { ...q.p }, w: q.w }));
    for (let i = 1; i < s.length - 1; i++) {
      next[i].p.x = (s[i - 1].p.x + 2 * s[i].p.x + s[i + 1].p.x) / 4;
      next[i].p.y = (s[i - 1].p.y + 2 * s[i].p.y + s[i + 1].p.y) / 4;
    }
    s = next;
  }
  smoothWidths(s);
  s[0].w = Math.min(s[0].w, s[1].w * 1.1);
  s[s.length - 1].w = Math.min(s[s.length - 1].w, s[s.length - 2].w * 1.1);
  return s;
}

export function traceCenterline(path, pts) {
  path.moveTo(pts[0].x, pts[0].y);
  if (pts.length === 2) { path.lineTo(pts[1].x, pts[1].y); return; }
  const m = mid(pts[0], pts[1]);
  path.lineTo(m.x, m.y);
  for (let i = 1; i < pts.length - 1; i++) {
    const n = mid(pts[i], pts[i + 1]);
    path.quadraticCurveTo(pts[i].x, pts[i].y, n.x, n.y);
  }
  path.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y);
}

function appendOutline(path, s) {
  const n = s.length;
  if (n === 1) {
    const r = s[0].w / 2;
    path.moveTo(s[0].p.x + r, s[0].p.y);
    path.arc(s[0].p.x, s[0].p.y, r, 0, Math.PI * 2);
    return;
  }
  const normals = s.map((_, i) => {
    let t = norm(sub(s[Math.min(i + 1, n - 1)].p, s[Math.max(i - 1, 0)].p));
    if (!t.x && !t.y) t = { x: 1, y: 0 };
    return perp(t);
  });
  const left = s.map((q, i) => add(q.p, mul(normals[i], q.w / 2)));
  const right = s.map((q, i) => sub(q.p, mul(normals[i], q.w / 2)));
  path.moveTo(left[0].x, left[0].y);
  addSmooth(path, left);
  const endAng = angleOf(normals[n - 1]);
  path.arc(s[n - 1].p.x, s[n - 1].p.y, s[n - 1].w / 2, endAng, endAng - Math.PI, true);
  path.lineTo(right[n - 1].x, right[n - 1].y);
  addSmooth(path, right.slice().reverse());
  const startAng = angleOf(mul(normals[0], -1));
  path.arc(s[0].p.x, s[0].p.y, s[0].w / 2, startAng, startAng - Math.PI, true);
  path.closePath();
}

function addSmooth(path, pts) {
  if (pts.length === 2) { path.lineTo(pts[1].x, pts[1].y); return; }
  const m = mid(pts[0], pts[1]);
  path.lineTo(m.x, m.y);
  for (let i = 1; i < pts.length - 1; i++) {
    const n = mid(pts[i], pts[i + 1]);
    path.quadraticCurveTo(pts[i].x, pts[i].y, n.x, n.y);
  }
  path.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y);
}

export { maxWidth, clamp, cross };
