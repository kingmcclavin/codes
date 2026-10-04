// Engineering tool registry. Add a calculator by appending to ENGINEERING_TOOLS —
// each tool is a self-contained component with an id, name and icon.

import { useMemo, useState, type ReactNode } from 'react'
import { fmt, fmtComplex, parseNumberList, solveQuadratic, statistics, vec, type Vec3 } from '../../services/calculations/tools'
import { centered, make } from '../../services/canvas/factories'
import { convert, formatNumber, UNIT_CATEGORIES } from '../../services/units'
import { useCanvas } from '../../store/canvas'
import { useUI } from '../../store/ui'
import { Icon } from '../common/Icon'
import { Tex } from '../Equation/Tex'

export interface EngineeringTool {
  id: string
  name: string
  description: string
  icon: string
  Component: (props: { pageId?: string }) => ReactNode
}

const num = (s: string) => {
  const v = Number(s)
  return Number.isFinite(v) ? v : NaN
}

function insertEquation(pageId: string | undefined, source: string) {
  if (!pageId) return
  useCanvas.getState().insertAtCenter(pageId, (c) => make.equation(centered(c, 240, 40), source))
  useUI.getState().toast('Inserted into page')
}

function NumField({ label, value, onChange, width }: { label: string; value: string; onChange: (v: string) => void; width?: number }) {
  return (
    <label className="tool-field" style={{ width }}>
      <span className="tool-field-label mono">{label}</span>
      <input className="input mono" inputMode="decimal" value={value} onChange={(e) => onChange(e.target.value)} onKeyDown={(e) => e.stopPropagation()} />
    </label>
  )
}

function Result({ label, value, tex }: { label: string; value?: string; tex?: string }) {
  return (
    <div className="tool-result">
      <span className="tool-result-label mono">{label}</span>
      <span className="tool-result-value mono">{tex ? <Tex tex={tex} /> : value}</span>
    </div>
  )
}

// ── Quadratic ────────────────────────────────────────────────────────────────
function Quadratic({ pageId }: { pageId?: string }) {
  const [a, setA] = useState('1')
  const [b, setB] = useState('-3')
  const [c, setC] = useState('2')
  const r = useMemo(() => solveQuadratic(num(a), num(b), num(c)), [a, b, c])
  const valid = [a, b, c].every((x) => Number.isFinite(num(x)))
  return (
    <div className="tool-body">
      <div className="tool-formula">
        <Tex tex={`${a || 'a'}x^2 ${num(b) < 0 ? '-' : '+'} ${Math.abs(num(b)) || 'b'}x ${num(c) < 0 ? '-' : '+'} ${Math.abs(num(c)) || 'c'} = 0`} display />
      </div>
      <div className="tool-row">
        <NumField label="a" value={a} onChange={setA} />
        <NumField label="b" value={b} onChange={setB} />
        <NumField label="c" value={c} onChange={setC} />
      </div>
      {valid && (
        <div className="tool-results">
          {r.kind === 'none' && <Result label="Result" value="No solution" />}
          {r.kind === 'all' && <Result label="Result" value="All real x" />}
          {r.roots.map((z, i) => (
            <Result key={i} label={r.roots.length === 1 ? 'x' : `x${i === 0 ? '₁' : '₂'}`} value={fmtComplex(z)} />
          ))}
          {Number.isFinite(r.discriminant) && <Result label="Δ = b²−4ac" value={fmt(r.discriminant)} />}
          {r.vertex && <Result label="Vertex" value={`(${fmt(r.vertex[0])}, ${fmt(r.vertex[1])})`} />}
          <div className="tool-tag mono">{r.kind === 'two-real' ? 'Two real roots' : r.kind === 'double' ? 'Repeated root' : r.kind === 'complex' ? 'Complex conjugate roots' : r.kind === 'linear' ? 'Linear (a = 0)' : ''}</div>
        </div>
      )}
      {pageId && valid && r.roots.length > 0 && (
        <button className="btn sm" onClick={() => insertEquation(pageId, r.roots.map((z, i) => `x_${i + 1} = ${fmtComplex(z).replace('−', '-').replace(/ /g, '')}`).join(',  '))}>
          <Icon name="insert" size={14} /> Insert roots into page
        </button>
      )}
    </div>
  )
}

