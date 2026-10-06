// Scribble to erase: a fast back-and-forth pen scribble over existing ink
// erases it instead of adding ink (ported from ScribbleDetector.swift and
// ScribbleEraser.swift).
//
// A scribble has many large reversals relative to its own extent, a high ink
// density (path length ≫ size) and speed. It must also lie mostly on top of
// existing content, which keeps normal handwriting ("mmm", "lll") safe.

import {
  boundsOf, expandRect, rectsIntersect, rectCenter, rectContains, rectDiagonal, pathLength, resampleSpacing,
  principalAxes, sub, dot, cross, polygonContains,
} from './util.js';
import { elementBounds, hitTest, intersectsPath, strokePoints, boxCorners } from './elements.js';
import { eraseStrokeInside } from './erase.js';

export const SCRIBBLE_MODES = [
  { value: 'strokes', label: 'Strokes' },
  { value: 'objects', label: 'Whole Objects' },
  { value: 'region', label: 'Scribbled Region' },
];

const MIN_MAJOR_REVERSALS = 4, MIN_MINOR_REVERSALS = 8;
const MIN_DENSITY = 3.2, MIN_ZIGZAG_DENSITY = 7;
const MIN_SPEED = 250, MAX_DURATION = 4;

/** @param points page-space points  @param times seconds  @param zoom page→screen scale */
export function isScribble(points, times, zoom) {
  if (points.length < 12 || points.length !== times.length) return false;
  const screen = points.map((p) => ({ x: p.x * zoom, y: p.y * zoom }));
  const length = pathLength(screen);
  const box = boundsOf(screen);
  const diag = rectDiagonal(box);
  if (diag < 10 || length <= 0) return false;
  const spaced = resampleSpacing(screen, Math.max(1.5, diag / 80));
  if (spaced.length < 8) return false;
  const axes = principalAxes(spaced);
  const major = spaced.map((p) => dot(sub(p, axes.centroid), axes.major));
  const minor = spaced.map((p) => dot(sub(p, axes.centroid), axes.minor));
  const majorExtent = Math.max(...major) - Math.min(...major);
  const minorExtent = Math.max(...minor) - Math.min(...minor);
  const duration = Math.max(times[times.length - 1] - times[0], 0.001);
  const m = {
    majorReversals: reversals(major, Math.max(4, majorExtent * 0.4)),
    minorReversals: reversals(minor, Math.max(4, minorExtent * 0.5)),
    density: length / Math.max(diag, 1),
    speed: length / duration,
  };
  if (duration > MAX_DURATION || m.speed < MIN_SPEED) return false;
  // Back-and-forth along the long axis: the classic scribble over a word.
  if (m.majorReversals >= MIN_MAJOR_REVERSALS && m.density >= MIN_DENSITY) return true;
  // A very tight, fast zig-zag across the short axis. Kept strict because
  // cursive handwriting has the same shape but is far less dense.
  return m.minorReversals >= MIN_MINOR_REVERSALS && m.density >= MIN_ZIGZAG_DENSITY
    && m.speed >= MIN_SPEED * 1.6 && minorExtent >= majorExtent * 0.15;
}

/** Counts direction reversals of a 1-D signal, ignoring wiggles smaller than `h`. */
function reversals(values, h) {
  let extreme = values[0], direction = 0, count = 0;
  for (const v of values.slice(1)) {
    if (direction === 0) {
      if (v - extreme > h) { direction = 1; extreme = v; } else if (extreme - v > h) { direction = -1; extreme = v; }
    } else if (direction === 1) {
      if (v > extreme) extreme = v; else if (extreme - v > h) { count++; direction = -1; extreme = v; }
    } else if (v < extreme) extreme = v; else if (v - extreme > h) { count++; direction = 1; extreme = v; }
  }
  return count;
}

/**
 * Returns the page's new element list, or null when the scribble doesn't
 * meaningfully cover existing content (then it's kept as ink).
 */
