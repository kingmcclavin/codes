import { useEffect, useMemo, useRef, useState } from 'react'
import { calculate } from '../../services/calculations/calculator'
import { CONSTANTS } from '../../services/calculations/engine'
import { centered, make } from '../../services/canvas/factories'
import { useCalculator } from '../../store/calculator'
import { useCanvas } from '../../store/canvas'
import { useUI } from '../../store/ui'
import { Icon } from '../common/Icon'
import './calculator.css'

type Key = { label: string; insert?: string; action?: 'eval' | 'clear' | 'back' | 'second' | 'angle'; kind?: 'fn' | 'op' | 'num' | 'eq' | 'mod'; alt?: { label: string; insert: string } }

const KEYS: Key[] = [
  { label: '2nd', action: 'second', kind: 'mod' },
  { label: 'DEG', action: 'angle', kind: 'mod' },
  { label: '(', insert: '(', kind: 'fn' },
  { label: ')', insert: ')', kind: 'fn' },
  { label: 'AC', action: 'clear', kind: 'mod' },

  { label: 'sin', insert: 'sin(', kind: 'fn', alt: { label: 'sin⁻¹', insert: 'asin(' } },
  { label: 'cos', insert: 'cos(', kind: 'fn', alt: { label: 'cos⁻¹', insert: 'acos(' } },
  { label: 'tan', insert: 'tan(', kind: 'fn', alt: { label: 'tan⁻¹', insert: 'atan(' } },
  { label: 'π', insert: 'π', kind: 'fn', alt: { label: 'e', insert: 'e' } },
  { label: '⌫', action: 'back', kind: 'mod' },

  { label: 'ln', insert: 'ln(', kind: 'fn', alt: { label: 'eˣ', insert: 'e^(' } },
  { label: 'log', insert: 'log(', kind: 'fn', alt: { label: '10ˣ', insert: '10^(' } },
  { label: 'x²', insert: '^2', kind: 'fn', alt: { label: 'x³', insert: '^3' } },
  { label: 'xʸ', insert: '^', kind: 'fn', alt: { label: 'ʸ√x', insert: 'nthRoot(' } },
  { label: '√', insert: 'sqrt(', kind: 'fn', alt: { label: '∛', insert: 'cbrt(' } },

  { label: '7', insert: '7', kind: 'num' },
  { label: '8', insert: '8', kind: 'num' },
  { label: '9', insert: '9', kind: 'num' },
  { label: '÷', insert: '÷', kind: 'op' },
  { label: 'EE', insert: 'E', kind: 'fn', alt: { label: 'x!', insert: '!' } },

  { label: '4', insert: '4', kind: 'num' },
  { label: '5', insert: '5', kind: 'num' },
  { label: '6', insert: '6', kind: 'num' },
  { label: '×', insert: '×', kind: 'op' },
  { label: 'i', insert: 'i', kind: 'fn', alt: { label: '|x|', insert: 'abs(' } },

  { label: '1', insert: '1', kind: 'num' },
  { label: '2', insert: '2', kind: 'num' },
  { label: '3', insert: '3', kind: 'num' },
  { label: '−', insert: '-', kind: 'op' },
  { label: 'Ans', insert: 'Ans', kind: 'fn', alt: { label: '1/x', insert: '^(-1)' } },

  { label: '0', insert: '0', kind: 'num' },
  { label: '.', insert: '.', kind: 'num' },
  { label: ',', insert: ',', kind: 'num' },
  { label: '+', insert: '+', kind: 'op' },
  { label: '=', action: 'eval', kind: 'eq' },
]

