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
  const strong = 0.38 - sensitivity * 0.32; // 0.06 (faint pencil) … 0.38 (bold pen only)
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

  // Big dark areas (the desk, a shadow, a printed photo) aren't writing:
  // clear them and their edges, without losing writing that touches them.
  let dt = distanceTransform(mask, W, H);
  const blob = new Uint8Array(n);
  let anyBlob = false;
  for (let i = 0; i < n; i++) if (dt[i] > MAX_PEN_RADIUS) { blob[i] = 1; anyBlob = true; }
  if (anyBlob) {
    const zone = dilate(blob, W, H, MAX_PEN_RADIUS + 2);
    for (let i = 0; i < n; i++) if (zone[i]) mask[i] = 0;
  }
  if (removeLines) removeRuledLines(mask, prep);
  if (anyBlob || removeLines) dt = distanceTransform(mask, W, H);

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
 * Takes the notebook's ruled lines out of the ink mask. A ruled line runs
 * across most of the page along the page's slant (cameras often make the
 * lines gray, so this goes by shape first). Only pixels that look like the
 * line itself are removed: pen or pencil on or across a line is kept (it's
 * darker, or not tinted like the line), and a drawn line that's long but
 * doesn't cross the page is left alone.
 */
const FAINT = 0.1; // darkness of the faintest printed line worth looking at

