// Spreadsheet-style formulas for data tables: `=A1*2`, `=sum(B1:B5)`, `=mean(C:C)`.
import { formatValue, math, prepare } from './engine'

export const colName = (i: number) => {
  let s = ''
  let n = i + 1
  while (n > 0) {
    const r = (n - 1) % 26
    s = String.fromCharCode(65 + r) + s
    n = Math.floor((n - 1) / 26)
  }
  return s
}

const colIndex = (name: string) => [...name.toUpperCase()].reduce((acc, c) => acc * 26 + (c.charCodeAt(0) - 64), 0) - 1

export interface TableEval {
  values: (number | null)[][]
  display: string[][]
  errors: boolean[][]
}

export function evaluateTable(rows: string[][], precision = 5): TableEval {
  const R = rows.length
  const C = rows[0]?.length ?? 0
  const values: (number | null)[][] = rows.map((r) => r.map(() => null))
  const display: string[][] = rows.map((r) => r.map((c) => c))
  const errors: boolean[][] = rows.map((r) => r.map(() => false))
  const state = rows.map((r) => r.map(() => 0)) // 0 = todo, 1 = visiting, 2 = done

  const get = (r: number, c: number): number | null => {
    if (r < 0 || c < 0 || r >= R || c >= C) return null
    if (state[r][c] === 2) return values[r][c]
    if (state[r][c] === 1) throw new Error('cycle')
    state[r][c] = 1
    const raw = (rows[r][c] ?? '').trim()
    let v: number | null = null
    if (raw.startsWith('=')) {
      try {
        let expr = raw.slice(1)
        // ranges: A1:B3 and whole columns A:A
        expr = expr.replace(/\b([A-Z]{1,2})(\d+)?:([A-Z]{1,2})(\d+)?\b/gi, (_m, c1: string, r1: string, c2: string, r2: string) => {
          const a = colIndex(c1), b = colIndex(c2)
          const ra = r1 ? Number(r1) - 1 : 0
          const rb = r2 ? Number(r2) - 1 : R - 1
          const vals: number[] = []
          for (let i = Math.min(ra, rb); i <= Math.max(ra, rb); i++)
            for (let j = Math.min(a, b); j <= Math.max(a, b); j++) {
              if (i === r && j === c) continue
              const x = get(i, j)
              if (x !== null && Number.isFinite(x)) vals.push(x)
            }
          return `[${vals.join(',')}]`
        })
        expr = expr.replace(/\b([A-Z]{1,2})(\d+)\b/g, (_m, cn: string, rn: string) => {
          const x = get(Number(rn) - 1, colIndex(cn))
          return x === null ? '0' : `(${x})`
        })
        const out = math.evaluate(prepare(expr))
        v = typeof out === 'number' ? out : Number(out)
        display[r][c] = formatValue(v, precision)
        if (!Number.isFinite(v)) throw new Error('nan')
      } catch {
        errors[r][c] = true
        display[r][c] = '#ERR'
        v = null
      }
    } else if (raw !== '' && Number.isFinite(Number(raw))) {
      v = Number(raw)
    }
    values[r][c] = v
    state[r][c] = 2
    return v
  }

  for (let r = 0; r < R; r++)
    for (let c = 0; c < C; c++) {
      try {
        get(r, c)
      } catch {
        errors[r][c] = true
        display[r][c] = '#CYCLE'
        state[r][c] = 2
      }
    }
  return { values, display, errors }
}
