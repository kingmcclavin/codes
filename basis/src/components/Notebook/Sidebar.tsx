import { useEffect, useRef, useState } from 'react'
import type { Page, Section } from '../../models'
import { sortedPages, sortedSections, useLibrary } from '../../store/library'
import { useUI } from '../../store/ui'
import { Icon } from '../common/Icon'
import { Menu, anchorOf, type MenuItem } from '../common/Popover'
import { NotebookCover } from '../Library/NotebookCard'
import './notebook.css'

interface DragState {
  pageId: string
  x: number
  y: number
  target: { sectionId: string; index: number } | null
  started: boolean
  startY: number
}

export function Sidebar({ notebookId, pageId, narrow }: { notebookId: string; pageId?: string; narrow: boolean }) {
  const nb = useLibrary((s) => s.notebooks[notebookId])
  const sectionsMap = useLibrary((s) => s.sections)
  const pagesMap = useLibrary((s) => s.pages)
  const width = useUI((s) => s.sidebarWidth)
  const sections = sortedSections(sectionsMap, notebookId)
  const [renaming, setRenaming] = useState<string | null>(null)
  const [menu, setMenu] = useState<{ anchor: ReturnType<typeof anchorOf>; items: MenuItem[] } | null>(null)
  const [drag, setDrag] = useState<DragState | null>(null)
  const dragRef = useRef<DragState | null>(null)
  dragRef.current = drag
  const listRef = useRef<HTMLDivElement>(null)

  const lib = useLibrary.getState()
  const ui = useUI.getState()

  const openPage = (id: string) => {
    ui.navigate({ view: 'notebook', notebookId, pageId: id })
    if (narrow) ui.setSidebarOpen(false)
  }

  const addPage = (sectionId: string) => {
    const id = lib.createPage(notebookId, sectionId, { template: ui.settings.defaultTemplate })
    lib.updateSection(sectionId, { collapsed: false })
    openPage(id)
    setRenaming(id)
  }

  const addSection = () => {
    const id = lib.createSection(notebookId, 'New section')
    setRenaming(id)
  }

  // ── Pointer-driven page reordering (works with mouse, touch and Pencil) ────
  const startDrag = (e: React.PointerEvent, id: string) => {
    e.preventDefault()
    e.stopPropagation()
    const d: DragState = { pageId: id, x: e.clientX, y: e.clientY, target: null, started: false, startY: e.clientY }
    setDrag(d)
    const move = (ev: PointerEvent) => {
      const cur = dragRef.current
      if (!cur) return
      const started = cur.started || Math.abs(ev.clientY - cur.startY) > 4
      setDrag({ ...cur, x: ev.clientX, y: ev.clientY, started, target: started ? dropTarget(ev.clientX, ev.clientY, id) : null })
    }
    const up = () => {
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
      window.removeEventListener('pointercancel', up)
      const cur = dragRef.current
      setDrag(null)
      if (cur?.started && cur.target) useLibrary.getState().movePage(id, cur.target.sectionId, cur.target.index)
      else if (!cur?.started) openPage(id)
    }
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
    window.addEventListener('pointercancel', up)
  }

  const dropTarget = (x: number, y: number, dragId: string) => {
    const els = document.elementsFromPoint(x, y)
    const row = els.find((n) => (n as HTMLElement).dataset?.pageRow) as HTMLElement | undefined
    if (row) {
      const sectionId = row.dataset.section!
      const pages = sortedPages(useLibrary.getState().pages, sectionId).filter((p) => p.id !== dragId)
      const idx = pages.findIndex((p) => p.id === row.dataset.pageRow)
      const r = row.getBoundingClientRect()
      if (row.dataset.pageRow === dragId) return dragRef.current?.target ?? null
      return { sectionId, index: idx + (y > r.top + r.height / 2 ? 1 : 0) }
    }
    const sec = els.find((n) => (n as HTMLElement).dataset?.sectionDrop) as HTMLElement | undefined
    if (sec) {
      const sectionId = sec.dataset.sectionDrop!
      const count = sortedPages(useLibrary.getState().pages, sectionId).filter((p) => p.id !== dragId).length
      return { sectionId, index: count }
    }
    return null
  }

  const sectionMenu = (s: Section, el: HTMLElement) => {
    const idx = sections.findIndex((x) => x.id === s.id)
    setMenu({
      anchor: anchorOf(el),
      items: [
        { label: 'Add page', icon: 'plus', onSelect: () => addPage(s.id) },
        { label: 'Rename section', icon: 'edit', onSelect: () => setRenaming(s.id) },
        ...(idx > 0 ? [{ label: 'Move up', icon: 'chevronLeft', onSelect: () => lib.moveSection(s.id, idx - 1) }] : []),
        ...(idx < sections.length - 1 ? [{ label: 'Move down', icon: 'chevronDown', onSelect: () => lib.moveSection(s.id, idx + 1) }] : []),
        { separator: true },
        {
          label: 'Delete section',
          icon: 'trash',
          danger: true,
          onSelect: () => {
            const n = sortedPages(pagesMap, s.id).length
            if (n === 0 || confirm(`Delete “${s.title}” and its ${n} page${n === 1 ? '' : 's'}?`)) {
              const wasCurrent = pageId && pagesMap[pageId]?.sectionId === s.id
              lib.deleteSection(s.id)
              if (wasCurrent) ui.navigate({ view: 'notebook', notebookId }, true)
            }
          },
        },
      ],
    })
  }

  const pageMenu = (p: Page, el: HTMLElement) => {
    const others = sections.filter((s) => s.id !== p.sectionId)
    setMenu({
      anchor: anchorOf(el),
      items: [
        { label: 'Rename', icon: 'edit', onSelect: () => setRenaming(p.id) },
        { label: 'Duplicate', icon: 'copy', onSelect: () => openPage(lib.duplicatePage(p.id)) },
        ...others.slice(0, 6).map((s) => ({ label: `Move to ${s.title}`, icon: 'section', onSelect: () => lib.movePage(p.id, s.id, 999) })),
        { separator: true },
        {
          label: 'Delete page',
          icon: 'trash',
          danger: true,
          onSelect: () => {
            if (p.elements.length === 0 || confirm(`Delete “${p.title}”?`)) {
              lib.deletePage(p.id)
              if (p.id === pageId) ui.navigate({ view: 'notebook', notebookId }, true)
            }
          },
        },
      ],
    })
  }

  // Resizable on desktop
  const startResize = (e: React.PointerEvent) => {
    e.preventDefault()
    const x0 = e.clientX
    const w0 = width
    const move = (ev: PointerEvent) => useUI.getState().setSidebarWidth(w0 + ev.clientX - x0)
    const up = () => {
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
      document.body.style.cursor = ''
    }
    document.body.style.cursor = 'col-resize'
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
  }

  if (!nb) return null
  const dragPage = drag?.started ? pagesMap[drag.pageId] : null

  return (
    <aside className={`sidebar ui ${narrow ? 'narrow' : ''}`} style={{ width: narrow ? undefined : width }}>
      <div className="sb-top">
        <button className="sb-back" onClick={() => ui.navigate({ view: 'library' })}>
          <Icon name="chevronLeft" size={16} />
          <span>Library</span>
        </button>
        {narrow && (
          <button className="icon-btn sm" onClick={() => ui.setSidebarOpen(false)} aria-label="Close sidebar">
            <Icon name="close" size={16} />
          </button>
        )}
      </div>
      <div className="sb-notebook">
        <NotebookCover nb={nb} size="sm" />
        <div className="sb-nb-text">
          <div className="sb-nb-name">{nb.name}</div>
          {nb.description && <div className="sb-nb-desc">{nb.description}</div>}
        </div>
        <button className="icon-btn sm" onClick={() => ui.setNotebookDialog({ mode: 'edit', id: nb.id })} aria-label="Edit notebook" data-tip="Notebook details">
          <Icon name="settings" size={15} />
        </button>
      </div>

      <div className="sb-head">
        <span className="label">Sections</span>
        <button className="icon-btn sm" onClick={addSection} data-tip="Add section" aria-label="Add section">
          <Icon name="plus" size={15} />
        </button>
      </div>

      <div className="sb-list" ref={listRef}>
        {sections.map((s) => {
          const pages = sortedPages(pagesMap, s.id)
          const visiblePages = pages.filter((p) => !(drag?.started && p.id === drag.pageId))
          const showTarget = drag?.started && drag.target?.sectionId === s.id
          return (
            <div key={s.id} className="sb-section" data-section-drop={s.id}>
              <div className="sb-section-head">
                <button className="sb-chevron" onClick={() => lib.updateSection(s.id, { collapsed: !s.collapsed })} aria-label="Toggle section">
                  <Icon name={s.collapsed ? 'chevronRight' : 'chevronDown'} size={14} />
                </button>
                {renaming === s.id ? (
                  <RenameInput value={s.title} onDone={(v) => (lib.updateSection(s.id, { title: v || s.title }), setRenaming(null))} />
                ) : (
                  <span className="sb-section-title" onDoubleClick={() => setRenaming(s.id)} onClick={() => lib.updateSection(s.id, { collapsed: !s.collapsed })}>
                    {s.title}
                  </span>
                )}
                <span className="sb-count mono">{pages.length}</span>
                <button className="icon-btn sm sb-row-action" onClick={() => addPage(s.id)} aria-label="Add page" data-tip="Add page">
                  <Icon name="plus" size={14} />
                </button>
                <button className="icon-btn sm sb-row-action" onClick={(e) => sectionMenu(s, e.currentTarget)} aria-label="Section menu">
                  <Icon name="more" size={14} stroke={2.4} />
                </button>
              </div>
              {(!s.collapsed || showTarget) && (
                <div className="sb-pages">
                  {visiblePages.map((p, i) => (
                    <div key={p.id}>
                      {showTarget && drag!.target!.index === i && <div className="drop-line" />}
                      <div
                        className={`sb-page ${p.id === pageId ? 'active' : ''}`}
                        data-page-row={p.id}
                        data-section={s.id}
                        onPointerDown={(e) => {
                          if ((e.target as HTMLElement).closest('button, input')) return
                          if (e.pointerType === 'mouse' && e.button !== 0) return
                          startDrag(e, p.id)
                        }}
                        onDoubleClick={() => setRenaming(p.id)}
                      >
                        <span className="sb-grip">
                          <Icon name="drag" size={14} stroke={2.6} />
                        </span>
                        {renaming === p.id ? (
                          <RenameInput value={p.title} onDone={(v) => (lib.updatePage(p.id, { title: v || p.title }), setRenaming(null))} />
                        ) : (
                          <span className="sb-page-title">{p.title}</span>
                        )}
                        <button className="icon-btn sm sb-row-action" onClick={(e) => pageMenu(p, e.currentTarget)} aria-label="Page menu">
                          <Icon name="more" size={14} stroke={2.4} />
                        </button>
                      </div>
                    </div>
                  ))}
                  {showTarget && drag!.target!.index >= visiblePages.length && <div className="drop-line" />}
                  {pages.length === 0 && !showTarget && (
                    <button className="sb-empty" onClick={() => addPage(s.id)}>
                      + Add a page
                    </button>
                  )}
                </div>
              )}
            </div>
          )
        })}
        <button className="sb-add-section" onClick={addSection}>
          <Icon name="plus" size={14} />
          Add Section
        </button>
      </div>

      {dragPage && drag && (
        <div className="drag-ghost" style={{ left: drag.x + 12, top: drag.y - 16 }}>
          <Icon name="page" size={14} /> {dragPage.title}
        </div>
      )}
      {!narrow && <div className="sb-resizer" onPointerDown={startResize} />}
      {menu && <Menu anchor={menu.anchor} items={menu.items} onClose={() => setMenu(null)} />}
    </aside>
  )
}

function RenameInput({ value, onDone }: { value: string; onDone: (v: string) => void }) {
  const [v, setV] = useState(value)
  const ref = useRef<HTMLInputElement>(null)
  const done = useRef(false)
  useEffect(() => {
    ref.current?.focus()
    ref.current?.select()
  }, [])
  const finish = (val: string) => {
    if (done.current) return
    done.current = true
    onDone(val.trim())
  }
  return (
    <input
      ref={ref}
      className="sb-rename"
      value={v}
      onChange={(e) => setV(e.target.value)}
      onBlur={() => finish(v)}
      onKeyDown={(e) => {
        e.stopPropagation()
        if (e.key === 'Enter') finish(v)
        if (e.key === 'Escape') finish(value)
      }}
      onPointerDown={(e) => e.stopPropagation()}
    />
  )
}
