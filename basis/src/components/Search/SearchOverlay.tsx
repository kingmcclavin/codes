import { useEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { search, type SearchKind, type SearchResult } from '../../services/search'
import { useCanvas } from '../../store/canvas'
import { useLibrary } from '../../store/library'
import { useUI } from '../../store/ui'
import { Icon } from '../common/Icon'
import './search.css'

const KIND: Record<SearchKind, { icon: string; label: string }> = {
  notebook: { icon: 'library', label: 'Notebook' },
  section: { icon: 'section', label: 'Section' },
  page: { icon: 'page', label: 'Page' },
  text: { icon: 'text', label: 'Text' },
  equation: { icon: 'equation', label: 'Equation' },
  variable: { icon: 'variable', label: 'Variables' },
  table: { icon: 'table', label: 'Table' },
  note: { icon: 'sticky', label: 'Note' },
  graph: { icon: 'graph', label: 'Graph' },
}

function Highlight({ text, q }: { text: string; q: string }) {
  const i = text.toLowerCase().indexOf(q.toLowerCase())
  if (i < 0 || !q) return <>{text}</>
  return (
    <>
      {text.slice(0, i)}
      <mark>{text.slice(i, i + q.length)}</mark>
      {text.slice(i + q.length)}
    </>
  )
}

export function SearchOverlay() {
  const open = useUI((s) => s.searchOpen)
  const [q, setQ] = useState('')
  const [active, setActive] = useState(0)
  const notebooks = useLibrary((s) => s.notebooks)
  const sections = useLibrary((s) => s.sections)
  const pages = useLibrary((s) => s.pages)
  const inputRef = useRef<HTMLInputElement>(null)
  const listRef = useRef<HTMLDivElement>(null)

  const results = useMemo(() => (open ? search(q, { notebooks, sections, pages }) : []), [q, open, notebooks, sections, pages])

  useEffect(() => {
    if (open) {
      setActive(0)
      setTimeout(() => inputRef.current?.select(), 10)
    }
  }, [open])
  useEffect(() => setActive(0), [q])
  useEffect(() => {
    listRef.current?.querySelector('.sr-item.active')?.scrollIntoView({ block: 'nearest' })
  }, [active])

  if (!open) return null
  const close = () => useUI.getState().setSearchOpen(false)

  const go = (r: SearchResult) => {
    close()
    const ui = useUI.getState()
    if (r.kind === 'section') {
      const first = Object.values(pages)
        .filter((p) => p.sectionId === r.sectionId)
        .sort((a, b) => a.order - b.order)[0]
      ui.navigate({ view: 'notebook', notebookId: r.notebookId, pageId: first?.id })
      return
    }
    ui.navigate({ view: 'notebook', notebookId: r.notebookId, pageId: r.pageId })
    if (r.elementId) setTimeout(() => useCanvas.getState().revealProvider?.(r.elementId!), 120)
  }

  const recent = Object.values(pages)
    .filter((p) => p.lastOpenedAt && notebooks[p.notebookId])
    .sort((a, b) => b.lastOpenedAt - a.lastOpenedAt)
    .slice(0, 6)

  return createPortal(
    <div className="modal-backdrop search-backdrop" onPointerDown={(e) => e.target === e.currentTarget && close()}>
      <div className="search-panel ui" role="dialog" aria-label="Search">
        <div className="search-input-row">
          <Icon name="search" size={18} />
          <input
            ref={inputRef}
            autoFocus
            className="search-input"
            value={q}
            placeholder="Search notebooks, pages, text, equations, variables…"
            onChange={(e) => setQ(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Escape') close()
              if (e.key === 'ArrowDown') {
                e.preventDefault()
                setActive((a) => Math.min(results.length - 1, a + 1))
              }
              if (e.key === 'ArrowUp') {
                e.preventDefault()
                setActive((a) => Math.max(0, a - 1))
              }
              if (e.key === 'Enter' && results[active]) go(results[active])
            }}
          />
          <span className="kbd">esc</span>
        </div>
        <div className="search-results" ref={listRef}>
          {!q && (
            <>
              <div className="sr-group label">Recently opened</div>
              {recent.map((p) => (
                <button key={p.id} className="sr-item" onClick={() => go({ kind: 'page', notebookId: p.notebookId, pageId: p.id, title: p.title, context: '', score: 0 })}>
                  <span className="sr-icon">
                    <Icon name="page" size={15} />
                  </span>
                  <span className="sr-text">
                    <span className="sr-title">{p.title}</span>
                    <span className="sr-context">
                      {notebooks[p.notebookId]?.name} › {sections[p.sectionId]?.title}
                    </span>
                  </span>
                </button>
              ))}
              <div className="sr-tip mono">Try “Gauss”, “capacitance”, “KE =”, or a variable name</div>
            </>
          )}
          {q && results.length === 0 && <div className="empty">No results for “{q}”</div>}
          {results.map((r, i) => (
            <button key={i} className={`sr-item ${i === active ? 'active' : ''}`} onMouseEnter={() => setActive(i)} onClick={() => go(r)}>
              <span className="sr-icon">
                <Icon name={KIND[r.kind].icon} size={15} />
              </span>
              <span className="sr-text">
                <span className="sr-title">
                  {r.snippet ? <Highlight text={r.snippet} q={q} /> : <Highlight text={r.title} q={q} />}
                </span>
                <span className="sr-context">{r.snippet ? `${r.context} › ${r.title}` : r.context}</span>
              </span>
              <span className="sr-kind mono">{KIND[r.kind].label}</span>
            </button>
          ))}
        </div>
      </div>
    </div>,
    document.body,
  )
}
