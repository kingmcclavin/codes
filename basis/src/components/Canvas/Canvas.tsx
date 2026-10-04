// The Engineering Canvas: an infinite, pan/zoomable page.
//
// Layers (back → front): template paper · background images (imported PDFs) ·
// highlighter ink · HTML blocks (text, maths, tables, graphs…) · pen ink & shapes ·
// selection overlay. All input goes through Pointer Events so mouse, touch and
// Apple Pencil share one code path (see services/input/pointerPolicy).

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type PointerEvent as RPointerEvent } from 'react'
import { isBlock, type CanvasElement, type Page, type ShapeElement, type StrokeElement, type Viewport } from '../../models'
import { make } from '../../services/canvas/factories'
import { elementBounds, rectsIntersect, round2, simplify, topElementAt, translateElement, unionBounds, type Rect } from '../../services/canvas/geometry'
import { outlineToPath, penOutline, polylinePath, resolveColor } from '../../services/canvas/ink'
import { insertImageFromPicker } from '../../services/canvas/insert'
import { uid } from '../../services/id'
import { pointerPolicy } from '../../services/input/pointerPolicy'
import { removeElements, useCanvas } from '../../store/canvas'
import { useLibrary } from '../../store/library'
import { useUI } from '../../store/ui'
import { EquationEditor } from '../Equation/EquationEditor'
import { BlockFrame } from './elements/BlockFrame'
import { GraphBlock } from './elements/GraphBlock'
import { CalcBlock, EquationBlock, ImageBlock, StickyBlock, TextBlock } from './elements/SimpleBlocks'
import { TableBlock } from './elements/TableBlock'
import { ShapeView, StrokeView } from './elements/VectorElements'
import { SelectionOverlay } from './SelectionOverlay'
import { pageColorVars, TemplateBackground } from './TemplateBackground'
import { ZoomControls } from './ZoomControls'
import './canvas.css'

const MIN_ZOOM = 0.1
const MAX_ZOOM = 8
const clampZoom = (z: number) => Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, z))
const EDITABLE = new Set(['text', 'equation', 'calc', 'sticky'])

type Pt = { x: number; y: number }

type Action =
  | { kind: 'pan'; id: number; start: Pt; vp0: Viewport }
  | { kind: 'stroke'; id: number; points: [number, number, number][]; tool: 'pen' | 'highlighter'; pressure: boolean }
  | { kind: 'erase'; id: number; ids: Set<string>; last: Pt }
  | { kind: 'move'; id: number; start: Pt; ids: string[]; moved: boolean; delta?: Pt }
  | { kind: 'marquee'; id: number; start: Pt; additive: string[]; rect?: Rect }
  | { kind: 'shape'; id: number; start: Pt; draft?: ShapeElement }
  | { kind: 'resize'; id: number; elId: string; start: Pt; w0: number; h0: number; keepAspect: boolean; heightToo: boolean; size?: { id: string; w: number; h: number } }
  | { kind: 'tap'; id: number; at: Pt; tool: 'image' }

/** In-app clipboard for copy / paste of canvas elements. */
let clipboard: CanvasElement[] = []

const isTypingTarget = (t: EventTarget | null) => {
  const el = t as HTMLElement | null
  return !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT' || el.isContentEditable)
}
const isInteractive = (t: HTMLElement) => !!t.closest('input, textarea, button, select, [contenteditable="true"], [data-interactive]')

