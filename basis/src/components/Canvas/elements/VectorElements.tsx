// SVG renderers for vector ink (strokes) and geometric shapes.
import { memo } from 'react'
import type { ShapeElement, StrokeElement } from '../../../models'
import { resolveColor, strokePath } from '../../../services/canvas/ink'

export const StrokeView = memo(function StrokeView({ el }: { el: StrokeElement }) {
  const color = resolveColor(el.color)
  if (el.tool === 'highlighter') {
    return (
      <path
        d={strokePath(el)}
        fill="none"
        stroke={color}
        strokeWidth={el.width}
        strokeOpacity={el.opacity}
        strokeLinecap="round"
        strokeLinejoin="round"
        className="hl-stroke"
      />
    )
  }
  return <path d={strokePath(el)} fill={color} fillOpacity={el.opacity} />
})

export function shapeGeometry(el: ShapeElement): { d: string; head?: string } {
  const { x, y, x2, y2 } = el
  const l = Math.min(x, x2), t = Math.min(y, y2), r = Math.max(x, x2), b = Math.max(y, y2)
  switch (el.shape) {
    case 'rect':
      return { d: `M${l} ${t}H${r}V${b}H${l}Z` }
    case 'ellipse': {
      const cx = (l + r) / 2, cy = (t + b) / 2, rx = (r - l) / 2, ry = (b - t) / 2
      return { d: `M${cx - rx} ${cy}a${rx} ${ry} 0 1 0 ${rx * 2} 0a${rx} ${ry} 0 1 0 ${-rx * 2} 0Z` }
    }
    case 'triangle':
      return { d: `M${(l + r) / 2} ${t}L${r} ${b}L${l} ${b}Z` }
    case 'diamond':
      return { d: `M${(l + r) / 2} ${t}L${r} ${(t + b) / 2}L${(l + r) / 2} ${b}L${l} ${(t + b) / 2}Z` }
    case 'line':
      return { d: `M${x} ${y}L${x2} ${y2}` }
    case 'arrow': {
      const ang = Math.atan2(y2 - y, x2 - x)
      const len = Math.hypot(x2 - x, y2 - y)
      const size = Math.min(len * 0.45, 9 + el.width * 2.4)
      const a1 = ang + Math.PI - 0.42, a2 = ang + Math.PI + 0.42
      const head = `M${x2 + Math.cos(a1) * size} ${y2 + Math.sin(a1) * size}L${x2} ${y2}L${x2 + Math.cos(a2) * size} ${y2 + Math.sin(a2) * size}`
      return { d: `M${x} ${y}L${x2} ${y2}`, head }
    }
  }
}

export const ShapeView = memo(function ShapeView({ el }: { el: ShapeElement }) {
  const color = resolveColor(el.color)
  const { d, head } = shapeGeometry(el)
  const closed = !['line', 'arrow'].includes(el.shape)
  return (
    <g opacity={el.opacity}>
      <path
        d={d}
        fill={closed && el.fill ? color : 'none'}
        fillOpacity={closed && el.fill ? 0.14 : undefined}
        stroke={color}
        strokeWidth={el.width}
        strokeDasharray={el.dashed ? `${el.width * 3.5} ${el.width * 2.5}` : undefined}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {head && <path d={head} fill="none" stroke={color} strokeWidth={el.width} strokeLinecap="round" strokeLinejoin="round" />}
    </g>
  )
})
