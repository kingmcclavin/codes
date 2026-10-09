# Basis for the web

Basis is free forever, with no ads and no paid features.

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
- `.basis` notebook export and import, in the same format as the Basis iPad app (editable ink, shapes, text, calculation cards, images and paper)
- GoodNotes import (`.goodnotes`): pages, paper, pen and highlighter strokes as editable ink, and images. Typed text boxes aren't imported yet.
- Notability import (`.note`): handwriting as editable ink with its width variation, paper style (dots, grid, lines), page size, typed text and annotated PDFs. Images and audio aren't imported yet.
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

## Cloud Sync (Google Drive, in testing)

People can sync their notebooks to their own Google Drive (Settings → Cloud Sync). Basis only gets access to the files it creates (the `drive.file` permission), and notebooks go straight from the browser to Drive. The one server piece is `api/google-oauth.js`, a Vercel function that completes Google sign-in with the client secret; it stores nothing.

One-time setup (free):

1. In the [Google Cloud console](https://console.cloud.google.com/), create a project (for example "Basis").
2. **APIs & Services → Library**: enable the **Google Drive API**.
3. **Google Auth Platform → Branding**: app name "Basis", your email. **Audience**: External. **Data access**: add the scope `https://www.googleapis.com/auth/drive.file`.
4. **Clients → Create client → Web application.** Authorized JavaScript origin: your site (e.g. `https://basis-web.vercel.app`). Authorized redirect URI: the same address with a trailing slash (e.g. `https://basis-web.vercel.app/`).
5. In Vercel → Project → Settings → **Environment Variables**, add `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` from that client, then redeploy.
6. While the app is in Google's **Testing** mode, only listed test users can connect, and Google signs them out after 7 days. **Publish** the app (Audience → Publish app) to let anyone connect and stay connected; `drive.file` doesn't need Google's security review.

## Data

Everything is stored in this browser (IndexedDB and localStorage) on this device. **Settings → Back Up Everything** saves a JSON file you can restore in any browser.

PDF import/export and GoodNotes paper use pdf.js and jsPDF, bundled in `vendor/` (Apache-2.0 and MIT licensed), with cdnjs as a fallback. The AI tab uses the Anthropic TypeScript SDK (MIT), bundled as `vendor/anthropic-sdk.mjs` and loaded only when AI is used.

**AI (bring your own key, in testing):** the AI tab walks you through connecting your own Claude (Anthropic) or Gemini (Google) account. The key stays in this browser, isn't included in backups, and requests go straight from the browser to that provider. Basis has no server.

## Not ported

These need iOS-only APIs: handwriting recognition (auto-solving handwritten math) and IPA export. The Engineering Tools screen and the data tables from Data & Graphs aren't ported yet. Graphs are.

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
