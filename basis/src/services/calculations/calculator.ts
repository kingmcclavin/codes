import { formatValue, math, prepare } from './engine'

export type AngleMode = 'deg' | 'rad'

export interface CalcResult {
  ok: boolean
  value?: unknown
  text: string
}

/** Evaluate a calculator expression. `Ans` refers to the previous answer. */
export function calculate(expr: string, angle: AngleMode, ans: unknown, precision = 10): CalcResult {
  const src = expr
    .replace(/(\d)\s*E\s*([+-]?\d)/g, '$1e$2') // 6.02E23 → 6.02e23
    .replace(/\bAns\b/g, '(__ans)')
  if (!src.trim()) return { ok: false, text: '' }
  try {
    const v = math.evaluate(prepare(src, angle), { __ans: ans ?? 0 })
    if (typeof v === 'function' || v === undefined) return { ok: false, text: '' }
    return { ok: true, value: v, text: formatValue(v, precision) }
  } catch (e) {
    return { ok: false, text: (e as Error).message.replace(/\(char \d+\)/, '').trim() }
  }
}
