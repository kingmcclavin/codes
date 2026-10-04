# Basis — Engineering Notebook (web prototype)

Basis is where you do your engineering work: notebooks → sections → pages, with an
infinite engineering canvas, real maths typesetting, live variables with units,
a scientific calculator and engineering tools in one place.

This is the web prototype, built to explore how Basis looks and feels before more
of it moves into the native iPad app. It runs offline, needs no account, and
stores everything in the browser (IndexedDB).

## Running it locally

Requires **Node.js 20+** (22 recommended).

```bash
cd basis
npm install
npm run dev          # http://localhost:5173
```

To try it on an iPad or phone on the same Wi‑Fi:

```bash
npm run dev -- --host   # then open the "Network" URL it prints, e.g. http://192.168.1.20:5173
```

## Building for production

```bash
npm run build        # type-checks, then outputs a static site to basis/dist
npm run preview      # serves dist/ at http://localhost:4173 (service worker + offline enabled)
```

`dist/` is a fully static site with relative paths (`base: './'`), so it works at a
domain root or in a sub-folder.

## Deploying for free

### Vercel (simplest)
1. Push the repo to GitHub.
2. On vercel.com: **Add New → Project →** import the repo.
3. Set **Root Directory** to `basis`. Vercel detects Vite automatically (`vercel.json` is included).
4. Deploy. You get a `https://<name>.vercel.app` URL.

CLI alternative: `npm i -g vercel && cd basis && vercel --prod`.

### GitHub Pages
A workflow is included at `.github/workflows/deploy-basis.yml`.
1. In the GitHub repo: **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. Push to `main` (or run the workflow manually from the **Actions** tab).
3. The site appears at `https://<user>.github.io/<repo>/`.

Hash-based routing (`#/n/…`) means no server rewrites are needed on either host.

### Netlify / Cloudflare Pages
Base directory `basis`, build command `npm run build`, publish directory `basis/dist`.

## Using Basis in Safari on iPad

1. Open the deployed URL (HTTPS is needed for offline mode) in Safari.
2. Tap **Share → Add to Home Screen**. Basis then launches full-screen with no Safari UI,
   like a native app, and keeps working offline after the first load.
3. **Apple Pencil** draws with pressure. Once a Pencil is detected, fingers switch to
   navigation (palm rejection): **one finger pans, two fingers pinch-zoom and pan.**
   Change this under **Settings → Apple Pencil & touch** (Auto / Draw / Pan).
4. Portrait: the sidebar becomes a drawer (☰ button, top left). Panels (calculator,
   variables, tools, files) float over the canvas.
5. Data is stored per browser. Exporting a notebook (**⋯ → Export notebook**) gives you a
   `.basis` backup file that you can re-import from the Library (upload icon).

> Safari may clear website data that hasn't been used for a long time. Adding Basis to the
> Home Screen and exporting notebooks now and then keeps your work safe.

## What's in the prototype

| Area | Features |
|---|---|
| **Library** | Notebook cards (name, description, icon, colour, page count, last edited), favourites, recently opened pages with live thumbnails, sorting, search, import/export, settings |
| **Notebook** | Sections and pages; add, rename, duplicate, delete, move between sections; drag to reorder pages (mouse, touch or Pencil); resizable/collapsible sidebar |
| **Canvas** | Infinite pan/zoom; pen (pressure-sensitive), highlighter, stroke eraser, select / box-select / move / resize, text (with inline `$…$` maths), shapes, lines, arrows, equations, images, reference notes, variables blocks, data tables, graphs; undo/redo; copy/paste/duplicate; z-order; recolour |
| **Templates** | Blank, Engineering grid, Graph paper (with axes), Dot grid, Cornell, Isometric, Custom (spacing, line weight, lines/dots, visibility, page colour) |
| **Equations** | Type `F = m*a`, `1/2*m*v^2`, `int(f, x, a, b)`, `sum(...)`, `pd(f, x)`, `vec(F)`, `[a, b; c, d]` or raw LaTeX; KaTeX rendering with a symbol palette |
| **Variables** | `m = 5 kg`, `v = 12 m/s`, `KE = 1/2*m*v^2` → `360 J`. Every Variables block on a page shares one scope with a dependency graph; editing an input updates all results. `-> kJ` converts. The Variables panel lists inputs vs. derived values and lets you edit inputs |
| **Units** | Length, mass, time, force, energy, power, pressure, velocity, temperature, angle, area, volume; e.g. `25 ft -> m` = 7.62 m, `50 psi -> kPa` = 344.7 kPa |
| **Calculator** | Trig and inverse trig (DEG/RAD), ln/log, powers and roots, EE notation, complex numbers (`i`), physical constants, Ans, history, insert result into the page |
| **Engineering tools** | Unit converter, quadratic solver (real and complex roots), 3D vector calculator, statistics, Ohm's law; registry design so more tools are easy to add |
| **Tables** | Add/remove rows and columns, edit cells, formulas (`=A1*2`, `=sum(B1:B5)`, `=mean(C:C)`), one-tap **Plot** into a graph |
| **Graphs** | Multiple functions, data series, drag to pan, wheel/buttons to zoom, grid, ticks, axis labels; functions can use the page's numeric variables |
| **Search** | ⌘K / ⌘F across notebooks, sections, pages, text, equations, variables, tables, notes; jumps to and highlights the matching element |
| **Files** | Import PDFs (each page becomes a notebook page you can write on), import images, attach any file, file browser; export page to PDF (print), page JSON, notebook `.basis` |
| **Offline** | IndexedDB storage with debounced autosave (⌘S forces a save), generated service worker precaches the app, installable PWA manifest |
| **Themes** | Polished dark charcoal mode and a light cream-paper mode; system option |

