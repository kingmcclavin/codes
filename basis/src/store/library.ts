// Notebook state: notebooks, sections and pages, with debounced persistence.
// Canvas, calculator and UI state live in their own stores.

import { create } from 'zustand'
import type { CanvasElement, Notebook, NotebookIcon, Page, Section, TemplateKind, TemplateOptions } from '../models'
import { templateInfo } from '../models/templates'
import { uid } from '../services/id'
import { storage, type LibrarySnapshot } from '../services/storage'

type SaveState = 'saved' | 'pending' | 'saving'

interface LibraryState {
  loaded: boolean
  notebooks: Record<string, Notebook>
  sections: Record<string, Section>
  pages: Record<string, Page>
  saveState: SaveState
  lastSavedAt: number

  init: (seed: () => LibrarySnapshot) => Promise<void>
  replaceAll: (snap: LibrarySnapshot) => Promise<void>
  importSnapshot: (snap: LibrarySnapshot) => void
  flush: () => Promise<void>

  createNotebook: (n: { name: string; description: string; icon: NotebookIcon; color: string; template?: TemplateKind }) => { notebookId: string; pageId: string }
  updateNotebook: (id: string, patch: Partial<Notebook>) => void
  deleteNotebook: (id: string) => void
  toggleFavorite: (id: string) => void
  duplicateNotebook: (id: string) => string

  createSection: (notebookId: string, title: string) => string
  updateSection: (id: string, patch: Partial<Section>) => void
  deleteSection: (id: string) => void
  moveSection: (id: string, toIndex: number) => void

  createPage: (notebookId: string, sectionId: string, opts?: { title?: string; template?: TemplateKind }) => string
  updatePage: (id: string, patch: Partial<Page>, opts?: { touch?: boolean }) => void
  setElements: (id: string, elements: CanvasElement[]) => void
  deletePage: (id: string) => void
  duplicatePage: (id: string) => string
  movePage: (id: string, sectionId: string, toIndex: number) => void
  markOpened: (pageId: string) => void
}

// ── Persistence bookkeeping ──────────────────────────────────────────────────
const dirty = { notebooks: new Set<string>(), sections: new Set<string>(), pages: new Set<string>() }
const removed = { notebooks: new Set<string>(), sections: new Set<string>(), pages: new Set<string>() }
let timer: ReturnType<typeof setTimeout> | null = null

const now = () => Date.now()

export const sortedSections = (sections: Record<string, Section>, notebookId: string) =>
  Object.values(sections)
    .filter((s) => s.notebookId === notebookId)
    .sort((a, b) => a.order - b.order)

export const sortedPages = (pages: Record<string, Page>, sectionId: string) =>
  Object.values(pages)
    .filter((p) => p.sectionId === sectionId)
    .sort((a, b) => a.order - b.order)

export const notebookPages = (pages: Record<string, Page>, notebookId: string) =>
  Object.values(pages).filter((p) => p.notebookId === notebookId)

export function newPage(notebookId: string, sectionId: string, order: number, title: string, template: TemplateKind): Page {
  const t = now()
  return {
    id: uid('p_'),
    notebookId,
    sectionId,
    title,
    order,
    template,
    templateOptions: { ...templateInfo(template).defaults },
    elements: [],
    viewport: { x: 80, y: 60, zoom: 1 },
    createdAt: t,
    updatedAt: t,
    lastOpenedAt: 0,
  }
}

