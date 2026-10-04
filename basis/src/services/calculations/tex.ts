// Converts Basis plain-text maths (`F = m*a`, `KE = 1/2*m*v^2`, `int(x^2, x, 0, 1)`)
// into LaTeX for KaTeX. Our own writer (rather than mathjs.toTex) gives engineering
// typography: italic variables, upright units, proper subscripts and integrals.

import type { MathNode } from 'mathjs'
import { math, markQuantities, normalize, unitToTex, numberToTex } from './engine'

const GREEK = new Set([
  'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'varepsilon', 'zeta', 'eta', 'theta', 'vartheta', 'iota', 'kappa',
  'lambda', 'mu', 'nu', 'xi', 'pi', 'rho', 'sigma', 'tau', 'upsilon', 'phi', 'varphi', 'chi', 'psi', 'omega',
  'Gamma', 'Delta', 'Theta', 'Lambda', 'Xi', 'Pi', 'Sigma', 'Upsilon', 'Phi', 'Psi', 'Omega',
])

const SPECIAL_SYMBOLS: Record<string, string> = {
  Infinity: '\\infty', inf: '\\infty', hbar: '\\hbar', nabla: '\\nabla', partial: '\\partial', ell: '\\ell',
  eps0: '\\varepsilon_0', mu0: '\\mu_0', i: 'i', e: 'e',
}

function baseToTex(base: string): string {
  if (SPECIAL_SYMBOLS[base]) return SPECIAL_SYMBOLS[base]
  if (GREEK.has(base)) return '\\' + (base === 'epsilon' ? 'varepsilon' : base)
  if (base.length > 1) return `\\mathit{${base}}`
  return base
}

export function symbolToTex(name: string): string {
  if (SPECIAL_SYMBOLS[name]) return SPECIAL_SYMBOLS[name]
  const idx = name.indexOf('_')
  if (idx <= 0) return baseToTex(name)
  const base = name.slice(0, idx)
  const sub = name.slice(idx + 1)
  let subTex: string
  if (/^\d+$/.test(sub) || sub.length === 1) subTex = sub
  else if (GREEK.has(sub)) subTex = '\\' + sub
  else if (sub.includes('_')) subTex = symbolToTex(sub)
  else subTex = `\\text{${sub}}`
  return `${baseToTex(base)}_{${subTex}}`
}

const FUNCS: Record<string, string> = {
  sin: '\\sin', cos: '\\cos', tan: '\\tan', sec: '\\sec', csc: '\\csc', cot: '\\cot',
  asin: '\\arcsin', acos: '\\arccos', atan: '\\arctan', sinh: '\\sinh', cosh: '\\cosh', tanh: '\\tanh',
  ln: '\\ln', exp: '\\exp', det: '\\det', max: '\\max', min: '\\min',
  __sind: '\\sin', __cosd: '\\cos', __tand: '\\tan', __asind: '\\arcsin', __acosd: '\\arccos', __atand: '\\arctan',
}

type N = MathNode & Record<string, any>

const unwrap = (n: N): N => (n.type === 'ParenthesisNode' ? unwrap(n.content) : n)
const paren = (s: string) => `\\left(${s}\\right)`

function needsParensForPower(n: N): boolean {
  const u = n
  return u.type === 'OperatorNode' || (u.type === 'ConstantNode' && typeof u.value === 'number' && u.value < 0)
}

function startsWithNumber(tex: string) {
  return /^[\d.]/.test(tex) || tex.startsWith('-')
}

