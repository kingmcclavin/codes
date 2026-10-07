// Document model: paper sizes, templates, ink, tools and their defaults.
// Page geometry is in PostScript points (1/72 in), like the iPad app.

import { hexToRgba, isLight, uuid } from './util.js';

export const PAPER_SIZES = [
  { id: 'letter', name: 'Letter', w: 612, h: 792, cat: 'Paper', sub: '8.5 × 11 in' },
  { id: 'legal', name: 'Legal', w: 612, h: 1008, cat: 'Paper', sub: '8.5 × 14 in' },
  { id: 'tabloid', name: 'Tabloid', w: 792, h: 1224, cat: 'Paper', sub: '11 × 17 in' },
  { id: 'a3', name: 'A3', w: 841.89, h: 1190.55, cat: 'Paper', sub: '297 × 420 mm' },
  { id: 'a4', name: 'A4', w: 595.28, h: 841.89, cat: 'Paper', sub: '210 × 297 mm' },
  { id: 'a5', name: 'A5', w: 419.53, h: 595.28, cat: 'Paper', sub: '148 × 210 mm' },
  { id: 'square', name: 'Square', w: 768, h: 768, cat: 'Other', sub: '768 × 768 pt' },
  { id: 'long-455x2500', name: 'Long Scroll', w: 455, h: 2500, cat: 'Other', sub: '455 × 2500 pt' },
  { id: 'whiteboard', name: 'Whiteboard', w: 2000, h: 2000, cat: 'Other', sub: '2000 × 2000 pt' },
  { id: 'ipad-13', name: 'iPad Pro 13″', w: 1024, h: 1366, cat: 'Screen', sub: '1024 × 1366 pt' },
  { id: 'ipad-11', name: 'iPad Pro 11″', w: 834, h: 1194, cat: 'Screen', sub: '834 × 1194 pt' },
  { id: 'ipad-air', name: 'iPad / iPad Air', w: 820, h: 1180, cat: 'Screen', sub: '820 × 1180 pt' },
  { id: '16x9', name: 'Widescreen 16:9', w: 720, h: 1280, cat: 'Screen', sub: '720 × 1280 pt' },
  { id: '4x3', name: 'Standard 4:3', w: 768, h: 1024, cat: 'Screen', sub: '768 × 1024 pt' },
];

export function paperSize(id) { return PAPER_SIZES.find((p) => p.id === id); }

export function sizeFor(paper, orientation) {
  const s = Math.min(paper.w, paper.h), l = Math.max(paper.w, paper.h);
  return orientation === 'landscape' ? { w: l, h: s } : { w: s, h: l };
}

export function matchPaper(size) {
  for (const p of PAPER_SIZES) {
    for (const o of ['portrait', 'landscape']) {
      const s = sizeFor(p, o);
      if (Math.abs(s.w - size.w) < 0.5 && Math.abs(s.h - size.h) < 0.5) return { paper: p, orientation: o };
    }
  }
  return null;
}

export function describeSize(size) {
  const m = matchPaper(size);
  if (m) return m.paper.w === m.paper.h ? m.paper.name : `${m.paper.name} ${m.orientation === 'portrait' ? 'Portrait' : 'Landscape'}`;
  return `Custom ${Math.round(size.w)} × ${Math.round(size.h)} pt`;
}

export const TEMPLATES = [
  { id: 'blank', name: 'Blank', spacing: 24 },
  { id: 'ruled', name: 'Ruled', spacing: 24 },
  { id: 'grid', name: 'Grid', spacing: 18 },
  { id: 'dotted', name: 'Dotted', spacing: 18 },
  { id: 'engineering', name: 'Engineering', spacing: 72 },
  { id: 'isometric', name: 'Isometric', spacing: 24 },
  { id: 'cornell', name: 'Cornell Notes', spacing: 24 },
  { id: 'lab', name: 'Lab Notebook', spacing: 18 },
];
export const templateInfo = (id) => TEMPLATES.find((t) => t.id === id) || TEMPLATES[0];

