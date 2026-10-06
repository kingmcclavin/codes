# Basis for the web

A browser port of the Basis iPad app (Swift Playgrounds): handwritten notebooks with an engineering calculator built in. Plain HTML, CSS and JavaScript modules, with no build step and no server code.

## Run it

Serve this folder over HTTP and open `index.html`:

```sh
cd basis-web
python3 -m http.server 8000
# open http://localhost:8000
```

Opening the file directly (`file://`) won't work because browsers block ES modules there. Any static host works too (GitHub Pages, Netlify, Cloudflare Pages). Once loaded over HTTPS, it installs as an app: use Add to Home Screen on iPad or Install in Chrome/Edge. A service worker keeps it usable offline.

## Deploy to Vercel

This folder is a static site with no build step. Import the repository in Vercel, set **Framework Preset** to *Other*, and leave the build command and output directory empty. If the app lives in a subfolder, set **Root Directory** to that folder. `vercel.json` keeps the service worker and scripts fresh after each deploy. From the CLI, run `npx vercel` in this folder.

## What's included

**Notebooks**
- Pen (fine pen, ballpoint, fountain, marker, pencil) with pressure and tilt from Apple Pencil or any stylus, plus a highlighter that multiplies over ink
- Hold still at the end of a stroke to snap it into a line, rectangle, ellipse, triangle, polygon or arrow. The Shapes tool snaps every stroke.
- Stroke eraser and a vector "pixel" eraser that splits strokes. Optional highlighter-only mode.
- Scribble to erase: scribble quickly over ink with the pen to erase the strokes, whole words, or the scribbled region
- Lasso: select, move, resize, rotate, recolor, restyle, cut/copy/paste, duplicate, arrange
- Text boxes with fonts, size, bold/italic and alignment
- Images, PDF import (pages become backgrounds you can write on), PDF and PNG export
- Templates: blank, ruled, grid, dotted, engineering, isometric, Cornell, lab notebook. Also paper sizes, orientation, paper color and endless pages.
- Pull up past the last page to add a page
- Page manager with drag-to-reorder, duplicate and sections. Undo/redo, zoom, open-notebook tabs.
- Library with nested folders, colors and icons, drag and drop, and search

**Calculator & toolbox**
- Calculator with a tape, variables (`m = 5`), scientific functions, constants, and DEG/RAD modes
- Floating calculator over notebooks, and live calculation cards on the page
- Formula library (math, physics, engineering, electrical), custom formulas, and formulas that use other formulas
- Unit converter, function grapher, calculation history

**Input**: pen and mouse draw. One finger scrolls (with momentum when you flick) and two fingers pinch-zoom. Double-tap with a finger to zoom the page edge to edge, and again to zoom back. Turn on *Draw with Finger* in ⋯ to draw with a finger. Keyboard: `1`–`6` tools, `E` eraser, `K` calculator, `⌘/Ctrl+Z` undo.

## Data

Everything is stored in this browser (IndexedDB and localStorage) on this device. **Settings → Back Up Everything** saves a JSON file you can restore in any browser.

PDF import and export load pdf.js and jsPDF from cdnjs the first time you use them.

## Not ported

These need iOS-only APIs: handwriting recognition (auto-solving handwritten math), GoodNotes import, and IPA export. The Engineering Tools screen and the data tables from Data & Graphs aren't ported yet. Graphs are.

## Layout

```
index.html, styles.css, sw.js, manifest.webmanifest, icons/
js/app.js          shell, routing, tabs, preferences
js/library.js      sidebar, notebook list, new notebook, search, settings
js/editor.js       notebook toolbar, tool options, pages, page settings, calculator cards
js/canvas.js       layout, zoom/scroll, rendering, pointer input, tools
js/elements.js     strokes, shapes, images, text: geometry, hit testing, stroke outlines
js/render.js       page templates and element drawing
js/recognizer.js   shape recognition (ported from ShapeRecognizer.swift)
js/erase.js        vector erasing (ported from ErasureEngine.swift)
js/calc/           expression engine, units, built-in formulas, calculator state
js/calculator.js   calculator, formulas, units, history and graph screens
```