export function nodeToTex(node: MathNode): string {
  const n = node as N
  switch (n.type) {
    case 'ConstantNode': {
      if (typeof n.value === 'string') return `\\text{${n.value}}`
      if (n.value === Infinity) return '\\infty'
      return numberToTex(String(n.value))
    }
    case 'SymbolNode':
      return symbolToTex(n.name)
    case 'ParenthesisNode':
      return paren(nodeToTex(n.content))
    case 'OperatorNode':
      return operatorToTex(n)
    case 'FunctionNode':
      return functionToTex(n)
    case 'ArrayNode': {
      const items: N[] = n.items
      if (items.length && items.every((it) => it.type === 'ArrayNode')) {
        const rows = items.map((r) => (r.items as N[]).map(nodeToTex).join(' & ')).join(' \\\\ ')
        return `\\begin{bmatrix} ${rows} \\end{bmatrix}`
      }
      return `\\left\\langle ${items.map(nodeToTex).join(',\\ ')} \\right\\rangle`
    }
    case 'AssignmentNode':
      return `${nodeToTex(n.object)} = ${nodeToTex(n.value)}`
    case 'RelationalNode': {
      const ops: Record<string, string> = { smaller: '<', larger: '>', smallerEq: '\\le', largerEq: '\\ge', equal: '=', unequal: '\\ne' }
      const params: N[] = n.params
      return params.map((p, i) => (i === 0 ? nodeToTex(p) : ` ${ops[n.conditionals[i - 1]] ?? '='} ${nodeToTex(p)}`)).join('')
    }
    case 'ConditionalNode':
      return `${nodeToTex(n.condition)} \\;?\\; ${nodeToTex(n.trueExpr)} : ${nodeToTex(n.falseExpr)}`
    case 'AccessorNode':
      return `${nodeToTex(n.object)}_{${(n.index.dimensions as N[]).map(nodeToTex).join(',')}}`
    case 'RangeNode':
      return `${nodeToTex(n.start)}:${nodeToTex(n.end)}`
    default:
      return n.toString()
  }
}

function operatorToTex(n: N): string {
  const args: N[] = n.args
  if (args.length === 1) {
    const a = nodeToTex(args[0])
    if (n.op === '-') return `-${a}`
    if (n.op === '+') return `+${a}`
    if (n.op === '!') return `${a}!`
    if (n.op === "'") return `${a}^{T}`
    return `${n.op}${a}`
  }
  const [l, r] = args
  switch (n.op) {
    case '+':
      return `${nodeToTex(l)} + ${nodeToTex(r)}`
    case '-':
      return `${nodeToTex(l)} - ${nodeToTex(r)}`
    case '/':
    case './':
      return `\\frac{${nodeToTex(unwrap(l))}}{${nodeToTex(unwrap(r))}}`
    case '^':
    case '.^': {
      const base = l.type === 'ParenthesisNode' || !needsParensForPower(l) ? nodeToTex(l) : paren(nodeToTex(l))
      return `{${base}}^{${nodeToTex(unwrap(r))}}`
    }
    case '*':
    case '.*': {
      const lt = nodeToTex(l)
      const rt = nodeToTex(r)
      const isQ = (x: N) => x.type === 'FunctionNode' && x.fn?.name === '__q'
      if (startsWithNumber(rt) || isQ(r)) return `${lt} \\cdot ${rt}`
      if (n.implicit) return `${lt}\\,${rt}`
      return `${lt}\\,${rt}`
    }
    case '%':
    case 'mod':
      return `${nodeToTex(l)} \\bmod ${nodeToTex(r)}`
    case '==':
      return `${nodeToTex(l)} = ${nodeToTex(r)}`
    case '!=':
      return `${nodeToTex(l)} \\ne ${nodeToTex(r)}`
    case '<':
    case '>':
      return `${nodeToTex(l)} ${n.op} ${nodeToTex(r)}`
    case '<=':
      return `${nodeToTex(l)} \\le ${nodeToTex(r)}`
    case '>=':
      return `${nodeToTex(l)} \\ge ${nodeToTex(r)}`
    case 'to':
      return `${nodeToTex(l)} \\to ${nodeToTex(r)}`
    default:
      return `${nodeToTex(l)} ${n.op} ${nodeToTex(r)}`
  }
}

