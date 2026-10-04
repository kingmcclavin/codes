export function relativeTime(ts: number, now = Date.now()): string {
  if (!ts) return 'never'
  const d = now - ts
  const min = 60_000
  const day = 86_400_000
  if (d < min) return 'just now'
  if (d < 60 * min) return `${Math.floor(d / min)} min ago`
  const startOfToday = new Date(now).setHours(0, 0, 0, 0)
  if (ts >= startOfToday) return 'today'
  if (ts >= startOfToday - day) return 'yesterday'
  if (d < 7 * day) return `${Math.ceil((startOfToday - ts) / day)} days ago`
  return new Date(ts).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: new Date(ts).getFullYear() === new Date(now).getFullYear() ? undefined : 'numeric' })
}

export const pluralize = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`
