// Turning raw pointer samples into beautiful vector ink.

import { getStroke } from 'perfect-freehand'
import { INK, type StrokeElement } from '../../models'

const cache = new WeakMap<StrokeElement, string>()

export function outlineToPath(outline: number[][]): string {
  if (!outline.length) return ''
  const d: (string | number)[] = ['M', outline[0][0].toFixed(2), outline[0][1].toFixed(2), 'Q']
  for (let i = 0; i < outline.length; i++) {
    const [x0, y0] = outline[i]
    const [x1, y1] = outline[(i + 1) % outline.length]
    d.push(x0.toFixed(2), y0.toFixed(2), ((x0 + x1) / 2).toFixed(2), ((y0 + y1) / 2).toFixed(2))
  }
  d.push('Z')
  return d.join(' ')
}

export function polylinePath(points: [number, number, number][]): string {
  if (!points.length) return ''
  if (points.length === 1) return `M${points[0][0]} ${points[0][1]} l0.01 0`
  let d = `M${points[0][0].toFixed(2)} ${points[0][1].toFixed(2)}`
  for (let i = 1; i < points.length - 1; i++) {
    const [x0, y0] = points[i]
    const [x1, y1] = points[i + 1]
    d += ` Q${x0.toFixed(2)} ${y0.toFixed(2)} ${((x0 + x1) / 2).toFixed(2)} ${((y0 + y1) / 2).toFixed(2)}`
  }
  const last = points[points.length - 1]
  d += ` L${last[0].toFixed(2)} ${last[1].toFixed(2)}`
  return d
}

export function penOutline(points: [number, number, number][], width: number, simulatePressure: boolean, last = true) {
  return getStroke(points, {
    size: width * 1.6,
    thinning: simulatePressure ? 0.45 : 0.6,
    smoothing: 0.55,
    streamline: 0.4,
    simulatePressure,
    last,
    start: { taper: 0, cap: true },
    end: { taper: 0, cap: true },
  })
}

/** SVG path for a committed stroke (cached per element object). */
export function strokePath(el: StrokeElement): string {
  const hit = cache.get(el)
  if (hit) return hit
  let d: string
  if (el.tool === 'highlighter') d = polylinePath(el.points)
  else {
    const hasPressure = el.points.some((p) => p[2] !== 0.5)
    d = outlineToPath(penOutline(el.points, el.width, !hasPressure))
  }
  cache.set(el, d)
  return d
}

export const resolveColor = (c: string) => (c === INK ? 'var(--ink)' : c)

export const INK_COLORS = [INK, '#2563eb', '#dc2626', '#16a34a', '#ea580c', '#7c3aed', '#0891b2', '#6b7280']
export const HIGHLIGHT_COLORS = ['#facc15', '#4ade80', '#38bdf8', '#f472b6', '#fb923c', '#a78bfa']