function functionToTex(n: N): string {
  if (n.fn && n.fn.type !== 'SymbolNode') {
    // e.g. vec(F)(x, y): a call on the result of another call
    return `${nodeToTex(n.fn)}${paren((n.args as N[]).map((a) => nodeToTex(unwrap(a))).join(', '))}`
  }
  const name: string = n.fn?.name ?? n.name
  const args: N[] = n.args
  const t = (i: number) => (args[i] ? nodeToTex(unwrap(args[i])) : '')
  const call = (fn: string) => `${fn}${paren(args.map((a) => nodeToTex(unwrap(a))).join(', '))}`

  switch (name) {
    case '__q': {
      const s = String(args[0]?.value ?? '')
      const m = s.match(/^(\S+)\s+(.*)$/)
      return m ? `${numberToTex(m[1])}\\ ${unitToTex(m[2])}` : s
    }
    case 'sqrt':
      return `\\sqrt{${t(0)}}`
    case 'cbrt':
      return `\\sqrt[3]{${t(0)}}`
    case 'nthRoot':
    case 'root':
      return `\\sqrt[${t(1)}]{${t(0)}}`
    case 'abs':
      return `\\left|${t(0)}\\right|`
    case 'norm':
    case 'mag':
      return `\\left\\lVert ${t(0)} \\right\\rVert`
    case 'exp':
      return `e^{${t(0)}}`
    case 'log':
    case '__log':
      return args.length > 1 ? `\\log_{${t(1)}}${paren(t(0))}` : `\\log${paren(t(0))}`
    case 'log10':
      return `\\log_{10}${paren(t(0))}`
    case 'frac':
      return `\\frac{${t(0)}}{${t(1)}}`
    case 'vec':
      return `\\vec{${t(0)}}`
    case 'hat':
      return `\\hat{${t(0)}}`
    case 'bar':
      return `\\bar{${t(0)}}`
    case 'dot':
      return args.length === 1 ? `\\dot{${t(0)}}` : `${t(0)} \\cdot ${t(1)}`
    case 'ddot':
      return `\\ddot{${t(0)}}`
    case 'cross':
      return `${t(0)} \\times ${t(1)}`
    case 'grad':
      return `\\nabla ${t(0)}`
    case 'div':
      return `\\nabla \\cdot ${t(0)}`
    case 'curl':
      return `\\nabla \\times ${t(0)}`
    case 'lap':
      return `\\nabla^2 ${t(0)}`
    case 'int':
    case 'integral':
      if (args.length >= 4) return `\\int_{${t(2)}}^{${t(3)}} ${t(0)}\\,\\mathrm{d}${t(1)}`
      return `\\int ${t(0)}\\,\\mathrm{d}${t(1) || 'x'}`
    case 'iint':
      return args.length >= 3
        ? `\\iint_{${t(2)}} ${t(0)}\\,\\mathrm{d}${t(1)}`
        : `\\iint ${t(0)}\\,\\mathrm{d}${t(1) || 'A'}`
    case 'iiint':
      return args.length >= 3
        ? `\\iiint_{${t(2)}} ${t(0)}\\,\\mathrm{d}${t(1)}`
        : `\\iiint ${t(0)}\\,\\mathrm{d}${t(1) || 'V'}`
    case 'oint':
      return args.length >= 3 ? `\\oint_{${t(2)}} ${t(0)}\\cdot\\mathrm{d}${t(1)}` : `\\oint ${t(0)}\\cdot\\mathrm{d}${t(1) || 's'}`
    case 'sum':
    case 'prod':
      if (args.length === 4) return `\\${name}_{${t(1)}=${t(2)}}^{${t(3)}} ${t(0)}`
      return call(name === 'sum' ? '\\operatorname{sum}' : '\\operatorname{prod}')
    case 'lim':
      return `\\lim_{${t(1)} \\to ${t(2)}} ${t(0)}`
    case 'dvec':
      return `\\mathrm{d}\\vec{${t(0)}}`
    case 'deriv':
    case 'd':
      if (args.length === 1) return `\\mathrm{d}${t(0)}`
      if (args.length >= 3) return `\\frac{\\mathrm{d}^{${t(2)}} ${t(0)}}{\\mathrm{d}${t(1)}^{${t(2)}}}`
      return `\\frac{\\mathrm{d}${t(0)}}{\\mathrm{d}${t(1)}}`
    case 'pd':
    case 'partial':
      if (args.length >= 3) return `\\frac{\\partial^{2} ${t(0)}}{\\partial ${t(1)}\\,\\partial ${t(2)}}`
      return `\\frac{\\partial ${t(0)}}{\\partial ${t(1)}}`
    case 'approx':
      return `${t(0)} \\approx ${t(1)}`
  }
  if (FUNCS[name]) {
    const inner = t(0)
    const simple = args.length === 1 && /^[a-zA-Z\\]+(\{[^}]*\})?$|^\d+$/.test(inner) && !inner.includes('\\left')
    return args.length === 1 && simple ? `${FUNCS[name]} ${inner}` : call(FUNCS[name])
  }
  if (GREEK.has(name) && args.length === 1) return `\\${name} ${t(0)}`
  if (name.length === 1 || name.includes('_')) return call(symbolToTex(name))
  return call(`\\operatorname{${name}}`)
}