export function Calculator({ pageId }: { pageId?: string }) {
  const { expr, history, angle, second, justEvaluated } = useCalculator()
  const calc = useCalculator.getState()
  const inputRef = useRef<HTMLInputElement>(null)
  const [constOpen, setConstOpen] = useState(false)
  const precision = useUI((s) => s.settings.precision)

  const preview = useMemo(() => {
    if (justEvaluated || !expr.trim()) return null
    const r = calculate(expr, angle, calc.ans, precision + 4)
    return r.ok ? r.text : null
  }, [expr, angle, justEvaluated, calc.ans, precision])

  useEffect(() => {
    // Keep the caret at the end after on-screen key presses.
    const t = inputRef.current
    if (t && document.activeElement === t) t.setSelectionRange(t.value.length, t.value.length)
  }, [expr])

  const press = (k: Key) => {
    if (k.action === 'eval') return calc.evaluate()
    if (k.action === 'clear') return calc.clear()
    if (k.action === 'back') return calc.backspace()
    if (k.action === 'second') return calc.toggleSecond()
    if (k.action === 'angle') return calc.setAngle(angle === 'deg' ? 'rad' : 'deg')
    const ins = second && k.alt ? k.alt.insert : k.insert!
    calc.input(ins)
    if (second) calc.toggleSecond()
  }

  const insertToPage = (entry: { expr: string; result: string }) => {
    if (!pageId) return
    const source = `${entry.expr.replace(/×/g, '*').replace(/÷/g, '/')} = ${entry.result.replace(/×10\^(-?\d+)/g, 'e$1')}`
    useCanvas.getState().insertAtCenter(pageId, (c) => make.equation(centered(c, 220, 40), source))
    useUI.getState().toast('Inserted into page')
  }

  const last = history[0]

  return (
    <div className="calculator">
      <div className="calc-display">
        <div className="calc-display-top mono">
          <span className={`calc-mode ${angle}`}>{angle.toUpperCase()}</span>
          {second && <span className="calc-mode on">2ND</span>}
          <span className="spacer" />
          <div className="calc-const-wrap">
            <button className="calc-const-btn" onClick={() => setConstOpen(!constOpen)}>
              Constants <Icon name="chevronDown" size={12} />
            </button>
            {constOpen && (
              <div className="calc-const-menu">
                {CONSTANTS.map((c) => (
                  <button
                    key={c.name}
                    onClick={() => {
                      calc.input(c.value === 'pi' ? 'π' : c.value === 'e' ? 'e' : `(${c.value})`)
                      setConstOpen(false)
                    }}
                  >
                    <span className="mono sym">{c.symbol}</span>
                    <span className="desc">{c.label}</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
        <input
          ref={inputRef}
          className="calc-input mono"
          value={expr}
          placeholder="0"
          spellCheck={false}
          autoCapitalize="off"
          autoCorrect="off"
          inputMode="text"
          onChange={(e) => calc.setExpr(e.target.value)}
          onKeyDown={(e) => {
            e.stopPropagation()
            if (e.key === 'Enter') calc.evaluate()
            if (e.key === 'Escape') calc.clear()
          }}
        />
        <div className="calc-preview mono">{preview ? `= ${preview}` : justEvaluated && last ? <span className="faint">{last.expr} =</span> : ' '}</div>
      </div>

      <div className="calc-keys">
        {KEYS.map((k, i) => {
          const label = second && k.alt ? k.alt.label : k.action === 'angle' ? angle.toUpperCase() : k.label
          return (
            <button
              key={i}
              className={`ck ck-${k.kind} ${k.action === 'second' && second ? 'on' : ''} ${second && k.alt ? 'alt' : ''}`}
              onPointerDown={(e) => e.preventDefault()}
              onClick={() => press(k)}
            >
              {label}
            </button>
          )
        })}
      </div>

      <div className="calc-history">
        <div className="calc-history-head">
          <span className="label">History</span>
          {history.length > 0 && (
            <button className="btn sm ghost" onClick={() => useCalculator.setState({ history: [] })}>
              Clear
            </button>
          )}
        </div>
        {history.length === 0 && <div className="empty">Results appear here. Units work too — try 5 kg * 9.81 m/s^2</div>}
        {history.map((h, i) => (
          <div key={i} className="calc-hist-row">
            <button className="calc-hist-main" onClick={() => calc.setExpr(h.expr)} title="Reuse expression">
              <span className="mono expr">{h.expr}</span>
              <span className={`mono res ${h.result.startsWith('Error') ? 'err' : ''}`}>{h.result.startsWith('Error') ? h.result : `= ${h.result}`}</span>
            </button>
            {pageId && !h.result.startsWith('Error') && (
              <button className="icon-btn sm" onClick={() => insertToPage(h)} data-tip="Insert into page" aria-label="Insert into page">
                <Icon name="insert" size={14} />
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
