// Engineering variables: a tiny reactive dependency system.
//
// Every calc block on a page contributes lines like `m = 5 kg` or `KE = 1/2*m*v^2 -> J`.
// All assignments on the page share one scope. We build a dependency graph,
// topologically sort it, and evaluate — so editing `m` updates `KE` everywhere.

import type { MathNode } from 'mathjs'
import type { CalcElement } from '../../models'
import { dependencies, formatValue, math, prepare, valueToTex } from './engine'
import { nodeToTex, symbolToTex } from './tex'

export interface CalcLineResult {
  blockId: string
  index: number
  raw: string
  kind: 'empty' | 'comment' | 'assign' | 'expr' | 'error'
  name?: string
  nameTex?: string
  exprTex?: string
  value?: unknown
  valueText?: string
  valueTex?: string
  error?: string
  deps: string[]
  /** true when the right-hand side is just a literal (an input variable). */
  isInput?: boolean
}

export interface VariableInfo {
  name: string
  nameTex: string
  blockId: string
  index: number
  expr: string
  valueText: string
  valueTex: string
  value: unknown
  deps: string[]
  dependents: string[]
  isInput: boolean
  error?: string
}

export interface PageEvaluation {
  lines: Map<string, CalcLineResult[]> // blockId → line results
  variables: VariableInfo[]
  /** Unitless numeric variables, handy for graphs. */
  numericScope: Record<string, number>
}

