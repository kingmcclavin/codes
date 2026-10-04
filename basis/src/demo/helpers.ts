// Small builders for authoring demo pages in code.
import {
  INK,
  type CalcElement,
  type EquationElement,
  type GraphElement,
  type ShapeElement,
  type ShapeKind,
  type StickyElement,
  type StrokeElement,
  type TableElement,
  type TextElement,
} from '../models'
import { uid } from '../services/id'

type Pt = [number, number]
const ACCENT = '#ff6b2c'
export const BLUE = '#3b82f6'
export const RED = '#ef4444'
export const GREEN = '#16a34a'
export const ORANGE = ACCENT
export const PURPLE = '#8b5cf6'

const jitter = (seed: number) => {
  let s = seed
  return () => {
    s = (s * 9301 + 49297) % 233280
    return s / 233280 - 0.5
  }
}

export function stroke(points: Pt[], o: { color?: string; width?: number; opacity?: number; highlighter?: boolean; seed?: number } = {}): StrokeElement {
  const rnd = jitter(o.seed ?? points.length * 7 + Math.round(points[0][0]))
  const pts = points.map(([x, y]) => [Math.round((x + rnd() * 0.6) * 100) / 100, Math.round((y + rnd() * 0.6) * 100) / 100, 0.5] as [number, number, number])
  return {
    id: uid('e'),
    type: 'stroke',
    tool: o.highlighter ? 'highlighter' : 'pen',
    points: pts,
    color: o.color ?? (o.highlighter ? '#facc15' : INK),
    width: o.width ?? (o.highlighter ? 20 : 2.2),
    opacity: o.opacity ?? (o.highlighter ? 0.35 : 1),
    x: pts[0][0],
    y: pts[0][1],
  }
}

export function bezier(p0: Pt, c: Pt, p1: Pt, n = 24): Pt[] {
  const out: Pt[] = []
  for (let i = 0; i <= n; i++) {
    const t = i / n
    out.push([(1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]])
  }
  return out
}

/** Hand-drawn underline with a gentle wave. */
export const underline = (x: number, y: number, w: number, color = ORANGE, width = 2.4) => stroke(bezier([x, y], [x + w / 2, y + 4], [x + w, y - 1.5], 30), { color, width })

/** Highlighter swipe. */
export const highlight = (x: number, y: number, w: number, color = '#facc15', h = 22) =>
  stroke(bezier([x, y], [x + w / 2, y - 1.5], [x + w, y + 1], 20), { highlighter: true, color, width: h })

/** Hand-drawn ellipse that slightly overshoots, like circling an answer. */
export function ring(cx: number, cy: number, rx: number, ry: number, color = ORANGE, width = 2.2): StrokeElement {
  const pts: Pt[] = []
  const turns = 1.08
  const n = 64
  for (let i = 0; i <= n; i++) {
    const a = -2.2 + (i / n) * Math.PI * 2 * turns
    const wob = 1 + Math.sin(i * 0.35) * 0.025
    pts.push([cx + Math.cos(a) * rx * wob, cy + Math.sin(a) * ry * wob])
  }
  return stroke(pts, { color, width })
}

export function circlePts(cx: number, cy: number, r: number, n = 48): Pt[] {
  return Array.from({ length: n + 1 }, (_, i) => [cx + Math.cos((i / n) * Math.PI * 2) * r, cy + Math.sin((i / n) * Math.PI * 2) * r] as Pt)
}

/** Curved hand-drawn arrow (stroke shaft + head). */
export function handArrow(from: Pt, to: Pt, bend = 0.2, color = ORANGE, width = 2.2): StrokeElement[] {
  const mx = (from[0] + to[0]) / 2, my = (from[1] + to[1]) / 2
  const dx = to[0] - from[0], dy = to[1] - from[1]
  const c: Pt = [mx - dy * bend, my + dx * bend]
  const shaft = bezier(from, c, to, 28)
  const ang = Math.atan2(to[1] - c[1], to[0] - c[0])
  const s = 11
  const head: Pt[] = [
    [to[0] + Math.cos(ang + Math.PI - 0.45) * s, to[1] + Math.sin(ang + Math.PI - 0.45) * s],
    to,
    [to[0] + Math.cos(ang + Math.PI + 0.45) * s, to[1] + Math.sin(ang + Math.PI + 0.45) * s],
  ]
  return [stroke(shaft, { color, width }), stroke(head, { color, width })]
}

