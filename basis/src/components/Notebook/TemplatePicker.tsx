import type { Page, TemplateKind } from '../../models'
import { TEMPLATES, templateInfo } from '../../models/templates'
import { useLibrary } from '../../store/library'
import { PAGE_COLORS } from '../Canvas/TemplateBackground'

function Thumb({ kind }: { kind: TemplateKind }) {
  const s = 'var(--grid-major)'
  const content: Record<TemplateKind, React.ReactNode> = {
    blank: null,
    engineering: (
      <>
        <pattern id="t-eng" width="6" height="6" patternUnits="userSpaceOnUse">
          <path d="M6 0H0V6" fill="none" stroke={s} strokeWidth="0.6" />
        </pattern>
        <rect width="64" height="44" fill="url(#t-eng)" />
        <pattern id="t-eng2" width="30" height="30" patternUnits="userSpaceOnUse">
          <path d="M30 0H0V30" fill="none" stroke={s} strokeWidth="1.1" />
        </pattern>
        <rect width="64" height="44" fill="url(#t-eng2)" />
      </>
    ),
    graph: (
      <>
        <pattern id="t-gr" width="4" height="4" patternUnits="userSpaceOnUse">
          <path d="M4 0H0V4" fill="none" stroke={s} strokeWidth="0.4" />
        </pattern>
        <rect width="64" height="44" fill="url(#t-gr)" />
        <path d="M8 0V44M0 36H64" stroke="var(--grid-axis)" strokeWidth="1.2" />
      </>
    ),
    dot: (
      <>
        <pattern id="t-dot" width="7" height="7" patternUnits="userSpaceOnUse">
          <circle cx="3.5" cy="3.5" r="0.8" fill={s} />
        </pattern>
        <rect width="64" height="44" fill="url(#t-dot)" />
      </>
    ),
    cornell: (
      <>
        <pattern id="t-cor" width="64" height="5" patternUnits="userSpaceOnUse">
          <path d="M0 5H64" stroke={s} strokeWidth="0.5" />
        </pattern>
        <rect y="8" width="64" height="26" fill="url(#t-cor)" />
        <path d="M0 8H64M0 34H64" stroke={s} strokeWidth="1" />
        <path d="M18 8V34" stroke="var(--grid-axis)" strokeWidth="1" />
      </>
    ),
    isometric: (
      <>
        <pattern id="t-iso" width="10.4" height="6" patternUnits="userSpaceOnUse">
          <path d="M0 0L10.4 6M0 6L10.4 0M0 0V6M5.2 0V6" stroke={s} strokeWidth="0.5" fill="none" />
        </pattern>
        <rect width="64" height="44" fill="url(#t-iso)" />
      </>
    ),
    custom: (
      <>
        <pattern id="t-cus" width="10" height="10" patternUnits="userSpaceOnUse">
          <path d="M10 0H0V10" fill="none" stroke={s} strokeWidth="0.8" strokeDasharray="1 1.5" />
        </pattern>
        <rect width="64" height="44" fill="url(#t-cus)" />
      </>
    ),
  }
  return (
    <svg viewBox="0 0 64 44" className="tpl-thumb">
      <rect width="64" height="44" fill="var(--paper)" />
      {content[kind]}
    </svg>
  )
}

export function TemplatePicker({ page }: { page: Page }) {
  const update = (patch: Partial<Page>) => useLibrary.getState().updatePage(page.id, patch)
  const o = page.templateOptions
  const setKind = (kind: TemplateKind) => update({ template: kind, templateOptions: { ...templateInfo(kind).defaults, pageColor: o.pageColor } })
  const setOpt = (patch: Partial<Page['templateOptions']>) => update({ templateOptions: { ...o, ...patch } })

  return (
    <div className="tpl-picker">
      <div className="label" style={{ padding: '4px 4px 8px' }}>Page template</div>
      <div className="tpl-grid">
        {TEMPLATES.map((t) => (
          <button key={t.kind} className={`tpl-option ${page.template === t.kind ? 'on' : ''}`} onClick={() => setKind(t.kind)}>
            <Thumb kind={t.kind} />
            <span>{t.name}</span>
          </button>
        ))}
      </div>
      <div className="tpl-custom">
        <div className="tpl-row">
          <span>Grid visible</span>
          <button className={`switch ${o.visible ? 'on' : ''}`} onClick={() => setOpt({ visible: !o.visible })} aria-label="Grid visible" />
        </div>
        <div className="tpl-row">
          <span>Spacing</span>
          <input type="range" min={6} max={60} step={1} value={o.spacing} onChange={(e) => setOpt({ spacing: Number(e.target.value) })} />
          <span className="mono tpl-val">{o.spacing}</span>
        </div>
        <div className="tpl-row">
          <span>Line weight</span>
          <input type="range" min={0.5} max={3} step={0.25} value={o.lineWidth} onChange={(e) => setOpt({ lineWidth: Number(e.target.value) })} />
          <span className="mono tpl-val">{o.lineWidth}</span>
        </div>
        {(page.template === 'custom' || page.template === 'engineering' || page.template === 'graph') && (
          <div className="tpl-row">
            <span>Style</span>
            <div className="segmented">
              <button className={o.style === 'lines' ? 'on' : ''} onClick={() => setOpt({ style: 'lines' })}>
                Lines
              </button>
              <button className={o.style === 'dots' ? 'on' : ''} onClick={() => setOpt({ style: 'dots' })}>
                Dots
              </button>
            </div>
          </div>
        )}
        <div className="tpl-row">
          <span>Page colour</span>
          <div className="tpl-colors">
            {PAGE_COLORS.map((c) => (
              <button
                key={c.name}
                className={`tpl-color ${o.pageColor === c.value ? 'on' : ''}`}
                style={{ background: c.value ?? 'var(--paper)' }}
                onClick={() => setOpt({ pageColor: c.value })}
                aria-label={c.name}
                data-tip={c.name}
                data-tip-pos="top"
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
