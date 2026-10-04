// Inserting images / PDFs onto pages. PDF rasterisation uses pdf.js in the
// browser; a native build would use PDFKit and keep pages as vector PDFs.

import { useCanvas } from '../../store/canvas'
import { useLibrary } from '../../store/library'
import { fileUrl, imageSize, pickFiles, saveFile } from '../files'
import { centered, make } from './factories'

export async function insertImageFromPicker(pageId: string, at?: { x: number; y: number }) {
  const [file] = await pickFiles('image/*')
  if (file) await insertImageFile(pageId, file, at)
}

export async function insertImageFile(pageId: string, file: File | Blob, at?: { x: number; y: number }) {
  const page = useLibrary.getState().pages[pageId]
  if (!page) return
  const stored = await saveFile(file, page.notebookId)
  const url = await fileUrl(stored.id)
  const { w, h } = await imageSize(url!)
  const scale = Math.min(1, 520 / w)
  const W = Math.round(w * scale), H = Math.round(h * scale)
  const c = at ?? useCanvas.getState().centerProvider?.() ?? { x: 200, y: 200 }
  const el = make.image(at ? c : centered(c, W, H), W, H, { fileId: stored.id })
  useCanvas.getState().commit(pageId, [...useLibrary.getState().pages[pageId].elements, el])
  useCanvas.setState({ tool: 'select', selection: [el.id] })
}

/** Import a PDF as a new section: one page per PDF page, each with the page image locked behind the ink. */
export async function importPdf(notebookId: string, file: File, onProgress?: (done: number, total: number) => void): Promise<string | null> {
  // The legacy build includes polyfills so it runs on older iPad Safari versions.
  const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs')
  const worker = await import('pdfjs-dist/legacy/build/pdf.worker.min.mjs?url')
  pdfjs.GlobalWorkerOptions.workerSrc = worker.default
  const data = new Uint8Array(await file.arrayBuffer())
  const doc = await pdfjs.getDocument({ data }).promise
  await saveFile(file, notebookId)
  const lib = useLibrary.getState()
  const sectionId = lib.createSection(notebookId, file.name.replace(/\.pdf$/i, ''))
  let firstPage: string | null = null
  for (let i = 1; i <= doc.numPages; i++) {
    const pdfPage = await doc.getPage(i)
    const base = pdfPage.getViewport({ scale: 1 })
    const worldScale = 900 / base.width
    const vp = pdfPage.getViewport({ scale: worldScale * 2 }) // 2× for crisp zoom
    const canvas = document.createElement('canvas')
    canvas.width = Math.ceil(vp.width)
    canvas.height = Math.ceil(vp.height)
    await pdfPage.render({ canvasContext: canvas.getContext('2d')!, viewport: vp }).promise
    const blob: Blob = await new Promise((res) => canvas.toBlob((b) => res(b!), 'image/png'))
    const stored = await saveFile(blob, notebookId, `${file.name} — p${i}.png`)
    const pageId = lib.createPage(notebookId, sectionId, { title: `Page ${i}`, template: 'blank' })
    const W = Math.round(base.width * worldScale), H = Math.round(base.height * worldScale)
    const img = make.image({ x: 0, y: 0 }, W, H, { fileId: stored.id, background: true, locked: true })
    useLibrary.getState().updatePage(pageId, { elements: [img], viewport: { x: 60, y: 40, zoom: 1 } })
    firstPage ??= pageId
    onProgress?.(i, doc.numPages)
  }
  return firstPage
}
