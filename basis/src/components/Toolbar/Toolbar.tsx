import { useRef, useState } from 'react'
import { INK, type ShapeKind } from '../../models'
import { centered, make } from '../../services/canvas/factories'
import { HIGHLIGHT_COLORS, INK_COLORS, resolveColor } from '../../services/canvas/ink'
import { insertImageFromPicker } from '../../services/canvas/insert'
import { useCanvas, type Tool } from '../../store/canvas'
import { Icon } from '../common/Icon'
import { Popover, anchorOf } from '../common/Popover'
import './toolbar.css'

const TOOLS: { id: Tool; icon: string; label: string; key: string }[][] = [
  [
    { id: 'select', icon: 'select', label: 'Select', key: 'V' },
    { id: 'hand', icon: 'hand', label: 'Pan', key: 'H' },
  ],
  [
    { id: 'pen', icon: 'pen', label: 'Pen', key: 'P' },
    { id: 'highlighter', icon: 'highlighter', label: 'Highlighter', key: 'M' },
    { id: 'eraser', icon: 'eraser', label: 'Eraser', key: 'E' },
  ],
  [
    { id: 'text', icon: 'text', label: 'Text', key: 'T' },
    { id: 'shape', icon: 'shapes', label: 'Shapes', key: 'S' },
    { id: 'line', icon: 'line', label: 'Line', key: 'L' },
    { id: 'arrow', icon: 'arrow', label: 'Arrow', key: 'A' },
  ],
  [
    { id: 'equation', icon: 'equation', label: 'Equation', key: 'Q' },
    { id: 'image', icon: 'image', label: 'Image', key: 'I' },
  ],
]

const SHAPES: { id: ShapeKind; icon: string; label: string }[] = [
  { id: 'rect', icon: 'rect', label: 'Rectangle' },
  { id: 'ellipse', icon: 'ellipse', label: 'Ellipse' },
  { id: 'triangle', icon: 'triangle', label: 'Triangle' },
  { id: 'diamond', icon: 'diamond', label: 'Diamond' },
]

export function Toolbar({ pageId }: { pageId: string }) {
  const tool = useCanvas((s) => s.tool)
  const setTool = useCanvas((s) => s.setTool)
  const shapeKind = useCanvas((s) => s.options.shape.kind)
  const insertRef = useRef<HTMLButtonElement>(null)
  const [insertOpen, setInsertOpen] = useState(false)

  const insert = (kind: 'calc' | 'table' | 'graph' | 'sticky' | 'image') => {
    setInsertOpen(false)
    const cs = useCanvas.getState()
    if (kind === 'image') return void insertImageFromPicker(pageId)
    if (kind === 'calc') cs.insertAtCenter(pageId, (c) => make.calc(centered(c, 340, 140)))
    if (kind === 'table') cs.insertAtCenter(pageId, (c) => make.table(centered(c, 330, 170)))
    if (kind === 'graph') cs.insertAtCenter(pageId, (c) => make.graph(centered(c, 460, 320)))
    if (kind === 'sticky') {
      const id = cs.insertAtCenter(pageId, (c) => make.sticky(centered(c, 240, 100), { text: 'Constants, assumptions or reminders…' }))
      cs.setEditing(id)
    }
  }

  return (
    <div className="toolbar-wrap canvas-ui ui">
      <div className="toolbar" role="toolbar" aria-label="Tools">
        {TOOLS.map((group, gi) => (
          <div key={gi} className="tool-group">
            {group.map((t) => (
              <button
                key={t.id}
                className={`tool-btn ${tool === t.id ? 'active' : ''}`}
                onClick={() => setTool(t.id)}
                aria-label={t.label}
                aria-pressed={tool === t.id}
                data-tip={`${t.label}  ${t.key}`}
              >
                <Icon name={t.id === 'shape' ? (SHAPES.find((x) => x.id === shapeKind)?.icon ?? 'shapes') : t.icon} size={19} />
                {(t.id === 'pen' || t.id === 'highlighter') && <ColorTick tool={t.id} />}
              </button>
            ))}
          </div>
        ))}
        <div className="tool-group">
          <button ref={insertRef} className={`tool-btn ${insertOpen ? 'active' : ''}`} onClick={() => setInsertOpen(!insertOpen)} aria-label="Insert" data-tip="Insert block">
            <Icon name="plus" size={19} />
          </button>
        </div>
      </div>
      <ToolOptions />
      {insertOpen && (
        <Popover anchor={anchorOf(insertRef.current)} onClose={() => setInsertOpen(false)} align="end">
          <div className="insert-menu">
            <InsertItem icon="variable" title="Variables" desc="Live engineering calculations" onClick={() => insert('calc')} />
            <InsertItem icon="table" title="Data table" desc="Rows, columns & formulas" onClick={() => insert('table')} />
            <InsertItem icon="graph" title="Graph" desc="Plot y = f(x)" onClick={() => insert('graph')} />
            <InsertItem icon="sticky" title="Reference note" desc="Constants & reminders" onClick={() => insert('sticky')} />
            <InsertItem icon="image" title="Image" desc="From your device" onClick={() => insert('image')} />
          </div>
        </Popover>
      )}
    </div>
  )
}

