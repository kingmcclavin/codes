// Apple Pencil / touch policy. In the browser we only have Pointer Events:
// `pointerType === 'pen'` identifies the Pencil and `pressure` gives force.
// This module is the single place deciding "does this touch draw or navigate?"
// — the native iPad app replaces it with PencilKit + UITouch.type.

import type { TouchPolicy } from '../../models'

let penSeen = false

export const pointerPolicy = {
  notePointer(e: PointerEvent | React.PointerEvent) {
    if (e.pointerType === 'pen') penSeen = true
  },
  get penSeen() {
    return penSeen
  },
  /** Should a single-finger touch pan the canvas instead of using the tool? */
  touchNavigates(policy: TouchPolicy): boolean {
    if (policy === 'navigate') return true
    if (policy === 'draw') return false
    return penSeen // auto: once a Pencil is detected, fingers navigate (palm rejection)
  },
  pressure(e: PointerEvent | React.PointerEvent): number {
    if (e.pointerType === 'pen') return e.pressure > 0 ? e.pressure : 0.5
    return 0.5
  },
}
