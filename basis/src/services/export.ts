// Import / export. `.basis` files are JSON bundles of a notebook, its sections,
// pages and attached files (base64). Page export to PDF uses the browser's print
// pipeline (see PrintView) — replace with PDFKit rendering in the native app.

import type { Notebook, Page, Section, StoredFile } from '../models'
import { uid } from './id'
import { blobToDataUrl, dataUrlToBlob, download } from './files'
import { storage, type LibrarySnapshot } from './storage'

interface BasisBundle {
  format: 'basis-notebook'
  version: 1
  exportedAt: number
  notebook: Notebook
  sections: Section[]
  pages: Page[]
  files: (Omit<StoredFile, 'blob'> & { data: string })[]
}

const safeName = (s: string) => s.replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '-') || 'notebook'

export async function exportNotebook(nb: Notebook, sections: Section[], pages: Page[]) {
  const fileIds = new Set<string>()
  for (const p of pages) for (const e of p.elements) if (e.type === 'image' && e.fileId) fileIds.add(e.fileId)
  const all = await storage.listFiles()
  const files = await Promise.all(
    all
      .filter((f) => fileIds.has(f.id) || f.notebookId === nb.id)
      .map(async ({ blob, ...meta }) => ({ ...meta, data: await blobToDataUrl(blob) })),
  )
  const bundle: BasisBundle = { format: 'basis-notebook', version: 1, exportedAt: Date.now(), notebook: nb, sections, pages, files }
  download(new Blob([JSON.stringify(bundle)], { type: 'application/json' }), `${safeName(nb.name)}.basis`)
}

export function exportPageJson(page: Page) {
  download(new Blob([JSON.stringify({ format: 'basis-page', version: 1, page }, null, 2)], { type: 'application/json' }), `${safeName(page.title)}.basis-page.json`)
}

/** Parse a .basis bundle, re-keying every id so imports never collide. */
export async function importNotebookFile(file: File): Promise<LibrarySnapshot> {
  const bundle = JSON.parse(await file.text()) as BasisBundle
  if (bundle.format !== 'basis-notebook') throw new Error('Not a Basis notebook file')
  const nbId = uid('n_')
  const secMap = new Map<string, string>()
  const fileMap = new Map<string, string>()
  for (const f of bundle.files ?? []) {
    const id = uid('f_')
    fileMap.set(f.id, id)
    const blob = await dataUrlToBlob(f.data)
    await storage.putFile({ id, notebookId: nbId, name: f.name, type: f.type, size: f.size, createdAt: f.createdAt, blob })
  }
  const sections = bundle.sections.map((s) => {
    const id = uid('s_')
    secMap.set(s.id, id)
    return { ...s, id, notebookId: nbId }
  })
  const pages = bundle.pages.map((p) => ({
    ...p,
    id: uid('p_'),
    notebookId: nbId,
    sectionId: secMap.get(p.sectionId) ?? sections[0]?.id,
    elements: p.elements.map((e) => (e.type === 'image' && e.fileId ? { ...e, fileId: fileMap.get(e.fileId) ?? e.fileId } : e)),
  }))
  const t = Date.now()
  return { notebooks: [{ ...bundle.notebook, id: nbId, updatedAt: t, lastOpenedAt: t }], sections, pages }
}
