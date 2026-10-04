import type { TemplateKind, TemplateOptions } from '.'

export interface TemplateInfo {
  kind: TemplateKind
  name: string
  description: string
  defaults: TemplateOptions
}

const base: TemplateOptions = {
  spacing: 20,
  lineWidth: 1,
  visible: true,
  pageColor: null,
  style: 'lines',
  majorEvery: 5,
}

export const TEMPLATES: TemplateInfo[] = [
  { kind: 'blank', name: 'Blank', description: 'Plain paper', defaults: { ...base, visible: false, majorEvery: 0 } },
  { kind: 'engineering', name: 'Engineering', description: 'Fine square grid, major every 5', defaults: { ...base, spacing: 16, majorEvery: 5 } },
  { kind: 'graph', name: 'Graph Paper', description: 'Millimetre grid with axes', defaults: { ...base, spacing: 10, majorEvery: 10 } },
  { kind: 'dot', name: 'Dot Grid', description: 'Subtle dots', defaults: { ...base, spacing: 24, style: 'dots', majorEvery: 0 } },
  { kind: 'cornell', name: 'Cornell', description: 'Cue column, notes, summary', defaults: { ...base, spacing: 32, majorEvery: 0 } },
  { kind: 'isometric', name: 'Isometric', description: '30° isometric lattice', defaults: { ...base, spacing: 24, majorEvery: 0 } },
  { kind: 'custom', name: 'Custom', description: 'Your own spacing & colour', defaults: { ...base, spacing: 25, majorEvery: 4 } },
]

export const templateInfo = (kind: TemplateKind) => TEMPLATES.find((t) => t.kind === kind) ?? TEMPLATES[0]

/** Cornell layout constants (world units). */
export const CORNELL = { cueWidth: 240, headerHeight: 120, pageHeight: 1600, summaryHeight: 260, pageWidth: 1200 }