export const useLibrary = create<LibraryState>((set, get) => {
  const schedule = () => {
    if (get().saveState !== 'saving') set({ saveState: 'pending' })
    if (timer) clearTimeout(timer)
    timer = setTimeout(() => void get().flush(), 600)
  }
  const mark = (kind: keyof typeof dirty, id: string) => {
    dirty[kind].add(id)
    schedule()
  }
  const unmark = (kind: keyof typeof dirty, id: string) => {
    dirty[kind].delete(id)
    removed[kind].add(id)
    schedule()
  }
  const touchNotebook = (id: string) => {
    const nb = get().notebooks[id]
    if (!nb) return
    set((s) => ({ notebooks: { ...s.notebooks, [id]: { ...nb, updatedAt: now() } } }))
    mark('notebooks', id)
  }

  return {
    loaded: false,
    notebooks: {},
    sections: {},
    pages: {},
    saveState: 'saved',
    lastSavedAt: now(),

    async init(seed) {
      let snap = await storage.loadAll().catch(() => ({ notebooks: [], sections: [], pages: [] }) as LibrarySnapshot)
      const seeded = await storage.getMeta<boolean>('seeded').catch(() => false)
      if (!snap.notebooks.length && !seeded) {
        snap = seed()
        await storage.putMany(snap).catch(() => {})
        await storage.setMeta('seeded', true).catch(() => {})
      }
      set({
        loaded: true,
        notebooks: Object.fromEntries(snap.notebooks.map((n) => [n.id, n])),
        sections: Object.fromEntries(snap.sections.map((n) => [n.id, n])),
        pages: Object.fromEntries(snap.pages.map((n) => [n.id, n])),
      })
    },

    async replaceAll(snap) {
      await storage.clearAll()
      await storage.putMany(snap)
      await storage.setMeta('seeded', true)
      set({
        notebooks: Object.fromEntries(snap.notebooks.map((n) => [n.id, n])),
        sections: Object.fromEntries(snap.sections.map((n) => [n.id, n])),
        pages: Object.fromEntries(snap.pages.map((n) => [n.id, n])),
      })
    },

    importSnapshot(snap) {
      set((s) => ({
        notebooks: { ...s.notebooks, ...Object.fromEntries(snap.notebooks.map((n) => [n.id, n])) },
        sections: { ...s.sections, ...Object.fromEntries(snap.sections.map((n) => [n.id, n])) },
        pages: { ...s.pages, ...Object.fromEntries(snap.pages.map((n) => [n.id, n])) },
      }))
      snap.notebooks.forEach((n) => mark('notebooks', n.id))
      snap.sections.forEach((n) => mark('sections', n.id))
      snap.pages.forEach((n) => mark('pages', n.id))
    },

    async flush() {
      if (timer) clearTimeout(timer)
      timer = null
      const s = get()
      const changes = {
        notebooks: [...dirty.notebooks].map((id) => s.notebooks[id]).filter(Boolean),
        sections: [...dirty.sections].map((id) => s.sections[id]).filter(Boolean),
        pages: [...dirty.pages].map((id) => s.pages[id]).filter(Boolean),
      }
      const dels = { notebooks: [...removed.notebooks], sections: [...removed.sections], pages: [...removed.pages] }
      Object.values(dirty).forEach((d) => d.clear())
      Object.values(removed).forEach((d) => d.clear())
      set({ saveState: 'saving' })
      try {
        await storage.putMany(changes)
        await storage.deleteMany(dels)
      } catch (e) {
        console.error('Basis: save failed', e)
      }
      const pending = Object.values(dirty).some((d) => d.size) || Object.values(removed).some((d) => d.size)
      set({ saveState: pending ? 'pending' : 'saved', lastSavedAt: now() })
    },

    createNotebook({ name, description, icon, color, template = 'engineering' }) {
      const t = now()
      const nb: Notebook = { id: uid('n_'), name, description, icon, color, favorite: false, createdAt: t, updatedAt: t, lastOpenedAt: t }
      const sec: Section = { id: uid('s_'), notebookId: nb.id, title: 'General', order: 0, collapsed: false }
      const page = newPage(nb.id, sec.id, 0, 'Untitled page', template)
      set((s) => ({
        notebooks: { ...s.notebooks, [nb.id]: nb },
        sections: { ...s.sections, [sec.id]: sec },
        pages: { ...s.pages, [page.id]: page },
      }))
      mark('notebooks', nb.id)
      mark('sections', sec.id)
      mark('pages', page.id)
      return { notebookId: nb.id, pageId: page.id }
    },

    updateNotebook(id, patch) {
      const nb = get().notebooks[id]
      if (!nb) return
      set((s) => ({ notebooks: { ...s.notebooks, [id]: { ...nb, ...patch, updatedAt: patch.lastOpenedAt ? nb.updatedAt : now() } } }))
      mark('notebooks', id)
    },

    deleteNotebook(id) {
      const s = get()
      const secIds = Object.values(s.sections).filter((x) => x.notebookId === id).map((x) => x.id)
      const pageIds = Object.values(s.pages).filter((x) => x.notebookId === id).map((x) => x.id)
      const notebooks = { ...s.notebooks }
      const sections = { ...s.sections }
      const pages = { ...s.pages }
      delete notebooks[id]
      secIds.forEach((x) => delete sections[x])
      pageIds.forEach((x) => delete pages[x])
      set({ notebooks, sections, pages })
      unmark('notebooks', id)
      secIds.forEach((x) => unmark('sections', x))
      pageIds.forEach((x) => unmark('pages', x))
    },

    toggleFavorite(id) {
      const nb = get().notebooks[id]
      if (!nb) return
      set((s) => ({ notebooks: { ...s.notebooks, [id]: { ...nb, favorite: !nb.favorite } } }))
      mark('notebooks', id)
    },

    duplicateNotebook(id) {
      const s = get()
      const nb = s.notebooks[id]
      const t = now()
      const copy: Notebook = { ...nb, id: uid('n_'), name: `${nb.name} copy`, favorite: false, createdAt: t, updatedAt: t }
      const secMap = new Map<string, string>()
      const newSections = sortedSections(s.sections, id).map((sec) => {
        const nid = uid('s_')
        secMap.set(sec.id, nid)
        return { ...sec, id: nid, notebookId: copy.id }
      })
      const newPages = notebookPages(s.pages, id).map((p) => ({
        ...structuredClone(p),
        id: uid('p_'),
        notebookId: copy.id,
        sectionId: secMap.get(p.sectionId)!,
      }))
      get().importSnapshot({ notebooks: [copy], sections: newSections, pages: newPages })
      return copy.id
    },

    createSection(notebookId, title) {
      const order = sortedSections(get().sections, notebookId).length
      const sec: Section = { id: uid('s_'), notebookId, title, order, collapsed: false }
      set((s) => ({ sections: { ...s.sections, [sec.id]: sec } }))
      mark('sections', sec.id)
      touchNotebook(notebookId)
      return sec.id
    },

    updateSection(id, patch) {
      const sec = get().sections[id]
      if (!sec) return
      set((s) => ({ sections: { ...s.sections, [id]: { ...sec, ...patch } } }))
      mark('sections', id)
    },

    deleteSection(id) {
      const s = get()
      const sec = s.sections[id]
      if (!sec) return
      const pageIds = Object.values(s.pages).filter((p) => p.sectionId === id).map((p) => p.id)
      const sections = { ...s.sections }
      const pages = { ...s.pages }
      delete sections[id]
      pageIds.forEach((p) => delete pages[p])
      set({ sections, pages })
      unmark('sections', id)
      pageIds.forEach((p) => unmark('pages', p))
      touchNotebook(sec.notebookId)
    },

    moveSection(id, toIndex) {
      const s = get()
      const sec = s.sections[id]
      const list = sortedSections(s.sections, sec.notebookId).filter((x) => x.id !== id)
      list.splice(Math.max(0, Math.min(toIndex, list.length)), 0, sec)
      const sections = { ...s.sections }
      list.forEach((x, i) => {
        sections[x.id] = { ...x, order: i }
        mark('sections', x.id)
      })
      set({ sections })
    },

    createPage(notebookId, sectionId, opts = {}) {
      const s = get()
      const order = sortedPages(s.pages, sectionId).length
      const page = newPage(notebookId, sectionId, order, opts.title ?? `Page ${order + 1}`, opts.template ?? 'engineering')
      set((st) => ({ pages: { ...st.pages, [page.id]: page } }))
      mark('pages', page.id)
      touchNotebook(notebookId)
      return page.id
    },

    updatePage(id, patch, { touch = true } = {}) {
      const p = get().pages[id]
      if (!p) return
      set((s) => ({ pages: { ...s.pages, [id]: { ...p, ...patch, updatedAt: touch ? now() : p.updatedAt } } }))
      mark('pages', id)
      if (touch) touchNotebook(p.notebookId)
    },

    setElements(id, elements) {
      get().updatePage(id, { elements })
    },

    deletePage(id) {
      const s = get()
      const p = s.pages[id]
      if (!p) return
      const pages = { ...s.pages }
      delete pages[id]
      // re-number remaining pages in the section
      sortedPages(pages, p.sectionId).forEach((x, i) => {
        if (x.order !== i) {
          pages[x.id] = { ...x, order: i }
          mark('pages', x.id)
        }
      })
      set({ pages })
      unmark('pages', id)
      touchNotebook(p.notebookId)
    },

    duplicatePage(id) {
      const s = get()
      const p = s.pages[id]
      const copy: Page = { ...structuredClone(p), id: uid('p_'), title: `${p.title} copy`, createdAt: now(), updatedAt: now() }
      set((st) => ({ pages: { ...st.pages, [copy.id]: copy } }))
      get().movePage(copy.id, p.sectionId, p.order + 1)
      return copy.id
    },

    movePage(id, sectionId, toIndex) {
      const s = get()
      const p = s.pages[id]
      if (!p) return
      const pages = { ...s.pages }
      const fromSection = p.sectionId
      const target = sortedPages(pages, sectionId).filter((x) => x.id !== id)
      target.splice(Math.max(0, Math.min(toIndex, target.length)), 0, { ...p, sectionId })
      target.forEach((x, i) => {
        pages[x.id] = { ...pages[x.id], sectionId, order: i }
        mark('pages', x.id)
      })
      if (fromSection !== sectionId) {
        sortedPages(pages, fromSection).forEach((x, i) => {
          pages[x.id] = { ...x, order: i }
          mark('pages', x.id)
        })
      }
      set({ pages })
    },

    markOpened(pageId) {
      const p = get().pages[pageId]
      if (!p) return
      const t = now()
      set((s) => ({
        pages: { ...s.pages, [pageId]: { ...p, lastOpenedAt: t } },
        notebooks: s.notebooks[p.notebookId]
          ? { ...s.notebooks, [p.notebookId]: { ...s.notebooks[p.notebookId], lastOpenedAt: t } }
          : s.notebooks,
      }))
      mark('pages', pageId)
      mark('notebooks', p.notebookId)
    },
  }
})

export type { TemplateOptions }
