// Basis icon set — 24px grid, 1.5px strokes, square-ish terminals.
import type { CSSProperties } from 'react'

const P: Record<string, string> = {
  pen: 'M4 20l1.2-4.2L15.6 5.4a1.9 1.9 0 012.7 0l.3.3a1.9 1.9 0 010 2.7L8.2 18.8 4 20zM13.8 7.2l3 3',
  highlighter: 'M9 15l-3 3h4l1.5-1.5M9 15l6.8-9.6a1.6 1.6 0 012.3-.3l.8.6a1.6 1.6 0 01.3 2.3L12 15.6M9 15l3 .6M4 21h16',
  eraser: 'M8.5 20H20M4.6 14.6l8.8-8.8a2 2 0 012.8 0l2.9 2.9a2 2 0 010 2.8L11 19.6a1.4 1.4 0 01-1 .4H8a1.4 1.4 0 01-1-.4l-2.4-2.4a1.9 1.9 0 010-2.6zM9 10.2l5.4 5.4',
  select: 'M5 4l13 6.2-5.6 1.6L9.8 18 5 4z',
  hand: 'M8 13V6.5a1.5 1.5 0 013 0V12m0-6.5V4.5a1.5 1.5 0 013 0V12m0-6a1.5 1.5 0 013 0v6m0-3.5a1.5 1.5 0 013 0V15a6 6 0 01-6 6h-1.2a6 6 0 01-4.6-2.2L5 15.5a1.6 1.6 0 012.4-2.1L8 14',
  text: 'M5 6V4.5h14V6M12 4.5v15M9 19.5h6',
  shapes: 'M4 13.5h7V20.5H4zM16.5 3.5l4.5 7.5h-9l4.5-7.5zM17 14a3.25 3.25 0 110 6.5 3.25 3.25 0 010-6.5z',
  line: 'M5 19L19 5',
  arrow: 'M5 19L19 5M10 5h9v9',
  equation: 'M17 5H7l5 7-5 7h10',
  image: 'M4 5h16v14H4zM4 15l4.5-4.5 4 4L15 12l5 5M15 8.5a1 1 0 100 .01',
  plus: 'M12 5v14M5 12h14',
  minus: 'M5 12h14',
  close: 'M6 6l12 12M18 6L6 18',
  check: 'M5 12.5l4.5 4.5L19 7.5',
  chevronDown: 'M6 9.5l6 6 6-6',
  chevronRight: 'M9.5 6l6 6-6 6',
  chevronLeft: 'M14.5 6l-6 6 6 6',
  search: 'M10.5 17a6.5 6.5 0 100-13 6.5 6.5 0 000 13zM15.5 15.5L20 20',
  settings: 'M12 15a3 3 0 100-6 3 3 0 000 6zM19.4 13.5l1.6 1.2-2 3.4-1.9-.7a7 7 0 01-1.9 1.1L15 20.5h-4l-.3-2a7 7 0 01-1.9-1.1l-1.9.7-2-3.4 1.6-1.2a7 7 0 010-2.2L3 10.1l2-3.4 1.9.7a7 7 0 011.9-1.1l.3-2.1h4l.3 2.1a7 7 0 011.9 1.1l1.9-.7 2 3.4-1.6 1.2a7 7 0 010 2.2z',
  star: 'M12 4l2.4 5 5.4.7-4 3.7 1 5.4L12 16.2 7.2 18.8l1-5.4-4-3.7 5.4-.7L12 4z',
  more: 'M6 12h.01M12 12h.01M18 12h.01',
  moreV: 'M12 6h.01M12 12h.01M12 18h.01',
  trash: 'M5 7h14M10 4h4M7 7l.8 12.2a1 1 0 001 .8h6.4a1 1 0 001-.8L17 7M10 11v5M14 11v5',
  copy: 'M9 9h10v10H9zM15 9V5H5v10h4',
  edit: 'M4 20h4L19 9l-4-4L4 16v4zM13.5 6.5l4 4',
  undo: 'M9 14L4 9l5-5M4 9h10a6 6 0 010 12h-3',
  redo: 'M15 14l5-5-5-5M20 9H10a6 6 0 000 12h3',
  calculator: 'M6 3h12v18H6zM9 6.5h6M9 11h.01M12 11h.01M15 11h.01M9 14.5h.01M12 14.5h.01M15 14.5h.01M9 18h.01M12 18h.01M15 18h.01',
  tools: 'M14.5 6.5a4 4 0 00-5.2 5.2L4 17l3 3 5.3-5.3a4 4 0 005.2-5.2l-2.3 2.3-2.4-.6-.6-2.4 2.3-2.3z',
  variable: 'M5 8c1.5 0 2 1 3 4s1.5 4 3 4M11 8c-2 0-4 8-6 8M15 10h5M15 14h5',
  files: 'M3.5 6.5a1 1 0 011-1h4.6l1.8 2h8.6a1 1 0 011 1v9a1 1 0 01-1 1h-15a1 1 0 01-1-1v-11z',
  sidebar: 'M4 5h16v14H4zM9.5 5v14',
  grid: 'M4 4h16v16H4zM4 9.33h16M4 14.66h16M9.33 4v16M14.66 4v16',
  sun: 'M12 16a4 4 0 100-8 4 4 0 000 8zM12 2.5v2M12 19.5v2M4.5 12h-2M21.5 12h-2M6.7 6.7L5.3 5.3M18.7 18.7l-1.4-1.4M6.7 17.3l-1.4 1.4M18.7 5.3l-1.4 1.4',
  moon: 'M19.5 14.5A8 8 0 019.5 4.5a7.5 7.5 0 1010 10z',
  download: 'M12 4v11M7.5 10.5L12 15l4.5-4.5M5 19.5h14',
  upload: 'M12 15V4M7.5 8.5L12 4l4.5 4.5M5 19.5h14',
  file: 'M6 3.5h8l4 4v13H6zM14 3.5v4h4',
  pdf: 'M6 3.5h8l4 4v13H6zM14 3.5v4h4M8.5 16.5v-4h1.2a1.2 1.2 0 010 2.4H8.5M12.5 12.5v4h.8a1.6 1.6 0 001.6-1.6v-.8a1.6 1.6 0 00-1.6-1.6h-.8z',
  table: 'M4 5h16v14H4zM4 9.5h16M4 14.25h16M10 5v14',
  graph: 'M4 4v16h16M7 16c2-6 4-9 6-9s3 3 4 3 2-2 3-4',
  sticky: 'M5 4h14v10l-6 6H5zM13 20v-6h6',
  calcBlock: 'M4 5h16v14H4zM7 9h3M7 12h5M7 15h3M14 9h3M14 15h3',
  library: 'M4 4h4v16H4zM10 4h4v16h-4zM16.5 4.5l3.8 1-3.7 14.3-3.8-1',
  drag: 'M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01',
  zoomIn: 'M10.5 17a6.5 6.5 0 100-13 6.5 6.5 0 000 13zM15.5 15.5L20 20M10.5 8v5M8 10.5h5',
  zoomOut: 'M10.5 17a6.5 6.5 0 100-13 6.5 6.5 0 000 13zM15.5 15.5L20 20M8 10.5h5',
  fit: 'M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5',
  keyboard: 'M3 6h18v12H3zM7 10h.01M10.5 10h.01M14 10h.01M17.5 10h.01M8 14h8',
  export: 'M12 3.5v11M8 7.5l4-4 4 4M5 13v6.5h14V13',
  page: 'M6 3.5h12v17H6zM9 8h6M9 11.5h6M9 15h4',
  section: 'M4 6h16M4 12h16M4 18h10',
  rect: 'M4.5 6.5h15v11h-15z',
  ellipse: 'M12 6c4.4 0 8 2.7 8 6s-3.6 6-8 6-8-2.7-8-6 3.6-6 8-6z',
  triangle: 'M12 5l8 14H4l8-14z',
  diamond: 'M12 3.5l8.5 8.5-8.5 8.5L3.5 12 12 3.5z',
  dash: 'M4 12h3M10.5 12h3M17 12h3',
  fill: 'M4.5 6.5h15v11h-15z',
  info: 'M12 21a9 9 0 100-18 9 9 0 000 18zM12 11v5M12 8h.01',
  swap: 'M7 4L4 7l3 3M4 7h13M17 20l3-3-3-3M20 17H7',
  attach: 'M8.5 12.5l6-6a3 3 0 014.2 4.2l-8 8a4.5 4.5 0 01-6.4-6.4l7.3-7.3',
  open: 'M14 4h6v6M20 4l-9 9M18 14v6H4V6h6',
  insert: 'M12 4v16M4 12h16',
  print: 'M7 9V4h10v5M7 17H5a1 1 0 01-1-1v-6a1 1 0 011-1h14a1 1 0 011 1v6a1 1 0 01-1 1h-2M7 14h10v6H7z',
  // Notebook glyphs
  atom: 'M12 13.2a1.2 1.2 0 100-2.4 1.2 1.2 0 000 2.4zM12 20.5c1.9 0 3.4-3.8 3.4-8.5S13.9 3.5 12 3.5 8.6 7.3 8.6 12s1.5 8.5 3.4 8.5zM4.6 16.3c1 1.6 5 1 9.1-1.4s6.6-5.6 5.7-7.2-5-1-9.1 1.4-6.6 5.6-5.7 7.2zM19.4 16.3c-1 1.6-5 1-9.1-1.4S3.7 9.3 4.6 7.7s5-1 9.1 1.4 6.6 5.6 5.7 7.2z',
  integral: 'M15.5 4.5c-.5-1-1.5-1.2-2.2-.6-.8.7-1 2.3-1.3 6.1s-.5 7.8-1.3 9.3c-.6 1-1.7 1.1-2.2.2',
  gear: 'M12 15.5a3.5 3.5 0 100-7 3.5 3.5 0 000 7zM12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1',
  circuit: 'M2.5 12h4l1.5-4 3 8 3-8 1.5 4h6',
  beam: 'M3 9h18v3H3zM6 12l-2 6h4l-2-6zM18 12l-2 6h4l-2-6zM3 21h18',
  wave: 'M3 12c1.5-4 3-6 4.5-6S10.5 18 12 18s3-12 4.5-12 3 2 4.5 6',
  flask: 'M9.5 3.5h5M10.5 3.5v6l-5.3 8.7a1.5 1.5 0 001.3 2.3h11a1.5 1.5 0 001.3-2.3l-5.3-8.7v-6M7.5 15h9',
  compass: 'M12 6a1.5 1.5 0 100-3 1.5 1.5 0 000 3zM11.2 5.8L5.5 20.5M12.8 5.8l5.7 14.7M7.6 15h8.8',
  cube: 'M12 3l8 4.5v9L12 21l-8-4.5v-9L12 3zM12 12l8-4.5M12 12L4 7.5M12 12v9',
  sigma: 'M17 5H7l5 7-5 7h10',
}

export type IconName = keyof typeof P

export function Icon({ name, size = 18, style, className, stroke = 1.5 }: { name: IconName | string; size?: number; style?: CSSProperties; className?: string; stroke?: number }) {
  const d = P[name] ?? P.info
  const filled = name === 'select'
  return (
    <svg
      className={className}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill={filled ? 'currentColor' : 'none'}
      fillOpacity={filled ? 0.08 : undefined}
      stroke="currentColor"
      strokeWidth={stroke}
      strokeLinecap="round"
      strokeLinejoin="round"
      style={style}
      aria-hidden="true"
    >
      <path d={d} />
    </svg>
  )
}

export const NOTEBOOK_ICONS = ['atom', 'integral', 'gear', 'circuit', 'beam', 'wave', 'flask', 'compass', 'cube', 'sigma'] as const
