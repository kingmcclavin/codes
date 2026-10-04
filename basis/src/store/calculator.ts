import { create } from 'zustand'
import { calculate, type AngleMode } from '../services/calculations/calculator'

export interface CalcEntry {
  expr: string
  result: string
}

interface CalculatorState {
  expr: string
  ans: unknown
  history: CalcEntry[]
  angle: AngleMode
  second: boolean
  justEvaluated: boolean
  setExpr: (e: string) => void
  input: (token: string) => void
  backspace: () => void
  clear: () => void
  evaluate: () => void
  setAngle: (a: AngleMode) => void
  toggleSecond: () => void
}

const loadHistory = (): CalcEntry[] => {
  try {
    return JSON.parse(localStorage.getItem('basis.calc.history') || '[]')
  } catch {
    return []
  }
}

export const useCalculator = create<CalculatorState>((set, get) => ({
  expr: '',
  ans: 0,
  history: loadHistory(),
  angle: 'deg',
  second: false,
  justEvaluated: false,

  setExpr: (expr) => set({ expr, justEvaluated: false }),
  input(token) {
    const { expr, justEvaluated } = get()
    // After "=", typing an operator continues from Ans; typing a number starts fresh.
    if (justEvaluated) {
      if (/^[+\-*/^×÷!]/.test(token)) set({ expr: 'Ans' + token, justEvaluated: false })
      else set({ expr: token, justEvaluated: false })
      return
    }
    set({ expr: expr + token })
  },
  backspace() {
    const e = get().expr
    const m = e.match(/(asin\(|acos\(|atan\(|sin\(|cos\(|tan\(|sqrt\(|log\(|ln\(|exp\(|abs\(|Ans)$/)
    set({ expr: m ? e.slice(0, -m[0].length) : e.slice(0, -1), justEvaluated: false })
  },
  clear: () => set({ expr: '', justEvaluated: false }),
  evaluate() {
    const { expr, angle, ans, history } = get()
    if (!expr.trim()) return
    const r = calculate(expr, angle, ans)
    if (!r.ok) {
      set({ history: [{ expr, result: `Error: ${r.text}` }, ...history].slice(0, 60) })
      return
    }
    const next = [{ expr, result: r.text }, ...history].slice(0, 60)
    try {
      localStorage.setItem('basis.calc.history', JSON.stringify(next))
    } catch {
      /* ignore */
    }
    set({ ans: r.value, history: next, expr: r.text.replace(/×10\^/g, 'E').replace(/ /g, ''), justEvaluated: true })
  },
  setAngle: (angle) => set({ angle }),
  toggleSecond: () => set({ second: !get().second }),
}))
