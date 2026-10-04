import type { EvalFunction } from 'mathjs'
import { math, prepare } from './engine'

export interface View {
  xmin: number
  xmax: number
  ymin: number
  ymax: number
}

const compiled = new Map<string, EvalFunction | Error>()

/** Strip `y =` / `f(x) =` prefixes and compile once. */
export function compileFunction(expr: string): EvalFunction | Error {
  const key = expr
  const hit = compiled.get(key)
  if (hit) return hit
  let src = expr.trim().replace(/^\s*(y|[a-zA-Z]\s*\(\s*x\s*\))\s*=/, '')
  if (!src) src = 'NaN'
  let out: EvalFunction | Error
  try {
    out = math.compile(prepare(src))
  } catch (e) {
    out = e as Error
  }
  if (compiled.size > 400) compiled.clear()
  compiled.set(key, out)
  return out
}

/** Sample f over the view; returns polyline segments (broken at discontinuities). */
export function sampleFunction(expr: string, view: View, samples: number, scope: Record<string, number>): { segments: [number, number][][]; error?: string } {
  const f = compileFunction(expr)
  if (f instanceof Error) return { segments: [], error: f.message }
  const segments: [number, number][][] = []
  let cur: [number, number][] = []
  const s: Record<string, number> = { ...scope, x: 0 }
  const span = view.ymax - view.ymin
  let prevY: number | null = null
  try {
    for (let i = 0; i <= samples; i++) {
      const x = view.xmin + ((view.xmax - view.xmin) * i) / samples
      s.x = x
      let y = f.evaluate(s) as unknown
      if (typeof y !== 'number') y = Number(y)
      const yn = y as number
      if (!Number.isFinite(yn) || (prevY !== null && Math.abs(yn - prevY) > span * 4)) {
        if (cur.length > 1) segments.push(cur)
        cur = Number.isFinite(yn) ? [[x, yn]] : []
      } else cur.push([x, yn])
      prevY = Number.isFinite(yn) ? yn : null
    }
  } catch (e) {
    return { segments: [], error: (e as Error).message.replace(/Undefined symbol (\w+)/, 'Unknown “$1”') }
  }
  if (cur.length > 1) segments.push(cur)
  return { segments }
}

/** “Nice” tick spacing: 1, 2 or 5 × 10ⁿ. */
export function niceStep(range: number, target = 8): number {
  const raw = range / target
  const p = Math.pow(10, Math.floor(Math.log10(raw)))
  const n = raw / p
  return (n < 1.5 ? 1 : n < 3.5 ? 2 : n < 7.5 ? 5 : 10) * p
}

export function ticks(min: number, max: number, target = 8): number[] {
  const step = niceStep(max - min, target)
  const out: number[] = []
  for (let v = Math.ceil(min / step) * step; v <= max + step * 1e-9; v += step) out.push(Math.abs(v) < step * 1e-9 ? 0 : v)
  return out
}

export const tickLabel = (v: number) => {
  const a = Math.abs(v)
  if (a !== 0 && (a >= 1e5 || a < 1e-3)) return v.toExponential(0)
  return String(Number(v.toPrecision(6)))
}
