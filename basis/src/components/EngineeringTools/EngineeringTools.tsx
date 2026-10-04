import { useState } from 'react'
import { Icon } from '../common/Icon'
import { ENGINEERING_TOOLS } from './tools'
import './tools.css'

export function EngineeringTools({ pageId }: { pageId?: string }) {
  const [open, setOpen] = useState<string | null>(() => {
    try {
      return localStorage.getItem('basis.tool') ?? 'units'
    } catch {
      return 'units'
    }
  })
  const toggle = (id: string) => {
    const next = open === id ? null : id
    setOpen(next)
    try {
      if (next) localStorage.setItem('basis.tool', next)
    } catch {
      /* ignore */
    }
  }
  return (
    <div className="eng-tools">
      {ENGINEERING_TOOLS.map((t) => (
        <section key={t.id} className={`eng-tool ${open === t.id ? 'open' : ''}`}>
          <button className="eng-tool-head" onClick={() => toggle(t.id)}>
            <span className="eng-tool-icon">
              <Icon name={t.icon} size={16} />
            </span>
            <span className="eng-tool-text">
              <span className="eng-tool-name">{t.name}</span>
              <span className="eng-tool-desc">{t.description}</span>
            </span>
            <Icon name="chevronDown" size={15} className="eng-tool-chev" />
          </button>
          {open === t.id && <t.Component pageId={pageId} />}
        </section>
      ))}
    </div>
  )
}
