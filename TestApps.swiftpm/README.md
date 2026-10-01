# Test Apps — a personal dev-testing container (Swift Playgrounds / iPad)

A SwiftUI app you build **entirely on an iPad in Swift Playgrounds** (no Mac,
Xcode, Terminal, Homebrew, CocoaPods, signing tools, or desktop build system).
It gives you a **virtual Home Screen** where you import `.ipa` builds of apps you
are developing, manage multiple builds/versions, inspect them, and prepare their
data containers — optimised for a tight import → test → fix loop.

---

## ⚠️ The one honest limitation (read this first)

**This container cannot natively execute a guest app's binary, and it does not
pretend to.**

A Swift Playgrounds–built app runs as an ordinary App Store–model iOS app inside
the normal sandbox. iOS only runs Mach-O code that is code-signed with a
signature the kernel trusts **and** loaded by the system loader at launch.
Third-party sandboxed apps get no `fork`/`exec`, cannot `dlopen` arbitrary
foreign/unsigned Mach-O, and get no JIT (no `dynamic-codesigning` entitlement).
A guest `.ipa` is signed for *its own* bundle id, not for execution inside our
process, and we deliberately **do not** attempt to re-sign it or bypass Apple's
signing/security model.

Projects like **LiveContainer** rely on contexts a normal Swift Playgrounds app
does not have — TrollStore / sideloading with special entitlements, a debugger
attaching for JIT, or a jailbreak. None of those are available to this app, so
the honest, maximum legitimate capability is: **import, validate, inspect,
version-manage, and prepare data containers** for your builds, and report the
execution limit clearly.

The runtime is a **swappable module** (`Runtime/AppRuntime.swift`). If a stronger
capability becomes available to you later, you can drop in a new `AppRuntime`
without touching the Home Screen or the IPA-management code, and `Launch` will
use it automatically.

When you tap **Launch**, the app shows an **Inspection** view (full metadata +
confirmation the build is stored and its data dir is ready) instead of faking a
running app.

---

## What works today (fully functional)

- **Virtual Home Screen** — icons, names, active-build labels, search, favorites,
  recently used, folders, and a long-press context menu (Launch, Info, Favorite,
  Rename, Move to Folder, Duplicate, Delete).
- **IPA import** via the Files picker → copies the `.ipa` into the app's private
  container → parses it → shows it on the Home Screen.
- **Real IPA parsing** with no external dependencies:
  - a minimal, read-only **ZIP reader** (`Services/MiniZip.swift`) that inflates
    DEFLATE entries with the system `Compression` framework (iPadOS does not ship
    a public ZIP API, so we parse it ourselves);
  - `Info.plist` (binary or XML) via `PropertyListSerialization`;
  - **icon** extraction (on-device `UIImage` decodes Apple-optimised/CgBI PNGs);
  - **Mach-O architectures** from the executable header;
  - **app extensions** under `PlugIns/`;
  - best-effort **entitlement keys** from `embedded.mobileprovision`.
- **Metadata shown**: display name, bundle id, version, build, min iOS, device
  family, architectures, bundle size, extensions, entitlements.
- **Version management** — multiple builds per bundle id, mark an **active**
  build, and a **New Version Detected** flow (Replace / Keep Both / Cancel).
- **Build history** per app with one-tap "Make Active".
- **App operations** — Launch, Replace, Duplicate, Rename, Delete, Clear Data,
  Reset App, Export Diagnostics.
- **Per-build isolated data directories** (`Documents/ Library/ Preferences/ …`)
  — best-effort within this container's sandbox (see Safety).
- **Compatibility report** — a static ✓/⚠/✗ checklist plus an explicit runtime
  verdict, with GOOD / LIMITED / UNSUPPORTED. Flagged builds can still be stored
  and inspected.
- **Development console** — launch events, runtime errors, termination,
  compatibility/file-system/loading errors, with category filters, **Copy
  Diagnostic Log**, share, and **Clear Log**.
- **Local-only + safety gate** — nothing is ever uploaded; a one-time
  acknowledgment explains that imported apps are not sandboxed from each other
  the way independently-installed apps are.

### Stage status (from the brief)

| Stage | Scope | Status |
|------|-------|--------|
| 1 | Container UI / Home Screen / navigation / settings / library | ✅ Done |
| 2 | IPA import, ZIP inspection, Info.plist, metadata, icon | ✅ Done |
| 3 | Multiple versions, delete/replace/duplicate, build history, data dirs | ✅ Done |
| 4 | Architecture / OS / entitlement / extension analysis | ✅ Done |
| 5 | Runtime | ⚠️ Implemented as an honest, modular `InspectionRuntime` that reports the execution limit; ready to swap for a stronger runtime later |

---

## Installing on your iPad (no Mac required)

1. Get the `TestApps.swiftpm` folder onto the iPad — e.g. with the **Working
   Copy** git client, iCloud Drive, AirDrop, or the Files app.
2. Open it in **Swift Playgrounds** (tap the `.swiftpm` package).
3. Press **Run**. (In **App Settings** you can set a real app icon.)

> `Package.swift` uses `AppleProductTypes` / `.iOSApplication`, which exist only
> inside Swift Playgrounds (and Xcode). A plain command-line `swift build` on
> Linux/macOS will **not** resolve this package — that is expected.

### Importing a build
Build your app's `.ipa` in Swift Playgrounds (or wherever), save it to Files,
then in Test Apps tap **Import IPA** and pick it. Re-importing a newer build of
the same bundle id offers **Replace / Keep Both / Cancel**, so your calculator
loop is: export new `.ipa` → Import → Replace → Launch (inspection).

---

## Project structure

```
TestApps.swiftpm/
  Package.swift              App Playground manifest (iOSApplication product)
  Resources/Info.plist       Document types so .ipa can be opened into the app
  App/TestAppsApp.swift      @main entry
  Models/                    ContainerApp, AppVersion, AppMetadata, CompatibilityReport
  Services/                  IPAImporter, IPAParser, IconExtractor, MiniZip, MachO,
                             AppLibraryManager, AppDataManager, CompatibilityChecker,
                             DiagnosticLogger
  Runtime/                   AppRuntime (protocol), RuntimeManager, InspectionRuntime
  Storage/                   ContainerStorage, PersistenceManager
  UI/                        HomeScreenView, AppDetailsView, AppLibraryView,
                             ImportView, LaunchResultView, SettingsView,
                             DebugConsoleView, RootView, Components/
```

Only `Foundation`, `SwiftUI`, `UIKit`, `Compression`, and
`UniformTypeIdentifiers` are used — all available to a Swift Playgrounds app on
iPadOS 16+.

---

## Safety

- Imported apps are **not** isolated from each other the way independently
  installed iOS apps are; isolation here is best-effort inside this one
  container's sandbox. **Only import apps you trust** (ideally only ones you
  build yourself).
- Everything stays on device. **Nothing is uploaded.**
- This app does not defeat Apple's signing or security model, and does not try to
  bypass DRM, authentication, or paid-app protections. Where iOS prevents an
  operation, it is reported, not worked around.
