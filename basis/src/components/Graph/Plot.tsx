import { memo, useMemo } from 'react'
import type { GraphFunction, GraphSeries } from '../../models'
import { sampleFunction, tickLabel, ticks, type View } from '../../services/calculations/graph'

const PAD = { l: 38, r: 10, t: 10, b: 24 }

export const Plot = memo(function Plot({
  w,
  h,
  view,
  functions,
  series = [],
  scope,
  xLabel,
  yLabel,
}: {
  w: number
  h: number
  view: View
  functions: GraphFunction[]
  series?: GraphSeries[]
  scope: Record<string, number>
  xLabel?: string
  yLabel?: string
}) {
  const iw = Math.max(10, w - PAD.l - PAD.r)
  const ih = Math.max(10, h - PAD.t - PAD.b)
  const sx = (x: number) => PAD.l + ((x - view.xmin) / (view.xmax - view.xmin)) * iw
  const sy = (y: number) => PAD.t + (1 - (y - view.ymin) / (view.ymax - view.ymin)) * ih

  const xt = useMemo(() => ticks(view.xmin, view.xmax, Math.max(3, Math.round(iw / 60))), [view.xmin, view.xmax, iw])
  const yt = useMemo(() => ticks(view.ymin, view.ymax, Math.max(3, Math.round(ih / 40))), [view.ymin, view.ymax, ih])

  const curves = useMemo(
    () =>
      functions.map((f) => {
        const { segments, error } = sampleFunction(f.expr, view, Math.min(900, Math.round(iw * 1.5)), scope)
        const d = segments
          .map((seg) => seg.map(([x, y], i) => `${i ? 'L' : 'M'}${sx(x).toFixed(1)} ${sy(Math.max(view.ymin - (view.ymax - view.ymin) * 3, Math.min(view.ymax + (view.ymax - view.ymin) * 3, y))).toFixed(1)}`).join(''))
          .join('')
        return { id: f.id, color: f.color, d, error }
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [functions, view, iw, ih, scope],
  )

  const x0 = sx(0)
  const y0 = sy(0)
  const clipId = useMemo(() => 'clip' + Math.random().toString(36).slice(2, 8), [])

  return (
    <svg className="plot" width={w} height={h}>
      <defs>
        <clipPath id={clipId}>
          <rect x={PAD.l} y={PAD.t} width={iw} height={ih} />
        </clipPath>
      </defs>
      <rect x={PAD.l} y={PAD.t} width={iw} height={ih} className="plot-bg" />
      <g className="plot-grid">
        {xt.map((t) => (
          <line key={'x' + t} x1={sx(t)} x2={sx(t)} y1={PAD.t} y2={PAD.t + ih} />
        ))}
        {yt.map((t) => (
          <line key={'y' + t} x1={PAD.l} x2={PAD.l + iw} y1={sy(t)} y2={sy(t)} />
        ))}
      </g>
      <g className="plot-axes">
        {x0 >= PAD.l && x0 <= PAD.l + iw && <line x1={x0} x2={x0} y1={PAD.t} y2={PAD.t + ih} />}
        {y0 >= PAD.t && y0 <= PAD.t + ih && <line x1={PAD.l} x2={PAD.l + iw} y1={y0} y2={y0} />}
      </g>
      <g className="plot-labels">
        {xt.map((t) => (
          <text key={'xl' + t} x={sx(t)} y={PAD.t + ih + 15} textAnchor="middle">
            {tickLabel(t)}
          </text>
        ))}
        {yt.map((t) => (
          <text key={'yl' + t} x={PAD.l - 6} y={sy(t) + 3.5} textAnchor="end">
            {tickLabel(t)}
          </text>
        ))}
        {xLabel && (
          <text x={PAD.l + iw - 4} y={PAD.t + ih - 6} textAnchor="end" className="axis-name">
            {xLabel}
          </text>
        )}
        {yLabel && (
          <text x={PAD.l + 6} y={PAD.t + 13} className="axis-name">
            {yLabel}
          </text>
        )}
      </g>
      <g clipPath={`url(#${clipId})`}>
        {curves.map((c) => (
          <path key={c.id} d={c.d} fill="none" stroke={c.color} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
        ))}
        {series.map((s) => (
          <g key={s.id}>
            <path d={s.points.map(([x, y], i) => `${i ? 'L' : 'M'}${sx(x)} ${sy(y)}`).join('')} fill="none" stroke={s.color} strokeWidth={1.4} strokeOpacity={0.6} />
            {s.points.map(([x, y], i) => (
              <circle key={i} cx={sx(x)} cy={sy(y)} r={3} fill="var(--surface)" stroke={s.color} strokeWidth={1.6} />
            ))}
          </g>
        ))}
      </g>
      <rect x={PAD.l} y={PAD.t} width={iw} height={ih} className="plot-frame" />
    </svg>
  )
})

export const PLOT_PAD = PAD