function removeRuledLines(mask, prep) {
  const { W, H } = prep;
  const { dark, rgb, paper } = prep;
  const kill = new Uint8Array(W * H);
  // Pages curl, so where the lines run is found strip by strip.
  const STRIPS = W > 600 ? 4 : 2, sw = Math.ceil(W / STRIPS);
  const strips = [];
  for (let k = 0; k < STRIPS; k++) { const st = findLinesInStrip(prep, k * sw, Math.min(W, (k + 1) * sw)); if (st) strips.push(st); }
  if (!strips.length) return;

  // What the lines look like, over the whole page: how dark, and how blue for that darkness (paper-balanced).
  const tint = (i) => rgb[i * 4 + 2] / paper.b - rgb[i * 4] / paper.r;
  const hd = new Uint32Array(101), hr = new Uint32Array(101);
  for (const st of strips) for (const band of st.bands) for (let x = st.xa; x < st.xb; x += 2) {
    const j = st.core(band, x);
    if (j < 0 || dark[j] <= FAINT) continue;
    hd[Math.round(dark[j] * 100)]++;
    hr[Math.max(0, Math.min(100, Math.round((tint(j) / dark[j]) * 100) + 50))]++;
  }
  const lineDark = histMedian(hd) ?? 0.3, lineRatio = (histMedian(hr) ?? 0.5) - 0.5;
  const tinted = lineRatio > 0.08;

  // Decide along each line in short stretches, against the rest of that same
  // line: a stretch that's a bit darker or less blue was drawn over (kept);
  // deciding by stretch keeps such a line whole instead of breaking it into dashes.
  const R = 10, d = new Float32Array(W), q = new Float32Array(W), has = new Uint8Array(W);
  const hb = new Uint32Array(101), hq = new Uint32Array(101);
  for (const { xa, xb, bands, core, shift } of strips) for (const band of bands) {
    hb.fill(0); hq.fill(0);
    for (let x = xa; x < xb; x++) {
      const j = core(band, x);
      has[x] = j >= 0 && dark[j] > FAINT ? 1 : 0;
      if (!has[x]) continue;
      d[x] = dark[j]; q[x] = tint(j) / dark[j];
      hb[Math.round(d[x] * 100)]++;
      hq[Math.max(0, Math.min(100, Math.round(q[x] * 100) + 50))]++;
    }
    // This line's own look (mostly bare line), kept close to the page's.
    const bandDark = Math.min(histMedian(hb) ?? lineDark, lineDark * 1.2);
    const bandRatio = Math.max((histMedian(hq) ?? 0.5 + lineRatio) - 0.5, lineRatio * 0.85);
    let sd = 0, sq = 0, sn = 0;
    const addAt = (x, k) => { if (x >= xa && x < xb && has[x]) { sd += k * d[x]; sq += k * q[x]; sn += k; } };
    for (let x = xa; x < Math.min(xa + R, xb); x++) addAt(x, 1);
    for (let x = xa; x < xb; x++) {
      addAt(x + R, 1); addAt(x - R - 1, -1);
      if (!sn || !has[x]) continue;
      const md = sd / sn, mq = sq / sn;
      if (md > bandDark + 0.07 || (tinted && mq < bandRatio * 0.8)) continue; // drawn over
      for (let r = band.r0 - 1; r <= band.r1 + 1; r++) {
        const y = r + shift[x], i = y * W + x;
        if (y > 0 && y < H - 1 && mask[i] && dark[i] < lineDark * 1.5 + 0.04) kill[i] = 1;
      }
    }
  }

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

/** Where the ruled lines run across one vertical strip of the page. */
function findLinesInStrip(prep, xa, xb) {
  const { W, H, dark } = prep, SW = xb - xa;
  const faint = [];
  for (let y = 1; y < H - 1; y++) for (let x = xa; x < xb; x++) if (dark[y * W + x] > FAINT) faint.push(y * W + x);
  if (!faint.length) return null;
  const stride = Math.max(1, Math.floor(faint.length / 80000));

  // The lines' slant here: the slope at which marks pile up into the sharpest rows.
  const off = Math.ceil(SW * 0.2) + 2, hist = new Float32Array(H + 2 * off);
  const score = (t) => {
    hist.fill(0);
    for (let k = 0; k < faint.length; k += stride) { const i = faint[k], x = (i % W) - xa, y = (i / W) | 0; hist[Math.round(y - x * t) + off]++; }
    let sq = 0;
    for (const v of hist) sq += v * v;
    return sq;
  };
  let best = 0, bestScore = -1;
  for (let t = -0.18; t <= 0.18001; t += 0.01) { const v = score(t); if (v > bestScore) { bestScore = v; best = t; } }
  const coarse = best;
  for (let t = coarse - 0.01; t <= coarse + 0.01; t += 0.002) { const v = score(t); if (v > bestScore) { bestScore = v; best = t; } }
  const shift = new Int32Array(W);
  for (let x = xa; x < xb; x++) shift[x] = Math.round((x - xa) * best);
  const lo = Math.min(0, shift[xb - 1]), hi = Math.max(0, shift[xb - 1]);

  // Ruled rows: a faint line along the slant across most of the strip, darker
  // than the rows around it (a line, not a shaded band). Read from the photo
  // itself: faint lines are only partly in the ink mask.
  const seen = (x, y) => y > 0 && y < H - 1 && (dark[y * W + x] > FAINT || dark[(y - 1) * W + x] > FAINT || dark[(y + 1) * W + x] > FAINT);
  const cover = [];
  for (let r = 1 - hi; r < H - 1 - lo; r++) {
    let c = 0;
    for (let x = xa; x < xb; x++) if (seen(x, r + shift[x])) c++;
    cover.push([r, c]);
  }
  const rows = [];
  for (let k = 0; k < cover.length; k++) {
    const [r, c] = cover[k];
    if (c < SW * 0.5) continue;
    const around = Math.min(cover[Math.max(0, k - 6)][1], cover[Math.min(cover.length - 1, k + 6)][1]);
    if (c > around * 1.3) rows.push(r);
  }
  if (!rows.length) return null;

  // One band per line.
  const bands = [];
  for (const r of rows) {
    const last = bands[bands.length - 1];
    if (last && r - last.r1 <= 1) last.r1 = r; else bands.push({ r0: r, r1: r });
  }
  // The darkest pixel across a band at column x (the line's core there).
  const core = (band, x) => {
    let j = -1;
    for (let r = band.r0 - 1; r <= band.r1 + 1; r++) {
      const y = r + shift[x];
      if (y <= 0 || y >= H - 1) continue;
      const i = y * W + x;
      if (j < 0 || dark[i] > dark[j]) j = i;
    }
    return j;
  };

  // Ruled lines repeat at an even spacing: keep bands with a neighbor at that
  // spacing, which drops an underline or a drawn line that crosses the strip.
  if (bands.length < 3) return null;
  const mid = (b) => (b.r0 + b.r1) / 2;
  const gaps = bands.slice(1).map((b, k) => mid(b) - mid(bands[k])).sort((a, b) => a - b);
  const pitch = gaps[gaps.length >> 1];
  const fits = (g) => Math.abs(g - pitch) <= pitch * 0.2 || Math.abs(g - 2 * pitch) <= pitch * 0.3;
  const ruled = bands.filter((b, k) => (k > 0 && fits(mid(b) - mid(bands[k - 1]))) || (k < bands.length - 1 && fits(mid(bands[k + 1]) - mid(b))));
  if (ruled.length < 3) return null;
  // Fill in lines the spacing predicts but that didn't stand out (next to
  // dense writing): look for each near its expected row.
  const coverAt = (r) => { const k = r - (1 - hi); return k >= 0 && k < cover.length ? cover[k][1] : 0; };
  const all = [...ruled];
  for (let k = 0; k + 1 < ruled.length; k++) {
    const a = mid(ruled[k]), b = mid(ruled[k + 1]), n = Math.round((b - a) / pitch);
    for (let m = 1; m < n; m++) {
      const p = Math.round(a + ((b - a) * m) / n);
      let bestR = -1, bestC = SW * 0.3;
      for (let r = p - 2; r <= p + 2; r++) if (coverAt(r) > bestC) { bestC = coverAt(r); bestR = r; }
      if (bestR >= 0) all.push({ r0: bestR, r1: bestR });
    }
  }
  for (const dir of [-1, 1]) {
    let p = mid(dir < 0 ? ruled[0] : ruled[ruled.length - 1]) + dir * pitch;
    while (p > 1 - hi && p < H - 1 - lo) {
      let bestR = -1, bestC = SW * 0.3;
      for (let r = Math.round(p) - 2; r <= Math.round(p) + 2; r++) if (coverAt(r) > bestC) { bestC = coverAt(r); bestR = r; }
      if (bestR < 0) break;
      all.push({ r0: bestR, r1: bestR });
      p = bestR + dir * pitch;
    }
  }
  all.sort((a, b) => a.r0 - b.r0);
  return { xa, xb, bands: all, core, shift };
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
