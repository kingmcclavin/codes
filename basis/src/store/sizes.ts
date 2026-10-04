import { create } from 'zustand'

/** Bumped whenever a block's measured size changes, so overlays can re-render. */
export const useSizes = create<{ v: number; bump: () => void }>((set, get) => ({
  v: 0,
  bump: () => set({ v: get().v + 1 }),
}))
