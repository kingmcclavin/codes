import { useEffect, useRef } from 'react'
import type { GraphElement } from '../../../models'
import { sourceToTex } from '../../../services/calculations/tex'
import { uid } from '../../../services/id'
import { updateElement, useCanvas } from '../../../store/canvas'
import { Icon } from '../../common/Icon'
import { Tex } from '../../Equation/Tex'
import { Plot, PLOT_PAD } from '../../Graph/Plot'
import { usePageEval } from '../PageContext'
import type { BlockProps } from './BlockFrame'

const COLORS = ['#ff6b2c', '#3b82f6', '#14b8a6', '#a855f7', '#eab308', '#ef4444']
const HEAD = 36

export function GraphBlock({ el, pageId, selected }: BlockProps<GraphElement>) {
  const { numericScope } = usePageEval()
  const plotRef = useRef<HTMLDivElement>(null)
  const latest = useRef(el)
  latest.current = el

  const setView = (view: GraphElement['view'], record = false) => updateElement(pageId, el.id, { view }, record)

  const zoom = (factor: number, cx?: number, cy?: number) => {
    const v = latest.current.view
    const mx = cx ?? (v.xmin + v.xmax) / 2
    const my = cy ?? (v.ymin + v.ymax) / 2
    setView({ xmin: mx + (v.xmin - mx) * factor, xmax: mx + (v.xmax - mx) * factor, ymin: my + (v.ymin - my) * factor, ymax: my + (v.ymax - my) * factor }, true)
  }

  // Wheel to zoom when selected (non-passive so the canvas doesn't zoom too).
  useEffect(() => {
    const node = plotRef.current
    if (!node || !selected) return
    const onWheel = (e: WheelEvent) => {
      e.preventDefault()
      e.stopPropagation()
      const r = node.getBoundingClientRect()
      const v = latest.current.view
      const sc = r.width / latest.current.w
      const iw = latest.current.w - PLOT_PAD.l - PLOT_PAD.r
      const ih = latest.current.h - HEAD - PLOT_PAD.t - PLOT_PAD.b
      const fx = ((e.clientX - r.left) / sc - PLOT_PAD.l) / iw
      const fy = ((e.clientY - r.top) / sc - PLOT_PAD.t) / ih
      const cx = v.xmin + fx * (v.xmax - v.xmin)
      const cy = v.ymax - fy * (v.ymax - v.ymin)
      const f = Math.exp(e.deltaY * 0.0025)
      setView({ xmin: cx + (v.xmin - cx) * f, xmax: cx + (v.xmax - cx) * f, ymin: cy + (v.ymin - cy) * f, ymax: cy + (v.ymax - cy) * f })
    }
    node.addEventListener('wheel', onWheel, { passive: false })
    return () => node.removeEventListener('wheel', onWheel)
  }, [selected]) // eslint-disable-line react-hooks/exhaustive-deps

  // Drag to pan the plot (only once selected; otherwise the canvas moves the block).
  const onPointerDown = (e: React.PointerEvent) => {
    if (!selected) return
    e.stopPropagation()
    e.preventDefault()
    const node = plotRef.current!
    const r = node.getBoundingClientRect()
    const start = { x: e.clientX, y: e.clientY, view: latest.current.view }
    useCanvas.getState().checkpoint(pageId)
    const sc = r.width / latest.current.w
    const pxW = sc * (latest.current.w - PLOT_PAD.l - PLOT_PAD.r)
    const pxH = sc * (latest.current.h - HEAD - PLOT_PAD.t - PLOT_PAD.b)
    const move = (ev: PointerEvent) => {
      const v = start.view
      const dx = ((ev.clientX - start.x) / pxW) * (v.xmax - v.xmin)
      const dy = ((ev.clientY - start.y) / pxH) * (v.ymax - v.ymin)
      setView({ xmin: v.xmin - dx, xmax: v.xmax - dx, ymin: v.ymin + dy, ymax: v.ymax + dy })
    }
    const up = () => {
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
    }
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
  }

  const setFn = (id: string, expr: string) =>
    updateElement(pageId, el.id, { functions: el.functions.map((f) => (f.id === id ? { ...f, expr } : f)) }, false)
  const addFn = () =>
    updateElement(pageId, el.id, { functions: [...el.functions, { id: uid('fn'), expr: 'y = ', color: COLORS[el.functions.length % COLORS.length] }] })
  const removeFn = (id: string) => updateElement(pageId, el.id, { functions: el.functions.filter((f) => f.id !== id) })
  const reset = () => setView({ xmin: -10, xmax: 10, ymin: -6.5, ymax: 6.5 }, true)

  return (
    <div className="graph-block">
      <div className="graph-head">
        <Icon name="graph" size={14} />
        <div className="graph-fns">
          {el.functions.map((f) =>
            selected ? (
              <span key={f.id} className="graph-fn-edit" data-interactive>
                <i style={{ background: f.color }} />
                <input
                  value={f.expr}
                  spellCheck={false}
                  onFocus={() => useCanvas.getState().checkpoint(pageId)}
                  onChange={(e) => setFn(f.id, e.target.value)}
                  onKeyDown={(e) => e.stopPropagation()}
                  style={{ width: Math.max(60, f.expr.length * 7.4 + 12) }}
                />
                <button className="x" onClick={() => removeFn(f.id)} aria-label="Remove">
                  <Icon name="close" size={11} />
                </button>
              </span>
            ) : (
              <span key={f.id} className="graph-fn">
                <i style={{ background: f.color }} />
                <Tex tex={sourceToTex(f.expr)} />
              </span>
            ),
          )}
          {(el.series ?? []).map((s) => (
            <span key={s.id} className="graph-fn">
              <i className="pt" style={{ borderColor: s.color }} />
              <span className="mono">{s.label}</span>
            </span>
          ))}
        </div>
        {selected && (
          <div className="block-tools" data-interactive>
            <button className="icon-btn sm" onClick={addFn} data-tip="Add function">
              <Icon name="plus" size={14} />
            </button>
            <button className="icon-btn sm" onClick={() => zoom(0.7)} data-tip="Zoom in">
              <Icon name="zoomIn" size={14} />
            </button>
            <button className="icon-btn sm" onClick={() => zoom(1 / 0.7)} data-tip="Zoom out">
              <Icon name="zoomOut" size={14} />
            </button>
            <button className="icon-btn sm" onClick={reset} data-tip="Reset view">
              <Icon name="fit" size={14} />
            </button>
          </div>
        )}
      </div>
      <div ref={plotRef} className={`graph-plot ${selected ? 'live' : ''}`} data-interactive={selected ? '' : undefined} onPointerDown={onPointerDown}>
        <Plot w={el.w} h={el.h - HEAD} view={el.view} functions={el.functions} series={el.series} scope={numericScope} xLabel={el.xLabel} yLabel={el.yLabel} />
      </div>
    </div>
  )
}