// ── Vectors ──────────────────────────────────────────────────────────────────
function Vectors({ pageId }: { pageId?: string }) {
  const [A, setA] = useState(['3', '-2', '1'])
  const [B, setB] = useState(['1', '4', '-2'])
  const va = A.map(num) as Vec3
  const vb = B.map(num) as Vec3
  const ok = [...va, ...vb].every(Number.isFinite)
  const v3 = (v: Vec3) => `\\langle ${v.map((x) => fmt(x, 5)).join(',\\ ')} \\rangle`
  const comp = (label: string, vals: string[], set: (v: string[]) => void) => (
    <div className="tool-vec">
      <span className="tool-vec-name">
        <Tex tex={`\\vec{${label}}`} />
      </span>
      {['x', 'y', 'z'].map((ax, i) => (
        <NumField key={ax} label={ax} value={vals[i]} onChange={(v) => set(vals.map((x, j) => (j === i ? v : x)))} />
      ))}
    </div>
  )
  return (
    <div className="tool-body">
      {comp('A', A, setA)}
      {comp('B', B, setB)}
      {ok && (
        <div className="tool-results">
          <Result label="|A|" value={fmt(vec.mag(va))} />
          <Result label="|B|" value={fmt(vec.mag(vb))} />
          <Result label="A + B" tex={v3(vec.add(va, vb))} />
          <Result label="A − B" tex={v3(vec.sub(va, vb))} />
          <Result label="A · B" value={fmt(vec.dot(va, vb))} />
          <Result label="A × B" tex={v3(vec.cross(va, vb))} />
          <Result label="∠(A, B)" value={`${fmt(vec.angle(va, vb), 5)}°`} />
          <Result label="Â" tex={v3(vec.unit(va))} />
        </div>
      )}
      {pageId && ok && (
        <button className="btn sm" onClick={() => insertEquation(pageId, `cross(vec(A), vec(B)) = [${vec.cross(va, vb).map((x) => fmt(x, 5)).join(', ')}]`)}>
          <Icon name="insert" size={14} /> Insert A × B into page
        </button>
      )}
    </div>
  )
}

// ── Unit converter ───────────────────────────────────────────────────────────
function UnitConverter({ pageId }: { pageId?: string }) {
  const [cat, setCat] = useState('pressure')
  const category = UNIT_CATEGORIES.find((c) => c.id === cat)!
  const [from, setFrom] = useState('psi')
  const [to, setTo] = useState('kPa')
  const [value, setValue] = useState('50')
  const changeCat = (id: string) => {
    const c = UNIT_CATEGORIES.find((x) => x.id === id)!
    setCat(id)
    setFrom(c.units[0].id)
    setTo(c.units[1]?.id ?? c.units[0].id)
  }
  const v = num(value)
  let out = NaN
  try {
    out = convert(v, from, to)
  } catch {
    /* incompatible */
  }
  const sym = (id: string) => category.units.find((u) => u.id === id)?.symbol ?? id
  return (
    <div className="tool-body">
      <div className="unit-cats">
        {UNIT_CATEGORIES.map((c) => (
          <button key={c.id} className={`chip ${cat === c.id ? 'on' : ''}`} onClick={() => changeCat(c.id)}>
            {c.name}
          </button>
        ))}
      </div>
      <div className="unit-conv">
        <div className="unit-side">
          <input className="input mono unit-value" inputMode="decimal" value={value} onChange={(e) => setValue(e.target.value)} onKeyDown={(e) => e.stopPropagation()} />
          <select className="select" value={from} onChange={(e) => setFrom(e.target.value)}>
            {category.units.map((u) => (
              <option key={u.id} value={u.id}>
                {u.symbol} — {u.label}
              </option>
            ))}
          </select>
        </div>
        <button
          className="icon-btn unit-swap"
          onClick={() => {
            setFrom(to)
            setTo(from)
            if (Number.isFinite(out)) setValue(String(Number(out.toPrecision(10))))
          }}
          aria-label="Swap units"
        >
          <Icon name="swap" size={16} />
        </button>
        <div className="unit-side">
          <div className="unit-out mono">{Number.isFinite(out) ? formatNumber(out, 6) : '—'}</div>
          <select className="select" value={to} onChange={(e) => setTo(e.target.value)}>
            {category.units.map((u) => (
              <option key={u.id} value={u.id}>
                {u.symbol} — {u.label}
              </option>
            ))}
          </select>
        </div>
      </div>
      <div className="tool-results compact">
        {category.units
          .filter((u) => u.id !== from)
          .map((u) => {
            let x = NaN
            try {
              x = convert(v, from, u.id)
            } catch {
              /* ignore */
            }
            return <Result key={u.id} label={u.symbol} value={Number.isFinite(x) ? formatNumber(x, 6) : '—'} />
          })}
      </div>
      {pageId && Number.isFinite(out) && (
        <button className="btn sm" onClick={() => insertEquation(pageId, `${value} ${from} = ${formatNumber(out, 6)} ${to}`.replace(/\^/g, '^'))}>
          <Icon name="insert" size={14} /> Insert {value} {sym(from)} → {sym(to)}
        </button>
      )}
    </div>
  )
}

