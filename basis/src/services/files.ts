// Local file handling: attachments live as Blobs in IndexedDB; images get
// cached object URLs. Replace with the native file provider in the iPad app.

import type { StoredFile, StoredFileMeta } from '../models'
import { uid } from './id'
import { storage } from './storage'

const urlCache = new Map<string, string>()
const listeners = new Set<() => void>()

export const fileEvents = {
  subscribe(fn: () => void) {
    listeners.add(fn)
    return () => listeners.delete(fn)
  },
  emit() {
    listeners.forEach((l) => l())
  },
}

export async function saveFile(file: Blob & { name?: string }, notebookId: string | null, name?: string): Promise<StoredFile> {
  const f: StoredFile = {
    id: uid('f_'),
    notebookId,
    name: name ?? file.name ?? 'file',
    type: file.type || 'application/octet-stream',
    size: file.size,
    blob: file,
    createdAt: Date.now(),
  }
  await storage.putFile(f)
  fileEvents.emit()
  return f
}

export async function fileUrl(id: string): Promise<string | null> {
  const cached = urlCache.get(id)
  if (cached) return cached
  const f = await storage.getFile(id)
  if (!f) return null
  const url = URL.createObjectURL(f.blob)
  urlCache.set(id, url)
  return url
}

export async function listFiles(): Promise<StoredFileMeta[]> {
  const all = await storage.listFiles()
  return all.map(({ blob: _b, ...meta }) => meta).sort((a, b) => b.createdAt - a.createdAt)
}

export async function deleteFile(id: string) {
  await storage.deleteFile(id)
  const u = urlCache.get(id)
  if (u) URL.revokeObjectURL(u)
  urlCache.delete(id)
  fileEvents.emit()
}

export async function openFile(id: string) {
  const url = await fileUrl(id)
  if (url) window.open(url, '_blank')
}

export function pickFiles(accept: string, multiple = false): Promise<File[]> {
  return new Promise((resolve) => {
    const input = document.createElement('input')
    input.type = 'file'
    input.accept = accept
    input.multiple = multiple
    input.style.display = 'none'
    input.onchange = () => {
      resolve(input.files ? [...input.files] : [])
      input.remove()
    }
    document.body.appendChild(input)
    input.click()
  })
}

export function imageSize(url: string): Promise<{ w: number; h: number }> {
  return new Promise((resolve) => {
    const img = new Image()
    img.onload = () => resolve({ w: img.naturalWidth, h: img.naturalHeight })
    img.onerror = () => resolve({ w: 400, h: 300 })
    img.src = url
  })
}

export function formatBytes(n: number) {
  if (n < 1024) return `${n} B`
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`
  return `${(n / 1024 / 1024).toFixed(1)} MB`
}

export function blobToDataUrl(b: Blob): Promise<string> {
  return new Promise((res, rej) => {
    const r = new FileReader()
    r.onload = () => res(r.result as string)
    r.onerror = rej
    r.readAsDataURL(b)
  })
}

export async function dataUrlToBlob(url: string): Promise<Blob> {
  return (await fetch(url)).blob()
}

export function download(blob: Blob, filename: string) {
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = filename
  document.body.appendChild(a)
  a.click()
  setTimeout(() => {
    URL.revokeObjectURL(a.href)
    a.remove()
  }, 1000)
}
