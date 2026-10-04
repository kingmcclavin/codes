// The Basis math engine. A thin, isolated wrapper around mathjs so the rest of
// the app never talks to mathjs directly. A native port can swap this module for
// a Swift implementation with the same surface.

import { create, all, type MathJsInstance, type MathNode, type Unit } from 'mathjs'

export const math: MathJsInstance = create(all, { number: 'number', precision: 64 })

// ── Engineering units that mathjs doesn't ship with ──────────────────────────
const extraUnits: [string, string, string[]?][] = [
  ['cal', '4.184 J'],
  ['kcal', '4184 J'],
  ['Cal', '4184 J'],
  ['kWh', '3.6e6 J'],
  ['MWh', '3.6e9 J'],
  ['ksi', '1000 psi'],
  ['kip', '1000 lbf'],
  ['rpm', '1 / minute'],
]
for (const [name, def] of extraUnits) {
  try {
    if (!math.Unit.isValuelessUnit(name)) math.createUnit(name, def)
  } catch {
    /* already defined */
  }
}
// Always simplify compound results to SI derived units (kg·m²/s² → J, not cal).
;(math.Unit as unknown as { setUnitSystem: (s: string) => void }).setUnitSystem('si')

// Derived units we try, in order, when mathjs leaves a compound unit behind.
const PREFERRED_UNITS = ['N', 'J', 'W', 'Pa', 'C', 'V', 'ohm', 'F', 'H', 'T', 'Wb', 'Hz', 'N/C', 'V/m', 'm/s', 'm/s^2', 'kg/m^3', 'N/m', 'J/K', 'kg*m/s', 'N*s', 'rad/s', 'm^2', 'm^3']
const preferred = PREFERRED_UNITS.map((u) => math.unit(u))

/** Turn awkward compound units like (kg m)/(s^3 A) into V/m where possible. */
export function simplifyUnit<T>(v: T): T {
  if (!isUnit(v)) return v
  const units = (v as unknown as { units: { power: number }[] }).units
  if (units.length === 1 && units[0].power === 1) return v
  for (const p of preferred) {
    if ((v as Unit).equalBase(p)) {
      const out = (v as Unit).to(p.formatUnits())
      return out as unknown as T
    }
  }
  return v
}

// ── Helper functions available inside every expression ───────────────────────
const deg2rad = Math.PI / 180
const isNum = (x: unknown): x is number => typeof x === 'number'

math.import(
  {
    __q: (s: string) => math.unit(s),
    __log: (x: number, b?: number) => (b === undefined ? math.log10(x as never) : math.log(x as never, b as never)),
    ln: (x: number) => math.log(x as never),
    __sind: (x: number) => (isNum(x) ? Math.sin(x * deg2rad) : math.sin(x as never)),
    __cosd: (x: number) => (isNum(x) ? Math.cos(x * deg2rad) : math.cos(x as never)),
    __tand: (x: number) => (isNum(x) ? Math.tan(x * deg2rad) : math.tan(x as never)),
    __asind: (x: number) => {
      const r = math.asin(x as never) as unknown
      return isNum(r) ? r / deg2rad : r
    },
    __acosd: (x: number) => {
      const r = math.acos(x as never) as unknown
      return isNum(r) ? r / deg2rad : r
    },
    __atand: (x: number) => {
      const r = math.atan(x as never) as unknown
      return isNum(r) ? r / deg2rad : r
    },
    mag: (v: unknown) => math.norm(v as never),
  },
  { override: true },
)

