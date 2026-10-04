import { useEffect, useRef, useState } from 'react'
import type { Page } from '../../models'
import { exportNotebook, exportPageJson } from '../../services/export'
import { pickFiles } from '../../services/files'
import { importPdf } from '../../services/canvas/insert'
import { useCanvas } from '../../store/canvas'
import { notebookPages, sortedSections, useLibrary } from '../../store/library'
import { useUI, type DockPanel } from '../../store/ui'
import { Icon } from '../common/Icon'
import { Menu, Popover, anchorOf } from '../common/Popover'
import { TemplatePicker } from './TemplatePicker'

const DOCK_BUTTONS: { id: DockPanel; icon: string; label: string }[] = [
  { id: 'calculator', icon: 'calculator', label: 'Calculator' },
  { id: 'variables', icon: 'variable', label: 'Variables' },
  { id: 'tools', icon: 'tools', label: 'Engineering tools' },
  { id: 'files', icon: 'files', label: 'Files' },
]

export function TopBar({ page, notebookId }: { page: Page | undefined; notebookId: string }) {
  const sidebarOpen = useUI((s) => s.sidebarOpen)
  const dock = useUI((s) => s.dock)
  const theme = useUI((s) => s.resolvedTheme)
  const saveState = useLibrary((s) => s.saveState)
  const section = useLibrary((s) => (page ? s.sections[page.sectionId] : undefined))
  const history = useCanvas((s) => (page ? s.history[page.id] : undefined))
  const [tplOpen, setTplOpen] = useState(false)
  const [moreOpen, setMoreOpen] = useState(false)
  const tplRef = useRef<HTMLButtonElement>(null)
  const moreRef = useRef<HTMLButtonElement>(null)
  const ui = useUI.getState()

  const exportNb = () => {
    const s = useLibrary.getState()
    void exportNotebook(s.notebooks[notebookId], sortedSections(s.sections, notebookId), notebookPages(s.pages, notebookId))
    ui.toast('Exporting notebook…')
  }
  const importPdfFile = async () => {
    const [file] = await pickFiles('application/pdf')
    if (!file) return
    ui.toast('Importing PDF…')
    try {
      const first = await importPdf(notebookId, file)
      if (first) ui.navigate({ view: 'notebook', notebookId, pageId: first })
      ui.toast('PDF imported as a new section')
    } catch (e) {
      console.error(e)
      alert('Could not import that PDF.')
    }
  }

  return (
    <header className="topbar ui">
      <button className={`icon-btn ${sidebarOpen ? '' : ''}`} onClick={() => ui.setSidebarOpen(!sidebarOpen)} aria-label="Toggle sidebar" data-tip="Sidebar (⌘\)">
        <Icon name="sidebar" />
      </button>
      <div className="crumbs">
        {section && <span className="crumb-section">{section.title}</span>}
        {section && <Icon name="chevronRight" size={13} className="crumb-sep" />}
        {page && <PageTitle page={page} />}
      </div>
      <SaveIndicator state={saveState} />
      <div className="topbar-spacer" />
      {page && (
        <div className="tb-group">
          <button className="icon-btn" disabled={!history?.past.length} onClick={() => useCanvas.getState().undo(page.id)} aria-label="Undo" data-tip="Undo (⌘Z)">
            <Icon name="undo" />
          </button>
          <button className="icon-btn" disabled={!history?.future.length} onClick={() => useCanvas.getState().redo(page.id)} aria-label="Redo" data-tip="Redo (⇧⌘Z)">
            <Icon name="redo" />
          </button>
        </div>
      )}
      {page && (
        <button ref={tplRef} className={`icon-btn tpl-btn ${tplOpen ? 'active' : ''}`} onClick={() => setTplOpen(!tplOpen)} aria-label="Page template" data-tip="Page template">
          <Icon name="grid" />
        </button>
      )}
      <div className="tb-group dock-toggles">
        {DOCK_BUTTONS.map((b) => (
          <button key={b.id} className={`icon-btn ${dock === b.id ? 'active' : ''}`} onClick={() => ui.toggleDock(b.id)} aria-label={b.label} data-tip={b.label}>
            <Icon name={b.icon} />
          </button>
        ))}
      </div>
      <button className="icon-btn" onClick={() => ui.setSearchOpen(true)} aria-label="Search" data-tip="Search (⌘F)">
        <Icon name="search" />
      </button>
      <button ref={moreRef} className="icon-btn" onClick={() => setMoreOpen(true)} aria-label="More">
        <Icon name="more" stroke={2.4} />
      </button>

      {tplOpen && page && (
        <Popover anchor={anchorOf(tplRef.current?.offsetParent ? tplRef.current : moreRef.current)} onClose={() => setTplOpen(false)} align="end" width={340}>
          <TemplatePicker page={page} />
        </Popover>
      )}
      {moreOpen && (
        <Menu
          anchor={anchorOf(moreRef.current)}
          align="end"
          onClose={() => setMoreOpen(false)}
          items={[
            ...(page
              ? [
                  { label: 'Export page as PDF', icon: 'print', onSelect: () => useCanvas.getState().printProvider?.() },
                  { label: 'Export page data (.json)', icon: 'download', onSelect: () => exportPageJson(page) },
                ]
              : []),
            { label: 'Export notebook (.basis)', icon: 'export', onSelect: exportNb },
            { label: 'Import PDF…', icon: 'pdf', onSelect: () => void importPdfFile() },
            { separator: true },
            ...(page ? [{ label: 'Page template…', icon: 'grid', onSelect: () => setTimeout(() => setTplOpen(true), 0) }] : []),
            ...DOCK_BUTTONS.map((b) => ({ label: b.label, icon: b.icon, onSelect: () => ui.setDock(b.id) })),
            { separator: true },
            { label: theme === 'dark' ? 'Light mode' : 'Dark mode', icon: theme === 'dark' ? 'sun' : 'moon', onSelect: () => ui.setSettings({ theme: theme === 'dark' ? 'light' : 'dark' }) },
            { label: 'Keyboard shortcuts', icon: 'keyboard', kbd: '?', onSelect: () => ui.setShortcutsOpen(true) },
            { label: 'Settings', icon: 'settings', onSelect: () => ui.setSettingsOpen(true) },
          ]}
        />
      )}
    </header>
  )
}

function PageTitle({ page }: { page: Page }) {
  const [v, setV] = useState(page.title)
  useEffect(() => setV(page.title), [page.title, page.id])
  return (
    <input
      className="page-title-input"
      value={v}
      size={Math.max(4, v.length)}
      onChange={(e) => setV(e.target.value)}
      onBlur={() => v.trim() && v !== page.title && useLibrary.getState().updatePage(page.id, { title: v.trim() })}
      onKeyDown={(e) => {
        e.stopPropagation()
        if (e.key === 'Enter' || e.key === 'Escape') (e.target as HTMLInputElement).blur()
      }}
      aria-label="Page title"
    />
  )
}

function SaveIndicator({ state }: { state: 'saved' | 'pending' | 'saving' }) {
  return (
    <span className={`save-ind ${state}`} title={state === 'saved' ? 'All changes saved on this device' : 'Saving…'}>
      <span className="save-dot" />
      <span className="mono">{state === 'saved' ? 'Saved' : 'Saving'}</span>
    </span>
  )
}