export function Canvas({ page }: { page: Page }) {
  const containerRef = useRef<HTMLDivElement>(null)
  const liveRef = useRef<SVGPathElement>(null)
  const [size, setSize] = useState({ w: 1000, h: 800 })
  const [vp, setVpState] = useState<Viewport>(page.viewport)
  const vpRef = useRef(vp)
  const persistTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const tool = useCanvas((s) => s.tool)
  const options = useCanvas((s) => s.options)
  const selection = useCanvas((s) => s.selection)
  const editingId = useCanvas((s) => s.editingId)
  const touchPolicy = useUI((s) => s.settings.touchPolicy)

  const [moveDelta, setMoveDelta] = useState<Pt | null>(null)
  const [marquee, setMarquee] = useState<Rect | null>(null)
  const [erased, setErased] = useState<Set<string>>(() => new Set())
  const [draft, setDraft] = useState<ShapeElement | null>(null)
  const [resize, setResize] = useState<{ id: string; w: number; h: number } | null>(null)
  const [cursor, setCursor] = useState<Pt | null>(null)
  const [spaceHeld, setSpaceHeld] = useState(false)
  const [printVp, setPrintVp] = useState<(Viewport & { h: number }) | null>(null)

  const action = useRef<Action | null>(null)
  const pointers = useRef(new Map<number, { x: number; y: number; type: string }>())
  const pinch = useRef<{ d0: number; mid0: Pt; vp0: Viewport } | null>(null)
  const lastTap = useRef<{ id: string; t: number } | null>(null)
  const rectRef = useRef<DOMRect | null>(null)

  const elements = page.elements
  const elementsRef = useRef(elements)
  elementsRef.current = elements
  const pageId = page.id

  // ── Viewport ──────────────────────────────────────────────────────────────
  const setVp = useCallback(
    (v: Viewport) => {
      vpRef.current = v
      setVpState(v)
      if (persistTimer.current) clearTimeout(persistTimer.current)
      persistTimer.current = setTimeout(() => useLibrary.getState().updatePage(pageId, { viewport: vpRef.current }, { touch: false }), 500)
    },
    [pageId],
  )

  useLayoutEffect(() => {
    vpRef.current = page.viewport
    setVpState(page.viewport)
    action.current = null
    setMoveDelta(null)
    setDraft(null)
    setMarquee(null)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page.id])

  // Phones: fit the page to the screen the first time it's opened at default zoom.
  useEffect(() => {
    const node = containerRef.current
    if (node && node.clientWidth < 700 && page.viewport.zoom === 1 && page.viewport.x === 40) requestAnimationFrame(() => fitContent())
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page.id])

  useLayoutEffect(() => {
    const node = containerRef.current!
    const ro = new ResizeObserver(() => setSize({ w: node.clientWidth, h: node.clientHeight }))
    ro.observe(node)
    setSize({ w: node.clientWidth, h: node.clientHeight })
    return () => ro.disconnect()
  }, [])

  const toWorld = useCallback((clientX: number, clientY: number): Pt => {
    const r = rectRef.current ?? containerRef.current!.getBoundingClientRect()
    const v = vpRef.current
    return { x: (clientX - r.left - v.x) / v.zoom, y: (clientY - r.top - v.y) / v.zoom }
  }, [])

  const zoomAt = useCallback(
    (sx: number, sy: number, factor: number) => {
      const v = vpRef.current
      const z = clampZoom(v.zoom * factor)
      const k = z / v.zoom
      setVp({ zoom: z, x: sx - (sx - v.x) * k, y: sy - (sy - v.y) * k })
    },
    [setVp],
  )

  const fitContent = useCallback(() => {
    const b = unionBounds(elementsRef.current)
    const node = containerRef.current
    if (!node) return
    if (!b) return setVp({ x: 80, y: 60, zoom: 1 })
    const pad = 60
    const z = clampZoom(Math.min(1.25, (node.clientWidth - pad * 2) / b.w, (node.clientHeight - pad * 2 - 60) / b.h))
    setVp({ zoom: z, x: (node.clientWidth - b.w * z) / 2 - b.x * z, y: (node.clientHeight - b.h * z) / 2 - b.y * z + 20 })
  }, [setVp])

  // Register providers so panels/menus can talk to the active canvas.
  useEffect(() => {
    useCanvas.setState({
      centerProvider: () => {
        const node = containerRef.current!
        const v = vpRef.current
        return { x: (node.clientWidth / 2 - v.x) / v.zoom, y: (node.clientHeight / 2 - v.y) / v.zoom }
      },
      revealProvider: (id) => {
        const el = elementsRef.current.find((e) => e.id === id)
        const node = containerRef.current
        if (!el || !node) return
        const b = elementBounds(el)
        const v = vpRef.current
        setVp({ ...v, x: node.clientWidth / 2 - (b.x + b.w / 2) * v.zoom, y: node.clientHeight / 2 - (b.y + b.h / 2) * v.zoom })
        useCanvas.getState().setTool('select')
        useCanvas.getState().setSelection([id])
      },
      zoomProvider: (a) => {
        const node = containerRef.current!
        if (a === 'fit') return fitContent()
        if (a === 'reset') return zoomAt(node.clientWidth / 2, node.clientHeight / 2, 1 / vpRef.current.zoom)
        zoomAt(node.clientWidth / 2, node.clientHeight / 2, a === 'in' ? 1.25 : 0.8)
      },
      printProvider: () => {
        const b = unionBounds(elementsRef.current) ?? { x: 0, y: 0, w: 800, h: 600 }
        const pad = 40
        const z = Math.min(1, 720 / (b.w + pad * 2))
        setPrintVp({ x: -(b.x - pad) * z, y: -(b.y - pad) * z, zoom: z, h: (b.h + pad * 2) * z })
        const html = document.documentElement
        const prevTheme = html.dataset.theme
        html.dataset.theme = 'light'
        document.body.classList.add('printing')
        const done = () => {
          document.body.classList.remove('printing')
          if (prevTheme) html.dataset.theme = prevTheme
          setPrintVp(null)
          window.removeEventListener('afterprint', done)
        }
        window.addEventListener('afterprint', done)
        setTimeout(() => window.print(), 120)
      },
    })
    return () => useCanvas.setState({ centerProvider: null, revealProvider: null, zoomProvider: null, printProvider: null })
  }, [fitContent, setVp, zoomAt])

  // Wheel / trackpad: pinch (ctrlKey) zooms, scroll pans. Safari gesture events are blocked.
  useEffect(() => {
    const node = containerRef.current!
    const onWheel = (e: WheelEvent) => {
      if ((e.target as HTMLElement).closest('.calc-edit, .text-edit, .eq-editor')) return
      e.preventDefault()
      const r = node.getBoundingClientRect()
      const unit = e.deltaMode === 1 ? 16 : 1
      if (e.ctrlKey || e.metaKey) zoomAt(e.clientX - r.left, e.clientY - r.top, Math.exp(-e.deltaY * unit * 0.0085))
      else {
        const v = vpRef.current
        setVp({ ...v, x: v.x - e.deltaX * unit, y: v.y - e.deltaY * unit })
      }
    }
    const stop = (e: Event) => e.preventDefault()
    node.addEventListener('wheel', onWheel, { passive: false })
    node.addEventListener('gesturestart', stop)
    node.addEventListener('gesturechange', stop)
    return () => {
      node.removeEventListener('wheel', onWheel)
      node.removeEventListener('gesturestart', stop)
      node.removeEventListener('gesturechange', stop)
    }
  }, [setVp, zoomAt])

  // ── Commit helpers ────────────────────────────────────────────────────────
  const commit = useCallback((next: CanvasElement[]) => useCanvas.getState().commit(pageId, next), [pageId])

  const cancelAction = () => {
    const a = action.current
    action.current = null
    if (a?.kind === 'stroke' && liveRef.current) liveRef.current.setAttribute('d', '')
    setMoveDelta(null)
    setDraft(null)
    setMarquee(null)
    setErased(new Set())
    setResize(null)
  }

  // ── Pointer input ─────────────────────────────────────────────────────────
  const onPointerDown = (e: RPointerEvent) => {
    pointerPolicy.notePointer(e)
    const target = e.target as HTMLElement
    const blockEl = target.closest('.block') as HTMLElement | null
    const blockId = blockEl?.dataset.id
    const { selection: sel, editingId: editing } = useCanvas.getState()

    // Let interactive content inside a selected / editing block handle itself.
    if (blockId && editing === blockId) return
    if (blockId && isInteractive(target) && tool === 'select' && sel.includes(blockId)) return
    if (target.closest('.canvas-ui')) return

    e.preventDefault()
    const active = document.activeElement as HTMLElement | null
    if (active && active !== document.body && isTypingTarget(active)) active.blur()

    rectRef.current = containerRef.current!.getBoundingClientRect()
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY, type: e.pointerType })
    try {
      containerRef.current!.setPointerCapture(e.pointerId)
    } catch {
      /* synthetic events */
    }

    // Two fingers: pinch-zoom + pan. Discard anything the first finger started.
    const touches = [...pointers.current.values()].filter((p) => p.type === 'touch')
    if (e.pointerType === 'touch' && touches.length >= 2) {
      cancelAction()
      const [a, b] = touches
      const r = rectRef.current
      pinch.current = {
        d0: Math.hypot(a.x - b.x, a.y - b.y) || 1,
        mid0: { x: (a.x + b.x) / 2 - r.left, y: (a.y + b.y) / 2 - r.top },
        vp0: vpRef.current,
      }
      return
    }
    if (pinch.current) return

    const navigate =
      e.button === 1 || tool === 'hand' || spaceHeld || (e.pointerType === 'touch' && pointerPolicy.touchNavigates(touchPolicy))
    if (navigate) {
      action.current = { kind: 'pan', id: e.pointerId, start: { x: e.clientX, y: e.clientY }, vp0: vpRef.current }
      return
    }
    if (e.button === 2) return

    const w = toWorld(e.clientX, e.clientY)
    const tol = 6 / vpRef.current.zoom
    const els = elementsRef.current

    switch (tool) {
      case 'pen':
      case 'highlighter': {
        const pressure = e.pointerType === 'pen'
        action.current = { kind: 'stroke', id: e.pointerId, points: [[round2(w.x), round2(w.y), pointerPolicy.pressure(e)]], tool, pressure }
        const o = options[tool]
        const path = liveRef.current!
        if (tool === 'highlighter') {
          path.setAttribute('fill', 'none')
          path.setAttribute('stroke', resolveColor(o.color))
          path.setAttribute('stroke-width', String(o.width))
          path.setAttribute('stroke-opacity', String(o.opacity))
          path.setAttribute('fill-opacity', '1')
        } else {
          path.setAttribute('fill', resolveColor(o.color))
          path.setAttribute('fill-opacity', String(o.opacity))
          path.setAttribute('stroke', 'none')
        }
        updateLive()
        break
      }
      case 'eraser': {
        const ids = new Set<string>()
        eraseAt(w, w, ids)
        action.current = { kind: 'erase', id: e.pointerId, ids, last: w }
        setErased(new Set(ids))
        break
      }
      case 'select': {
        const handle = target.closest('[data-handle]') as HTMLElement | null
        if (handle) {
          const el = els.find((x) => x.id === handle.dataset.handle)
          if (el) {
            const b = elementBounds(el)
            action.current = {
              kind: 'resize',
              id: e.pointerId,
              elId: el.id,
              start: w,
              w0: b.w,
              h0: b.h,
              keepAspect: el.type === 'image',
              heightToo: el.type === 'image' || el.type === 'graph',
            }
          }
          return
        }
        const hit = topElementAt(els, w.x, w.y, tol)
        if (hit) {
          const now = performance.now()
          if (lastTap.current?.id === hit.id && now - lastTap.current.t < 380 && EDITABLE.has(hit.type)) {
            lastTap.current = null
            useCanvas.getState().setSelection([hit.id])
            useCanvas.getState().setEditing(hit.id)
            return
          }
          lastTap.current = { id: hit.id, t: now }
          let next = sel
          if (e.shiftKey) next = sel.includes(hit.id) ? sel.filter((x) => x !== hit.id) : [...sel, hit.id]
          else if (!sel.includes(hit.id)) next = [hit.id]
          useCanvas.getState().setSelection(next)
          if (editing && editing !== hit.id) useCanvas.getState().setEditing(null)
          action.current = { kind: 'move', id: e.pointerId, start: w, ids: next.filter((id) => !els.find((x) => x.id === id)?.locked), moved: false }
        } else {
          const selected = els.filter((x) => sel.includes(x.id))
          const sb = unionBounds(selected)
          if (sb && sel.length > 1 && w.x >= sb.x && w.x <= sb.x + sb.w && w.y >= sb.y && w.y <= sb.y + sb.h) {
            action.current = { kind: 'move', id: e.pointerId, start: w, ids: sel, moved: false }
          } else {
            if (!e.shiftKey) useCanvas.getState().setSelection([])
            useCanvas.getState().setEditing(null)
            action.current = { kind: 'marquee', id: e.pointerId, start: w, additive: e.shiftKey ? sel : [] }
          }
        }
        break
      }
      case 'text': {
        const hit = topElementAt(els, w.x, w.y, tol)
        if (hit && (hit.type === 'text' || hit.type === 'sticky')) {
          useCanvas.getState().setSelection([hit.id])
          useCanvas.getState().setEditing(hit.id)
          return
        }
        if (editing) {
          useCanvas.getState().setEditing(null)
          return
        }
        const o = options.text
        const el = make.text({ x: round2(w.x), y: round2(w.y - o.fontSize * 0.75) }, { fontSize: o.fontSize, color: o.color, font: o.font })
        commit([...els, el])
        useCanvas.getState().setSelection([el.id])
        useCanvas.getState().setEditing(el.id)
        break
      }
      case 'equation': {
        const hit = topElementAt(els, w.x, w.y, tol)
        if (hit && hit.type === 'equation') {
          useCanvas.getState().setSelection([hit.id])
          useCanvas.getState().setEditing(hit.id)
          return
        }
        if (editing) {
          useCanvas.getState().setEditing(null)
          return
        }
        const el = make.equation({ x: round2(w.x), y: round2(w.y - 18) })
        commit([...els, el])
        useCanvas.getState().setSelection([el.id])
        useCanvas.getState().setEditing(el.id)
        break
      }
      case 'shape':
      case 'line':
      case 'arrow':
        action.current = { kind: 'shape', id: e.pointerId, start: w }
        break
      case 'image':
        action.current = { kind: 'tap', id: e.pointerId, at: w, tool: 'image' }
        break
    }
  }

  const updateLive = () => {
    const a = action.current
    if (a?.kind !== 'stroke' || !liveRef.current) return
    const o = options[a.tool]
    const d = a.tool === 'highlighter' ? polylinePath(a.points) : outlineToPath(penOutline(a.points, o.width, !a.pressure, false))
    liveRef.current.setAttribute('d', d)
  }

  const eraseAt = (from: Pt, to: Pt, ids: Set<string>) => {
    const r = options.eraser.size / 2 / vpRef.current.zoom
    const steps = Math.max(1, Math.ceil(Math.hypot(to.x - from.x, to.y - from.y) / (r * 0.8)))
    const els = elementsRef.current
    for (let i = 0; i <= steps; i++) {
      const x = from.x + ((to.x - from.x) * i) / steps
      const y = from.y + ((to.y - from.y) * i) / steps
      for (const el of els) {
        if (ids.has(el.id) || isBlock(el) || el.locked) continue
        const b = elementBounds(el)
        if (x < b.x - r || x > b.x + b.w + r || y < b.y - r || y > b.y + b.h + r) continue
        if (topElementAt([el], x, y, r)) ids.add(el.id)
      }
    }
  }

  const onPointerMove = (e: RPointerEvent) => {
    const r = rectRef.current ?? containerRef.current!.getBoundingClientRect()
    if (tool === 'eraser' && e.pointerType !== 'touch') setCursor({ x: e.clientX - r.left, y: e.clientY - r.top })
    if (!pointers.current.has(e.pointerId)) return
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY, type: e.pointerType })

    if (pinch.current) {
      const touches = [...pointers.current.values()].filter((p) => p.type === 'touch')
      if (touches.length < 2) return
      const [a, b] = touches
      const { d0, mid0, vp0 } = pinch.current
      const d = Math.hypot(a.x - b.x, a.y - b.y) || 1
      const mid = { x: (a.x + b.x) / 2 - r.left, y: (a.y + b.y) / 2 - r.top }
      const z = clampZoom(vp0.zoom * (d / d0))
      const wx = (mid0.x - vp0.x) / vp0.zoom
      const wy = (mid0.y - vp0.y) / vp0.zoom
      setVp({ zoom: z, x: mid.x - wx * z, y: mid.y - wy * z })
      return
    }

    const a = action.current
    if (!a || a.id !== e.pointerId) return
    switch (a.kind) {
      case 'pan':
        setVp({ ...a.vp0, x: a.vp0.x + e.clientX - a.start.x, y: a.vp0.y + e.clientY - a.start.y })
        break
      case 'stroke': {
        const events = (e.nativeEvent as PointerEvent).getCoalescedEvents?.() ?? [e.nativeEvent]
        for (const ev of events.length ? events : [e.nativeEvent]) {
          const p = toWorld(ev.clientX, ev.clientY)
          const last = a.points[a.points.length - 1]
          if (Math.hypot(p.x - last[0], p.y - last[1]) * vpRef.current.zoom < 0.8) continue
          a.points.push([round2(p.x), round2(p.y), pointerPolicy.pressure(ev)])
        }
        updateLive()
        break
      }
      case 'erase': {
        const p = toWorld(e.clientX, e.clientY)
        const before = a.ids.size
        eraseAt(a.last, p, a.ids)
        a.last = p
        if (a.ids.size !== before) setErased(new Set(a.ids))
        break
      }
      case 'move': {
        const p = toWorld(e.clientX, e.clientY)
        const dx = p.x - a.start.x, dy = p.y - a.start.y
        if (!a.moved && Math.hypot(dx, dy) * vpRef.current.zoom < 3) return
        a.moved = true
        a.delta = { x: dx, y: dy }
        setMoveDelta(a.delta)
        break
      }
      case 'marquee': {
        const p = toWorld(e.clientX, e.clientY)
        a.rect = { x: Math.min(a.start.x, p.x), y: Math.min(a.start.y, p.y), w: Math.abs(p.x - a.start.x), h: Math.abs(p.y - a.start.y) }
        setMarquee(a.rect)
        break
      }
      case 'shape': {
        let p = toWorld(e.clientX, e.clientY)
        const kind = tool === 'shape' ? options.shape.kind : tool === 'line' ? 'line' : 'arrow'
        if (e.shiftKey) {
          if (kind === 'line' || kind === 'arrow') {
            const ang = Math.round(Math.atan2(p.y - a.start.y, p.x - a.start.x) / (Math.PI / 12)) * (Math.PI / 12)
            const len = Math.hypot(p.x - a.start.x, p.y - a.start.y)
            p = { x: a.start.x + Math.cos(ang) * len, y: a.start.y + Math.sin(ang) * len }
          } else {
            const s = Math.max(Math.abs(p.x - a.start.x), Math.abs(p.y - a.start.y))
            p = { x: a.start.x + Math.sign(p.x - a.start.x || 1) * s, y: a.start.y + Math.sign(p.y - a.start.y || 1) * s }
          }
        }
        const o = tool === 'shape' ? options.shape : tool === 'line' ? options.line : options.arrow
        a.draft = {
          id: 'draft',
          type: 'shape',
          shape: kind,
          x: round2(a.start.x),
          y: round2(a.start.y),
          x2: round2(p.x),
          y2: round2(p.y),
          color: o.color,
          width: o.width,
          opacity: o.opacity,
          fill: tool === 'shape' ? options.shape.fill : false,
          dashed: 'dashed' in o ? o.dashed : false,
        }
        setDraft(a.draft)
        break
      }
      case 'resize': {
        const p = toWorld(e.clientX, e.clientY)
        let w = Math.max(80, a.w0 + p.x - a.start.x)
        let h = a.heightToo ? Math.max(60, a.h0 + p.y - a.start.y) : a.h0
        if (a.keepAspect) h = (w * a.h0) / a.w0
        a.size = { id: a.elId, w: Math.round(w), h: Math.round(h) }
        setResize(a.size)
        break
      }
    }
  }

  const finish = (e: RPointerEvent, cancelled: boolean) => {
    pointers.current.delete(e.pointerId)
    if (pinch.current) {
      if ([...pointers.current.values()].filter((p) => p.type === 'touch').length < 2) pinch.current = null
      action.current = null
      return
    }
    const a = action.current
    if (!a || a.id !== e.pointerId) return
    action.current = null
    const els = elementsRef.current

    switch (a.kind) {
      case 'stroke': {
        liveRef.current?.setAttribute('d', '')
        if (cancelled) break
        const o = options[a.tool]
        const pts = simplify(a.points, 0.25 / Math.max(0.5, vpRef.current.zoom))
        const el: StrokeElement = { id: uid('e'), type: 'stroke', tool: a.tool, points: pts, color: o.color, width: o.width, opacity: o.opacity, x: pts[0][0], y: pts[0][1] }
        commit([...els, el])
        break
      }
      case 'erase':
        if (a.ids.size) commit(els.filter((x) => !a.ids.has(x.id)))
        setErased(new Set())
        break
      case 'move':
        if (a.moved && a.delta) {
          const { x: dx, y: dy } = a.delta
          const ids = new Set(a.ids)
          commit(els.map((x) => (ids.has(x.id) ? translateElement(x, round2(dx), round2(dy)) : x)))
        }
        setMoveDelta(null)
        break
      case 'marquee': {
        const m = a.rect
        setMarquee(null)
        if (!m || (m.w < 2 && m.h < 2)) break
        const hits = els.filter((x) => !(x.type === 'image' && x.background) && rectsIntersect(m, elementBounds(x))).map((x) => x.id)
        useCanvas.getState().setSelection([...new Set([...a.additive, ...hits])])
        break
      }
      case 'shape': {
        const d = a.draft
        setDraft(null)
        if (d && Math.hypot(d.x2 - d.x, d.y2 - d.y) > 4) commit([...els, { ...d, id: uid('e') }])
        break
      }
      case 'resize': {
        const r = a.size
        setResize(null)
        if (r) {
          const el = els.find((x) => x.id === r.id)
          if (el) {
            const patch = 'h' in el && (el.type === 'graph' || el.type === 'image') ? { w: r.w, h: r.h } : { w: r.w }
            commit(els.map((x) => (x.id === r.id ? ({ ...x, ...patch } as CanvasElement) : x)))
          }
        }
        break
      }
      case 'tap':
        if (!cancelled) void insertImageFromPicker(pageId, a.at)
        break
    }
  }

  // ── Keyboard ──────────────────────────────────────────────────────────────
  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if (useUI.getState().searchOpen || document.querySelector('.modal-backdrop')) return
      const mod = e.metaKey || e.ctrlKey
      const typing = isTypingTarget(e.target)
      const cs = useCanvas.getState()
      if (mod && e.key.toLowerCase() === 'z' && !typing) {
        e.preventDefault()
        if (e.shiftKey) cs.redo(pageId)
        else cs.undo(pageId)
        return
      }
      if (mod && e.key.toLowerCase() === 'y' && !typing) {
        e.preventDefault()
        cs.redo(pageId)
        return
      }
      if (typing) return
      if (e.key === ' ' && !e.repeat) {
        setSpaceHeld(true)
        e.preventDefault()
        return
      }
      const els = elementsRef.current
      const sel = cs.selection
      if ((e.key === 'Delete' || e.key === 'Backspace') && sel.length) {
        e.preventDefault()
        removeElements(pageId, sel)
        return
      }
      if (e.key === 'Escape') {
        cs.setSelection([])
        cs.setEditing(null)
        return
      }
      if (e.key === 'Enter' && sel.length === 1) {
        const el = els.find((x) => x.id === sel[0])
        if (el && EDITABLE.has(el.type)) {
          e.preventDefault()
          cs.setEditing(el.id)
        }
        return
      }
      if (mod) {
        const k = e.key.toLowerCase()
        if (k === 'a') {
          e.preventDefault()
          cs.setTool('select')
          cs.setSelection(els.filter((x) => !(x.type === 'image' && x.background)).map((x) => x.id))
        } else if (k === 'd' && sel.length) {
          e.preventDefault()
          const copies = els.filter((x) => sel.includes(x.id)).map((x) => ({ ...translateElement(x, 24, 24), id: uid('e') }))
          commit([...els, ...copies])
          cs.setSelection(copies.map((c) => c.id))
        } else if (k === 'c' && sel.length) {
          clipboard = els.filter((x) => sel.includes(x.id)).map((x) => structuredClone(x))
        } else if (k === 'x' && sel.length) {
          clipboard = els.filter((x) => sel.includes(x.id)).map((x) => structuredClone(x))
          removeElements(pageId, sel)
        } else if (k === 'v' && clipboard.length) {
          e.preventDefault()
          const c = cs.centerProvider?.() ?? { x: 0, y: 0 }
          const b = unionBounds(clipboard)!
          const copies = clipboard.map((x) => ({ ...translateElement(x, c.x - b.x - b.w / 2, c.y - b.y - b.h / 2), id: uid('e') }))
          commit([...els, ...copies])
          cs.setTool('select')
          cs.setSelection(copies.map((x) => x.id))
        } else if (k === '0') {
          e.preventDefault()
          cs.zoomProvider?.('reset')
        } else if (k === '1') {
          e.preventDefault()
          cs.zoomProvider?.('fit')
        } else if (k === '=' || k === '+') {
          e.preventDefault()
          cs.zoomProvider?.('in')
        } else if (k === '-') {
          e.preventDefault()
          cs.zoomProvider?.('out')
        }
        return
      }
      if (e.key.startsWith('Arrow') && sel.length) {
        e.preventDefault()
        const step = e.shiftKey ? 10 : 1
        const dx = e.key === 'ArrowLeft' ? -step : e.key === 'ArrowRight' ? step : 0
        const dy = e.key === 'ArrowUp' ? -step : e.key === 'ArrowDown' ? step : 0
        commit(els.map((x) => (sel.includes(x.id) ? translateElement(x, dx, dy) : x)))
        return
      }
      const map: Record<string, Parameters<typeof cs.setTool>[0]> = {
        v: 'select', h: 'hand', p: 'pen', m: 'highlighter', e: 'eraser', t: 'text', s: 'shape', l: 'line', a: 'arrow', q: 'equation', '=': 'equation', i: 'image',
      }
      const t = map[e.key.toLowerCase()]
      if (t && !e.altKey) cs.setTool(t)
    }
    const up = (e: KeyboardEvent) => {
      if (e.key === ' ') setSpaceHeld(false)
    }
    window.addEventListener('keydown', down)
    window.addEventListener('keyup', up)
    return () => {
      window.removeEventListener('keydown', down)
      window.removeEventListener('keyup', up)
    }
  }, [pageId, commit])

  // ── Render ────────────────────────────────────────────────────────────────
  const selSet = useMemo(() => new Set(selection), [selection])
  const layers = useMemo(() => {
    const bg: CanvasElement[] = []
    const hl: StrokeElement[] = []
    const blocks: CanvasElement[] = []
    const ink: CanvasElement[] = []
    for (const el of elements) {
      if (erased.has(el.id)) continue
      if (el.type === 'image' && el.background) bg.push(el)
      else if (el.type === 'stroke' && el.tool === 'highlighter') hl.push(el)
      else if (isBlock(el)) blocks.push(el)
      else ink.push(el)
    }
    return { bg, hl, blocks, ink }
  }, [elements, erased])

  const moving = moveDelta ? moveDelta : null
  const view = printVp ?? vp
  const worldTransform = `translate(${view.x}px, ${view.y}px) scale(${view.zoom})`
  const editingEl = editingId ? elements.find((x) => x.id === editingId) : undefined

  const renderVector = (els: CanvasElement[]) => {
    const still: CanvasElement[] = []
    const moved: CanvasElement[] = []
    for (const el of els) (moving && selSet.has(el.id) ? moved : still).push(el)
    const draw = (el: CanvasElement) =>
      el.type === 'stroke' ? <StrokeView key={el.id} el={el} /> : el.type === 'shape' ? <ShapeView key={el.id} el={el} /> : null
    return (
      <>
        {still.map(draw)}
        {moved.length > 0 && <g transform={`translate(${moving!.x} ${moving!.y})`}>{moved.map(draw)}</g>}
      </>
    )
  }

  const renderBlock = (el: CanvasElement) => {
    const selected = selSet.has(el.id)
    const editing = editingId === el.id
    const props = { pageId, selected, editing }
    const offset = moving && selected ? { dx: moving.x, dy: moving.y } : null
    const sz = resize?.id === el.id ? resize : null
    let content: React.ReactNode = null
    switch (el.type) {
      case 'text':
        content = <TextBlock el={el} {...props} />
        break
      case 'equation':
        content = <EquationBlock el={el} {...props} />
        break
      case 'calc':
        content = <CalcBlock el={el} {...props} />
        break
      case 'table':
        content = <TableBlock el={el} {...props} />
        break
      case 'graph':
        content = <GraphBlock el={sz ? { ...el, w: sz.w, h: sz.h } : el} {...props} />
        break
      case 'image':
        content = <ImageBlock el={el} {...props} />
        break
      case 'sticky':
        content = <StickyBlock el={el} {...props} />
        break
    }
    return (
      <BlockFrame key={el.id} el={el} selected={selected} editing={editing} offset={offset} size={sz}>
        {content}
      </BlockFrame>
    )
  }

  const cursorClass = spaceHeld ? 'grab' : tool

  return (
    <div
      ref={containerRef}
      className={`canvas tool-${cursorClass} ${printVp ? 'print-mode' : ''}`}
      data-tool={tool}
      style={{ ...pageColorVars(page.templateOptions.pageColor), height: printVp ? printVp.h : undefined }}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={(e) => finish(e, false)}
      onPointerCancel={(e) => finish(e, true)}
      onPointerLeave={() => setCursor(null)}
      onContextMenu={(e) => e.preventDefault()}
    >
      <TemplateBackground vp={view} template={page.template} opts={page.templateOptions} width={printVp ? 820 : size.w} height={printVp ? printVp.h : size.h} />
      <div className="world" key={page.id} style={{ transform: worldTransform }}>
        {layers.bg.map(renderBlock)}
        <svg className="layer">{renderVector(layers.hl)}</svg>
        {layers.blocks.map(renderBlock)}
        <svg className="layer">
          {renderVector(layers.ink)}
          {draft && <ShapeView el={draft} />}
          <path ref={liveRef} className="live-stroke" />
        </svg>
        {!printVp && (
          <SelectionOverlay
            pageId={pageId}
            elements={elements}
            selection={selection}
            editingId={editingId}
            moveDelta={moving}
            resize={resize}
            marquee={marquee}
            zoom={vp.zoom}
            showHandles={tool === 'select'}
          />
        )}
      </div>
      {tool === 'eraser' && cursor && (
        <div className="eraser-cursor" style={{ left: cursor.x, top: cursor.y, width: options.eraser.size, height: options.eraser.size }} />
      )}
      <ZoomControls zoom={vp.zoom} />
      {editingEl?.type === 'equation' && <EquationEditor key={editingEl.id} el={editingEl} pageId={pageId} />}
    </div>
  )
}
