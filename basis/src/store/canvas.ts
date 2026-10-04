// Canvas interaction state: active tool, tool options, selection and the
// per-page undo history. Page *content* lives in the library store.

import { create } from 'zustand'
import { INK, type CanvasElement, type ShapeKind } from '../models'
import { useLibrary } from './library'

export type Tool =
  | 'pen'
  | 'highlighter'
  | 'eraser'
  | 'select'
  | 'hand'
  | 'text'
  | 'shape'
  | 'line'
  | 'arrow'
  | 'equation'
  | 'image'

export interface StrokeOptions {
  color: string
  width: number
  opacity: number
}

export interface ToolOptions {
  pen: StrokeOptions
  highlighter: StrokeOptions
  shape: StrokeOptions & { kind: ShapeKind; fill: boolean; dashed: boolean }
  line: StrokeOptions & { dashed: boolean }
  arrow: StrokeOptions & { dashed: boolean }
  text: { color: string; fontSize: number; font: 'sans' | 'mono' }
  eraser: { size: number; mode: 'stroke' | 'area' }
}

interface History {
  past: CanvasElement[][]
  future: CanvasElement[][]
}

interface CanvasState {
  tool: Tool
  previousTool: Tool
  options: ToolOptions
  selection: string[]
  editingId: string | null
  history: Record<string, History>
  /** Registered by the active canvas so panels can insert at the visible centre. */
  centerProvider: (() => { x: number; y: number }) | null
  revealProvider: ((elementId: string) => void) | null
  printProvider: (() => void) | null
  zoomProvider: ((action: 'in' | 'out' | 'reset' | 'fit') => void) | null

  setTool: (t: Tool) => void
  setOptions: <K extends keyof ToolOptions>(tool: K, patch: Partial<ToolOptions[K]>) => void
  setSelection: (ids: string[]) => void
  setEditing: (id: string | null) => void

  /** Apply a new element list to a page, recording undo history. */
  commit: (pageId: string, next: CanvasElement[]) => void
  /** Mutate without recording history (e.g. live typing); call checkpoint() first. */
  checkpoint: (pageId: string) => void
  undo: (pageId: string) => void
  redo: (pageId: string) => void

  insertAtCenter: (pageId: string, make: (c: { x: number; y: number }) => CanvasElement) => string
}

const MAX_HISTORY = 120

const initialOptions: ToolOptions = {
  pen: { color: INK, width: 2.4, opacity: 1 },
  highlighter: { color: '#facc15', width: 18, opacity: 0.35 },
  shape: { color: INK, width: 2, opacity: 1, kind: 'rect', fill: false, dashed: false },
  line: { color: INK, width: 2, opacity: 1, dashed: false },
  arrow: { color: INK, width: 2, opacity: 1, dashed: false },
  text: { color: INK, fontSize: 18, font: 'sans' },
  eraser: { size: 16, mode: 'stroke' },
}

const loadOptions = (): ToolOptions => {
  try {
    const saved = JSON.parse(localStorage.getItem('basis.tools') || '{}')
    return { ...initialOptions, ...saved }
  } catch {
    return initialOptions
  }
}

export const useCanvas = create<CanvasState>((set, get) => ({
  tool: 'pen',
  previousTool: 'pen',
  options: loadOptions(),
  selection: [],
  editingId: null,
  history: {},
  centerProvider: null,
  revealProvider: null,
  printProvider: null,
  zoomProvider: null,

  setTool(t) {
    if (t === get().tool) return
    set({ tool: t, previousTool: get().tool, editingId: null, selection: t === 'select' ? get().selection : [] })
  },
  setOptions(tool, patch) {
    const options = { ...get().options, [tool]: { ...get().options[tool], ...patch } }
    set({ options })
    try {
      localStorage.setItem('basis.tools', JSON.stringify(options))
    } catch {
      /* ignore */
    }
  },
  setSelection: (ids) => set({ selection: ids }),
  setEditing: (id) => set({ editingId: id }),

  checkpoint(pageId) {
    const page = useLibrary.getState().pages[pageId]
    if (!page) return
    const h = get().history[pageId] ?? { past: [], future: [] }
    const past = [...h.past, page.elements].slice(-MAX_HISTORY)
    set({ history: { ...get().history, [pageId]: { past, future: [] } } })
  },

  commit(pageId, next) {
    const page = useLibrary.getState().pages[pageId]
    if (!page || page.elements === next) return
    get().checkpoint(pageId)
    useLibrary.getState().setElements(pageId, next)
  },

  undo(pageId) {
    const h = get().history[pageId]
    const page = useLibrary.getState().pages[pageId]
    if (!h || !h.past.length || !page) return
    const prev = h.past[h.past.length - 1]
    set({
      history: { ...get().history, [pageId]: { past: h.past.slice(0, -1), future: [page.elements, ...h.future] } },
      selection: [],
      editingId: null,
    })
    useLibrary.getState().setElements(pageId, prev)
  },

  redo(pageId) {
    const h = get().history[pageId]
    const page = useLibrary.getState().pages[pageId]
    if (!h || !h.future.length || !page) return
    const [next, ...rest] = h.future
    set({
      history: { ...get().history, [pageId]: { past: [...h.past, page.elements], future: rest } },
      selection: [],
      editingId: null,
    })
    useLibrary.getState().setElements(pageId, next)
  },

  insertAtCenter(pageId, make) {
    const c = get().centerProvider?.() ?? { x: 200, y: 200 }
    const el = make(c)
    const page = useLibrary.getState().pages[pageId]
    if (!page) return el.id
    get().commit(pageId, [...page.elements, el])
    set({ tool: 'select', selection: [el.id] })
    return el.id
  },
}))

/** Update one element in place (records history). */
export function updateElement(pageId: string, id: string, patch: Partial<CanvasElement>, record = true) {
  const page = useLibrary.getState().pages[pageId]
  if (!page) return
  const next = page.elements.map((e) => (e.id === id ? ({ ...e, ...patch } as CanvasElement) : e))
  if (record) useCanvas.getState().commit(pageId, next)
  else useLibrary.getState().setElements(pageId, next)
}

export function removeElements(pageId: string, ids: string[]) {
  const page = useLibrary.getState().pages[pageId]
  if (!page) return
  const set = new Set(ids)
  useCanvas.getState().commit(
    pageId,
    page.elements.filter((e) => !set.has(e.id)),
  )
  useCanvas.setState({ selection: [], editingId: null })
}