### Keyboard shortcuts (desktop)
`⌘Z` undo · `⇧⌘Z` redo · `⌘S` save · `⌘F`/`⌘K` search · `⌘\` sidebar · `V` select · `H` pan
(or hold Space) · `P` pen · `M` highlighter · `E` eraser · `T` text · `S` shapes · `L` line ·
`A` arrow · `Q` equation · `I` image · `Enter` edit selection · `⌫` delete · `⌘D` duplicate ·
`⌘C/⌘V` copy/paste · `⌘0` 100% · `⌘1` fit · `?` all shortcuts.

## Architecture

```
src/
├── app/App.tsx                 # shell, routing, global shortcuts
├── models/                     # Notebook, Section, Page, CanvasElement, templates (plain serialisable data)
├── store/                      # zustand stores, kept separate:
│   ├── library.ts              #   notebooks/sections/pages + debounced persistence
│   ├── canvas.ts               #   tool, options, selection, per-page undo history
│   ├── calculator.ts           #   calculator state
│   └── ui.ts                   #   routing, theme, panels, dialogs
├── services/
│   ├── calculations/           # math engine (mathjs wrapper), TeX writer, variables/dependency
│   │                           #   graph, calculator, tables, graph sampling, tool maths
│   ├── units.ts                # engineering unit catalogue + conversion
│   ├── storage.ts              # IndexedDB persistence (sync engine would plug in here)
│   ├── files.ts, export.ts     # attachments, .basis import/export
│   ├── canvas/                 # geometry/hit-testing, ink rendering, factories, PDF/image insert
│   ├── input/pointerPolicy.ts  # Pencil vs finger decisions (replace with PencilKit natively)
│   └── search.ts, offline.ts
├── components/
│   ├── Library/ Notebook/ Canvas/ Toolbar/ Calculator/ Equation/ Graph/
│   └── EngineeringTools/ Panels/ Files/ Search/ Settings/ Brand/ common/
└── demo/                       # demo notebooks authored in code
```

### Parts to replace in the native iPad app
These are deliberately isolated so they can be swapped without touching the UI:

- **`services/input/pointerPolicy.ts`**: Pencil detection and palm rejection via Pointer Events → `PencilKit` / `UITouch.type`, plus Pencil hover, tilt and double-tap.
- **`services/canvas/ink.ts`**: stroke smoothing with `perfect-freehand` → `PKDrawing`, or a Metal renderer.
- **`services/canvas/insert.ts` `importPdf`**: PDFs are rasterised with pdf.js → `PDFKit`, keeping vector pages.
- **`services/storage.ts`**: IndexedDB → Core Data / SwiftData + CloudKit sync. Entities are already plain JSON with ids and timestamps.
- **Page → PDF export**: uses the browser's print dialog → `UIGraphicsPDFRenderer`.
- **`services/calculations/engine.ts`**: the only module that touches mathjs. A Swift engine can expose the same functions.

## Notes and limitations
- The eraser removes whole strokes or shapes. Partial (pixel) erasing is a Phase 4 item.
- Variables are scoped to a page. Notebook-wide variables would be the next step for the dependency engine.
- Units are only recognised directly after a number (`12 m/s`), so a variable called `m` never collides with metres. Write `5*g`, not `5 g`, when you mean a variable `g`.
- The demo notebooks are seeded on first launch. **Settings → Restore demo notebooks** brings them back.
- The Basis mark in `components/Brand/Logo.tsx` (two basis vectors from one origin) is a placeholder. Swap in the official logo asset there and in `public/`.