export const PAPER_COLORS = [
  { name: 'White', c: { r: 1, g: 1, b: 1, a: 1 } },
  { name: 'Ivory', c: { r: 0.984, g: 0.973, b: 0.941, a: 1 } },
  { name: 'Graphite', c: { r: 0.2, g: 0.2, b: 0.215, a: 1 } },
  { name: 'Black', c: { r: 0.09, g: 0.09, b: 0.1, a: 1 } },
];

export function makeBackground(template = 'blank', color = PAPER_COLORS[0].c, spacing) {
  return { color, template, spacing: spacing ?? templateInfo(template).spacing, section: null, autoExtends: false, image: null };
}

export function lineColor(bg) {
  const dark = !isLight(bg.color);
  if (bg.template === 'engineering') {
    return dark ? { r: 0.45, g: 0.75, b: 0.55, a: 0.35 } : { r: 0.36, g: 0.62, b: 0.45, a: 0.45 };
  }
  return dark ? { r: 1, g: 1, b: 1, a: 0.18 } : { r: 0.45, g: 0.58, b: 0.78, a: 0.45 };
}

export function marginColor(bg) {
  return !isLight(bg.color) ? { r: 1, g: 0.45, b: 0.45, a: 0.35 } : { r: 0.9, g: 0.35, b: 0.35, a: 0.5 };
}

// ---------- Ink ----------

export const INK_KINDS = {
  fineliner: { name: 'Fine Pen', quick: [0.6, 1.2, 2.0], range: [0.3, 24] },
  ballpoint: { name: 'Ballpoint', quick: [1.0, 1.8, 3.0], range: [0.3, 24] },
  fountain: { name: 'Fountain Pen', quick: [1.0, 1.8, 3.0], range: [0.3, 24] },
  marker: { name: 'Marker', quick: [3, 6, 10], range: [1, 36] },
  pencil: { name: 'Pencil', quick: [1.0, 2.0, 4.0], range: [0.3, 24] },
  highlighter: { name: 'Highlighter', quick: [10, 16, 26], range: [4, 48] },
};

export const INK_PALETTE = ['#111114', '#1F4FD8', '#D62828', '#1E8A4C', '#F08C00', '#7B3FE4', '#6B7280', '#FFFFFF'].map((x) => hexToRgba(x));
export const HIGHLIGHTER_PALETTE = ['#FFE14D', '#7CF08A', '#6EC6FF', '#FF8AD8', '#FFB347', '#C6A4FF'].map((x) => hexToRgba(x));

const ink = (kind, hex, width, extra = {}) => ({
  kind, color: hexToRgba(hex), width, opacity: 1, pressure: 0.5, tilt: 0, lineStyle: 'solid', ...extra,
});

export const PEN_PRESETS = [
  { id: 'fine', name: 'Fine Pen', style: ink('fineliner', '#111114', 1.0, { pressure: 0.15 }) },
  { id: 'ballpoint', name: 'Ballpoint', style: ink('ballpoint', '#111114', 1.8, { pressure: 0.55 }) },
  { id: 'fountain', name: 'Fountain', style: ink('fountain', '#1F4FD8', 2.2, { pressure: 0.95 }) },
  { id: 'marker', name: 'Marker', style: ink('marker', '#D62828', 5, { opacity: 0.95, pressure: 0.1 }) },
  { id: 'pencil', name: 'Pencil', style: ink('pencil', '#3A3A3F', 1.4, { opacity: 0.8, pressure: 0.6, tilt: 0.6 }) },
];
export const HIGHLIGHTER_PRESET = { id: 'highlighter', name: 'Highlighter', style: ink('highlighter', '#FFE14D', 16, { opacity: 0.4, pressure: 0 }) };

export function dashPattern(lineStyle, width) {
  if (lineStyle === 'dashed') return [Math.max(4, width * 3.5), Math.max(3, width * 2.5)];
  if (lineStyle === 'dotted') return [0.001, Math.max(2.5, width * 2.2)];
  return null;
}

