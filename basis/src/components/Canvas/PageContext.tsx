import { createContext, useContext, useMemo, type ReactNode } from 'react'
import type { CalcElement, Page } from '../../models'
import { evaluatePage, type PageEvaluation } from '../../services/calculations/variables'
import { useUI } from '../../store/ui'

const EMPTY: PageEvaluation = { lines: new Map(), variables: [], numericScope: {} }

const PageEvalContext = createContext<PageEvaluation>(EMPTY)

/** Evaluates every calc block on the page once, shared by blocks, graphs and the Variables panel. */
export function PageEvalProvider({ page, children }: { page: Page | undefined; children: ReactNode }) {
  const precision = useUI((s) => s.settings.precision)
  const calcs = useMemo(() => (page?.elements.filter((e) => e.type === 'calc') ?? []) as CalcElement[], [page?.elements])
  // Re-evaluate only when calc sources change, not on every stroke.
  const key = calcs.map((c) => c.id + '\u0000' + c.source).join('\u0001')
  const evaluation = useMemo(() => (calcs.length ? evaluatePage(calcs, precision) : EMPTY), [key, precision]) // eslint-disable-line react-hooks/exhaustive-deps
  return <PageEvalContext.Provider value={evaluation}>{children}</PageEvalContext.Provider>
}

export const usePageEval = () => useContext(PageEvalContext)
