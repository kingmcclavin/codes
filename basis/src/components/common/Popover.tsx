import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { Icon } from './Icon'

export type Anchor = { x: number; y: number; w?: number; h?: number }

export function anchorOf(el: Element | null): Anchor {
  const r = el?.getBoundingClientRect()
  return r ? { x: r.left, y: r.top, w: r.width, h: r.height } : { x: 100, y: 100 }
}

/** A floating panel anchored to a point/rect, clamped to the viewport. */
export function Popover({
  anchor,
  onClose,
  children,
  align = 'start',
  placement = 'bottom',
  className = '',
  width,
}: {
  anchor: Anchor
  onClose: () => void
  children: ReactNode
  align?: 'start' | 'end' | 'center'
  placement?: 'bottom' | 'top' | 'right'
  className?: string
  width?: number
}) {
  const ref = useRef<HTMLDivElement>(null)
  const [pos, setPos] = useState<{ left: number; top: number } | null>(null)

  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    const r = el.getBoundingClientRect()
    const vw = window.innerWidth
    const vh = window.innerHeight
    const aw = anchor.w ?? 0
    const ah = anchor.h ?? 0
    let left: number
    let top: number
    if (placement === 'right') {
      left = anchor.x + aw + 8
      top = anchor.y
    } else {
      left = align === 'end' ? anchor.x + aw - r.width : align === 'center' ? anchor.x + aw / 2 - r.width / 2 : anchor.x
      top = placement === 'top' ? anchor.y - r.height - 8 : anchor.y + ah + 6
      if (top + r.height > vh - 8 && placement === 'bottom') top = Math.max(8, anchor.y - r.height - 6)
    }
    left = Math.max(8, Math.min(left, vw - r.width - 8))
    top = Math.max(8, Math.min(top, vh - r.height - 8))
    setPos({ left, top })
  }, [anchor.x, anchor.y, anchor.w, anchor.h, align, placement])

  useEffect(() => {
    const down = (e: PointerEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose()
    }
    const key = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    const t = setTimeout(() => window.addEventListener('pointerdown', down, true), 0)
    window.addEventListener('keydown', key)
    return () => {
      clearTimeout(t)
      window.removeEventListener('pointerdown', down, true)
      window.removeEventListener('keydown', key)
    }
  }, [onClose])

  return createPortal(
    <div
      ref={ref}
      className={`popover ui ${className}`}
      style={{ left: pos?.left ?? -9999, top: pos?.top ?? -9999, width }}
      onPointerDown={(e) => e.stopPropagation()}
    >
      {children}
    </div>,
    document.body,
  )
}

export interface MenuItem {
  label?: string
  icon?: string
  danger?: boolean
  kbd?: string
  onSelect?: () => void
  separator?: boolean
}

export function Menu({ anchor, items, onClose, align = 'start' }: { anchor: Anchor; items: MenuItem[]; onClose: () => void; align?: 'start' | 'end' }) {
  return (
    <Popover anchor={anchor} onClose={onClose} align={align}>
      {items.map((it, i) =>
        it.separator ? (
          <div key={i} className="menu-sep" />
        ) : (
          <button
            key={i}
            className={`menu-item ${it.danger ? 'danger' : ''}`}
            onClick={() => {
              onClose()
              it.onSelect?.()
            }}
          >
            {it.icon && <Icon name={it.icon} size={16} />}
            <span>{it.label}</span>
            {it.kbd && <span className="kbd">{it.kbd}</span>}
          </button>
        ),
      )}
    </Popover>
  )
}

export function Modal({ title, onClose, children, footer, width = 520 }: { title: string; onClose: () => void; children: ReactNode; footer?: ReactNode; width?: number }) {
  useEffect(() => {
    const key = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', key)
    return () => window.removeEventListener('keydown', key)
  }, [onClose])
  return createPortal(
    <div className="modal-backdrop" onPointerDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal" style={{ maxWidth: width }} role="dialog" aria-label={title}>
        <div className="modal-head">
          <h2>{title}</h2>
          <button className="icon-btn sm" onClick={onClose} aria-label="Close">
            <Icon name="close" size={16} />
          </button>
        </div>
        <div className="modal-body">{children}</div>
        {footer && <div className="modal-foot">{footer}</div>}
      </div>
    </div>,
    document.body,
  )
}
