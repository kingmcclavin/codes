# Skyline Links — arcade golf for Swift Playgrounds (iPad)

An original single-player arcade golf game built with **Swift, SwiftUI and SpriteKit only**.
No Mac, Xcode, art assets, sound files, packages or servers are needed.

The whole game lives in `SkylineLinks.swiftpm/`, a Swift Playgrounds **App** project.

---

## Running it on iPad

### Option A — open the project folder (fastest)
1. On GitHub, tap **Code → Download ZIP** for this repository (in Safari on the iPad).
2. In the **Files** app, tap the ZIP to unzip it.
3. Open the unzipped folder and tap **`SkylineLinks.swiftpm`**. It opens in Swift Playgrounds.
4. Press **▶︎ Run** (or the app preview). Rotate to landscape on iPad for the best view.

### Option B — paste the files into a new App
Use this if Option A will not open (for example, an older version of Swift Playgrounds).
1. In Swift Playgrounds tap **+ → App**. Delete `ContentView.swift` and the generated `MyApp.swift`.
2. Create the folders `App`, `Core`, `Game`, `Swing`, `Clubs`, `Courses`, `Progression`, `UI`.
   Folders are optional; Swift does not care where a file sits.
3. For every `.swift` file in `SkylineLinks.swiftpm/` (except `Package.swift`), create a file with the
   same name and paste in its contents.
4. Run.

Requirements: Swift Playgrounds 4.4 or newer and iPadOS 17 or newer.

---

## How to play

| Step | Action |
|------|--------|
| Aim | **3D:** drag left/right to turn, up/down to change distance (the yellow ring is the target). **2D:** drag anywhere to move the target. The dotted line shows the no‑wind flight and roll. |
| Club | Pick a club from the strip at the bottom. The game pre‑selects a sensible club and target every shot. |
| Power | **Hold** the swing button. Release when the bar reaches the white line (100% = exactly the aimed distance; up to 110% overswing). |
| Timing | **Tap** again as the needle crosses the green **PERFECT** zone. The needle bounces back and forth (a little faster each pass) until you tap. Early pulls left and hooks, late pushes right and slices. |
| Putt | Hold and release only. Read the pulsing slope arrows; only part of the roll line is shown. |
| Wind | Shown top right relative to your view. It pushes the ball in flight; the preview ignores it. |
| 👁 | Toggles a whole-hole overview. ↩︎ resets the aim. |

Beat (or match) the rival's target score to unlock the next course. Earn coins, buy packs, collect clubs,
level them up with duplicate cards and swap them into your bag.

---

## Project map

```
SkylineLinks.swiftpm
├── Package.swift               Swift Playgrounds app manifest
├── App/
│   ├── SkylineLinksApp.swift   @main app + screen router (RootView)
│   ├── GameStore.swift         ObservableObject wrapping the saved progress
│   ├── Feedback.swift          haptics + synthesized sound effects (AVAudioEngine, no audio files)
│   └── PlatformBridges.swift   Vec2/RGBColor → CGPoint/UIColor/Color
├── Core/GameMath.swift         Vec2, rects, seeded RNG, helpers
├── Game/
│   ├── Terrain.swift           8 surfaces and how each affects power, accuracy, bounce, roll
│   ├── GolfHole.swift          data model of a hole (fairway strips, green, bunkers, water, trees, slope, wind)
│   ├── GolfPhysics.swift       ball flight / bounce / roll / cup + shot solver
│   ├── CameraController.swift  smooth framing camera rig
│   ├── CourseRenderer.swift    turns a GolfHole into SpriteKit shapes
│   ├── GolfGameScene.swift     SKScene: rendering, ball animation, camera, particles, aim drag
│   ├── GolfRenderer.swift      the interface both the 2D and 3D views implement
│   └── RoundController.swift   round rules: strokes, penalties, clubs, swing → shot
├── Game3D/
│   ├── Course3DBuilder.swift   terrain mesh following elevation, painted course texture, 3D trees/rocks/cacti
│   └── GolfScene3D.swift       SceneKit view: chase camera, ball, flag, aim ring, preview, effects, drag aiming
├── Swing/SwingSystem.swift     timing windows, 3‑step swing meter, shot planner, auto aim advisor, score names
├── Clubs/
│   ├── Club.swift              11 club types, rarities, stats
│   ├── ClubAbility.swift       data-driven abilities + how stats/abilities/lie modify a shot
│   └── ClubCard.swift          51 club cards (11 starters + 40 collectible), upgrade costs
├── Courses/
│   ├── GolfCourse.swift        course + theme models, round lengths, targets
│   ├── CourseGenerator.swift   reusable hole components (dogleg, island green, split fairway, …)
│   └── CourseDatabase.swift    10 themed campaign courses × 18 holes
├── Progression/
│   ├── PlayerProgress.swift    everything that is saved (tolerant decoding for future fields)
│   ├── PackSystem.swift        Basic / Premium / Elite packs with visible odds
│   ├── RewardSystem.swift      coins/XP per round, unlocks, best scores
│   └── SaveManager.swift       JSON in UserDefaults (offline)
└── UI/                         SwiftUI screens: menu, courses, clubs, packs, settings, HUD, summary
```

