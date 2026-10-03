# Basis

A focused, native iPad note-taking and handwriting app built around one thing:
a fast, precise, vector "digital paper" canvas for Apple Pencil. It's aimed at
math, science and engineering notes.

There are no notebook covers, shelves or thumbnail grids. The library is a
simple list, and the canvas fills the screen.

## Building

Requirements: Xcode 15 or later, iPadOS 17 SDK, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cd Basis
xcodegen generate
open Basis.xcodeproj
```

Choose the **Basis** scheme, pick your signing team in *Signing & Capabilities*,
and run it on an iPad. Apple Pencil needs a real device; in the simulator you can
turn on **… › Draw with Finger**. Run the unit tests with ⌘U.

## Features

| Area | What you get |
| --- | --- |
| **Pages** | Letter, Legal, Tabloid, A3, A4, A5, Square, iPad screen sizes (13″/11″/Air/mini), 16:9 and 4:3. Custom sizes in in / cm / mm / pt / px. Portrait or landscape. |
| **Paper** | White, off-white, black or any custom color. Blank, ruled (with margin), grid, dotted and engineering (5 subdivisions per major square) templates with adjustable spacing. Settings apply per page or to all pages. |
| **Pens** | Fine pen, ballpoint, fountain pen, marker and pencil (with tilt shading) presets. You can adjust color, thickness, opacity, pressure sensitivity, tilt sensitivity and line style (solid, dashed, dotted), and save your own presets. |
| **Colors** | Preset palette, recently used colors and the system color picker. |
| **Highlighter** | Its own tool and palette. Multiply blending keeps the ink under it crisp. Hold at the end to get a perfectly straight highlight. |
| **Eraser** | A stroke eraser, a partial ("pixel") eraser that splits vector strokes, an adjustable size, and a highlighter-only option. |
| **Scribble to erase** | Scribble quickly over ink with the pen. You can set it to erase the strokes you crossed, whole objects (for example a whole word), or everything inside the scribbled region. |
| **Shapes** | Hold the pencil still at the end of a stroke (or use the Shapes tool) to turn it into a line, arrow, circle, ellipse, rectangle, square, triangle, polygon, polyline or smooth curve. Drawing a small "V" at the end of a line turns it into an arrow. |
| **Lasso** | Select ink, shapes, images and text, then move, resize (corners keep the aspect ratio, edge handles stretch shapes and images) or rotate (snaps to 45°). You can also cut, copy, paste (including between documents and apps), duplicate, delete, recolor, restyle and change the stacking order. |
| **Text** | Font, size, color, bold, italic and alignment. Tap existing text to edit it. |
| **Images** | Insert from Photos or paste them in. Move, resize, rotate and delete them. |
| **Undo** | Unlimited. Each user action is one step. Two-finger tap undoes, three-finger tap redoes, and ⌘Z / ⇧⌘Z work too. |
| **Navigation** | Pinch to zoom from an overview of several pages up to 24× (tiles stay sharp up to 32×). Two-finger pan, double-tap to fit the width, fit-page and fit-width buttons, a zoom percentage indicator and quick zoom controls. |
| **Pages list** | Add, delete, duplicate, reorder and jump to pages. |
| **Persistence** | Documents save automatically in the background and reopen exactly where you left off: same document, page, zoom, scroll position and tool settings. Export to vector PDF. |

## Architecture

```
Basis/
├─ Model/        Value types: Stroke, ShapeElement, ImageElement, TextElement,
│                CanvasElement, page formats, tool settings (all Codable)
├─ Engine/       PageStore + SpatialGrid, DocumentModel, commands & History,
│                StrokePathBuilder, PageRenderer, ErasureEngine, TextLayout
├─ Recognition/  ShapeRecognizer, BezierFitter, ScribbleDetector
├─ Tools/        CanvasTool protocol + Pen/Shapes, Eraser, Lasso, Text tools,
│                SelectionController, ScribbleEraser, Clipboard
├─ Canvas/       CanvasViewController, tiled PageView, OverlayView,
│                PencilInputRecognizer, TextEditingController
├─ Persistence/  DocumentStore (package format), AutosaveController, AppPreferences
└─ UI/           SwiftUI: library, new document, editor chrome, tool bars,
                 pen settings, page manager/settings, selection inspector