export function scribbleErase(scribble, elements, mode, tolerance) {
  const region = boundsOf(scribble);
  const reach = expandRect(region, tolerance);
  const candidates = elements.filter((e) => rectsIntersect(elementBounds(e), reach));
  const hit = candidates.filter((e) => intersectsPath(e, scribble, tolerance));
  if (!hit.length) return null;

  // Coverage guard: a real scribble lies mostly on top of content.
  const samples = resampleSpacing(scribble, Math.max(2, rectDiagonal(region) / 60));
  const near = samples.filter((p) => hit.some((e) => hitTest(e, p, tolerance * 1.5))).length;
  if (near / Math.max(samples.length, 1) < 0.2) return null;

  if (mode === 'region') return regionErase(scribble, candidates, elements);
  const ids = new Set(mode === 'objects' ? expandToObjects(hit, elements, region) : hit.map((e) => e.id));
  return elements.filter((e) => !ids.has(e.id));
}

function samplePointsOf(e) {
  if (e.type === 'stroke') return strokePoints(e);
  if (e.box) return [...boxCorners(e.box), { x: e.box.cx, y: e.box.cy }];
  const b = elementBounds(e);
  return [{ x: b.x, y: b.y }, { x: b.x + b.w, y: b.y }, { x: b.x + b.w, y: b.y + b.h }, { x: b.x, y: b.y + b.h }, rectCenter(b)];
}

/** Grows the hit set to whole objects: elements that touch each other (the letters of a word). */
function expandToObjects(hit, elements, region) {
  const neighbourhood = expandRect(region, Math.max(12, rectDiagonal(region) * 0.3));
  const pool = elements.filter((e) => rectsIntersect(elementBounds(e), neighbourhood));
  const selected = new Set(hit.map((e) => e.id));
  const queue = hit.slice();
  const gap = 3;
  while (queue.length) {
    const e = queue.pop();
    const eb = expandRect(elementBounds(e), gap);
    for (const o of pool) {
      if (selected.has(o.id) || !rectContains(neighbourhood, rectCenter(elementBounds(o)))) continue;
      if (!rectsIntersect(elementBounds(o), eb)) continue;
      const close = o.type === 'stroke' && e.type === 'stroke'
        ? samplePointsOf(o).some((p) => hitTest(e, p, gap + 2)) || samplePointsOf(e).some((p) => hitTest(o, p, gap + 2))
        : true;
      if (close) { selected.add(o.id); queue.push(o); }
    }
  }
  return [...selected];
}

/** Erases everything inside the scribble's hull; strokes crossing it are split. */
function regionErase(scribble, candidates, elements) {
  const hull = convexHull(scribble);
  if (hull.length < 3) return null;
  const ids = new Set(candidates.map((e) => e.id));
  let changed = false;
  const out = [];
  for (const e of elements) {
    if (!ids.has(e.id)) { out.push(e); continue; }
    if (e.type === 'stroke') {
      const pieces = eraseStrokeInside(e, hull);
      if (pieces) { changed = true; out.push(...pieces); } else out.push(e);
    } else {
      const s = samplePointsOf(e);
      if (s.filter((p) => polygonContains(hull, p)).length / Math.max(s.length, 1) >= 0.5) changed = true;
      else out.push(e);
    }
  }
  return changed ? out : null;
}

function convexHull(points) {
  const pts = points.slice().sort((a, b) => (a.x === b.x ? a.y - b.y : a.x - b.x));
  if (pts.length <= 2) return pts;
  const half = (list) => {
    const h = [];
    for (const p of list) {
      while (h.length >= 2 && cross(sub(h[h.length - 1], h[h.length - 2]), sub(p, h[h.length - 2])) <= 0) h.pop();
      h.push(p);
    }
    h.pop();
    return h;
  };
  return [...half(pts), ...half(pts.slice().reverse())];
}
