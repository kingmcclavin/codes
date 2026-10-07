// Outline icons for folders and notebooks (24×24, stroked, one colour).
// Stored by name on folders and notebooks; older emoji choices map to names.

const P = {
  // School & writing
  notebook: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 3v18M12 8h4M12 11.5h4"/>',
  book: '<path d="M4 5.5A1.5 1.5 0 015.5 4H11v16H5.5A1.5 1.5 0 014 18.5z"/><path d="M20 5.5A1.5 1.5 0 0018.5 4H13v16h5.5a1.5 1.5 0 001.5-1.5z"/>',
  books: '<rect x="3.5" y="4" width="4" height="16" rx="1"/><rect x="8.5" y="6" width="4" height="14" rx="1"/><path d="M14 7.2l3.7-1 3 13.6-3.7 1z"/>',
  bookOpen: '<path d="M12 6.5C10 5 7.5 4.5 3.5 4.8v13.4c4-.3 6.5.2 8.5 1.8 2-1.6 4.5-2.1 8.5-1.8V4.8C16.5 4.5 14 5 12 6.5z"/><path d="M12 6.5V20"/>',
  pencil: '<path d="M4 20l1.2-4.6L16.5 4.1a2.1 2.1 0 013 3L8.2 18.4z"/><path d="M14.5 6.1l3.4 3.4"/>',
  pen: '<path d="M12 3l4 7-4 11-4-11z"/><path d="M8 10h8"/><circle cx="12" cy="12.5" r="1"/>',
  document: '<path d="M13.5 3.5H7A1.5 1.5 0 005.5 5v14A1.5 1.5 0 007 20.5h10a1.5 1.5 0 001.5-1.5V8.5z"/><path d="M13.5 3.5v5h5M9 13h6M9 16.5h6"/>',
  clipboard: '<rect x="5" y="4.5" width="14" height="16.5" rx="2"/><rect x="9" y="3" width="6" height="3.5" rx="1"/><path d="M8.5 11h7M8.5 14.5h7M8.5 18h4"/>',
  checklist: '<path d="M4 6.5l1.5 1.5L8 5.5M4 12.5l1.5 1.5L8 11.5M4 18.5l1.5 1.5L8 17.5M11 7h9M11 13h9M11 19h9"/>',
  graduation: '<path d="M2.5 9.5L12 5l9.5 4.5L12 14z"/><path d="M6.5 11.5v4.5c3.5 2.5 7.5 2.5 11 0v-4.5M21.5 9.5v5"/>',
  backpack: '<path d="M6 10a6 6 0 0112 0v9.5a1.5 1.5 0 01-1.5 1.5h-9A1.5 1.5 0 016 19.5z"/><path d="M9.5 4.5V3.5h5v1M9 21v-5h6v5M6 13h12"/>',
  bookmark: '<path d="M6.5 3.5h11v17L12 16.5l-5.5 4z"/>',
  tag: '<path d="M3.5 12.2V4.5a1 1 0 011-1h7.7l8.3 8.3a1.5 1.5 0 010 2.1l-6.2 6.2a1.5 1.5 0 01-2.1 0z"/><circle cx="8" cy="8" r="1.5"/>',
  paperclip: '<path d="M20 11.5l-8.2 8.2a5 5 0 01-7-7L13 4.5a3.3 3.3 0 014.7 4.7l-8.2 8.2a1.7 1.7 0 01-2.4-2.4l7.6-7.6"/>',

  // Math
  ruler: '<rect x="2.5" y="8" width="19" height="8" rx="1"/><path d="M6 8v3M9.5 8v4.5M13 8v3M16.5 8v4.5"/>',
  triangleRuler: '<path d="M4 4v16h16z"/><path d="M8 12v4h4z"/><path d="M4 8h2M4 12h2"/>',
  compass: '<circle cx="12" cy="4.5" r="1.5"/><path d="M11.2 6L6 20M12.8 6L18 20M7.8 15h8.4"/>',
  sigma: '<path d="M18 5H6l6.5 7L6 19h12"/>',
  sqrt: '<path d="M3 13h3l3.5 7L14 4h7"/>',
  pi: '<path d="M4 7.5c1-1.3 2-2 4-2h12M9.5 5.5c0 6-.5 10.5-3 13.5M15.5 5.5c-.5 5 0 10 1 12 .6 1 2 1.3 3 .5"/>',
  infinity: '<path d="M12 12c-2-2.7-3.7-4-5.5-4a4 4 0 000 8c1.8 0 3.5-1.3 5.5-4zm0 0c2 2.7 3.7 4 5.5 4a4 4 0 000-8c-1.8 0-3.5 1.3-5.5 4z"/>',
  percent: '<path d="M19 5L5 19"/><circle cx="7" cy="7" r="2.5"/><circle cx="17" cy="17" r="2.5"/>',
  calculator: '<rect x="4.5" y="3" width="15" height="18" rx="2.5"/><rect x="7.5" y="6" width="9" height="3.5" rx=".5"/><path d="M8 13h.01M12 13h.01M16 13h.01M8 17h.01M12 17h.01M16 17h.01" stroke-width="2.4"/>',
  function: '<path d="M15.5 4.5c-2.5 0-3 1.5-3.4 3.5L10 17c-.4 1.8-1 3-3 3"/><path d="M8 9.5h7"/><path d="M14.5 13.5l4.5 5M19 13.5l-4.5 5"/>',
  chart: '<path d="M4 4v16h16"/><path d="M7.5 15l3.5-4 3 2.5L19.5 7"/>',
  barChart: '<path d="M4 20h16"/><rect x="5.5" y="12" width="3" height="8"/><rect x="10.5" y="7" width="3" height="13"/><rect x="15.5" y="4" width="3" height="16"/>',
  pieChart: '<path d="M12 3.5a8.5 8.5 0 108.5 8.5H12z"/><path d="M15 3.8a8.5 8.5 0 015.2 5.2H15z"/>',
  grid: '<rect x="4" y="4" width="16" height="16" rx="1.5"/><path d="M4 9.3h16M4 14.7h16M9.3 4v16M14.7 4v16"/>',
  shapes: '<rect x="3.5" y="11.5" width="8" height="8" rx="1"/><circle cx="16.5" cy="16" r="4"/><path d="M12 3l4 6.5H8z"/>',
  cube: '<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z"/><path d="M4 7.5l8 4.5 8-4.5M12 12v9"/>',

  // Science
  atom: '<circle cx="12" cy="12" r="1.3"/><ellipse cx="12" cy="12" rx="9" ry="3.6"/><ellipse cx="12" cy="12" rx="9" ry="3.6" transform="rotate(60 12 12)"/><ellipse cx="12" cy="12" rx="9" ry="3.6" transform="rotate(120 12 12)"/>',
  flask: '<path d="M9.5 3.5h5M10 3.5v6L4.8 18.3A1.5 1.5 0 006.1 20.5h11.8a1.5 1.5 0 001.3-2.2L14 9.5v-6"/><path d="M7.3 14.5h9.4"/>',
  testTube: '<g transform="rotate(30 12 12)"><path d="M9 3h6M10 3v14.5a2 2 0 004 0V3M10 11.5h4"/></g>',
  microscope: '<path d="M4.5 21h15M8 18h7.5"/><path d="M14 17.5a5 5 0 001.5-8.5"/><g transform="rotate(-25 11 8)"><rect x="9" y="2.5" width="4" height="9.5" rx="1"/><path d="M11 12v2.5M8.5 2.5h5"/></g>',
  magnet: '<path d="M5 4h4v8a3 3 0 006 0V4h4v8a7 7 0 01-14 0z"/><path d="M5 8h4M15 8h4"/>',
  dna: '<path d="M7 3c0 6 10 6 10 12v6M17 3c0 6-10 6-10 12v6"/><path d="M8.5 6.5h7M8.5 17.5h7M10 12h4"/>',
  leaf: '<path d="M5 19c0-8 5-14 15-14 0 10-6 15-14 15"/><path d="M5 19c3-5 6-8 10-10"/>',
  tree: '<path d="M12 3l6 8h-3l4.5 6h-15L9 11H6z"/><path d="M12 17v4"/>',
  globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.5 2.5 3.5 5.3 3.5 8.5s-1 6-3.5 8.5c-2.5-2.5-3.5-5.3-3.5-8.5s1-6 3.5-8.5z"/>',
  planet: '<circle cx="12" cy="12" r="5.5"/><path d="M6.6 10.2C3.4 11.6 2 13.2 2.6 14.4c.9 1.9 6.4 1 12.1-1.9s9.6-6.7 8.7-8.6c-.5-1.1-2.7-1.2-5.6-.3"/>',
  rocket: '<path d="M12 3c3 2.5 4.5 6 4.5 10l-2 3h-5l-2-3c0-4 1.5-7.5 4.5-10z"/><circle cx="12" cy="10" r="1.6"/><path d="M7.5 13l-2.5 3v3l4.5-3M16.5 13l2.5 3v3l-4.5-3M10.5 19.5L12 21l1.5-1.5"/>',
  brain: '<path d="M12 5.5a3 3 0 00-5.5-1.3A3 3 0 004 8.5a3 3 0 00-.5 5 3.2 3.2 0 003 4.5A3 3 0 0012 19z"/><path d="M12 5.5a3 3 0 015.5-1.3A3 3 0 0120 8.5a3 3 0 01.5 5 3.2 3.2 0 01-3 4.5A3 3 0 0112 19z"/><path d="M12 5.5V19"/>',
  heart: '<path d="M12 20s-7.5-4.5-8.8-9.6A4.5 4.5 0 0112 7a4.5 4.5 0 018.8 3.4C19.5 15.5 12 20 12 20z"/>',
  pulse: '<path d="M3 12h4l2.5-6 4 12 2.5-6h5"/>',
  pill: '<rect x="2.6" y="8.5" width="18.8" height="7" rx="3.5" transform="rotate(-45 12 12)"/><path d="M9.5 9.5l5 5"/>',

  // Engineering & tech
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.6 1.6 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.6 1.6 0 00-1.8-.3 1.6 1.6 0 00-1 1.5V21a2 2 0 11-4 0v-.1a1.6 1.6 0 00-1-1.5 1.6 1.6 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.6 1.6 0 00.3-1.8 1.6 1.6 0 00-1.5-1H3a2 2 0 110-4h.1a1.6 1.6 0 001.5-1 1.6 1.6 0 00-.3-1.8l-.1-.1a2 2 0 112.8-2.8l.1.1a1.6 1.6 0 001.8.3H9a1.6 1.6 0 001-1.5V3a2 2 0 114 0v.1a1.6 1.6 0 001 1.5 1.6 1.6 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.6 1.6 0 00-.3 1.8V9a1.6 1.6 0 001.5 1H21a2 2 0 110 4h-.1a1.6 1.6 0 00-1.5 1z"/>',
  wrench: '<path d="M14.5 6.5a4 4 0 015-3.5l-2.5 2.5.5 2.5 2.5.5L22.5 6a4 4 0 01-5.5 4.5L8 19.5a2.1 2.1 0 01-3-3l9-9a4 4 0 01.5-1z"/>',
  hammer: '<path d="M13.5 8.5L4.3 17.7a1.6 1.6 0 002.3 2.3l9.2-9.2"/><path d="M11.5 6.5l3-3c1.5-.5 3 0 4 1l2 2-1.5 1.5-1-1-1.5 1.5 1 1-2 2-4-4z"/>',
  bolt: '<path d="M13 3L5 13.5h6L10 21l8-10.5h-6z"/>',
  lightbulb: '<path d="M9 18h6M10 21h4M8.5 14.5a6 6 0 117 0c-.6.5-1 1.2-1 2v1.5h-5V16.5c0-.8-.4-1.5-1-2z"/>',
  battery: '<rect x="2.5" y="7.5" width="17" height="9" rx="2"/><path d="M21.5 10.5v3M6 10.5v3M9.5 10.5v3"/>',
  chip: '<rect x="6" y="6" width="12" height="12" rx="1.5"/><rect x="9.5" y="9.5" width="5" height="5"/><path d="M9.5 3v3M14.5 3v3M9.5 18v3M14.5 18v3M3 9.5h3M3 14.5h3M18 9.5h3M18 14.5h3"/>',
  laptop: '<rect x="5" y="5" width="14" height="10" rx="1.5"/><path d="M2.5 18.5h19l-1.5-3.5H4z"/>',
  code: '<path d="M8.5 7L3.5 12l5 5M15.5 7l5 5-5 5M13.5 4.5l-3 15"/>',
  terminal: '<rect x="3" y="4.5" width="18" height="15" rx="2"/><path d="M7 9.5l3 2.5-3 2.5M12.5 15h4.5"/>',
  wifi: '<path d="M2.5 9a14 14 0 0119 0M5.5 12.5a9.5 9.5 0 0113 0M8.5 16a5 5 0 017 0"/><circle cx="12" cy="19" r=".8" fill="currentColor"/>',
  bridge: '<path d="M2.5 16h19M6 20V5M18 20V5M6 6.5c2.5 5.5 9.5 5.5 12 0M2.5 11.5C4.5 11 6 9 6 6.5M21.5 11.5C19.5 11 18 9 18 6.5M10 10.6V16M14 10.6V16"/>',
  building: '<path d="M4.5 21V5.5a1 1 0 011-1h8a1 1 0 011 1V21M14.5 10h4a1 1 0 011 1v10M3 21h18"/><path d="M8 8h3M8 11.5h3M8 15h3"/>',
  columns: '<path d="M3 20.5h18M4 8h16M12 3l8.5 5h-17zM6.5 8v10M10 8v10M14 8v10M17.5 8v10M4.5 18h15"/>',

  // Work, money, people
  briefcase: '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5a1 1 0 011-1h4a1 1 0 011 1v2M3 12.5h18"/>',
  dollar: '<path d="M12 3v18M16.5 7.5c-.5-1.8-2.3-2.8-4.5-2.8-2.5 0-4.3 1.3-4.3 3.3 0 4.5 9 2.5 9 7 0 2-1.9 3.3-4.7 3.3-2.3 0-4.2-1-4.8-3"/>',
  coins: '<ellipse cx="9" cy="7" rx="5.5" ry="2.5"/><path d="M3.5 7v4c0 1.4 2.5 2.5 5.5 2.5M3.5 11v4c0 1.4 2.5 2.5 5.5 2.5"/><ellipse cx="15" cy="13" rx="5.5" ry="2.5"/><path d="M9.5 13v4c0 1.4 2.5 2.5 5.5 2.5s5.5-1.1 5.5-2.5v-4"/>',
  cart: '<path d="M3 4h2.5l2.2 11h10.6l2-8H6.5"/><circle cx="9" cy="19" r="1.4"/><circle cx="17" cy="19" r="1.4"/>',
  person: '<circle cx="12" cy="8" r="4"/><path d="M4.5 20.5a7.5 7.5 0 0115 0"/>',
  people: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0113 0"/><path d="M15.5 4.7a3.5 3.5 0 010 6.6M18 14.2a6.5 6.5 0 013.5 5.8"/>',
  chat: '<path d="M4 5.5A1.5 1.5 0 015.5 4h13A1.5 1.5 0 0120 5.5v9a1.5 1.5 0 01-1.5 1.5H10l-4.5 4v-4h0A1.5 1.5 0 014 14.5z"/>',
  envelope: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3.5 6l8.5 7 8.5-7"/>',
  calendar: '<rect x="3.5" y="5" width="17" height="15.5" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5l3.5 2"/>',
  target: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.5"/>',
  trophy: '<path d="M7.5 4h9v5a4.5 4.5 0 01-9 0z"/><path d="M7.5 6H4.5a3 3 0 003 4M16.5 6h3a3 3 0 01-3 4M12 13.5V17M8.5 20.5h7M9.5 17h5v3.5h-5z"/>',

  // Life & hobbies
  home: '<path d="M3.5 11L12 4l8.5 7"/><path d="M5.5 9.5V20h13V9.5M10 20v-5.5h4V20"/>',
  music: '<path d="M9 18V5.5l11-2V16"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="17.5" cy="16" r="2.5"/>',
  palette: '<path d="M12 3.5a8.5 8.5 0 000 17c1.3 0 2-.8 2-1.8 0-1.3-1.2-1.6-1.2-2.8 0-1 .8-1.6 1.8-1.6h2.4a3.5 3.5 0 003.5-3.5c0-4.1-3.8-7.3-8.5-7.3z"/><circle cx="7.5" cy="11" r="1.1"/><circle cx="10" cy="7.3" r="1.1"/><circle cx="14.5" cy="7.3" r="1.1"/>',
  brush: '<path d="M20 4L11 14.5"/><path d="M9.5 13.5a3 3 0 013 3c0 2.5-3 4-7.5 4 1-1.5.5-3 1.5-5a3 3 0 013-2z"/>',
  camera: '<path d="M3.5 8.5A1.5 1.5 0 015 7h2.5L9 5h6l1.5 2H19a1.5 1.5 0 011.5 1.5v9.5A1.5 1.5 0 0119 19.5H5A1.5 1.5 0 013.5 18z"/><circle cx="12" cy="13" r="3.5"/>',
  film: '<rect x="3.5" y="4" width="17" height="16" rx="1.5"/><path d="M7.5 4v16M16.5 4v16M3.5 8h4M3.5 12h4M3.5 16h4M16.5 8h4M16.5 12h4M16.5 16h4"/>',
  gamepad: '<path d="M7 7h10a4.5 4.5 0 014.4 5.5l-1 4.5a2.3 2.3 0 01-4 1L14.5 16h-5L7.6 18a2.3 2.3 0 01-4-1l-1-4.5A4.5 4.5 0 017 7z"/><path d="M8 10v4M6 12h4M15.5 11h.01M17.5 13h.01" stroke-width="1.9"/>',
  ball: '<circle cx="12" cy="12" r="8.5"/><path d="M5.5 6.5c3 2 4 5 4 9M18.5 6.5c-3 2-4 5-4 9M3.5 12c3 0 5.5 1 8.5 1s5.5-1 8.5-1"/>',
  dumbbell: '<path d="M6.5 7v10M17.5 7v10M3.5 9.5v5M20.5 9.5v5M6.5 12h11"/>',
  coffee: '<path d="M4.5 9h12v5.5A4.5 4.5 0 0112 19h-3a4.5 4.5 0 01-4.5-4.5z"/><path d="M16.5 10.5h1.5a2.5 2.5 0 010 5h-1.8M8 3.5c-.7 1 .7 2 0 3M12 3.5c-.7 1 .7 2 0 3"/>',
  utensils: '<path d="M6 3v6a2 2 0 004 0V3M8 3v18M17 21V3c-2 1-3.5 3.5-3.5 7v3h3.5"/>',
  plane: '<path d="M10.5 13.5L3 11l1-1.5 7.5.5L16 4.5c1-1 2.6-1.3 3.3-.6s.4 2.3-.6 3.3L13.2 11.7l.6 7.5L12.3 20l-2.5-7.4z"/><path d="M7 15.5l-2.5.5 3.5 3.5.5-2.5"/>',
  car: '<path d="M4 16.5V12l2-5a1.5 1.5 0 011.4-1h9.2a1.5 1.5 0 011.4 1l2 5v4.5"/><rect x="3" y="12" width="18" height="5" rx="1.5"/><path d="M5.5 17v2h2.5v-2M16 17v2h2.5v-2"/><circle cx="7" cy="14.5" r=".8"/><circle cx="17" cy="14.5" r=".8"/>',
  map: '<path d="M3.5 6.5l5.5-2.5 6 2.5 5.5-2.5v13.5L15 20l-6-2.5-5.5 2.5z"/><path d="M9 4v13.5M15 6.5V20"/>',
  pin: '<path d="M12 21s6.5-6 6.5-11a6.5 6.5 0 00-13 0c0 5 6.5 11 6.5 11z"/><circle cx="12" cy="10" r="2.3"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2.5M12 19v2.5M2.5 12H5M19 12h2.5M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M5.3 18.7l1.8-1.8M16.9 7.1l1.8-1.8"/>',
  moon: '<path d="M19.5 14.5A8 8 0 019.5 4.5a8 8 0 1010 10z"/>',
  cloud: '<path d="M7 18.5a4.5 4.5 0 01-.6-9A6 6 0 0118 9.5a4.5 4.5 0 01-.5 9z"/>',
  paw: '<circle cx="6" cy="10" r="1.8"/><circle cx="9.5" cy="6" r="1.8"/><circle cx="14.5" cy="6" r="1.8"/><circle cx="18" cy="10" r="1.8"/><path d="M12 11.5c-2.5 0-5.5 3.5-5.5 6 0 1.5 1 2.5 2.5 2.5 1.2 0 1.9-.6 3-.6s1.8.6 3 .6c1.5 0 2.5-1 2.5-2.5 0-2.5-3-6-5.5-6z"/>',

  // Marks
  star: '<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 16.9l-5.2 2.8 1-5.9-4.3-4.1 5.9-.8z"/>',
  flag: '<path d="M5 21V4M5 4.5h12l-2.5 4 2.5 4H5"/>',
  sparkle: '<path d="M12 3c.6 4.5 1.5 5.4 6 6-4.5.6-5.4 1.5-6 6-.6-4.5-1.5-5.4-6-6 4.5-.6 5.4-1.5 6-6z"/><path d="M18.5 15c.3 2 .7 2.4 2.5 2.7-1.8.3-2.2.7-2.5 2.6-.3-1.9-.7-2.3-2.5-2.6 1.8-.3 2.2-.7 2.5-2.7z"/>',
  lock: '<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 10.5V7.5a4 4 0 018 0v3"/>',
  key: '<circle cx="8" cy="15" r="4.5"/><path d="M11.2 11.8L20 3M17 6l2.5 2.5M14.5 8.5l2 2"/>',
  box: '<path d="M3.5 7.5L12 3.5l8.5 4v9L12 20.5l-8.5-4z"/><path d="M3.5 7.5l8.5 4 8.5-4M12 11.5v9M7.8 5.5l8.5 4"/>',
  archive: '<rect x="3" y="4" width="18" height="4.5" rx="1"/><path d="M4.5 8.5V19a1.5 1.5 0 001.5 1.5h12a1.5 1.5 0 001.5-1.5V8.5M10 12h4"/>',
  trash: '<path d="M4 6.5h16M9 6.5V4.5h6v2M6 6.5l1 13.5h10l1-13.5M10 10.5v6M14 10.5v6"/>',
};

