import { useEffect, useState } from 'react'
import { sortedPages, sortedSections, useLibrary } from '../../store/library'
import { useUI } from '../../store/ui'
import { Canvas } from '../Canvas/Canvas'
import { PageEvalProvider } from '../Canvas/PageContext'
import { Icon } from '../common/Icon'
import { Dock } from '../Panels/Dock'
import { Toolbar } from '../Toolbar/Toolbar'
import { Sidebar } from './Sidebar'
import { TopBar } from './TopBar'
import './notebook.css'

function useWidth() {
  const [w, setW] = useState(() => window.innerWidth)
  useEffect(() => {
    const on = () => setW(window.innerWidth)
    window.addEventListener('resize', on)
    return () => window.removeEventListener('resize', on)
  }, [])
  return w
}

export function NotebookView({ notebookId, pageId }: { notebookId: string; pageId?: string }) {
  const nb = useLibrary((s) => s.notebooks[notebookId])
  const page = useLibrary((s) => (pageId ? s.pages[pageId] : undefined))
  const sidebarOpen = useUI((s) => s.sidebarOpen)
  const dock = useUI((s) => s.dock)
  const width = useWidth()
  const narrow = width < 900
  const dockOverlay = width < 1280

  // Collapse the sidebar into a drawer when the window becomes narrow (iPad portrait, phones).
  useEffect(() => {
    if (narrow) useUI.getState().setSidebarOpen(false)
  }, [narrow])

  // Resolve a page when the route has none (or a stale one).
  useEffect(() => {
    if (!nb) return
    if (pageId && page) return
    const s = useLibrary.getState()
    const pages = sortedSections(s.sections, notebookId).flatMap((sec) => sortedPages(s.pages, sec.id))
    const recent = [...pages].sort((a, b) => b.lastOpenedAt - a.lastOpenedAt)[0]
    const target = recent && recent.lastOpenedAt ? recent : pages[0]
    if (target) useUI.getState().navigate({ view: 'notebook', notebookId, pageId: target.id }, true)
  }, [nb, notebookId, pageId, page])

  useEffect(() => {
    if (pageId && page) useLibrary.getState().markOpened(pageId)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pageId])

  if (!nb) {
    return (
      <div className="nb-missing">
        <p>This notebook doesn't exist anymore.</p>
        <button className="btn" onClick={() => useUI.getState().navigate({ view: 'library' })}>
          Back to Library
        </button>
      </div>
    )
  }

  return (
    <PageEvalProvider page={page}>
      <div className={`notebook ${narrow ? 'is-narrow' : ''}`}>
        {sidebarOpen && narrow && <div className="sb-backdrop" onClick={() => useUI.getState().setSidebarOpen(false)} />}
        {sidebarOpen && <Sidebar notebookId={notebookId} pageId={pageId} narrow={narrow} />}
        <div className="nb-main">
          <TopBar page={page} notebookId={notebookId} />
          <div className="canvas-area">
            {page ? (
              <>
                <Canvas page={page} />
                <Toolbar pageId={page.id} />
              </>
            ) : (
              <div className="empty" style={{ height: '100%' }}>
                <Icon name="page" size={26} />
                This notebook has no pages yet.
              </div>
            )}
            {dockOverlay && <Dock notebookId={notebookId} pageId={pageId} overlay />}
          </div>
        </div>
        {!dockOverlay && dock && <Dock notebookId={notebookId} pageId={pageId} overlay={false} />}
      </div>
    </PageEvalProvider>
  )
}
