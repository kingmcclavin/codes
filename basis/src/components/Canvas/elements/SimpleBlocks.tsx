import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { CalcElement, EquationElement, ImageElement, StickyElement, TextElement } from '../../../models'
import { sourceToTex } from '../../../services/calculations/tex'
import { resolveColor } from '../../../services/canvas/ink'
import { fileUrl } from '../../../services/files'
import { removeElements, updateElement, useCanvas } from '../../../store/canvas'
import { useLibrary } from '../../../store/library'
import { Icon } from '../../common/Icon'
import { RichText, Tex } from '../../Equation/Tex'
import { usePageEval } from '../PageContext'
import type { BlockProps } from './BlockFrame'

function autosize(t: HTMLTextAreaElement | null) {
  if (!t) return
  t.style.height = '0px'
  t.style.height = t.scrollHeight + 'px'
}

/** Begin a live edit: one undo checkpoint, then un-recorded updates while typing. */
function useEditSession(pageId: string, editing: boolean) {
  useEffect(() => {
    if (editing) useCanvas.getState().checkpoint(pageId)
  }, [editing, pageId])
}

const finishEditing = () => useCanvas.getState().setEditing(null)

function focusEnd(t: HTMLTextAreaElement | HTMLInputElement | null) {
  if (!t) return
  t.focus({ preventScroll: true })
  const n = t.value.length
  t.setSelectionRange(n, n)
}

// ── Text ─────────────────────────────────────────────────────────────────────
export function TextBlock({ el, pageId, editing }: BlockProps<TextElement>) {
  const ref = useRef<HTMLTextAreaElement>(null)
  useEditSession(pageId, editing)
  useLayoutEffect(() => {
    if (editing) {
      autosize(ref.current)
      focusEnd(ref.current)
    }
  }, [editing])
  useLayoutEffect(() => autosize(ref.current), [el.text, el.w])

  const style = {
    fontSize: el.fontSize,
    color: resolveColor(el.color),
    fontFamily: el.font === 'mono' ? 'var(--font-mono)' : 'var(--font-sans)',
    fontWeight: el.weight === 'bold' ? 600 : 400,
  }
  if (editing)
    return (
      <textarea
        ref={ref}
        className="text-edit"
        style={style}
        value={el.text}
        placeholder="Type…  ($…$ for inline maths)"
        onChange={(e) => {
          updateElement(pageId, el.id, { text: e.target.value }, false)
          autosize(e.target)
        }}
        onBlur={() => {
          finishEditing()
          const cur = useLibrary.getState().pages[pageId]?.elements.find((x) => x.id === el.id) as TextElement | undefined
          if (cur && !cur.text.trim()) removeElements(pageId, [el.id])
        }}
        onKeyDown={(e) => {
          if (e.key === 'Escape') (e.target as HTMLTextAreaElement).blur()
          e.stopPropagation()
        }}
      />
    )
  return (
    <div className="text-view" style={style}>
      <RichText text={el.text || ' '} />
    </div>
  )
}

// ── Equation ─────────────────────────────────────────────────────────────────
export function EquationBlock({ el }: BlockProps<EquationElement>) {
  const tex = sourceToTex(el.source)
  return (
    <div className="eq-view" style={{ fontSize: el.fontSize, color: resolveColor(el.color) }}>
      {tex ? <Tex tex={tex} display /> : <span className="eq-empty">∑ Empty equation</span>}
    </div>
  )
}

