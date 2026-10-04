// The Basis mark: two orthonormal basis vectors (ê₁, ê₂) from a common origin,
// set inside a precise frame. Swap this file for the official asset when available.

export function LogoMark({ size = 22 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" fill="none" aria-label="Basis">
      <rect x="1.5" y="1.5" width="29" height="29" rx="7" stroke="currentColor" strokeOpacity="0.22" strokeWidth="1.5" />
      <path d="M9 23V9.5" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />
      <path d="M5.8 12.6L9 9.2l3.2 3.4" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M9 23h13.5" stroke="var(--accent)" strokeWidth="2.2" strokeLinecap="round" />
      <path d="M19.4 19.8l3.4 3.2-3.4 3.2" stroke="var(--accent)" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="9" cy="23" r="1.9" fill="currentColor" />
    </svg>
  )
}

export function Wordmark({ size = 22 }: { size?: number }) {
  return (
    <span className="wordmark" style={{ display: 'inline-flex', alignItems: 'center', gap: size * 0.42 }}>
      <LogoMark size={size} />
      <span style={{ fontSize: size * 0.62, letterSpacing: '0.32em', fontWeight: 600, fontFamily: 'var(--font-mono)' }}>BASIS</span>
    </span>
  )
}
