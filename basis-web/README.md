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

The Engineering Tools screen and the data tables from Data & Graphs aren't ported yet (Graphs are). Handwriting recognition works differently from the iPad app: it uses your own AI key (see the AI tab) instead of Apple's on-device recognition.

## Layout

```
index.html, styles.css, sw.js, manifest.webmanifest, vercel.json, icons/
api/google-oauth.js  Vercel function: finishes Google sign-in for Cloud Sync (stores nothing)
vendor/              pdf.js, jsPDF, Anthropic SDK (bundled, no build step)
js/app.js            shell, routing, tabs, preferences, loading splash
js/library.js        sidebar, notebook list, new notebook, search, settings, imports
js/editor.js         notebook toolbar, tool options, pages, export, crop, find in notebook
js/canvas.js         layout, zoom/scroll, rendering, pointer input, palm rejection, tools
js/elements.js       strokes, shapes, images, text: geometry, hit testing, stroke outlines
js/render.js         page templates and element drawing
js/history.js        undo/redo
js/model.js          paper sizes, templates, pens and their defaults
js/store.js          IndexedDB storage, backups
js/recognizer.js     shape recognition (ported from ShapeRecognizer.swift)
js/erase.js          vector erasing (ported from ErasureEngine.swift)
js/scribble.js       scribble to erase
js/pdf.js            PDF import/export, sharp PDF re-rendering
js/goodnotes.js      GoodNotes import          js/notability.js  Notability import
js/basisfile.js      .basis import/export (iPad app format)
js/ai.js, aiscreen.js     bring-your-own-key AI (Claude or Gemini) and its setup tab
js/recognize.js      handwriting recognition and search
js/sync.js, syncsettings.js  Google Drive Cloud Sync and its settings
js/tour.js           tutorial          js/features.js  feature flags, Developer Mode
js/icons.js, libicons.js  app icons and folder/notebook icons
js/calc/, js/calculator.js  calculator engine, units, formulas, and their screens
js/version.js        version shown in Settings
```

## Working on Basis

Notes for anyone continuing this project, including a new Claude Code session.

**Principles**
- **Free forever, no ads, no paid tier, no tracking.** Nothing gets locked behind payment. Anything that would cost money per user (AI, cloud storage) uses the person's own account: bring your own AI key, bring your own Google Drive.
- **Local-first.** Notebooks live in the browser (IndexedDB). Sync and AI are optional extras.
- **No build step and no server.** Plain ES modules served as static files; third-party code is bundled in `vendor/`. The only server code is `api/google-oauth.js`, which exists because Google requires a client secret for long-lived sign-in.
- **iPad and Apple Pencil first.** Test with touch, pen and palm in mind. Safari quirks already handled: assets stored as raw bytes (Safari can't read Blobs back from IndexedDB), touch events cancelled on the page (stops text selection under a resting palm), and live ink repainted only around the stroke tip (Safari draws canvases on the CPU).
- **Plain language** in everything people see: no jargon in buttons, messages or errors.

**Each update**
- Bump the version in `js/version.js` (shown in Settings) by one: 1.33 → 1.34, and so on.
- Bump the cache name in `sw.js` (`basis-v33` → `basis-v34`) at the same time and add any new files to its list, or installed copies keep old files.
- New, unfinished features go behind a flag in `js/features.js` with status `testing`. They show only in Developer Mode (tap the version in Settings five times, then the password; only its hash is in the code). Change the status to `released` when ready.

**Where the code lives**
- `kingmcclavin/basis-web`, branch `main`: what Vercel deploys.
- `kingmcclavin/codes`, branch `basis-web-app`, folder `basis-web/`: a mirror kept in step with every change.
- A private preview is published as a claude.ai artifact. It can't run `api/` or reach outside services, so test sign-in and AI on the Vercel site.

**Testing changes**
- Serve the folder (`python3 -m http.server`) and drive it with Playwright in Chromium, with service workers blocked so changes load.
- Fake outside services instead of calling them: Claude and Gemini replies, Google sign-in and a small in-memory Google Drive (two browser contexts act as two devices sharing one Drive).
- Things that have broken before and are worth re-checking: palm rejection and finger scrolling; double-tap zoom; smooth ink while writing and pixel-identical ink after; undo; moving selections between pages; cropping; GoodNotes and Notability imports; sharp PDF pages at high zoom; sync conflicts keeping both versions.

**On hold or next**
- Study Buddy (AI practice exams, flashcards and summaries from your notes), paused while AI free-tier limits get sorted out.
- Dropbox as a second Cloud Sync option.
- Highlighting search matches on the page; moving content stranded past a page edge back onto the page.
- Engineering Tools and the Data & Graphs tables from the iPad app.
