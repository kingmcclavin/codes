// Converts a rough freehand stroke into clean geometry: lines, arrows,
// triangles, rectangles, regular polygons, ellipses and simple curves.
// Fits the intended geometry (least-squares sides, right angles, axis snaps)
// and snaps endpoints to existing shapes.

import {
  add, sub, mul, dot, cross, len, dist, norm, perp, mid, angleOf, unit, rotateAround,
  angleDifference, normalizeAngle, boundsOf, rectDiagonal, pathLength, resampleCount, resampleSpacing,
  fitLine, principalAxes, lineIntersection, distToPolyline, polygonArea,
} from './util.js';

const SAMPLES = 96;
const AXIS_SNAP = (5 * Math.PI) / 180;
const DIAG_SNAP = (3 * Math.PI) / 180;
const MAX_CURVE_SEGMENTS = 4;

/**
 * @param input points
 * @param ctx { snapPoints: [], snapTolerance, lines: [{id, a, b}] }
 * @returns {kind:'shape', geom, arrows} | {kind:'arrowhead', lineId, atEnd} | null
 */
export function recognize(input, ctx = {}, { allowCurve = false } = {}) {
  const context = { snapPoints: [], snapTolerance: 10, lines: [], ...ctx };
  const pts = [];
  for (const p of input) if (!pts.length || dist(pts[pts.length - 1], p) > 0.25) pts.push(p);
  if (pts.length < 2) return null;
  const diag = Math.max(rectDiagonal(boundsOf(pts)), 1);
  if (pathLength(pts) < 8) return null;
  const raw = resampleCount(pts, SAMPLES);
  const rs = smoothOpen(raw, 2);
  const length = pathLength(rs);

  const line = detectLine(rs, length);
  if (line) return shape(snapLine(line[0], line[1], context));
  const closed = closedLoop(rs, diag, length);
  if (closed) {
    const loop = resampleLoop(closed, SAMPLES);
    const poly = detectPolygon(loop, diag, context);
    if (poly) return shape(poly);
    const ell = detectEllipse(loop, context);
    if (ell) return shape(ell);
    return allowCurve ? shape(fitCurve(pts, diag)) : null;
  }
  const arrow = detectArrow(rs, raw, context);
  if (arrow) return arrow;
  const head = detectArrowHeadForLine(rs, diag, context);
  if (head) return head;
  const polyline = detectPolyline(rs, context);
  if (polyline) return shape(polyline);
  const curve = fitCurve(pts, diag);
  if (allowCurve || (curve.pts.length - 1) / 3 <= MAX_CURVE_SEGMENTS) return shape(curve);
  return null;
}

const shape = (geom, arrows = { start: false, end: false }) => ({ kind: 'shape', geom, arrows });

export function fitCurve(pts, diag) {
  const spaced = resampleSpacing(pts, Math.max(1.5, diag / 120));
  const smoothed = smoothOpen(spaced, 2);
  return { kind: 'curve', pts: fitBezier(smoothed, Math.max(1.2, diag * 0.012)) };
}

// ---------- Lines ----------

function detectLine(rs, length) {
  const a = rs[0], b = rs[rs.length - 1];
  const chord = dist(a, b);
  if (chord <= 4 || chord / length <= 0.93) return null;
  const fit = fitLine(rs);
  let maxDev = 0;
  for (const p of rs) maxDev = Math.max(maxDev, Math.abs(cross(sub(p, fit.point), fit.direction)));
  if (maxDev >= Math.max(2.5, chord * 0.07)) return null;
  const project = (p) => add(fit.point, mul(fit.direction, dot(sub(p, fit.point), fit.direction)));
  return [project(a), project(b)];
}

function nearestSnap(p, c) {
  let best = null, bestD = c.snapTolerance;
  for (const q of c.snapPoints) { const d = dist(q, p); if (d <= bestD) { bestD = d; best = q; } }
  return best;
}

function snapAngle(a) {
  for (let k = 0; k < 8; k++) {
    const target = (k * Math.PI) / 4;
    if (angleDifference(a, target) < (k % 2 === 0 ? AXIS_SNAP : DIAG_SNAP)) return target;
  }
  return a;
}

