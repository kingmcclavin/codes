import { useLayoutEffect, useRef, type ReactNode } from 'react'
import type { CanvasElement } from '../../../models'
import { blockSizes } from '../../../services/canvas/geometry'
import { useSizes } from '../../../store/sizes'

export interface BlockProps<T extends CanvasElement> {
  el: T
  pageId: string
  selected: boolean
  editing: boolean
}

/** Positions a block in world space and reports its measured size. */
export function BlockFrame({
  el,
  selected,
  editing,
  offset,
  size,
  className = '',
  children,
}: {
  el: CanvasElement
  selected: boolean
  editing: boolean
  offset?: { dx: number; dy: number } | null
  size?: { w?: number; h?: number } | null
  className?: string
  children: ReactNode
}) {
  const ref = useRef<HTMLDivElement>(null)
  useLayoutEffect(() => {
    const node = ref.current
    if (!node) return
    const measure = () => {
      const prev = blockSizes.get(el.id)
      const w = node.offsetWidth
      const h = node.offsetHeight
      if (!prev || prev.w !== w || prev.h !== h) {
        blockSizes.set(el.id, { w, h })
        useSizes.getState().bump()
      }
    }
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(node)
    return () => ro.disconnect()
  }, [el.id])

  const w = size?.w ?? ('w' in el ? el.w : undefined)
  const h = size?.h ?? (el.type === 'graph' || el.type === 'image' ? el.h : undefined)

  return (
    <div
      ref={ref}
      data-id={el.id}
      className={`block block-${el.type} ${selected ? 'selected' : ''} ${editing ? 'editing' : ''} ${className}`}
      style={{
        left: el.x,
        top: el.y,
        width: w,
        height: h,
        transform: offset ? `translate(${offset.dx}px, ${offset.dy}px)` : undefined,
      }}
    >
      {children}
    </div>
  )
}