Everything in `Core`, `Game/Terrain|GolfHole|GolfPhysics|CameraController`, `Swing`, `Clubs`, `Courses`
and `Progression` only imports Foundation, so the rules are independent of the UI.

---

## What is in this version

All seven planned stages are present in a first pass:

1. **App + scene:** SwiftUI app hosting a SpriteKit scene (`SpriteView`), procedural course art, ball, camera.
2. **Swing:** drag aiming, trajectory preview, hold/release power meter, timing needle with
   Perfect / Great / Good / Early / Late / Poor results, separate putting meter.
3. **Physics + scoring:** gravity, drag, wind, side spin (hook/slice), backspin, bounce, roll, green slope,
   elevation, trees, cup capture and lip‑outs. Water (drop, +1), out of bounds (stroke and distance),
   max score par+4, birdie/eagle/etc.
4. **Clubs:** 11 club types, 51 cards (11 starters + 40 collectible) across 5 rarities with Power / Accuracy / Forgiveness / Spin / Control /
   Distance, and 9 data-driven ability types. Forgiveness widens the timing windows; Control slows the meter.
5. **Economy:** coins, three packs with odds shown, duplicates → upgrades (stats and ability strength).
6. **Campaign:** 10 courses (Clover Meadows → Grand Summit) with themed visuals and rising difficulty,
   3 / 9 / 18-hole rounds, rival target scores, unlocks and a rewards screen.
7. **Polish:** camera fly-over intro, ball trail, sand/water/leaf/confetti particles, synthesized sounds, haptics.

### 3D view (SceneKit)

Rounds play in 3D by default. **Settings → 3D view** switches back to the classic top-down 2D view at any time.
Both views share the same rules, physics, swing and HUD; only the drawing and camera differ.

* Camera sits behind the ball looking down the aim line, follows the ball in flight, drops low for putts,
  and the 👁 button gives a high overview of the hole.
* The ground is a mesh that follows the hole's uphill/downhill shape, textured with a painted top-down
  image of the hole so fairway, green and bunker edges stay sharp. Trees, pines, palms, cacti and rocks are 3D.
* SceneKit is built into iPadOS and works in Swift Playgrounds. Apple has marked it as no longer getting new
  features, but it continues to run.

### Verification notes

* This was written without access to a Mac, an iPad or a Swift compiler, so it has **not yet been compiled**.
  The code sticks to long-standing SwiftUI/SpriteKit APIs (iOS 17), avoids macros, `async`/actors and
  third‑party code, and uses Swift 5 language mode to stay clear of strict-concurrency errors.
* The gameplay rules (course generator, physics, auto-aim, scoring) were ported to Python and simulated:
  all 180 holes were completed by simulated players with no stuck balls, and the rival targets form a
  difficulty curve (early courses beatable by casual play, the last courses need good timing and upgraded clubs).
* If Swift Playgrounds reports an error, copy the message (file and line) and it can be fixed quickly.

### Ideas for next steps
Branching campaign, daily challenges, more ability types (multi-ability legendaries already work),
custom artwork via asset catalogs, club loadout presets, and hand-designed signature holes using `HoleBlueprint`.
