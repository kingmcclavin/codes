import { useUI, type DockPanel } from '../../store/ui'
import { Calculator } from '../Calculator/Calculator'
import { Icon } from '../common/Icon'
import { EngineeringTools } from '../EngineeringTools/EngineeringTools'
import { FilesPanel } from '../Files/FilesPanel'
import { VariablesPanel } from './VariablesPanel'
import './panels.css'

const TABS: { id: DockPanel; label: string; icon: string }[] = [
  { id: 'calculator', label: 'Calculator', icon: 'calculator' },
  { id: 'variables', label: 'Variables', icon: 'variable' },
  { id: 'tools', label: 'Tools', icon: 'tools' },
  { id: 'files', label: 'Files', icon: 'files' },
]

export function Dock({ notebookId, pageId, overlay }: { notebookId: string; pageId?: string; overlay: boolean }) {
  const dock = useUI((s) => s.dock)
  const width = useUI((s) => s.dockWidth)
  if (!dock) return null

  const startResize = (e: React.PointerEvent) => {
    e.preventDefault()
    const x0 = e.clientX
    const w0 = width
    const move = (ev: PointerEvent) => useUI.getState().setDockWidth(w0 - (ev.clientX - x0))
    const up = () => {
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
      document.body.style.cursor = ''
    }
    document.body.style.cursor = 'col-resize'
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
  }

  return (
    <aside className={`dock ui ${overlay ? 'overlay' : ''}`} style={{ width: overlay ? undefined : width }}>
      {!overlay && <div className="dock-resizer" onPointerDown={startResize} />}
      <div className="dock-tabs">
        {TABS.map((t) => (
          <button key={t.id} className={`dock-tab ${dock === t.id ? 'on' : ''}`} onClick={() => useUI.getState().setDock(t.id)}>
            <Icon name={t.icon} size={15} />
            <span>{t.label}</span>
          </button>
        ))}
        <button className="icon-btn sm dock-close" onClick={() => useUI.getState().setDock(null)} aria-label="Close panel">
          <Icon name="close" size={15} />
        </button>
      </div>
      <div className="dock-body" key={dock}>
        {dock === 'calculator' && <Calculator pageId={pageId} />}
        {dock === 'variables' && <VariablesPanel pageId={pageId} />}
        {dock === 'tools' && <EngineeringTools pageId={pageId} />}
        {dock === 'files' && <FilesPanel notebookId={notebookId} pageId={pageId} />}
      </div>
    </aside>
  )
}