function snapLine(s0, e0, c) {
  const sS = nearestSnap(s0, c), eS = nearestSnap(e0, c);
  if (sS && eS && dist(sS, eS) > 1) return { kind: 'line', a: { ...sS }, b: { ...eS } };
  if (eS && !sS) {
    const l = dist(e0, s0), ang = snapAngle(angleOf(sub(s0, eS)));
    return { kind: 'line', a: add(eS, mul(unit(ang), l)), b: { ...eS } };
  }
  const anchor = sS || s0, l = dist(anchor, e0), ang = snapAngle(angleOf(sub(e0, anchor)));
  return { kind: 'line', a: { ...anchor }, b: add(anchor, mul(unit(ang), l)) };
}

// ---------- Closed shapes ----------

function closedLoop(rs, diag, length) {
  const first = rs[0], last = rs[rs.length - 1];
  if (length <= diag * 1.6) return null;
  if (dist(first, last) <= diag * 0.22) return rs;
  let bestI = -1, bestD = Infinity;
  for (let i = Math.floor(rs.length * 0.55); i < rs.length; i++) {
    const d = dist(rs[i], first);
    if (d < bestD) { bestD = d; bestI = i; }
  }
  if (bestI > 0 && bestD <= diag * 0.12) return rs.slice(0, bestI + 1);
  return null;
}

function resampleLoop(pts, count) {
  const r = resampleCount([...pts, pts[0]], count + 1);
  if (r.length > count) r.pop();
  return r;
}

function turning(p, k, closed) {
  const n = p.length;
  return p.map((_, i) => {
    let a, b;
    if (closed) { a = p[(i - k + n) % n]; b = p[(i + k) % n]; } else {
      if (i - k < 0 || i + k >= n) return 0;
      a = p[i - k]; b = p[i + k];
    }
    const v1 = sub(p[i], a), v2 = sub(b, p[i]);
    if (len(v1) < 1e-6 || len(v2) < 1e-6) return 0;
    return angleDifference(angleOf(v1), angleOf(v2));
  });
}

function corners(p, k, threshold, closed) {
  const turn = turning(p, k, closed), n = p.length;
  const cand = [...Array(n).keys()].filter((i) => turn[i] > threshold).sort((a, b) => turn[b] - turn[a]);
  const accepted = [];
  for (const c of cand) {
    const tooClose = accepted.some((a) => { const d = Math.abs(a - c); return (closed ? Math.min(d, n - d) : d) <= k + 1; });
    if (!tooClose) accepted.push(c);
  }
  return accepted.sort((a, b) => a - b);
}

function detectPolygon(loop, diag, c) {
  const n = loop.length;
  const cs = corners(loop, 4, (40 * Math.PI) / 180, true);
  if (cs.length < 3 || cs.length > 8) return null;
  const lines = [];
  for (let j = 0; j < cs.length; j++) {
    const a = cs[j], b = cs[(j + 1) % cs.length];
    const span = (b - a + n) % n;
    if (span < 3) return null;
    const trim = Math.max(1, Math.floor(span / 6));
    const side = [];
    for (let i = a + trim; i <= a + span - trim; i++) side.push(loop[i % n]);
    const fit = fitLine(side);
    const sideLen = dist(loop[a], loop[b % n]);
    const maxDev = Math.max(...side.map((q) => Math.abs(cross(sub(q, fit.point), fit.direction))));
    if (maxDev > Math.max(2.5, sideLen * 0.12)) return null;
    lines.push(fit);
  }
  const vertices = cs.map((ci, j) => {
    const l1 = lines[(j - 1 + cs.length) % cs.length], l2 = lines[j];
    const x = lineIntersection(l1.point, l1.direction, l2.point, l2.direction);
    return x && dist(x, loop[ci]) < diag * 0.25 ? x : loop[ci];
  });
  const closedV = [...vertices, vertices[0]];
  const meanErr = loop.reduce((s, q) => s + distToPolyline(q, closedV), 0) / n;
  if (meanErr / diag >= 0.035) return null;
  const perim = pathLength(closedV);
  for (let j = 0; j < vertices.length; j++) if (dist(vertices[j], vertices[(j + 1) % vertices.length]) < perim * 0.04) return null;

  if (vertices.length === 3) return { kind: 'polygon', pts: regularizeTriangle(vertices, c), closed: true };
  if (vertices.length === 4) return rectangle(vertices, c) || { kind: 'polygon', pts: snapPolygonRotation(vertices), closed: true };
  return { kind: 'polygon', pts: regularizePolygon(vertices), closed: true };
}

