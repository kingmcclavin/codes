// Offline-first persistence in IndexedDB. Every entity type lives in its own
// object store so pages can be saved individually. This is the seam where a
// sync engine (CloudKit / CRDT) would plug in later.

import { openDB, type DBSchema, type IDBPDatabase } from 'idb'
import type { Notebook, Page, Section, Settings, StoredFile } from '../models'

interface BasisDB extends DBSchema {
  notebooks: { key: string; value: Notebook }
  sections: { key: string; value: Section; indexes: { notebookId: string } }
  pages: { key: string; value: Page; indexes: { notebookId: string } }
  files: { key: string; value: StoredFile; indexes: { notebookId: string } }
  meta: { key: string; value: unknown }
}

let dbp: Promise<IDBPDatabase<BasisDB>> | null = null

function db() {
  dbp ??= openDB<BasisDB>('basis', 1, {
    upgrade(d) {
      d.createObjectStore('notebooks', { keyPath: 'id' })
      d.createObjectStore('sections', { keyPath: 'id' }).createIndex('notebookId', 'notebookId')
      d.createObjectStore('pages', { keyPath: 'id' }).createIndex('notebookId', 'notebookId')
      d.createObjectStore('files', { keyPath: 'id' }).createIndex('notebookId', 'notebookId')
      d.createObjectStore('meta')
    },
  })
  return dbp
}

export interface LibrarySnapshot {
  notebooks: Notebook[]
  sections: Section[]
  pages: Page[]
}

export const storage = {
  async loadAll(): Promise<LibrarySnapshot> {
    const d = await db()
    const [notebooks, sections, pages] = await Promise.all([d.getAll('notebooks'), d.getAll('sections'), d.getAll('pages')])
    return { notebooks, sections, pages }
  },

  async putMany(changes: { notebooks?: Notebook[]; sections?: Section[]; pages?: Page[] }) {
    const d = await db()
    const tx = d.transaction(['notebooks', 'sections', 'pages'], 'readwrite')
    for (const n of changes.notebooks ?? []) tx.objectStore('notebooks').put(n)
    for (const s of changes.sections ?? []) tx.objectStore('sections').put(s)
    for (const p of changes.pages ?? []) tx.objectStore('pages').put(p)
    await tx.done
  },

  async deleteMany(ids: { notebooks?: string[]; sections?: string[]; pages?: string[]; files?: string[] }) {
    const d = await db()
    const tx = d.transaction(['notebooks', 'sections', 'pages', 'files'], 'readwrite')
    for (const id of ids.notebooks ?? []) tx.objectStore('notebooks').delete(id)
    for (const id of ids.sections ?? []) tx.objectStore('sections').delete(id)
    for (const id of ids.pages ?? []) tx.objectStore('pages').delete(id)
    for (const id of ids.files ?? []) tx.objectStore('files').delete(id)
    await tx.done
  },

  async clearAll() {
    const d = await db()
    const tx = d.transaction(['notebooks', 'sections', 'pages', 'files', 'meta'], 'readwrite')
    await Promise.all([
      tx.objectStore('notebooks').clear(),
      tx.objectStore('sections').clear(),
      tx.objectStore('pages').clear(),
      tx.objectStore('files').clear(),
      tx.objectStore('meta').clear(),
    ])
    await tx.done
  },

  // Files
  async putFile(f: StoredFile) {
    await (await db()).put('files', f)
  },
  async getFile(id: string) {
    return (await db()).get('files', id)
  },
  async listFiles(): Promise<StoredFile[]> {
    return (await db()).getAll('files')
  },
  async deleteFile(id: string) {
    await (await db()).delete('files', id)
  },

  // Meta
  async getMeta<T>(key: string): Promise<T | undefined> {
    return (await (await db()).get('meta', key)) as T | undefined
  },
  async setMeta(key: string, value: unknown) {
    await (await db()).put('meta', value, key)
  },
}

// Settings are tiny and needed synchronously at boot, so they live in localStorage.
const SETTINGS_KEY = 'basis.settings'
export function loadSettings(): Partial<Settings> {
  try {
    return JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}')
  } catch {
    return {}
  }
}
export function saveSettings(s: Settings) {
  try {
    localStorage.setItem(SETTINGS_KEY, JSON.stringify(s))
  } catch {
    /* private mode */
  }
}

export async function storageEstimate(): Promise<{ usage: number; quota: number } | null> {
  try {
    const e = await navigator.storage?.estimate?.()
    return e ? { usage: e.usage ?? 0, quota: e.quota ?? 0 } : null
  } catch {
    return null
  }
}

export async function requestPersistence() {
  try {
    await navigator.storage?.persist?.()
  } catch {
    /* ignore */
  }
}
