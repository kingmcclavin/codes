// Global search across notebooks, sections, pages and page content
// (text, equations, variables, tables, sticky notes, graph functions).

import type { CanvasElement, Notebook, Page, Section } from '../models'

export type SearchKind = 'notebook' | 'section' | 'page' | 'text' | 'equation' | 'variable' | 'table' | 'note' | 'graph'

export interface SearchResult {
  kind: SearchKind
  notebookId: string
  pageId?: string
  sectionId?: string
  elementId?: string
  title: string
  context: string
  snippet?: string
  score: number
}

function elementText(el: CanvasElement): { kind: SearchKind; text: string } | null {
  switch (el.type) {
    case 'text':
      return { kind: 'text', text: el.text }
    case 'equation':
      return { kind: 'equation', text: el.source }
    case 'calc':
      return { kind: 'variable', text: `${el.title ?? ''}\n${el.source}` }
    case 'table':
      return { kind: 'table', text: [el.title ?? '', el.columns.join(' '), ...el.rows.map((r) => r.join(' '))].join('\n') }
    case 'sticky':
      return { kind: 'note', text: `${el.title}\n${el.text}` }
    case 'graph':
      return { kind: 'graph', text: el.functions.map((f) => f.expr).join('\n') }
    default:
      return null
  }
}

function snippetAround(text: string, idx: number, len: number) {
  const lineStart = text.lastIndexOf('\n', idx) + 1
  let lineEnd = text.indexOf('\n', idx + len)
  if (lineEnd === -1) lineEnd = text.length
  let s = text.slice(lineStart, lineEnd)
  let off = idx - lineStart
  if (s.length > 90) {
    const from = Math.max(0, off - 35)
    s = (from > 0 ? '…' : '') + s.slice(from, from + 90) + (from + 90 < s.length ? '…' : '')
    off = off - from + (from > 0 ? 1 : 0)
  }
  return { s, off }
}

export function search(q: string, data: { notebooks: Record<string, Notebook>; sections: Record<string, Section>; pages: Record<string, Page> }, limit = 40): SearchResult[] {
  const query = q.trim().toLowerCase()
  if (!query) return []
  const out: SearchResult[] = []
  const nbName = (id: string) => data.notebooks[id]?.name ?? ''

  for (const nb of Object.values(data.notebooks)) {
    const i = `${nb.name} ${nb.description}`.toLowerCase().indexOf(query)
    if (i >= 0) out.push({ kind: 'notebook', notebookId: nb.id, title: nb.name, context: nb.description || 'Notebook', score: 100 - i })
  }
  for (const s of Object.values(data.sections)) {
    if (!data.notebooks[s.notebookId]) continue
    const i = s.title.toLowerCase().indexOf(query)
    if (i >= 0) out.push({ kind: 'section', notebookId: s.notebookId, sectionId: s.id, title: s.title, context: nbName(s.notebookId), score: 80 - i })
  }
  for (const p of Object.values(data.pages)) {
    if (!data.notebooks[p.notebookId]) continue
    const ctx = `${nbName(p.notebookId)} › ${data.sections[p.sectionId]?.title ?? ''}`
    const i = p.title.toLowerCase().indexOf(query)
    if (i >= 0) out.push({ kind: 'page', notebookId: p.notebookId, pageId: p.id, title: p.title, context: ctx, score: 90 - i })
    for (const el of p.elements) {
      const t = elementText(el)
      if (!t) continue
      const j = t.text.toLowerCase().indexOf(query)
      if (j < 0) continue
      const { s } = snippetAround(t.text, j, query.length)
      out.push({ kind: t.kind, notebookId: p.notebookId, pageId: p.id, elementId: el.id, title: p.title, context: ctx, snippet: s, score: 50 - Math.min(j, 40) })
    }
  }
  return out.sort((a, b) => b.score - a.score).slice(0, limit)
}