export const LIBRARY_ICON_GROUPS = [
  ['School', ['notebook', 'book', 'books', 'bookOpen', 'pencil', 'pen', 'document', 'clipboard', 'checklist', 'graduation', 'backpack', 'bookmark', 'tag', 'paperclip']],
  ['Math', ['ruler', 'triangleRuler', 'compass', 'sigma', 'sqrt', 'pi', 'infinity', 'percent', 'calculator', 'function', 'chart', 'barChart', 'pieChart', 'grid', 'shapes', 'cube']],
  ['Science', ['atom', 'flask', 'testTube', 'microscope', 'magnet', 'dna', 'leaf', 'tree', 'globe', 'planet', 'rocket', 'brain', 'heart', 'pulse', 'pill']],
  ['Engineering', ['gear', 'wrench', 'hammer', 'bolt', 'lightbulb', 'battery', 'chip', 'laptop', 'code', 'terminal', 'wifi', 'bridge', 'building', 'columns']],
  ['Work & life', ['briefcase', 'dollar', 'coins', 'cart', 'person', 'people', 'chat', 'envelope', 'calendar', 'clock', 'target', 'trophy', 'home', 'music', 'palette', 'brush', 'camera', 'film', 'gamepad', 'ball', 'dumbbell', 'coffee', 'utensils', 'plane', 'car', 'map', 'pin', 'sun', 'moon', 'cloud', 'paw']],
  ['Marks', ['star', 'flag', 'sparkle', 'lock', 'key', 'box', 'archive', 'trash']],
];