// ── Equation sources ─────────────────────────────────────────────────────────

const RELATIONS: [string, string][] = [
  ['<=>', '\\iff'],
  ['=>', '\\Rightarrow'],
  ['->', '\\rightarrow'],
  ['→', '\\rightarrow'],
  ['<=', '\\le'],
  ['>=', '\\ge'],
  ['!=', '\\ne'],
  ['≈', '\\approx'],
  ['~=', '\\approx'],
  ['≤', '\\le'],
  ['≥', '\\ge'],
  ['==', '='],
  ['=', '='],
  ['<', '<'],
  ['>', '>'],
]

/** Split on top-level relational operators, keeping them. */
function splitRelations(s: string): { parts: string[]; ops: string[] } {
  const parts: string[] = []
  const ops: string[] = []
  let depth = 0
  let cur = ''
  for (let i = 0; i < s.length; i++) {
    const ch = s[i]
    if ('([{'.includes(ch)) depth++
    if (')]}'.includes(ch)) depth--
    if (depth === 0) {
      const rel = RELATIONS.find(([tok]) => s.startsWith(tok, i))
      if (rel) {
        parts.push(cur)
        ops.push(rel[1])
        cur = ''
        i += rel[0].length - 1
        continue
      }
    }
    cur += ch
  }
  parts.push(cur)
  return { parts, ops }
}

export function looksLikeLatex(src: string) {
  return /\\[a-zA-Z]|\$|\^\{|_\{/.test(src)
}

/** Expression (no relations) → TeX. Throws if it cannot be parsed. */
export function exprToTex(expr: string): string {
  const node = math.parse(markQuantities(normalize(expr)))
  return nodeToTex(node)
}

/** Equation source (Basis syntax or raw LaTeX) → TeX. Never throws. */
/** Split on commas that are not inside brackets (separate equations on one line). */
function splitTopLevelCommas(s: string): string[] {
  const out: string[] = []
  let depth = 0
  let cur = ''
  for (const ch of s) {
    if ('([{'.includes(ch)) depth++
    if (')]}'.includes(ch)) depth--
    if (ch === ',' && depth === 0) {
      out.push(cur)
      cur = ''
    } else cur += ch
  }
  out.push(cur)
  return out
}

export function sourceToTex(src: string): string {
  const s = src.trim()
  if (!s) return ''
  if (looksLikeLatex(s)) return s.replace(/^\$+|\$+$/g, '')
  const segments = splitTopLevelCommas(s)
  if (segments.length > 1) return segments.map((seg) => relationToTex(seg.trim())).join(',\\quad ')
  return relationToTex(s)
}

function relationToTex(s: string): string {
  const { parts, ops } = splitRelations(s)
  return parts
    .map((p, i) => {
      const part = p.trim()
      let tex: string
      try {
        tex = part ? exprToTex(part) : ''
      } catch {
        tex = part.replace(/([#%&_{}])/g, '\\$1')
      }
      return i === 0 ? tex : ` ${ops[i - 1]} ${tex}`
    })
    .join('')
}
