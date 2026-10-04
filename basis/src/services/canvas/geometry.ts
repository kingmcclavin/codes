// Pure geometry for the canvas: bounds, hit-testing, translation.

import type { CanvasElement, StrokeElement } from '../../models'

export interface Rect {
  x: number
  y: number
  w: number
  h: number
}

/** Rendered size of HTML blocks, measured by ResizeObserver (world units). */
export const blockSizes = new Map<string, { w: number; h: number }>()

export function elementBounds(el: CanvasElement): Rect {
  switch (el.type) {
    case 'stroke': {
      let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
      for (const [x, y] of el.points) {
        if (x < minX) minX = x
        if (y < minY) minY = y
        if (x > maxX) maxX = x
        if (y > maxY) maxY = y
      }
      const pad = el.width / 2
      return { x: minX - pad, y: minY - pad, w: maxX - minX + pad * 2, h: maxY - minY + pad * 2 }
    }
    case 'shape': {
      const x = Math.min(el.x, el.x2), y = Math.min(el.y, el.y2)
      const pad = el.width / 2 + (el.shape === 'arrow' ? 8 : 0)
      return { x: x - pad, y: y - pad, w: Math.abs(el.x2 - el.x) + pad * 2, h: Math.abs(el.y2 - el.y) + pad * 2 }
    }
    default: {
      const m = blockSizes.get(el.id)
      const w = m?.w ?? ('w' in el ? el.w : 160)
      const h = m?.h ?? ('h' in el ? (el as { h: number }).h : 48)
      return { x: el.x, y: el.y, w, h }
    }
  }
}

export function unionBounds(els: CanvasElement[]): Rect | null {
  if (!els.length) return null
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (const el of els) {
    const b = elementBounds(el)
    minX = Math.min(minX, b.x)
    minY = Math.min(minY, b.y)
    maxX = Math.max(maxX, b.x + b.w)
    maxY = Math.max(maxY, b.y + b.h)
  }
  return { x: minX, y: minY, w: maxX - minX, h: maxY - minY }
}

export const rectsIntersect = (a: Rect, b: Rect) =>
  a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y

export const rectContains = (outer: Rect, inner: Rect) =>
  inner.x >= outer.x && inner.y >= outer.y && inner.x + inner.w <= outer.x + outer.w && inner.y + inner.h <= outer.y + outer.h

export function distToSegment(px: number, py: number, ax: number, ay: number, bx: number, by: number) {
  const dx = bx - ax, dy = by - ay
  const l2 = dx * dx + dy * dy
  let t = l2 ? ((px - ax) * dx + (py - ay) * dy) / l2 : 0
  t = Math.max(0, Math.min(1, t))
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy))
}

function strokeHit(el: StrokeElement, x: number, y: number, tol: number) {
  const r = el.width / 2 + tol
  const pts = el.points
  if (pts.length === 1) return Math.hypot(pts[0][0] - x, pts[0][1] - y) <= r
  for (let i = 1; i < pts.length; i++) {
    if (distToSegment(x, y, pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1]) <= r) return true
  }
  return false
}

/** Precise hit test at a world point. `tol` is in world units. */
export function hitTest(el: CanvasElement, x: number, y: number, tol: number): boolean {
  const b = elementBounds(el)
  if (x < b.x - tol || x > b.x + b.w + tol || y < b.y - tol || y > b.y + b.h + tol) return false
  if (el.type === 'stroke') return strokeHit(el, x, y, tol)
  if (el.type === 'shape') {
    const r = el.width / 2 + tol
    const x1 = Math.min(el.x, el.x2), x2 = Math.max(el.x, el.x2)
    const y1 = Math.min(el.y, el.y2), y2 = Math.max(el.y, el.y2)
    switch (el.shape) {
      case 'line':
      case 'arrow':
        return distToSegment(x, y, el.x, el.y, el.x2, el.y2) <= r
      case 'rect':
        if (el.fill) return true
        return (
          distToSegment(x, y, x1, y1, x2, y1) <= r ||
          distToSegment(x, y, x2, y1, x2, y2) <= r ||
          distToSegment(x, y, x2, y2, x1, y2) <= r ||
          distToSegment(x, y, x1, y2, x1, y1) <= r
        )
      case 'ellipse': {
        const cx = (x1 + x2) / 2, cy = (y1 + y2) / 2
        const rx = Math.max(1, (x2 - x1) / 2), ry = Math.max(1, (y2 - y1) / 2)
        const d = Math.hypot((x - cx) / rx, (y - cy) / ry)
        if (el.fill) return d <= 1 + r / Math.min(rx, ry)
        return Math.abs(d - 1) * Math.min(rx, ry) <= r
      }
      default:
        return true
    }
  }
  return true
}

/** Topmost element under a point. Blocks are checked against their measured box. */
export function topElementAt(els: CanvasElement[], x: number, y: number, tol: number): CanvasElement | null {
  for (let i = els.length - 1; i >= 0; i--) {
    const el = els[i]
    if (el.type === 'image' && el.background) continue
    if (hitTest(el, x, y, tol)) return el
  }
  return null
}

export function translateElement<T extends CanvasElement>(el: T, dx: number, dy: number): T {
  if (el.type === 'stroke') {
    return { ...el, x: el.x + dx, y: el.y + dy, points: el.points.map(([x, y, p]) => [x + dx, y + dy, p]) } as T
  }
  if (el.type === 'shape') return { ...el, x: el.x + dx, y: el.y + dy, x2: el.x2 + dx, y2: el.y2 + dy } as T
  return { ...el, x: el.x + dx, y: el.y + dy }
}

/** Simplify a polyline (Ramer–Douglas–Peucker) to keep stored strokes small. */
export function simplify(points: [number, number, number][], epsilon = 0.35): [number, number, number][] {
  if (points.length < 3) return points
  const keep = new Uint8Array(points.length)
  keep[0] = keep[points.length - 1] = 1
  const stack: [number, number][] = [[0, points.length - 1]]
  while (stack.length) {
    const [s, e] = stack.pop()!
    let maxD = 0, idx = -1
    for (let i = s + 1; i < e; i++) {
      const d = distToSegment(points[i][0], points[i][1], points[s][0], points[s][1], points[e][0], points[e][1])
      if (d > maxD) {
        maxD = d
        idx = i
      }
    }
    if (maxD > epsilon && idx > 0) {
      keep[idx] = 1
      stack.push([s, idx], [idx, e])
    }
  }
  return points.filter((_, i) => keep[i])
}

export const round2 = (n: number) => Math.round(n * 100) / 100
