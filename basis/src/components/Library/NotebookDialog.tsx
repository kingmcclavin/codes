import { useState } from 'react'
import type { NotebookIcon, TemplateKind } from '../../models'
import { TEMPLATES } from '../../models/templates'
import { useLibrary } from '../../store/library'
import { useUI } from '../../store/ui'
import { Icon, NOTEBOOK_ICONS } from '../common/Icon'
import { Modal } from '../common/Popover'
import { NotebookCover } from './NotebookCard'

export const NOTEBOOK_COLORS = ['#ff6b2c', '#3b82f6', '#14b8a6', '#a855f7', '#eab308', '#ef4444', '#64748b', '#22c55e']

export function NotebookDialog() {
  const dialog = useUI((s) => s.notebookDialog)
  const close = () => useUI.getState().setNotebookDialog(null)
  const existing = useLibrary((s) => (dialog?.mode === 'edit' ? s.notebooks[dialog.id] : undefined))
  const [name, setName] = useState(existing?.name ?? '')
  const [description, setDescription] = useState(existing?.description ?? '')
  const [icon, setIcon] = useState<NotebookIcon>(existing?.icon ?? 'atom')
  const [color, setColor] = useState(existing?.color ?? NOTEBOOK_COLORS[0])
  const [template, setTemplate] = useState<TemplateKind>(useUI.getState().settings.defaultTemplate)

  if (!dialog) return null

  const submit = () => {
    const n = name.trim() || 'Untitled notebook'
    if (dialog.mode === 'edit') {
      useLibrary.getState().updateNotebook(dialog.id, { name: n, description: description.trim(), icon, color })
      close()
      return
    }
    const { notebookId, pageId } = useLibrary.getState().createNotebook({ name: n, description: description.trim(), icon, color, template })
    close()
    useUI.getState().navigate({ view: 'notebook', notebookId, pageId })
  }

  return (
    <Modal
      title={dialog.mode === 'edit' ? 'Notebook details' : 'New notebook'}
      onClose={close}
      footer={
        <>
          <button className="btn ghost" onClick={close}>
            Cancel
          </button>
          <button className="btn primary" onClick={submit}>
            {dialog.mode === 'edit' ? 'Save' : 'Create notebook'}
          </button>
        </>
      }
    >
      <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
        <div style={{ width: 96, flex: 'none' }}>
          <NotebookCover nb={{ icon, color }} />
        </div>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 12 }}>
          <label className="field">
            <span className="label">Name</span>
            <input className="input" autoFocus value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Thermodynamics" onKeyDown={(e) => e.key === 'Enter' && submit()} />
          </label>
          <label className="field">
            <span className="label">Description</span>
            <input className="input" value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Course, project or topic" onKeyDown={(e) => e.key === 'Enter' && submit()} />
          </label>
        </div>
      </div>
      <div className="field">
        <span className="label">Icon</span>
        <div className="icon-grid">
          {NOTEBOOK_ICONS.map((i) => (
            <button key={i} className={`icon-btn ${icon === i ? 'active' : ''}`} onClick={() => setIcon(i)} aria-label={i}>
              <Icon name={i} size={20} stroke={1.4} />
            </button>
          ))}
        </div>
      </div>
      <div className="field">
        <span className="label">Colour</span>
        <div className="swatches">
          {NOTEBOOK_COLORS.map((c) => (
            <button key={c} className={`swatch ${color === c ? 'on' : ''}`} style={{ background: c }} onClick={() => setColor(c)} aria-label={c} />
          ))}
        </div>
      </div>
      {dialog.mode === 'create' && (
        <div className="field">
          <span className="label">Default page template</span>
          <div className="template-chips">
            {TEMPLATES.filter((t) => t.kind !== 'custom').map((t) => (
              <button key={t.kind} className={`chip ${template === t.kind ? 'on' : ''}`} onClick={() => setTemplate(t.kind)}>
                {t.name}
              </button>
            ))}
          </div>
        </div>
      )}
    </Modal>
  )
}

