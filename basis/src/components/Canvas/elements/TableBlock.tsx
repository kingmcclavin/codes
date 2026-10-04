import { useMemo, useState } from 'react'
import type { GraphElement, TableElement } from '../../../models'
import { colName, evaluateTable } from '../../../services/calculations/table'
import { blockSizes } from '../../../services/canvas/geometry'
import { uid } from '../../../services/id'
import { updateElement, useCanvas } from '../../../store/canvas'
import { useLibrary } from '../../../store/library'
import { Icon } from '../../common/Icon'
import type { BlockProps } from './BlockFrame'

const SERIES_COLORS = ['#ff6b2c', '#3b82f6', '#14b8a6', '#a855f7', '#eab308']

export function TableBlock({ el, pageId, selected }: BlockProps<TableElement>) {
  const evald = useMemo(() => evaluateTable(el.rows), [el.rows])
  const [focus, setFocus] = useState<string | null>(null)

  const set = (patch: Partial<TableElement>) => updateElement(pageId, el.id, patch)
  const setCell = (r: number, c: number, v: string) => {
    const rows = el.rows.map((row) => [...row])
    rows[r][c] = v
    updateElement(pageId, el.id, { rows }, false)
  }
  const setHeader = (c: number, v: string) => {
    const columns = [...el.columns]
    columns[c] = v
    updateElement(pageId, el.id, { columns }, false)
  }
  const addRow = () => set({ rows: [...el.rows, el.columns.map(() => '')] })
  const addCol = () => set({ columns: [...el.columns, `Col ${el.columns.length + 1}`], rows: el.rows.map((r) => [...r, '']) })
  const delRow = () => el.rows.length > 1 && set({ rows: el.rows.slice(0, -1) })
  const delCol = () => el.columns.length > 1 && set({ columns: el.columns.slice(0, -1), rows: el.rows.map((r) => r.slice(0, -1)) })

  const plot = () => {
    const xs = evald.values.map((r) => r[0])
    const series = el.columns.slice(1).map((name, ci) => ({
      id: uid('s'),
      label: name,
      color: SERIES_COLORS[ci % SERIES_COLORS.length],
      points: evald.values
        .map((r, ri) => [xs[ri], r[ci + 1]] as [number | null, number | null])
        .filter((p): p is [number, number] => p[0] !== null && p[1] !== null),
    }))
    const all = series.flatMap((s) => s.points)
    if (!all.length) return
    const xmin = Math.min(...all.map((p) => p[0])), xmax = Math.max(...all.map((p) => p[0]))
    const ymin = Math.min(0, ...all.map((p) => p[1])), ymax = Math.max(...all.map((p) => p[1]))
    const px = (xmax - xmin || 1) * 0.08, py = (ymax - ymin || 1) * 0.12
    const graph: GraphElement = {
      id: uid('e'),
      type: 'graph',
      x: el.x,
      y: el.y + (blockSizes.get(el.id)?.h ?? 40 + (el.rows.length + 1) * 33) + 28,
      w: 460,
      h: 300,
      functions: [],
      series,
      view: { xmin: xmin - px, xmax: xmax + px, ymin: ymin - py, ymax: ymax + py },
      xLabel: el.columns[0],
      yLabel: el.columns.slice(1).join(', '),
    }
    const page = useLibrary.getState().pages[pageId]
    useCanvas.getState().commit(pageId, [...page.elements, graph])
    useCanvas.getState().setSelection([graph.id])
  }

  return (
    <div className="table-block">
      <div className="block-head">
        <Icon name="table" size={14} />
        {selected ? (
          <input className="block-title-input" data-interactive value={el.title ?? ''} placeholder="DATA" onChange={(e) => updateElement(pageId, el.id, { title: e.target.value }, false)} onKeyDown={(e) => e.stopPropagation()} />
        ) : (
          <span className="label">{el.title || 'Data'}</span>
        )}
        {selected && (
          <div className="block-tools" data-interactive>
            <button className="icon-btn sm" onClick={addRow} data-tip="Add row">
              <Icon name="plus" size={14} />
            </button>
            <button className="icon-btn sm" onClick={delRow} data-tip="Remove row">
              <Icon name="minus" size={14} />
            </button>
            <span className="vsep" />
            <button className="btn sm ghost" onClick={addCol}>
              + Col
            </button>
            <button className="btn sm ghost" onClick={delCol}>
              − Col
            </button>
            <span className="vsep" />
            <button className="btn sm ghost" onClick={plot}>
              <Icon name="graph" size={14} /> Plot
            </button>
          </div>
        )}
      </div>
      <table>
        <thead>
          <tr>
            <th className="rowh" />
            {el.columns.map((c, ci) => (
              <th key={ci}>
                <span className="colref">{colName(ci)}</span>
                <input value={c} data-interactive readOnly={!selected} tabIndex={selected ? 0 : -1} onChange={(e) => setHeader(ci, e.target.value)} onFocus={() => useCanvas.getState().checkpoint(pageId)} onKeyDown={(e) => e.stopPropagation()} />
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {el.rows.map((row, ri) => (
            <tr key={ri}>
              <td className="rowh">{ri + 1}</td>
              {row.map((cell, ci) => {
                const key = `${ri}:${ci}`
                const isFormula = cell.trim().startsWith('=')
                const shown = focus === key ? cell : isFormula ? evald.display[ri][ci] : cell
                return (
                  <td key={ci} className={`${isFormula ? 'formula' : ''} ${evald.errors[ri][ci] ? 'err' : ''}`}>
                    <input
                      value={shown}
                      data-interactive
                      readOnly={!selected}
                      tabIndex={selected ? 0 : -1}
                      inputMode="decimal"
                      onFocus={() => {
                        setFocus(key)
                        useCanvas.getState().checkpoint(pageId)
                      }}
                      onBlur={() => setFocus(null)}
                      onChange={(e) => setCell(ri, ci, e.target.value)}
                      onKeyDown={(e) => {
                        e.stopPropagation()
                        if (e.key === 'Enter') {
                          const next = (e.currentTarget.closest('tr')?.nextElementSibling?.children[ci + 1] as HTMLElement | undefined)?.querySelector('input')
                          if (next) next.focus()
                          else {
                            addRow()
                            setTimeout(() => (e.target as HTMLElement).closest('tbody')?.lastElementChild?.children[ci + 1]?.querySelector('input')?.focus(), 30)
                          }
                        }
                      }}
                    />
                  </td>
                )
              })}
            </tr>
          ))}
        </tbody>
      </table>
      {selected && <div className="table-hint mono">Formulas: =A1*2 · =sum(B1:B5) · =mean(C:C)</div>}
    </div>
  )
}
