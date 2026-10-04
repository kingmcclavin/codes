import type { CalcElement, EquationElement, GraphElement, ImageElement, StickyElement, TableElement, TextElement } from '../../models'
import { INK } from '../../models'
import { uid } from '../id'

type P = { x: number; y: number }

export const make = {
  text: (p: P, o: Partial<TextElement> = {}): TextElement => ({ id: uid('e'), type: 'text', x: p.x, y: p.y, w: 380, text: '', fontSize: 18, color: INK, font: 'sans', ...o }),
  equation: (p: P, source = '', o: Partial<EquationElement> = {}): EquationElement => ({ id: uid('e'), type: 'equation', x: p.x, y: p.y, source, fontSize: 20, color: INK, ...o }),
  calc: (p: P, source = 'm = 5 kg\nv = 12 m/s\nKE = 1/2*m*v^2', o: Partial<CalcElement> = {}): CalcElement => ({ id: uid('e'), type: 'calc', x: p.x, y: p.y, w: 340, source, ...o }),
  table: (p: P, o: Partial<TableElement> = {}): TableElement => ({
    id: uid('e'),
    type: 'table',
    x: p.x,
    y: p.y,
    columns: ['t (s)', 'x (m)', 'v (m/s)'],
    rows: [
      ['0', '0', '0'],
      ['1', '4.2', '=B2-B1'],
      ['2', '8.7', '=B3-B2'],
      ['', '', ''],
    ],
    ...o,
  }),
  graph: (p: P, o: Partial<GraphElement> = {}): GraphElement => ({
    id: uid('e'),
    type: 'graph',
    x: p.x,
    y: p.y,
    w: 460,
    h: 320,
    functions: [{ id: uid('fn'), expr: 'y = x^2', color: '#ff6b2c' }],
    view: { xmin: -5, xmax: 5, ymin: -2, ymax: 10 },
    ...o,
  }),
  sticky: (p: P, o: Partial<StickyElement> = {}): StickyElement => ({ id: uid('e'), type: 'sticky', x: p.x, y: p.y, w: 240, title: 'Reference', text: '', color: 'amber', ...o }),
  image: (p: P, w: number, h: number, o: Partial<ImageElement> = {}): ImageElement => ({ id: uid('e'), type: 'image', x: p.x, y: p.y, w, h, ...o }),
}

/** Centre a new block of roughly (w, h) on point p. */
export const centered = (p: P, w: number, h: number): P => ({ x: Math.round(p.x - w / 2), y: Math.round(p.y - h / 2) })
