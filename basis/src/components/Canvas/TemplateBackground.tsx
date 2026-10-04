// Screen-space paper: an infinite template that follows pan & zoom.
import { memo } from 'react'
import type { TemplateKind, TemplateOptions, Viewport } from '../../models'
import { CORNELL } from '../../models/templates'

const mod = (a: number, n: number) => ((a % n) + n) % n

export const TemplateBackground = memo(function TemplateBackground({
  vp,
  template,
  opts,
  width,
  height,
}: {
  vp: Viewport
  template: TemplateKind
  opts: TemplateOptions
  width: number
  height: number
}) {
  const lw = opts.lineWidth
  const show = opts.visible && template !== 'blank'
  const z = vp.zoom

  let content: React.ReactNode = null
  let defs: React.ReactNode = null

  if (show && template === 'isometric') {
    let a = opts.spacing * z
    while (a < 10) a *= 2
    const W = a * Math.sqrt(3)
    const H = a
    const ox = mod(vp.x, W)
    const oy = mod(vp.y, H)
    defs = (
      <pattern id="tpl-iso" width={W} height={H} patternUnits="userSpaceOnUse" x={ox} y={oy}>
        <path
          d={`M0 ${-H}L${W} 0M0 0L${W} ${H}M0 ${H}L${W} ${2 * H}M0 ${H}L${W} 0M0 ${2 * H}L${W} ${H}M0 0L${W} ${-H}M0 0V${H}M${W / 2} 0V${H}`}
          stroke="var(--grid)"
          strokeWidth={lw}
          fill="none"
        />
      </pattern>
    )
    content = <rect width="100%" height="100%" fill="url(#tpl-iso)" />
  } else if (show && (opts.style === 'dots' || template === 'dot')) {
    let s = opts.spacing * z
    while (s < 10) s *= 2
    const ox = mod(vp.x - s / 2, s)
    const oy = mod(vp.y - s / 2, s)
    const r = Math.max(0.8, Math.min(1.6, 1.1 * Math.sqrt(z))) * lw
    defs = (
      <pattern id="tpl-dot" width={s} height={s} patternUnits="userSpaceOnUse" x={ox} y={oy}>
        <circle cx={s / 2} cy={s / 2} r={r} fill="var(--grid-major)" />
      </pattern>
    )
    content = <rect width="100%" height="100%" fill="url(#tpl-dot)" />
  } else if (show && template === 'cornell') {
    let s = opts.spacing * z
    while (s < 8) s *= 2
    const oy = mod(vp.y, s)
    const cueX = vp.x + CORNELL.cueWidth * z
    const headY = vp.y + CORNELL.headerHeight * z
    const sumY = vp.y + (CORNELL.pageHeight - CORNELL.summaryHeight) * z
    const labelSize = Math.max(8, 10 * z)
    defs = (
      <pattern id="tpl-rule" width={8} height={s} patternUnits="userSpaceOnUse" x={0} y={oy}>
        <rect width={8} height={lw} fill="var(--grid)" />
      </pattern>
    )
    content = (
      <>
        <rect width="100%" height="100%" fill="url(#tpl-rule)" />
        <line x1={cueX} x2={cueX} y1={headY} y2={sumY} stroke="var(--grid-axis)" strokeWidth={1.25} />
        <line x1={0} x2={width} y1={headY} y2={headY} stroke="var(--grid-major)" strokeWidth={1.25} />
        <line x1={0} x2={width} y1={sumY} y2={sumY} stroke="var(--grid-major)" strokeWidth={1.25} />
        <g fontFamily="var(--font-mono)" fontSize={labelSize} letterSpacing="0.14em" fill="var(--text-3)" opacity={0.75}>
          <text x={vp.x + 16 * z} y={headY + 22 * z}>CUES</text>
          <text x={cueX + 16 * z} y={headY + 22 * z}>NOTES</text>
          <text x={vp.x + 16 * z} y={sumY + 22 * z}>SUMMARY</text>
        </g>
      </>
    )
  } else if (show) {
    // Square grids: engineering, graph, custom
    let s = opts.spacing * z
    let k = Math.max(0, opts.majorEvery)
    while (s < 7) {
      s *= k > 1 ? k : 2
    }
    const S = k > 1 ? s * k : 0
    const ox = mod(vp.x, s)
    const oy = mod(vp.y, s)
    defs = (
      <>
        <pattern id="tpl-minor" width={s} height={s} patternUnits="userSpaceOnUse" x={ox} y={oy}>
          <rect width={lw} height={s} fill="var(--grid)" />
          <rect width={s} height={lw} fill="var(--grid)" />
        </pattern>
        {S > 0 && (
          <pattern id="tpl-major" width={S} height={S} patternUnits="userSpaceOnUse" x={mod(vp.x, S)} y={mod(vp.y, S)}>
            <rect width={lw} height={S} fill="var(--grid-major)" />
            <rect width={S} height={lw} fill="var(--grid-major)" />
          </pattern>
        )}
      </>
    )
    content = (
      <>
        <rect width="100%" height="100%" fill="url(#tpl-minor)" />
        {S > 0 && <rect width="100%" height="100%" fill="url(#tpl-major)" />}
        {template === 'graph' && (
          <>
            <line x1={0} x2={width} y1={vp.y} y2={vp.y} stroke="var(--grid-axis)" strokeWidth={1.4} />
            <line x1={vp.x} x2={vp.x} y1={0} y2={height} stroke="var(--grid-axis)" strokeWidth={1.4} />
          </>
        )}
      </>
    )
  }

  return (
    <svg className="tpl-bg" width={width} height={height} aria-hidden="true">
      <defs>{defs}</defs>
      {content}
    </svg>
  )
})

/** Choose readable ink + grid colours for a custom page colour. */
export function pageColorVars(color: string | null): React.CSSProperties | undefined {
  if (!color) return undefined
  const hex = color.replace('#', '')
  const n = parseInt(hex.length === 3 ? hex.replace(/./g, '$&$&') : hex, 16)
  const r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255
  const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
  const dark = lum < 0.5
  return {
    ['--paper' as string]: color,
    ['--ink' as string]: dark ? '#eef0f2' : '#1b1d22',
    ['--grid' as string]: dark ? 'rgba(255,255,255,0.07)' : 'rgba(48,92,150,0.11)',
    ['--grid-major' as string]: dark ? 'rgba(255,255,255,0.14)' : 'rgba(48,92,150,0.22)',
  }
}

export const PAGE_COLORS: { name: string; value: string | null }[] = [
  { name: 'Theme paper', value: null },
  { name: 'Cream', value: '#f7f2e4' },
  { name: 'White', value: '#ffffff' },
  { name: 'Charcoal', value: '#17191c' },
  { name: 'Blueprint', value: '#123058' },
  { name: 'Slate green', value: '#1d3029' },
]
