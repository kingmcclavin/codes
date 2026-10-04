// Lightweight static thumbnail of a page: ink and shapes are drawn for real,
// blocks are drawn as quiet placeholders.
import { memo, useMemo } from 'react'
import type { Page } from '../../models'
import { elementBounds, unionBounds } from '../../services/canvas/geometry'
import { ShapeView, StrokeView } from '../Canvas/elements/VectorElements'

export const PagePreview = memo(function PagePreview({ page }: { page: Page }) {
  const content = useMemo(() => {
    const els = page.elements.filter((e) => !(e.type === 'image' && e.background))
    const b = unionBounds(els) ?? { x: 0, y: 0, w: 800, h: 560 }
    const aspect = 1.45
    let w = Math.max(b.w + 80, 600)
    let h = Math.max(b.h + 80, 400)
    if (w / h > aspect) h = w / aspect
    else w = h * aspect
    const vb = `${b.x - 40} ${b.y - 40} ${w} ${h}`
    return { els, vb }
  }, [page.elements])

  return (
    <svg className="page-preview" viewBox={content.vb} preserveAspectRatio="xMinYMin meet">
      {content.els.map((el) => {
        if (el.type === 'stroke') return <StrokeView key={el.id} el={el} />
        if (el.type === 'shape') return <ShapeView key={el.id} el={el} />
        const r = elementBounds(el)
        if (el.type === 'equation' || el.type === 'text') {
          const lines = el.type === 'text' ? Math.min(6, Math.max(1, Math.round(r.h / 28))) : 1
          return (
            <g key={el.id}>
              {Array.from({ length: lines }, (_, i) => (
                <rect key={i} x={r.x} y={r.y + i * 26 + 6} width={Math.min(r.w, 420) * (i === lines - 1 && lines > 1 ? 0.6 : 1)} height={11} rx={5} fill="var(--ink)" opacity={el.type === 'equation' ? 0.32 : 0.16} />
              ))}
            </g>
          )
        }
        const tint = el.type === 'sticky' ? 'var(--accent)' : 'var(--ink)'
        return <rect key={el.id} x={r.x} y={r.y} width={r.w} height={r.h} rx={8} fill={tint} opacity={0.07} stroke="var(--ink)" strokeOpacity={0.12} />
      })}
    </svg>
  )
})