function ColorTick({ tool }: { tool: 'pen' | 'highlighter' }) {
  const color = useCanvas((s) => s.options[tool].color)
  return <span className="color-tick" style={{ background: resolveColor(color) }} />
}

function InsertItem({ icon, title, desc, onClick }: { icon: string; title: string; desc: string; onClick: () => void }) {
  return (
    <button className="insert-item" onClick={onClick}>
      <span className="insert-icon">
        <Icon name={icon} size={18} />
      </span>
      <span>
        <span className="insert-title">{title}</span>
        <span className="insert-desc">{desc}</span>
      </span>
    </button>
  )
}

/** Contextual options strip for the active tool. */
function ToolOptions() {
  const tool = useCanvas((s) => s.tool)
  const options = useCanvas((s) => s.options)
  const setOptions = useCanvas((s) => s.setOptions)

  let content: React.ReactNode = null
  if (tool === 'pen' || tool === 'highlighter' || tool === 'shape' || tool === 'line' || tool === 'arrow') {
    const o = options[tool]
    const colors = tool === 'highlighter' ? HIGHLIGHT_COLORS : INK_COLORS
    const widths = tool === 'highlighter' ? [10, 16, 24, 34] : [1.2, 2.4, 4, 7]
    content = (
      <>
        {tool === 'shape' && (
          <div className="opt-group">
            {SHAPES.map((s) => (
              <button key={s.id} className={`opt-btn ${options.shape.kind === s.id ? 'on' : ''}`} onClick={() => setOptions('shape', { kind: s.id })} aria-label={s.label} data-tip={s.label}>
                <Icon name={s.icon} size={16} />
              </button>
            ))}
          </div>
        )}
        <div className="opt-group">
          {colors.map((c) => (
            <button
              key={c}
              className={`opt-swatch ${o.color === c ? 'on' : ''}`}
              style={{ ['--sw' as string]: resolveColor(c) }}
              onClick={() => setOptions(tool, { color: c })}
              aria-label={c === INK ? 'Ink' : c}
            />
          ))}
        </div>
        <div className="opt-group">
          {widths.map((w) => (
            <button key={w} className={`opt-btn ${Math.abs(o.width - w) < 0.01 ? 'on' : ''}`} onClick={() => setOptions(tool, { width: w })} aria-label={`Width ${w}`}>
              <span className="width-dot" style={{ width: Math.min(18, tool === 'highlighter' ? w / 2 : w * 2 + 2), height: Math.min(18, tool === 'highlighter' ? w / 2 : w * 2 + 2), opacity: tool === 'highlighter' ? 0.6 : 1 }} />
            </button>
          ))}
          <input
            className="opt-range"
            type="range"
            min={tool === 'highlighter' ? 6 : 0.6}
            max={tool === 'highlighter' ? 48 : 14}
            step={0.2}
            value={o.width}
            onChange={(e) => setOptions(tool, { width: Number(e.target.value) })}
            aria-label="Stroke width"
          />
        </div>
        <div className="opt-group">
          <span className="opt-label mono">{tool === 'highlighter' ? 'HL OPACITY' : 'OPACITY'}</span>
          <input
            className="opt-range short"
            type="range"
            min={0.1}
            max={1}
            step={0.05}
            value={o.opacity}
            onChange={(e) => setOptions(tool, { opacity: Number(e.target.value) })}
            aria-label="Opacity"
          />
          <span className="opt-value mono">{Math.round(o.opacity * 100)}%</span>
        </div>
        {(tool === 'shape' || tool === 'line' || tool === 'arrow') && (
          <div className="opt-group">
            {tool === 'shape' && (
              <button className={`opt-btn ${options.shape.fill ? 'on' : ''}`} onClick={() => setOptions('shape', { fill: !options.shape.fill })} data-tip="Fill">
                <Icon name="fill" size={16} style={{ fill: options.shape.fill ? 'currentColor' : 'none', fillOpacity: 0.25 }} />
              </button>
            )}
            <button className={`opt-btn ${options[tool].dashed ? 'on' : ''}`} onClick={() => setOptions(tool, { dashed: !options[tool].dashed })} data-tip="Dashed">
              <Icon name="dash" size={16} />
            </button>
          </div>
        )}
      </>
    )
  } else if (tool === 'eraser') {
    content = (
      <div className="opt-group">
        <span className="opt-label mono">SIZE</span>
        {[10, 18, 32, 56].map((s) => (
          <button key={s} className={`opt-btn ${options.eraser.size === s ? 'on' : ''}`} onClick={() => setOptions('eraser', { size: s })}>
            <span className="width-dot ring" style={{ width: Math.min(20, s / 2.6), height: Math.min(20, s / 2.6) }} />
          </button>
        ))}
        <span className="opt-hint">Erases whole strokes &amp; shapes</span>
      </div>
    )
  } else if (tool === 'text') {
    const o = options.text
    content = (
      <>
        <div className="opt-group">
          {INK_COLORS.slice(0, 6).map((c) => (
            <button key={c} className={`opt-swatch ${o.color === c ? 'on' : ''}`} style={{ ['--sw' as string]: resolveColor(c) }} onClick={() => setOptions('text', { color: c })} aria-label={c} />
          ))}
        </div>
        <div className="opt-group">
          {[14, 18, 24, 34].map((s) => (
            <button key={s} className={`opt-btn wide ${o.fontSize === s ? 'on' : ''}`} onClick={() => setOptions('text', { fontSize: s })}>
              <span className="mono" style={{ fontSize: 11 }}>{s}</span>
            </button>
          ))}
        </div>
        <div className="segmented">
          <button className={o.font === 'sans' ? 'on' : ''} onClick={() => setOptions('text', { font: 'sans' })}>
            Sans
          </button>
          <button className={o.font === 'mono' ? 'on' : ''} onClick={() => setOptions('text', { font: 'mono' })}>
            Mono
          </button>
        </div>
        <span className="opt-hint">Use $…$ for inline maths</span>
      </>
    )
  } else if (tool === 'equation') {
    content = <span className="opt-hint">Tap the page to place an equation · supports fractions, powers, ∫, Σ, vectors, matrices</span>
  } else if (tool === 'image') {
    content = <span className="opt-hint">Tap the page where the image should go</span>
  } else if (tool === 'select') {
    content = <span className="opt-hint">Tap to select · drag to move · double-tap to edit · drag empty space to box-select</span>
  } else if (tool === 'hand') {
    content = <span className="opt-hint">Drag to pan · pinch or ⌘-scroll to zoom</span>
  }

  return (
    <div className="tool-options" key={tool}>
      {content}
    </div>
  )
}