// ── Physical constants (SI) usable as `c`, `g0`… only in the calculator menu ──
export const CONSTANTS: { name: string; symbol: string; value: string; label: string }[] = [
  { name: 'pi', symbol: 'π', value: 'pi', label: 'Pi' },
  { name: 'e', symbol: 'e', value: 'e', label: "Euler's number" },
  { name: 'c', symbol: 'c', value: '299792458', label: 'Speed of light (m/s)' },
  { name: 'g', symbol: 'g', value: '9.80665', label: 'Standard gravity (m/s²)' },
  { name: 'G', symbol: 'G', value: '6.6743e-11', label: 'Gravitational const.' },
  { name: 'h', symbol: 'h', value: '6.62607015e-34', label: 'Planck const. (J·s)' },
  { name: 'kB', symbol: 'k_B', value: '1.380649e-23', label: 'Boltzmann const. (J/K)' },
  { name: 'NA', symbol: 'N_A', value: '6.02214076e23', label: 'Avogadro (1/mol)' },
  { name: 'R', symbol: 'R', value: '8.314462618', label: 'Gas constant (J/mol·K)' },
  { name: 'qe', symbol: 'q_e', value: '1.602176634e-19', label: 'Elementary charge (C)' },
  { name: 'me', symbol: 'm_e', value: '9.1093837e-31', label: 'Electron mass (kg)' },
  { name: 'eps0', symbol: 'ε₀', value: '8.8541878128e-12', label: 'Vacuum permittivity (F/m)' },
  { name: 'mu0', symbol: 'μ₀', value: '1.25663706212e-6', label: 'Vacuum permeability (H/m)' },
  { name: 'ke', symbol: 'k', value: '8.9875517923e9', label: 'Coulomb const. (N·m²/C²)' },
]

// ── Text normalisation ───────────────────────────────────────────────────────
const SUPERSCRIPTS: Record<string, string> = {
  '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4', '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9', '⁻': '-',
}

const GREEK_UNICODE: Record<string, string> = {
  α: 'alpha', β: 'beta', γ: 'gamma', δ: 'delta', ε: 'epsilon', ζ: 'zeta', η: 'eta', θ: 'theta', ι: 'iota',
  κ: 'kappa', λ: 'lambda', μ: 'mu', ν: 'nu', ξ: 'xi', ρ: 'rho', σ: 'sigma', τ: 'tau', υ: 'upsilon',
  φ: 'phi', χ: 'chi', ψ: 'psi', ω: 'omega', Γ: 'Gamma', Δ: 'Delta', Θ: 'Theta', Λ: 'Lambda', Ξ: 'Xi',
  Π: 'Pi', Σ: 'Sigma', Φ: 'Phi', Ψ: 'Psi', Ω: 'Omega',
}

