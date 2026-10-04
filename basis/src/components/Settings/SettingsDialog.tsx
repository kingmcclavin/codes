import { useEffect, useState } from 'react'
import type { TemplateKind, ThemePreference, TouchPolicy } from '../../models'
import { TEMPLATES } from '../../models/templates'
import { formatBytes } from '../../services/files'
import { pointerPolicy } from '../../services/input/pointerPolicy'
import { storage, storageEstimate } from '../../services/storage'
import { useLibrary } from '../../store/library'
import { useUI } from '../../store/ui'
import { createDemoLibrary } from '../../demo/demo'
import { Wordmark } from '../Brand/Logo'
import { Modal } from '../common/Popover'

function Row({ title, desc, children }: { title: string; desc?: string; children: React.ReactNode }) {
  return (
    <div className="set-row">
      <div className="set-text">
        <div className="set-title">{title}</div>
        {desc && <div className="set-desc">{desc}</div>}
      </div>
      <div className="set-control">{children}</div>
    </div>
  )
}

export function SettingsDialog() {
  const open = useUI((s) => s.settingsOpen)
  const settings = useUI((s) => s.settings)
  const [est, setEst] = useState<{ usage: number; quota: number } | null>(null)
  useEffect(() => {
    if (open) void storageEstimate().then(setEst)
  }, [open])
  if (!open) return null
  const ui = useUI.getState()
  const close = () => ui.setSettingsOpen(false)

  const resetDemo = async () => {
    if (!confirm('Replace everything with the demo notebooks? Your current notebooks will be deleted.')) return
    await useLibrary.getState().replaceAll(createDemoLibrary())
    ui.navigate({ view: 'library' })
    close()
    ui.toast('Demo content restored')
  }
  const clearAll = async () => {
    if (!confirm('Delete ALL notebooks, pages and files stored in this browser? This cannot be undone.')) return
    await useLibrary.getState().replaceAll({ notebooks: [], sections: [], pages: [] })
    await storage.clearAll()
    await storage.setMeta('seeded', true)
    ui.navigate({ view: 'library' })
    close()
  }

  return (
    <Modal title="Settings" onClose={close} width={560}>
      <div className="set-group">
        <div className="label">Appearance</div>
        <Row title="Theme" desc="Dark charcoal paper or light cream paper">
          <div className="segmented">
            {(['light', 'dark', 'system'] as ThemePreference[]).map((t) => (
              <button key={t} className={settings.theme === t ? 'on' : ''} onClick={() => ui.setSettings({ theme: t })}>
                {t[0].toUpperCase() + t.slice(1)}
              </button>
            ))}
          </div>
        </Row>
        <Row title="Default page template">
          <select className="select" style={{ width: 170 }} value={settings.defaultTemplate} onChange={(e) => ui.setSettings({ defaultTemplate: e.target.value as TemplateKind })}>
            {TEMPLATES.map((t) => (
              <option key={t.kind} value={t.kind}>
                {t.name}
              </option>
            ))}
          </select>
        </Row>
      </div>

      <div className="set-group">
        <div className="label">Apple Pencil &amp; touch</div>
        <Row title="Finger input" desc={pointerPolicy.penSeen ? 'Apple Pencil detected — fingers navigate in Auto mode.' : 'Auto: fingers draw until a Pencil is detected, then they pan & zoom (palm rejection).'}>
          <div className="segmented">
            {(['auto', 'draw', 'navigate'] as TouchPolicy[]).map((t) => (
              <button key={t} className={settings.touchPolicy === t ? 'on' : ''} onClick={() => ui.setSettings({ touchPolicy: t })}>
                {t === 'auto' ? 'Auto' : t === 'draw' ? 'Draw' : 'Pan'}
              </button>
            ))}
          </div>
        </Row>
      </div>

      <div className="set-group">
        <div className="label">Calculations</div>
        <Row title="Significant figures" desc="Used for variable results and tools">
          <div className="segmented">
            {[3, 4, 5, 6].map((p) => (
              <button key={p} className={settings.precision === p ? 'on' : ''} onClick={() => ui.setSettings({ precision: p })}>
                {p}
              </button>
            ))}
          </div>
        </Row>
      </div>

      <div className="set-group">
        <div className="label">Storage</div>
        <Row title="Stored on this device" desc={est ? `${formatBytes(est.usage)} used of ${formatBytes(est.quota)} available. Works offline; no account needed.` : 'Notebooks are saved locally in IndexedDB.'}>
          <span />
        </Row>
        <div className="set-actions">
          <button className="btn sm" onClick={resetDemo}>
            Restore demo notebooks
          </button>
          <button className="btn sm danger" onClick={clearAll}>
            Erase all data
          </button>
        </div>
      </div>

      <div className="set-about">
        <Wordmark size={18} />
        <span className="mono faint">Web prototype · v0.1</span>
      </div>
    </Modal>
  )
}

const SHORTCUTS: [string, string][] = [
  ['⌘ Z', 'Undo'],
  ['⇧ ⌘ Z', 'Redo'],
  ['⌘ S', 'Save now'],
  ['⌘ F  /  ⌘ K', 'Search'],
  ['⌘ \\', 'Toggle sidebar'],
  ['V', 'Select'],
  ['H  /  Space-drag', 'Pan'],
  ['P', 'Pen'],
  ['M', 'Highlighter'],
  ['E', 'Eraser'],
  ['T', 'Text'],
  ['S', 'Shapes'],
  ['L', 'Line'],
  ['A', 'Arrow'],
  ['Q  /  =', 'Equation'],
  ['I', 'Image'],
  ['Enter', 'Edit selected block'],
  ['⌫', 'Delete selection'],
  ['⌘ D', 'Duplicate'],
  ['⌘ C / ⌘ V', 'Copy / paste'],
  ['⌘ A', 'Select all'],
  ['⌘ + / ⌘ −', 'Zoom in / out'],
  ['⌘ 0', 'Zoom to 100%'],
  ['⌘ 1', 'Fit content'],
  ['⇧ + drag', 'Constrain shapes / angles'],
]

export function ShortcutsDialog() {
  const open = useUI((s) => s.shortcutsOpen)
  if (!open) return null
  return (
    <Modal title="Keyboard shortcuts" onClose={() => useUI.getState().setShortcutsOpen(false)} width={560}>
      <div className="shortcut-grid">
        {SHORTCUTS.map(([k, d]) => (
          <div key={d} className="shortcut-row">
            <span>{d}</span>
            <span className="kbd">{k}</span>
          </div>
        ))}
      </div>
    </Modal>
  )
}