// ── Calc / variables ─────────────────────────────────────────────────────────
export function CalcBlock({ el, pageId, editing }: BlockProps<CalcElement>) {
  const evaluation = usePageEval()
  const rows = evaluation.lines.get(el.id) ?? []
  const ref = useRef<HTMLTextAreaElement>(null)
  useEditSession(pageId, editing)
  useLayoutEffect(() => {
    if (editing) {
      autosize(ref.current)
      focusEnd(ref.current)
    }
  }, [editing])

  return (
    <div className="calc">
      <div className="calc-head">
        <Icon name="variable" size={14} />
        <span className="label">{el.title || 'Variables'}</span>
        <span className="calc-hint">{editing ? 'Esc to finish' : 'Double-tap to edit'}</span>
      </div>
      {editing && (
        <textarea
          ref={ref}
          className="calc-edit"
          spellCheck={false}
          autoCapitalize="off"
          autoCorrect="off"
          value={el.source}
          placeholder={'m = 5 kg\nv = 12 m/s\nKE = 1/2*m*v^2'}
          onChange={(e) => {
            updateElement(pageId, el.id, { source: e.target.value }, false)
            autosize(e.target)
          }}
          onBlur={finishEditing}
          onKeyDown={(e) => {
            if (e.key === 'Escape') (e.target as HTMLTextAreaElement).blur()
            e.stopPropagation()
          }}
        />
      )}
      <div className="calc-rows">
        {rows.map((r) => {
          if (r.kind === 'empty') return <div key={r.index} className="calc-gap" />
          if (r.kind === 'comment') return <div key={r.index} className="calc-comment">{r.raw.replace(/^\s*(#|\/\/)\s?/, '')}</div>
          if (r.kind === 'error' && !r.exprTex)
            return (
              <div key={r.index} className="calc-row err">
                <code>{r.raw}</code>
                <span className="calc-err">{r.error}</span>
              </div>
            )
          const lhs = r.kind === 'assign' ? `${r.nameTex} = ` : ''
          return (
            <div key={r.index} className={`calc-row ${r.error ? 'err' : ''}`}>
              <Tex tex={`${lhs}${r.exprTex}`} />
              {r.error ? (
                <span className="calc-err">{r.error}</span>
              ) : (
                !r.isInput &&
                r.valueTex && (
                  <span className="calc-result">
                    <Tex tex={`= ${r.valueTex}`} />
                  </span>
                )
              )}
            </div>
          )
        })}
        {!rows.some((r) => r.kind !== 'empty') && !editing && <div className="calc-comment">Empty — double-tap to define variables</div>}
      </div>
    </div>
  )
}

// ── Image ────────────────────────────────────────────────────────────────────
export function ImageBlock({ el }: BlockProps<ImageElement>) {
  const [src, setSrc] = useState<string | null>(el.src ?? null)
  useEffect(() => {
    let alive = true
    if (el.fileId) void fileUrl(el.fileId).then((u) => alive && setSrc(u))
    else setSrc(el.src ?? null)
    return () => {
      alive = false
    }
  }, [el.fileId, el.src])
  return src ? <img className="img-view" src={src} alt="" draggable={false} /> : <div className="img-missing">Image unavailable</div>
}

// ── Sticky / reference ───────────────────────────────────────────────────────
export function StickyBlock({ el, pageId, editing }: BlockProps<StickyElement>) {
  const ref = useRef<HTMLTextAreaElement>(null)
  useEditSession(pageId, editing)
  useLayoutEffect(() => {
    if (editing) {
      autosize(ref.current)
      focusEnd(ref.current)
    }
  }, [editing])
  const blur = (e: React.FocusEvent) => {
    // stay in edit mode while focus moves between the title and the body
    if (!(e.currentTarget.parentElement?.contains(e.relatedTarget as Node))) finishEditing()
  }
  return (
    <div className={`sticky sticky-${el.color}`}>
      {editing ? (
        <>
          <input
            className="sticky-title-edit"
            value={el.title}
            placeholder="REFERENCE"
            onChange={(e) => updateElement(pageId, el.id, { title: e.target.value }, false)}
            onBlur={blur}
            onKeyDown={(e) => e.stopPropagation()}
          />
          <textarea
            ref={ref}
            className="sticky-edit"
            value={el.text}
            onChange={(e) => {
              updateElement(pageId, el.id, { text: e.target.value }, false)
              autosize(e.target)
            }}
            onBlur={blur}
            onKeyDown={(e) => {
              if (e.key === 'Escape') (e.target as HTMLTextAreaElement).blur()
              e.stopPropagation()
            }}
          />
        </>
      ) : (
        <>
          <div className="sticky-title">{el.title || 'Reference'}</div>
          <div className="sticky-text">
            <RichText text={el.text} />
          </div>
        </>
      )}
    </div>
  )
}
