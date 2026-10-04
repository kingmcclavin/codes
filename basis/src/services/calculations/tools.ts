// Pure numerical routines behind the Engineering Tools panel.

export interface Complex {
  re: number
  im: number
}

export interface QuadraticResult {
  discriminant: number
  roots: Complex[]
  vertex: [number, number] | null
  kind: 'two-real' | 'double' | 'complex' | 'linear' | 'none' | 'all'
}

export function solveQuadratic(a: number, b: number, c: number): QuadraticResult {
  if (a === 0) {
    if (b === 0) return { discriminant: NaN, roots: [], vertex: null, kind: c === 0 ? 'all' : 'none' }
    return { discriminant: NaN, roots: [{ re: -c / b, im: 0 }], vertex: null, kind: 'linear' }
  }
  const d = b * b - 4 * a * c
  const vertex: [number, number] = [-b / (2 * a), c - (b * b) / (4 * a)]
  if (d > 0) {
    // Numerically stable form avoids cancellation.
    const q = -0.5 * (b + Math.sign(b || 1) * Math.sqrt(d))
    const r1 = q / a
    const r2 = c / q
    const [x1, x2] = r1 > r2 ? [r1, r2] : [r2, r1]
    return { discriminant: d, roots: [{ re: x1, im: 0 }, { re: x2, im: 0 }], vertex, kind: 'two-real' }
  }
  if (d === 0) return { discriminant: d, roots: [{ re: -b / (2 * a), im: 0 }], vertex, kind: 'double' }
  const re = -b / (2 * a)
  const im = Math.sqrt(-d) / (2 * Math.abs(a))
  return { discriminant: d, roots: [{ re, im }, { re, im: -im }], vertex, kind: 'complex' }
}

export type Vec3 = [number, number, number]

export const vec = {
  add: (a: Vec3, b: Vec3): Vec3 => [a[0] + b[0], a[1] + b[1], a[2] + b[2]],
  sub: (a: Vec3, b: Vec3): Vec3 => [a[0] - b[0], a[1] - b[1], a[2] - b[2]],
  dot: (a: Vec3, b: Vec3) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
  cross: (a: Vec3, b: Vec3): Vec3 => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
  mag: (a: Vec3) => Math.hypot(a[0], a[1], a[2]),
  unit: (a: Vec3): Vec3 => {
    const m = Math.hypot(a[0], a[1], a[2])
    return m === 0 ? [0, 0, 0] : [a[0] / m, a[1] / m, a[2] / m]
  },
  angle: (a: Vec3, b: Vec3) => {
    const m = vec.mag(a) * vec.mag(b)
    if (m === 0) return NaN
    return (Math.acos(Math.min(1, Math.max(-1, vec.dot(a, b) / m))) * 180) / Math.PI
  },
}

export interface Stats {
  n: number
  sum: number
  mean: number
  median: number
  stdSample: number
  stdPop: number
  min: number
  max: number
  range: number
}

export function parseNumberList(text: string): number[] {
  return text
    .split(/[\s,;]+/)
    .map((t) => t.trim())
    .filter(Boolean)
    .map(Number)
    .filter((n) => Number.isFinite(n))
}

export function statistics(xs: number[]): Stats | null {
  const n = xs.length
  if (!n) return null
  const sorted = [...xs].sort((a, b) => a - b)
  const sum = xs.reduce((s, x) => s + x, 0)
  const mean = sum / n
  const ss = xs.reduce((s, x) => s + (x - mean) ** 2, 0)
  const median = n % 2 ? sorted[(n - 1) / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
  return {
    n,
    sum,
    mean,
    median,
    stdSample: n > 1 ? Math.sqrt(ss / (n - 1)) : 0,
    stdPop: Math.sqrt(ss / n),
    min: sorted[0],
    max: sorted[n - 1],
    range: sorted[n - 1] - sorted[0],
  }
}

export const fmt = (x: number, p = 6) => {
  if (!Number.isFinite(x)) return '—'
  if (x === 0) return '0'
  const a = Math.abs(x)
  if (a >= 1e7 || a < 1e-4) return x.toExponential(p - 1).replace(/\.?0+e/, 'e')
  return String(Number(x.toPrecision(p)))
}

export const fmtComplex = (z: Complex, p = 6) => {
  if (Math.abs(z.im) < 1e-14) return fmt(z.re, p)
  const sign = z.im < 0 ? '−' : '+'
  return `${fmt(z.re, p)} ${sign} ${fmt(Math.abs(z.im), p)}i`
}
