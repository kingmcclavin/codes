// Docked equation editor. Accepts Basis plain-text maths (F = m*a, 1/2*m*v^2,
// int(f, x, a, b)) or raw LaTeX; the palette inserts snippets at the caret.

import { useEffect, useLayoutEffect, useRef } from 'react'
import type { EquationElement } from '../../models'
import { sourceToTex } from '../../services/calculations/tex'
import { removeElements, updateElement, useCanvas } from '../../store/canvas'
import { useLibrary } from '../../store/library'
import { Icon } from '../common/Icon'
import { Tex } from './Tex'

interface Snippet {
  label: string // TeX label for the button
  insert: string
  caret?: number // caret offset from start of insert
  title: string
}

const STRUCTURES: Snippet[] = [
  { label: '\\frac{a}{b}', insert: '()/()', caret: 1, title: 'Fraction' },
  { label: 'x^{n}', insert: '^()', caret: 2, title: 'Power' },
  { label: 'x_{i}', insert: '_', caret: 1, title: 'Subscript' },
  { label: '\\sqrt{x}', insert: 'sqrt()', caret: 5, title: 'Square root' },
  { label: '\\sqrt[n]{x}', insert: 'nthRoot(, n)', caret: 8, title: 'nth root' },
  { label: '\\int_a^b', insert: 'int(f, x, a, b)', caret: 4, title: 'Integral' },
  { label: '\\sum', insert: 'sum(f, k, 1, n)', caret: 4, title: 'Summation' },
  { label: '\\frac{d}{dx}', insert: 'd(f, x)', caret: 2, title: 'Derivative' },
  { label: '\\frac{\\partial}{\\partial x}', insert: 'pd(f, x)', caret: 3, title: 'Partial derivative' },
  { label: '\\lim', insert: 'lim(f, x, 0)', caret: 4, title: 'Limit' },
  { label: '\\vec{v}', insert: 'vec()', caret: 4, title: 'Vector' },
  { label: '\\hat{x}', insert: 'hat()', caret: 4, title: 'Unit vector' },
  { label: '\\begin{bmatrix}a&b\\\\c&d\\end{bmatrix}', insert: '[a, b; c, d]', caret: 1, title: 'Matrix' },
  { label: '\\langle\\,\\rangle', insert: '[x, y, z]', caret: 1, title: 'Vector components' },
  { label: '|x|', insert: 'abs()', caret: 4, title: 'Absolute value' },
  { label: '\\nabla', insert: 'grad()', caret: 5, title: 'Gradient' },
  { label: '\\times', insert: 'cross(a, b)', caret: 6, title: 'Cross product' },
  { label: '\\approx', insert: ' ≈ ', title: 'Approximately' },
]

const GREEK = ['α', 'β', 'γ', 'δ', 'Δ', 'ε', 'θ', 'λ', 'μ', 'ν', 'π', 'ρ', 'σ', 'τ', 'φ', 'ω', 'Ω', '∞']

export function EquationEditor({ el, pageId }: { el: EquationElement; pageId: string }) {
  const ref = useRef<HTMLTextAreaElement>(null)

  useLayoutEffect(() => {
    useCanvas.getState().checkpoint(pageId)
    const t = ref.current
    if (t) {
      t.focus({ preventScroll: true })
      t.setSelectionRange(t.value.length, t.value.length)
    }
    return () => {
      // Deferred so StrictMode's mount/unmount/mount doesn't delete a fresh equation.
      setTimeout(() => {
        if (useCanvas.getState().editingId === el.id) return
        const cur = useLibrary.getState().pages[pageId]?.elements.find((x) => x.id === el.id) as EquationElement | undefined
        if (cur && !cur.source.trim()) removeElements(pageId, [el.id])
      }, 0)
    }
  }, [el.id, pageId])

  useEffect(() => {
    const t = ref.current
    if (!t) return
    t.style.height = '0px'
    t.style.height = Math.min(140, t.scrollHeight) + 'px'
  }, [el.source])

  const set = (source: string) => updateElement(pageId, el.id, { source }, false)
  const done = () => useCanvas.getState().setEditing(null)

  const insert = (s: Snippet | string) => {
    const t = ref.current!
    const snip = typeof s === 'string' ? { insert: s, caret: s.length } : s
    const a = t.selectionStart ?? el.source.length
    const b = t.selectionEnd ?? a
    const next = el.source.slice(0, a) + snip.insert + el.source.slice(b)
    set(next)
    requestAnimationFrame(() => {
      t.focus()
      const c = a + (snip.caret ?? snip.insert.length)
      t.setSelectionRange(c, c)
    })
  }

  const tex = sourceToTex(el.source)

  return (
    <div className="eq-editor canvas-ui ui" onPointerDown={(e) => e.stopPropagation()}>
      <div className="eq-editor-head">
        <Icon name="equation" size={14} />
        <span className="label">Equation</span>
        <span className="eq-editor-hint">Type <code>F = m*a</code>, <code>1/2*m*v^2</code> or LaTeX</span>
        <button className="btn sm primary" onClick={done}>
          Done
        </button>
      </div>
      <div className="eq-editor-body">
        <textarea
          ref={ref}
          className="eq-input mono"
          value={el.source}
          rows={1}
          spellCheck={false}
          autoCapitalize="off"
          autoCorrect="off"
          placeholder="E = m*c^2"
          onChange={(e) => set(e.target.value)}
          onKeyDown={(e) => {
            e.stopPropagation()
            if ((e.key === 'Enter' && !e.shiftKey) || e.key === 'Escape') {
              e.preventDefault()
              done()
            }
          }}
        />
        <div className="eq-preview">{tex ? <Tex tex={tex} display /> : <span className="faint">Preview</span>}</div>
      </div>
      <div className="eq-palette">
        {STRUCTURES.map((s) => (
          <button key={s.title} className="eq-key" title={s.title} onPointerDown={(e) => e.preventDefault()} onClick={() => insert(s)}>
            <Tex tex={s.label} />
          </button>
        ))}
        <span className="eq-palette-sep" />
        {GREEK.map((g) => (
          <button key={g} className="eq-key greek" onPointerDown={(e) => e.preventDefault()} onClick={() => insert(g)}>
            {g}
          </button>
        ))}
      </div>
    </div>
  )
}