/** Width multiplier for a normalized force (≈0.25 for normal writing gives 1×). */
const pressureFactor = (f) => Math.min(1.9, Math.max(0.3, 0.35 + 1.5 * Math.pow(Math.min(1, Math.max(0, f)), 0.6)));

export function widthAt(style, force, altitude) {
  let w = style.width;
  if (style.pressure > 0) w *= 1 + (pressureFactor(force) - 1) * style.pressure;
  if (style.tilt > 0) {
    const tilt = 1 - Math.min(1, Math.max(0, altitude / (Math.PI / 3)));
    w *= 1 + tilt * 2.5 * style.tilt;
  }
  return Math.max(0.15, w);
}

export const maxWidth = (style) => style.width * (1 + 0.9 * style.pressure) * (1 + 2.5 * style.tilt);

// ---------- Tools ----------

export const TOOLS = [
  { id: 'pen', name: 'Pen', key: '1' },
  { id: 'highlighter', name: 'Highlighter', key: '2' },
  { id: 'eraser', name: 'Eraser', key: '3' },
  { id: 'shapes', name: 'Shapes', key: '4' },
  { id: 'lasso', name: 'Lasso', key: '5' },
  { id: 'text', name: 'Text', key: '6' },
];

export const FONT_FAMILIES = [
  { id: 'System', css: 'system-ui, -apple-system, "Segoe UI", Roboto, sans-serif' },
  { id: 'Serif', css: '"Iowan Old Style", "New York", Georgia, "Times New Roman", serif' },
  { id: 'Helvetica', css: '"Helvetica Neue", Helvetica, Arial, sans-serif' },
  { id: 'Georgia', css: 'Georgia, serif' },
  { id: 'Times', css: '"Times New Roman", Times, serif' },
  { id: 'Mono', css: '"IBM Plex Mono", Menlo, Consolas, monospace' },
  { id: 'Courier', css: '"Courier New", Courier, monospace' },
  { id: 'Handwriting', css: '"Caveat", "Noteworthy", "Marker Felt", cursive' },
];
export const fontCss = (id) => (FONT_FAMILIES.find((f) => f.id === id) || FONT_FAMILIES[0]).css;

export function defaultSettings() {
  return {
    tool: 'pen',
    pen: structuredClone(PEN_PRESETS[1].style),
    highlighter: structuredClone(HIGHLIGHTER_PRESET.style),
    shape: { strokeColor: hexToRgba('#111114'), lineWidth: 2, opacity: 1, fill: null, lineStyle: 'solid' },
    eraser: { mode: 'object', size: 24, highlighterOnly: false },
    text: { fontFamily: 'System', fontSize: 18, color: hexToRgba('#111114'), bold: false, italic: false, align: 'left' },
    scribbleToErase: true,
    scribbleMode: 'strokes',
    holdToSnap: true,
    holdDuration: 0.5,
    fingerDrawing: false,
  };
}

export function makePage(size, background) {
  return { id: uuid(), w: size.w, h: size.h, background: structuredClone(background), elements: [] };
}

export function makeDocument({ title, size, background, folderId = null, color = null, icon = null }) {
  const now = Date.now();
  return {
    id: uuid(),
    title: title || 'Untitled',
    createdAt: now,
    modifiedAt: now,
    folderId,
    color,
    icon,
    pages: [makePage(size, background)],
    settings: defaultSettings(),
    view: { pageIndex: 0, zoom: 0, scrollX: 0, scrollY: 0 },
  };
}

/** Library colors and icons (emoji stand in for SF Symbols). */
export const LIBRARY_COLORS = ['#1F6FEB', '#5E5CE6', '#9B51E0', '#E84393', '#E5484D', '#F76B15', '#D4A017', '#30A46C', '#12A594', '#0891B2', '#8D6E63', '#5F6B7A'];