```

### Vector ink

Every stroke keeps its raw samples: position, pressure, altitude, azimuth and
timestamp, plus a style (tool, color, width, opacity, pressure and tilt
sensitivity, line style). Nothing is ever flattened to a bitmap. Rendering,
erasing, selecting, transforming, undo and saving all work on this data.
`StrokePathBuilder` turns the samples into a smooth variable-width outline
(or a stroked centerline for constant-width and dashed ink). The result is
cached per element revision.

### Rendering pipeline

- Each page is a `CATiledLayer` with 5 magnified detail levels. Tiles are drawn
  straight from vector data at the tile's own resolution, so ink is sharp at
  any zoom and there is never one huge page bitmap.
- `PageStore` keeps a uniform spatial grid, so a tile only asks for the elements
  that overlap it. Adding a stroke invalidates only the tiles under that
  stroke. Rendering cost depends on what is visible, not on the page's total
  stroke count.
- The in-progress stroke is drawn in a **screen-space overlay** that is not
  zoomed. It uses coalesced touches for accuracy and predicted touches to cut
  perceived latency. Only the dirty rectangle at the stroke's tail is redrawn
  each frame.
- After a commit, the overlay keeps drawing the new ink until the tile that
  contains it has redrawn (it tracks the page generation), so ink never
  flickers.

### Input

`PencilInputRecognizer` accepts only `.pencil` touches, which gives palm
rejection. It passes touches on the moment UIKit delivers them.
`touchesEstimatedPropertiesUpdated` fills in Apple Pencil's late-arriving force
values. Fingers are left to the scroll view for panning and zooming, to the
two- and three-finger tap gestures, and to finger drags of a selection.
Double-tapping Apple Pencil follows the system setting (switch to eraser or to
the previous tool).

### Commands & undo

Every change to a document goes through an `EditCommand`, such as
`ElementsEdit` (removals, insertions and updates on one page),
`ReorderElementsCommand`, page commands or `CompositeCommand`. Tools that change
the document continuously, like the eraser, apply edits as they go and then
record **one** composite command when the pencil lifts. That's why undo always
works on whole user actions.

### Adding a tool

1. Implement `CanvasTool`: `began/moved/ended/cancelled` receive page-space
   `ToolInput`, and `drawOverlay` draws transient feedback.
2. Change the document only through `EditCommand`s via `host.history`.
3. Add a case to `ToolKind` and to the factory in
   `CanvasViewController.activateTool`, and optionally an options bar in
   `ToolOptionsBar`.

The canvas engine itself doesn't need to change. New element types are
likewise one case in `CanvasElement` plus drawing code in `PageRenderer`.

### Shape recognition

`ShapeRecognizer` fits the geometry you *intended* rather than smoothing the
stroke:

- **Lines** use a total-least-squares fit and snap to 0°, 90° and 45°. Their
  endpoints snap to nearby shape vertices, ends and centers.
- **Polygons** find corners from windowed turning angles. Each side is fitted
  as a least-squares line, and the vertices are where neighboring sides
  intersect. Near-right angles become exact (right triangles), near-regular
  polygons are regularized, and near-axis edges are straightened.
- **Rectangles and squares** get their orientation from the dominant edge
  direction.
- **Ellipses and circles** are fitted with least squares in the principal-axis
  frame, then snapped to a circle or to the axes.
- **Arrows** are recognized when drawn in one stroke (a shaft plus a head that
  doubles back), or by adding a "V" to an existing line.
- **Open polylines** snap each segment to the axes, which suits graph axes and
  angles.
- **Curves** use Schneider least-squares Bézier fitting. A complex stroke you
  pause on, such as a word, stays as ink.

### Scribble detection

`ScribbleDetector` counts large direction reversals along the stroke's
principal axes, using hysteresis so small wiggles don't count. It also
requires a high ink density (path length compared to size) and speed, with
thresholds measured in screen points. Dense zig-zags need to be far denser
than cursive. Then `ScribbleEraser` only erases when the scribble actually
covers existing content. Normal handwriting such as "mmm" or "lll" is covered
by unit tests to make sure it never triggers.

### Document format

A document is a folder in the app's Documents directory, which you can see in
the Files app:

```
Basis Documents/<uuid>.basis/
  manifest.json      title, page order, tool settings, view state
  pages/<uuid>.json  one file per page; only changed pages are rewritten
  assets/            inserted images
```

Stroke samples are packed as little-endian Float32. Autosave takes a
copy-on-write snapshot of the pages that changed on the main thread, then
encodes and writes them atomically on a background queue.