function interiorAngles(v) {
  const n = v.length;
  return v.map((p, i) => angleDifference(angleOf(sub(v[(i - 1 + n) % n], p)), angleOf(sub(v[(i + 1) % n], p))));
}

function rectangle(v, c) {
  const tol = (13 * Math.PI) / 180;
  if (!interiorAngles(v).every((a) => Math.abs(a - Math.PI / 2) < tol)) return null;
  let sx = 0, sy = 0;
  for (let i = 0; i < 4; i++) {
    const e = sub(v[(i + 1) % 4], v[i]), a = 4 * angleOf(e);
    sx += Math.cos(a) * len(e); sy += Math.sin(a) * len(e);
  }
  let theta = Math.atan2(sy, sx) / 4;
  if (angleDifference(theta, 0) < (7 * Math.PI) / 180) theta = 0;
  const u = unit(theta), w = perp(u);
  const su = v.map((p) => dot(p, u)).sort((a, b) => a - b), sw = v.map((p) => dot(p, w)).sort((a, b) => a - b);
  let width = (su[2] + su[3] - (su[0] + su[1])) / 2;
  let height = (sw[2] + sw[3] - (sw[0] + sw[1])) / 2;
  let center = add(mul(u, (su[0] + su[3]) / 2), mul(w, (sw[0] + sw[3]) / 2));
  if (Math.abs(width - height) / Math.max(width, height) < 0.1) { const s = (width + height) / 2; width = s; height = s; }
  center = nearestSnap(center, c) || center;
  return { kind: 'rect', box: { cx: center.x, cy: center.y, w: width, h: height, rot: theta } };
}

const centroid = (v) => mul(v.reduce((s, p) => add(s, p), { x: 0, y: 0 }), 1 / Math.max(v.length, 1));

function snapPolygonRotation(v) {
  let best = Infinity, corr = 0;
  for (let i = 0; i < v.length; i++) {
    const a = angleOf(sub(v[(i + 1) % v.length], v[i]));
    for (let k = 0; k < 4; k++) {
      const d = normalizeAngle((k * Math.PI) / 2 - a);
      if (Math.abs(d) < best) { best = Math.abs(d); corr = d; }
    }
  }
  if (best >= AXIS_SNAP || best <= 1e-6) return v;
  const c = centroid(v);
  return v.map((p) => rotateAround(p, corr, c));
}

function regularizeTriangle(input, c) {
  let v = input.slice();
  const angles = interiorAngles(v), tol = (7 * Math.PI) / 180;
  if (angles.every((a) => Math.abs(a - Math.PI / 3) < tol)) {
    const ct = centroid(v), r = v.reduce((s, p) => s + dist(p, ct), 0) / 3, start = angleOf(sub(v[0], ct));
    v = [0, 1, 2].map((i) => add(ct, mul(unit(start + (i * 2 * Math.PI) / 3), r)));
    if (polygonArea(v) * polygonArea(input) < 0) v = [v[0], v[2], v[1]];
  } else {
    const right = angles.findIndex((a) => Math.abs(a - Math.PI / 2) < tol);
    if (right >= 0) {
      const a = v[(right + 2) % 3], b = v[(right + 1) % 3], m = mid(a, b), r = dist(a, b) / 2;
      const dir = norm(sub(v[right], m));
      if (dir.x || dir.y) v[right] = add(m, mul(dir, r));
    }
  }
  return snapPolygonRotation(v).map((p) => nearestSnap(p, c) || p);
}

function regularizePolygon(v) {
  const n = v.length;
  const sides = v.map((p, i) => dist(p, v[(i + 1) % n]));
  const mean = sides.reduce((a, b) => a + b, 0) / n;
  const dev = Math.max(...sides.map((s) => Math.abs(s - mean)));
  const regular = ((n - 2) * Math.PI) / n;
  const anglesOK = interiorAngles(v).every((a) => Math.abs(a - regular) < (12 * Math.PI) / 180);
  if (dev / mean >= 0.2 || !anglesOK) return snapPolygonRotation(v);
  const c = centroid(v), r = v.reduce((s, p) => s + dist(p, c), 0) / n, start = angleOf(sub(v[0], c));
  const sign = polygonArea(v) >= 0 ? 1 : -1;
  return snapPolygonRotation([...Array(n).keys()].map((i) => add(c, mul(unit(start + (sign * i * 2 * Math.PI) / n), r))));
}

