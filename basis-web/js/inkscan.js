// Turns a photo of handwriting on paper into ink strokes, on the device.
//
// 1. Estimate the paper's brightness everywhere (so shadows and uneven light
//    don't count as ink) and mark pixels clearly darker than the paper.
// 2. Drop specks and big dark areas (the desk, shadows) that aren't pen lines.
// 3. Thin what's left to one-pixel centerlines and trace them into strokes,
//    keeping each stroke's thickness and color.

const MAX_SIDE = 1600;     // working size of the photo, px
const BLOCK = 16;          // paper brightness is estimated per block
const MAX_PEN_RADIUS = 10; // thicker than this isn't writing (desk, shadow, photo)

/** Reads the cropped part of a photo (crop in 0–1 units) and measures how much darker than the paper each pixel is. */
export function preparePhoto(img, crop = { x: 0, y: 0, w: 1, h: 1 }) {
  const iw = img.naturalWidth || img.width, ih = img.naturalHeight || img.height;
  const sx = crop.x * iw, sy = crop.y * ih, sw = crop.w * iw, sh = crop.h * ih;
  const s = Math.min(1, MAX_SIDE / Math.max(sw, sh));
  const W = Math.max(8, Math.round(sw * s)), H = Math.max(8, Math.round(sh * s));
  const c = document.createElement('canvas');
  c.width = W; c.height = H;
  const ctx = c.getContext('2d', { willReadFrequently: true });
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, W, H);
  ctx.drawImage(img, sx, sy, sw, sh, 0, 0, W, H);
  const rgb = ctx.getImageData(0, 0, W, H).data;
  const n = W * H;
  const gray = new Float32Array(n);
  for (let i = 0, k = 0; i < n; i++, k += 4) gray[i] = 0.299 * rgb[k] + 0.587 * rgb[k + 1] + 0.114 * rgb[k + 2];

  // Paper brightness: brightest pixel per block, spread to neighbors (blocks
  // full of ink), smoothed, then interpolated per pixel.
  const gw = Math.ceil(W / BLOCK), gh = Math.ceil(H / BLOCK);
  let grid = new Float32Array(gw * gh);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const g = (y / BLOCK | 0) * gw + (x / BLOCK | 0);
    if (gray[y * W + x] > grid[g]) grid[g] = gray[y * W + x];
  }
  const spread = (src, pick) => {
    const out = new Float32Array(gw * gh);
    for (let y = 0; y < gh; y++) for (let x = 0; x < gw; x++) {
      let acc = pick === 'max' ? 0 : 0, cnt = 0;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const X = x + dx, Y = y + dy;
        if (X < 0 || Y < 0 || X >= gw || Y >= gh) continue;
        const v = src[Y * gw + X];
        if (pick === 'max') acc = Math.max(acc, v); else { acc += v; cnt++; }
      }
      out[y * gw + x] = pick === 'max' ? acc : acc / cnt;
    }
    return out;
  };
  grid = spread(grid, 'max');
  grid = spread(spread(grid, 'mean'), 'mean');
  const bgAt = (x, y) => {
    const fx = Math.min(gw - 1, Math.max(0, x / BLOCK - 0.5)), fy = Math.min(gh - 1, Math.max(0, y / BLOCK - 0.5));
    const x0 = fx | 0, y0 = fy | 0, x1 = Math.min(gw - 1, x0 + 1), y1 = Math.min(gh - 1, y0 + 1), tx = fx - x0, ty = fy - y0;
    const top = grid[y0 * gw + x0] * (1 - tx) + grid[y0 * gw + x1] * tx;
    const bot = grid[y1 * gw + x0] * (1 - tx) + grid[y1 * gw + x1] * tx;
    return top * (1 - ty) + bot * ty;
  };
  const dark = new Float32Array(n);
  let pr = 0, pg = 0, pb = 0, pc = 0;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = y * W + x, bg = Math.max(40, bgAt(x, y));
    const d = Math.min(1, Math.max(0, 1 - gray[i] / bg));
    dark[i] = d;
    if (d < 0.04) { pr += rgb[i * 4]; pg += rgb[i * 4 + 1]; pb += rgb[i * 4 + 2]; pc++; }
  }
  const paper = pc ? { r: pr / pc, g: pg / pc, b: pb / pc } : { r: 255, g: 255, b: 255 };
  return { W, H, dark, rgb, paper };
}