const ASSIGN_RE = /^\s*([A-Za-zͰ-Ͽ][A-Za-z0-9_Ͱ-Ͽ]*)\s*=(?!=)\s*(.+)$/
const CONVERT_RE = /\s*(?:->|→|\bto\b)\s*([A-Za-z°µΩ][A-Za-z0-9^/*·\s°µΩ]*)\s*$/

interface ParsedLine {
  res: CalcLineResult
  node?: MathNode
  convert?: string
}

export function splitConversion(expr: string): { expr: string; convert?: string } {
  const m = expr.match(CONVERT_RE)
  if (!m || m.index === undefined || m.index === 0) return { expr }
  return { expr: expr.slice(0, m.index), convert: m[1].trim() }
}

function parseLine(blockId: string, raw: string, index: number): ParsedLine {
  const base: CalcLineResult = { blockId, index, raw, kind: 'empty', deps: [] }
  const trimmed = raw.trim()
  if (!trimmed) return { res: base }
  if (trimmed.startsWith('#') || trimmed.startsWith('//')) return { res: { ...base, kind: 'comment' } }

  const am = trimmed.match(ASSIGN_RE)
  const name = am?.[1]
  const rhs = am ? am[2] : trimmed
  const { expr, convert } = splitConversion(rhs)
  try {
    const node = math.parse(prepare(expr))
    const deps = dependencies(node)
    const literal = deps.length === 0 && !node.toString().match(/[a-zA-Z]{2,}\(/)
    return {
      node,
      convert,
      res: {
        ...base,
        kind: name ? 'assign' : 'expr',
        name,
        nameTex: name ? symbolToTex(name) : undefined,
        exprTex: nodeToTex(node),
        deps,
        isInput: !!name && literal,
      },
    }
  } catch (e) {
    return { res: { ...base, kind: 'error', name, error: (e as Error).message.replace(/\(char \d+\)/, '').trim() } }
  }
}

const BUILTINS = new Set(['pi', 'e', 'i', 'Infinity', 'NaN', 'true', 'false', 'tau', 'phi', 'null'])

export function evaluatePage(blocks: CalcElement[], precision = 4): PageEvaluation {
  const parsed: ParsedLine[] = []
  const lines = new Map<string, CalcLineResult[]>()
  for (const b of blocks) {
    const ls = b.source.split('\n').map((raw, i) => parseLine(b.id, raw, i))
    parsed.push(...ls)
    lines.set(b.id, ls.map((l) => l.res))
  }

  // First definition of a name wins; later ones are flagged.
  const defs = new Map<string, ParsedLine>()
  for (const p of parsed) {
    if (p.res.kind !== 'assign' || !p.res.name) continue
    if (defs.has(p.res.name)) {
      p.res.kind = 'error'
      p.res.error = `“${p.res.name}” is already defined`
      continue
    }
    defs.set(p.res.name, p)
  }

  // Topological evaluation with cycle detection.
  const scope = new Map<string, unknown>()
  const state = new Map<string, 'visiting' | 'done'>()
  const failed = new Set<string>()

  const evalLine = (p: ParsedLine) => {
    try {
      let v = p.node!.evaluate(scope)
      if (p.convert) v = math.unit(v as never).to(p.convert)
      p.res.value = v
      // An explicit conversion (-> km/s) is honoured exactly, never re-simplified.
      p.res.valueText = formatValue(v, precision, !!p.convert)
      p.res.valueTex = valueToTex(v, precision, !!p.convert)
      return true
    } catch (e) {
      p.res.error = cleanError((e as Error).message)
      return false
    }
  }

  const visit = (name: string): boolean => {
    const p = defs.get(name)
    if (!p) return !BUILTINS.has(name) ? false : true
    const st = state.get(name)
    if (st === 'done') return !failed.has(name)
    if (st === 'visiting') {
      p.res.error = 'Circular dependency'
      failed.add(name)
      return false
    }
    state.set(name, 'visiting')
    let ok = true
    for (const d of p.res.deps) {
      if (defs.has(d)) {
        if (!visit(d)) {
          ok = false
          p.res.error ??= `Depends on “${d}”, which has an error`
        }
      }
    }
    state.set(name, 'done')
    if (ok && !p.res.error) {
      ok = evalLine(p)
      if (ok) scope.set(name, p.res.value)
    } else ok = false
    if (!ok) failed.add(name)
    return ok
  }

  for (const name of defs.keys()) visit(name)
  for (const p of parsed) if (p.res.kind === 'expr') evalLine(p)

  // Variable table (with reverse dependencies).
  const variables: VariableInfo[] = []
  for (const [name, p] of defs) {
    variables.push({
      name,
      nameTex: p.res.nameTex ?? name,
      blockId: p.res.blockId,
      index: p.res.index,
      expr: p.res.raw.split('=').slice(1).join('=').trim(),
      valueText: p.res.valueText ?? '',
      valueTex: p.res.valueTex ?? '',
      value: p.res.value,
      deps: p.res.deps.filter((d) => defs.has(d)),
      dependents: [],
      isInput: !!p.res.isInput,
      error: p.res.error,
    })
  }
  for (const v of variables) for (const d of v.deps) variables.find((x) => x.name === d)?.dependents.push(v.name)

  const numericScope: Record<string, number> = {}
  for (const [k, v] of scope) if (typeof v === 'number' && Number.isFinite(v)) numericScope[k] = v

  return { lines, variables, numericScope }
}

function cleanError(msg: string): string {
  if (/Undefined symbol (\w+)/.test(msg)) return msg.replace(/Undefined symbol (\w+)/, 'Unknown variable “$1”')
  if (/Units do not match/.test(msg)) return 'Units do not match'
  if (/Unexpected type of argument/.test(msg)) return 'Incompatible types'
  return msg.replace(/\(char \d+\)/, '').trim()
}

/** Replace the right-hand side of a variable definition inside a calc block's source. */
export function rewriteVariable(source: string, index: number, newExpr: string): string {
  const lines = source.split('\n')
  const line = lines[index] ?? ''
  const m = line.match(ASSIGN_RE)
  if (!m) return source
  const { convert } = splitConversion(m[2])
  const lead = line.match(/^\s*/)?.[0] ?? ''
  lines[index] = `${lead}${m[1]} = ${newExpr}${convert ? ` -> ${convert}` : ''}`
  return lines.join('\n')
}
