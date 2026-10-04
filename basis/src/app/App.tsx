import { useEffect } from 'react'
import { createDemoLibrary } from '../demo/demo'
import { requestPersistence } from '../services/storage'
import { useLibrary } from '../store/library'
import { useUI } from '../store/ui'
import { LogoMark } from '../components/Brand/Logo'
import { Library } from '../components/Library/Library'
import { NotebookDialog } from '../components/Library/NotebookDialog'
import { NotebookView } from '../components/Notebook/NotebookView'
import { SearchOverlay } from '../components/Search/SearchOverlay'
import { SettingsDialog, ShortcutsDialog } from '../components/Settings/SettingsDialog'

export function App() {
  const loaded = useLibrary((s) => s.loaded)
  const route = useUI((s) => s.route)
  const theme = useUI((s) => s.resolvedTheme)
  const notebookDialog = useUI((s) => s.notebookDialog)
  const toasts = useUI((s) => s.toasts)

  useEffect(() => {
    void useLibrary.getState().init(createDemoLibrary)
    void requestPersistence()
  }, [])

  useEffect(() => {
    document.documentElement.dataset.theme = theme
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', theme === 'dark' ? '#0b0c0e' : '#e9e7e1')
  }, [theme])

  // Global shortcuts + flush on hide
  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      const mod = e.metaKey || e.ctrlKey
      const ui = useUI.getState()
      const k = e.key.toLowerCase()
      if (mod && k === 's') {
        e.preventDefault()
        void useLibrary.getState().flush().then(() => ui.toast('Saved to this device'))
      } else if (mod && (k === 'f' || k === 'k')) {
        e.preventDefault()
        ui.setSearchOpen(true)
      } else if (mod && e.key === '\\') {
        e.preventDefault()
        ui.setSidebarOpen(!ui.sidebarOpen)
      } else if (e.key === '?' && !(e.target as HTMLElement).closest('input, textarea')) {
        ui.setShortcutsOpen(true)
      }
    }
    const hide = () => document.visibilityState === 'hidden' && void useLibrary.getState().flush()
    // Block Safari's page-level pinch zoom so canvas gestures stay ours.
    const block = (e: Event) => e.preventDefault()
    window.addEventListener('keydown', key)
    document.addEventListener('visibilitychange', hide)
    window.addEventListener('pagehide', hide)
    document.addEventListener('gesturestart', block)
    return () => {
      window.removeEventListener('keydown', key)
      document.removeEventListener('visibilitychange', hide)
      window.removeEventListener('pagehide', hide)
      document.removeEventListener('gesturestart', block)
    }
  }, [])

  if (!loaded) {
    return (
      <div className="boot">
        <LogoMark size={40} />
      </div>
    )
  }

  return (
    <div className="app">
      {route.view === 'library' ? <Library /> : <NotebookView key={route.notebookId} notebookId={route.notebookId} pageId={route.pageId} />}
      {notebookDialog && <NotebookDialog key={notebookDialog.mode === 'edit' ? notebookDialog.id : 'new'} />}
      <SearchOverlay />
      <SettingsDialog />
      <ShortcutsDialog />
      <div className="toasts">
        {toasts.map((t) => (
          <div key={t.id} className="toast">
            {t.text}
          </div>
        ))}
      </div>
    </div>
  )
}