function detectEllipse(loop, c) {
  const axes = principalAxes(loop);
  let theta = angleOf(axes.major);
  const u = axes.major, w = axes.minor;
  const pu = loop.map((p) => dot(sub(p, axes.centroid), u)), pw = loop.map((p) => dot(sub(p, axes.centroid), w));
  const cu = (Math.min(...pu) + Math.max(...pu)) / 2, cw = (Math.min(...pw) + Math.max(...pw)) / 2;
  let center = add(add(axes.centroid, mul(u, cu)), mul(w, cw));
  const lu = pu.map((x) => x - cu), lw = pw.map((x) => x - cw);
  let s40 = 0, s22 = 0, s04 = 0, s20 = 0, s02 = 0;
  for (let i = 0; i < loop.length; i++) {
    const u2 = lu[i] * lu[i], w2 = lw[i] * lw[i];
    s40 += u2 * u2; s22 += u2 * w2; s04 += w2 * w2; s20 += u2; s02 += w2;
  }
  const det = s40 * s04 - s22 * s22;
  if (Math.abs(det) <= 1e-9) return null;
  const A = (s20 * s04 - s02 * s22) / det, B = (s40 * s02 - s22 * s20) / det;
  if (A <= 0 || B <= 0) return null;
  let a = 1 / Math.sqrt(A), b = 1 / Math.sqrt(B);
  let err = 0;
  for (let i = 0; i < loop.length; i++) err += Math.abs(Math.sqrt(lu[i] * lu[i] * A + lw[i] * lw[i] * B) - 1);
  err /= loop.length;
  if (err >= 0.12 || Math.min(a, b) <= 1) return null;
  const deg8 = (8 * Math.PI) / 180;
  if (Math.min(a, b) / Math.max(a, b) > 0.86) { const r = (a + b) / 2; a = r; b = r; theta = 0; } else if (angleDifference(theta, 0) < deg8 || angleDifference(theta, Math.PI) < deg8) theta = 0;
  else if (angleDifference(theta, Math.PI / 2) < deg8 || angleDifference(theta, -Math.PI / 2) < deg8) { theta = 0; [a, b] = [b, a]; }
  center = nearestSnap(center, c) || center;
  return { kind: 'ellipse', box: { cx: center.x, cy: center.y, w: 2 * a, h: 2 * b, rot: theta } };
}

// ---------- Open shapes ----------

function straightness(pts) {
  const l = pathLength(pts);
  return l > 0 ? dist(pts[0], pts[pts.length - 1]) / l : 0;
}

function detectArrow(rs, raw, c) {
  return arrowForward(rs, raw, c) || arrowForward(rs.slice().reverse(), raw.slice().reverse(), c);
}

function arrowForward(rs, raw, c) {
  const n = rs.length, turn = turning(rs, 2, false);
  const from = Math.floor(n * 0.35), to = Math.floor(n * 0.95);
  let tip = -1;
  for (let i = from; i < to; i++) if (turn[i] > (100 * Math.PI) / 180) { tip = i; break; }
  if (tip < 0) return null;
  const shaft = rs.slice(0, tip + 1);
  if (straightness(shaft) <= 0.93) return null;
  const fit = fitLine(shaft);
  let dir = fit.direction;
  if (dot(sub(rs[tip], rs[0]), dir) < 0) dir = mul(dir, -1);
  const project = (p) => add(fit.point, mul(fit.direction, dot(sub(p, fit.point), fit.direction)));
  const start = project(raw[0]), tipP = project(raw[Math.min(tip, raw.length - 1)]);
  const shaftLen = dist(start, tipP);
  if (shaftLen <= 12) return null;
  const head = rs.slice(tip);
  const headLen = pathLength(head);
  if (headLen <= shaftLen * 0.08 || headLen >= shaftLen * 1.6) return null;
  if (!head.every((p) => dist(p, tipP) < Math.max(shaftLen * 0.45, 10))) return null;
  const back = head.slice(1).map((p) => dot(norm(sub(p, tipP)), mul(dir, -1)));
  if (!back.length || back.reduce((a, b) => a + b, 0) / back.length <= 0.45) return null;
  const l = snapLine(start, tipP, c);
  return shape(l, { start: false, end: true });
}