// ── Statistics ───────────────────────────────────────────────────────────────
function Statistics({ pageId }: { pageId?: string }) {
  const [text, setText] = useState('9.79, 9.83, 9.81, 9.78, 9.84, 9.80, 9.82')
  const xs = parseNumberList(text)
  const s = statistics(xs)
  return (
    <div className="tool-body">
      <label className="tool-field">
        <span className="tool-field-label mono">Data (comma, space or newline separated)</span>
        <textarea className="textarea mono" rows={4} value={text} onChange={(e) => setText(e.target.value)} onKeyDown={(e) => e.stopPropagation()} />
      </label>
      {s ? (
        <div className="tool-results">
          <Result label="n" value={String(s.n)} />
          <Result label="Mean x̄" value={fmt(s.mean)} />
          <Result label="Median" value={fmt(s.median)} />
          <Result label="Std dev (s)" value={fmt(s.stdSample)} />
          <Result label="Std dev (σ)" value={fmt(s.stdPop)} />
          <Result label="Min" value={fmt(s.min)} />
          <Result label="Max" value={fmt(s.max)} />
          <Result label="Range" value={fmt(s.range)} />
          <Result label="Sum" value={fmt(s.sum)} />
        </div>
      ) : (
        <div className="empty">Enter some numbers</div>
      )}
      {pageId && s && (
        <button className="btn sm" onClick={() => insertEquation(pageId, `bar(x) = ${fmt(s.mean)},  s = ${fmt(s.stdSample)},  n = ${s.n}`)}>
          <Icon name="insert" size={14} /> Insert summary into page
        </button>
      )}
    </div>
  )
}

// ── Ohm's law / power (an example of how easily tools extend) ───────────────
function OhmsLaw() {
  const [V, setV] = useState('12')
  const [R, setR] = useState('220')
  const v = num(V), r = num(R)
  const I = v / r
  return (
    <div className="tool-body">
      <div className="tool-formula">
        <Tex tex="V = IR,\quad P = VI = \frac{V^2}{R}" display />
      </div>
      <div className="tool-row">
        <NumField label="V (volts)" value={V} onChange={setV} />
        <NumField label="R (ohms)" value={R} onChange={setR} />
      </div>
      <div className="tool-results">
        <Result label="I" value={Number.isFinite(I) ? `${fmt(I * 1000, 5)} mA` : '—'} />
        <Result label="P" value={Number.isFinite(I) ? `${fmt(v * I * 1000, 5)} mW` : '—'} />
      </div>
    </div>
  )
}

export const ENGINEERING_TOOLS: EngineeringTool[] = [
  { id: 'units', name: 'Unit Converter', description: 'Length, force, energy, pressure…', icon: 'swap', Component: UnitConverter },
  { id: 'quadratic', name: 'Quadratic Solver', description: 'ax² + bx + c = 0', icon: 'sigma', Component: Quadratic },
  { id: 'vectors', name: 'Vector Calculator', description: 'Magnitude, dot & cross products', icon: 'arrow', Component: Vectors },
  { id: 'stats', name: 'Statistics', description: 'Mean, median, standard deviation', icon: 'graph', Component: Statistics },
  { id: 'ohm', name: "Ohm's Law", description: 'Voltage, current, resistance, power', icon: 'circuit', Component: OhmsLaw },
]
