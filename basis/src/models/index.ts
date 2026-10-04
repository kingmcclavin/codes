// Core data model for Basis. Everything here is plain, serialisable data so it
// can be persisted to IndexedDB today and synced / ported to a native store later.

export type ID = string

export type NotebookIcon =
  | 'atom'
  | 'integral'
  | 'gear'
  | 'circuit'
  | 'beam'
  | 'wave'
  | 'flask'
  | 'compass'
  | 'cube'
  | 'sigma'

export interface Notebook {
  id: ID
  name: string
  description: string
  icon: NotebookIcon
  color: string // accent swatch for the cover
  favorite: boolean
  createdAt: number
  updatedAt: number
  lastOpenedAt: number
}

export interface Section {
  id: ID
  notebookId: ID
  title: string
  order: number
  collapsed: boolean
}

export type TemplateKind =
  | 'blank'
  | 'engineering'
  | 'graph'
  | 'dot'
  | 'cornell'
  | 'isometric'
  | 'custom'

export interface TemplateOptions {
  spacing: number // world units between minor lines
  lineWidth: number // screen px
  visible: boolean
  pageColor: string | null // null = theme paper
  style: 'lines' | 'dots'
  majorEvery: number // 0 = no major lines
}

export interface Viewport {
  x: number // screen offset of world origin
  y: number
  zoom: number
}

export interface Page {
  id: ID
  notebookId: ID
  sectionId: ID
  title: string
  order: number
  template: TemplateKind
  templateOptions: TemplateOptions
  elements: CanvasElement[]
  viewport: Viewport
  createdAt: number
  updatedAt: number
  lastOpenedAt: number
}

// ───────────────────────── Canvas elements ─────────────────────────

/** Special colour token that renders as the theme's ink (near-black on paper, near-white on dark). */
export const INK = 'ink'

interface ElementBase {
  id: ID
  x: number
  y: number
  locked?: boolean
}

export interface StrokeElement extends ElementBase {
  type: 'stroke'
  tool: 'pen' | 'highlighter'
  /** Absolute world-space points: [x, y, pressure] */
  points: [number, number, number][]
  color: string
  width: number
  opacity: number
}

export type ShapeKind = 'rect' | 'ellipse' | 'triangle' | 'diamond' | 'line' | 'arrow'

export interface ShapeElement extends ElementBase {
  type: 'shape'
  shape: ShapeKind
  x2: number
  y2: number
  color: string
  width: number
  opacity: number
  fill: boolean
  dashed: boolean
}

export interface TextElement extends ElementBase {
  type: 'text'
  w: number
  text: string
  fontSize: number
  color: string
  font: 'sans' | 'mono'
  weight?: 'normal' | 'bold'
}

export interface EquationElement extends ElementBase {
  type: 'equation'
  source: string
  fontSize: number
  color: string
}

export interface CalcElement extends ElementBase {
  type: 'calc'
  w: number
  source: string
  title?: string
}

export interface TableElement extends ElementBase {
  type: 'table'
  title?: string
  columns: string[]
  rows: string[][]
}

export interface GraphFunction {
  id: ID
  expr: string
  color: string
}

export interface GraphSeries {
  id: ID
  label: string
  color: string
  points: [number, number][]
}

export interface GraphElement extends ElementBase {
  type: 'graph'
  w: number
  h: number
  functions: GraphFunction[]
  series?: GraphSeries[]
  view: { xmin: number; xmax: number; ymin: number; ymax: number }
  xLabel?: string
  yLabel?: string
}

export interface ImageElement extends ElementBase {
  type: 'image'
  w: number
  h: number
  fileId?: ID
  src?: string // inline (svg / data url) for demo content
  background?: boolean // imported PDF pages sit behind ink and are locked
}

export interface StickyElement extends ElementBase {
  type: 'sticky'
  w: number
  title: string
  text: string
  color: 'amber' | 'blue' | 'green' | 'rose' | 'graphite'
}

export type CanvasElement =
  | StrokeElement
  | ShapeElement
  | TextElement
  | EquationElement
  | CalcElement
  | TableElement
  | GraphElement
  | ImageElement
  | StickyElement

export type ElementType = CanvasElement['type']

/** Elements rendered as HTML blocks (vs. SVG vector ink). */
export const BLOCK_TYPES: ElementType[] = ['text', 'equation', 'calc', 'table', 'graph', 'image', 'sticky']

export const isBlock = (el: CanvasElement) => BLOCK_TYPES.includes(el.type)

// ───────────────────────── Files ─────────────────────────

export interface StoredFile {
  id: ID
  notebookId: ID | null
  name: string
  type: string
  size: number
  blob: Blob
  createdAt: number
}

export type StoredFileMeta = Omit<StoredFile, 'blob'>

// ───────────────────────── Settings ─────────────────────────

export type ThemePreference = 'system' | 'light' | 'dark'
export type TouchPolicy = 'auto' | 'draw' | 'navigate'

export interface Settings {
  theme: ThemePreference
  touchPolicy: TouchPolicy
  defaultTemplate: TemplateKind
  precision: number
  angleMode: 'deg' | 'rad'
}

export const DEFAULT_SETTINGS: Settings = {
  theme: 'dark',
  touchPolicy: 'auto',
  defaultTemplate: 'engineering',
  precision: 4,
  angleMode: 'deg',
}