/** Normalise typed/pasted maths: superscripts, ×, ÷, π, √, Greek letters. */
export function normalize(input: string): string {
  let s = input
  s = s.replace(/[⁰¹²³⁴⁵⁶⁷⁸⁹⁻]+/g, (m) => '^' + (m.length > 1 ? '(' : '') + [...m].map((c) => SUPERSCRIPTS[c]).join('') + (m.length > 1 ? ')' : ''))
  s = s.replace(/[×⋅·∙]/g, '*').replace(/÷/g, '/').replace(/[−–]/g, '-').replace(/π/g, 'pi').replace(/∞/g, 'Infinity')
  s = s.replace(/√\s*\(/g, 'sqrt(').replace(/√\s*([A-Za-z0-9_.]+)/g, 'sqrt($1)')
  s = s.replace(/(\d)\s*°/g, '$1 deg')
  s = s.replace(/[α-ωΓΔΘΛΞΠΣΦΨΩ]/g, (c) => GREEK_UNICODE[c] ?? c)
  return s
}

export const isUnitName = (name: string) => {
  try {
    return math.Unit.isValuelessUnit(name)
  } catch {
    return false
  }
}

const NUMBER_UNIT_RE =
  /(^|[^A-Za-z0-9_.])((?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)(\s*)([A-Za-z][A-Za-z0-9]*(?:\^-?\d+)?(?:[*/][A-Za-z][A-Za-z0-9]*(?:\^-?\d+)?)*)/g

/**
 * Turn engineering quantities (`12 m/s`, `9.81 m/s^2`, `25 ft`) into explicit unit literals.
 * Units are only recognised immediately after a number, so a variable called `m` never
 * collides with metres.
 */
export function markQuantities(s: string): string {
  return s.replace(NUMBER_UNIT_RE, (whole, pre: string, num: string, _sp: string, unitExpr: string) => {
    // Accept the longest prefix of unit atoms that are all real units.
    const atoms = unitExpr.split(/(?=[*/])/)
    let accepted = ''
    for (const atom of atoms) {
      const name = atom.replace(/^[*/]/, '').replace(/\^-?\d+$/, '')
      if (!isUnitName(name)) break
      accepted += atom
    }
    if (!accepted) return whole
    const rest = unitExpr.slice(accepted.length)
    return `${pre}__q("${num} ${accepted}")${rest}`
  })
}

/** Engineering conventions: log = log₁₀, ln = natural log. */
function conventions(s: string, angle: 'deg' | 'rad'): string {
  let out = s.replace(/\blog\s*\(/g, '__log(')
  if (angle === 'deg') out = out.replace(/\b(a?)(sin|cos|tan)\s*\(/g, (_m, a: string, f: string) => `__${a}${f}d(`)
  return out
}

export function prepare(expr: string, angle: 'deg' | 'rad' = 'rad'): string {
  return conventions(markQuantities(normalize(expr)), angle)
}

export function parse(expr: string, angle: 'deg' | 'rad' = 'rad'): MathNode {
  return math.parse(prepare(expr, angle))
}

/** Symbols referenced by an expression (excluding function names and built-in constants). */
export function dependencies(node: MathNode): string[] {
  const out = new Set<string>()
  node.traverse((n, path, parent) => {
    if (n.type === 'SymbolNode') {
      if (parent && parent.type === 'FunctionNode' && path === 'fn') return
      out.add((n as unknown as { name: string }).name)
    }
  })
  return [...out]
}

// ── Formatting ──────────────────────────────────────────────────────────────
export function isUnit(v: unknown): v is Unit {
  return !!v && typeof v === 'object' && (v as { type?: string }).type === 'Unit'
}

export function formatValue(v: unknown, precision = 4, keepUnits = false): string {
  if (v === undefined || v === null) return ''
  if (typeof v === 'function') return 'ƒ'
  if (typeof v === 'boolean') return v ? 'true' : 'false'
  try {
    let out = math.format((keepUnits ? v : simplifyUnit(v)) as never, { precision, lowerExp: -4, upperExp: 6 } as never)
    out = out.replace(/(\d) u([A-Za-z])/g, '$1 µ$2')
    out = out.replace(/(\d)e\+?(-?\d+)/g, '$1×10^$2')
    return out
  } catch {
    return String(v)
  }
}

export function unitToTex(u: string): string {
  const t = u
    .trim()
    .replace(/^\(([^()]*)\)\s*\//, '$1 /') // "(N m^2) / C^2" → "N m^2 / C^2"
    .replace(/\^(?:\((-?[\d.]+)\)|(-?[\d.]+))/g, (_m, a: string, b: string) => `^{${a ?? b}}`)
    .replace(/\s*\/\s*/g, '/')
    .replace(/\s*\*\s*/g, '*')
    .replace(/\s+/g, '\\,')
    .replace(/\*/g, '\\cdot ')
    .replace(/\bohm\b/g, '\\Omega')
    .replace(/deg\b/g, '^{\\circ}')
    .replace(/(^|[,/\s(]|\\cdot )u(?=[A-Za-z])/g, '$1\\mu ')
    .replace(/µ/g, '\\mu ')
  return `\\mathrm{${t}}`
}

export function numberToTex(s: string): string {
  return s.replace(/(-?[\d.]+)(?:e|×10\^)\+?(-?\d+)/g, (_m, a: string, b: string) => `${a}\\times10^{${b}}`)
}

/** Render an evaluated value as TeX (numbers, quantities, complex, vectors). */
export function valueToTex(v: unknown, precision = 4, keepUnits = false): string {
  if (isUnit(v)) {
    const full = formatValue(v, precision, keepUnits)
    const m = full.match(/^(\S+)\s+(.*)$/)
    if (m) return `${numberToTex(m[1])}\\ ${unitToTex(m[2])}`
    return numberToTex(full)
  }
  const s = formatValue(v, precision)
  if (s.startsWith('[')) {
    try {
      const arr = JSON.parse(s.replace(/×10\^(-?\d+)/g, 'e$1'))
      if (Array.isArray(arr) && arr.every((x) => typeof x === 'number'))
        return `\\left\\langle ${arr.map((x: number) => numberToTex(formatValue(x, precision))).join(',\\ ')} \\right\\rangle`
    } catch {
      /* fall through */
    }
  }
  return numberToTex(s).replace(/(\d)i\b/g, '$1\\,i')
}
