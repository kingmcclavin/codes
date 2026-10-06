// Vector erasing: splits strokes where they are touched instead of painting
// over them, so erased ink stays editable.

import { boundsOf, expandRect, rectsIntersect, rectContains, distToPolyline, distToSegment, dist, pathLength, uuid } from './util.js';
import { elementBounds, STRIDE } from './elements.js';
import { maxWidth } from './model.js';

/** Returns null when untouched, otherwise the surviving fragments (maybe none). */
export function eraseStroke(stroke, path, radius) {
  if (!path.length) return null;
  const pb = expandRect(boundsOf(path), radius + maxWidth(stroke.style));
  if (!rectsIntersect(elementBounds(stroke), pb)) return null;
  const reach = radius + stroke.style.width * 0.5;
  return split(stroke, Math.max(0.5, radius * 0.4), (p) => rectContains(pb, p) && distToPolyline(p, path) <= reach);
}

function split(stroke, spacing, isErased) {
  const dense = densify(stroke.pts, spacing);
  let erasedAny = false;
  const runs = [];
  let cur = [];
  for (let i = 0; i < dense.length; i += STRIDE) {
    if (isErased({ x: dense[i], y: dense[i + 1] })) {
      erasedAny = true;
      if (cur.length) { runs.push(cur); cur = []; }
    } else {
      cur.push(dense[i], dense[i + 1], dense[i + 2], dense[i + 3]);
    }
  }
  if (cur.length) runs.push(cur);
  if (!erasedAny) return null;
  const minLen = Math.max(0.5, stroke.style.width * 0.3);
  const single = stroke.pts.length === STRIDE;
  return runs.filter((r) => {
    const n = r.length / STRIDE;
    if (n <= 1 && !single) return false;
    if (n > 1) {
      const pts = [];
      for (let i = 0; i < r.length; i += STRIDE) pts.push({ x: r[i], y: r[i + 1] });
      if (pathLength(pts) < minLen) return false;
    }
    return true;
  }).map((r) => ({ ...stroke, id: uuid(), pts: simplify(new Float32Array(r)) }));
}

function densify(pts, spacing) {
  const out = [];
  const n = pts.length / STRIDE;
  for (let i = 0; i < n; i++) {
    if (i > 0) {
      const ax = pts[(i - 1) * 4], ay = pts[(i - 1) * 4 + 1], bx = pts[i * 4], by = pts[i * 4 + 1];
      const k = Math.floor(Math.hypot(bx - ax, by - ay) / spacing);
      for (let j = 1; j <= k; j++) {
        const t = j / (k + 1);
        for (let c = 0; c < STRIDE; c++) out.push(pts[(i - 1) * 4 + c] + (pts[i * 4 + c] - pts[(i - 1) * 4 + c]) * t);
      }
    }
    for (let c = 0; c < STRIDE; c++) out.push(pts[i * 4 + c]);
  }
  return out;
}

/** Drops interpolated samples on straight runs (keeps curvature and pressure changes). */
function simplify(pts) {
  const n = pts.length / STRIDE;
  if (n <= 8) return pts;
  const P = (i) => ({ x: pts[i * 4], y: pts[i * 4 + 1] });
  const keep = [0];
  for (let i = 1; i < n - 1; i++) {
    const prev = keep[keep.length - 1];
    const dev = distToSegment(P(i), P(prev), P(i + 1));
    if (dev > 0.08 || Math.abs(pts[i * 4 + 2] - pts[prev * 4 + 2]) > 0.03 || dist(P(prev), P(i)) > 6) keep.push(i);
  }
  keep.push(n - 1);
  const out = new Float32Array(keep.length * STRIDE);
  keep.forEach((k, j) => { for (let c = 0; c < STRIDE; c++) out[j * 4 + c] = pts[k * 4 + c]; });
  return out;
}
