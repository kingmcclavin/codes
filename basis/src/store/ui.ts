// UI state: routing, theme, panels, dialogs. Persisted bits go to localStorage.

import { create } from 'zustand'
import { DEFAULT_SETTINGS, type Settings } from '../models'
import { loadSettings, saveSettings } from '../services/storage'

export type Route =
  | { view: 'library' }
  | { view: 'notebook'; notebookId: string; pageId?: string }

export type DockPanel = 'calculator' | 'tools' | 'variables' | 'files'

export interface Toast {
  id: number
  text: string
}

interface UIState {
  route: Route
  settings: Settings
  resolvedTheme: 'light' | 'dark'
  sidebarOpen: boolean
  sidebarWidth: number
  dock: DockPanel | null
  dockWidth: number
  searchOpen: boolean
  settingsOpen: boolean
  shortcutsOpen: boolean
  notebookDialog: { mode: 'create' } | { mode: 'edit'; id: string } | null
  toasts: Toast[]

  navigate: (r: Route, replace?: boolean) => void
  setSettings: (patch: Partial<Settings>) => void
  setSidebarOpen: (v: boolean) => void
  setSidebarWidth: (w: number) => void
  toggleDock: (p: DockPanel) => void
  setDock: (p: DockPanel | null) => void
  setDockWidth: (w: number) => void
  setSearchOpen: (v: boolean) => void
  setSettingsOpen: (v: boolean) => void
  setShortcutsOpen: (v: boolean) => void
  setNotebookDialog: (d: UIState['notebookDialog']) => void
  toast: (text: string) => void
}

// ── Hash routing (works on GitHub Pages / any static host) ───────────────────
export function parseHash(hash: string): Route {
  const parts = hash.replace(/^#\/?/, '').split('/').filter(Boolean)
  if (parts[0] === 'n' && parts[1]) return { view: 'notebook', notebookId: parts[1], pageId: parts[2] === 'p' ? parts[3] : undefined }
  return { view: 'library' }
}

export function routeToHash(r: Route) {
  if (r.view === 'library') return '#/'
  return `#/n/${r.notebookId}${r.pageId ? `/p/${r.pageId}` : ''}`
}

const LAYOUT_KEY = 'basis.layout'
const layout = (() => {
  try {
    return JSON.parse(localStorage.getItem(LAYOUT_KEY) || '{}') as { sidebarWidth?: number; dockWidth?: number }
  } catch {
    return {}
  }
})()
const saveLayout = (s: { sidebarWidth: number; dockWidth: number }) => {
  try {
    localStorage.setItem(LAYOUT_KEY, JSON.stringify(s))
  } catch {
    /* ignore */
  }
}

const systemDark = () => typeof matchMedia !== 'undefined' && matchMedia('(prefers-color-scheme: dark)').matches
const resolve = (s: Settings) => (s.theme === 'system' ? (systemDark() ? 'dark' : 'light') : s.theme)

const initialSettings: Settings = { ...DEFAULT_SETTINGS, ...loadSettings() }
const wide = typeof window !== 'undefined' ? window.innerWidth >= 900 : true

let toastId = 0

export const useUI = create<UIState>((set, get) => ({
  route: typeof location !== 'undefined' ? parseHash(location.hash) : { view: 'library' },
  settings: initialSettings,
  resolvedTheme: resolve(initialSettings),
  sidebarOpen: wide,
  sidebarWidth: layout.sidebarWidth ?? 264,
  dock: null,
  dockWidth: layout.dockWidth ?? 340,
  searchOpen: false,
  settingsOpen: false,
  shortcutsOpen: false,
  notebookDialog: null,
  toasts: [],

  navigate(r, replace = false) {
    const hash = routeToHash(r)
    if (location.hash !== hash) {
      if (replace) history.replaceState(null, '', hash)
      else history.pushState(null, '', hash)
    }
    set({ route: r })
  },
  setSettings(patch) {
    const settings = { ...get().settings, ...patch }
    saveSettings(settings)
    set({ settings, resolvedTheme: resolve(settings) })
  },
  setSidebarOpen: (v) => set({ sidebarOpen: v }),
  setSidebarWidth(w) {
    const sidebarWidth = Math.round(Math.max(200, Math.min(440, w)))
    set({ sidebarWidth })
    saveLayout({ sidebarWidth, dockWidth: get().dockWidth })
  },
  toggleDock: (p) => set({ dock: get().dock === p ? null : p }),
  setDock: (p) => set({ dock: p }),
  setDockWidth(w) {
    const dockWidth = Math.round(Math.max(300, Math.min(520, w)))
    set({ dockWidth })
    saveLayout({ sidebarWidth: get().sidebarWidth, dockWidth })
  },
  setSearchOpen: (v) => set({ searchOpen: v }),
  setSettingsOpen: (v) => set({ settingsOpen: v }),
  setShortcutsOpen: (v) => set({ shortcutsOpen: v }),
  setNotebookDialog: (d) => set({ notebookDialog: d }),
  toast(text) {
    const id = ++toastId
    set({ toasts: [...get().toasts, { id, text }] })
    setTimeout(() => set({ toasts: get().toasts.filter((t) => t.id !== id) }), 2200)
  },
}))

if (typeof window !== 'undefined') {
  window.addEventListener('popstate', () => useUI.setState({ route: parseHash(location.hash) }))
  window.addEventListener('hashchange', () => useUI.setState({ route: parseHash(location.hash) }))
  matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change', () =>
    useUI.setState({ resolvedTheme: resolve(useUI.getState().settings) }),
  )
}
