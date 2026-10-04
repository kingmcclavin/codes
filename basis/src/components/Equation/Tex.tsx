import katex from 'katex'
import { memo, useMemo } from 'react'

/** Render a TeX string with KaTeX. Never throws; shows the source in red on error. */
export const Tex = memo(function Tex({ tex, display = false, className }: { tex: string; display?: boolean; className?: string }) {
  const html = useMemo(() => {
    try {
      return katex.renderToString(tex || '\\;', { displayMode: display, throwOnError: false, strict: 'ignore', trust: false, output: 'html' })
    } catch {
      return `<span style="color:var(--danger)">${tex.replace(/</g, '&lt;')}</span>`
    }
  }, [tex, display])
  return <span className={className} dangerouslySetInnerHTML={{ __html: html }} />
})

/** Render text with inline $…$ maths segments. */
export const RichText = memo(function RichText({ text }: { text: string }) {
  const parts = useMemo(() => {
    const out: { math: boolean; s: string }[] = []
    const re = /\$([^$\n]+)\$/g
    let last = 0
    let m: RegExpExecArray | null
    while ((m = re.exec(text))) {
      if (m.index > last) out.push({ math: false, s: text.slice(last, m.index) })
      out.push({ math: true, s: m[1] })
      last = m.index + m[0].length
    }
    if (last < text.length) out.push({ math: false, s: text.slice(last) })
    return out
  }, [text])
  return (
    <>
      {parts.map((p, i) => (p.math ? <Tex key={i} tex={p.s} /> : <span key={i}>{p.s}</span>))}
    </>
  )
})
