import { useState } from 'react'
import type { CanvasElement } from '../../models'
import { elementBounds, translateElement, type Rect } from '../../services/canvas/geometry'
import { INK_COLORS, resolveColor } from '../../services/canvas/ink'
import { uid } from '../../services/id'
import { removeElements, useCanvas } from '../../store/canvas'
import { useLibrary } from '../../store/library'
import { useSizes } from '../../store/sizes'
import { Icon } from '../common/Icon'

const RESIZABLE = new Set(['text', 'calc', 'sticky', 'graph', 'image'])
const EDITABLE = new Set(['text', 'equation', 'calc', 'sticky'])
const COLORABLE = new Set(['stroke', 'shape', 'text', 'equation'])

export function SelectionOverlay({
  elements,
  selection,
  editingId,
  moveDelta,
  resize,
  marquee,
  zoom,
  showHandles,
  pageId,
}: {
  pageId: string
  elements: CanvasElement[]
  selection: string[]
  editingId: string | null
  moveDelta: { x: number; y: number } | null
  resize: { id: string; w: number; h: number } | null
  marquee: Rect | null
  zoom: number
  showHandles: boolean
}) {
  useSizes((s) => s.v) // re-render when blocks are measured
  const [colors, setColors] = useState(false)
  const selected = elements.filter((e) => selection.includes(e.id))
  const inv = 1 / zoom

  const boxes = selected.map((el) => {
    const b = elementBounds(el)
    const r = resize?.id === el.id ? { ...b, w: resize.w, h: el.type === 'graph' || el.type === 'image' ? resize.h : b.h } : b
    return { id: el.id, x: r.x + (moveDelta?.x ?? 0), y: r.y + (moveDelta?.y ?? 0), w: r.w, h: r.h }
  })
  let union: Rect | null = null
  if (boxes.length) {
    const x1 = Math.min(...boxes.map((b) => b.x)), y1 = Math.min(...boxes.map((b) => b.y))
    const x2 = Math.max(...boxes.map((b) => b.x + b.w)), y2 = Math.max(...boxes.map((b) => b.y + b.h))
    union = { x: x1, y: y1, w: x2 - x1, h: y2 - y1 }
  }
  const single = selected.length === 1 ? selected[0] : null
  const pad = 6 * inv

  const act = (fn: (pageId: string, els: CanvasElement[]) => void) => () => {
    if (!pageId) return
    fn(pageId, useLibrary.getState().pages[pageId].elements)
  }
  const duplicate = act((pid, els) => {
    const copies = els.filter((x) => selection.includes(x.id)).map((x) => ({ ...translateElement(x, 24, 24), id: uid('e') }))
    useCanvas.getState().commit(pid, [...els, ...copies])
    useCanvas.getState().setSelection(copies.map((c) => c.id))
  })
  const toFront = act((pid, els) => useCanvas.getState().commit(pid, [...els.filter((x) => !selection.includes(x.id)), ...els.filter((x) => selection.includes(x.id))]))
  const toBack = act((pid, els) => useCanvas.getState().commit(pid, [...els.filter((x) => selection.includes(x.id)), ...els.filter((x) => !selection.includes(x.id))]))
  const recolor = (c: string) =>
    act((pid, els) => useCanvas.getState().commit(pid, els.map((x) => (selection.includes(x.id) && COLORABLE.has(x.type) ? ({ ...x, color: c } as CanvasElement) : x))))()

  return (
    <>
      <svg className="layer overlay">
        {marquee && (
          <rect x={marquee.x} y={marquee.y} width={marquee.w} height={marquee.h} className="marquee" strokeWidth={inv} />
        )}
        {boxes.length > 1 &&
          boxes.map((b) => <rect key={b.id} x={b.x - 2 * inv} y={b.y - 2 * inv} width={b.w + 4 * inv} height={b.h + 4 * inv} className="sel-item" strokeWidth={inv} />)}
        {union && editingId !== single?.id && (
          <rect x={union.x - pad} y={union.y - pad} width={union.w + pad * 2} height={union.h + pad * 2} className="sel-box" strokeWidth={1.25 * inv} rx={3 * inv} />
        )}
      </svg>
      {union && showHandles && !moveDelta && editingId !== single?.id && (
        <div
          className="sel-bar canvas-ui"
          style={{ left: union.x + union.w / 2, top: union.y - pad, transform: `translate(-50%, -100%) scale(${inv}) translateY(-8px)` }}
        >
          {single && EDITABLE.has(single.type) && (
            <button className="icon-btn sm" onClick={() => useCanvas.getState().setEditing(single.id)} data-tip="Edit (Enter)">
              <Icon name="edit" size={15} />
            </button>
          )}
          {selected.some((x) => COLORABLE.has(x.type)) && (
            <div className="sel-colors">
              <button className="icon-btn sm" onClick={() => setColors(!colors)} data-tip="Colour">
                <span className="color-dot" style={{ background: resolveColor((selected.find((x) => COLORABLE.has(x.type)) as { color: string }).color) }} />
              </button>
              {colors && (
                <div className="sel-swatches">
                  {INK_COLORS.map((c) => (
                    <button key={c} className="swatch-dot" style={{ background: resolveColor(c) }} onClick={() => recolor(c)} aria-label={c} />
                  ))}
                </div>
              )}
            </div>
          )}
          <button className="icon-btn sm" onClick={duplicate} data-tip="Duplicate (⌘D)">
            <Icon name="copy" size={15} />
          </button>
          <button className="icon-btn sm" onClick={toFront} data-tip="Bring to front">
            <Icon name="upload" size={15} />
          </button>
          <button className="icon-btn sm" onClick={toBack} data-tip="Send to back">
            <Icon name="download" size={15} />
          </button>
          <span className="vsep" />
          <button className="icon-btn sm danger" onClick={() => pageId && removeElements(pageId, selection)} data-tip="Delete (⌫)">
            <Icon name="trash" size={15} />
          </button>
        </div>
      )}
      {single && showHandles && RESIZABLE.has(single.type) && union && editingId !== single.id && (
        <div className="resize-handle" data-handle={single.id} style={{ left: union.x + union.w + pad, top: union.y + union.h + pad, transform: `translate(-50%, -50%) scale(${inv})` }} />
      )}
    </>
  )
}