export function shape(kind: ShapeKind, x: number, y: number, x2: number, y2: number, o: Partial<ShapeElement> = {}): ShapeElement {
  return { id: uid('e'), type: 'shape', shape: kind, x, y, x2, y2, color: INK, width: 2, opacity: 1, fill: false, dashed: false, ...o }
}

export const text = (x: number, y: number, t: string, o: Partial<TextElement> = {}): TextElement => ({
  id: uid('e'),
  type: 'text',
  x,
  y,
  w: 420,
  text: t,
  fontSize: 17,
  color: INK,
  font: 'sans',
  ...o,
})

export const title = (x: number, y: number, t: string, sub?: string): TextElement[] => [
  text(x, y, t, { fontSize: 34, weight: 'bold', w: 760 }),
  ...(sub ? [text(x + 2, y + 50, sub, { fontSize: 13, font: 'mono', color: '#8b8f97', w: 760 })] : []),
]

export const eq = (x: number, y: number, source: string, fontSize = 22, color = INK): EquationElement => ({ id: uid('e'), type: 'equation', x, y, source, fontSize, color })

export const calc = (x: number, y: number, source: string, title?: string, w = 340): CalcElement => ({ id: uid('e'), type: 'calc', x, y, w, source, title })

export const sticky = (x: number, y: number, t: string, body: string, color: StickyElement['color'] = 'amber', w = 250): StickyElement => ({ id: uid('e'), type: 'sticky', x, y, w, title: t, text: body, color })

export const table = (x: number, y: number, columns: string[], rows: string[][], title?: string): TableElement => ({ id: uid('e'), type: 'table', x, y, columns, rows, title })

export const graph = (x: number, y: number, w: number, h: number, fns: [string, string][], view: GraphElement['view'], o: Partial<GraphElement> = {}): GraphElement => ({
  id: uid('e'),
  type: 'graph',
  x,
  y,
  w,
  h,
  functions: fns.map(([expr, color]) => ({ id: uid('fn'), expr, color })),
  view,
  ...o,
})

/** Point charge glyph: circle with a + or − sign. */
export function charge(cx: number, cy: number, sign: '+' | '-', r = 18, color = sign === '+' ? RED : BLUE) {
  const out = [shape('ellipse', cx - r, cy - r, cx + r, cy + r, { color, width: 2.2, fill: true })]
  out.push(shape('line', cx - r * 0.45, cy, cx + r * 0.45, cy, { color, width: 2.4 }))
  if (sign === '+') out.push(shape('line', cx, cy - r * 0.45, cx, cy + r * 0.45, { color, width: 2.4 }))
  return out
}

/** Resistor zig-zag between two points (horizontal). */
export function resistorH(x: number, y: number, len = 80, color = INK): StrokeElement {
  const pts: Pt[] = [[x, y], [x + len * 0.2, y]]
  const n = 6
  const seg = (len * 0.6) / n
  for (let i = 0; i < n; i++) pts.push([x + len * 0.2 + seg * (i + 0.5), y + (i % 2 ? 9 : -9)])
  pts.push([x + len * 0.8, y], [x + len, y])
  return stroke(pts, { color, width: 2.2 })
}

export function resistorV(x: number, y: number, len = 80, color = INK): StrokeElement {
  const pts: Pt[] = [[x, y], [x, y + len * 0.2]]
  const n = 6
  const seg = (len * 0.6) / n
  for (let i = 0; i < n; i++) pts.push([x + (i % 2 ? 9 : -9), y + len * 0.2 + seg * (i + 0.5)])
  pts.push([x, y + len * 0.8], [x, y + len])
  return stroke(pts, { color, width: 2.2 })
}

export const lerpColor = (a: string, b: string, t: number) => {
  const pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16)
  const r = Math.round(((pa >> 16) & 255) + ((((pb >> 16) & 255) - ((pa >> 16) & 255)) * t))
  const g = Math.round(((pa >> 8) & 255) + ((((pb >> 8) & 255) - ((pa >> 8) & 255)) * t))
  const bl = Math.round((pa & 255) + (((pb & 255) - (pa & 255)) * t))
  return `#${((1 << 24) + (r << 16) + (g << 8) + bl).toString(16).slice(1)}`
}
