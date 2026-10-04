import { useState } from 'react'
import type { CalcElement } from '../../models'
import { quickConvert } from '../../services/units'
import { rewriteVariable } from '../../services/calculations/variables'
import { centered, make } from '../../services/canvas/factories'
import { updateElement, useCanvas } from '../../store/canvas'
import { useLibrary } from '../../store/library'
import { Icon } from '../common/Icon'
import { Tex } from '../Equation/Tex'
import { usePageEval } from '../Canvas/PageContext'
import './panels.css'

export function VariablesPanel({ pageId }: { pageId?: string }) {
  const { variables } = usePageEval()
  const [editing, setEditing] = useState<string | null>(null)
  const [draft, setDraft] = useState('')
  const [conv, setConv] = useState('25 ft -> m')
  const convResult = quickConvert(conv)

  const commitEdit = (name: string) => {
    const v = variables.find((x) => x.name === name)
    setEditing(null)
    if (!v || !pageId || !draft.trim()) return
    const block = useLibrary.getState().pages[pageId]?.elements.find((e) => e.id === v.blockId) as CalcElement | undefined
    if (!block) return
    updateElement(pageId, block.id, { source: rewriteVariable(block.source, v.index, draft.trim()) })
  }

  return (
    <div className="vars-panel">
      <div className="panel-intro">
        Variables defined in <b>Variables</b> blocks on this page share one scope. Edit an input and every dependent result updates.
      </div>

      {variables.length === 0 ? (
        <div className="empty">
          <Icon name="variable" size={22} />
          No variables on this page yet.
          {pageId && (
            <button className="btn sm" onClick={() => useCanvas.getState().insertAtCenter(pageId, (c) => make.calc(centered(c, 340, 140)))}>
              <Icon name="plus" size={14} /> Add a Variables block
            </button>
          )}
        </div>
      ) : (
        <div className="var-list">
          {variables.map((v) => (
            <div key={v.name} className={`var-row ${v.error ? 'err' : ''} ${v.isInput ? 'input' : 'derived'}`}>
              <button className="var-main" onClick={() => useCanvas.getState().revealProvider?.(v.blockId)} title="Show on page">
                <span className="var-name">
                  <Tex tex={v.nameTex} />
                </span>
                {editing === v.name ? (
                  <input
                    className="input mono var-edit"
                    autoFocus
                    value={draft}
                    onChange={(e) => setDraft(e.target.value)}
                    onClick={(e) => e.stopPropagation()}
                    onBlur={() => commitEdit(v.name)}
                    onKeyDown={(e) => {
                      e.stopPropagation()
                      if (e.key === 'Enter') commitEdit(v.name)
                      if (e.key === 'Escape') setEditing(null)
                    }}
                  />
                ) : (
                  <span className="var-value">{v.error ? <span className="var-err">{v.error}</span> : <Tex tex={v.valueTex || '—'} />}</span>
                )}
              </button>
              <div className="var-meta">
                <span className={`var-kind mono ${v.isInput ? 'in' : ''}`}>{v.isInput ? 'INPUT' : 'DERIVED'}</span>
                {v.deps.length > 0 && <span className="var-deps mono">← {v.deps.join(', ')}</span>}
                {v.dependents.length > 0 && <span className="var-deps mono">→ {v.dependents.join(', ')}</span>}
                <span className="spacer" />
                {v.isInput && pageId && editing !== v.name && (
                  <button
                    className="icon-btn sm"
                    onClick={() => {
                      setDraft(v.expr.replace(/\s*(->|→).*$/, ''))
                      setEditing(v.name)
                    }}
                    aria-label={`Edit ${v.name}`}
                    data-tip="Edit value"
                  >
                    <Icon name="edit" size={13} />
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      <div className="panel-section">
        <div className="label">Quick convert</div>
        <input className="input mono" value={conv} onChange={(e) => setConv(e.target.value)} placeholder="50 psi -> kPa" onKeyDown={(e) => e.stopPropagation()} />
        <div className={`quick-result mono ${convResult ? '' : 'faint'}`}>{convResult ? `= ${convResult}` : 'e.g. 25 ft -> m · 3 hp to kW · 100 degC to degF'}</div>
      </div>

      <div className="panel-section help">
        <div className="label">Syntax</div>
        <ul>
          <li>
            <code>m = 5 kg</code> — a number followed by a unit is a quantity
          </li>
          <li>
            <code>KE = 1/2*m*v^2</code> — results simplify to SI (J, N, Pa, W…)
          </li>
          <li>
            <code>KE -&gt; kJ</code> — convert a result
          </li>
          <li>
            <code># comment</code> — notes inside a block
          </li>
          <li>
            <code>log</code> is base-10, <code>ln</code> is natural
          </li>
        </ul>
      </div>
    </div>
  )
}