/**
 * Finds the writing. `sensitivity` 0–1: higher picks up fainter marks.
 * Returns strokes in photo pixels: [{ pts: [{x, y}], width, color: {r,g,b} (0–1) | null }].
 * `color` is null for black/gray ink (use the pen color).
 */
export function traceInk(prep, { sensitivity = 0.5, removeLines = true } = {}) {
  const { W, H, dark, rgb, paper } = prep, n = W * H;
  const strong = 0.5 - sensitivity * 0.4; // 0.10 (faint pencil) … 0.50 (bold pen only)
  const weak = strong * 0.6;

  // Notebook lines are light blue (and the margin pink); pen ink is much darker.
  const lineTint = (i) => {
    const r = rgb[i * 4] / paper.r, g = rgb[i * 4 + 1] / paper.g, b = rgb[i * 4 + 2] / paper.b;
    return (b - r > 0.06 || r - g > 0.08) && dark[i] < 0.42;
  };

  // Ink: clearly dark pixels, plus fainter ones right next to them (soft stroke edges).
  const strongMask = new Uint8Array(n);
  for (let y = 1; y < H - 1; y++) for (let x = 1; x < W - 1; x++) {
    const i = y * W + x;
    if (dark[i] > strong && !(removeLines && lineTint(i))) strongMask[i] = 1;
  }
  const near = dilate(strongMask, W, H, 2);
  const mask = new Uint8Array(n);
  for (let i = 0; i < n; i++) if (strongMask[i] || (near[i] && dark[i] > weak && !(removeLines && lineTint(i)))) mask[i] = 1;
  for (let x = 0; x < W; x++) mask[x] = mask[(H - 1) * W + x] = 0;
  for (let y = 0; y < H; y++) mask[y * W] = mask[y * W + W - 1] = 0;
  // Close pinholes inside strokes.
  for (let y = 1; y < H - 1; y++) for (let x = 1; x < W - 1; x++) {
    const i = y * W + x;
    if (mask[i]) continue;
    const k = mask[i - 1] + mask[i + 1] + mask[i - W] + mask[i + W];
    if (k >= 3) mask[i] = 2;
  }
  for (let i = 0; i < n; i++) if (mask[i]) mask[i] = 1;
  if (removeLines) removeRuledLines(mask, dark, W, H);

  // Big dark areas (the desk, a shadow, a printed photo) aren't writing:
  // clear them and their edges, without losing writing that touches them.
  let dt = distanceTransform(mask, W, H);
  const blob = new Uint8Array(n);
  let anyBlob = false;
  for (let i = 0; i < n; i++) if (dt[i] > MAX_PEN_RADIUS) { blob[i] = 1; anyBlob = true; }
  if (anyBlob) {
    const zone = dilate(blob, W, H, MAX_PEN_RADIUS + 2);
    for (let i = 0; i < n; i++) if (zone[i]) mask[i] = 0;
    dt = distanceTransform(mask, W, H);
  }

  // Drop specks.
  const label = new Uint8Array(n);
  const stack = [];
  const minArea = Math.max(6, Math.round((W * H) / 400000));
  for (let s = 0; s < n; s++) {
    if (!mask[s] || label[s]) continue;
    const members = [];
    stack.push(s); label[s] = 1;
    while (stack.length) {
      const i = stack.pop();
      members.push(i);
      for (const j of [i - 1, i + 1, i - W, i + W, i - W - 1, i - W + 1, i + W - 1, i + W + 1]) {
        if (mask[j] && !label[j]) { label[j] = 1; stack.push(j); }
      }
    }
    if (members.length < minArea) for (const i of members) mask[i] = 0;
  }

  thin(mask, W, H);
  let strokes = traceSkeleton(mask, W, H, dt);

  const thick = median(strokes.map((s) => s.width)) || 2;
  strokes = strokes.filter((s) => s.isolated || s.length >= thick * 1.5);
  if (removeLines) {
    // Printed dots (dot-grid paper) are small and lighter than the writing.
    const darkOf = (s) => median(s.pix.map((i) => dark[i]));
    const writingDark = median(strokes.filter((s) => s.length > Math.max(30, thick * 8)).map(darkOf)) || 1; // long strokes: real writing
    const small = (s) => {
      let x0 = W, y0 = H, x1 = 0, y1 = 0;
      for (const i of s.pix) { const x = i % W, y = (i / W) | 0; if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
      return Math.max(x1 - x0, y1 - y0) < Math.max(6, thick * 3);
    };
    strokes = strokes.filter((s) => !isMarginLine(s, W, H) && !(small(s) && darkOf(s) < writingDark * 0.75));
  }
  for (const s of strokes) {
    s.color = inkColor(prep, s.pix);
    s.pts = simplify(smooth(s.pix.map((i) => ({ x: (i % W) + 0.5, y: ((i / W) | 0) + 0.5 }))), 0.6);
    delete s.pix;
  }
  return strokes;
}

// Square dilation of a 0/1 mask by radius r (separable running counts).
function dilate(src, W, H, r) {
  const tmp = new Uint8Array(W * H), out = new Uint8Array(W * H);
  for (let y = 0; y < H; y++) {
    let c = 0;
    const row = y * W;
    for (let x = 0; x < Math.min(r, W); x++) c += src[row + x];
    for (let x = 0; x < W; x++) {
      if (x + r < W) c += src[row + x + r];
      if (x - r - 1 >= 0) c -= src[row + x - r - 1];
      tmp[row + x] = c > 0 ? 1 : 0;
    }
  }
  for (let x = 0; x < W; x++) {
    let c = 0;
    for (let y = 0; y < Math.min(r, H); y++) c += tmp[y * W + x];
    for (let y = 0; y < H; y++) {
      if (y + r < H) c += tmp[(y + r) * W + x];
      if (y - r - 1 >= 0) c -= tmp[(y - r - 1) * W + x];
      out[y * W + x] = c > 0 ? 1 : 0;
    }
  }
  return out;
}

// Two-pass chamfer distance (3-4), in pixels, to the nearest non-ink pixel.
function distanceTransform(mask, W, H) {
  const n = W * H, d = new Float32Array(n), INF = 1e9;
  for (let i = 0; i < n; i++) d[i] = mask[i] ? INF : 0;
  for (let y = 1; y < H - 1; y++) for (let x = 1; x < W - 1; x++) {
    const i = y * W + x;
    if (!d[i]) continue;
    d[i] = Math.min(d[i], d[i - 1] + 3, d[i - W] + 3, d[i - W - 1] + 4, d[i - W + 1] + 4);
  }
  for (let y = H - 2; y > 0; y--) for (let x = W - 2; x > 0; x--) {
    const i = y * W + x;
    if (!d[i]) continue;
    d[i] = Math.min(d[i], d[i + 1] + 3, d[i + W] + 3, d[i + W + 1] + 4, d[i + W - 1] + 4);
  }
  for (let i = 0; i < n; i++) d[i] /= 3;
  return d;
}

// Zhang–Suen thinning, in place; then removes staircase corners so lines are 8-connected and one pixel wide.
function thin(m, W, H) {
  let pts = [];
  for (let i = 0; i < W * H; i++) if (m[i]) pts.push(i);
  const del = [];
  for (let changed = true; changed;) {
    changed = false;
    for (let step = 0; step < 2; step++) {
      del.length = 0;
      for (const i of pts) {
        if (!m[i]) continue;
        const p2 = m[i - W], p3 = m[i - W + 1], p4 = m[i + 1], p5 = m[i + W + 1], p6 = m[i + W], p7 = m[i + W - 1], p8 = m[i - 1], p9 = m[i - W - 1];
        const B = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9;
        if (B < 2 || B > 6) continue;
        const A = (!p2 && p3) + (!p3 && p4) + (!p4 && p5) + (!p5 && p6) + (!p6 && p7) + (!p7 && p8) + (!p8 && p9) + (!p9 && p2);
        if (A !== 1) continue;
        if (step === 0 ? (p2 && p4 && p6) || (p4 && p6 && p8) : (p2 && p4 && p8) || (p2 && p6 && p8)) continue;
        del.push(i);
      }
      for (const i of del) m[i] = 0;
      if (del.length) changed = true;
    }
    pts = pts.filter((i) => m[i]);
  }
  for (const i of pts) {
    const N = m[i - W], E = m[i + 1], S = m[i + W], Wst = m[i - 1];
    if ((N && E && !m[i + W - 1]) || (E && S && !m[i - W - 1]) || (S && Wst && !m[i - W + 1]) || (Wst && N && !m[i + W + 1])) {
      const ring = [m[i - W], m[i - W + 1], m[i + 1], m[i + W + 1], m[i + W], m[i + W - 1], m[i - 1], m[i - W - 1]];
      let A = 0;
      for (let k = 0; k < 8; k++) if (!ring[k] && ring[(k + 1) % 8]) A++;
      if (A === 1) m[i] = 0;
    }
  }
}

// Follows centerlines into paths. Through a crossing it carries straight on,
// so a letter's stroke stays one stroke; the other branch becomes its own.
function traceSkeleton(m, W, H, dt) {
  const OFF = [[-1, -1], [0, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [0, 1], [1, 1]];
  const nbrs = (i) => {
    const out = [];
    for (const [dx, dy] of OFF) { const j = i + dy * W + dx; if (m[j]) out.push(j); }
    return out;
  };
  const used = new Set();
  const key = (a, b) => (a < b ? a * W * H + b : b * W * H + a);
  const free = (a) => nbrs(a).filter((b) => !used.has(key(a, b)));
  const xy = (i) => ({ x: i % W, y: (i / W) | 0 });

  // Skeleton components, to know which paths stand alone (dots, short dashes).
  const comp = new Int32Array(W * H).fill(-1), compSize = [];
  const pixels = [];
  for (let i = 0; i < W * H; i++) if (m[i]) pixels.push(i);
  for (const s of pixels) {
    if (comp[s] >= 0) continue;
    const id = compSize.length, st = [s];
    comp[s] = id; let size = 0;
    while (st.length) { const i = st.pop(); size++; for (const j of nbrs(i)) if (comp[j] < 0) { comp[j] = id; st.push(j); } }
    compSize.push(size);
  }

  const paths = [];
  const walk = (start) => {
    const pix = [start];
    let cur = start;
    for (;;) {
      const cand = free(cur);
      if (!cand.length) break;
      let next = cand[0];
      if (cand.length > 1) {
        const back = xy(pix[Math.max(0, pix.length - 6)]), c = xy(cur);
        let dx = c.x - back.x, dy = c.y - back.y;
        const dl = Math.hypot(dx, dy);
        let best = -Infinity;
        for (const j of cand) {
          const q = xy(j), ex = q.x - c.x, ey = q.y - c.y, el = Math.hypot(ex, ey);
          // Without a direction yet, prefer straight (4-connected) steps.
          const score = dl ? (dx * ex + dy * ey) / (dl * el) : -el;
          if (score > best) { best = score; next = j; }
        }
        // At a crossing, don't turn sharply; leave that branch for its own stroke.
        if (dl && best < 0.2 && nbrs(cur).length >= 3) break;
      }
      used.add(key(cur, next));
      // Skip the redundant corner of a little triangle.
      for (const k of cand) if (k !== next && Math.abs(xy(k).x - xy(next).x) <= 1 && Math.abs(xy(k).y - xy(next).y) <= 1) used.add(key(cur, k));
      pix.push(next);
      cur = next;
    }
    return pix;
  };
  const add = (pix) => {
    let length = 0;
    for (let k = 1; k < pix.length; k++) { const a = xy(pix[k - 1]), b = xy(pix[k]); length += Math.hypot(a.x - b.x, a.y - b.y); }
    const widths = pix.map((i) => Math.max(1, 2 * dt[i] - 1));
    paths.push({ pix, length, width: median(widths), isolated: new Set(pix).size >= compSize[comp[pix[0]]] });
  };
  // Endpoints first, then whatever's left (closed loops like "o").
  for (const i of pixels) if (nbrs(i).length === 1 && free(i).length) add(walk(i));
  for (const i of pixels) while (free(i).length) add(walk(i));
  for (const i of pixels) if (!nbrs(i).length) add([i]);
  return paths;
}

// A long, straight, upright line: the notebook's margin.
function isMarginLine(s, W, H) {
  const a = { x: s.pix[0] % W, y: (s.pix[0] / W) | 0 }, b = { x: s.pix[s.pix.length - 1] % W, y: (s.pix[s.pix.length - 1] / W) | 0 };
  const chord = Math.hypot(b.x - a.x, b.y - a.y);
  return Math.abs(b.x - a.x) < chord * 0.17 && chord > H * 0.3 && chord / s.length > 0.97;
}

/**
 * Takes the notebook's ruled lines out of the ink mask. They're found by
 * shape, not color (cameras often make them gray): long, thin runs along the
 * page's slant. A run as dark as the writing is kept (an underline, a
 * fraction bar) unless it crosses most of the page. Where writing crosses a
 * line, the crossing stays so letters aren't cut.
 */
function removeRuledLines(mask, dark, W, H) {
  const ink = [];
  for (let i = 0; i < W * H; i++) if (mask[i]) ink.push(i);
  if (!ink.length) return;
  const stride = Math.max(1, Math.floor(ink.length / 150000));

  // The lines' slant: the slope at which ink piles up into the sharpest rows.
  const off = Math.ceil(W * 0.2) + 2, hist = new Float32Array(H + 2 * off);
  const score = (t) => {
    hist.fill(0);
    for (let k = 0; k < ink.length; k += stride) { const i = ink[k], x = i % W, y = (i / W) | 0; hist[Math.round(y - x * t) + off]++; }
    let sq = 0;
    for (const v of hist) sq += v * v;
    return sq;
  };
  let best = 0, bestScore = -1;
  for (let t = -0.18; t <= 0.18001; t += 0.01) { const v = score(t); if (v > bestScore) { bestScore = v; best = t; } }
  const coarse = best;
  for (let t = coarse - 0.01; t <= coarse + 0.01; t += 0.002) { const v = score(t); if (v > bestScore) { bestScore = v; best = t; } }
  const shift = new Int32Array(W);
  for (let x = 0; x < W; x++) shift[x] = Math.round(x * best);
  const lo = Math.min(0, shift[W - 1]), hi = Math.max(0, shift[W - 1]);

  // Long runs along that slant (a pixel of slack up or down, small gaps allowed).
  const L = Math.max(60, Math.round(W / 16)), GAP = 3;
  const at = (x, y) => y > 0 && y < H - 1 && (mask[y * W + x] || mask[(y - 1) * W + x] || mask[(y + 1) * W + x]);
  const findRuns = (r, minLen, out) => {
    let start = -1, last = -1;
    for (let x = 0; x <= W; x++) {
      const on = x < W && at(x, r + shift[x]);
      if (on) { if (start < 0) start = x; last = x; continue; }
      if (start >= 0 && (x === W || x - last > GAP)) {
        if (last - start + 1 >= minLen) out.push({ r, x0: start, x1: last });
        start = -1;
      }
    }
  };
  const runs = [];
  for (let r = 1 - hi; r < H - 1 - lo; r++) findRuns(r, L, runs);
  if (!runs.length) return;

  // How dark the writing is (everything not on a long run).
  const onRun = new Uint8Array(W * H);
  for (const u of runs) for (let x = u.x0; x <= u.x1; x++) for (let dy = -1; dy <= 1; dy++) {
    const y = u.r + shift[x] + dy;
    if (y > 0 && y < H - 1 && mask[y * W + x]) onRun[y * W + x] = 1;
  }
  const writing = new Uint32Array(101);
  for (let k = 0; k < ink.length; k += stride) if (!onRun[ink[k]]) writing[Math.round(dark[ink[k]] * 100)]++;
  const writingDark = histMedian(writing) ?? 1;

  // Which runs are ruled lines: lighter than the writing, or across most of the page.
  const kill = new Uint8Array(W * H);
  const hst = new Uint32Array(101);
  const lineRows = new Set();
  const judge = (u) => {
    hst.fill(0);
    for (let x = u.x0; x <= u.x1; x++) { const y = u.r + shift[x]; if (y > 0 && y < H - 1 && mask[y * W + x]) hst[Math.round(dark[y * W + x] * 100)]++; }
    const d = histMedian(hst) ?? 0;
    if (d >= writingDark * 0.8 && u.x1 - u.x0 < W * 0.6) return;
    lineRows.add(u.r);
    // Pen drawn on top of the line is clearly darker than the line: keep it.
    const keepAbove = Math.max(d + 0.15, writingDark * 0.85);
    for (let x = u.x0; x <= u.x1; x++) for (let dy = -1; dy <= 1; dy++) {
      const y = u.r + shift[x] + dy, i = y * W + x;
      if (y > 0 && y < H - 1 && mask[i] && dark[i] < keepAbove) kill[i] = 1;
    }
  };
  for (const u of runs) judge(u);
  // Shorter pieces of a line already found (cut up by writing or the margin).
  const rows = new Set();
  for (const r of lineRows) for (let d = -2; d <= 2; d++) rows.add(r + d);
  const pieces = [];
  for (const r of rows) if (r >= 1 - hi && r < H - 1 - lo) findRuns(r, 12, pieces);
  for (const u of pieces) judge(u);

  // Keep crossings: writing continues above and below the line there.
  const writingNear = (x, y, dir) => {
    for (let k = 2; k <= 5; k++) {
      const yy = y + dir * k;
      if (yy <= 0 || yy >= H - 1) return false;
      for (let dx = -1; dx <= 1; dx++) { const j = yy * W + x + dx; if (mask[j] && !kill[j]) return true; }
    }
    return false;
  };
  const drop = [];
  for (let i = 0; i < W * H; i++) {
    if (!kill[i]) continue;
    const x = i % W, y = (i / W) | 0;
    if (x > 0 && x < W - 1 && writingNear(x, y, -1) && writingNear(x, y, 1)) continue;
    drop.push(i);
  }
  for (const i of drop) mask[i] = 0;
}

function histMedian(hist) {
  let total = 0;
  for (const v of hist) total += v;
  if (!total) return null;
  for (let k = 0, acc = 0; k < hist.length; k++) { acc += hist[k]; if (acc * 2 >= total) return k / 100; }
  return null;
}

// The ink's color, corrected for the paper's tint. Black, gray and pencil give null (use the pen color).
function inkColor(prep, pix) {
  const { rgb, paper, dark } = prep;
  const sorted = pix.slice().sort((a, b) => dark[b] - dark[a]).slice(0, Math.max(1, Math.ceil(pix.length / 2)));
  let r = 0, g = 0, b = 0;
  for (const i of sorted) { r += rgb[i * 4]; g += rgb[i * 4 + 1]; b += rgb[i * 4 + 2]; }
  const k = sorted.length;
  r = Math.min(1, r / k / Math.max(1, paper.r)); g = Math.min(1, g / k / Math.max(1, paper.g)); b = Math.min(1, b / k / Math.max(1, paper.b));
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  const sat = max ? (max - min) / max : 0;
  // Very dark ink reads as black whatever its tint; only clearly colored ink keeps a color.
  if (max < 0.3 || sat < 0.35) return null;
  let hue;
  if (max === r) hue = ((g - b) / (max - min) + 6) % 6; else if (max === g) hue = (b - r) / (max - min) + 2; else hue = (r - g) / (max - min) + 4;
  hue *= 60;
  // Snap to the nearest pen color so one pen gives one color.
  let best = PEN_HUES[0], bd = Infinity;
  for (const c of PEN_HUES) { const d = Math.min(Math.abs(c.hue - hue), 360 - Math.abs(c.hue - hue)); if (d < bd) { bd = d; best = c; } }
  return { ...best.rgb };
}

const hex = (x) => ({ r: parseInt(x.slice(1, 3), 16) / 255, g: parseInt(x.slice(3, 5), 16) / 255, b: parseInt(x.slice(5, 7), 16) / 255 });
// Basis' pen colors, by hue.
const PEN_HUES = [
  { hue: 0, rgb: hex('#D62828') }, { hue: 33, rgb: hex('#F08C00') }, { hue: 145, rgb: hex('#1E8A4C') },
  { hue: 222, rgb: hex('#1F4FD8') }, { hue: 265, rgb: hex('#7B3FE4') }, { hue: 360, rgb: hex('#D62828') },
];

function smooth(pts) {
  if (pts.length < 3) return pts;
  let s = pts;
  for (let pass = 0; pass < 2; pass++) {
    const o = s.map((p) => ({ ...p }));
    for (let i = 1; i < s.length - 1; i++) { o[i].x = (s[i - 1].x + 2 * s[i].x + s[i + 1].x) / 4; o[i].y = (s[i - 1].y + 2 * s[i].y + s[i + 1].y) / 4; }
    s = o;
  }
  return s;
}

// Ramer–Douglas–Peucker.
function simplify(pts, tol) {
  if (pts.length < 3) return pts;
  const keep = new Uint8Array(pts.length);
  keep[0] = keep[pts.length - 1] = 1;
  const st = [[0, pts.length - 1]];
  while (st.length) {
    const [a, b] = st.pop();
    const A = pts[a], B = pts[b], dx = B.x - A.x, dy = B.y - A.y, L = Math.hypot(dx, dy);
    let far = -1, fd = tol;
    for (let i = a + 1; i < b; i++) {
      const d = L > 1e-3 ? Math.abs((pts[i].x - A.x) * dy - (pts[i].y - A.y) * dx) / L : Math.hypot(pts[i].x - A.x, pts[i].y - A.y);
      if (d > fd) { fd = d; far = i; }
    }
    if (far >= 0) { keep[far] = 1; st.push([a, far], [far, b]); }
  }
  return pts.filter((_, i) => keep[i]);
}

function median(a) {
  if (!a.length) return 0;
  const s = a.slice().sort((x, y) => x - y);
  return s[s.length >> 1];
}