// Emoji and symbols picked before icons were outlines.
const LEGACY = {
  '📝': 'document', '📘': 'book', '📚': 'books', '🎓': 'graduation', '📐': 'triangleRuler', '📏': 'ruler', '∑': 'sigma', '√': 'sqrt', '%': 'percent',
  '📈': 'chart', '📊': 'barChart', '⚛️': 'atom', '⚛': 'atom', '🧪': 'testTube', '🔬': 'microscope', '🌿': 'leaf', '🧠': 'brain', '❤️': 'heart', '❤': 'heart',
  '💻': 'laptop', '⚙️': 'gear', '⚙': 'gear', '🔨': 'hammer', '🔧': 'wrench', '⚡': 'bolt', '💡': 'lightbulb', '🌎': 'globe', '🏛️': 'columns', '🏛': 'columns',
  '💼': 'briefcase', '💲': 'dollar', '👥': 'people', '📅': 'calendar', '🎵': 'music', '🎨': 'palette', '📷': 'camera', '⭐': 'star', '🚩': 'flag',
  '🔖': 'bookmark', '🏠': 'home', '✈️': 'plane', '✈': 'plane', '🚗': 'car', '🏷️': 'tag', '🏷': 'tag', '📦': 'box',
};

/** The icon name for a stored value (an icon name, or an old emoji), or null. */
export function libraryIconName(value) {
  if (!value) return null;
  if (P[value]) return value;
  return LEGACY[value] || null;
}

/** An outline SVG for a folder or notebook icon, drawn in the current text colour. */
export function libraryIcon(value, size = 20) {
  const name = libraryIconName(value);
  if (!name) return null;
  const span = document.createElement('span');
  span.className = 'lib-icon';
  span.innerHTML = `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[name]}</svg>`;
  return span;
}
