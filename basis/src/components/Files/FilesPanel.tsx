// A simple local file browser. Files live in IndexedDB (see services/files).
import { useEffect, useState } from 'react'
import type { StoredFileMeta } from '../../models'
import { importPdf, insertImageFile } from '../../services/canvas/insert'
import { deleteFile, fileEvents, formatBytes, listFiles, openFile, pickFiles, saveFile } from '../../services/files'
import { storage } from '../../services/storage'
import { relativeTime } from '../../services/time'
import { useLibrary } from '../../store/library'
import { useUI } from '../../store/ui'
import { Icon } from '../common/Icon'
import '../Panels/panels.css'

export function FilesPanel({ notebookId, pageId }: { notebookId: string; pageId?: string }) {
  const [files, setFiles] = useState<StoredFileMeta[]>([])
  const [scope, setScope] = useState<'notebook' | 'all'>('notebook')
  const [busy, setBusy] = useState<string | null>(null)
  const notebooks = useLibrary((s) => s.notebooks)

  useEffect(() => {
    const load = () => void listFiles().then(setFiles)
    load()
    const off = fileEvents.subscribe(load)
    return () => {
      off()
    }
  }, [])

  const shown = files.filter((f) => scope === 'all' || f.notebookId === notebookId)

  const attach = async () => {
    const picked = await pickFiles('*/*', true)
    for (const f of picked) await saveFile(f, notebookId)
    if (picked.length) useUI.getState().toast(`${picked.length} file${picked.length > 1 ? 's' : ''} attached`)
  }
  const addImage = async () => {
    const [f] = await pickFiles('image/*')
    if (f && pageId) await insertImageFile(pageId, f)
  }
  const addPdf = async () => {
    const [f] = await pickFiles('application/pdf')
    if (!f) return
    setBusy('Rendering PDF pages…')
    try {
      const first = await importPdf(notebookId, f, (d, t) => setBusy(`Rendering page ${d} of ${t}…`))
      if (first) useUI.getState().navigate({ view: 'notebook', notebookId, pageId: first })
      useUI.getState().toast('PDF imported as a new section')
    } catch (e) {
      console.error(e)
      alert('Could not import that PDF.')
    }
    setBusy(null)
  }
  const placeImage = async (f: StoredFileMeta) => {
    if (!pageId) return
    const stored = await storage.getFile(f.id)
    if (stored) await insertImageFile(pageId, stored.blob)
  }

  const icon = (t: string) => (t.startsWith('image/') ? 'image' : t === 'application/pdf' ? 'pdf' : 'file')

  return (
    <div className="files-panel">
      <div className="files-actions">
        <button className="btn sm" onClick={addPdf} disabled={!!busy}>
          <Icon name="pdf" size={15} /> Import PDF
        </button>
        <button className="btn sm" onClick={addImage} disabled={!pageId}>
          <Icon name="image" size={15} /> Image
        </button>
        <button className="btn sm" onClick={attach}>
          <Icon name="attach" size={15} /> Attach
        </button>
      </div>
      {busy && <div className="files-busy mono">{busy}</div>}
      <div className="files-scope">
        <div className="segmented">
          <button className={scope === 'notebook' ? 'on' : ''} onClick={() => setScope('notebook')}>
            This notebook
          </button>
          <button className={scope === 'all' ? 'on' : ''} onClick={() => setScope('all')}>
            All files
          </button>
        </div>
        <span className="mono faint" style={{ fontSize: 10.5 }}>
          {shown.length} item{shown.length === 1 ? '' : 's'}
        </span>
      </div>
      {shown.length === 0 ? (
        <div className="empty">
          <Icon name="files" size={22} />
          No files yet. Import a lecture PDF to annotate it, or attach datasheets and references.
        </div>
      ) : (
        <div className="file-list">
          {shown.map((f) => (
            <div key={f.id} className="file-row">
              <span className={`file-icon ${icon(f.type)}`}>
                <Icon name={icon(f.type)} size={16} />
              </span>
              <button className="file-main" onClick={() => void openFile(f.id)} title="Open">
                <span className="file-name">{f.name}</span>
                <span className="file-meta mono">
                  {formatBytes(f.size)} · {relativeTime(f.createdAt)}
                  {scope === 'all' && f.notebookId && notebooks[f.notebookId] ? ` · ${notebooks[f.notebookId].name}` : ''}
                </span>
              </button>
              {f.type.startsWith('image/') && pageId && (
                <button className="icon-btn sm" onClick={() => void placeImage(f)} data-tip="Place on page" aria-label="Place on page">
                  <Icon name="insert" size={14} />
                </button>
              )}
              <button
                className="icon-btn sm"
                onClick={() => confirm(`Delete “${f.name}”? Pages using it will show a placeholder.`) && void deleteFile(f.id)}
                aria-label="Delete file"
              >
                <Icon name="trash" size={14} />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