function detectArrowHeadForLine(rs, diag, c) {
  if (!c.lines.length) return null;
  const cs = corners(rs, 4, (50 * Math.PI) / 180, false);
  if (cs.length !== 1) return null;
  const apex = rs[cs[0]], arms = [rs[0], rs[rs.length - 1]];
  for (const line of c.lines) {
    const lineLen = dist(line.a, line.b);
    if (lineLen <= 10 || diag >= Math.max(80, lineLen * 0.6)) continue;
    for (const atEnd of [true, false]) {
      const endpoint = atEnd ? line.b : line.a, other = atEnd ? line.a : line.b;
      if (dist(apex, endpoint) >= Math.max(14, diag * 0.35)) continue;
      const outward = norm(sub(endpoint, other));
      if (arms.every((a) => dot(norm(sub(a, apex)), outward) < -0.25)) return { kind: 'arrowhead', lineId: line.id, atEnd };
    }
  }
  return null;
}

function detectPolyline(rs, c) {
  const cs = corners(rs, 4, (40 * Math.PI) / 180, false);
  if (cs.length < 1 || cs.length > 5) return null;
  const bounds = [0, ...cs, rs.length - 1];
  const lines = [];
  for (let j = 0; j < bounds.length - 1; j++) {
    const a = bounds[j], b = bounds[j + 1];
    if (b - a < 3) return null;
    const trim = Math.max(1, Math.floor((b - a) / 6));
    const lo = j === 0 ? a : a + trim, hi = j === bounds.length - 2 ? b : b - trim;
    if (hi <= lo) return null;
    if (straightness(rs.slice(a, b + 1)) <= 0.95) return null;
    const fit = fitLine(rs.slice(lo, hi + 1));
    fit.direction = unit(snapAngle(angleOf(fit.direction)));
    lines.push(fit);
  }
  const project = (p, l) => add(l.point, mul(l.direction, dot(sub(p, l.point), l.direction)));
  const vertices = [nearestSnap(rs[0], c) || project(rs[0], lines[0])];
  for (let j = 1; j < lines.length; j++) {
    const sample = rs[bounds[j]];
    const x = lineIntersection(lines[j - 1].point, lines[j - 1].direction, lines[j].point, lines[j].direction);
    vertices.push(x && dist(x, sample) < 40 ? x : sample);
  }
  vertices.push(nearestSnap(rs[rs.length - 1], c) || project(rs[rs.length - 1], lines[lines.length - 1]));
  return { kind: 'polygon', pts: vertices, closed: false };
}

function smoothOpen(p, passes) {
  if (p.length <= 2) return p;
  let s = p.map((q) => ({ ...q }));
  for (let k = 0; k < passes; k++) {
    const next = s.map((q) => ({ ...q }));
    for (let i = 1; i < s.length - 1; i++) next[i] = { x: (s[i - 1].x + 2 * s[i].x + s[i + 1].x) / 4, y: (s[i - 1].y + 2 * s[i].y + s[i + 1].y) / 4 };
    s = next;
  }
  return s;
}

// ---------- Bézier fitting (Schneider) ----------

function fitBezier(pts, tolerance) {
  if (pts.length < 2) return pts.slice();
  if (pts.length === 2) return [pts[0], lerp3(pts[0], pts[1], 1 / 3), lerp3(pts[0], pts[1], 2 / 3), pts[1]];
  const out = [pts[0]];
  const tHat1 = norm(sub(pts[1], pts[0])), tHat2 = norm(sub(pts[pts.length - 2], pts[pts.length - 1]));
  fitCubic(pts, 0, pts.length - 1, tHat1, tHat2, tolerance * tolerance, out, 0);
  return out;
}
const lerp3 = (a, b, t) => ({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });

function fitCubic(d, first, last, t1, t2, err2, out, depth) {
  const n = last - first + 1;
  if (n === 2) {
    const l = dist(d[first], d[last]) / 3;
    out.push(add(d[first], mul(t1, l)), add(d[last], mul(t2, l)), d[last]);
    return;
  }
  let u = chordParams(d, first, last);
  let bez = generateBezier(d, first, last, u, t1, t2);
  let [maxErr, split] = maxError(d, first, last, bez, u);
  if (maxErr < err2) { out.push(bez[1], bez[2], bez[3]); return; }
  if (maxErr < err2 * 4) {
    for (let i = 0; i < 4; i++) {
      u = reparam(d, first, last, u, bez);
      bez = generateBezier(d, first, last, u, t1, t2);
      [maxErr, split] = maxError(d, first, last, bez, u);
      if (maxErr < err2) { out.push(bez[1], bez[2], bez[3]); return; }
    }
  }
  if (depth > 12) { out.push(bez[1], bez[2], bez[3]); return; }
  split = Math.min(Math.max(split, first + 1), last - 1);
  const tc = norm(sub(d[split - 1], d[split + 1]));
  fitCubic(d, first, split, t1, tc, err2, out, depth + 1);
  fitCubic(d, split, last, mul(tc, -1), t2, err2, out, depth + 1);
}

function chordParams(d, first, last) {
  const u = [0];
  for (let i = first + 1; i <= last; i++) u.push(u[u.length - 1] + dist(d[i], d[i - 1]));
  const total = u[u.length - 1] || 1;
  return u.map((x) => x / total);
}

function bezierAt(b, t) {
  const mt = 1 - t;
  return {
    x: mt * mt * mt * b[0].x + 3 * mt * mt * t * b[1].x + 3 * mt * t * t * b[2].x + t * t * t * b[3].x,
    y: mt * mt * mt * b[0].y + 3 * mt * mt * t * b[1].y + 3 * mt * t * t * b[2].y + t * t * t * b[3].y,
  };
}

function generateBezier(d, first, last, u, t1, t2) {
  const p0 = d[first], p3 = d[last];
  let c00 = 0, c01 = 0, c11 = 0, x0 = 0, x1 = 0;
  for (let i = 0; i < u.length; i++) {
    const t = u[i], mt = 1 - t;
    const b0 = mt * mt * mt, b1 = 3 * mt * mt * t, b2 = 3 * mt * t * t, b3 = t * t * t;
    const a1 = mul(t1, b1), a2 = mul(t2, b2);
    c00 += dot(a1, a1); c01 += dot(a1, a2); c11 += dot(a2, a2);
    const tmp = sub(d[first + i], add(mul(p0, b0 + b1), mul(p3, b2 + b3)));
    x0 += dot(a1, tmp); x1 += dot(a2, tmp);
  }
  const det = c00 * c11 - c01 * c01;
  let al = det ? (x0 * c11 - x1 * c01) / det : 0, ar = det ? (c00 * x1 - c01 * x0) / det : 0;
  const segLen = dist(p0, p3), eps = 1e-6 * segLen;
  if (al < eps || ar < eps) { al = ar = segLen / 3; }
  return [p0, add(p0, mul(t1, al)), add(p3, mul(t2, ar)), p3];
}

function maxError(d, first, last, bez, u) {
  let maxD = 0, split = Math.floor((first + last) / 2);
  for (let i = first + 1; i < last; i++) {
    const p = bezierAt(bez, u[i - first]);
    const e = (p.x - d[i].x) ** 2 + (p.y - d[i].y) ** 2;
    if (e >= maxD) { maxD = e; split = i; }
  }
  return [maxD, split];
}

function reparam(d, first, last, u, b) {
  return u.map((t, i) => {
    const p = d[first + i], q = bezierAt(b, t);
    const mt = 1 - t;
    const q1 = add(add(mul(sub(b[1], b[0]), 3 * mt * mt), mul(sub(b[2], b[1]), 6 * mt * t)), mul(sub(b[3], b[2]), 3 * t * t));
    const q2 = add(mul(add(sub(b[2], mul(b[1], 2)), b[0]), 6 * mt), mul(add(sub(b[3], mul(b[2], 2)), b[1]), 6 * t));
    const num = dot(sub(q, p), q1), den = dot(q1, q1) + dot(sub(q, p), q2);
    return den ? Math.min(1, Math.max(0, t - num / den)) : t;
  });
}
